from contracts.models import Action


def build_actions(verdict: str, brand: dict | None, mode: str = "incoming", channel: str = "sms") -> list[Action]:
    if mode == "outgoing_draft":
        return [Action(id="dont_send", label="Don't send", primary=True), Action(id="send_anyway", label="Send anyway")] if verdict != "safe" else []
    if verdict in ("scam", "suspicious"):
        email = channel == "email"
        a = [Action(id="report_7726", label="Report phishing" if email else "Report to 7726", primary=True)]
        if brand and brand.get("verified") and brand.get("officialPhone"):  # never offer an unverified number
            a.append(Action(id="call_official", label=f"Call real {brand['brand']}", payload={"number": brand["officialPhone"]}))
        a.append(Action(id="alert_guardian", label="Alert my guardian"))
        return a + ([] if email else [Action(id="block_sender", label="Block sender")]) + [Action(id="delete", label="Delete")]
    if verdict == "unsure":
        return [Action(id="mark_safe", label="Mark safe"), Action(id="report_7726", label="Report phishing" if channel == "email" else "Report to 7726")]
    return []
