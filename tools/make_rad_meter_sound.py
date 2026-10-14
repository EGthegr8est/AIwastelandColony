"""
Dosimeter sound for the rad meter button, timed to the sprite animation.

Reads the frame timings and needle values from make_rad_meter.py, so if you change
the animation and re-run both scripts the sound follows it.

    python3 make_rad_meter_sound.py [out_dir]

Outputs:
    rad_meter_on.wav   power-on (press, 3 knob detents, wind-up, red-band alarm)
                       followed by the idle loop. A loop point is embedded so
                       Godot plays the intro once, then repeats the idle hum gaplessly.
    rad_meter_off.wav  power-off (detents, counts stop, drone winds down)

Layers:
    drone   two detuned pulse waves, crushed to 5 bits, that wind up in pitch steps
    whine   faint inverter whine that sweeps up on power-on
    tone    ratemeter voice whose pitch follows the needle
    counts  Geiger ticks + digital chirps; rate rises with the needle
    alarm   triple beep while the needle sits in the red check band
"""
import os
import struct
import sys

import numpy as np
from scipy.signal import butter, lfilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_rad_meter import ANIMS  # noqa: E402

SR = 44100
rng = np.random.default_rng(715)

INTRO = sum(f["ms"] for f in ANIMS["power_on"]) / 1000.0
LOOP = sum(f["ms"] for f in ANIMS["on"]) / 1000.0
OFF = sum(f["ms"] for f in ANIMS["power_off"]) / 1000.0


def n(t):
    return int(round(t * SR))


def loopsafe(freq):
    """Nearest frequency with a whole number of cycles in one idle loop."""
    return round(freq * LOOP) / LOOP


# ------------------------------------------------------------ timeline helpers
def track(frames, t0=0.0):
    out, t = [], t0
    for f in frames:
        out.append((t, f["ms"] / 1000.0, f))
        t += f["ms"] / 1000.0
    return out


def per_sample(segs, total_n, key, default):
    arr = np.full(total_n, default, dtype=object if key == "knob_name" else float)
    for t, d, f in segs:
        arr[n(t):n(t + d)] = f[key]
    return arr


def one_pole(x, tau):
    a = np.exp(-1.0 / (tau * SR))
    return lfilter([1 - a], [1, -a], x)


def crush(x, bits):
    q = 2 ** (bits - 1)
    return np.round(x * q) / q


def stepped(t, t0, t1, a, b, steps):
    """Digital stair-step ramp from a to b between t0 and t1."""
    u = np.clip((t - t0) / (t1 - t0), 0, 1)
    u = np.floor(u * steps) / steps
    return a + (b - a) * u


# ------------------------------------------------------------ one-shot sounds
def add(buf, t, snd, gain=1.0):
    i = n(t)
    j = min(len(buf), i + len(snd))
    if i < len(buf):
        buf[i:j] += snd[: j - i] * gain


def env(length_s, tau):
    k = np.arange(n(length_s)) / SR
    return np.exp(-k / tau)


def square(freq, length_s, duty=0.5):
    k = np.arange(n(length_s)) / SR
    ph = (k * freq) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


B_CLICK = butter(2, [1800, 6000], btype="band", fs=SR)
B_LOW = butter(2, 1200, btype="low", fs=SR)


def thump():
    k = np.arange(n(0.09)) / SR
    f = 55 + 65 * np.exp(-k / 0.02)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-k / 0.03)
    hit = lfilter(*B_LOW, rng.standard_normal(len(k))) * np.exp(-k / 0.004)
    return 0.55 * body + 0.35 * hit


