// Pure validation + document shaping for fleet reports — kept free of
// I/O so it can be unit-tested without a database (test/validate.test.mjs).

export function validateReport(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return 'body must be a JSON object';
  }
  if (typeof body.incidentId !== 'string' || !body.incidentId) {
    return 'incidentId must be a non-empty string';
  }
  if (typeof body.sender !== 'string' || !body.sender) {
    return 'sender must be a non-empty string';
  }
  if (
    !Number.isFinite(body.riskScore) ||
    body.riskScore < 0 ||
    body.riskScore > 100
  ) {
    return 'riskScore must be a number between 0 and 100';
  }
  if (typeof body.verdict !== 'string' || !body.verdict) {
    return 'verdict must be a non-empty string';
  }
  if (body.topFlags !== undefined && !Array.isArray(body.topFlags)) {
    return 'topFlags must be an array';
  }
  if (body.account !== undefined && typeof body.account !== 'string') {
    return 'account must be a string';
  }
  return null;
}

export function reportDocument(body, now = new Date()) {
  return {
    incidentId: body.incidentId,
    sender: body.sender,
    riskScore: body.riskScore,
    verdict: body.verdict,
    topFlags: (body.topFlags ?? []).slice(0, 8).map(String),
    account: body.account ?? null,
    reportedAt: now,
  };
}
