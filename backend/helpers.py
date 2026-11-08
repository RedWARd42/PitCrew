from contracts.models import ScanRequest
from . import intel_data

INTEL = intel_data.load()


def sender(raw="+14695550100", kind="long_code", contact=False):
    return dict(raw=raw, kind=kind, e164=raw if raw.startswith("+") else None, isContact=contact)


def req(text_or_msgs, snd=None, mode="incoming"):
    msgs = [("in", text_or_msgs)] if isinstance(text_or_msgs, str) else text_or_msgs
    ms = [dict(id=f"m{i}", direction=d, text=t) for i, (d, t) in enumerate(msgs)]
    return ScanRequest(requestId="t", client="android", mode=mode, sender=snd or sender(), messages=ms, targetMessageId=ms[-1]["id"])
