extends RefCounted
## The d20 roll system for scavenging and combat. Every check is one d20 plus the scout's trait modifiers
## (and any situational ones, all clamped to -5..+5) against a DC, and the margin gives one of four tiers:
## CRITICAL_FAILURE, FAILURE, SUCCESS or CRITICAL_SUCCESS. Tier-shifts from traits come after, then the
## outcome table for the kind of check decides injuries, lost loot and new loot. All the numbers are in
## d20_data.gd. Nothing here touches the game's state: each function takes the dice (see dice.gd) and returns a
## result dictionary, with a log line for each roll, for the caller to apply and to show.
##
## A "scout" is a dictionary: {"name", "traits" (ids from d20_data.gd TRAITS), "rerolls" (charges left)}. Make
## one with new_scout().
##
## Order the dice are rolled in, so a test can force them: an event roll (scavenge_site) first, then for a cache
## the resource d20, then each check's d20 (a Lucky reroll takes a second one), then any enemy loot resource d20
## and package dice.

const Data = preload("res://scripts/d20_data.gd")

## The permadeath setting (see d20_data.gd). A variable so a game option, or a test, can flip it.
static var permadeath: bool = Data.PERMADEATH
## How much richer every loot package is than the design doc's dice (see d20_data.gd LOOT_SCALE). A variable so a
## test, or a vehicle that hauls more, can use another.
static var loot_scale: float = Data.LOOT_SCALE


# ---------------------------------------------------------------- scouts and modifiers

static func new_scout(scout_name: String, trait_ids: Array) -> Dictionary:
	var charges := 0
	for id in trait_ids:
		charges += int(Data.TRAITS[id].get("reroll_charges_per_expedition", 0))
	return {"name": scout_name, "traits": trait_ids.duplicate(), "rerolls": charges}


## "Sharp-Eyed, Lucky": the names of a scout's traits.
static func trait_names(scout: Dictionary) -> String:
	var names := []
	for id in scout.traits:
		names.append(Data.TRAITS[id].name)
	return ", ".join(names)


## The traits of a party together. Every different trait counts once, however many of the party have it:
## three Magpies are worth no more than one.
static func party_traits(party: Array) -> Array:
	var out := []
	for s in party:
		for id in s.traits:
			if not id in out:
				out.append(id)
	return out


## The rerolls a party has between them: Lucky's charge, once, however many of them are Lucky.
static func party_rerolls(party: Array) -> int:
	var charges := 0
	for id in party_traits(party):
		charges += int(Data.TRAITS[id].get("reroll_charges_per_expedition", 0))
	return charges


## One scout standing for the whole party: the party's combined traits and `rerolls`, with the name and the
## condition (sickness, hunger, injuries) of `roller`, the survivor who makes the roll.
static func party_scout(party: Array, roller: Dictionary, rerolls := 0) -> Dictionary:
	return {"name": roller.name, "traits": party_traits(party), "rerolls": rerolls, "sick": roller.get("sick", 0),
		"hunger": roller.get("hunger", 0), "hurt": roller.get("hurt", false), "injury": roller.get("injury", "none")}


## The sum of a scout's trait modifiers for a kind of check (combat, ambush, trap or cache), before the clamp.
static func mod_for(scout: Dictionary, check: String) -> int:
	var total := 0
	for id in scout.traits:
		var mods: Dictionary = Data.TRAITS[id].mods
		for kind in Data.CHECK_MODS[check]:
			total += int(mods.get(kind, 0))
	return total


static func clamp_mod(mod: int) -> int:
	return clampi(mod, -Data.MOD_CLAMP, Data.MOD_CLAMP)


# ---------------------------------------------------------------- the check

## The tier for a d20 and a total modifier against a DC. A natural 1 or 20 settles it whatever the modifiers.
static func tier_from_roll(d20: int, mod: int, dc: int) -> String:
	if d20 <= Data.NAT_FAIL:
		return Data.CRITICAL_FAILURE
	if d20 >= Data.NAT_CRIT:
		return Data.CRITICAL_SUCCESS
	var margin := d20 + mod - dc
	if margin <= -Data.CRIT_MARGIN:
		return Data.CRITICAL_FAILURE
	if margin < 0:
		return Data.FAILURE
	if margin < Data.CRIT_MARGIN:
		return Data.SUCCESS
	return Data.CRITICAL_SUCCESS


## A trait that softens (or sharpens) a tier moves it once: {"tier", "shifted"}. Never more than one shift.
static func apply_tier_shifts(scout: Dictionary, check: String, tier: String) -> Dictionary:
	for id in scout.traits:
		for shift in Data.TRAITS[id].get("tier_shifts", []):
			if shift["check"] == check and shift["from"] == tier:
				return {"tier": shift["to"], "shifted": true}
	return {"tier": tier, "shifted": false}


