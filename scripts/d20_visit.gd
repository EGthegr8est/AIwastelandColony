extends RefCounted
## One visit to a ruin as a series of rolls, one button press each, built on the d20 module. A "visit" is a plain
## dictionary (it is saved with the party): the ruin's hidden state (safe, trapped, rogue), what stage the visit is
## at, and what has been found so far. step() performs the next roll and moves the visit on; pending() says what the
## player is about to do (who rolls, the check, its DC, the modifier broken into parts, and the buttons) so the
## panel can show it before the press. Nothing here touches game state: the party's survivors are passed in, and a
## roll that hurts one marks "injury" on it.
##
## The stages, in the order a visit can reach them:
##   strike   a scouting party's attack on a building: one combat check against the building's DC, repeatable until it falls
##   site     a point of interest: one check against the site's DC, whose tier picks that site's outcome (see SITES in
##            d20_data.gd); an outcome may hurt someone, poison the party, force a fight, or hand the colony a reward
##   event    a plain d20 for what the ruin holds (a safe ruin never rolls a hazard: those rows are rerolled)
##   cache    a cache check; a CRITICAL_SUCCESS may offer "deeper"
##   trap     a trapped ruin's trap check; then the ruin is searched like a safe one
##   ambush   a rogue-held ruin's ambush check (or the noise of a collapsed cache); it leads to a fight
##   choice   an ambush spotted in time: fight or slip away
##   fight    a combat check against the enemy's DC (from its strength)
##   deeper   offered after a CRITICAL_SUCCESS on a cache: search again at a higher DC, or head home
##   done     nothing left to roll
## Dice are rolled in this order, so a test can force them: the event d20 (a reroll each time a hazard row comes
## up), then for a cache the resource d20; each check's d20 (a Lucky reroll takes a second); an enemy's strength
## when it appears (a site's fight has a fixed one); loot resource d20s and package dice; a fatal fumble d20.

const Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")

const EVENT_NAMES := {"nothing": "nothing of note", "minor_find": "a small find", "cache": "a pre-war cache"}
const CHECK_NAMES := {"cache": "Cache check", "trap": "Trap check", "ambush": "Ambush check", "combat": "Fight", "site": "Site check"}


# ---------------------------------------------------------------- the situation

## The multiplier a scout's traits put on one situational penalty (1 if none does, 0 to ignore it).
static func situation_mult(scout: Dictionary, key: String) -> float:
	var mult := 1.0
	for id in scout.traits:
		mult *= float(Data.TRAITS[id].get("situation", {}).get(key, 1.0))
	return mult


## A fight's DC from the enemy's strength.
static func enemy_dc(strength: int) -> int:
	var rule: Dictionary = Data.ENEMY_DC
	return clampi(rule.base + rule.per_strength * strength, rule.min, rule.max)


## A new enemy's strength, from the dice.
static func enemy_strength(dice) -> int:
	var span: Array = Data.ENEMY_STRENGTH
	return span[0] + int(dice.roll("1d%d" % (span[1] - span[0] + 1))) - 1


## The situational parts for one scout and one kind of check: [{"label", "value"}]. They come from the site's
## radiation (after the vehicle's shield), the scout's own sickness, hunger, injuries, and, in a fight, the enemy's
## strength against the party's. `ctx` is {"radiation", "party_strength", "enemy_strength"}.
static func situation_parts(scout: Dictionary, ctx: Dictionary, check: String) -> Array:
	var parts := []
	var rad: float = ctx.get("radiation", 0.0)
	var rad_mod := 0
	for row in Data.RADIATION_PENALTY:
		if rad >= row[0]:
			rad_mod = row[1]
	if rad_mod != 0:
		parts.append({"label": "radiation (%d R/h)" % roundi(rad), "value": rad_mod})
	var sick := int(scout.get("sick", 0))
	if sick > 0:
		parts.append({"label": ["", "ill", "radiation sick", "critically sick"][sick], "value": Data.SICK_PENALTY[sick]})
	var hunger := int(scout.get("hunger", 0))
	var hunger_mod := 0
	for row in Data.HUNGER_PENALTY:
		if hunger >= row[0]:
			hunger_mod = row[1]
	if hunger_mod != 0:
		parts.append({"label": "starving" if hunger >= 2 else "hungry", "value": hunger_mod})
	if scout.get("hurt", false):
		parts.append({"label": "hurt", "value": Data.HURT_PENALTY})
	var injury: String = scout.get("injury", "none")
	if injury != "none" and Data.SITUATION.has("injury_" + injury):
		parts.append({"label": "%s injury" % injury, "value": Data.SITUATION["injury_" + injury]})
	var from_leader := int(ctx.get("leader", {}).get(check, 0))
	if from_leader != 0:
		parts.append({"label": "leader", "value": from_leader})
	if check == "combat":
		var enemy := int(ctx.get("enemy_strength", 0))
		if enemy > int(ctx.get("party_strength", 0)):
			var value := roundi(Data.SITUATION["outnumbered"] * situation_mult(scout, "outnumbered"))
			if value != 0:
				parts.append({"label": "outnumbered", "value": value})
	return parts


