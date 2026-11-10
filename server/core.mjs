// Skylog push engine – watches the flights the app reports and decides which pushes to send.
// Platform independent: storage, push sending and logging are injected (Node server or Cloudflare Worker).

const MIN = 60_000;

// Texts in the language of the device (sent by the app with each sync). {0}, {1} … are placeholders.
const TEXTS = {
  de: {
    scheduled: "Planmässig", cancelled: "Annulliert", diverted: "Umgeleitet", leftGate: "Gate verlassen", inAir: "In der Luft",
    landed: "Gelandet", atGate: "Am Gate", boarding: "Boarding (ca.)",
    leftGateTitle: "🛫 Gate verlassen", leftGateBody: "{0} rollt zur Startbahn.",
    departedTitle: "{0} ist gestartet", departedEta: "Ankunft ca. {0}.", departedTo: "Unterwegs nach {0}.",
    landedTitle: "{0} ist gelandet", landedBody: "Willkommen in {0}!",
    gateChangeTitle: "{0}: Gate-Wechsel", gateTitle: "{0}: Gate {1}", gateChangeBody: "Neues Gate {0} (vorher {1}).",
    gateBody: "Abflug von Gate {0}.", gateBodyTerminal: "Abflug von Gate {0}, Terminal {1}.",
    newDepTitle: "{0}: neue Abflugzeit", newDepBody: "Abflug jetzt {0}.", newDepBodyDelay: "Abflug jetzt {0} (+{1} Min.).",
    beltTitle: "{0}: Gepäckband {1}", beltBody: "Dein Gepäck kommt auf Band {0}.",
    cancelledTitle: "{0} annulliert", cancelledBody: "Dein Flug wurde annulliert.",
    boardingTitle: "{0}: Boarding beginnt", boardingBody: "Voraussichtlich jetzt. Abflug {0}.", boardingBodyGate: "Voraussichtlich jetzt an Gate {0}. Abflug {1}.",
    testTitle: "Skylog-Server verbunden ✅", testBody: "Pushs funktionieren.",
  },
  en: {
    scheduled: "On time", cancelled: "Cancelled", diverted: "Diverted", leftGate: "Left the gate", inAir: "In the air",
    landed: "Landed", atGate: "At the gate", boarding: "Boarding (est.)",
    leftGateTitle: "🛫 Left the gate", leftGateBody: "{0} is taxiing to the runway.",
    departedTitle: "{0} has taken off", departedEta: "Arrival around {0}.", departedTo: "On the way to {0}.",
    landedTitle: "{0} has landed", landedBody: "Welcome to {0}!",
    gateChangeTitle: "{0}: gate change", gateTitle: "{0}: gate {1}", gateChangeBody: "New gate {0} (was {1}).",
    gateBody: "Departing from gate {0}.", gateBodyTerminal: "Departing from gate {0}, terminal {1}.",
    newDepTitle: "{0}: new departure time", newDepBody: "Now departing at {0}.", newDepBodyDelay: "Now departing at {0} (+{1} min).",
    beltTitle: "{0}: baggage belt {1}", beltBody: "Your bags arrive on belt {0}.",
    cancelledTitle: "{0} cancelled", cancelledBody: "Your flight has been cancelled.",
    boardingTitle: "{0}: boarding starts", boardingBody: "Probably now. Departure {0}.", boardingBodyGate: "Probably now at gate {0}. Departure {1}.",
    testTitle: "Skylog server connected ✅", testBody: "Push notifications work.",
  },
};
function t(lang, key, ...args) {
  const text = (TEXTS[lang] || TEXTS.de)[key] ?? TEXTS.de[key] ?? key;
  return text.replace(/\{(\d)\}/g, (_, i) => String(args[Number(i)] ?? ""));
}