## The outcome flags the scout's traits attach to this tier of this check ("no_injury", "injury_severe").
static func flags_for(scout: Dictionary, check: String, tier: String) -> Array:
	var flags := []
	for id in scout.traits:
		for flag in Data.TRAITS[id].get("outcome_flags", []):
			if flag["check"] == check and flag["tier"] == tier:
				flags.append(flag["flag"])
	return flags


## One check: d20 + modifiers against `dc`. `situational` is added to the trait modifiers inside the clamp. A scout
## with a reroll charge (Lucky) rerolls a FAILURE or worse once and keeps the new roll, spending it automatically
## unless `auto_reroll` is false. The result has the d20, the clamped modifier, the total, the raw tier (before any
## shift), the final tier, any outcome flags, and a one-line log.
static func roll_check(dice, scout: Dictionary, check: String, dc: int, situational := 0, auto_reroll := true, parts := []) -> Dictionary:
	var mod := clamp_mod(mod_for(scout, check) + situational)
	var first: int = dice.d20()
	var d20 := first
	var raw := tier_from_roll(d20, mod, dc)
	var rerolled := false
	if auto_reroll and (raw == Data.CRITICAL_FAILURE or raw == Data.FAILURE) and int(scout.get("rerolls", 0)) > 0:
		scout["rerolls"] = int(scout["rerolls"]) - 1
		d20 = dice.d20()
		raw = tier_from_roll(d20, mod, dc)
		rerolled = true
	var shift := apply_tier_shifts(scout, check, raw)
	var tier: String = shift.tier
	var result := {"name": scout.name, "check": check, "d20": d20, "first_d20": first, "mod": mod, "total": d20 + mod, "dc": dc,
		"raw": raw, "tier": tier, "rerolled": rerolled, "shifted": shift.shifted, "flags": flags_for(scout, check, tier), "parts": parts}
	result["log"] = log_line(scout, result)
	return result


## "Mara (Sharp-Eyed) trap: d20 8 +4 = 12 vs DC 11 -> SUCCESS", with the raw tier and the first d20 shown when a
## shift or a reroll changed the result.
static func log_line(scout: Dictionary, r: Dictionary) -> String:
	var who: String = scout.name
	var names := trait_names(scout)
	if names != "":
		who += " (%s)" % names
	var line := "%s %s: d20 %d %+d = %d vs DC %d -> %s" % [who, r.check, r.d20, r.mod, r.total, r.dc, r.tier]
	if r.rerolled:
		line += " (rerolled from %d)" % r.first_d20
	if r.shifted:
		line += " (raw %s)" % r.raw
	if not r.parts.is_empty():
		line += " [%s]" % parts_text(r.parts)
	return line


## "+4 traits, -1 radiation (35 R/h)": the parts a modifier is made of.
static func parts_text(parts: Array) -> String:
	var bits := []
	for p in parts:
		bits.append("%+d %s" % [p.value, p.label])
	return ", ".join(bits)


# ---------------------------------------------------------------- tables

static func _lookup(table: Array, d20: int, key: String) -> String:
	for row in table:
		if d20 >= row["min"] and d20 <= row["max"]:
			return row[key]
	push_error("d20: no row for a roll of %d" % d20)
	return ""


## What a scout runs into at a site (a plain d20): ambush, trap, cache, minor_find or nothing.
static func event_for_roll(d20: int) -> String:
	return _lookup(Data.EVENT_TABLE, d20, "event")


## What a cache, minor find or disarmed trap holds (a plain d20): veg, fuel or gold.
static func resource_for_roll(d20: int) -> String:
	return _lookup(Data.RESOURCE_TABLE, d20, "resource")


# ---------------------------------------------------------------- loot

## A package size bumped up by the scout's traits for this tier of this check (Trigger-Happy), never past large.
static func size_shifted(scout: Dictionary, check: String, tier: String, size: String) -> String:
	var steps := 0
	for id in scout.traits:
		for shift in Data.TRAITS[id].get("loot_size_shift", []):
			if shift["check"] == check and shift["tier"] == tier:
				steps += int(shift["steps"])
	return Data.SIZES[mini(Data.SIZES.find(size) + steps, Data.SIZES.size() - 1)]


## The scout's loot multiplier for a resource: every trait's multiplier for it, and for everything, multiplied
## together and capped.
static func loot_multiplier(scout: Dictionary, resource: String) -> float:
	var mult := 1.0
	for id in scout.traits:
		var table: Dictionary = Data.TRAITS[id].get("loot_mult", {})
		mult *= float(table.get(resource, 1.0)) * float(table.get("all", 1.0))
	return minf(mult, Data.LOOT_MULT_CAP)