## Every part of a scout's modifier for a check: traits first, then the situation, then `extra` (how the
## ambush went, say).
static func check_parts(scout: Dictionary, check: String, ctx: Dictionary, extra := 0, extra_label := "") -> Array:
	var parts := []
	var trait_mod := D20.mod_for(scout, check)
	if trait_mod != 0 or not scout.traits.is_empty():
		parts.append({"label": "traits", "value": trait_mod})
	parts.append_array(situation_parts(scout, ctx, check))
	if extra != 0:
		parts.append({"label": extra_label if extra_label != "" else "situation", "value": extra})
	return parts


static func parts_total(parts: Array) -> int:
	var total := 0
	for p in parts:
		total += int(p.value)
	return total


## The survivor who should make a check's roll. The party's traits are combined whoever rolls, so what differs is
## each one's condition: the best total modifier (clamped) wins, skipping anyone badly hurt unless everyone is.
## Ties go to the first. -1 if nobody is left.
static func pick_roller(party: Array, check: String, ctx: Dictionary, extra := 0) -> int:
	var best := -1
	var best_mod := -999
	for pass_number in 2:
		for i in party.size():
			var s: Dictionary = party[i]
			if pass_number == 0 and s.get("injury", "none") == "severe":
				continue
			var mod := D20.clamp_mod(parts_total(check_parts(D20.party_scout(party, s), check, ctx, extra)))
			if mod > best_mod:
				best_mod = mod
				best = i
		if best >= 0:
			break
	return best


# ---------------------------------------------------------------- starting and describing a visit

## A new visit to a ruin whose hidden state is "safe", "trapped" or "rogue", or to a "poi", a point of interest, of
## the kind `poi` (a key of SITES). `ctx` is {"radiation", "party_strength"} (and `scale` the loot scale for this
## party). A rogue-held ruin's raider has a strength, rolled now. What a site gives the colony (ground charted, Dustwell's
## trust, recruits) is only recorded here, in "reveal", "reveal_fort", "trust", "colonists" and "troops": the game
## applies it when the party heads home.
static func begin(ruin: String, ctx: Dictionary, scale: float, dice, party := [], poi := "") -> Dictionary:
	var is_site := ruin == "poi" and Data.SITES.has(poi)
	var lead: Dictionary = ctx.get("leader", {})
	var visit := {
		"ruin": ruin, "stage": "site" if is_site else {"safe": "event", "poi": "event", "trapped": "trap", "rogue": "ambush"}[ruin],
		"poi": poi,
		"ctx": {"radiation": float(ctx.get("radiation", 0.0)), "party_strength": int(ctx.get("party_strength", 0)), "leader": lead},
		"scale": scale, "site_dc": int(Data.SITES[poi].dc) if is_site else Data.DC.standard, "hazard_dc": Data.DC.hard,
		"depth": 0, "resource": "", "enemy": 0, "ambush_dc": Data.DC.hard, "ambush_sit": 0, "ambush_kind": "rogue",
		"fight_sit": 0, "fight_bonus": "", "after": "loot",
		"loot": {}, "site_loot": {}, "packages": [], "prisoners": 0, "camp_revealed": false, "wiped": false,
		"reveal": 0, "reveal_fort": false, "trust": 0, "colonists": 0, "troops": 0,
		"strike_dc": 0, "building": "", "cell": [-1, -1], "camp": -1, "destroyed": false, "carried_loss": 0.0,
		"injuries": {}, "outcome": "", "log": [], "last": [], "shown": 0,
		"rerolls": maxi(D20.party_rerolls(party), int(lead.get("min_rerolls", 0))),
	}
	if ruin == "rogue":
		visit["enemy"] = enemy_strength(dice)
	return visit


