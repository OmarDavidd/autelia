"""Synthesizes the game's sound effects as 16-bit mono WAV files.

Pure standard library, deterministic (fixed noise seed), so the sounds are original,
license-free and can be regenerated after tweaking a recipe:

    python3 tools/sfx/generate_sfx.py

Output: assets/audio/*.wav
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "audio"
_noise = random.Random(7)


def sweep(start_hz, end_hz, seconds, shape="sine", volume=0.5, decay=6.0):
    """A tone gliding from start_hz to end_hz with an exponential fade-out."""
    samples = []
    phase = 0.0
    count = int(RATE * seconds)
    for i in range(count):
        t = i / count
        freq = start_hz + (end_hz - start_hz) * t
        phase += 2 * math.pi * freq / RATE
        if shape == "square":
            value = 1.0 if math.sin(phase) >= 0 else -1.0
        elif shape == "triangle":
            value = 2 / math.pi * math.asin(math.sin(phase))
        else:
            value = math.sin(phase)
        envelope = math.exp(-decay * t) * min(1.0, i / (RATE * 0.004))
        samples.append(value * envelope * volume)
    return samples


def noise(seconds, volume=0.3, decay=12.0):
    count = int(RATE * seconds)
    return [(_noise.random() * 2 - 1) * math.exp(-decay * i / count) * volume for i in range(count)]


def mix(*layers):
    length = max(len(layer) for layer in layers)
    return [sum(layer[i] for layer in layers if i < len(layer)) for i in range(length)]


def sequence(*parts, gap=0.0):
    result = []
    for part in parts:
        result.extend(part)
        result.extend([0.0] * int(RATE * gap))
    return result


def note(name):
    semitones = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    return 440.0 * 2 ** ((semitones[name[0]] + 12 * (int(name[1]) - 4)) / 12)


def write(name, samples):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(str(OUT_DIR / f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))
    print(f"{name}.wav  {len(samples) / RATE * 1000:.0f} ms")


RECIPES = {
    # Fires 8 times per second, so it must be short and soft.
    "shoot": lambda: sweep(900, 420, 0.06, "triangle", 0.35, 8.0),
    "enemy_shoot": lambda: sweep(520, 300, 0.08, "square", 0.18, 7.0),
    "enemy_hit": lambda: mix(sweep(320, 220, 0.05, "square", 0.2, 10.0), noise(0.04, 0.25)),
    "enemy_death": lambda: mix(sweep(660, 140, 0.16, "sine", 0.6, 4.0), noise(0.08, 0.2)),
    "player_hurt": lambda: mix(sweep(220, 70, 0.2, "triangle", 0.7, 3.5), noise(0.12, 0.35, 8.0)),
    "wave_start": lambda: sequence(
        sweep(note("C5"), note("C5"), 0.12, "triangle", 0.5, 3.0),
        sweep(note("G5"), note("G5"), 0.22, "triangle", 0.5, 3.0), gap=0.03),
    "game_over": lambda: sequence(
        sweep(note("G4"), note("G4"), 0.18, "triangle", 0.5, 2.5),
        sweep(note("E4"), note("E4"), 0.18, "triangle", 0.5, 2.5),
        sweep(note("C4"), note("C4"), 0.45, "triangle", 0.5, 2.0), gap=0.04),
}


if __name__ == "__main__":
    for sound_name, recipe in RECIPES.items():
        write(sound_name, recipe())