## Rolls a package of one size of one resource: its dice, times the loot scale and the scout's multiplier,
## rounded to the nearest unit and never below 1 (a package is only rolled when the tier grants loot). `scale` is
## the loot scale (a negative one means the standing `loot_scale`).
static func roll_package(dice, scout: Dictionary, size: String, resource: String, scale := -1.0) -> Dictionary:
	var rolled: int = dice.roll(Data.PACKAGES[size][resource])
	var mult := loot_multiplier(scout, resource)
	var factor := loot_scale if scale < 0.0 else scale
	return {"size": size, "resource": resource, "rolled": rolled, "mult": mult, "amount": maxi(roundi(rolled * factor * mult), 1)}


## A package of a resource picked by the resource roll. `avoid` rerolls the resource until it differs from it.
static func random_package(dice, scout: Dictionary, size: String, avoid := "", scale := -1.0) -> Dictionary:
	var resource := resource_for_roll(dice.d20())
	var tries := 0
	while resource == avoid and tries < 100:
		resource = resource_for_roll(dice.d20())
		tries += 1
	return roll_package(dice, scout, size, resource, scale)


## Splits carried loot into what's lost (a share of each resource, rounded down) and what's kept.
static func lose_share(carried: Dictionary, share: float) -> Dictionary:
	var lost := {}
	var kept := {}
	for k in carried:
		var gone := floori(carried[k] * share)
		if gone > 0:
			lost[k] = gone
		kept[k] = carried[k] - gone
	return {"lost": lost, "kept": kept}


# ---------------------------------------------------------------- outcomes

## An empty outcome. "steps" holds the outcomes this one set off (an ambush's fight, a cache's ambush).
static func _blank(kind: String) -> Dictionary:
	return {"kind": kind, "check": {}, "tier": "", "injury": "none", "lost": {}, "loot": {}, "packages": [], "camp_revealed": false,
		"died": false, "wiped": false, "choice": false, "steps": [], "log": []}


static func _add_to(into: Dictionary, from: Dictionary) -> void:
	for k in from:
		into[k] = into.get(k, 0) + from[k]


static func _add_package(out: Dictionary, package: Dictionary) -> void:
	out["packages"].append(package)
	out["loot"][package.resource] = out["loot"].get(package.resource, 0) + package.amount
	out["log"].append("Found %d %s." % [package.amount, package.resource])


## Folds an outcome that this one set off into it: the worse injury, the loot and losses added up, the log joined.
static func _absorb(out: Dictionary, step: Dictionary) -> void:
	out["steps"].append(step)
	if Data.INJURY_RANK.find(step.injury) > Data.INJURY_RANK.find(out.injury):
		out["injury"] = step.injury
	_add_to(out["lost"], step.lost)
	_add_to(out["loot"], step.loot)
	out["packages"].append_array(step.packages)
	out["camp_revealed"] = out.camp_revealed or step.camp_revealed
	out["died"] = out.died or step.died
	out["wiped"] = out.wiped or step.wiped
	out["log"].append_array(step.log)


## What's left of `carried` once `lost` is taken off.
static func _carried_after(carried: Dictionary, lost: Dictionary) -> Dictionary:
	var left := carried.duplicate()
	for k in lost:
		left[k] = maxi(left.get(k, 0) - lost[k], 0)
	return left


## A fight: one combat check against the enemy's DC. Injury and carried-loot loss by tier, enemy loot for a win
## (one size bigger for Trigger-Happy on a CRITICAL_SUCCESS), the enemy camp revealed on a CRITICAL_SUCCESS.
static func resolve_combat(dice, scout: Dictionary, dc: int, situational := 0, carried := {}) -> Dictionary:
	var out := _blank("combat")
	var check := roll_check(dice, scout, "combat", dc, situational)
	var row: Dictionary = Data.COMBAT[check.tier]
	out["check"] = check
	out["tier"] = check.tier
	out["log"].append(check.log)
	out["injury"] = "none" if "no_injury" in check.flags else row.injury
	out["lost"] = lose_share(carried, row.carried_loss).lost
	if row.enemy_package != "":
		_add_package(out, random_package(dice, scout, size_shifted(scout, "combat", check.tier, row.enemy_package)))
	out["camp_revealed"] = row.camp_revealed
	if fumble_applies("combat", check.tier, dc):
		var fumble: int = dice.d20()
		out["log"].append("%s fumbles: d20 %d" % [scout.name, fumble])
		if fumble <= Data.FATAL_FUMBLE.roll_max:
			out["died"] = true
			out["wiped"] = Data.FATAL_FUMBLE.scope == "party"
			out["log"].append("The whole party is dead." if out.wiped else "%s is dead." % scout.name)
	return out