## A scouting party's attack on the building `building` on tile `cell`, which takes `dc` to destroy: one combat check
## (the party's own traits and condition), then the party goes on or stays. Winning pays the usual package for a won fight
## and the game removes the building when the party presses Continue; see Units.visit_finish.
static func begin_strike(ctx: Dictionary, scale: float, dice, party: Array, cell: Vector2i, building: String, dc: int) -> Dictionary:
	var visit := begin("safe", ctx, scale, dice, party)
	visit["ruin"] = "building"
	visit["stage"] = "strike"
	visit["strike_dc"] = dc
	visit["building"] = building
	visit["cell"] = [cell.x, cell.y]
	return visit


## A scouting party's attack on a raider camp: the same one-roll-a-press attack as on a building, against the DC of the camp's
## strength (what a fight with that strength would be at the ruins), with the party's strength against the camp's counting too.
## A hit scatters the camp; see Units.visit_finish.
static func begin_camp_strike(ctx: Dictionary, scale: float, dice, party: Array, tribe_id: int, strength: int) -> Dictionary:
	var visit := begin("safe", ctx, scale, dice, party)
	visit["ruin"] = "camp"
	visit["stage"] = "strike"
	visit["enemy"] = strength
	visit["strike_dc"] = enemy_dc(strength)
	visit["camp"] = tribe_id
	return visit


## A raider band meeting a party on the road: the ruin-fight rules, rolled at once for the party by its best fighter against the
## band's DC. Injuries land on the survivors as they do at the ruins. What the party carries, who dies and what happens to
## the band is for the caller: {"won", "tier", "d20", "roller", "wiped", "loot", "carried_loss", "log"}.
static func field_fight(ctx: Dictionary, dice, party: Array, strength: int, scale: float) -> Dictionary:
	var visit := begin("safe", ctx, scale, dice, party)
	visit["stage"] = "fight"
	visit["enemy"] = strength
	visit["after"] = "end"
	step(visit, dice, party, "roll")
	var rolled: Dictionary = visit.rolled
	return {"won": rolled.tier == Data.SUCCESS or rolled.tier == Data.CRITICAL_SUCCESS, "tier": rolled.tier, "d20": int(rolled.d20),
		"roller": rolled.roller, "wiped": visit.wiped, "loot": visit.loot, "carried_loss": float(Data.COMBAT[rolled.tier].carried_loss),
		"log": visit.log}


static func _dc_for(visit: Dictionary) -> int:
	match visit.stage:
		"site":
			return visit.site_dc
		"cache":
			return visit.site_dc + Data.SEARCH_DEEPER.dc_step * visit.depth
		"trap":
			return visit.hazard_dc
		"ambush":
			return visit.ambush_dc
		"fight":
			return enemy_dc(visit.enemy)
		"strike":
			return visit.strike_dc
	return 0


static func _check_for(visit: Dictionary) -> String:
	return "combat" if visit.stage in ["fight", "strike"] else str(visit.stage)


static func _extra_for(visit: Dictionary) -> Array:
	if visit.stage == "fight":
		return [visit.fight_sit, "surprised" if visit.fight_sit < 0 else "sprang the ambush"]
	if visit.stage == "ambush":
		return [visit.ambush_sit, "the noise"]
	return [0, ""]


static func _ctx(visit: Dictionary, check: String) -> Dictionary:
	var ctx: Dictionary = visit.ctx.duplicate()
	ctx["enemy_strength"] = visit.enemy if check == "combat" else 0
	return ctx


