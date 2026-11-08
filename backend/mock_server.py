import json, pathlib
from fastapi import FastAPI
F = pathlib.Path(__file__).parent.parent / "contracts" / "fixtures"
app = FastAPI()
def load(n): return json.loads((F / f"{n}.json").read_text())
@app.get("/v1/healthz")
def health(): return {"ok": True, "classifier": "fallback", "llm": False}
@app.post("/v1/scan")
def scan(req: dict):
    t = " ".join(m["text"] for m in req["messages"]).lower()
    name = "scan_result_tmobile_lock" if "t-mobile" in t or "t-mobi" in t else "scan_result_warden_otp" if "code" in t else "scan_result_safe_bank"
    return {**load(name), "requestId": req["requestId"]}
@app.post("/v1/guardian/alert")
def alert(_: dict): return {"sent": True}
@app.post("/v1/feedback", status_code=204)
def fb(_: dict): return None
