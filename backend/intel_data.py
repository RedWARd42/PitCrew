"""Loads intel files from data/ once (brands, domains, reputation)."""
import csv, functools, json, pathlib
from dataclasses import dataclass

DATA = pathlib.Path(__file__).resolve().parent.parent / "data"


@dataclass
class Intel:
    brands: list
    domains: dict
    reputation: dict  # e164 -> row

    @property
    def whois(self):
        return {w["domain"]: w["createdDaysAgo"] for w in self.domains["whois"]}


@functools.lru_cache(maxsize=1)
def load() -> Intel:
    brands = json.load(open(DATA / "brands.json", encoding="utf-8"))
    domains = json.load(open(DATA / "domains.json", encoding="utf-8"))
    with open(DATA / "reputation" / "numbers.csv", newline="", encoding="utf-8") as f:
        rep = {r["e164"]: r for r in csv.DictReader(f)}
    return Intel(brands, domains, rep)
