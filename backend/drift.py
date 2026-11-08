"""Drift drone: thread trajectory rapport -> trust/off-platform -> money, with a per-message risk series."""
import re
from .common import mk

I = re.I
STAGES = [
    (0.15, "rapport", re.compile(r"wrong number|who is this|is this \w+\?|nice to meet|where are you from|how was your day|i'?m \w+ from|you seem|beautiful|new friend", I)),
    (0.5, "off_platform", re.compile(r"whatsapp|telegram|signal app|text me at|add me|move (?:to|over)|my other number|private chat", I)),
    (1.0, "money", re.compile(r"crypto\w*|bitcoin|usdt|invest\w*|trading platform|profit\w*|returns?\b|wallet|gift ?cards?|wire|send money|transfer|withdraw\w*", I)),
]


def series(req):
    """Cumulative stage reached after each message, plus the ordered list of stages seen."""
    reached, seen, out = 0.0, [], []
    for m in req.messages:
        if m.direction == "in":
            for w, name, rx in STAGES:
                if rx.search(m.text):
                    reached = max(reached, w)
                    if name not in seen:
                        seen.append(name)
        out.append(round(reached, 2))
    return out, seen


def analyze(req, intel):
    if len(req.messages) < 2:
        return None, 0.0
    ser, seen = series(req)
    if len(seen) < 2 or "money" not in seen and len(seen) < 3:
        return None, 0.0
    score = 0.6 if len(seen) == 2 else 0.8
    from .explain import template
    t = template("drift", dict(stages=seen))
    last = next(m for m in reversed(req.messages) if m.direction == "in")
    return mk("drift", score, t["title"], t["explanation"], [("stages", " > ".join(seen), "heuristic")],
              dict(messageId=last.id, field="body"), t.get("change")), score
