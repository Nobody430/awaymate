// Skylog push server – watches the user's flights and sends real-time pushes + Live Activity updates.
// No dependencies (Node 20+). Configuration via environment variables (see README.md).
import http from "node:http";
import http2 from "node:http2";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const cfg = {
  port: Number(process.env.PORT || 8080),
  token: process.env.SERVER_TOKEN || "",
  apnsKeyId: process.env.APNS_KEY_ID || "",
  apnsTeamId: process.env.APPLE_TEAM_ID || "",
  apnsKey: (process.env.APNS_KEY_P8 || "").replace(/\\n/g, "\n"),
  topic: process.env.APNS_TOPIC || "com.nobody430.skylog",
  apnsHost: process.env.APNS_HOST || "https://api.push.apple.com",
  faKey: process.env.FLIGHTAWARE_KEY || "",
  dataDir: process.env.DATA_DIR || "/data",
};
const stateFile = path.join(cfg.dataDir, "state.json");

// ---------- state ----------
// devices[token] = { flights: [...], live: {flightId: liveToken}, last: {flightId: snapshot}, updated }
let state = { devices: {} };
try { state = JSON.parse(fs.readFileSync(stateFile, "utf8")); } catch {}
let saveTimer = null;
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    try { fs.mkdirSync(cfg.dataDir, { recursive: true }); fs.writeFileSync(stateFile, JSON.stringify(state)); } catch (e) { console.error("save", e.message); }
  }, 500);
}
const log = (...a) => console.log(new Date().toISOString(), ...a);

// ---------- APNs ----------
let jwtCache = { token: "", at: 0 };
function apnsJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && now - jwtCache.at < 3000) return jwtCache.token;
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const unsigned = `${b64({ alg: "ES256", kid: cfg.apnsKeyId })}.${b64({ iss: cfg.apnsTeamId, iat: now })}`;
  const sig = crypto.sign("sha256", Buffer.from(unsigned), { key: cfg.apnsKey, dsaEncoding: "ieee-p1363" });
  jwtCache = { token: `${unsigned}.${sig.toString("base64url")}`, at: now };
  return jwtCache.token;
}

let apnsSession = null;
function apns() {
  if (!apnsSession || apnsSession.closed || apnsSession.destroyed) {
    apnsSession = http2.connect(cfg.apnsHost);
    apnsSession.on("error", (e) => { log("apns session", e.message); apnsSession = null; });
  }
  return apnsSession;
}

