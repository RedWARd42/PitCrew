"""Warden drone (outgoing drafts): OTPs, gift-card codes, card numbers (Luhn), SSNs, passwords.
Evidence values are masked placeholders; the secret itself is never echoed."""
import re
from .common import mk, target_msg

CTX = re.compile(r"\b(code|otp|passcode|verification|verify|pin|one[- ]?time|security)\b", re.I)
ASK = re.compile(r"\b(send|read|give|reply with|forward|tell)\b.{0,40}\b(code|otp|pin)\b|\bcode\b.{0,30}\b(sent|received|texted)\b", re.I | re.S)
CARD = re.compile(r"(?<!\d)(?:\d[ -]?){13,19}(?!\d)")
SSN = re.compile(r"(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)")
GIFT = re.compile(r"gift ?card", re.I)
PASSWD = re.compile(r"\b(?:password|passwd|passcode|pw)\s*(?:is|:|=)\s*\S+", re.I)


def luhn(d: str) -> bool:
    s = sum((x * 2 - 9 if x * 2 > 9 else x * 2) if i % 2 else x for i, x in enumerate(int(c) for c in reversed(d)))
    return len(d) >= 13 and s % 10 == 0


def detect(text: str, thread_asks_code: bool):
    """-> (kind, masked_value, span) or None. Placeholders from the on-device redactor count as hits."""
    if m := re.search(r"<CODE:(\d+)>", text):
        return "otp", m.group(0), m.span()
    if m := re.search(r"<CARD>", text):
        return "card", "<CARD>", m.span()
    if m := re.search(r"<SSN>", text):
        return "ssn", "<SSN>", m.span()
    for m in CARD.finditer(text):
        if luhn(re.sub(r"\D", "", m.group())):
            return "card", "<CARD>", m.span()
    if m := SSN.search(text):
        return "ssn", "<SSN>", m.span()
    if GIFT.search(text) and (m := re.search(r"\b(?=[A-Z0-9-]*\d)[A-Z0-9-]{10,20}\b", text)):
        return "giftcard", "<GIFTCARD>", m.span()
    if m := PASSWD.search(text):
        return "password", "<PASSWORD>", m.span()
    if m := re.search(r"(?<![\d$.,])\d{4,8}(?![\d.,%])", text):
        if CTX.search(text) or thread_asks_code or re.fullmatch(r"\s*\d{4,8}\s*", text):
            return "otp", f"<CODE:{len(m.group())}>", m.span()
    return None


def analyze(req, intel):
    msg = target_msg(req)
    if req.mode != "outgoing_draft" and msg.direction != "out":
        return None, 0.0
    asks = any(m.direction == "in" and ASK.search(m.text) for m in req.messages)
    hit = detect(msg.text, asks)
    if not hit:
        return None, 0.0
    kind, masked, span = hit
    risky = not req.sender.isContact or asks
    score = 0.95 if risky else 0.6
    from .explain import template
    t = template("warden", dict(kind=kind))
    return mk("warden", score, t["title"], t["explanation"], [(f"{kind}_in_draft", masked, "heuristic")],
              dict(messageId="draft", field="compose"), t.get("change")), score
