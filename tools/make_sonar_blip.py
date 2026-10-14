"""
Makes audio/sonar_tablet_blip.wav: the simple blip the sonar tablet button plays when it is clicked.

A short square-wave chirp (700 Hz sliding up to 1400 Hz over 55 ms), quickly fading out, with 4-bit volume steps and a 22.05 kHz sample rate so it sits with the
8-bit dice sounds (d20_dice/audio). Plain Python, no packages needed:

    python tools/make_sonar_blip.py [out_dir]      (out_dir defaults to ../audio)
"""
import math
import os
import struct
import sys
import wave

RATE = 22050
LENGTH = 0.09          # seconds in all
SWEEP = 0.055          # seconds the pitch takes to climb
F_FROM, F_TO = 700.0, 1400.0
LEVEL = 0.55           # peak volume, 0 to 1
STEPS = 15             # 4-bit volume steps


def blip() -> list:
    n = int(RATE * LENGTH)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        climb = min(t / SWEEP, 1.0)
        freq = F_FROM * (F_TO / F_FROM) ** climb          # a rising whistle, an octave up
        phase = (phase + freq / RATE) % 1.0
        wave_ = 1.0 if phase < 0.5 else -1.0               # square wave
        fade = max(0.0, 1.0 - (t / LENGTH)) ** 1.6         # fast fade, so it is a tap and not a beep
        attack = min(1.0, t / 0.002)                       # 2 ms in, so it does not click
        level = round(fade * attack * STEPS) / STEPS       # 4-bit volume steps
        out.append(wave_ * level * LEVEL)
    return out


def main(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "sonar_tablet_blip.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in blip()))
    print("wrote", path, "(%d ms)" % round(LENGTH * 1000))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio"))