## What the player faces now: {"stage", "text", "who", "traits", "check", "dc", "mod", "parts", "buttons"}. Each
## button is {"id", "label"}; its id is what step() takes as the choice (or "finish" once the visit is done).
static func pending(visit: Dictionary, party: Array) -> Dictionary:
	var out := {"stage": visit.stage, "text": "", "who": "", "traits": "", "check": "", "dc": 0, "mod": 0, "parts": [], "buttons": []}
	match visit.stage:
		"event":
			out["text"] = "Search the ruins: a plain d20, no modifiers."
			out["buttons"] = [{"id": "roll", "label": "Search the ruins (d20)"}, {"id": "home", "label": "Leave without searching"}]
		"site", "cache", "trap", "ambush", "fight", "strike":
			var check := _check_for(visit)
			var extra := _extra_for(visit)
			var ctx := _ctx(visit, check)
			var dc := _dc_for(visit)
			var idx := pick_roller(party, check, ctx, extra[0])
			var scout: Dictionary = D20.party_scout(party, party[idx], int(visit.rerolls)) if idx >= 0 else {"name": "Nobody", "traits": []}
			var parts := check_parts(scout, check, ctx, extra[0], extra[1])
			var mod := D20.clamp_mod(parts_total(parts))
			out["who"] = scout.name
			out["traits"] = D20.trait_names(scout)
			var check_name: String = "Attack" if visit.stage == "strike" else CHECK_NAMES[check]
			out["check"] = check_name
			out["dc"] = dc
			out["mod"] = mod
			out["parts"] = parts
			out["text"] = "%s rolls. %s, DC %d, %+d" % [scout.name, check_name, dc, mod]
			if visit.stage == "fight" or visit.ruin == "camp":
				out["text"] += " (enemy strength %d)" % visit.enemy
			out["buttons"] = [{"id": "roll", "label": "Roll d20 (%+d vs DC %d)" % [mod, dc]}]
			if visit.stage == "site":
				out["buttons"].append({"id": "home", "label": "Leave without searching"})
			elif visit.stage == "strike":
				out["buttons"].append({"id": "home", "label": "Back off"})
		"choice":
			out["text"] = "Spotted in time. Fight (DC %d) or slip away?" % enemy_dc(visit.enemy)
			out["buttons"] = [{"id": "fight", "label": "Fight"}, {"id": "slip", "label": "Slip away"}]
		"deeper":
			var next_dc: int = visit.site_dc + Data.SEARCH_DEEPER.dc_step * (visit.depth + 1)
			out["text"] = "A rich find. Search deeper at DC %d, or head home with it?" % next_dc
			out["buttons"] = [{"id": "deeper", "label": "Search deeper (DC %d)" % next_dc}, {"id": "home", "label": "Head home"}]
		_:
			out["text"] = _outcome_text(visit)
			out["buttons"] = [{"id": "finish", "label": "Continue" if visit.wiped or visit.ruin in ["building", "camp"] else "Head home"}]
	return out


static func _outcome_text(visit: Dictionary) -> String:
	if visit.ruin == "building":
		if visit.outcome == "wiped":
			return "The party was wiped out."
		if visit.outcome == "left":
			return "You backed off."
		return "The building came down." if visit.destroyed else "The building held."
	if visit.ruin == "camp":
		if visit.outcome == "wiped":
			return "The party was wiped out."
		if visit.outcome == "left":
			return "You backed off."
		return "The camp is scattered." if visit.destroyed else "The camp held."
	if visit.ruin == "poi" and visit.outcome in ["looted", "empty", ""]:
		return "There was nothing here." if visit.outcome == "empty" else "The site is picked clean."
	match visit.outcome:
		"wiped":
			return "The party was wiped out."
		"slipped":
			return "You slipped away. The raider still holds the ruins."
		"lost_fight":
			return "You were driven off. The raider still holds the ruins."
		"driven_off":
			return ("You were driven off: the noise of the ruined cache drew raiders. %s" % _carrying_text(visit)).strip_edges()
		"left":
			return "You left the %s untouched." % ("site" if visit.ruin == "poi" else "ruins")
		"empty":
			return "There was nothing here."
	return "The ruins are stripped. %s" % _carrying_text(visit) if not visit.loot.is_empty() else "The ruins are stripped."


## "The party carries 6 metal and 3 fuel." (what the visit found so far)
static func _carrying_text(visit: Dictionary) -> String:
	var bits := []
	for r in visit.loot:
		if int(visit.loot[r]) > 0:
			bits.append("%d %s" % [int(visit.loot[r]), r])
	return "The party carries %s." % ", ".join(bits) if not bits.is_empty() else ""


# ---------------------------------------------------------------- doing the next roll

## Performs the next roll of the visit. `choice` is the id of the button pressed ("roll", "home", "fight", "slip",
## "deeper"). The lines this step produced are in visit["last"], and appended to visit["log"].
static func step(visit: Dictionary, dice, party: Array, choice := "roll") -> void:
	visit["last"] = []
	visit["shown"] = 0   # the d20 the dice should land on, if this step rolls one
	match visit.stage:
		"site":
			_site(visit, dice, party, choice)
		"event":
			_event(visit, dice, party, choice)
		"cache":
			_cache(visit, dice, party)
		"trap":
			_trap(visit, dice, party)
		"ambush":
			_ambush(visit, dice, party)
		"choice":
			_choice(visit, choice)
		"fight":
			_fight(visit, dice, party)
		"strike":
			_strike(visit, dice, party, choice)
		"deeper":
			_deeper(visit, dice, choice)
	visit["log"].append_array(visit.last)
	if visit.stage == "done" and visit.outcome == "":
		visit["outcome"] = "looted" if not visit.loot.is_empty() or has_rewards(visit) else "empty"


