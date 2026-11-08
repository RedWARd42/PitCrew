"""Writes scenarios/email/*.yaml, dummy attachments, and data/synthetic/emails.jsonl. Run: python data/synthetic/gen_emails.py"""
import json, pathlib, random, socket, yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
ED = ROOT / "scenarios/email"
R = random.Random(26)
P, L = "scam", "safe"


def S(id, desc, name, addr, subj, body, expect, drones=(), reply_to=None, att=(), to="you@example.com"):
    return dict(id=id, desc=desc, from_name=name, from_address=addr, reply_to=reply_to, to=to, subject=subj, body=body,
                attachments=list(att), expect=dict(verdict=expect, drones=list(drones)))


SC = [
 S("paypal_lookalike", "PayPal lookalike, reply-to mismatch, html attachment", "PayPal Support", "security@paypa1-support.com",
   "Your account is limited - verify within 24 hours",
   "Dear customer,\n\nWe noticed unusual activity. Verify your account within 24 hours or it will be permanently limited.\n\n[https://paypa1-support.com/verify](https://paypa1-support.com/verify)\n\nSee attached form.",
   P, ["angler", "link", "pressure", "impersonator", "carrier"], "help@mailbox-relay.biz", ["invoice_4491.html"]),
 S("paypal_text_href_mismatch", "Visible text is real paypal.com, href differs; only detectable server-side (Photon path), Gmail on-device a11y never exposes href", "PayPal Support", "security@paypa1-support.com",
   "Your account is limited - verify within 24 hours",
   "Dear customer,\n\nWe noticed unusual activity. Verify your account within 24 hours or it will be permanently limited.\n\n[https://www.paypal.com/verify](https://paypa1-support.com/login?id=88a)\n\nSee attached form.",
   P, ["angler", "link", "pressure", "impersonator"], "help@mailbox-relay.biz"),
 S("m365_password_expiry", "Microsoft 365 password expiry", "Microsoft 365 Admin", "no-reply@secure-micros0ft-365.net",
   "Password expires today - action required",
   "Your Microsoft 365 password expires in 2 hours. Keep your current password:\n\n[Keep my password](https://secure-micros0ft-365.net/login)\n\nIT Service Desk",
   P, ["angler", "link", "pressure", "impersonator"]),
 S("docusign_lure", "DocuSign lure", "DocuSign via HR", "dse@docusgn-secure-sign.click",
   "Completed: Salary Revision 2026 - please review and sign",
   "HR has sent you a document to review and sign.\n\n[REVIEW DOCUMENT](https://docusgn-secure-sign.click/s/91ab)\n\nDo not forward this email.",
   P, ["angler", "link", "impersonator"]),
 S("ceo_giftcards", "CEO gift-card request from free-mail", "Jordan Reyes (CEO)", "jordan.reyes.ceo@gmail.com",
   "Quick favor - urgent",
   "Are you at your desk? I am in a meeting and cannot talk. I need 4 x $100 Apple gift cards for clients today. Buy them and send me the codes. I will reimburse you. Keep this between us.\n\nJordan",
   P, ["angler", "pressure", "impersonator"], "jreyes.office@outlook-mailer.cc"),
 S("invoice_macro", "Invoice with macro document", "Accounts Receivable", "billing@northwind-invoices.xyz",
   "Overdue invoice INV-20877 - payment required",
   "Please find the overdue invoice attached. Enable editing and content to view it. Payment is required today to avoid a late fee.",
   P, ["angler", "pressure", "carrier"], None, ["INV-20877.docm"]),
 S("bank_limited", "Bank account limited", "Chase Alerts", "alerts@chase-secure-login.info",
   "Your account has been limited",
   "We limited your account after suspicious sign-in attempts. Restore access now:\n\n[chase.com/restore](https://chase-secure-login.info/restore?s=77)\n\nFailure to act within 12 hours will result in closure.",
   P, ["angler", "link", "pressure", "impersonator"]),
 S("shipping_shortener", "Shipping notice with shortener link", "UPS Delivery", "tracking@ups-parcel-notice.top",
   "Package on hold - address confirmation needed",
   "Your parcel could not be delivered. Confirm your address and pay a $1.99 redelivery fee:\n\n[Track your package](https://bit.ly/3xK9fakeUPS)",
   P, ["angler", "link", "pressure", "impersonator"]),
 S("dropbox_lookalike", "Dropbox share lookalike", "Dropbox", "share@dropb0x-share.co",
   "Maria shared Q3 Payroll.pdf with you",
   "Maria Lopez shared a file with you.\n\n[Open Q3 Payroll.pdf](https://dropb0x-share.co/s/8Qa)\n\nSign in with your work email to view.",
   P, ["angler", "link", "impersonator"]),
 S("legit_github", "Real GitHub notification", "GitHub", "notifications@github.com",
   "[acme/api] Pull request #412: Fix retry backoff (merged)",
   "@sam-dev merged #412 into main.\n\n[View pull request](https://github.com/acme/api/pull/412)\n\nYou are receiving this because you were mentioned.",
   L),
 S("legit_newsletter", "Newsletter via known ESP", "Morning Brew", "crew@morningbrew.com",
   "Your Monday briefing",
   "Markets open mixed. Read the full story:\n\n[Read online](https://www.morningbrew.com/daily/stories/2026/11/08)\n\n[Unsubscribe](https://www.morningbrew.com/unsubscribe)", L),
 S("legit_meeting_invite", "Internal meeting invite", "Priya Nair", "priya.nair@example.com",
   "Invitation: Sprint planning @ Tue 10:00",
   "Hi team, sprint planning is Tuesday at 10:00 in Room 4B.\n\n[Join with Google Meet](https://meet.google.com/abc-defg-hij)\n\nAgenda attached.", L, att=["agenda.pdf"]),
 S("legit_order_receipt", "Real order receipt", "Amazon.com", "auto-confirm@amazon.com",
   "Your order #112-5550123-4412 has shipped",
   "Your package will arrive Thursday.\n\n[Track package](https://www.amazon.com/progress-tracker/package/112-5550123)\n\nThanks for shopping with us.", L),
 S("legit_bank_statement", "Real bank statement notice", "Chase", "no-reply@alerts.chase.com",
   "Your statement is ready",
   "Your October statement is available. Sign in at chase.com to view it. We never ask for your password by email.", L),
]

