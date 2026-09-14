#!/usr/bin/env python3
# Green check for W5D2 (knee + capacity + cost).
# Run next to your filled capacity-worksheet.md:  python verify.py
# Prints exactly one line last: GREEN CHECK: PASS  or  GREEN CHECK: FAIL (<reason>)
# stdlib only. Your measurements are yours; the arithmetic on them is checked.
import math, os, re, sys
from typing import NoReturn


class _Stop(Exception):
    pass


def _fail(reason) -> NoReturn:
    print("GREEN CHECK: FAIL (%s)" % reason)
    raise _Stop()


def main():
    path = "capacity-worksheet.md"
    if not os.path.isfile(path):
        _fail("capacity-worksheet.md not found; fill the template in this directory")
    text = open(path).read()
    if re.search(r"<[a-zA-Z.][^>]*>", text):
        _fail("worksheet still has angle-bracket placeholders: %s"
              % re.search(r"<[a-zA-Z.][^>]*>", text).group(0))

    rows = re.findall(r"^\|\s*(\d+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|", text, re.M)
    rows = [(int(u), float(r), float(p)) for u, r, p in rows]
    if len(rows) < 4:
        _fail("need at least 4 measured ramp levels in the table, found %d" % len(rows))

    m = re.search(r"Knee:\s*users\s*=\s*(\d+),\s*rate\s*=\s*([\d.]+)", text)
    if not m:
        _fail("no knee line in the form 'Knee: users=N, rate=R'")
    knee_u, knee_rate = int(m.group(1)), float(m.group(2))
    if knee_u not in [u for u, _, _ in rows]:
        _fail("knee users=%d is not one of the measured levels" % knee_u)
    meas = {u: r for u, r, _ in rows}
    if abs(meas[knee_u] - knee_rate) > max(1.0, meas[knee_u] * 0.05):
        _fail("knee rate %.1f disagrees with the table's %.1f at users=%d"
              % (knee_rate, meas[knee_u], knee_u))

    for mult in (2, 3):
        m2 = re.search(r"%dx knee load \(([\d.]+) req/min\): ceil\(([\d.]+)/([\d.]+)\) = (\d+) replicas" % mult, text)
        if not m2:
            _fail("missing or malformed %dx replica line" % mult)
        target, num, den, n = (float(m2.group(1)), float(m2.group(2)),
                               float(m2.group(3)), int(m2.group(4)))
        if abs(target - mult * knee_rate) > knee_rate * 0.05:
            _fail("%dx target %.1f is not %dx your knee rate %.1f"
                  % (mult, target, mult, knee_rate))
        want = math.ceil(target / den - 1e-9)
        if n != want or abs(den - knee_rate) > knee_rate * 0.05:
            _fail("%dx: ceil(%.1f/%.1f) is %d, worksheet says %d"
                  % (mult, target, den, want, n))

    m3 = re.search(r"rate:\s*\$([\d.]+)/h", text)
    m4 = re.search(r"Tokens/hour at the knee:.*=\s*([\d,]+)", text)
    m5 = re.search(r"steady knee:\s*\$([\d.]+)", text)
    if not (m3 and m4 and m5):
        _fail("cost section incomplete (rate, tokens/hour, steady cost all required)")
    rate = float(m3.group(1))
    tph = float(m4.group(1).replace(",", ""))
    want_tph = knee_rate * 60 * 200
    if abs(tph - want_tph) > want_tph * 0.02:
        _fail("tokens/hour %.0f, but knee %.1f req/min x 60 x 200 = %.0f"
              % (tph, knee_rate, want_tph))
    want_cost = rate / (tph / 1e6)
    if abs(float(m5.group(1)) - want_cost) > max(0.005, want_cost * 0.02):
        _fail("steady cost $%s, formula gives $%.4f" % (m5.group(1), want_cost))

    print("knee named from your own levels; replicas and cost recompute cleanly")
    print("GREEN CHECK: PASS")


if __name__ == "__main__":
    try:
        main()
    except _Stop:
        sys.exit(1)