## Did a site's outcome give the colony something besides loot (ground charted, trust, recruits)?
static func has_rewards(visit: Dictionary) -> bool:
	return int(visit.get("reveal", 0)) > 0 or visit.get("reveal_fort", false) or int(visit.get("trust", 0)) > 0 \
		or int(visit.get("colonists", 0)) > 0 or int(visit.get("troops", 0)) > 0


## One roll for the visit's current check: the best survivor rolls, with every modifier part in the log.
static func _roll(visit: Dictionary, dice, party: Array) -> Dictionary:
	var check := _check_for(visit)
	var extra := _extra_for(visit)
	var ctx := _ctx(visit, check)
	var roller: Dictionary = party[pick_roller(party, check, ctx, extra[0])]
	var scout := D20.party_scout(party, roller, int(visit.rerolls))
	var parts := check_parts(scout, check, ctx, extra[0], extra[1])
	var situational := parts_total(parts) - D20.mod_for(scout, check)
	var result := D20.roll_check(dice, scout, check, _dc_for(visit), situational, true, parts)
	visit["rerolls"] = scout.rerolls   # a Lucky reroll, once spent, is spent for the whole party
	visit["shown"] = result.d20
	visit["rolled"] = {"tier": result.tier, "d20": result.d20, "roller": roller.name}
	visit.last.append(result.log)
	return {"result": result, "scout": scout, "roller": roller}


static func _hurt(visit: Dictionary, scout: Dictionary, level: String) -> void:
	if int(visit.ctx.get("leader", {}).get("medic", 0)) > 0:
		level = {"severe": "light", "light": "none"}.get(level, level)   # a Field medic's people are hurt one step less
	if level == "none":
		return
	if Data.INJURY_RANK.find(level) > Data.INJURY_RANK.find(scout.get("injury", "none")):
		scout["injury"] = level
	visit.injuries[scout.name] = scout["injury"]
	visit.last.append("%s is %s." % [scout.name, "badly hurt" if level == "severe" else "hurt"])


static func _add_package(visit: Dictionary, package: Dictionary) -> void:
	var r: String = package.resource
	visit.loot[r] = visit.loot.get(r, 0) + package.amount
	visit.site_loot[r] = visit.site_loot.get(r, 0) + package.amount
	visit.packages.append(package)
	visit.last.append("Found %d %s." % [package.amount, r])


static func _loot_scout(visit: Dictionary, party: Array) -> Dictionary:
	return D20.party_scout(party, party[pick_roller(party, "cache", _ctx(visit, "cache"))], int(visit.rerolls))


static func _event(visit: Dictionary, dice, party: Array, choice: String) -> void:
	if choice == "home":
		visit["stage"] = "done"
		visit["outcome"] = "left"
		visit.last.append("The party leaves the ruins untouched.")
		return
	var roll: int = dice.d20()
	var event := D20.event_for_roll(roll)
	var rerolled := false
	var tries := 0
	while (event == "ambush" or event == "trap") and tries < 50:
		tries += 1
		rerolled = true
		roll = dice.d20()
		event = D20.event_for_roll(roll)
	visit["shown"] = roll
	visit.last.append("Search: d20 %d -> %s%s" % [roll, EVENT_NAMES[event], " (the map says no hazard here: rerolled)" if rerolled else ""])
	match event:
		"nothing":
			visit["stage"] = "done"
			visit["outcome"] = "empty" if visit.loot.is_empty() and not has_rewards(visit) else "looted"
			if not visit.loot.is_empty():
				visit.last.append("Nothing more turns up.")
		"minor_find":
			_add_package(visit, D20.random_package(dice, _loot_scout(visit, party), "small", "", visit.scale))
			visit["stage"] = "done"
		"cache":
			visit["resource"] = D20.resource_for_roll(dice.d20())
			visit.last.append("It holds %s." % visit.resource)
			visit["stage"] = "cache"


