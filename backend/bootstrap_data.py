"""Tiny synthetic bootstrap corpus (template-generated) used to train the fallback classifier and ensemble
until/unless data/synthetic/ provides more. All numbers are 555-01xx style; nothing here is real."""
import random

LEGIT = "legit"
CAT_LABELS = {
    "account_suspension": "Account-Suspension Smishing", "package_delivery": "Package-Delivery Smishing", "toll_payment": "Unpaid-Toll Smishing",
    "irs_gov": "Government / Tax Smishing", "bank_fraud": "Bank-Fraud Alert Smishing", "otp_request": "One-Time-Code Request",
    "crypto_investment": "Crypto / Investment Scam", "prize_gift": "Prize / Gift-Card Scam", LEGIT: "Legitimate message",
}
BRANDS = [("T-Mobile", "t-mobile"), ("Apple", "apple"), ("Amazon", "amazon"), ("PayPal", "paypal"), ("Chase", "chase"), ("Bank of America", "bankofamerica"),
          ("Wells Fargo", "wellsfargo"), ("Netflix", "netflix")]
TLDS = ["co", "top", "xyz", "icu", "click", "cfd", "live", "online", "info", "vip"]


def _scam_domain(r, slug):
    s = slug.translate(str.maketrans({"l": "1"})) if r.random() < 0.4 else slug
    mid = r.choice(["-acct-verify", "-secure-login", "-support", "-update", "-billing", "verify", "-help"])
    return f"{s}{mid}.{r.choice(TLDS)}/{r.choice('abcdefgh')}{r.randint(10, 99)}"


def _sender(r, kinds):
    k = r.choice(kinds)
    n = f"+1{r.choice(['469', '214', '312', '972'])}555{r.randint(100, 199):04d}"
    if k == "long_code":
        return dict(raw=n, kind=k, e164=n, isContact=False)
    if k == "toll_free":
        return dict(raw="+18885550" + str(r.randint(100, 199)), kind=k, e164=None, isContact=False)
    if k == "email":
        return dict(raw=f"user{r.randint(1, 99)}@mail-relay.example", kind=k, e164=None, isContact=False)
    if k == "alphanumeric":
        return dict(raw=r.choice(["INFO", "ALERT", "SUPPORT"]), kind=k, e164=None, isContact=False)
    return dict(raw=str(r.choice([611, 22000, 33789, 86753, 24273])), kind="short_code", e164=None, isContact=False)


def _req(sender, msgs, i):
    ms = [dict(id=f"m{j}", direction=d, text=t) for j, (d, t) in enumerate(msgs)]
    return dict(requestId=f"boot-{i}", client="android", mode="incoming", sender=sender, messages=ms, targetMessageId=ms[-1]["id"])


def _scam(r, cat):
    b, slug = r.choice(BRANDS)
    url = _scam_domain(r, slug)
    n = r.choice([1, 2, 4, 6, 12, 24])
    amt = r.randint(2, 900)
    T = {
        "account_suspension": [f"{b}: your account will be suspended in {n} hrs. Verify: {url}", f"{b} alert: unusual sign-in. Your line is locked. Confirm identity now {url}",
                               f"{b}: final notice, your account has been disabled. Restore access within {n} hours: {url}"],
        "package_delivery": [f"USPS: your package could not be delivered. Pay a ${r.randint(1, 3)}.99 redelivery fee: {url}", f"FedEx: parcel on hold, confirm your address today {url}",
                             f"UPS: delivery failed, reschedule within {n} hrs {url}"],
        "toll_payment": [f"E-ZPass: unpaid toll balance ${amt}. Pay within {n} hrs to avoid a late fine: {url}", f"NTTA: final notice, outstanding toll of ${amt}. Pay now {url}"],
        "irs_gov": [f"IRS: you have a pending refund of ${amt}. Claim it before it expires {url}", f"IRS final notice: unpaid tax. A warrant will be issued unless you pay today {url}"],
        "bank_fraud": [f"{b} fraud alert: a ${amt} charge was blocked. Verify your card now: {url}", f"{b}: your debit card is locked. Call 1-888-555-01{r.randint(10, 99)} or verify {url}"],
        "otp_request": ["Hi, this is support. We sent a 6 digit code to your phone. Reply with the code to cancel the request", "Oops I sent my code to your number by mistake, can you send it back to me please?",
                        f"{b} security: reply with the verification code you just received to keep your account active"],
        "prize_gift": [f"Congratulations! You won a ${amt * 5} gift card. Claim here {url}", "You have been selected for a free gift card. Reply YES to claim, act now!"],
    }
    t = r.choice(T[cat])
    return _req(_sender(r, ["long_code", "long_code", "toll_free", "email", "alphanumeric"]), [("in", t)], r.random())


