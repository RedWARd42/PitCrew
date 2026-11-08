#!/usr/bin/env python
"""Play a scenario into the Android emulator: python scripts/inject.py <id> | --list | --call <number>"""
import argparse, pathlib, subprocess, sys, time
import yaml

SC = pathlib.Path(__file__).resolve().parent.parent / "scenarios"


def load(sid):
    p = SC / f"{sid}.yaml"
    if not p.exists():
        sys.exit(f"unknown scenario '{sid}' (try --list)")
    return yaml.safe_load(p.read_text(encoding="utf-8"))


def adb(args, dry=False):
    if dry:
        print("  $ adb", " ".join(args))
        return ""
    r = subprocess.run(["adb", *args], capture_output=True, text=True)
    if r.returncode or "KO" in r.stdout:
        sys.exit(f"adb failed: {r.stdout.strip()} {r.stderr.strip()}")
    return r.stdout


def sms(sender, text, dry=False):
    # emulator console takes one line; subprocess list avoids shell quoting, only newlines need flattening
    adb(["emu", "sms", "send", sender, " ".join(text.split())], dry)


def call(number, dry=False):
    adb(["emu", "gsm", "call", number], dry)


def run(sid, dry=False, speed=1.0):
    sc = load(sid)
    print(f"[{sid}] {sc.get('desc', '')} expect={sc['expect']}")
    for i, st in enumerate(sc["steps"], 1):
        time.sleep(0 if dry else st.get("delay", 0) / speed)
        if "call" in st:
            print(f" step {i}: CALL {st['call']}"); call(str(st["call"]), dry)
        elif "text" in st:
            snd = str(st.get("sender", sc["sender"]))
            print(f" step {i}: SMS from {snd}: {st['text'][:70]}"); sms(snd, st["text"], dry)
        if "user_reply" in st:
            print(f" step {i}: PRESENTER CUE -> type '{st['user_reply']}' in the reply box. {st.get('note', '')}")
        if "type" in st:  # best effort, adb input text needs %s for spaces
            adb(["shell", "input", "text", st["type"].replace(" ", "%s")], dry)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", nargs="?")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--call", metavar="NUMBER")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--speed", type=float, default=1.0)
    a = ap.parse_args()
    if a.list:
        for p in sorted(SC.glob("*.yaml")):
            s = yaml.safe_load(p.read_text(encoding="utf-8"))
            print(f"{s['id']:28} {len(s['steps'])} step(s)  expect={s['expect']['verdict']}")
    elif a.call:
        call(a.call, a.dry_run)
    elif a.scenario:
        run(a.scenario, a.dry_run, a.speed)
    else:
        ap.error("scenario, --list or --call required")


if __name__ == "__main__":
    main()
