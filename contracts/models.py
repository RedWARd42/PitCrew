"""Canonical Pydantic mirror of PLAN.md §5.2. Only the orchestrator edits this."""
from __future__ import annotations
from typing import Literal, Optional
from pydantic import BaseModel, Field

DroneId = Literal["angler", "link", "pressure", "impersonator", "warden", "drift", "carrier", "scanner"]
ActionId = Literal["report_7726", "call_official", "alert_guardian", "block_sender", "delete", "mark_safe", "dont_send", "send_anyway"]


class Sender(BaseModel):
    raw: str
    kind: Literal["long_code", "short_code", "toll_free", "email", "alphanumeric", "unknown"]
    e164: Optional[str] = None
    isContact: bool = False


class MessageIn(BaseModel):
    id: str
    direction: Literal["in", "out"]
    text: str
    ts: Optional[str] = None
    hasAttachment: Optional[bool] = None


class Redaction(BaseModel):
    type: str
    count: int


class EmailLink(BaseModel):
    text: str  # visible link text
    href: str  # real destination


class EmailAttachment(BaseModel):
    name: str


class EmailInfo(BaseModel):
    """Present when channel == "email". Body goes in messages[0].text (redacted on device)."""
    subject: str
    fromName: str
    fromAddress: str
    replyTo: Optional[str] = None
    links: list[EmailLink] = []
    attachments: list[EmailAttachment] = []


class ScanRequest(BaseModel):
    channel: Literal["sms", "email"] = "sms"
    email: Optional[EmailInfo] = None
    requestId: str
    client: Literal["android", "photon", "web"]
    mode: Literal["incoming", "outgoing_draft"]
    sender: Sender
    messages: list[MessageIn] = Field(max_length=20)
    targetMessageId: str
    locale: str = "en-US"
    redactions: list[Redaction] = []


class Evidence(BaseModel):
    kind: str
    value: str
    source: Literal["heuristic", "classifier", "reputation", "intel", "llm"]


class Anchor(BaseModel):
    messageId: str  # or "header" / "draft"
    field: Literal["sender", "body", "link", "compose"]
    span: Optional[tuple[int, int]] = None


class Finding(BaseModel):
    drone: DroneId
    severity: Literal["info", "low", "medium", "high"]
    confidence: float = Field(ge=0, le=1)
    title: str = Field(max_length=60)
    explanation: str = Field(max_length=280)
    evidence: list[Evidence] = []
    anchor: Anchor
    whatWouldChangeMyMind: Optional[str] = None


class Action(BaseModel):
    id: ActionId
    label: str
    payload: Optional[dict[str, str]] = None
    primary: Optional[bool] = None


class Category(BaseModel):
    id: str
    label: str
    source: Literal["tmobile_taxonomy", "fallback"]


class Privacy(BaseModel):
    fieldsReceived: list[str]
    retained: Literal[False] = False
    llmUsed: bool


class ScanResult(BaseModel):
    requestId: str
    verdict: Literal["scam", "suspicious", "unsure", "safe"]
    riskScore: int = Field(ge=0, le=100)
    confidence: float = Field(ge=0, le=1)
    category: Optional[Category] = None
    summary: str
    findings: list[Finding] = Field(max_length=8)
    actions: list[Action] = []
    riskSeries: Optional[list[float]] = None
    privacy: Privacy
    latencyMs: int
    modelVersion: str
