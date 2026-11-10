// Skylog push relay (Cloudflare Worker). Run by whoever publishes the app: it holds the Apple push key and
// forwards pushes from users' own servers to Apple. It knows no flights and no API keys – only a device token
// and the finished notification. It only ever sends to this one app.
import { pushViaFetch } from "../server/apns.mjs";

const recent = new Map();   // deviceToken -> timestamps (best effort, per isolate)

function limited(token, perMinute) {
  const now = Date.now();
  const list = (recent.get(token) || []).filter((t) => now - t < 60_000);
  if (list.length >= perMinute) return true;
  list.push(now);
  recent.set(token, list);
  if (recent.size > 5000) recent.clear();
  return false;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const creds = { keyId: env.APNS_KEY_ID || "", teamId: env.APPLE_TEAM_ID || "", p8: env.APNS_KEY_P8 || "",
                    topic: env.APNS_TOPIC || "com.nobody430.skylog" };
    if (url.pathname === "/health") return Response.json({ ok: true, apns: !!(creds.keyId && creds.p8 && creds.teamId) });
    if (request.method !== "POST" || url.pathname !== "/push") return Response.json({ error: "not found" }, { status: 404 });

    const text = await request.text();
    if (text.length > 6000) return Response.json({ ok: false, reason: "too large" }, { status: 413 });
    let body;
    try { body = JSON.parse(text); } catch { return Response.json({ ok: false, reason: "json" }, { status: 400 }); }
    const { deviceToken, payload, type = "alert", priority = 10 } = body;
    if (typeof deviceToken !== "string" || !/^[0-9a-f]{32,200}$/i.test(deviceToken)) return Response.json({ ok: false, reason: "deviceToken" }, { status: 400 });
    if (!payload || typeof payload !== "object" || !payload.aps) return Response.json({ ok: false, reason: "payload" }, { status: 400 });
    if (type !== "alert" && type !== "liveactivity") return Response.json({ ok: false, reason: "type" }, { status: 400 });
    if (limited(deviceToken, Number(env.MAX_PER_MINUTE || 20))) return Response.json({ ok: false, reason: "rate limit" }, { status: 429 });

    const r = await pushViaFetch(creds, deviceToken, payload, { type, priority: priority === 5 ? 5 : 10 });
    return Response.json(r, { status: r.ok ? 200 : 502 });
  },
};
