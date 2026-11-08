import csv, json, pathlib
from intel.build_bundle import build

D = pathlib.Path(__file__).parent.parent / "data"


def test_brands_schema():
    brands = json.load(open(D / "brands.json"))
    assert len(brands) >= 15
    for b in brands:
        assert {"brand", "aliases", "domains", "shortCodes", "officialPhone", "officialUrl", "verified", "sourceUrl"} <= b.keys()
        assert b["domains"]
    ver = [b for b in brands if b["verified"]]
    assert [b["brand"] for b in ver] == ["T-Mobile"] and ver[0]["officialPhone"] == "611" and ver[0]["sourceUrl"]


def test_domains_schema():
    d = json.load(open(D / "domains.json"))
    assert {"brandDomains", "shorteners", "riskyTlds", "whois"} <= d.keys()
    assert {w["domain"]: w["createdDaysAgo"] for w in d["whois"]}["t-mobi1e-acct-verify.co"] == 3


def test_numbers_and_bundle():
    rows = list(csv.DictReader(open(D / "reputation" / "numbers.csv")))
    assert rows and all(r["e164"].startswith("+") and r["source"] == "synthetic" for r in rows)
    b = build("s")
    assert len(b["hashes"]) == len(rows) and b["salt"] == "s"


def test_hero_scenario_resolvable():
    d = json.load(open(D / "domains.json"))
    assert "+14695550182" in open(D / "reputation" / "numbers.csv").read()
    assert any(w["domain"] == "t-mobi1e-acct-verify.co" for w in d["whois"])