ED.mkdir(parents=True, exist_ok=True)
import re
for s in SC:
    if s["expect"]["verdict"] == "scam" and s["id"] != "paypal_text_href_mismatch":
        s["body"] = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: f"[{m.group(2)}]({m.group(2)})", s["body"])
    (ED / f"{s['id']}.yaml").write_text(yaml.safe_dump(s, sort_keys=False, allow_unicode=True), encoding="utf-8")
    for a in s["attachments"]:  # harmless dummy payloads
        d = ED / "attachments"
        d.mkdir(exist_ok=True)
        (d / a).write_text(f"Harmless dummy attachment for Signal Swarm testing: {a}\n", encoding="utf-8")


def dead(d):
    try:
        socket.gethostbyname(d)
    except OSError:
        return True
    return False


BR = [("PayPal", "paypal.com", "paypa1"), ("Microsoft", "microsoft.com", "micros0ft"), ("DocuSign", "docusign.com", "docusgn"),
      ("Chase", "chase.com", "chas3"), ("Dropbox", "dropbox.com", "dr0pbox"), ("UPS", "ups.com", "ups"), ("Netflix", "netflix.com", "netfl1x")]
TLD = ["top", "xyz", "click", "link", "info", "cc"]
STEM = ["secure", "verify", "login", "support", "acct", "portal"]


def dom(b):
    while True:
        d = f"{b[2]}-{R.choice(STEM)}{R.randint(10, 99)}.{R.choice(TLD)}"
        if dead(d):
            return d


scam_t = [("Your {B} account is limited", "We limited your account. Verify within {H} hours or it will be closed. {real}/verify", ["angler", "link", "pressure", "impersonator"]),
          ("{B}: password expires today", "Your {B} password expires in {H} hours. Keep it by signing in at {real}", ["angler", "link", "pressure", "impersonator"]),
          ("{B} document shared with you", "A document was shared with you. Open it at {real}", ["angler", "link", "impersonator"])]
legit_t = [("Your {B} receipt", "Thanks for your purchase. View your receipt at {real}"),
           ("{B} security notice", "We noticed a sign-in from a new device. If this was you, no action is needed. Visit {real} to review activity."),
           ("Your {B} statement is ready", "Your statement is ready. Sign in at {real} to view it.")]
rows = []
for i in range(170):
    b, t, d = R.choice(BR), R.choice(scam_t), None
    d = dom(b)
    free = R.random() < .3
    addr = "support@gmail.com" if free else f"no-reply@{d}"
    rt = f"help@{dom(b)}" if R.random() < .4 else None
    drones = list(t[2]) + (["angler"] if rt and "angler" not in t[2] else [])
    rows.append(dict(id=f"em-s{i:03d}", label="scam", category="phish", fromName=f"{b[0]} Support", fromAddress=addr, replyTo=rt,
                     subject=t[0].format(B=b[0]), text=t[1].format(B=b[0], H=R.choice([2, 12, 24, 48]), real=b[1]),
                     links=[(lambda h: dict(text=h, href=h))(f"https://{d}/l/{R.randint(100, 999)}")],
                     attachments=[dict(name="form.html")] if R.random() < .2 else [], drones=drones))
for i in range(130):
    b, t = R.choice(BR), R.choice(legit_t)
    rows.append(dict(id=f"em-l{i:03d}", label="legit", category="legit", fromName=b[0], fromAddress=f"no-reply@{b[1]}", replyTo=None,
                     subject=t[0].format(B=b[0]), text=t[1].format(B=b[0], real=b[1]),
                     links=[dict(text=f"https://www.{b[1]}/account", href=f"https://www.{b[1]}/account/{R.randint(100, 999)}")],
                     attachments=[], drones=[]))
R.shuffle(rows)
(ROOT / "data/synthetic/emails.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
print(len(SC), "scenarios,", len(rows), "rows")
