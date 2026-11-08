import json, pathlib
from models import ScanRequest, ScanResult
F = pathlib.Path(__file__).parent / "fixtures"
def test_fixtures():
    ScanRequest.model_validate_json((F / "scan_request_tmobile_lock.json").read_text())
    for p in F.glob("scan_result_*.json"): ScanResult.model_validate_json(p.read_text())
