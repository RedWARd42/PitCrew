"""Link drone: URL extraction, lookalike / punycode / shortener / TLD / domain-age checks."""
import re
from contracts.models import ScanRequest
from .common import mk, target_msg

URL_RE = re.compile(
    r"(?i)(?<![\w@.\-])((?:https?://)?(?:www\.)?(?:(?:[a-z0-9¡-￿](?:[a-z0-9¡-￿-]*[a-z0-9¡-￿])?\.)+[a-z¡-￿]{2,24}"
    r"|\d{1,3}(?:\.\d{1,3}){3}))(?::\d+)?(/[^\s<>\"']*)?")
HOMO = str.maketrans({"1": "l", "0": "o", "5": "s", "3": "e", "$": "s", "@": "a", "!": "i"})


def _lev(a: str, b: str) -> int:
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[-1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def reg_domain(host: str) -> str:
    p = host.split(".")
    return ".".join(p[-3:] if len(p) >= 3 and len(p[-1]) == 2 and p[-2] in {"co", "com", "org", "net", "gov", "ac"} else p[-2:])


def extract_urls(text: str, intel):
    """-> [(host, full_url_text, (start, end))]"""
    d = intel.domains
    tlds = set(d["commonTlds"]) | set(d["riskyTlds"]) | {x.rsplit(".", 1)[1] for x in d["brandDomains"] + d["shorteners"]}
    out = []
    for m in URL_RE.finditer(text):
        s, e = m.start(), m.end()
        while e > s and text[e - 1] in ".,;:!?)]":
            e -= 1
        full = text[s:e]
        host = m.group(1).lower().removeprefix("https://").removeprefix("http://").removeprefix("www.")
        if not (full.lower().startswith(("http", "www.")) or m.group(2) or host.rsplit(".", 1)[-1] in tlds or host.startswith("xn--")):
            continue
        out.append((host, full, (s, e)))
    return out


def _is_brand_host(host, intel):
    return any(host == d or host.endswith("." + d) for b in intel.brands for d in b["domains"])


def lookalike(rd: str, intel):
    """Return the brand dict if registered domain `rd` imitates a brand domain, else None."""
    name = rd.split(".")[0]
    nn = name.translate(HOMO).replace("rn", "m").replace("vv", "w")
    for b in intel.brands:
        for d in b["domains"]:
            bn = d.split(".")[0]
            if rd == d or len(bn) < 3:
                continue
            variants = {bn, bn.replace("-", "")}
            toks = set(nn.split("-")) | set(name.split("-"))
            if len(bn) < 5:  # short names ("ups", "irs"): whole-token matches only
                if bn in toks:
                    return b
                continue
            forms = (nn, nn.replace("-", ""), name)
            if any(v in c for v in variants for c in forms):
                return b
            tol = 2 if len(bn) >= 10 else 1
            cands = {nn, nn.replace("-", "")} | toks
            if any(_lev(v, c) <= tol for v in variants for c in cands if len(c) >= 5):
                return b
    return None


def score_url(host: str, full: str, intel):
    """-> (score, evidence, brand|None, age_days|None) for one URL host; brand-owned hosts score 0."""
    rd = reg_domain(host)
    if _is_brand_host(host, intel):
        return 0.0, [], None, None
    ev, score = [], 0.0
    b = lookalike(rd, intel)
    age = intel.whois.get(rd)
    tld = rd.rsplit(".", 1)[-1]
    path = full.split("/", 1)[1].lower() if "/" in full.replace("://", "") else ""
    if b:
        score = 1.0
        ev.append(("lookalike", f"{rd} ~ {b['domains'][0]}", "intel"))
    if host.startswith("xn--") or ".xn--" in host:
        score = max(score, 0.9)
        ev.append(("punycode", host, "intel"))
    if re.fullmatch(r"\d+(\.\d+){3}", host):
        score = max(score, 0.8)
        ev.append(("ip_host", host, "heuristic"))
    if age is not None and age < 30:
        score = max(score, 0.8)
        ev.append(("domain_age_days", str(age), "intel"))
    if rd in intel.domains["shorteners"]:
        score = max(score, 0.5)
        ev.append(("shortener", rd, "intel"))
    if tld in intel.domains["riskyTlds"]:
        score = max(score, 0.45)
        ev.append(("risky_tld", "." + tld, "intel"))
    kw = [k for k in intel.domains["pathKeywords"] if k in (path + "-" + rd).lower()]
    if kw and score:
        score = min(1.0, score + 0.1)
        ev.append(("path_keyword", kw[0], "heuristic"))
    return (score or 0.15), ev, b, age  # 0.15 = plain unknown domain: not worth a finding


def link_template(host, b, age, intel):
    from .explain import template
    rd = reg_domain(host)
    return template("link", dict(rd=rd, brand=b and b["brand"], bdom=b and b["domains"][0], age=age, tld=rd.rsplit(".", 1)[-1],
                                 shortener=rd in intel.domains["shorteners"], punycode=host.startswith("xn--")))


def analyze(req: ScanRequest, intel):
    msg = target_msg(req)
    best = (0.0, None)
    for host, full, span in extract_urls(msg.text, intel):
        score, ev, b, age = score_url(host, full, intel)
        if score > best[0]:
            best = (score, (host, b, age, span, ev))
    score, info = best
    if info is None or score < 0.4:
        return None, score
    host, b, age, span, ev = info
    t = link_template(host, b, age, intel)
    return mk("link", score, t["title"], t["explanation"], ev, dict(messageId=msg.id, field="link", span=span), t.get("change")), score
