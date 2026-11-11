// Skylog push engine – watches the flights the app reports and decides which pushes to send.
// Platform independent: storage, push sending and logging are injected (Node server or Cloudflare Worker).

const MIN = 60_000;

// Texts in the language of the device (sent by the app with each sync). {0}, {1} … are placeholders.
const TEXTS = {
  de: {
    delayed: "Verspätet", scheduled: "Planmässig", cancelled: "Annulliert", diverted: "Umgeleitet", leftGate: "Gate verlassen", inAir: "In der Luft",
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
    delayed: "Delayed", scheduled: "On time", cancelled: "Cancelled", diverted: "Diverted", leftGate: "Left the gate", inAir: "In the air",
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
  fr: {
    delayed: "Retardé", scheduled: "À l'heure", cancelled: "Annulé", diverted: "Dérouté", leftGate: "A quitté la porte", inAir: "En vol",
    landed: "Atterri", atGate: "À la porte", boarding: "Embarquement (env.)",
    leftGateTitle: "🛫 Porte quittée", leftGateBody: "{0} roule vers la piste.",
    departedTitle: "{0} a décollé", departedEta: "Arrivée vers {0}.", departedTo: "En route pour {0}.",
    landedTitle: "{0} a atterri", landedBody: "Bienvenue à {0} !",
    gateChangeTitle: "{0} : changement de porte", gateTitle: "{0} : porte {1}", gateChangeBody: "Nouvelle porte {0} (avant : {1}).",
    gateBody: "Départ de la porte {0}.", gateBodyTerminal: "Départ de la porte {0}, terminal {1}.",
    newDepTitle: "{0} : nouvelle heure de départ", newDepBody: "Départ maintenant à {0}.", newDepBodyDelay: "Départ maintenant à {0} (+{1} min).",
    beltTitle: "{0} : tapis {1}", beltBody: "Vos bagages arrivent sur le tapis {0}.",
    cancelledTitle: "{0} annulé", cancelledBody: "Votre vol a été annulé.",
    boardingTitle: "{0} : l'embarquement commence", boardingBody: "Probablement maintenant. Départ {0}.", boardingBodyGate: "Probablement maintenant à la porte {0}. Départ {1}.",
    testTitle: "Serveur Skylog connecté ✅", testBody: "Les notifications fonctionnent.",
  },
  it: {
    delayed: "In ritardo", scheduled: "In orario", cancelled: "Cancellato", diverted: "Dirottato", leftGate: "Ha lasciato il gate", inAir: "In volo",
    landed: "Atterrato", atGate: "Al gate", boarding: "Imbarco (ca.)",
    leftGateTitle: "🛫 Gate lasciato", leftGateBody: "{0} sta rullando verso la pista.",
    departedTitle: "{0} è decollato", departedEta: "Arrivo verso le {0}.", departedTo: "In viaggio verso {0}.",
    landedTitle: "{0} è atterrato", landedBody: "Benvenuto a {0}!",
    gateChangeTitle: "{0}: cambio gate", gateTitle: "{0}: gate {1}", gateChangeBody: "Nuovo gate {0} (prima {1}).",
    gateBody: "Partenza dal gate {0}.", gateBodyTerminal: "Partenza dal gate {0}, terminal {1}.",
    newDepTitle: "{0}: nuovo orario di partenza", newDepBody: "Partenza ora alle {0}.", newDepBodyDelay: "Partenza ora alle {0} (+{1} min).",
    beltTitle: "{0}: nastro bagagli {1}", beltBody: "I tuoi bagagli arrivano sul nastro {0}.",
    cancelledTitle: "{0} cancellato", cancelledBody: "Il tuo volo è stato cancellato.",
    boardingTitle: "{0}: inizia l'imbarco", boardingBody: "Probabilmente ora. Partenza {0}.", boardingBodyGate: "Probabilmente ora al gate {0}. Partenza {1}.",
    testTitle: "Server Skylog collegato ✅", testBody: "Le notifiche funzionano.",
  },
  es: {
    delayed: "Retrasado", scheduled: "A tiempo", cancelled: "Cancelado", diverted: "Desviado", leftGate: "Salió de la puerta", inAir: "En vuelo",
    landed: "Aterrizado", atGate: "En la puerta", boarding: "Embarque (aprox.)",
    leftGateTitle: "🛫 Salió de la puerta", leftGateBody: "{0} rueda hacia la pista.",
    departedTitle: "{0} ha despegado", departedEta: "Llegada sobre las {0}.", departedTo: "Rumbo a {0}.",
    landedTitle: "{0} ha aterrizado", landedBody: "¡Bienvenido a {0}!",
    gateChangeTitle: "{0}: cambio de puerta", gateTitle: "{0}: puerta {1}", gateChangeBody: "Nueva puerta {0} (antes {1}).",
    gateBody: "Salida desde la puerta {0}.", gateBodyTerminal: "Salida desde la puerta {0}, terminal {1}.",
    newDepTitle: "{0}: nueva hora de salida", newDepBody: "Salida ahora a las {0}.", newDepBodyDelay: "Salida ahora a las {0} (+{1} min).",
    beltTitle: "{0}: cinta de equipaje {1}", beltBody: "Tu equipaje llega por la cinta {0}.",
    cancelledTitle: "{0} cancelado", cancelledBody: "Tu vuelo ha sido cancelado.",
    boardingTitle: "{0}: comienza el embarque", boardingBody: "Probablemente ahora. Salida {0}.", boardingBodyGate: "Probablemente ahora en la puerta {0}. Salida {1}.",
    testTitle: "Servidor Skylog conectado ✅", testBody: "Las notificaciones funcionan.",
  },
};
// Texts of the public status page (link shared with family & friends)
const PAGE = {
  de: { alt: "Höhe", spd: "Geschwindigkeit", left: "Noch", climb: "steigt", desc: "sinkt", live: "Live-Position, Stand {0}", est: "Geschätzte Position (keine Live-Daten)", title: "Flugstatus", dep: "Abflug", arr: "Ankunft", gate: "Gate", terminal: "Terminal", belt: "Gepäckband", delay: "{0} Min. später",
        onTime: "pünktlich", updated: "Stand {0}", local: "Ortszeit", ended: "Dieser Link ist abgelaufen oder ungültig.", by: "Geteilt mit Skylog", reload: "Die Seite aktualisiert sich jede Minute." },
  en: { alt: "Altitude", spd: "Speed", left: "Remaining", climb: "climbing", desc: "descending", live: "Live position as of {0}", est: "Estimated position (no live data)", title: "Flight status", dep: "Departure", arr: "Arrival", gate: "Gate", terminal: "Terminal", belt: "Baggage belt", delay: "{0} min late",
        onTime: "on time", updated: "As of {0}", local: "local time", ended: "This link has expired or is invalid.", by: "Shared with Skylog", reload: "This page refreshes every minute." },
  fr: { alt: "Altitude", spd: "Vitesse", left: "Restant", climb: "en montée", desc: "en descente", live: "Position en direct à {0}", est: "Position estimée (pas de données en direct)", title: "Statut du vol", dep: "Départ", arr: "Arrivée", gate: "Porte", terminal: "Terminal", belt: "Tapis à bagages", delay: "{0} min de retard",
        onTime: "à l'heure", updated: "Mis à jour à {0}", local: "heure locale", ended: "Ce lien a expiré ou n'est pas valide.", by: "Partagé avec Skylog", reload: "La page s'actualise chaque minute." },
  it: { alt: "Quota", spd: "Velocità", left: "Mancano", climb: "in salita", desc: "in discesa", live: "Posizione in tempo reale alle {0}", est: "Posizione stimata (nessun dato in tempo reale)", title: "Stato del volo", dep: "Partenza", arr: "Arrivo", gate: "Gate", terminal: "Terminal", belt: "Nastro bagagli", delay: "{0} min di ritardo",
        onTime: "in orario", updated: "Aggiornato alle {0}", local: "ora locale", ended: "Questo link è scaduto o non è valido.", by: "Condiviso con Skylog", reload: "La pagina si aggiorna ogni minuto." },
  es: { alt: "Altitud", spd: "Velocidad", left: "Faltan", climb: "ascendiendo", desc: "descendiendo", live: "Posición en directo a las {0}", est: "Posición estimada (sin datos en directo)", title: "Estado del vuelo", dep: "Salida", arr: "Llegada", gate: "Puerta", terminal: "Terminal", belt: "Cinta de equipaje", delay: "{0} min de retraso",
        onTime: "a tiempo", updated: "Actualizado a las {0}", local: "hora local", ended: "Este enlace ha caducado o no es válido.", by: "Compartido con Skylog", reload: "La página se actualiza cada minuto." },
};
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const LOCALES = { de: "de-CH", en: "en-GB", fr: "fr-FR", it: "it-IT", es: "es-ES" };

// Runs in the visitor's browser: draws the great-circle route and the plane with Leaflet / OpenStreetMap.
// Kept as text on purpose: bundlers rewrite real functions (helper calls that don't exist in the browser).
const MAP_JS = String.raw`function mapScript(D) {
  var box = document.getElementById("map");
  // no map library (blocked or offline): show no empty box
  if (!window.L) { box.style.display = "none"; return; }
  try {
  var rad = Math.PI / 180;
  function gc(a, b, f) {      // point at fraction f on the great circle a → b
    var p1 = a[0] * rad, l1 = a[1] * rad, p2 = b[0] * rad, l2 = b[1] * rad;
    var d = 2 * Math.asin(Math.sqrt(Math.pow(Math.sin((p2 - p1) / 2), 2) + Math.cos(p1) * Math.cos(p2) * Math.pow(Math.sin((l2 - l1) / 2), 2)));
    if (d < 1e-9) return a;
    var A = Math.sin((1 - f) * d) / Math.sin(d), B = Math.sin(f * d) / Math.sin(d);
    var x = A * Math.cos(p1) * Math.cos(l1) + B * Math.cos(p2) * Math.cos(l2);
    var y = A * Math.cos(p1) * Math.sin(l1) + B * Math.cos(p2) * Math.sin(l2);
    var z = A * Math.sin(p1) + B * Math.sin(p2);
    return [Math.atan2(z, Math.sqrt(x * x + y * y)) / rad, Math.atan2(y, x) / rad];
  }
  function bearing(a, b) {
    var p1 = a[0] * rad, p2 = b[0] * rad, dl = (b[1] - a[1]) * rad;
    return (Math.atan2(Math.sin(dl) * Math.cos(p2), Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl)) / rad + 360) % 360;
  }
  var pts = [], prev = null;
  for (var i = 0; i <= 64; i++) {     // keep the line continuous across the date line
    var p = gc(D.from, D.to, i / 64);
    if (prev) { while (p[1] - prev[1] > 180) p[1] -= 360; while (p[1] - prev[1] < -180) p[1] += 360; }
    pts.push(p); prev = p;
  }
  var map = L.map("map", { zoomControl: false, attributionControl: true, scrollWheelZoom: false });
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 10, attribution: "© OpenStreetMap" }).addTo(map);
  L.polyline(pts, { color: "#7fb0ff", weight: 3, dashArray: "6 6" }).addTo(map);
  function label(pos, text) {
    L.circleMarker(pos, { radius: 5, color: "#fff", fillColor: "#7fb0ff", fillOpacity: 1, weight: 2 }).addTo(map);
    L.marker(pos, { icon: L.divIcon({ className: "apt", html: text, iconSize: [40, 16], iconAnchor: [20, -6] }), interactive: false }).addTo(map);
  }
  label(pts[0], D.fromCode); label(pts[pts.length - 1], D.toCode);
  var plane = D.pos, heading = D.track;
  if (!plane && D.frac > 0 && D.frac < 1) { plane = pts[Math.round(D.frac * 64)]; }
  if (plane) {
    // put the live position on the same side of the date line as the drawn route
    while (plane[1] - pts[0][1] > 180) plane[1] -= 360; while (plane[1] - pts[0][1] < -180) plane[1] += 360;
    if (heading == null) heading = bearing(plane, D.to);
    L.marker(plane, { icon: L.divIcon({ className: "plane", html: '<div style="transform:rotate(' + (heading - 90) + 'deg)">✈</div>', iconSize: [26, 26], iconAnchor: [13, 13] }), interactive: false }).addTo(map);
  }
  map.fitBounds(L.latLngBounds(pts).pad(0.15));
  } catch (e) { box.style.display = "none"; }
}`;

function t(lang, key, ...args) {
  const text = (TEXTS[lang] || TEXTS.de)[key] ?? TEXTS.de[key] ?? key;
  return text.replace(/\{(\d)\}/g, (_, i) => String(args[Number(i)] ?? ""));
}

export function createEngine({ cfg, state, save, sendPush, store = null, log = () => {} }) {
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
        if (ac && ac.lat != null) return { lat: ac.lat, lon: ac.lon, onGround: ac.alt_baro === "ground", gs: ac.gs, alt: ac.alt_baro, track: ac.track ?? ac.true_heading ?? null, rate: ac.baro_rate ?? ac.geom_rate ?? null };
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
    try { return new Date(iso).toLocaleTimeString(LOCALES[lang] || "de-CH", { hour: "2-digit", minute: "2-digit", timeZone: tz || "Europe/Zurich" }); }
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
      let p = await adsb(f.callsign);
      // ignore the 0°/0° placeholder and fixes far off the route (another aircraft with the same callsign)
      const sane = p && (Math.abs(p.lat) > 0.05 || Math.abs(p.lon) > 0.05) &&
        (f.fromLat == null || f.toLat == null ||
         distKm({ lat: f.fromLat, lon: f.fromLon }, p) + distKm(p, { lat: f.toLat, lon: f.toLon }) < distKm({ lat: f.fromLat, lon: f.fromLon }, { lat: f.toLat, lon: f.toLon }) * 1.6 + 400);
      if (p && !sane) p = null;
      if (p) snap.pos = { lat: p.lat, lon: p.lon, track: p.track, ground: !!p.onGround, t: now,
                          altFt: typeof p.alt === "number" ? p.alt : null, kt: typeof p.gs === "number" ? p.gs : null, fpm: typeof p.rate === "number" ? p.rate : null };
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
    // Public status page: the unguessable id in the link is the key
    if (req.method === "GET" && req.path.startsWith("/s/")) return statusPage(req.path.slice(3), req.language);
    if (!cfg.token || !safeEqual(req.authorization || "", `Bearer ${cfg.token}`)) return { status: 401, json: { error: "unauthorized" } };

    // Device sync: one opaque document per server, merged by the apps (the server only stores it)
    if (req.path === "/data" && store) {
      if (req.method === "GET") {
        const doc = await store.get();
        return { status: 200, json: { rev: doc?.rev || 0, data: doc?.data ?? null } };
      }
      if (req.method === "PUT") {
        let put;
        try { put = JSON.parse(req.body || ""); } catch { return { status: 400, json: { error: "json" } }; }
        if (typeof put.data !== "string" || put.data.length > 4_000_000) return { status: 413, json: { error: "too large" } };
        const cur = await store.get();
        // someone else wrote in between: the app must merge again
        if ((cur?.rev || 0) !== (put.rev || 0)) return { status: 409, json: { rev: cur?.rev || 0, data: cur?.data ?? null } };
        const rev = (cur?.rev || 0) + 1;
        await store.put({ rev, data: put.data });
        return { status: 200, json: { rev } };
      }
    }
    let body = {};
    try { body = req.body ? JSON.parse(req.body) : {}; } catch { return { status: 400, json: { error: "json" } }; }

    if (req.method === "POST" && req.path === "/sync") {
      if (!body.deviceToken || !/^[0-9a-f]{32,200}$/i.test(body.deviceToken)) return { status: 400, json: { error: "deviceToken" } };
      if (!state.devices[body.deviceToken] && Object.keys(state.devices).length >= (cfg.maxDevices || 20)) {
        return { status: 429, json: { error: "too many devices" } };
      }
      const dev = state.devices[body.deviceToken] || { flights: [], live: {}, last: {} };
      dev.flights = (body.flights || []).slice(0, 50).map((f) =>
        typeof f.share === "string" && !/^[A-Za-z0-9_-]{20,64}$/.test(f.share) ? { ...f, share: undefined } : f);
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

  function statusPage(id, language) {
    const lang = PAGE[(language || "").slice(0, 2).toLowerCase()] ? language.slice(0, 2).toLowerCase() : "en";
    const P = (k, ...a) => (PAGE[lang][k] || k).replace(/\{(\d)\}/g, (_, i) => String(a[Number(i)] ?? ""));
    let found = null;
    if (/^[A-Za-z0-9_-]{20,64}$/.test(id)) {
      for (const dev of Object.values(state.devices)) {
        const f = (dev.flights || []).find((x) => x.share === id);
        if (f) { found = { f, snap: (dev.last || {})[f.id] || {} }; break; }
      }
    }
    const page = (body, refresh) => ({
      status: found ? 200 : 404,
      html: `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
        `<meta name="robots" content="noindex,nofollow">${refresh ? '<meta http-equiv="refresh" content="60">' : ""}<title>${esc(P("title"))}</title>` +
        `<style>:root{color-scheme:light dark}body{margin:0;font:16px/1.4 -apple-system,system-ui,sans-serif;background:#0b1220;color:#f2f4f8}` +
        `main{max-width:460px;margin:0 auto;padding:24px 16px}.card{background:#172033;border-radius:18px;padding:20px;margin-bottom:14px}` +
        `.top{display:flex;justify-content:space-between;align-items:center;font-weight:600}.status{color:#7fb0ff}.late{color:#ffb454}.bad{color:#ff6b6b}` +
        `.time.ok{color:#f2f4f8}.was{font-size:14px;font-weight:500;color:#93a0b8;text-decoration:line-through}.lbl{margin-top:10px}` +
        `.route{display:flex;justify-content:space-between;align-items:flex-end;margin-top:14px}.code{font-size:34px;font-weight:800;line-height:1}` +
        `.time{font-size:22px;font-weight:700;font-variant-numeric:tabular-nums}.muted{color:#93a0b8;font-size:13px}.right{text-align:right}` +
        `.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.tile{background:#172033;border-radius:14px;padding:12px}` +
        `.tile b{display:block;font-size:19px;white-space:nowrap}.tile .muted{font-size:12px}#map{height:260px;border-radius:18px;margin-bottom:8px;background:#172033}` +
        `.plane{font-size:26px;line-height:26px;text-align:center;color:#ffb454;text-shadow:0 0 3px #000}.apt{font:700 12px system-ui;color:#fff;text-shadow:0 0 3px #000}</style></head><body><main>${body}<p class="muted">${esc(P("by"))}</p></main></body></html>`,
    });
    if (!found) return page(`<div class="card">${esc(P("ended"))}</div>`, false);
    const { f, snap } = found;
    const dep = snap.dep || f.dep, arr = snap.arr || f.arr;
    // statusKey = set by this server (translated here); otherwise the label the app sent
    // (viewer's language): the server's own status, else the app's status code, else the app's label
    const APP_STATE = { scheduled: "scheduled", unknown: "scheduled", delayed: "delayed", checkIn: "scheduled", boarding: "boarding", gateClosed: "boarding",
                        departed: "leftGate", enRoute: "inAir", approaching: "inAir", arrived: "landed", canceled: "cancelled", diverted: "diverted" };
    const status = snap.statusKey ? t(lang, snap.statusKey) : APP_STATE[f.state] ? t(lang, APP_STATE[f.state]) : (snap.statusLabel || f.statusLabel || t(lang, "scheduled"));
    const mins = (a, b) => (a && b ? Math.round((Date.parse(a) - Date.parse(b)) / 60000) : 0);
    // delay against the originally planned time (the app sends it); fall back to what FlightAware reported
    const delay = Math.max(0, f.depPlanned ? mins(dep, f.depPlanned) : (snap.delay || 0));
    const arrDelay = f.arrPlanned ? mins(arr, f.arrPlanned) : 0;
    const late = delay >= 5 && !snap.inAir && !snap.landed;
    const cls = (m) => (m >= 15 ? "bad" : m >= 5 ? "late" : "ok");
    const planned = (iso, tz, m) => (iso && Math.abs(m) >= 5 ? `<span class="was">${esc(fmtTime(iso, tz, lang))}</span> ` : "");
    const gate = snap.landed || snap.inAir ? snap.arrGate : (snap.gate || f.gate);
    const terminal = snap.landed || snap.inAir ? null : (snap.terminal || f.terminal);
    // Map: route, and the plane at its live position (ADS-B) or estimated along the route while in the air
    let map = "", mapNote = "";
    if (f.fromLat != null && f.toLat != null) {
      const nowMs = Date.now(), depMs = Date.parse(dep), arrMs = Date.parse(arr);
      const livePos = snap.pos && !snap.pos.ground && nowMs - snap.pos.t < 20 * MIN ? snap.pos : null;
      const frac = snap.landed ? 1 : snap.inAir && arrMs > depMs ? Math.min(1, Math.max(0, (nowMs - depMs) / (arrMs - depMs))) : 0;
      const data = { from: [f.fromLat, f.fromLon], to: [f.toLat, f.toLon], pos: livePos ? [livePos.lat, livePos.lon] : null,
                     track: livePos?.track ?? null, frac, fromCode: f.from, toCode: f.to };
      if (livePos) mapNote = P("live", fmtTime(new Date(livePos.t).toISOString(), f.depTz, lang));
      else if (snap.inAir && !snap.landed) mapNote = P("est");
      map = `<div id="map"></div>${mapNote ? `<p class="muted">${esc(mapNote)}</p>` : ""}` +
        `<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">` +
        `<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>` +
        `<script>var D=${JSON.stringify(data).replace(/</g, "\\u003c")};(${MAP_JS})(D);</script>`;
    }
    // Flight data while airborne (from the live position)
    let flightTiles = "";
    const lp = snap.pos && !snap.pos.ground && Date.now() - snap.pos.t < 20 * MIN && !snap.landed ? snap.pos : null;
    if (lp) {
      const num = (n) => Math.round(n).toLocaleString(LOCALES[lang] || "de-CH");
      const ft = (label, value, sub) => `<div class="tile"><span class="muted">${esc(label)}</span><b>${esc(value)}</b>${sub ? `<span class="muted">${esc(sub)}</span>` : ""}</div>`;
      if (lp.altFt != null) {
        const trend = lp.fpm > 300 ? P("climb") : lp.fpm < -300 ? P("desc") : "";
        flightTiles += ft(P("alt"), `${num(lp.altFt * 0.3048)} m`, `${num(lp.altFt)} ft${trend ? " · " + trend : ""}`);
      }
      if (lp.kt != null) flightTiles += ft(P("spd"), `${num(lp.kt * 1.852)} km/h`, `${num(lp.kt)} kt`);
      if (f.toLat != null) {
        const km = distKm(lp, { lat: f.toLat, lon: f.toLon });
        const mins = Math.max(0, Math.round((Date.parse(arr) - Date.now()) / MIN));
        flightTiles += ft(P("left"), `${num(km)} km`, mins > 0 ? (mins >= 60 ? `${Math.floor(mins / 60)} h ${mins % 60} min` : `${mins} min`) : "");
      }
    }
    const tile = (label, value) => (value ? `<div class="tile"><span class="muted">${esc(label)}</span><b>${esc(value)}</b></div>` : "");
    const tiles = tile(P("terminal"), terminal) + tile(P("gate"), gate) + tile(P("belt"), snap.landed || snap.inAir ? snap.belt : null);
    const updated = fmtTime(new Date(snap.faAt || Date.parse(dev_updated(f)) || Date.now()).toISOString(), f.depTz, lang);
    const body =
      // a delayed flight shows the delay instead of a contradicting "on time"
      `<div class="card"><div class="top"><span>${esc(f.number)}</span><span class="${late ? cls(delay) : "status"}">` +
      `${late ? esc(P("delay", delay)) : esc(status)}</span></div>` +
      `<div class="route"><div><div class="code">${esc(f.from)}</div><div class="muted">${esc(f.fromCity || "")}</div>` +
      `<div class="muted lbl">${esc(P("dep"))}</div><div class="time ${cls(delay)}">${planned(f.depPlanned, f.depTz, delay)}${esc(fmtTime(dep, f.depTz, lang))}</div></div>` +
      `<div class="right"><div class="code">${esc(f.to)}</div><div class="muted">${esc(f.toCity || "")}</div>` +
      `<div class="muted lbl">${esc(P("arr"))}</div><div class="time ${cls(arrDelay)}">${planned(f.arrPlanned, f.arrTz, arrDelay)}${esc(fmtTime(arr, f.arrTz, lang))}</div></div></div>` +
      `<p class="muted">${esc(P("local"))} · ${esc(P("updated", updated))}</p></div>` +
      map + (flightTiles ? `<div class="grid">${flightTiles}</div><p></p>` : "") + (tiles ? `<div class="grid">${tiles}</div><p></p>` : "") + `<p class="muted">${esc(P("reload"))}</p>`;
    return page(body, true);
  }
  // time of the device's last sync (shown when the server has not queried anything itself yet)
  function dev_updated(f) {
    for (const dev of Object.values(state.devices)) if ((dev.flights || []).includes(f)) return dev.updated;
    return null;
  }

  return { loop, handle };
}

function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
