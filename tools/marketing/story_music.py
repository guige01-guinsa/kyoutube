"""Original preview score: written notes and synthesized tones, no sampled media."""
from array import array
import math

RATE = 22050
# Eight original bars; beats are spaced to leave room for the spoken story.
MELODY = (
    (0, 69), (1.5, 72), (3, 76), (4.5, 74), (6, 72),
    (8, 67), (9.5, 71), (11, 74), (13, 72), (14.5, 69),
    (16, 65), (17.5, 69), (19, 72), (21, 71), (22.5, 67),
    (24, 64), (25.5, 67), (27, 71), (29, 69), (30.5, 64),
)
CHORDS = ((45, 52, 60), (43, 50, 59), (41, 48, 57), (40, 47, 55))


def add_note(buffer, start, midi, length, level):
    """Soft struck-string-like timbre with attack and exponential decay."""
    frequency = 440 * 2 ** ((midi - 69) / 12)
    begin = int(start * RATE)
    count = min(int(length * RATE), len(buffer) - begin)
    for i in range(max(0, count)):
        t = i / RATE
        envelope = min(1, t / .018) * math.exp(-t * 1.8) * min(1, (length - t) / .12)
        phase = 2 * math.pi * frequency * t
        tone = math.sin(phase) + .22 * math.sin(2 * phase) + .07 * math.sin(3 * phase)
        buffer[begin + i] += level * envelope * tone


def score(seconds, episode=1):
    if not 0 < seconds <= 240 or episode not in range(1, 13):
        raise ValueError('invalid_score_duration_or_episode')
    output = array('f', [0]) * int(seconds * RATE)
    beat = 60 / 76
    cycle = beat * 32
    offset = 0.0
    # Same motif across episodes; hopeful finale shifts the last cadence upward.
    while offset < seconds:
        for bar, notes in enumerate(CHORDS):
            for position, midi in enumerate(notes):
                add_note(output, offset + (bar * 8 + position * .5) * beat, midi, 3.4, .12)
        for position, midi in MELODY:
            note = midi + (12 if episode == 3 and position >= 29 else 0)
            add_note(output, offset + position * beat, note, 2.7, .16)
        offset += cycle
    peak = max(map(abs, output), default=1) or 1
    for i in range(len(output)):
        t = i / RATE
        fade = min(1, t / 1.2, (seconds - t) / 2)
        output[i] = output[i] / peak * .13 * max(0, fade)
    return output
