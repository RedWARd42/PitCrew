"""Build the salted-hash reputation bundle served at /v1/reputation/bundle."""
import csv, hashlib, os, pathlib

CSV = pathlib.Path(__file__).parent.parent / "data" / "reputation" / "numbers.csv"


def build(salt: str | None = None, path: pathlib.Path = CSV) -> dict:
    salt = salt or os.environ.get("REPUTATION_SALT", "swarm-demo-salt")
    with open(path, newline="") as f:
        hashes = sorted(hashlib.sha256((salt + r["e164"]).encode()).hexdigest() for r in csv.DictReader(f))
    return {"salt": salt, "hashes": hashes, "version": hashlib.sha256("".join(hashes).encode()).hexdigest()[:12]}


if __name__ == "__main__":
    print(build())
