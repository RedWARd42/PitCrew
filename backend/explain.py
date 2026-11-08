"""Templated explanations (default, offline) + optional LLM rewrite.
The LLM only rewrites text fields; severity, confidence, verdict and evidence are never touched."""
import json, os
import httpx
from contracts.models import Finding

STAGE_TXT = {"rapport": "friendly small talk", "off_platform": "a move to another app", "money": "talk of money or crypto"}
WARDEN = {
    "otp": ("This code unlocks your account", "A one-time code lets whoever has it into your account. Real companies never ask you to text it back."),
    "card": ("That looks like a card number", "Anyone who gets this number can charge it. Only share it on a payment page you opened yourself."),
    "ssn": ("That looks like a Social Security number", "A Social Security number sent by text can be used to open accounts in your name."),
    "giftcard": ("Gift card code in your message", "Gift card codes work like cash. Scammers ask for them because they cannot be traced or refunded."),
    "password": ("You are about to send a password", "Anyone who reads this text can sign in as you. Share passwords only through a password manager."),
}


def template(drone: str, f: dict) -> dict:
    if drone == "angler_email":
        if f.get("brand"):
            e = f"The name says {f['brand']}, but the email comes from '{f['domain']}', which is not {f['brand']}'s."
        elif f.get("exec"):
            e = f"This asks for money or favors from a free email address ({f['domain']}). Bosses and banks do not do that."
        else:
            e = f"The sender's address uses '{f['domain']}', which looks suspicious."
        if f.get("reply"):
            e += f" Replies would go to a different place ({f['reply']})."
        return dict(title="Sender is not who it claims" if f.get("brand") else "Suspicious sender address", explanation=e,
                    change="If the address really belongs to the company and you were expecting this email, I would trust it more.")
    if drone == "link_email":
        if f.get("mismatch"):
            return dict(title="Link goes somewhere else", explanation=f"The link says '{f['shown']}' but really opens '{f['real']}'. Scammers hide the real address this way.",
                        change="If the real address is the company's own site, it is fine.")
    if drone == "carrier":
        why = {"danger": "can run programs on your computer", "web": "can open a fake login page on your computer", "archive": "can hide harmful files inside", "macro": "can run hidden macros"}[f["risk"]]
        return dict(title="Risky attachment"[:60], explanation=f"'{f['name']}' is a file type that {why}." + (" Invoice-style names are a common lure." if f.get("lure") else ""),
                    change="If you were expecting this exact file from someone you trust, ask them before opening.")
    if drone == "angler":
        who = {"long_code": "a 10-digit number", "email": "an email gateway", "alphanumeric": "a text-only sender name", "toll_free": "a toll-free number"}.get(f["kind"], "a sender")
        title = "First-time sender, " + f["kind"].replace("_", " ") if f.get("first_time") else "Unfamiliar sender"
        if f.get("brand"):
            e = f"Real {f['brand']} alerts come from short codes, not {who} you have never texted."
        else:
            e = f"This came from {who} you have not texted before."
        if f.get("complaints"):
            e += f" It has {f['complaints']} complaints on file (reported by consumers, unverified)."
        return dict(title=title, explanation=e, change="If this came from a known short code or someone in your contacts, I would trust it more.")
    if drone == "link":
        if f.get("brand"):
            e = f"'{f['rd']}' imitates {f['bdom']} with swapped or added characters."
            if f.get("age") is not None:
                e += f" The site was registered {f['age']} days ago."
            return dict(title="Lookalike domain", explanation=e, change=f"If the link were on {f['bdom']} itself, I would trust it more.")
        if f.get("punycode"):
            return dict(title="Disguised web address", explanation=f"'{f['rd']}' uses special characters that can imitate a real site.", change="If you recognise this exact site, it may be fine.")
        if f.get("age") is not None and f["age"] < 30:
            return dict(title="Brand-new website", explanation=f"'{f['rd']}' was registered only {f['age']} days ago. Scam sites are usually new.", change="A site that has existed for years would lower my concern.")
        if f.get("shortener"):
            return dict(title="Hidden destination", explanation=f"'{f['rd']}' is a link shortener, so you cannot see where it leads.", change="If you know who sent it and what it is, it is likely fine.")
        return dict(title="Unusual link", explanation=f"'{f['rd']}' ends in '.{f['tld']}', a type of address common in scams.", change="If this is a site you already use, it may be fine.")
    if drone == "pressure" and not f.get("phrase"):
        return dict(title="Matches a known scam pattern", explanation=f"The wording closely matches messages seen in scams of this kind: {f['label']}.", change="If you were expecting this exact request, it may be genuine.")
    if drone == "pressure":
        return dict(title="Pressure to act fast", explanation=f"'{f['phrase']}' is meant to make you act before you think. Real companies give you time and a number you can call.", change="A message that gives you time and does not threaten you would lower my concern.")
    if drone == "impersonator":
        call = f" Call the real {f['brand']}: {f['phone']}." if f.get("phone") else f" Contact {f['brand']} through its official app or website, not this message."
        return dict(title=f"Pretends to be {f['brand']}"[:60], explanation=f"The {f['brand']} name appears but the sender and link are not {f['brand']}'s." + call,
                    change=f"If this came from a known {f['brand']} short code with a {f['brand']} link, I would trust it more.")
    if drone == "warden":
        t, e = WARDEN[f["kind"]]
        return dict(title=t, explanation=e, change="If you started this conversation and trust the person, sending may be fine.")
    if drone == "drift":
        steps = ", then ".join(STAGE_TXT.get(s, s) for s in f["stages"])
        return dict(title="Conversation is escalating", explanation=f"This thread moved from {steps}. That pattern is common in wrong-number and investment scams.", change="If you know this person, the pattern may be innocent.")
    return dict(title="Heads up", explanation="Something about this message looks off.")


