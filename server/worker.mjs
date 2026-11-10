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
    this._engine = createEngine({ cfg, state, sendPush, log: (...a) => console.log(...a),
                                  save: () => this.ctx.storage.put("state", state) });
    return this._engine;
  }

  async fetch(request) {
    const engine = await this.engine();
    const url = new URL(request.url);
    if (url.pathname === "/__tick") { await engine.loop(); return new Response("ok"); }
    const r = await engine.handle({ method: request.method, path: url.pathname,
                                    authorization: request.headers.get("authorization") || "", body: await request.text() });
    if (r.after) this.ctx.waitUntil(r.after());
    return Response.json(r.json, { status: r.status });
  }
}

const stub = (env) => env.STATE.get(env.STATE.idFromName("main"));

export default {
  fetch: (request, env) => stub(env).fetch(request),
  scheduled: (event, env, ctx) => ctx.waitUntil(stub(env).fetch("https://skylog/__tick")),
};
