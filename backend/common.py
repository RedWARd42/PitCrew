import re
from contracts.models import Anchor, Evidence, Finding, ScanRequest


def target_msg(req: ScanRequest):
    return next((m for m in req.messages if m.id == req.targetMessageId), req.messages[-1])


def incoming_text(req: ScanRequest) -> str:
    return "\n".join(m.text for m in req.messages if m.direction == "in")


def level(score: float) -> str:
    return "high" if score >= 0.7 else "medium" if score >= 0.5 else "low"


def mk(drone, score, title, expl, evidence, anchor, change=None) -> Finding:
    return Finding(drone=drone, severity=level(score), confidence=round(min(0.98, 0.55 + 0.45 * score), 2),
                   title=title[:60], explanation=expl[:280], evidence=[Evidence(kind=k, value=v, source=s) for k, v, s in evidence],
                   anchor=anchor if isinstance(anchor, Anchor) else Anchor(**anchor), whatWouldChangeMyMind=change)


def norm(text: str) -> str:
    """Classifier normalisation: URLs and digits collapsed (keeps <CODE:n> tokens readable)."""
    t = re.sub(r"https?://\S+|\b[\w-]+(\.[\w-]+)+/\S*", " urltoken ", text.lower())
    t = re.sub(r"<code:\d+>|\b\d{4,8}\b", " codetoken ", t)
    return re.sub(r"\d", "0", t)
