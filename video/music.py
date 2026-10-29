"""Original background track for the Keyward launch video (44 s, 100 BPM). Pure standard library."""
import array, math, random, sys, wave

SR, DUR, BPM = 44100, 44.0, 100
BEAT = 60 / BPM
N = int(SR * DUR)
L = array.array('f', [0.0]) * N
R = array.array('f', [0.0]) * N
rnd = random.Random(7)


def midi(n):
    return 440 * 2 ** ((n - 69) / 12)


def add(buf, start, samples, gain):
    i0 = int(start * SR)
    for i, s in enumerate(samples):
        j = i0 + i
        if 0 <= j < N:
            buf[j] += s * gain


# Pad: Am - F - C - G, two bars each (8 beats), soft detuned voices with slow swell.
CHORDS = [[57, 60, 64, 69], [53, 57, 60, 65], [48, 55, 60, 64], [55, 59, 62, 67]]
chord_len = 8 * BEAT
t0 = 0.0
k = 0
while t0 < DUR:
    notes = CHORDS[k % 4]
    n = int(chord_len * SR) + int(1.2 * SR)
    for vi, note in enumerate(notes):
        f = midi(note)
        for det, pan in ((-0.12, 0.3), (0.12, 0.7)):
            fr = f * 2 ** (det / 12)
            ph = rnd.random() * 6.28
            out = []
            for i in range(n):
                tt = i / SR
                a = min(1, tt / 1.0) * (1 - max(0, (tt - chord_len) / 1.2))
                w = 2 * math.pi * fr * tt + ph
                out.append(a * (math.sin(w) + 0.28 * math.sin(2 * w) + 0.1 * math.sin(3 * w)))
            add(L, t0, out, 0.030 * (1 - pan))
            add(R, t0, out, 0.030 * pan)
    # bass root
    f = midi(notes[0] - 24)
    out = [min(1, i / 2000) * math.exp(-(i / SR) / 3.5) * math.sin(2 * math.pi * f * i / SR) for i in range(int(chord_len * SR))]
    add(L, t0, out, 0.08)
    add(R, t0, out, 0.08)
    t0 += chord_len
    k += 1

# Kick on every beat from the logo reveal (7.7 s) until the end card fade.
kick = []
for i in range(int(0.35 * SR)):
    tt = i / SR
    f = 45 + 95 * math.exp(-tt * 28)
    kick.append(math.sin(2 * math.pi * f * tt - 0) * math.exp(-tt * 9))
t = 7.7
while t < 42.8:
    g = 0.30 if t < 39.8 else 0.22
    add(L, t, kick, g)
    add(R, t, kick, g)
    t += BEAT

# Hi-hats on off-beats from 11 s.
def hat(length=0.05):
    return [(rnd.random() * 2 - 1) * math.exp(-(i / SR) * 70) for i in range(int(length * SR))]
t = 11.0 + BEAT / 2
while t < 42.5:
    h = hat()
    # crude high-pass: difference of neighbours
    h = [h[i] - h[i - 1] if i else h[0] for i in range(len(h))]
    add(L, t, h, 0.045)
    add(R, t, h, 0.06)
    t += BEAT

# Plucky arpeggio during the features / install (29.6 s on).
ARP = [69, 72, 76, 79, 76, 72]
t = 29.6
i = 0
while t < 42.6:
    f = midi(ARP[i % len(ARP)] + 12)
    pl = [math.sin(2 * math.pi * f * j / SR) * math.exp(-(j / SR) * 7) for j in range(int(0.6 * SR))]
    add(L if i % 2 else R, t, pl, 0.035)
    add(R if i % 2 else L, t, pl, 0.018)
    t += BEAT / 2
    i += 1

# Riser into the logo (5.7–7.7 s) and an impact at 7.7 s.
rise = []
for j in range(int(2.0 * SR)):
    tt = j / SR
    rise.append((rnd.random() * 2 - 1) * (tt / 2.0) ** 2 * 0.6 + math.sin(2 * math.pi * (200 + 600 * tt / 2) * tt) * (tt / 2.0) ** 2 * 0.25)
add(L, 5.7, rise, 0.12)
add(R, 5.7, rise, 0.12)
boom = [math.sin(2 * math.pi * (38 + 40 * math.exp(-j / SR * 6)) * j / SR) * math.exp(-(j / SR) * 2.2) for j in range(int(2.5 * SR))]
add(L, 7.7, boom, 0.45)
add(R, 7.7, boom, 0.45)

# Master: fade in/out, normalise, soft clip, write 16-bit stereo.
peak = max(max(abs(x) for x in L), max(abs(x) for x in R)) or 1
frames = array.array('h')
for j in range(N):
    tt = j / SR
    g = min(1, tt / 0.8) * (1 - max(0, (tt - 42.6) / 1.4))
    for buf in (L, R):
        x = math.tanh(1.3 * buf[j] / peak) / math.tanh(1.3) * 0.89 * g
        frames.append(int(x * 32767))
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(frames.tobytes())
print('wrote', sys.argv[1])
