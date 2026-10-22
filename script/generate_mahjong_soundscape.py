#!/usr/bin/env python3
"""Generate original, warm Mahjong foley and seamless instrumental loops.

Solid tile bodies, felt friction and rolling impacts carry the physical cues.
No downloaded recordings, external libraries, or runtime synthesis are needed.
Re-run this script when changing the sound palette; build_app.sh bundles its output.
"""
from array import array
import math
from pathlib import Path
import random
import sys
import wave

RATE = 32000
ROOT = Path(__file__).resolve().parent.parent / "Resources" / "MahjongAudio"
TAU = math.tau


def warm_filter(samples, cutoff, cyclic=False):
    """Two gentle treble roll-offs plus DC/subsonic removal; no resonant ringing."""
    alpha = 1 - math.exp(-TAU * cutoff / RATE)
    dc_alpha = 1 - math.exp(-TAU * 42 / RATE)
    first = second = dc = 0.0
    if cyclic:
        # Settle the filters on a full cycle before rendering the loop boundary.
        for sample in samples:
            first += alpha * (sample - first)
            second += alpha * (first - second)
            dc += dc_alpha * (second - dc)
    result = []
    for sample in samples:
        first += alpha * (sample - first)
        second += alpha * (first - second)
        dc += dc_alpha * (second - dc)
        result.append(second - dc)
    return result


