// Sending pushes: directly to Apple (needs the publisher's APNs key) or through the Skylog relay.
// Uses only WebCrypto + fetch, so it runs in Node 20+ and in Cloudflare Workers.

const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJson = (o) => b64url(new TextEncoder().encode(JSON.stringify(o)));

let jwtCache = { token: "", at: 0, kid: "" };

/** Provider token for APNs (ES256), cached for 50 minutes. */
export async function apnsJwt({ keyId, teamId, p8 }) {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && jwtCache.kid === keyId && now - jwtCache.at < 3000) return jwtCache.token;
  const pem = String(p8).replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const unsigned = `${b64urlJson({ alg: "ES256", kid: keyId })}.${b64urlJson({ iss: teamId, iat: now })}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  jwtCache = { token: `${unsigned}.${b64url(sig)}`, at: now, kid: keyId };
  return jwtCache.token;
}

export function apnsHeaders(jwt, { type = "alert", topic, priority = 10 }) {
  return {
    authorization: `bearer ${jwt}`,
    "apns-topic": type === "liveactivity" ? `${topic}.push-type.liveactivity` : topic,
    "apns-push-type": type,
    "apns-priority": String(priority),
    "content-type": "application/json",
  };
}

/** Direct to Apple with fetch (Cloudflare Workers). Returns { ok, status, reason }. */
export async function pushViaFetch(creds, deviceToken, payload, opts = {}) {
  const jwt = await apnsJwt(creds);
  const host = creds.host || "https://api.push.apple.com";
  try {
    const r = await fetch(`${host}/3/device/${deviceToken}`, {
      method: "POST", headers: apnsHeaders(jwt, { ...opts, topic: creds.topic }), body: JSON.stringify(payload),
    });
    const text = r.status === 200 ? "" : await r.text();
    let reason = "";
    try { reason = JSON.parse(text).reason || ""; } catch { reason = text.slice(0, 120); }
    return { ok: r.status === 200, status: r.status, reason };
  } catch (e) {
    return { ok: false, status: 0, reason: String(e.message || e) };
  }
}

/** Through the relay of whoever published the app (no Apple key needed on this server). */
export async function pushViaRelay(relayUrl, deviceToken, payload, opts = {}) {
  try {
    const r = await fetch(relayUrl.replace(/\/+$/, "") + "/push", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceToken, payload, type: opts.type || "alert", priority: opts.priority || 10 }),
    });
    const j = await r.json().catch(() => ({}));
    return { ok: r.ok && j.ok !== false, status: j.status || r.status, reason: j.reason || "" };
  } catch (e) {
    return { ok: false, status: 0, reason: String(e.message || e) };
  }
}