## Does a result of this tier, on this kind of check against this DC, call for the fatal fumble roll?
static func fumble_applies(check: String, tier: String, dc: int) -> bool:
	var rule: Dictionary = Data.FATAL_FUMBLE
	return permadeath and check == rule.check and tier == rule.tier and dc >= rule.min_dc


## A trap: injury and lost loot on a failure, a clean escape on a SUCCESS, a small package when disarmed.
static func resolve_trap(dice, scout: Dictionary, dc: int, carried := {}, situational := 0) -> Dictionary:
	var out := _blank("trap")
	var check := roll_check(dice, scout, "trap", dc, situational)
	var row: Dictionary = Data.TRAP[check.tier]
	out["check"] = check
	out["tier"] = check.tier
	out["log"].append(check.log)
	var injury: String = row.injury
	if injury == "light" and "injury_severe" in check.flags:
		injury = "severe"
	out["injury"] = injury
	out["lost"] = lose_share(carried, row.carried_loss).lost
	if row.package != "":
		_add_package(out, random_package(dice, scout, row.package))
	return out


## An ambush check (spotting it), then the forced fight it leads to. On a SUCCESS the scout may fight or slip
## away: `on_success` is "fight", "slip", or "ask" (the default) which leaves "choice" true and no fight rolled.
## `enemy_dc` is the DC of the fight; it has no default because the design doc doesn't set one.
static func resolve_ambush(dice, scout: Dictionary, dc: int, enemy_dc: int, carried := {}, situational := 0, on_success := "ask") -> Dictionary:
	var out := _blank("ambush")
	var check := roll_check(dice, scout, "ambush", dc, situational)
	var row: Dictionary = Data.AMBUSH[check.tier]
	out["check"] = check
	out["tier"] = check.tier
	out["log"].append(check.log)
	out["lost"] = lose_share(carried, row.carried_loss).lost
	var fights: bool = row.fight is bool and row.fight
	if str(row.fight) == "choice":
		if on_success == "fight":
			fights = true
		elif on_success == "ask":
			out["choice"] = true
	if fights:
		var fight := resolve_combat(dice, scout, enemy_dc, row.situational, _carried_after(carried, out.lost))
		_absorb(out, fight)
		if row.bonus_package != "" and (fight.tier == Data.SUCCESS or fight.tier == Data.CRITICAL_SUCCESS):
			_add_package(out, random_package(dice, scout, row.bonus_package))
	return out


## A pre-war cache. The resource roll is made when it is found, then the cache check picks the package size. A
## CRITICAL_FAILURE ruins it and the noise draws an ambush check at -2.
static func resolve_cache(dice, scout: Dictionary, dc: int, enemy_dc: int, carried := {}) -> Dictionary:
	var out := _blank("cache")
	var resource := resource_for_roll(dice.d20())
	var check := roll_check(dice, scout, "cache", dc)
	var row: Dictionary = Data.CACHE[check.tier]
	out["check"] = check
	out["tier"] = check.tier
	out["log"].append(check.log)
	if row.has("ambush_situational"):
		out["log"].append("The cache is ruined, and the noise draws enemies.")
		_absorb(out, resolve_ambush(dice, scout, dc, enemy_dc, carried, row.ambush_situational))
		return out
	_add_package(out, roll_package(dice, scout, row.package, resource))
	if row.extra_package != "":
		_add_package(out, random_package(dice, scout, row.extra_package, resource))
	return out


## One visit to a site: the event roll, then whatever it is. `site_dc` is the DC of the ambush, trap and cache
## checks (the table calls a standard one 11), `enemy_dc` of any fight that follows.
static func scavenge_site(dice, scout: Dictionary, site_dc: int, enemy_dc: int, carried := {}, on_success := "ask") -> Dictionary:
	var roll: int = dice.d20()
	var event := event_for_roll(roll)
	var out: Dictionary
	match event:
		"ambush":
			out = resolve_ambush(dice, scout, site_dc, enemy_dc, carried, 0, on_success)
		"trap":
			out = resolve_trap(dice, scout, site_dc, carried)
		"cache":
			out = resolve_cache(dice, scout, site_dc, enemy_dc, carried)
		"minor_find":
			out = _blank("minor_find")
			_add_package(out, random_package(dice, scout, "small"))
		_:
			out = _blank("nothing")
			out["log"].append("Nothing of note.")
	out["event"] = event
	out["event_roll"] = roll
	out["log"].push_front("%s scavenges: d20 %d -> %s" % [scout.name, roll, event])
	out["carried"] = _carried_after(carried, out.lost)
	return out
