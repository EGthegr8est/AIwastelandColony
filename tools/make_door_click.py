"""
Makes audio/end_season_click.wav: the simple door click the END SEASON window plays once its sunset or dawn has finished.

Two quick knocks like a latch going home: a small high "tick", then, 45 ms later, a lower, duller "clack" with a little wooden thump under it. Each is a burst of noise that dies in a few
milliseconds plus a short tone, in 4-bit volume steps at 22.05 kHz so it sits with the 8-bit dice sounds (d20_dice/audio) and the tablet's blip. Plain Python, no packages needed:

    python tools/make_door_click.py [out_dir]      (out_dir defaults to ../audio)
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
LENGTH = 0.14          # seconds in all
LEVEL = 0.6            # peak volume, 0 to 1
STEPS = 15             # 4-bit volume steps


def knock(out: list, start: float, noise: float, noise_tau: float, tone_hz: float, tone_tau: float, thump_hz: float, thump_tau: float, gain: float, rnd: random.Random) -> None:
    """Adds one knock at `start` seconds: decaying noise, a short square-wave tone and (if thump_hz > 0) a low sine thump."""
    first = int(start * RATE)
    phase = 0.0
    for i in range(first, len(out)):
        t = (i - first) / RATE
        if t > 0.08:
            break
        s = noise * rnd.uniform(-1.0, 1.0) * math.exp(-t / noise_tau)
        phase = (phase + tone_hz / RATE) % 1.0
        s += 0.35 * (1.0 if phase < 0.5 else -1.0) * math.exp(-t / tone_tau)
        if thump_hz > 0:
            s += 0.8 * math.sin(2 * math.pi * thump_hz * t) * math.exp(-t / thump_tau)
        out[i] += s * gain * min(1.0, t / 0.0005)   # half a millisecond in, so the first sample does not jump


def click() -> list:
    rnd = random.Random(7)   # the same noise every time the file is made
    out = [0.0] * int(RATE * LENGTH)
    knock(out, 0.0, 0.9, 0.0025, 2600.0, 0.004, 0.0, 0.0, 0.55, rnd)       # the tick: bright and tiny
    knock(out, 0.045, 0.7, 0.005, 900.0, 0.009, 170.0, 0.022, 0.85, rnd)   # the clack: duller, with the thump
    peak = max(abs(s) for s in out) or 1.0
    return [round(s / peak * STEPS) / STEPS * LEVEL for s in out]          # 4-bit volume steps


def main(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "end_season_click.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in click()))
    print("wrote", path, "(%d ms)" % round(LENGTH * 1000))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio"))