function sendPush(deviceToken, payload, { type = "alert", topic = cfg.topic, priority = 10 } = {}) {
  if (!cfg.apnsKey || !cfg.apnsKeyId) return Promise.resolve(false);
  return new Promise((resolve) => {
    const req = apns().request({
      ":method": "POST", ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${apnsJwt()}`, "apns-topic": topic,
      "apns-push-type": type, "apns-priority": String(priority),
    });
    let status = 0, body = "";
    req.on("response", (h) => { status = h[":status"]; });
    req.on("data", (d) => (body += d));
    req.on("end", () => {
      if (status !== 200) log("apns", status, body);
      if (status === 410 || /BadDeviceToken|Unregistered/.test(body)) forgetToken(deviceToken);
      resolve(status === 200);
    });
    req.on("error", (e) => { log("apns req", e.message); resolve(false); });
    req.end(JSON.stringify(payload));
  });
}

function forgetToken(t) {
  if (state.devices[t]) { delete state.devices[t]; save(); return; }
  for (const d of Object.values(state.devices)) for (const [k, v] of Object.entries(d.live || {})) if (v === t) delete d.live[k];
  save();
}

const alert = (deviceToken, title, body, flightId) =>
  sendPush(deviceToken, { aps: { alert: { title, body }, sound: "default", "thread-id": flightId } });

// Live Activity content-state must match FlightActivityAttributes.ContentState (dates = seconds since 2001-01-01).
const refDate = (iso) => (iso ? (Date.parse(iso) - Date.UTC(2001, 0, 1)) / 1000 : null);
function liveUpdate(liveToken, snap, alertText) {
  const aps = {
    timestamp: Math.floor(Date.now() / 1000),
    event: snap.final ? "end" : "update",
    "content-state": {
      status: snap.statusLabel, departure: refDate(snap.dep), arrival: refDate(snap.arr),
      gate: snap.gate || null, terminal: snap.terminal || null, delayMinutes: Math.max(0, snap.delay || 0),
      belt: snap.belt || null, inAir: !!snap.inAir,
    },
  };
  if (snap.final) aps["dismissal-date"] = Math.floor(Date.now() / 1000) + 30 * 60;
  if (alertText) aps.alert = { title: alertText.title, body: alertText.body };
  return sendPush(liveToken, { aps }, { type: "liveactivity", topic: `${cfg.topic}.push-type.liveactivity` });
}

// ---------- data sources ----------
async function adsb(callsign) {
  for (const base of ["https://api.adsb.lol/v2/callsign/", "https://api.airplanes.live/v2/callsign/"]) {
    try {
      const r = await fetch(base + callsign, { headers: { "User-Agent": "Skylog push server (personal)" }, signal: AbortSignal.timeout(8000) });
      if (!r.ok) continue;
      const j = await r.json();
      const ac = (j.ac || []).filter((a) => (a.flight || "").trim().toUpperCase() === callsign).sort((a, b) => (a.seen ?? 99) - (b.seen ?? 99))[0];
      if (ac && ac.lat != null) return { lat: ac.lat, lon: ac.lon, onGround: ac.alt_baro === "ground", gs: ac.gs, alt: ac.alt_baro };
      return null;
    } catch {}
  }
  return null;
}

async function flightAware(f) {
  if (!cfg.faKey) return null;
  try {
    const url = f.faFlightID
      ? `https://aeroapi.flightaware.com/aeroapi/flights/${encodeURIComponent(f.faFlightID)}`
      : `https://aeroapi.flightaware.com/aeroapi/flights/${encodeURIComponent(f.number)}?ident_type=designator`;
    const r = await fetch(url, { headers: { "x-apikey": cfg.faKey }, signal: AbortSignal.timeout(15000) });
    if (!r.ok) { log("fa", r.status); return null; }
    const list = (await r.json()).flights || [];
    const dep = Date.parse(f.dep || "");
    const match = list.filter((x) => !f.from || (x.origin?.code_iata || "") === f.from)
      .sort((a, b) => Math.abs(Date.parse(a.scheduled_out || a.scheduled_off) - dep) - Math.abs(Date.parse(b.scheduled_out || b.scheduled_off) - dep))[0];
    if (match) f.faFlightID = match.fa_flight_id;
    return match || null;
  } catch (e) { log("fa err", e.message); return null; }
}

function distKm(a, b) {
  const R = 6371, rad = (x) => (x * Math.PI) / 180;
  const h = Math.sin(rad(b.lat - a.lat) / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(rad(b.lon - a.lon) / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// ---------- per-flight logic ----------
const MIN = 60_000;
async function checkFlight(deviceToken, dev, f) {
  const now = Date.now();
  const dep = Date.parse(f.dep), arr = Date.parse(f.arr || f.dep) || dep + 3 * 3600_000;
  if (!dep || now < dep - 24 * 3600_000 || now > arr + 3 * 3600_000) return;

  const prev = dev.last[f.id] || { statusLabel: f.statusLabel || "Planmässig", dep: f.dep, arr: f.arr, gate: f.gate, terminal: f.terminal };
  const snap = { ...prev };
  const msgs = [];

  // FlightAware: 24–4 h before every 2 h, 4 h before until landing every 10 min, after landing a few times (belt)
  const sinceFA = now - (prev.faAt || 0);
  const faEvery = now < dep - 4 * 3600_000 ? 120 * MIN : snap.landed ? 20 * MIN : 10 * MIN;
  if (sinceFA > faEvery && !(snap.landed && snap.belt)) {
    const x = await flightAware(f);
    snap.faAt = now;
    if (x) {
      snap.dep = x.estimated_out || x.scheduled_out || snap.dep;
      snap.arr = x.estimated_in || x.scheduled_in || snap.arr;
      snap.gate = x.gate_origin || snap.gate;
      snap.terminal = x.terminal_origin || snap.terminal;
      snap.arrGate = x.gate_destination || snap.arrGate;
      snap.belt = x.baggage_claim || snap.belt;
      snap.delay = x.departure_delay ? Math.round(x.departure_delay / 60) : snap.delay || 0;
      if (x.cancelled) { snap.statusLabel = "Annulliert"; snap.final = true; }
      if (x.diverted) snap.statusLabel = "Umgeleitet";
      if (x.actual_out && !prev.leftGate) { snap.leftGate = true; snap.statusLabel = "Gate verlassen"; msgs.push(["🛫 Gate verlassen", `${f.number} rollt zur Startbahn.`]); }
      if (x.actual_off && !prev.inAir && !prev.landed) { snap.inAir = true; snap.statusLabel = "In der Luft"; msgs.push([`${f.number} ist gestartet`, `Ankunft ca. ${fmtTime(snap.arr, f.arrTz)}.`]); }
      if ((x.actual_on || x.actual_in) && !prev.landed) { snap.landed = true; snap.inAir = false; snap.statusLabel = "Gelandet"; msgs.push([`${f.number} ist gelandet`, `Willkommen in ${f.toCity || f.to}!`]); }
      if (x.actual_in && !prev.atGate) { snap.atGate = true; snap.statusLabel = "Am Gate"; }
    }
  }

  // Free ADS-B: from 45 min before departure while not landed (every loop = 1 min)
  if (f.callsign && now > dep - 45 * MIN && !snap.landed) {
    const p = await adsb(f.callsign);
    if (p && !p.onGround && !snap.inAir) { snap.inAir = true; snap.statusLabel = "In der Luft"; msgs.push([`${f.number} ist gestartet`, `Unterwegs nach ${f.toCity || f.to}.`]); }
    if (p && !p.onGround && f.toLat != null && p.gs > 100) {
      const km = distKm(p, { lat: f.toLat, lon: f.toLon });
      snap.arr = new Date(now + (km / (p.gs * 1.852)) * 3600_000 + 10 * MIN).toISOString();
    }
    if (p && p.onGround && snap.inAir && f.toLat != null && distKm(p, { lat: f.toLat, lon: f.toLon }) < 15) {
      snap.inAir = false; snap.landed = true; snap.statusLabel = "Gelandet";
      msgs.push([`${f.number} ist gelandet`, `Willkommen in ${f.toCity || f.to}!`]);
    }
  }

  // Change notifications
  if (snap.gate && snap.gate !== prev.gate) msgs.push([prev.gate ? `${f.number}: Gate-Wechsel` : `${f.number}: Gate ${snap.gate}`, prev.gate ? `Neues Gate ${snap.gate} (vorher ${prev.gate}).` : `Abflug von Gate ${snap.gate}${snap.terminal ? `, Terminal ${snap.terminal}` : ""}.`]);
  const delayChange = Math.abs((Date.parse(snap.dep) - Date.parse(prev.dep || snap.dep)) / MIN);
  if (!snap.inAir && !snap.landed && delayChange >= 10) msgs.push([`${f.number}: neue Abflugzeit`, `Abflug jetzt ${fmtTime(snap.dep, f.depTz)}${snap.delay > 0 ? ` (+${snap.delay} Min.)` : ""}.`]);
  if (snap.belt && snap.belt !== prev.belt) msgs.push([`${f.number}: Gepäckband ${snap.belt}`, `Dein Gepäck kommt auf Band ${snap.belt}.`]);
  if (snap.statusLabel === "Annulliert" && prev.statusLabel !== "Annulliert") msgs.push([`${f.number} annulliert`, "Dein Flug wurde annulliert."]);

  // Estimated boarding (airlines don't publish boarding status in open data)
  const boardingAt = dep - (f.longHaul ? 50 : 35) * MIN;
  if (!prev.boardingNotified && now >= boardingAt && now < dep && !snap.inAir) {
    snap.boardingNotified = true;
    if (!snap.leftGate) snap.statusLabel = "Boarding (ca.)";
    msgs.push([`${f.number}: Boarding beginnt`, `Voraussichtlich jetzt${snap.gate ? ` an Gate ${snap.gate}` : ""}. Abflug ${fmtTime(snap.dep, f.depTz)}.`]);
  }

  dev.last[f.id] = snap;
  const changed = msgs.length > 0 || JSON.stringify(snap) !== JSON.stringify(prev);
  if (!changed) return;
  save();
  for (const [title, body] of msgs) await alert(deviceToken, title, body, f.id);
  const live = dev.live?.[f.id];
  if (live) await liveUpdate(live, { ...snap, final: snap.final || (snap.landed && now > arr + 45 * MIN) }, null);
}

function fmtTime(iso, tz) {
  if (!iso) return "–";
  try { return new Date(iso).toLocaleTimeString("de-CH", { hour: "2-digit", minute: "2-digit", timeZone: tz || "Europe/Zurich" }); }
  catch { return new Date(iso).toISOString().slice(11, 16); }
}

let running = false;
async function loop() {
  if (running) return;
  running = true;
  try {
    for (const [token, dev] of Object.entries(state.devices)) {
      dev.last ||= {};
      for (const f of dev.flights || []) {
        try { await checkFlight(token, dev, f); } catch (e) { log("check", f.number, e.message); }
      }
    }
  } finally { running = false; }
}
setInterval(loop, MIN);

// ---------- HTTP API ----------
function readBody(req) {
  return new Promise((resolve) => { let b = ""; req.on("data", (d) => (b += d)); req.on("end", () => resolve(b)); });
}
function auth(req) {
  const expected = Buffer.from(`Bearer ${cfg.token}`);
  const got = Buffer.from(req.headers.authorization || "");
  return cfg.token && got.length === expected.length && crypto.timingSafeEqual(got, expected);
}

http.createServer(async (req, res) => {
  const send = (code, obj) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(obj)); };
  if (req.url === "/health") return send(200, { ok: true, devices: Object.keys(state.devices).length, apns: !!cfg.apnsKey, flightaware: !!cfg.faKey });
  if (!auth(req)) return send(401, { error: "unauthorized" });
  if (req.method === "POST" && req.url === "/sync") {
    try {
      const body = JSON.parse(await readBody(req));
      if (!body.deviceToken || !/^[0-9a-f]{32,200}$/i.test(body.deviceToken)) return send(400, { error: "deviceToken" });
      const dev = state.devices[body.deviceToken] || { flights: [], live: {}, last: {} };
      dev.flights = (body.flights || []).slice(0, 50);
      dev.live = { ...dev.live, ...(body.liveTokens || {}) };
      const ids = new Set(dev.flights.map((f) => f.id));
      for (const k of Object.keys(dev.last)) if (!ids.has(k)) delete dev.last[k];
      dev.updated = new Date().toISOString();
      state.devices[body.deviceToken] = dev;
      save();
      loop();
      return send(200, { ok: true, tracking: dev.flights.length });
    } catch (e) { return send(400, { error: e.message }); }
  }
  if (req.method === "POST" && req.url === "/test") {
    const body = JSON.parse((await readBody(req)) || "{}");
    const ok = await alert(body.deviceToken, "Skylog-Server verbunden ✅", "Pushs funktionieren.", "test");
    return send(ok ? 200 : 502, { ok });
  }
  send(404, { error: "not found" });
}).listen(cfg.port, () => log(`Skylog push server on :${cfg.port} (apns ${cfg.apnsKey ? "on" : "off"}, flightaware ${cfg.faKey ? "on" : "off"})`));
