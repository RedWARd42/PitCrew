// TS port of the on-device redactor (PLAN.md section 8 A1). URLs and sender are kept.
export interface Redacted { text: string; redactions: { type: string; count: number }[] }

export function luhn(digits: string): boolean {
  let sum = 0, alt = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = +digits[i];
    if (alt && (d *= 2) > 9) d -= 9;
    sum += d; alt = !alt;
  }
  return sum % 10 === 0;
}

const URL_RE = /\b(?:https?:\/\/)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}(?:\/\S*)?/gi;
const EMAIL_RE = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g;
const CARD_RE = /\b\d(?:[ -]?\d){12,18}\b/g;
const SSN_RE = /\b\d{3}-\d{2}-\d{4}\b/g;
const ADDR_RE = /\b\d{1,5}\s+(?:[a-z]+\s+){1,3}(?:st|street|ave|avenue|rd|road|blvd|boulevard|dr|drive|ln|lane|ct|court|way)\b\.?/gi;
const CODE_RE = /(?<![\d\-.:/@+])\d{4,8}(?![\d\-.:/@])/g;

export function redact(input: string): Redacted {
  const counts: Record<string, number> = {};
  const hit = (t: string) => (counts[t] = (counts[t] ?? 0) + 1);
  let s = input.replace(EMAIL_RE, () => (hit("email"), "<EMAIL>"));
  const urls: string[] = [];
  s = s.replace(URL_RE, (m) => `\u0000${urls.push(m) - 1}\u0000`);
  s = s.replace(CARD_RE, (m) => {
    const d = m.replace(/\D/g, "");
    return d.length >= 13 && d.length <= 19 && luhn(d) ? (hit("card"), "<CARD>") : m;
  });
  s = s.replace(SSN_RE, () => (hit("ssn"), "<SSN>"));
  s = s.replace(ADDR_RE, () => (hit("address"), "<ADDR>"));
  s = s.replace(CODE_RE, (m) => (hit("code"), `<CODE:${m.length}>`));
  s = s.replace(/\u0000(\d+)\u0000/g, (_, i) => urls[+i]);
  return { text: s, redactions: Object.entries(counts).map(([type, count]) => ({ type, count })) };
}