def detent(blip_hz=None, sweep_to=None):
    click = lfilter(*B_CLICK, rng.standard_normal(n(0.012))) * env(0.012, 0.0018)
    k = np.arange(n(0.03)) / SR
    knock = np.sin(2 * np.pi * 240 * k) * np.exp(-k / 0.008)
    out = np.zeros(n(0.14))
    out[: len(click)] += 0.9 * click
    out[: len(knock)] += 0.25 * knock
    if blip_hz:
        if sweep_to:       # power-down chirp
            L = 0.10
            kk = np.arange(n(L)) / SR
            f = blip_hz * (sweep_to / blip_hz) ** (kk / L)
            ph = np.cumsum(f) / SR % 1.0
            b = np.where(ph < 0.5, 1.0, -1.0) * np.exp(-kk / 0.05)
        else:
            b = square(blip_hz, 0.028) * env(0.028, 0.012)
        b = crush(b, 4)
        s = n(0.004)
        out[s:s + len(b)] += 0.16 * b
    return out


def count():
    """One detection: a dry tick plus a short digital chirp."""
    L = n(0.006)
    tick = np.diff(rng.standard_normal(42), prepend=0) * np.exp(-np.arange(42) / 9)
    fc = 3100 * (1 + rng.normal(0, 0.04))
    chirp = crush(square(fc, 0.006) * env(0.006, 0.0016), 3)
    out = np.zeros(L)
    out[:42] += 0.55 * tick * rng.uniform(0.6, 1.0)
    out += 0.22 * chirp
    return out


def alarm_beep(length_s):
    k = np.arange(n(length_s)) / SR
    a = np.minimum(1, k / 0.002) * np.minimum(1, (length_s - k) / 0.004)
    return crush(square(2700, length_s) * a, 4)


def crackle(length_s, density):
    out = np.zeros(n(length_s))
    idx = rng.choice(len(out), size=int(len(out) * density), replace=False)
    out[idx] = rng.uniform(-1, 1, size=len(idx))
    return lfilter(*B_CLICK, out) * 3


# ------------------------------------------------------------ continuous layers
F_A, F_B = loopsafe(55.0), loopsafe(56.0)   # detuned pair -> slow beating
F_TREM = loopsafe(6.8)
F_WHINE = loopsafe(7000.0)


def drone(t, pitch, amp):
    out = np.zeros_like(t)
    for f, g, duty in ((F_A, 1.0, 0.30), (F_B, 0.7, 0.42)):
        ph = np.cumsum(f * pitch / SR) % 1.0
        out += g * np.where(ph < duty, 1.0, -1.0)
    out = lfilter(*butter(2, 650, btype="low", fs=SR), out)
    out = crush(out / 1.7, 5)
    trem = 1 + 0.12 * np.sin(2 * np.pi * F_TREM * t)
    return out * trem * amp


def whine(freq, amp):
    return np.sin(2 * np.pi * np.cumsum(freq / SR)) * amp


def needle_tone(v, gate, loop_from=None, loop_to=None):
    f = one_pole(260 + 95 * np.maximum(v, 0), 0.012)
    inc = f / SR
    if loop_from is not None:   # make the loop hold a whole number of cycles
        seg = inc[loop_from:loop_to]
        inc[loop_from:loop_to] = seg * (round(seg.sum()) / seg.sum())
    ph = np.cumsum(inc) % 1.0
    tri = 4 * np.abs(ph - 0.5) - 1
    return crush(tri, 4) * gate


def counts_layer(segs, total_n, keep_clear):
    out = np.zeros(total_n)
    for t, d, f in segs:
        if f["knob_name"] not in ("x100", "x10"):
            continue
        lam = 2.2 * np.exp(1.1 * max(f["v"], 0))
        for _ in range(rng.poisson(lam * d)):
            tt = t + rng.uniform(0, d)
            if any(a <= tt < b for a, b in keep_clear):
                continue
            add(out, tt, count())
    return out