static func _cache(visit: Dictionary, dice, party: Array) -> void:
	var rolled := _roll(visit, dice, party)
	var result: Dictionary = rolled.result
	var scout: Dictionary = rolled.scout
	var tier: String = result.tier
	if tier == Data.CRITICAL_FAILURE:
		if visit.depth > 0:
			var lost := _lose_site_loot(visit, Data.SEARCH_DEEPER.collapse_loss)
			visit.last.append("The cache collapses on the deeper search%s." % (": %d lost" % _sum(lost) if not lost.is_empty() else ""))
		else:
			visit.last.append("The cache is ruined.")
		visit.last.append("The noise draws enemies.")
		visit["enemy"] = enemy_strength(dice)
		visit["ambush_dc"] = visit.site_dc
		visit["ambush_sit"] = Data.CACHE.CRITICAL_FAILURE.ambush_situational
		visit["ambush_kind"] = "noise"
		visit["after"] = "end"
		visit["stage"] = "ambush"
		return
	var base: int = {"FAILURE": 0, "SUCCESS": 1}.get(tier, 2)
	var size: String = Data.SIZES[mini(base + int(visit.depth), Data.SIZES.size() - 1)]
	_add_package(visit, D20.roll_package(dice, scout, size, visit.resource, visit.scale))
	if tier == Data.CRITICAL_SUCCESS:
		_add_package(visit, D20.random_package(dice, scout, Data.CACHE.CRITICAL_SUCCESS.extra_package, visit.resource, visit.scale))
		if visit.depth < Data.SEARCH_DEEPER.max_depth:
			visit["stage"] = "deeper"
			return
	visit["stage"] = "done"


## A share of everything found at this site so far is lost (rounded down per resource); returns what was lost.
static func _lose_site_loot(visit: Dictionary, share: float) -> Dictionary:
	var lost := {}
	for r in visit.site_loot.keys():
		var gone := floori(visit.site_loot[r] * share)
		visit.site_loot[r] -= gone
		visit.loot[r] -= gone
		if gone > 0:
			lost[r] = gone
	return lost


## A point of interest: one check against the site's DC, and the tier of the roll picks that site's outcome. The
## effects are done in order; a fight leaves the stage at "fight", anything else ends the visit.
static func _site(visit: Dictionary, dice, party: Array, choice: String) -> void:
	if choice == "home":
		visit["stage"] = "done"
		visit["outcome"] = "left"
		visit.last.append("The party leaves the site untouched.")
		return
	var rolled := _roll(visit, dice, party)
	var outcome: Dictionary = Data.SITES[visit.poi].outcomes[rolled.result.tier]
	visit.last.append("%s." % outcome.name)
	visit["stage"] = "done"
	for effect in outcome["do"]:
		_site_effect(visit, dice, party, rolled, effect)


static func _site_effect(visit: Dictionary, dice, party: Array, rolled: Dictionary, effect: Dictionary) -> void:
	if effect.has("pkg"):
		var resource: String = effect.get("res", "")
		if resource != "":
			_add_package(visit, D20.roll_package(dice, rolled.scout, effect.pkg, resource, visit.scale))
		else:
			var avoid: String = visit.packages[-1].resource if effect.get("other", false) and not visit.packages.is_empty() else ""
			_add_package(visit, D20.random_package(dice, rolled.scout, effect.pkg, avoid, visit.scale))
	elif effect.has("each"):
		for resource in Data.PACKAGES[effect.each]:
			_add_package(visit, D20.roll_package(dice, rolled.scout, effect.each, resource, visit.scale))
	elif effect.has("injury"):
		_hurt(visit, rolled.roller, effect.injury)
	elif effect.has("dose"):
		for s in party:
			s["dose"] = float(s.get("dose", 0.0)) + float(effect.dose)
		visit.last.append("Everyone in the party takes a dose of radiation (%d)." % int(effect.dose))
	elif effect.has("fight"):
		visit["enemy"] = int(effect.fight)
		visit["fight_sit"] = 0
		visit["fight_bonus"] = ""
		visit["ambush_kind"] = "site"
		visit["after"] = "end"
		visit["stage"] = "fight"
		visit.last.append("A fight is forced on you (enemy strength %d)." % int(effect.fight))
	elif effect.has("reveal"):
		visit["reveal"] = maxi(int(visit.reveal), int(effect.reveal))
		visit.last.append("The map within %d tiles is charted." % int(effect.reveal))
	elif effect.has("reveal_fort"):
		visit["reveal_fort"] = true
		visit.last.append("The Rust Kings' fort and the land around it are charted.")
	elif effect.has("trust"):
		visit["trust"] = int(visit.trust) + int(effect.trust)
	elif effect.has("colonists"):
		visit["colonists"] = int(visit.colonists) + int(effect.colonists)
		visit.last.append("%d colonists will follow you home." % int(effect.colonists))
	elif effect.has("troops"):
		visit["troops"] = int(visit.troops) + int(effect.troops)
		visit.last.append("%d troops will follow you home." % int(effect.troops))
	elif effect.has("lose"):
		var lost := _lose_site_loot(visit, float(effect.lose))
		if not lost.is_empty():
			visit.last.append("The find is lost: %d." % _sum(lost))


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