def write(name, samples, directory="effects", peak=0.68, cutoff=1100):
    target = ROOT / directory / f"{name}.wav"
    target.parent.mkdir(parents=True, exist_ok=True)
    samples = warm_filter(samples, cutoff, cyclic=directory == "music")
    maximum = max((abs(x) for x in samples), default=1) or 1
    gain = min(1, peak / maximum)
    pcm = array("h", (int(max(-1, min(1, x * gain)) * 32767) for x in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(target), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    print(target.relative_to(ROOT), f"{len(samples) / RATE:.2f}s")


def silent(duration):
    return [0.0] * int(duration * RATE)


def add(target, sound, at=0, gain=1, cyclic=False):
    start = round(at * RATE)
    for offset, sample in enumerate(sound):
        index = start + offset
        if cyclic:
            index %= len(target)
        elif index >= len(target):
            break
        target[index] += sample * gain


def pluck(frequency, duration=0.5, strength=0.5, mellow=False):
    """Soft low-register string/wood tone instead of an inharmonic bell."""
    result = silent(duration)
    for index in range(len(result)):
        t = index / RATE
        attack = min(1, t / 0.012)
        release = min(1, (duration - t) / 0.045)
        partials = (math.sin(TAU * frequency * t) * math.exp(-t * (3.8 if mellow else 11))
                    + 0.14 * math.sin(TAU * frequency * 2 * t) * math.exp(-t * 16)
                    + 0.035 * math.sin(TAU * frequency * 3 * t) * math.exp(-t * 25)
                    + 0.28 * math.sin(TAU * frequency * 0.5 * t) * math.exp(-t * 7))
        result[index] = partials * strength * attack * release
    return result


def tile_impact(seed, body=0.72, duration=0.19, hardness=1):
    """Short solid-body resonances, a muted contact edge and a felt/wood thump."""
    rng = random.Random(seed)
    result = silent(duration)
    modes = [(rng.uniform(175, 225), body, 37),
             (rng.uniform(440, 570), 0.29, 60),
             (rng.uniform(850, 1050), 0.10 * hardness, 100),
             (rng.uniform(1420, 1680), 0.035 * hardness, 155)]
    contact = 0.0
    alpha = 1 - math.exp(-TAU * 1900 / RATE)
    for index in range(len(result)):
        t = index / RATE
        contact += alpha * (rng.uniform(-1, 1) - contact)
        hit = sum(math.sin(TAU * frequency * t) * amplitude * math.exp(-decay * t)
                  for frequency, amplitude, decay in modes)
        hit += 0.22 * math.sin(TAU * 112 * t) * math.exp(-43 * t)
        hit += contact * 0.13 * hardness * math.exp(-180 * t)
        result[index] = hit * min(1, t / 0.0018) * min(1, (duration - t) / 0.015)
    return result


def scrape(seed, duration=0.16, strength=0.14):
    """Irregular, band-limited friction as a tile slides across the felt."""
    rng = random.Random(seed)
    result = silent(duration)
    fine = coarse = 0.0
    fine_alpha = 1 - math.exp(-TAU * 1600 / RATE)
    coarse_alpha = 1 - math.exp(-TAU * 180 / RATE)
    for index in range(len(result)):
        t = index / RATE
        noise = rng.uniform(-1, 1)
        fine += fine_alpha * (noise - fine)
        coarse += coarse_alpha * (noise - coarse)
        envelope = math.sin(math.pi * t / duration) ** 2
        envelope *= 0.7 + 0.3 * math.sin(TAU * 37 * t) ** 2
        result[index] = (fine - coarse) * envelope * strength
    return result


def chime(name, notes, gap=0.1, strength=0.32, duration=1.2):
    # Two octaves lower, with shorter, darker overtones and a softer onset.
    result = silent(max(duration, len(notes) * gap + 0.6))
    for index, midi in enumerate(notes):
        note = pluck(440 * 2 ** ((midi - 24 - 69) / 12), 0.8, strength, mellow=True)
        add(result, note, index * gap)
        add(result, note, index * gap + 0.085, 0.07)
    write(name, result)


def meld(name, count, seed):
    result = silent(0.58 if count == 4 else 0.48)
    # Chi lays down sequentially; pong/kong have a clustered landing and a final tile.
    timings = [0, 0.052, 0.112] if name == "chi" else [0, 0.018, 0.092]
    if count == 4:
        timings = [0, 0.018, 0.043, 0.158]
    for index, at in enumerate(timings):
        add(result, tile_impact(seed + index, body=0.64), at,
            0.48 if index < count - 1 else 0.67)
    add(result, scrape(seed + 11, duration=0.23, strength=0.21), timings[-1] + 0.025)
    write(name, result, cutoff=1800)


def tile_actions():
    for variant in [1, 2, 3]:
        landing = silent(0.24)
        add(landing, tile_impact(50 + variant), 0.004, 0.92)
        add(landing, tile_impact(65 + variant, body=0.42, hardness=0.5), 0.034, 0.19)
        add(landing, scrape(70 + variant, duration=0.09, strength=0.10), 0.045)
        write(f"tileDiscard-{variant}", landing, cutoff=1800)
        drawing = silent(0.26)
        add(drawing, scrape(80 + variant, duration=0.15, strength=0.28))
        add(drawing, tile_impact(90 + variant, body=0.56, hardness=0.65), 0.11, 0.58)
        write(f"tileDraw-{variant}", drawing, peak=0.38, cutoff=1550)
    packet = silent(0.19)
    for index, at in enumerate([0, 0.011, 0.042]):
        add(packet, tile_impact(21 + index, body=0.48), at, 0.31)
    write("deal", packet, peak=0.31, cutoff=1700)


def effects():
    # Only physical actions and a single restrained deadline/result cue remain.
    write("tick", tile_impact(810, body=0.38, duration=0.13, hardness=0.35), peak=0.20, cutoff=900)
    meld("chi", 3, 200)
    meld("pong", 3, 230)
    meld("kong", 4, 260)
    # Used only when spoken announcements are muted.
    chime("win", [60, 67], gap=0.18, strength=0.18, duration=1.0)
    tile_actions()


def music_note(midi, duration, strength, bass=False):
    """Rounded wood-key lead and a soft, bouncing bass without sharp transients."""
    frequency = 440 * 2 ** ((midi - 69) / 12)
    result = silent(duration)
    for index in range(len(result)):
        t = index / RATE
        envelope = min(1, t / 0.009) * min(1, (duration - t) / 0.04)
        fundamental = math.sin(TAU * frequency * t) * math.exp(-t * (3.8 if bass else 6.5))
        second = 0.22 * math.sin(TAU * frequency * 2 * t) * math.exp(-t * 12)
        third = 0.06 * math.sin(TAU * frequency * 3 * t) * math.exp(-t * 20)
        result[index] = (fundamental + second + third) * envelope * strength
    return result


def music():
    # Sixteen bars in C major at 112 BPM, with breathing space in the melody.
    # Offbeat chord strokes and a rounded two-beat bass make the loop buoyant.
    beat = 60 / 112
    result = silent(64 * beat)
    harmony = [(48, 52, 55), (53, 57, 60), (48, 52, 55), (43, 47, 50),
               (45, 48, 52), (53, 57, 60), (43, 47, 50), (48, 52, 55)] * 2
    phrases = [
        [(0, 64, 0.5), (0.5, 67, 0.5), (1, 69, 1), (2.5, 67, 0.5), (3, 64, 0.75)],
        [(0, 65, 0.5), (0.5, 69, 0.5), (1.5, 72, 0.5), (2, 69, 1), (3, 67, 0.5)],
        [(0, 64, 0.5), (0.5, 67, 0.5), (1, 72, 1), (2.5, 71, 0.5), (3, 69, 0.75)],
        [(0, 67, 1), (1.5, 64, 0.5), (2, 62, 1.5)],
        [(0, 64, 0.5), (0.5, 69, 0.5), (1.5, 72, 0.5), (2, 71, 0.5), (3, 69, 0.75)],
        [(0, 69, 0.5), (0.5, 72, 0.5), (1, 74, 1), (2.5, 72, 0.5), (3, 69, 0.75)],
        [(0, 67, 0.5), (0.5, 71, 0.5), (1.5, 74, 0.5), (2, 71, 0.5), (3, 62, 0.75)],
        [(0, 64, 0.5), (0.5, 67, 0.5), (1.5, 64, 0.5), (2, 60, 1.5)],
        [(0, 72, 0.75), (1, 69, 0.5), (1.5, 67, 0.5), (2.5, 64, 0.5), (3, 67, 0.75)],
        [(0, 69, 0.5), (0.5, 72, 0.5), (1.5, 69, 0.5), (2, 65, 1), (3.5, 64, 0.5)],
        [(0, 67, 0.5), (0.5, 72, 0.5), (1, 76, 1), (2.5, 72, 0.5), (3, 69, 0.75)],
        [(0, 71, 0.75), (1, 67, 0.5), (1.5, 64, 0.5), (2, 62, 1.5)],
        [(0, 69, 0.5), (0.5, 72, 0.5), (1.5, 76, 0.5), (2, 72, 1), (3, 69, 0.75)],
        [(0, 72, 0.75), (1, 69, 0.5), (1.5, 65, 0.5), (2.5, 69, 0.5), (3, 72, 0.75)],
        [(0, 71, 0.5), (0.5, 74, 0.5), (1.5, 71, 0.5), (2, 67, 0.5), (3, 62, 0.75)],
        [(0, 64, 0.5), (0.5, 67, 0.5), (1.5, 72, 0.5), (2, 60, 1.5)],
    ]
    for bar, chord in enumerate(harmony):
        start = bar * 4 * beat
        for step, note in [(0, chord[0] - 12), (2, chord[0] - 5)]:
            add(result, music_note(note, beat * 1.2, 0.16, bass=True), start + step * beat, cyclic=True)
        for step in [0.5, 1.5, 2.5, 3.5]:
            for index, note in enumerate(chord):
                add(result, music_note(note + 12, beat * 0.42, 0.035),
                    start + step * beat + index * 0.012, cyclic=True)
        for offset, note, length in phrases[bar]:
            add(result, music_note(note, beat * length, 0.19), start + offset * beat, cyclic=True)
        for step in [0, 2]:
            pulse = [0.065 * math.sin(TAU * 72 * i / RATE) * math.exp(-35 * i / RATE)
                     * min(1, i / (RATE * 0.006)) for i in range(int(RATE * 0.16))]
            add(result, pulse, start + step * beat, cyclic=True)
        for step in [1, 3]:
            add(result, scrape(900 + bar, duration=0.09, strength=0.035),
                start + step * beat, cyclic=True)
    write("happyTable", result, directory="music", peak=0.46, cutoff=1800)


if __name__ == "__main__":
    effects()
    music()