# ------------------------------------------------------------ the two files
def render_on():
    total = n(INTRO) + n(LOOP)
    t = np.arange(total) / SR
    segs = track(ANIMS["power_on"]) + track(ANIMS["on"], INTRO)
    v = per_sample(segs, total, "v", 0.0)
    det = [s for s in segs[:4]]                # press + three detents

    pitch = np.where(t < 0.06, 0.0, stepped(t, 0.06, 0.50, 0.40, 1.0, 8))
    d_amp = np.clip((t - 0.06) / 0.30, 0, 1)
    w_freq = np.where(t < 0.6, stepped(t, 0.06, 0.6, 2400, F_WHINE, 12), F_WHINE)
    w_amp = 0.006 * np.clip((t - 0.06) / 0.4, 0, 1)
    gate = np.clip((t - 0.13) / 0.08, 0, 1)

    guard = 0.008
    keep_clear = [(INTRO - guard, INTRO), (INTRO + LOOP - guard, INTRO + LOOP)]
    mix = 0.17 * drone(t, pitch, d_amp)
    mix += whine(w_freq, w_amp)
    mix += 0.045 * needle_tone(v, gate, n(INTRO), total)
    mix += counts_layer(segs, total, keep_clear)

    add(mix, det[0][0], thump())
    for (tt, _, _), hz in zip(det[1:], (988, 1319, 1760)):
        add(mix, tt, detent(hz))
    red = [s for s in segs if s[2]["v"] >= 3.8 and s[0] < INTRO]
    if red:
        r0 = red[0][0]
        for i, L in enumerate((0.04, 0.04, 0.05)):
            add(mix, r0 + i * 0.06, alarm_beep(L), 0.17)
    return mix, n(INTRO)


def render_off():
    segs = track(ANIMS["power_off"])
    tail = 0.12
    total = n(OFF + tail)
    t = np.arange(total) / SR
    v = per_sample(segs, total, "v", segs[-1][2]["v"])

    pitch = stepped(t, 0.06, 0.42, 1.0, 0.35, 7)
    d_amp = 1 - np.clip((t - 0.13) / 0.32, 0, 1)
    w_freq = stepped(t, 0.0, 0.30, F_WHINE, 2500, 8)
    w_amp = 0.006 * (1 - np.clip(t / 0.30, 0, 1))
    gate = 1 - np.clip((t - 0.13) / 0.09, 0, 1)

    mix = 0.17 * drone(t, pitch, d_amp)
    mix += whine(w_freq, w_amp)
    mix += 0.045 * needle_tone(v, gate)
    mix += counts_layer(segs, total, [])

    add(mix, segs[0][0], thump())
    add(mix, segs[1][0], detent(1760))
    add(mix, segs[2][0], detent(1319))
    add(mix, segs[3][0], detent(990, sweep_to=180))
    flicker = [s for s in segs[4:] if s[2]["glow"] > 0]
    if flicker:
        add(mix, flicker[0][0], crackle(0.025, 0.02), 0.25)
    fade = np.ones(total)
    fade[-n(0.03):] = np.linspace(1, 0, n(0.03))
    return mix * fade


# ------------------------------------------------------------ output
def master(x):
    x = np.tanh(x * 1.3) / np.tanh(1.3)
    x[1::2] = x[0::2][: len(x[1::2])]          # sample-and-hold: 22 kHz grit
    return x


def write_wav(path, x, loop=None):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    data = pcm.tobytes()
    chunks = [b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16),
              b"data" + struct.pack("<I", len(data)) + data]
    if loop:
        start, end = loop      # end is exclusive, which is how Godot reads it
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, start, end, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    body = b"WAVE" + b"".join(chunks)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def main(out_dir):
    on, loop_start = render_on()
    off = render_off()
    on, off = master(on), master(off)
    peak = max(np.abs(on).max(), np.abs(off).max())
    on, off = on * 0.89 / peak, off * 0.89 / peak
    loop_end = len(on)
    # one extra sample = first loop sample, for tools that read the loop end as inclusive
    on = np.append(on, on[loop_start])
    write_wav(os.path.join(out_dir, "rad_meter_on.wav"), on, (loop_start, loop_end))
    write_wav(os.path.join(out_dir, "rad_meter_off.wav"), off)
    print(f"on: intro {INTRO:.3f}s + loop {LOOP:.3f}s (samples {loop_start}-{loop_end}); "
          f"off: {len(off) / SR:.3f}s")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
