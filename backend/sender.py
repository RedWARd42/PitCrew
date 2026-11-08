"""Angler drone: who is texting? Number type, reputation, first-time sender, brand/sender mismatch."""
import re
from .common import mk, target_msg
from .impersonation import brands_in

BASE = {"short_code": 0.05, "toll_free": 0.25, "long_code": 0.3, "email": 0.45, "alphanumeric": 0.3, "unknown": 0.3}


def e164_of(sender) -> str | None:
    if sender.e164:
        return sender.e164
    d = re.sub(r"\D", "", sender.raw)
    return "+" + (d if len(d) == 11 else "1" + d) if len(d) in (10, 11) else None


def analyze(req, intel):
    s, msg = req.sender, target_msg(req)
    if s.isContact or msg.direction != "in":
        return None, 0.0
    score, ev, facts = BASE.get(s.kind, 0.3), [("sender_kind", s.kind, "heuristic")], {}
    first_time = not any(m.direction == "out" for m in req.messages)
    if first_time and s.kind != "short_code":
        score += 0.15
        ev.append(("first_time_sender", "true", "heuristic"))
    rep = intel.reputation.get(e164_of(s) or "")
    if rep:
        c = int(rep["complaints"])
        score += 0.4 if c >= 10 else 0.2
        ev.append(("complaints", str(c), "reputation"))
        if rep["robocall"].lower() == "true":
            score += 0.2
            ev.append(("robocall_flag", "true", "reputation"))
        facts["complaints"] = c
    brands = brands_in(msg.text, intel)
    if brands and s.kind != "short_code":
        score += 0.3
        ev.append(("brand_claim_mismatch", brands[0][0]["brand"], "heuristic"))
        facts["brand"] = brands[0][0]["brand"]
    if s.raw.upper().startswith("FRM:") or msg.text.upper().startswith("FRM:"):
        score += 0.2
        ev.append(("email_gateway", "FRM:", "heuristic"))
    score = min(score, 1.0)
    if score < 0.44:
        return None, score
    from .explain import template
    t = template("angler", dict(kind=s.kind, first_time=first_time, **facts))
    return mk("angler", score, t["title"], t["explanation"], ev, dict(messageId="header", field="sender"), t.get("change")), score
