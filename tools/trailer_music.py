"""Makes the trailer's drum track (original, synthesized): 128 BPM kick / clap / hi-hat,
with a little build-up and a hit + ring-out for the title. Writes a 16-bit WAV.
    python tools/trailer_music.py out.wav seconds title_at_seconds
The game's guitar loop is sped up to the same tempo and mixed in by ffmpeg (see README).
Needs: pip install numpy
"""
import sys
import wave
import numpy as np

RATE = 44100
BPM = 128.0
out = sys.argv[1] if len(sys.argv) > 1 else "drums.wav"
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 25.0
title_at = float(sys.argv[3]) if len(sys.argv) > 3 else seconds - 4.0
rng = np.random.default_rng(7)
n = int(RATE * seconds)
mix = np.zeros(n, dtype=np.float32)


def add(sound, at):
    i = int(at * RATE)
    if i >= n:
        return
    m = min(len(sound), n - i)
    mix[i:i + m] += sound[:m]


def kick():
    t = np.arange(int(RATE * 0.35)) / RATE
    freq = 50 + 110 * np.exp(-t * 30)
    phase = np.cumsum(freq) / RATE
    return (np.sin(2 * np.pi * phase) * np.exp(-t * 9) * 0.9).astype(np.float32)


def clap():
    t = np.arange(int(RATE * 0.25)) / RATE
    noise = rng.uniform(-1, 1, len(t))
    env = np.exp(-t * 18) + 0.6 * np.exp(-((t - 0.012) * 120) ** 2)
    hp = np.diff(noise, prepend=0)   # brighter
    return (hp * env * 0.35).astype(np.float32)


def hat(open_=False):
    t = np.arange(int(RATE * (0.18 if open_ else 0.05))) / RATE
    noise = np.diff(rng.uniform(-1, 1, len(t)), prepend=0)
    return (noise * np.exp(-t * (14 if open_ else 70)) * 0.16).astype(np.float32)


def boom():
    t = np.arange(int(RATE * 2.5)) / RATE
    freq = 40 + 60 * np.exp(-t * 6)
    phase = np.cumsum(freq) / RATE
    body = np.sin(2 * np.pi * phase) * np.exp(-t * 1.6)
    noise = rng.uniform(-1, 1, len(t)) * np.exp(-t * 5) * 0.25
    return ((body + noise) * 0.9).astype(np.float32)


beat = 60.0 / BPM
K, C, H, HO = kick(), clap(), hat(), hat(True)
b = 0
while b * beat < title_at - 0.01:
    at = b * beat
    bar_pos = b % 4
    add(K, at)
    if bar_pos in (1, 3):
        add(C, at)
    add(H, at + beat * 0.5)
    if b % 8 == 7:
        add(HO, at + beat * 0.5)
    # build-up: 16th-note claps in the last bar before the title
    if title_at - at <= beat * 4:
        for k in range(4):
            add(C * (0.4 + 0.15 * k), at + beat * k / 4)
    b += 1
add(boom(), title_at)
add(K, title_at)
peak = np.max(np.abs(mix)) or 1.0
mix = mix / peak * 0.9
fade = int(RATE * 0.6)
mix[-fade:] *= np.linspace(1, 0, fade)
data = (mix * 32767).astype(np.int16)
with wave.open(out, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(data.tobytes())
print("drums saved:", out, "%.1f s, title hit at %.2f s" % (seconds, title_at))
