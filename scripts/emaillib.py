"""Shared email scenario helpers: load, render markdown-ish links to HTML, build EmailMessage."""
import html, pathlib, re
from email.message import EmailMessage
from email.utils import formataddr, formatdate, make_msgid
import yaml

ED = pathlib.Path(__file__).resolve().parent.parent / "scenarios/email"
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def load_all():
    return {p.stem: yaml.safe_load(p.read_text(encoding="utf-8")) for p in sorted(ED.glob("*.yaml"))}


def links(body):
    return [dict(text=t, href=h) for t, h in LINK.findall(body)]


def plain(body):  # visible text only
    return LINK.sub(lambda m: m.group(1), body)


def to_html(body):  # real href differs from visible text where the scenario says so
    esc = html.escape(body)
    esc = LINK.sub(lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>', esc)
    return "<html><body>" + "".join(f"<p>{p.replace(chr(10), '<br>')}</p>" for p in esc.split("\n\n")) + "</body></html>"


def build(s, to=None):
    m = EmailMessage()
    m["From"] = formataddr((s["from_name"], s["from_address"]))
    m["To"] = to or s.get("to") or "you@example.com"
    if s.get("reply_to"):
        m["Reply-To"] = s["reply_to"]
    m["Subject"] = s["subject"]
    m["Date"] = formatdate(localtime=True)
    m["Message-ID"] = make_msgid(domain="swarm-test.invalid")
    m.set_content(plain(s["body"]))
    m.add_alternative(to_html(s["body"]), subtype="html")
    for a in s.get("attachments", []):
        f = ED / "attachments" / a
        m.add_attachment(f.read_bytes(), maintype="application", subtype="octet-stream", filename=a)
    return m