export function createEngine({ cfg, state, save, sendPush, log = () => {} }) {
  state.devices ||= {};

  function forgetToken(t) {
    if (state.devices[t]) { delete state.devices[t]; return; }
    for (const d of Object.values(state.devices)) for (const [k, v] of Object.entries(d.live || {})) if (v === t) delete d.live[k];
  }

  async function push(token, payload, opts) {
    const r = await sendPush(token, payload, opts);
    if (!r.ok) log("push", r.status, r.reason);
    if (r.status === 410 || /BadDeviceToken|Unregistered/.test(r.reason || "")) forgetToken(token);
    return r.ok;
  }

  const alert = (deviceToken, title, body, flightId) =>
    push(deviceToken, { aps: { alert: { title, body }, sound: "default", "thread-id": flightId } }, { type: "alert" });

  // Live Activity content-state must match FlightActivityAttributes.ContentState (dates = seconds since 2001-01-01).
  const refDate = (iso) => (iso ? (Date.parse(iso) - Date.UTC(2001, 0, 1)) / 1000 : null);
  function liveUpdate(liveToken, snap, lang) {
    const aps = {
      timestamp: Math.floor(Date.now() / 1000),
      event: snap.final ? "end" : "update",
      "content-state": {
        status: snap.statusKey ? t(lang, snap.statusKey) : snap.statusLabel, departure: refDate(snap.dep), arrival: refDate(snap.arr),
        gate: snap.gate || null, terminal: snap.terminal || null, delayMinutes: Math.max(0, snap.delay || 0),
        belt: snap.belt || null, inAir: !!snap.inAir, landed: !!snap.landed,
      },
    };
    if (snap.final) aps["dismissal-date"] = Math.floor(Date.now() / 1000) + 30 * 60;
    return push(liveToken, { aps }, { type: "liveactivity" });
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

  async function flightAware(f, key) {
    if (!key) return null;
    try {
      const url = f.faFlightID
        ? `https://aeroapi.flightaware.com/aeroapi/flights/${encodeURIComponent(f.faFlightID)}`
        : `https://aeroapi.flightaware.com/aeroapi/flights/${encodeURIComponent(f.number)}?ident_type=designator`;
      const r = await fetch(url, { headers: { "x-apikey": key }, signal: AbortSignal.timeout(15000) });
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

  function fmtTime(iso, tz, lang) {
    if (!iso) return "–";
    try { return new Date(iso).toLocaleTimeString(lang === "en" ? "en-GB" : "de-CH", { hour: "2-digit", minute: "2-digit", timeZone: tz || "Europe/Zurich" }); }
    catch { return new Date(iso).toISOString().slice(11, 16); }
  }

  // ---------- per-flight logic ----------
  /** Returns true if something worth storing changed. */
  async function checkFlight(deviceToken, dev, f) {
    const now = Date.now();
    const dep = Date.parse(f.dep), arr = Date.parse(f.arr || f.dep) || dep + 3 * 3600_000;
    if (!dep || now < dep - 24 * 3600_000 || now > arr + 3 * 3600_000) return false;

    const lang = dev.lang || "de";
    const L = (key, ...args) => t(lang, key, ...args);
    // statusLabel = text from the app (already in the user's language); statusKey = set by this server
    const prev = dev.last[f.id] || { statusLabel: f.statusLabel || L("scheduled"), dep: f.dep, arr: f.arr, gate: f.gate, terminal: f.terminal };
    const snap = { ...prev };
    const msgs = [];
    let fetched = false;

    // FlightAware (the device's own key, sent by the app; or the server's): 24–4 h before every 2 h,
    // then every 10 min until landing, after landing a few times (belt)
    const faKey = dev.faKey || cfg.faKey;
    const sinceFA = now - (prev.faAt || 0);
    const faEvery = now < dep - 4 * 3600_000 ? 120 * MIN : snap.landed ? 20 * MIN : 10 * MIN;
    if (faKey && sinceFA > faEvery && !(snap.landed && snap.belt)) {
      const x = await flightAware(f, faKey);
      snap.faAt = now;
      fetched = true;
      if (x) {
        snap.dep = x.estimated_out || x.scheduled_out || snap.dep;
        snap.arr = x.estimated_in || x.scheduled_in || snap.arr;
        snap.gate = x.gate_origin || snap.gate;
        snap.terminal = x.terminal_origin || snap.terminal;
        snap.arrGate = x.gate_destination || snap.arrGate;
        snap.belt = x.baggage_claim || snap.belt;
        snap.delay = x.departure_delay ? Math.round(x.departure_delay / 60) : snap.delay || 0;
        if (x.cancelled) { snap.statusKey = "cancelled"; snap.final = true; }
        if (x.diverted) snap.statusKey = "diverted";
        if (x.actual_out && !prev.leftGate) { snap.leftGate = true; snap.statusKey = "leftGate"; msgs.push([L("leftGateTitle"), L("leftGateBody", f.number)]); }
        if (x.actual_off && !prev.inAir && !prev.landed) { snap.inAir = true; snap.statusKey = "inAir"; msgs.push([L("departedTitle", f.number), L("departedEta", fmtTime(snap.arr, f.arrTz, lang))]); }
        if ((x.actual_on || x.actual_in) && !prev.landed) { snap.landed = true; snap.inAir = false; snap.statusKey = "landed"; msgs.push([L("landedTitle", f.number), L("landedBody", f.toCity || f.to)]); }
        if (x.actual_in && !prev.atGate) { snap.atGate = true; snap.statusKey = "atGate"; }
      }
    }

    // Free ADS-B: from 15 min before departure while not landed (every loop = 1 min)
    if (f.callsign && now > dep - 15 * MIN && !snap.landed) {
      const p = await adsb(f.callsign);
      if (p && !p.onGround && !snap.inAir) { snap.inAir = true; snap.statusKey = "inAir"; msgs.push([L("departedTitle", f.number), L("departedTo", f.toCity || f.to)]); }
      if (p && !p.onGround && f.toLat != null && p.gs > 100) {
        const km = distKm(p, { lat: f.toLat, lon: f.toLon });
        const eta = now + (km / (p.gs * 1.852)) * 3600_000 + 10 * MIN;
        // only move the ETA in steps of 3 minutes (fewer updates and writes)
        if (Math.abs(eta - Date.parse(snap.arr || 0)) >= 3 * MIN) snap.arr = new Date(eta).toISOString();
      }
      if (p && p.onGround && snap.inAir && f.toLat != null && distKm(p, { lat: f.toLat, lon: f.toLon }) < 15) {
        snap.inAir = false; snap.landed = true; snap.statusKey = "landed";
        msgs.push([L("landedTitle", f.number), L("landedBody", f.toCity || f.to)]);
      }
    }

    // Change notifications
    if (snap.gate && snap.gate !== prev.gate) {
      msgs.push(prev.gate
        ? [L("gateChangeTitle", f.number), L("gateChangeBody", snap.gate, prev.gate)]
        : [L("gateTitle", f.number, snap.gate), snap.terminal ? L("gateBodyTerminal", snap.gate, snap.terminal) : L("gateBody", snap.gate)]);
    }
    // compare with the time the user was last told about, so creeping delays are noticed
    const told = Date.parse(prev.toldDep || prev.dep || snap.dep);
    if (!snap.inAir && !snap.landed && Math.abs(Date.parse(snap.dep) - told) >= 5 * MIN) {
      snap.toldDep = snap.dep;
      const when = fmtTime(snap.dep, f.depTz, lang);
      msgs.push([L("newDepTitle", f.number), snap.delay > 0 ? L("newDepBodyDelay", when, snap.delay) : L("newDepBody", when)]);
    }
    // the belt only matters once the plane is on its way down
    if (snap.belt && snap.belt !== prev.belt && (snap.landed || (snap.inAir && Date.parse(snap.arr) - now < 45 * MIN))) {
      msgs.push([L("beltTitle", f.number, snap.belt), L("beltBody", snap.belt)]);
    }
    if (snap.statusKey === "cancelled" && prev.statusKey !== "cancelled") msgs.push([L("cancelledTitle", f.number), L("cancelledBody")]);

    // Estimated boarding (airlines don't publish boarding status in open data)
    const boardingAt = Date.parse(snap.dep) - (f.longHaul ? 50 : 35) * MIN;
    if (!prev.boardingNotified && now >= boardingAt && now < Date.parse(snap.dep) && !snap.inAir) {
      snap.boardingNotified = true;
      if (!snap.leftGate) snap.statusKey = "boarding";
      const when = fmtTime(snap.dep, f.depTz, lang);
      msgs.push([L("boardingTitle", f.number), snap.gate ? L("boardingBodyGate", snap.gate, when) : L("boardingBody", when)]);
    }

    dev.last[f.id] = snap;
    const visible = ["statusKey", "statusLabel", "dep", "arr", "gate", "terminal", "belt", "delay", "inAir", "landed", "final"];
    const changed = msgs.length > 0 || visible.some((k) => snap[k] !== prev[k]);
    if (!changed) return fetched;
    for (const [title, body] of msgs) await alert(deviceToken, title, body, f.id);
    const live = dev.live?.[f.id];
    if (live) await liveUpdate(live, { ...snap, final: snap.final || snap.landed }, lang);
    return true;
  }

  let running = false;
  async function loop() {
    if (running) return;
    running = true;
    let dirty = false;
    try {
      const cutoff = Date.now() - 60 * 86400_000;
      for (const [token, dev] of Object.entries(state.devices)) {
        // devices that haven't synced for two months are forgotten
        if (dev.updated && Date.parse(dev.updated) < cutoff) { delete state.devices[token]; dirty = true; continue; }
        dev.last ||= {};
        for (const f of dev.flights || []) {
          try { if (await checkFlight(token, dev, f)) dirty = true; } catch (e) { log("check", f.number, e.message); }
        }
      }
    } finally { running = false; }
    if (dirty) await save();
  }

  /** HTTP API shared by all platforms. `req` = { method, path, authorization, body } → { status, json }. */
  async function handle(req) {
    if (req.path === "/health") {
      return { status: 200, json: { ok: true, devices: Object.keys(state.devices).length, push: cfg.pushMode, flightaware: !!cfg.faKey } };
    }
    if (!cfg.token || !safeEqual(req.authorization || "", `Bearer ${cfg.token}`)) return { status: 401, json: { error: "unauthorized" } };
    let body = {};
    try { body = req.body ? JSON.parse(req.body) : {}; } catch { return { status: 400, json: { error: "json" } }; }

    if (req.method === "POST" && req.path === "/sync") {
      if (!body.deviceToken || !/^[0-9a-f]{32,200}$/i.test(body.deviceToken)) return { status: 400, json: { error: "deviceToken" } };
      if (!state.devices[body.deviceToken] && Object.keys(state.devices).length >= (cfg.maxDevices || 20)) {
        return { status: 429, json: { error: "too many devices" } };
      }
      const dev = state.devices[body.deviceToken] || { flights: [], live: {}, last: {} };
      dev.flights = (body.flights || []).slice(0, 50);
      dev.live = { ...dev.live, ...(body.liveTokens || {}) };
      if (typeof body.flightawareKey === "string") dev.faKey = body.flightawareKey || undefined;
      if (typeof body.lang === "string") dev.lang = body.lang.slice(0, 2).toLowerCase();
      const ids = new Set(dev.flights.map((f) => f.id));
      for (const k of Object.keys(dev.last || {})) if (!ids.has(k)) delete dev.last[k];
      for (const k of Object.keys(dev.live || {})) if (!ids.has(k)) delete dev.live[k];
      dev.updated = new Date().toISOString();
      state.devices[body.deviceToken] = dev;
      await save();
      return { status: 200, json: { ok: true, tracking: dev.flights.length }, after: loop };
    }
    if (req.method === "POST" && req.path === "/test") {
      if (!body.deviceToken) return { status: 400, json: { error: "deviceToken" } };
      const lang = (typeof body.lang === "string" ? body.lang : state.devices[body.deviceToken]?.lang || "de").slice(0, 2).toLowerCase();
      const r = await sendPush(body.deviceToken, { aps: { alert: { title: t(lang, "testTitle"), body: t(lang, "testBody") }, sound: "default" } }, { type: "alert" });
      return { status: r.ok ? 200 : 502, json: { ok: r.ok, status: r.status, reason: r.reason || undefined } };
    }
    return { status: 404, json: { error: "not found" } };
  }

  return { loop, handle };
}

function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
