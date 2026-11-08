"""Pressure drone: urgency / threat / secrecy / payment-rail lexicons with spans."""
import re
from .common import mk, target_msg

I = re.I
DEADLINE = re.compile(r"\b(?:in|within|before|by)\s+(?:the\s+next\s+)?\d+\s*(?:hrs?|hours?|mins?|minutes?|days?)\b|\b(?:today|tonight|immediately|right now|asap)\b", I)
THREAT = re.compile(r"\b(?:suspend\w*|terminat\w*|lock(?:ed)?|deactivat\w*|disabled?|closed|arrest\w*|warrant|legal action|lawsuit|penalt\w+|fines?|forfeit\w*|blocked|cancell?ed|frozen)\b", I)
URGENT = re.compile(r"\b(?:urgent\w*|final notice|last chance|act now|immediate action|expires? (?:soon|today)|failure to|verify now|confirm now|respond now|limited time)\b", I)
SECRECY = re.compile(r"\b(?:don'?t tell|do not tell|keep (?:this|it) (?:between|secret|private|confidential)|confidential|tell no one|do not share this with)\b", I)
RAILS = re.compile(r"\b(?:gift ?cards?|bitcoin|btc|crypto\w*|usdt|ethereum|wire (?:transfer|money)|western union|zelle|cash ?app|money ?gram|itunes card|steam card)\b", I)
W = dict(deadline=0.3, threat=0.3, urgent=0.3, secrecy=0.5, rail=0.4, billing=0.3, limited=0.3, pwexpire=0.3, verify=0.3, ceo=0.5)
EMAIL_RX = (
    ("billing", re.compile(r"\b(?:payment (?:is )?(?:due|overdue|failed)|past due|overdue|outstanding (?:balance|invoice)|unpaid invoice)\b", I)),
    ("limited", re.compile(r"\baccount (?:has been |is |was )?(?:limited|restricted|on hold|compromised|suspended)\b|\bunusual activity\b", I)),
    ("pwexpire", re.compile(r"\bpassword (?:will |is about to )?expire[sd]?\b", I)),
    ("verify", re.compile(r"\bverify your (?:account|identity|email|information)\b|\bconfirm your (?:account|identity)\b", I)),
    ("ceo", re.compile(r"\b(?:are you available|wire (?:the )?(?:funds|payment)|buy (?:some )?gift cards?|need a favou?r|keep this (?:confidential|between us)|urgent task)\b", I)),
)


def analyze(req, intel, clf=None):
    msg = target_msg(req)
    t, off, rxs = msg.text, 0, [("deadline", DEADLINE), ("threat", THREAT), ("urgent", URGENT), ("secrecy", SECRECY), ("rail", RAILS)]
    if req.channel == "email" and req.email:  # subject counts too; spans are mapped back to the body
        t, off = req.email.subject + "\n" + msg.text, len(req.email.subject) + 1
        rxs += list(EMAIL_RX)
    hits = {}
    for name, rx in rxs:
        m = rx.search(t)
        if m:
            hits[name] = m
    score = min(1.0, sum(W[k] for k in hits) + (0.15 if "threat" in hits and "deadline" in hits else 0))
    if score < 0.5:
        if clf and clf.get("category_id") != "legit" and clf.get("prob", 0) >= 0.75:  # classifier-only pattern match
            from .explain import template
            tp = template("pressure", dict(phrase=None, label=clf["label"]))
            return mk("pressure", clf["prob"] * 0.8, tp["title"], tp["explanation"], [("classifier_category", clf["category_id"], "classifier")],
                      dict(messageId=msg.id, field="body"), tp.get("change")), score
        return None, score
    # a threat followed closely by a deadline reads best as one span ("suspended in 2 hrs")
    th, dl = hits.get("threat"), hits.get("deadline")
    if th and dl and 0 <= dl.start() - th.end() <= 12:
        span, phrase = (th.start(), dl.end()), t[th.start():dl.end()]
    else:
        m = min(hits.values(), key=lambda x: x.start())
        span, phrase = (m.start(), m.end()), m.group(0)
    span = (span[0] - off, span[1] - off) if span[0] >= off else None  # None: phrase is only in the subject
    ev = [(k, v.group(0), "heuristic") for k, v in hits.items()]
    if clf and clf.get("category_id") != "legit" and clf.get("prob", 0) > 0.6:
        ev.append(("classifier_category", clf["category_id"], "classifier"))
    from .explain import template
    tp = template("pressure", dict(phrase=phrase, kinds=sorted(hits)))
    return mk("pressure", score, tp["title"], tp["explanation"], ev, dict(messageId=msg.id, field="body", span=span), tp.get("change")), score
