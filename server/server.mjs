// Skylog push server for Node 20+ / Docker (Fly.io, a VPS, a Raspberry Pi …). No dependencies.
// Pushes go through the Skylog relay (RELAY_URL) or – if you built the app yourself – directly to Apple
// with your own APNs key (APNS_KEY_ID, APNS_KEY_P8, APPLE_TEAM_ID, APNS_TOPIC).
import http from "node:http";
import http2 from "node:http2";
import fs from "node:fs";
import path from "node:path";
import { createEngine } from "./core.mjs";
import { apnsJwt, apnsHeaders, pushViaRelay } from "./apns.mjs";

const env = process.env;
const creds = { keyId: env.APNS_KEY_ID || "", teamId: env.APPLE_TEAM_ID || "", p8: env.APNS_KEY_P8 || "",
                topic: env.APNS_TOPIC || "com.nobody430.skylog", host: env.APNS_HOST || "https://api.push.apple.com" };
const direct = !!(creds.keyId && creds.p8 && creds.teamId);
const relay = env.RELAY_URL || "";
const cfg = {
  port: Number(env.PORT || 8080), token: env.SERVER_TOKEN || "", faKey: env.FLIGHTAWARE_KEY || "",
  maxDevices: Number(env.MAX_DEVICES || 20), pushMode: direct ? "direct" : relay ? "relay" : "off",
};
const dataDir = env.DATA_DIR || "/data";
const stateFile = path.join(dataDir, "state.json");
const log = (...a) => console.log(new Date().toISOString(), ...a);

let state = { devices: {} };
try { state = JSON.parse(fs.readFileSync(stateFile, "utf8")); } catch {}
async function save() {
  try { fs.mkdirSync(dataDir, { recursive: true }); fs.writeFileSync(stateFile, JSON.stringify(state)); } catch (e) { log("save", e.message); }
}

// Apple only speaks HTTP/2, which Node's fetch doesn't – so the direct path uses node:http2.
let session = null;
function apns() {
  if (!session || session.closed || session.destroyed) {
    session = http2.connect(creds.host);
    session.on("error", (e) => { log("apns session", e.message); session = null; });
  }
  return session;
}
async function sendDirect(deviceToken, payload, opts = {}) {
  const jwt = await apnsJwt(creds);
  return new Promise((resolve) => {
    const req = apns().request({ ":method": "POST", ":path": `/3/device/${deviceToken}`, ...apnsHeaders(jwt, { ...opts, topic: creds.topic }) });
    let status = 0, body = "";
    req.on("response", (h) => { status = h[":status"]; });
    req.on("data", (d) => (body += d));
    req.on("end", () => {
      let reason = "";
      try { reason = JSON.parse(body).reason || ""; } catch {}
      resolve({ ok: status === 200, status, reason });
    });
    req.on("error", (e) => resolve({ ok: false, status: 0, reason: e.message }));
    req.end(JSON.stringify(payload));
  });
}
const sendPush = (t, p, o) => direct ? sendDirect(t, p, o) : relay ? pushViaRelay(relay, t, p, o) : Promise.resolve({ ok: false, status: 0, reason: "no push configured" });

// Device sync document (one file)
const dataFile = path.join(dataDir, "sync.json");
const store = {
  get: async () => { try { return JSON.parse(fs.readFileSync(dataFile, "utf8")); } catch { return null; } },
  put: async (doc) => { fs.mkdirSync(dataDir, { recursive: true }); fs.writeFileSync(dataFile, JSON.stringify(doc)); },
};
const engine = createEngine({ cfg, state, save, sendPush, store, log });
setInterval(() => engine.loop().catch((e) => log("loop", e.message)), 60_000);

http.createServer(async (req, res) => {
  let body = "";
  for await (const chunk of req) { body += chunk; if (body.length > 4_500_000) break; }
  const r = await engine.handle({ method: req.method, path: (req.url || "/").split("?")[0], authorization: req.headers.authorization,
                                  language: req.headers["accept-language"] || "", body })
    .catch((e) => ({ status: 500, json: { error: e.message } }));
  if (r.html) {
    res.writeHead(r.status, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer" });
    res.end(r.html);
  } else {
    res.writeHead(r.status, { "content-type": "application/json" });
    res.end(JSON.stringify(r.json));
  }
  if (r.after) r.after().catch((e) => log("loop", e.message));
}).listen(cfg.port, () => log(`Skylog push server on :${cfg.port} (push ${cfg.pushMode}, flightaware ${cfg.faKey ? "on" : "per device"})`));
