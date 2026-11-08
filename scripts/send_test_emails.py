#!/usr/bin/env python
"""Send test emails via SMTP. Creds come from env only: SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS (never stored).
python scripts/send_test_emails.py --list | <scenario>|--all --to you@gmail.com [--dry-run]
Gmail: SMTP_HOST=smtp.gmail.com SMTP_PORT=587 SMTP_USER=you@gmail.com SMTP_PASS=<app password>"""
import argparse, os, smtplib, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import emaillib


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", nargs="?")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--to")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    sc = emaillib.load_all()
    if a.list:
        for k, s in sc.items():
            print(f"{k:24} {len(s['attachments'])} att  expect={s['expect']['verdict']:5} {s['subject'][:50]}")
        return
    if not (a.scenario or a.all):
        ap.error("scenario, --all or --list required")
    if not a.to:
        ap.error("--to required")
    pick = list(sc) if a.all else [a.scenario]
    if a.scenario and a.scenario not in sc:
        sys.exit(f"unknown scenario '{a.scenario}' (try --list)")
    msgs = [emaillib.build(sc[k], a.to) for k in pick]
    if a.dry_run:
        for m in msgs:
            print(m.as_string() if len(msgs) == 1 else f"--- {m['Subject']} (From {m['From']}, Reply-To {m['Reply-To']})")
        return
    miss = [v for v in ("SMTP_HOST", "SMTP_PORT", "SMTP_USER", "SMTP_PASS") if not os.environ.get(v)]
    if miss:
        sys.exit(f"set env vars: {', '.join(miss)}")
    with smtplib.SMTP(os.environ["SMTP_HOST"], int(os.environ["SMTP_PORT"]), timeout=30) as c:
        c.starttls()
        c.login(os.environ["SMTP_USER"], os.environ["SMTP_PASS"])
        for m in msgs:
            c.send_message(m)  # note: Gmail rewrites From to the authenticated account; see make_eml.py for exact headers
            print("sent", m["Subject"])
            time.sleep(1)


if __name__ == "__main__":
    main()