def _legit(r):
    b, slug = r.choice(BRANDS)
    amt = round(r.uniform(3, 120), 2)
    code = r.randint(100000, 999999)
    kind = r.random()
    if kind < 0.45:
        t = r.choice([f"{b}: Your verification code is {code}. Don't share it with anyone.", f"{b}: Debit card ending {r.randint(1000, 9999)} was used for ${amt} at Target. Reply STOP to opt out.",
                      f"{b}: Your bill of ${amt} is ready. View it at {slug}.com/bill", f"Your {b} order has shipped. Track at {slug}.com/track",
                      f"{b}: Your code {code} expires in 10 minutes."])
        return _req(_sender(r, ["short_code"]), [("in", t)], r.random())
    if kind < 0.65:
        t = r.choice(["Reminder: dentist appointment tomorrow at 3pm. Reply C to confirm.", "Your table for 4 is confirmed tonight at 7pm. See you soon!", "Hi, your car is ready for pickup. Details at example-clinic.org/visit"])
        return _req(_sender(r, ["short_code", "long_code"]), [("in", t)], r.random())
    s = _sender(r, ["long_code"])
    s["isContact"] = r.random() < 0.7
    pre = [("out", "hey are you around?")] if r.random() < 0.5 else []
    t = r.choice(["running late, be there in 10", "dinner at 7? I can get a table", "call me asap, mom is at the hospital but she is okay", "can you venmo me $20 for the pizza?",
                  "happy birthday!! see you tonight", "did you see the game last night", "meeting moved to tomorrow, same time", "can you send me the notes by today?", "thanks! talk soon"])
    return _req(s, pre + [("in", t)], r.random())


def _ambiguous(r):
    """Wrong-number -> investment threads; real-world base rate of these being scams is high but not certain."""
    name = r.choice(["Anna", "Mark", "Lisa", "David"])
    th = [("in", f"Hi, is this {name}? We met at the conference"), ("out", "Sorry, wrong number"), ("in", "Oh sorry! You seem nice though, where are you from?"),
          ("out", "Dallas"), ("in", r.choice(["I make good returns on a crypto trading platform, my uncle taught me. Want to try?", "I do USDT investing, the profit is great. Let me show you"]))]
    return _req(_sender(r, ["long_code"]), th[: r.choice([4, 5, 5])], r.random())


def generate(seed=0, scale=1):
    """-> list of (request_dict, category_id, scam_weight_pairs) where pairs = [(label, copies)]"""
    r = random.Random(seed)
    out = []
    for cat in ["account_suspension", "package_delivery", "toll_payment", "irs_gov", "bank_fraud", "otp_request", "prize_gift"]:
        out += [(_scam(r, cat), cat, [(1, 1)]) for _ in range(70 * scale)]
    out += [(_legit(r), LEGIT, [(0, 1)]) for _ in range(500 * scale)]
    out += [(_ambiguous(r), "crypto_investment", [(1, 7), (0, 3)]) for _ in range(15 * scale)]
    return out
