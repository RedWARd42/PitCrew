"""Deterministic synthetic SMS set (stand-in for the T-Mobile set). Run: python data/synthetic/generate.py"""
import json, pathlib, random, socket, hashlib

OUT = pathlib.Path(__file__).parent
R = random.Random(26)
NAMES = ["Linda", "Marcus", "Priya", "Dan", "Sofia", "Jae", "Tom", "Aisha", "Grace", "Ben"]
BRANDS = ["T-Mobile", "Chase", "Wells Fargo", "Bank of America", "Citi", "Capital One"]
STEMS = ["verify", "secure", "acct", "update", "portal", "help", "pay", "claim", "track", "id"]
TLDS = ["co", "top", "xyz", "info", "click", "link", "support", "cc"]


def resolves(d):
    try:
        socket.gethostbyname(d)
        return True
    except OSError:
        return False


def fake_domain(brand=None):
    # shortcut: nonsense labels; any that resolve are re-rolled (offline, nothing resolves)
    while True:
        b = (brand or R.choice(["usps", "ezpass", "irs", "gift", "job", "win"])).lower().replace(" ", "")
        if R.random() < .5:
            b = b.replace("l", "1")
        d = f"{b}-{R.choice(STEMS)}-{R.choice(STEMS)}{R.randint(10, 99)}.{R.choice(TLDS)}"
        if not resolves(d):
            return d + "/" + "".join(R.choice("abcdef0123456789") for _ in range(R.choice([3, 4, 6])))


def longcode(): return f"{R.choice(['469', '214', '972', '347', '646', '305'])}555{R.randint(0, 9999):04d}"
def short(): return str(R.choice([22000, 62884, 33733, 89000, 45678, 72727, 24273]))
def email(): return f"{R.choice(['notice', 'alert', 'support'])}{R.randint(1, 99)}@{fake_domain().split('/')[0]}"


# category -> (sender fns, templates). {d}=domain {b}=brand {n}=name {x}=number {c}=6-digit code
SCAM = {
    "account_suspension": ([longcode, email], [
        "{b}: your line will be suspended in {h} hrs. Verify now: {d}",
        "{b} ALERT: unusual activity on your account. Confirm identity to avoid closure: {d}",
        "Your {b} account is locked. Restore access within {h} hours: {d}",
        "Final notice from {b}: payment method failed, service ends today. Update: {d}"]),
    "toll_ezpass": ([longcode, email], [
        "E-ZPass: you have an unpaid toll balance of ${x}. Pay within 24h to avoid a $50 fee: {d}",
        "Toll Services: final notice, outstanding toll ${x}. Late fees apply. Settle at {d}",
        "Your vehicle has an unpaid toll. Avoid license suspension, pay ${x} here: {d}"]),
    "package_delivery": ([longcode, email], [
        "USPS: your package could not be delivered, address incomplete. Reschedule: {d}",
        "Parcel #{x} on hold. Pay $1.99 redelivery fee: {d}",
        "FedEx: delivery attempt failed. Confirm your address within 12 hours: {d}"]),
    "bank_fraud": ([longcode, email], [
        "{b} Fraud Dept: suspicious charge of ${x} at ELECTRO-MART. Reply YES if you made it or call 1-833-555-{x4} now.",
        "{b}: your card was used for ${x}. If this wasn't you, call our fraud line 1-855-555-{x4} immediately.",
        "{b} security: login from new device. Secure your account: {d}"]),
    "otp_harvest": ([longcode], [
        "Hi, it's {b} support. We just texted you a code, please reply with it to confirm your identity.",
        "{b} security team: to cancel the unauthorized transfer, read us the 6-digit code you just received.",
        "Sorry, I sent my code to your number by mistake. Can you forward the 6 digit code you got? Thanks!"]),
    "giftcard_grandkid": ([longcode], [
        "Grandma it's me, I'm in trouble and need help. Please don't tell mom. Can you buy Apple gift cards and send me the codes?",
        "Hi Grandpa, I got arrested, need ${x} bail today. Buy Google Play cards and text the numbers. Please keep this secret.",
        "Hey, it's {n}, new number. Phone broke. Can you grab 4 iTunes gift cards for me? I'll pay you back, it's urgent."]),
    "irs_gov": ([longcode, email], [
        "IRS: you owe ${x} in back taxes. A warrant will be issued unless you pay today: {d}",
        "Final notice from the Tax Department. Legal action begins in {h} hours. Resolve at {d}",
        "Social Security Administration: your SSN has been suspended due to suspicious activity. Call 1-888-555-{x4}."]),
    "prize": ([longcode, email], [
        "Congratulations! You've been selected to win a ${x} gift card. Claim your prize: {d}",
        "WINNER! Your number won the weekly draw. Claim within {h} hours: {d}",
        "You qualify for a free iPhone reward. Complete the short survey: {d}"]),
    "job_offer": ([longcode], [
        "Hi {n}, we reviewed your resume. Earn ${x}/day working from home, no experience needed. Message us on WhatsApp: wa.me/1555555{x4}",
        "Remote part-time job, $200-$500 daily. Reply YES or chat on Telegram @{n}hire for details.",
        "Recruiter here: you're pre-approved for a data entry role. Start today, apply at {d}"]),
    "wrong_number_crypto": ([longcode], [
        "Hi, is this {n}? We met at the conference last week.",
        "Sorry wrong number! You seem nice though. I'm {n}, I invest in crypto, my uncle taught me.",
        "Hey {n} here again, my uncle's trading app made me ${x} this week. Want me to show you? Add me on WhatsApp.",
        "Do you want to try? Deposit just ${x} on {d} and withdraw profit tomorrow, guaranteed."]),
    "romance": ([longcode, email], [
        "Hello dear, I saw your profile and felt a connection. I'm deployed overseas. Can we chat on Telegram?",
        "My love, I need ${x} for my flight home, can you send via gift card or wire? I will repay you.",
        "I never felt this way before. Please keep us private, my family wouldn't understand. Send help with the fee?"]),
}
LEGIT = {
    "bank_alert": ([short], [
        "{b}: a ${x} purchase was made on your card ending 4821. Not you? Call the number on your card.",
        "{b}: Your statement is ready. Sign in to the app to view it.",
        "{b} Alert: low balance on checking ending 3307. Reply STOP to opt out."]),
    "pharmacy": ([short], [
        "CVS Pharmacy: your prescription is ready for pickup at Main St. Reply STOP to opt out.",
        "Walgreens: refill reminder for your prescription. Reply 1 to refill.",
        "Your prescription #{x} is ready. Store closes at 9pm."]),
    "twofa": ([short], [
        "Your verification code is {c}. Do not share this code with anyone.",
        "{b}: {c} is your login code. It expires in 10 minutes. We will never ask for it.",
        "Your Google verification code is G-{c}."]),
    "friend": ([longcode], [
        "Hey, are we still on for dinner at 7? Also check this out https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "lol just saw your message, running 10 min late",
        "Mom says call her when you get a chance. Love you!",
        "Can you send me the address for Saturday? Here's the playlist: https://open.spotify.com/playlist/abc",
        "Did you see the game last night?? unreal"]),
    "delivery_notice": ([short], [
        "Amazon: Your package was delivered to your front door. Order #{x}.",
        "UPS: package arriving today between 2-6pm. Track at ups.com with your tracking number.",
        "Your DoorDash order from Taco Bell is on its way."]),
    "appointment": ([short, longcode], [
        "Reminder: you have an appointment with Dr. Smith tomorrow at 3:30pm. Reply C to confirm.",
        "Dental Care: your cleaning is scheduled for Friday 10am. Reply STOP to opt out.",
        "Your haircut at 2pm today is confirmed. See you soon!"]),
}