static func _trap(visit: Dictionary, dice, party: Array) -> void:
	var rolled := _roll(visit, dice, party)
	var result: Dictionary = rolled.result
	var scout: Dictionary = rolled.scout
	var row: Dictionary = Data.TRAP[result.tier]
	var injury: String = row.injury
	if injury == "light" and "injury_severe" in result.flags:
		injury = "severe"
	_hurt(visit, rolled.roller, injury)
	if row.package != "":
		_add_package(visit, D20.random_package(dice, scout, row.package, "", visit.scale))
		visit.last.append("The trap is disarmed and stripped.")
	elif injury == "none":
		visit.last.append("The trap is spotted and avoided.")
	visit.last.append("The ruins are open: search them.")
	visit["stage"] = "event"


static func _ambush(visit: Dictionary, dice, party: Array) -> void:
	var rolled := _roll(visit, dice, party)
	var tier: String = rolled.result.tier
	var row: Dictionary = Data.AMBUSH[tier]
	visit["fight_sit"] = row.situational
	visit["fight_bonus"] = row.bonus_package
	if str(row.fight) == "win":
		visit.last.append("You turn the ambush on them: the raiders are beaten.")
		_won_fight(visit, dice, rolled.scout, Data.SUCCESS, true)   # beaten outright: the enemy's small package, the bonus, their camp
		return
	if str(row.fight) == "choice":
		visit.last.append("You spot it in time.")
		visit["stage"] = "choice"
	else:
		visit.last.append("A fight is forced on you.")
		visit["stage"] = "fight"


static func _choice(visit: Dictionary, choice: String) -> void:
	if choice == "fight":
		visit["stage"] = "fight"
		visit.last.append("You take them on.")
	elif choice == "slip":
		visit["stage"] = "done"
		visit["outcome"] = "slipped"
		visit.last.append("You slip away.")


static func _fight(visit: Dictionary, dice, party: Array) -> void:
	var rolled := _roll(visit, dice, party)
	var result: Dictionary = rolled.result
	var scout: Dictionary = rolled.scout
	var tier: String = result.tier
	var row: Dictionary = Data.COMBAT[tier]
	if _combat_toll(visit, dice, rolled, _dc_for(visit)):
		return
	var won := tier == Data.SUCCESS or tier == Data.CRITICAL_SUCCESS
	if won:
		_won_fight(visit, dice, scout, tier)
	else:
		visit["stage"] = "done"
		var rogue_held: bool = visit.ruin == "rogue" and visit.ambush_kind == "rogue"
		visit["outcome"] = "lost_fight" if rogue_held else ("" if visit.ruin == "poi" else "driven_off")   # a site is simply spent
		visit.last.append("You are driven off.")


## What a won fight pays, whether it was fought or the ambush was turned on them: the enemy's package for the tier, the
## ambush's bonus package, the raider taken prisoner at a rogue-held ruin, their camp on a critical, and then the ruins to search.
static func _won_fight(visit: Dictionary, dice, scout: Dictionary, tier: String, reveal := false) -> void:
	var row: Dictionary = Data.COMBAT[tier]
	if row.enemy_package != "":
		var size := D20.size_shifted(scout, "combat", tier, row.enemy_package)
		_add_package(visit, D20.random_package(dice, scout, size, "", visit.scale))
	if visit.fight_bonus != "":
		_add_package(visit, D20.random_package(dice, scout, visit.fight_bonus, "", visit.scale))
		visit["fight_bonus"] = ""
	if visit.ruin == "rogue" and visit.ambush_kind == "rogue":
		visit["prisoners"] += 1
		visit.last.append("The raider is taken prisoner.")
	if row.camp_revealed or reveal:
		visit["camp_revealed"] = true
		visit.last.append("Their camp is revealed.")
	if visit.after == "loot":
		visit.last.append("The ruins are yours to search.")
		visit["stage"] = "event"
	else:
		visit["stage"] = "done"


