// Skylog push server for Cloudflare Workers (free plan): one Durable Object keeps the state,
// a cron trigger runs the flight check every minute.
import { DurableObject } from "cloudflare:workers";
import { createEngine } from "./core.mjs";
import { pushViaFetch, pushViaRelay } from "./apns.mjs";

export class SkylogState extends DurableObject {
  async engine() {
    if (this._engine) return this._engine;
    const env = this.env;
    const state = (await this.ctx.storage.get("state")) || { devices: {} };
    const creds = { keyId: env.APNS_KEY_ID || "", teamId: env.APPLE_TEAM_ID || "", p8: env.APNS_KEY_P8 || "",
                    topic: env.APNS_TOPIC || "com.nobody430.skylog" };
    const direct = !!(creds.keyId && creds.p8 && creds.teamId);
    const relay = env.RELAY_URL || "";
    const cfg = { token: env.SERVER_TOKEN || "", faKey: env.FLIGHTAWARE_KEY || "", maxDevices: Number(env.MAX_DEVICES || 20),
                  pushMode: direct ? "direct" : relay ? "relay" : "off" };
    const sendPush = (t, p, o) => direct ? pushViaFetch(creds, t, p, o) : relay ? pushViaRelay(relay, t, p, o)
      : Promise.resolve({ ok: false, status: 0, reason: "no push configured" });
    // Device sync document, stored in chunks (Durable Object values are size-limited)
    const storage = this.ctx.storage;
    const store = {
      get: async () => {
        const meta = await storage.get("sync:meta");
        if (!meta) return null;
        const parts = await storage.get(Array.from({ length: meta.chunks }, (_, i) => `sync:${i}`));
        return { rev: meta.rev, data: Array.from({ length: meta.chunks }, (_, i) => parts.get(`sync:${i}`) || "").join("") };
      },
      put: async ({ rev, data }) => {
        const size = 100_000, old = (await storage.get("sync:meta"))?.chunks || 0;
        const chunks = Math.max(1, Math.ceil(data.length / size));
        for (let i = 0; i < chunks; i++) await storage.put(`sync:${i}`, data.slice(i * size, (i + 1) * size));
        for (let i = chunks; i < old; i++) await storage.delete(`sync:${i}`);
        await storage.put("sync:meta", { rev, chunks });
      },
    };
    this._engine = createEngine({ cfg, state, sendPush, store, log: (...a) => console.log(...a),
                                  save: () => this.ctx.storage.put("state", state) });
    return this._engine;
  }

  async fetch(request) {
    const engine = await this.engine();
    const url = new URL(request.url);
    if (url.pathname === "/__tick") { await engine.loop(); return new Response("ok"); }
    const r = await engine.handle({ method: request.method, path: url.pathname,
                                    authorization: request.headers.get("authorization") || "",
                                    language: request.headers.get("accept-language") || "", body: await request.text() });
    if (r.after) this.ctx.waitUntil(r.after());
    if (r.html) {
      return new Response(r.html, { status: r.status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer" } });
    }
    return Response.json(r.json, { status: r.status });
  }
}

const stub = (env) => env.STATE.get(env.STATE.idFromName("main"));

export default {
  fetch: (request, env) => stub(env).fetch(request),
  scheduled: (event, env, ctx) => ctx.waitUntil(stub(env).fetch("https://skylog/__tick")),
};
