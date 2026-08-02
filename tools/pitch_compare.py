#!/usr/bin/env python3
"""Pitch + spectrum comparison for TMS5200 speech captures.

Reports, per file:
  - voiced DURATION (silence trimmed) -- if our phrase is shorter than the
    cabinet's by the same ratio the pitch is high, the CLOCK is wrong, because
    an LPC synthesiser scales pitch and rate together.
  - median F0 over voiced frames, with explicit octave-error handling: raw
    autocorrelation happily reports a subharmonic, which is how a previous
    pass concluded 103 Hz for a 206 Hz phrase.
  - 95% spectral rolloff and the fraction of energy above 4 kHz (a real
    TMS5220-class part cannot produce content above ~4 kHz).
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import get_window


def load_mono(path):
    sr, x = wavfile.read(path)
    x = x.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if np.max(np.abs(x)) > 0:
        x /= np.max(np.abs(x))
    return sr, x


def voiced_mask(x, sr, frame, hop, thresh_db=-33.0):
    n = 1 + max(0, (len(x) - frame) // hop)
    rms = np.array([np.sqrt(np.mean(x[i * hop:i * hop + frame] ** 2) + 1e-20)
                    for i in range(n)])
    db = 20 * np.log10(rms / (rms.max() + 1e-20) + 1e-20)
    return db > thresh_db, rms


def f0_autocorr(seg, sr, fmin=70.0, fmax=400.0):
    seg = seg - seg.mean()
    if np.sqrt(np.mean(seg ** 2)) < 1e-6:
        return None
    w = seg * get_window("hann", len(seg))
    ac = np.correlate(w, w, mode="full")[len(w) - 1:]
    if ac[0] <= 0:
        return None
    ac /= ac[0]
    lo, hi = int(sr / fmax), min(int(sr / fmin), len(ac) - 2)
    if hi <= lo + 2:
        return None
    seg_ac = ac[lo:hi]
    lag = lo + int(np.argmax(seg_ac))
    peak = ac[lag]
    if peak < 0.30:                      # too weak to trust
        return None
    # parabolic interpolation around the peak
    if 0 < lag < len(ac) - 1:
        a, b, c = ac[lag - 1], ac[lag], ac[lag + 1]
        denom = (a - 2 * b + c)
        if denom != 0:
            lag = lag + 0.5 * (a - c) / denom
    f = sr / lag
    # OCTAVE CHECK: if half the lag also correlates strongly, the true period
    # is the shorter one and we just locked onto a subharmonic.
    half = lag / 2.0
    if half >= lo:
        hl = int(round(half))
        if 0 < hl < len(ac) and ac[hl] > 0.85 * peak:
            f *= 2.0
    return f


def analyse(path, label):
    sr, x = load_mono(path)
    frame, hop = int(0.040 * sr), int(0.010 * sr)
    mask, rms = voiced_mask(x, sr, frame, hop)
    if not mask.any():
        print(f"{label}: no voiced audio found")
        return
    idx = np.where(mask)[0]
    dur = (idx[-1] - idx[0] + 1) * hop / sr

    f0s = []
    for i in idx:
        f = f0_autocorr(x[i * hop:i * hop + frame], sr)
        if f:
            f0s.append(f)
    f0s = np.array(f0s)

    # spectrum over the voiced region only
    a, b = idx[0] * hop, idx[-1] * hop + frame
    seg = x[a:b]
    spec = np.abs(np.fft.rfft(seg * get_window("hann", len(seg)))) ** 2
    freq = np.fft.rfftfreq(len(seg), 1 / sr)
    csum = np.cumsum(spec)
    roll95 = freq[np.searchsorted(csum, 0.95 * csum[-1])]
    above4k = spec[freq > 4000].sum() / spec.sum() * 100

    print(f"{label}")
    print(f"   file            : {path.split('/')[-1]}")
    print(f"   voiced duration : {dur:.3f} s")
    if len(f0s):
        print(f"   F0 median       : {np.median(f0s):6.1f} Hz   "
              f"(p25 {np.percentile(f0s,25):.0f} / p75 {np.percentile(f0s,75):.0f}, "
              f"n={len(f0s)})")
    else:
        print("   F0 median       : (unvoiced / no reliable estimate)")
    print(f"   95% rolloff     : {roll95:6.0f} Hz")
    print(f"   energy > 4 kHz  : {above4k:5.1f} %")
    print()
    return dict(dur=dur, f0=float(np.median(f0s)) if len(f0s) else None,
                roll=roll95, hi=above4k)


if __name__ == "__main__":
    res = {}
    for arg in sys.argv[1:]:
        label, path = arg.split("=", 1)
        res[label] = analyse(path, label)
    if len(res) >= 2:
        keys = list(res.keys())
        ours = res[keys[0]]
        real = res[keys[1]]
        if ours and real and ours["f0"] and real["f0"]:
            print("=" * 62)
            print(f"pitch ratio    {keys[0]} / {keys[1]} : "
                  f"{ours['f0']/real['f0']:.3f}")
            print(f"duration ratio {keys[0]} / {keys[1]} : "
                  f"{ours['dur']/real['dur']:.3f}")
            print()
            print("If BOTH ratios move together (pitch high AND duration short")
            print("by the same factor) the TMS clock is wrong. If pitch is off")
            print("but duration matches, it is not the clock.")