## The injury a combat-type roll leaves and, against a hard enough DC, the fatal fumble. True if it wiped the party out.
static func _combat_toll(visit: Dictionary, dice, rolled: Dictionary, dc: int) -> bool:
	var tier: String = rolled.result.tier
	if not "no_injury" in rolled.result.flags:
		_hurt(visit, rolled.roller, Data.COMBAT[tier].injury)
	if not D20.fumble_applies("combat", tier, dc):
		return false
	var fumble: int = dice.d20()
	visit.last.append("%s fumbles: d20 %d" % [rolled.scout.name, fumble])
	if fumble > Data.FATAL_FUMBLE.roll_max:
		return false
	visit["wiped"] = true
	visit["stage"] = "done"
	visit["outcome"] = "wiped"
	visit.last.append("The whole party is dead." if Data.FATAL_FUMBLE.scope == "party" else "%s is dead." % rolled.scout.name)
	return true


## A scouting party's attack on a building: one combat check against the building's DC. A hit destroys it (the game
## removes it when the party presses Continue) and pays the usual package for a won fight; a miss leaves it standing,
## and the party can attack again. What a miss costs the party is carried to the game in "carried_loss".
static func _strike(visit: Dictionary, dice, party: Array, choice: String) -> void:
	if choice == "home":
		visit["stage"] = "done"
		visit["outcome"] = "left"
		visit.last.append("The party backs off.")
		return
	var rolled := _roll(visit, dice, party)
	var tier: String = rolled.result.tier
	var row: Dictionary = Data.COMBAT[tier]
	if _combat_toll(visit, dice, rolled, visit.strike_dc):
		return
	visit["stage"] = "done"
	visit["carried_loss"] = row.carried_loss
	var camp: bool = visit.ruin == "camp"
	if tier == Data.SUCCESS or tier == Data.CRITICAL_SUCCESS:
		visit["destroyed"] = true
		visit.last.append("The camp is scattered." if camp else "The building comes down.")
		if camp:
			visit["prisoners"] += 1
			visit.last.append("One of the raiders is taken prisoner.")
		if row.enemy_package != "":
			var size := D20.size_shifted(rolled.scout, "combat", tier, row.enemy_package)
			_add_package(visit, D20.random_package(dice, rolled.scout, size, "", visit.scale))
	else:
		visit.last.append("The camp holds." if camp else "The building holds.")


static func _deeper(visit: Dictionary, dice, choice: String) -> void:
	if choice == "deeper":
		visit["depth"] += 1
		visit["resource"] = D20.resource_for_roll(dice.d20())
		visit.last.append("You search deeper (DC %d). It holds %s." % [_dc_for_cache(visit), visit.resource])
		visit["stage"] = "cache"
	else:
		visit["stage"] = "done"
		visit.last.append("You head home with what you found.")


static func _dc_for_cache(visit: Dictionary) -> int:
	return visit.site_dc + Data.SEARCH_DEEPER.dc_step * visit.depth


# ---------------------------------------------------------------- saving

## A visit read back from JSON has floats where it had whole numbers: put the ints back.
static func normalize(visit: Dictionary) -> Dictionary:
	for k in ["depth", "enemy", "ambush_dc", "ambush_sit", "fight_sit", "prisoners", "site_dc", "hazard_dc", "shown"]:
		visit[k] = int(visit[k])
	for k in ["reveal", "trust", "colonists", "troops"]:   # a visit saved before sites had outcomes lacks these
		visit[k] = int(visit.get(k, 0))
	visit["reveal_fort"] = bool(visit.get("reveal_fort", false))
	visit["strike_dc"] = int(visit.get("strike_dc", 0))   # and these, before scouting parties could attack
	visit["cell"] = (visit.get("cell", [-1, -1]) as Array).map(func(n): return int(n))
	visit["destroyed"] = bool(visit.get("destroyed", false))
	visit["carried_loss"] = float(visit.get("carried_loss", 0.0))
	visit["building"] = str(visit.get("building", ""))
	visit["camp"] = int(visit.get("camp", -1))
	visit["scale"] = float(visit["scale"])
	visit["rerolls"] = int(visit["rerolls"])
	var lead := {}
	for k in visit.ctx.get("leader", {}):
		lead[k] = int(visit.ctx.leader[k])
	visit["ctx"] = {"radiation": float(visit.ctx.radiation), "party_strength": int(visit.ctx.party_strength), "leader": lead}
	for k in ["loot", "site_loot"]:
		var fixed := {}
		for r in visit[k]:
			fixed[r] = int(visit[k][r])
		visit[k] = fixed
	for p in visit.packages:
		p["amount"] = int(p.amount)
		p["rolled"] = int(p.rolled)
	return visit
