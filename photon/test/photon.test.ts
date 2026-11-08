import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { redact } from "../src/redact";
import { formatReply, guardianMessage } from "../src/format";
import { makeHandler } from "../src/handler";

const fx = (n: string) => JSON.parse(readFileSync(`${import.meta.dir}/../../contracts/fixtures/${n}.json`, "utf8"));

const cases: [string, string][] = [
  ["card 4111 1111 1111 1111 ok", "card <CARD> ok"],
  ["card 4111-1111-1111-1111", "card <CARD>"],
  ["not luhn 4111 1111 1111 1112", "not luhn <CODE:4> <CODE:4> <CODE:4> <CODE:4>"], // conservative: groups look like codes
  ["ssn 123-45-6789 here", "ssn <SSN> here"],
  ["mail me bob@example.com now", "mail me <EMAIL> now"],
  ["two a@b.co and c.d@e.org", "two <EMAIL> and <EMAIL>"],
  ["Your code is 482913", "Your code is <CODE:6>"],
  ["pin 1234 only", "pin <CODE:4> only"],
  ["code 12345678 x", "code <CODE:8> x"],
  ["too short 123 stays", "too short 123 stays"],
  ["too long 123456789 stays", "too long 123456789 stays"],
  ["I live at 123 Main St today", "I live at <ADDR> today"],
  ["send to 4500 Elm Avenue.", "send to <ADDR>"],
  ["Verify: t-mobi1e-acct-verify.co/a8f", "Verify: t-mobi1e-acct-verify.co/a8f"],
  ["go https://x.example.com/p?c=123456", "go https://x.example.com/p?c=123456"],
  ["call 469-555-0182 now", "call 469-555-0182 now"],
  ["suspended in 2 hrs", "suspended in 2 hrs"],
  ["", ""],
  ["code 482913 at foo.co/123456", "code <CODE:6> at foo.co/123456"],
];
test.each(cases)("redact %j", (i, o) => expect(redact(i).text).toBe(o));

test("redaction counts", () => {
  expect(redact("a@b.co 123-45-6789 9999").redactions.sort((a, b) => a.type.localeCompare(b.type)))
    .toEqual([{ type: "code", count: 1 }, { type: "email", count: 1 }, { type: "ssn", count: 1 }]);
});

test("reply: scam verdict, 3 findings, next steps", () => {
  const out = formatReply(fx("scan_result_tmobile_lock"));
  const lines = out.split("\n");
  expect(lines[0]).toBe("🚨 Likely scam · 92% sure");
  expect(lines.filter((l) => l.startsWith("• ")).length).toBe(3);
  expect(out).toContain("7726");
  expect(out).toContain("611");
});

test("reply: unsure under 0.6", () => {
  const r = { ...fx("scan_result_unsure"), confidence: 0.5 };
  expect(formatReply(r).split("\n")[0]).toContain("Not sure");
});

test("reply: safe has no next steps", () => {
  const out = formatReply(fx("scan_result_safe_bank"));
  expect(out).toContain("safe");
  expect(out).not.toContain("Next steps");
});

test("guardian message text", () => {
  expect(guardianMessage("Account-Suspension Smishing", "Grandma", 94)).toBe(
    "Signal Swarm stopped a likely Account-Suspension Smishing scam on Grandma's phone (risk 94). No message content was shared. Reply CALL to call them.");
});

test("handler: redacts before scan, client photon, commands, guardian", async () => {
  let seen: any;
  const h = makeHandler({ scan: async (r) => ((seen = r), fx("scan_result_tmobile_lock")) });
  await h.onMessage("u", "your code 482913 card 4111 1111 1111 1111");
  expect(seen.client).toBe("photon");
  expect(seen.sender.kind).toBe("unknown");
  expect(seen.messages[0].text).toBe("your code <CODE:6> card <CARD>");
  expect(await h.onMessage("u", "privacy")).toContain("Nothing is stored");
  expect(await h.onMessage("u", "STOP")).toContain("unsubscribed");
  expect(await h.onMessage("u", "anything")).toBeNull();
  h.addGuardianAlert("g", { categoryLabel: "X", userAlias: "Ana", riskScore: 90, callNumber: "+14695550100" });
  expect(await h.onMessage("g", "CALL")).toContain("tel:+14695550100");
  expect(await h.onMessage("g", "OK")).toBe("Thanks, noted.");
});

test("handler: backend down -> safe fallback", async () => {
  const h = makeHandler({ scan: async () => { throw new Error("x"); } });
  expect(await h.onMessage("u", "hi there")).toContain("could not reach");
});