def fill(t):
    b = R.choice(BRANDS)
    dom = fake_domain(b if "T-Mobile" in t else None) if "{d}" in t else ""
    return t.format(d=dom, b=b, n=R.choice(NAMES), h=R.choice([1, 2, 4, 12, 24]), x=R.randint(3, 900),
                    x4=f"{R.randint(0, 9999):04d}", c=R.randint(100000, 999999))


def build(n_scam=950, n_legit=900):
    rows = []
    for label, cats, n in (("scam", SCAM, n_scam), ("legit", LEGIT, n_legit)):
        keys = sorted(cats)
        for i in range(n):
            k = keys[i % len(keys)]
            senders, tmpl = cats[k]
            text = fill(R.choice(tmpl))
            if label == "legit" and R.random() < .6:  # extra variety so legit isn't template-capped
                text += R.choice([" Ref {0}.", " Thanks, {1}!", " Msg ID {0}."]).format(R.randint(100, 99999), R.choice(NAMES))
            rows.append({"text": text, "sender": R.choice(senders)(), "label": label, "category": k})
    seen, out = set(), []
    for r in rows:
        r["id"] = "s" + hashlib.sha1((r["text"] + r["sender"]).encode()).hexdigest()[:10]
        if r["id"] not in seen:  # drop identical text+sender duplicates
            seen.add(r["id"])
            out.append(r)
    R.shuffle(out)
    return [{k: r[k] for k in ("id", "text", "sender", "label", "category")} for r in out]


def main():
    rows = build()

    def dump(name, rs):
        (OUT / name).write_text("".join(json.dumps(r) + "\n" for r in rs), encoding="utf-8")

    dump("all.jsonl", rows)
    a, b = int(len(rows) * .70), int(len(rows) * .85)
    dump("train.jsonl", rows[:a]); dump("val.jsonl", rows[a:b]); dump("test.jsonl", rows[b:])
    print(len(rows), "rows;", sum(r["label"] == "legit" for r in rows), "legit")


if __name__ == "__main__":
    main()
