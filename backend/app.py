"""Signal Swarm detection backend. Run from repo root: python -m uvicorn backend.app:app --port 8000
Never logs message text: only requestId, latency and verdict."""
import collections, logging, os
import httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from contracts.models import ScanRequest, ScanResult
from intel.build_bundle import build as build_bundle
from . import classifier, engine

log = logging.getLogger("swarm")
app = FastAPI(title="Signal Swarm backend", docs_url=None, redoc_url=None)
FEEDBACK = collections.Counter()  # aggregate counters only, in memory


@app.on_event("startup")
def _warm():
    engine.models()


@app.middleware("http")
async def auth(request: Request, call_next):
    if request.url.path != "/v1/healthz" and request.headers.get("x-swarm-key") != os.environ.get("SWARM_API_KEY", "dev-key"):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return await call_next(request)


@app.exception_handler(RequestValidationError)
async def _invalid(_, exc):  # the default handler echoes request input (message text); keep only field paths
    return JSONResponse({"error": "invalid request", "fields": [".".join(map(str, e["loc"])) for e in exc.errors()]}, status_code=422)


@app.get("/v1/healthz")
def healthz():
    return {"ok": True, "classifier": "fallback", "llm": engine.explain._llm_enabled()}


@app.post("/v1/scan", response_model=ScanResult)
def scan(req: ScanRequest):
    res = engine.scan(req)
    log.info("scan requestId=%s latencyMs=%d verdict=%s", req.requestId, res.latencyMs, res.verdict)
    return res


@app.post("/v1/guardian/alert")
def guardian_alert(body: dict):
    payload = {"to": body.get("to", os.environ.get("GUARDIAN_TO", "")), "userAlias": body.get("userAlias", ""),
               "categoryLabel": body.get("category", ""), "riskScore": body.get("riskScore", 0)}  # never message text
    try:
        r = httpx.post(os.environ.get("PHOTON_URL", "http://127.0.0.1:8787") + "/internal/guardian-alert", json=payload, timeout=2.0,
                       headers={"X-Swarm-Key": os.environ.get("SWARM_API_KEY", "dev-key")})
        return {"sent": r.is_success}
    except httpx.HTTPError:
        return {"sent": False}


@app.post("/v1/feedback", status_code=204)
def feedback(body: dict):
    if body.get("label") in ("scam", "safe"):
        FEEDBACK[body["label"]] += 1
    return Response(status_code=204)


@app.get("/v1/reputation/bundle")
def reputation_bundle():
    return build_bundle()