SUMMARY = {
    "scam": "This text looks like a scam. Do not tap links or reply.",
    "suspicious": "This looks suspicious. Be careful before replying or tapping anything.",
    "unsure": "Not sure about this one. Check with the sender another way.",
    "safe": "Looks like a normal message.",
}


def summary(verdict, category_label, brand, mode, findings, noun="text") -> str:
    return _summary(verdict, brand, mode, findings).replace("text", noun)


def _summary(verdict, brand, mode, findings) -> str:
    if mode == "outgoing_draft":
        return "You're about to send sensitive information." if findings else "Nothing risky in this draft."
    if verdict in ("scam", "suspicious") and brand:
        return f"This text pretends to be {brand} and pushes you to act." if verdict == "scam" else f"This text mentions {brand} but has warning signs."
    return SUMMARY[verdict]


def _llm_enabled() -> bool:
    return os.environ.get("LLM_DISABLED", "1") == "0" and bool(os.environ.get("ANTHROPIC_API_KEY"))


def llm_rewrite(findings: list[Finding], redacted_text: str, category: str | None):
    """Return (findings, used). Any failure or timeout -> unchanged findings, False."""
    if not findings or not _llm_enabled():
        return findings, False
    prompt = ("Rewrite scam-warning copy for a non-technical reader. Use ONLY the evidence given; do not state facts not present in evidence. "
              'Reply with strict JSON: {"<drone>": {"title": str(<=60), "explanation": str(<=280), "whatWouldChangeMyMind": str}}.\n'
              + json.dumps({"category": category, "text": redacted_text, "findings": {f.drone: [e.model_dump() for e in f.evidence] for f in findings}}))
    try:
        r = httpx.post("https://api.anthropic.com/v1/messages", timeout=1.2,
                       headers={"x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01"},
                       json={"model": os.environ.get("LLM_MODEL", "claude-haiku-5-5"), "max_tokens": 600, "messages": [{"role": "user", "content": prompt}]})
        data = json.loads(r.json()["content"][0]["text"])
        out = []
        for f in findings:
            d = data[f.drone]
            out.append(Finding.model_validate({**f.model_dump(), "title": d["title"], "explanation": d["explanation"],
                                               "whatWouldChangeMyMind": d.get("whatWouldChangeMyMind") or f.whatWouldChangeMyMind}))
        return out, True
    except Exception:
        return findings, False
