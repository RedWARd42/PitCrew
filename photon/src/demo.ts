import { makeHandler } from "./handler";
const HERO = "T-Mobile: your line will be suspended in 2 hrs. Verify: t-mobi1e-acct-verify.co/a8f";
const out = await makeHandler().onMessage("demo-user", HERO);
console.log(`> ${HERO}\n\n${out}`);
