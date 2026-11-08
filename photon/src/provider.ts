// PHOTON_PROVIDER=terminal (default, no creds) | imessage (needs PHOTON_PROJECT_ID/SECRET)
export interface Provider {
  run(onMessage: (from: string, text: string) => Promise<string | null>): Promise<void>;
  send(to: string, text: string): Promise<void>;
}

export async function makeProvider(name = process.env.PHOTON_PROVIDER ?? "terminal"): Promise<Provider> {
  if (name === "terminal") {
    // Own readline loop: no creds, same Provider surface as Spectrum.
    const rl = await import("node:readline");
    return {
      async run(on) {
        const r = rl.createInterface({ input: process.stdin });
        for await (const line of r) { if (!line.trim()) continue; const out = await on("terminal-user", line); if (out) console.log(out); }
      },
      async send(to, text) { console.log(`[send -> ${to}] ${text}`); },
    };
  }
  const { Spectrum } = await import("spectrum-ts");
  const { imessage } = await import("spectrum-ts/providers/imessage");
  const app: any = await Spectrum({
    projectId: process.env.PHOTON_PROJECT_ID!, projectSecret: process.env.PHOTON_PROJECT_SECRET!,
    providers: [imessage.config()],
  } as any);
  return {
    async run(on) {
      for await (const [space, message] of app.messages as AsyncIterable<[any, any]>) {
        if (message.content.type !== "text") continue;
        const out = await on(message.sender?.id ?? space.id, message.content.text);
        if (out) await space.send(out);
      }
    },
    async send(to, text) {
      const im = (imessage as any)(app);
      const space = await im.space.create(await im.user(to));
      await space.send(text);
    },
  };
}
