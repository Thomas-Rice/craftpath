// CraftPath planner page. The planning itself is the addon's Lua code, run by wasmoon.
import { createEngine } from "./engine.js";

const $ = (id) => document.getElementById(id);
const store = {
  get(k, d) { try { const v = localStorage.getItem("cp." + k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem("cp." + k, JSON.stringify(v)); } catch { /* private mode */ } },
};

const PROFESSIONS = ["Engineering", "Blacksmithing", "Cooking"];
const BETA_LEVEL = 30;

let engine, snapshot, overrides = store.get("prices", {}), lastPlan;
const state = Object.assign({
  profession: "Engineering", from: 1, to: 300, faction: "Horde", spec: "",
  allowRecipeItems: true, allowFavor: true, levelCap: true,
}, store.get("settings", {}), fromHash());

// ---------- money ----------
export function money(c, { plain = false } = {}) {
  if (c == null || isNaN(c)) return "—";
  c = Math.round(c);
  const g = Math.floor(c / 10000), s = Math.floor((c % 10000) / 100), cu = c % 100;
  const parts = [];
  if (g) parts.push([g, "g", "gold"]);
  if (s || (g && cu)) parts.push([s, "s", "silver"]);
  if (cu || !parts.length) parts.push([cu, "c", "copper"]);
  if (plain) return parts.map(([n, u]) => n + u).join(" ");
  return parts.map(([n, u, cls]) => `<span class="coin ${cls}">${n.toLocaleString("en-GB")}${u}</span>`).join(" ");
}

function parseMoney(text) {
  text = String(text).trim().toLowerCase();
  if (!text) return null;
  if (/^\d+(\.\d+)?$/.test(text)) return Math.round(parseFloat(text) * 10000); // bare number = gold
  let total = 0, matched = false;
  for (const [, n, u] of text.matchAll(/(\d+(?:\.\d+)?)\s*([gsc])/g)) {
    matched = true;
    total += parseFloat(n) * (u === "g" ? 10000 : u === "s" ? 100 : 1);
  }
  return matched ? Math.round(total) : null;
}

// Empty Lua tables arrive as {} rather than [].
const arr = (x) => (Array.isArray(x) ? x : []);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// ---------- settings in the URL so a plan can be shared ----------
function fromHash() {
  const p = new URLSearchParams(location.hash.slice(1));
  const o = {};
  if (PROFESSIONS.includes(p.get("p"))) o.profession = p.get("p");
  if (p.get("from")) o.from = +p.get("from");
  if (p.get("to")) o.to = +p.get("to");
  if (["Horde", "Alliance"].includes(p.get("f"))) o.faction = p.get("f");
  return o;
}
function saveState() {
  store.set("settings", state);
  const p = new URLSearchParams({ p: state.profession, from: state.from, to: state.to, f: state.faction });
  history.replaceState(null, "", "#" + p);
}

// ---------- plan ----------
function prices() {
  const out = {};
  for (const [k, v] of Object.entries(snapshot.prices)) out[k] = v.p;
  for (const [k, v] of Object.entries(overrides)) if (v != null) out[k] = v;
  return out;
}

function run() {
  saveState();
  const from = Math.max(1, Math.min(299, Math.round(+state.from || 1)));
  const to = Math.max(from + 1, Math.min(300, Math.round(+state.to || 300)));
  const plan = engine.plan({
    profession: state.profession, from, to, faction: state.faction,
    spec: state.profession === "Engineering" && state.spec ? state.spec : null,
    allowRecipeItems: state.allowRecipeItems, allowFavor: state.allowFavor,
    charLevel: state.levelCap ? BETA_LEVEL : null,
    prices: prices(), vendor: snapshot.vendor,
  });
  lastPlan = plan;
  priceNote();
  render(plan);
}

function whereText(w) {
  if (!w) return "";
  let t = "";
  if (w.quest) t = `Quest “${esc(w.quest)}”` + (w.npc ? ` from ${esc(w.npc)}` : "") + (w.where ? `, ${esc(w.where)}` : "");
  else if (w.npc) t = `${esc(w.npc)}` + (w.where ? `, ${esc(w.where)}` : "");
  else if (w.where) t = esc(w.where);
  if (w.also) t += `. Also sold by ${esc(w.also)}`;
  if (w.note) t += `. ${esc(w.note)}`;
  return t;
}

const HOW = {
  auto: "Learned automatically", trainer: "Trainer", known: "Already known", favor: "Merchant's Favor",
  vendor: "Vendor", "vendor-est": "Vendor (price estimated)", ah: "Auction house", quest: "Quest reward",
  "not at trainer": "Not at your trainer", "other faction": "Other faction only",
};

function learnLine(how, cost, where, favor, item) {
  const bits = [HOW[how] || how];
  if (cost) bits.push(money(cost));
  if (favor) bits.push(`${favor} Merchant's Favor`);
  let t = bits.join(" · ");
  if (how === "ah" && item) t += ` <span class="muted">(${esc(item)})</span>`;
  const w = whereText(where);
  if (w) t += `<div class="where">${w}</div>`;
  return t;
}

function render(plan) {
  $("loading").hidden = true;
  if (plan.error) {
    $("result").hidden = true;
    $("error").hidden = false;
    const blocked = arr(plan.blocked).slice(0, 6).map((b) =>
      `<li>${esc(b.recipe)}: needs a price for ${esc(arr(b.missing).join(", "))}</li>`).join("");
    $("error").innerHTML = `<strong>${esc(plan.error)}</strong>` +
      (blocked ? `<p>Add a price on the Prices tab for one of these to continue:</p><ul>${blocked}</ul>` : "");
    renderPrices(plan);
    return;
  }
  $("error").hidden = true;
  $("result").hidden = false;
  $("tTotal").innerHTML = money(plan.total);
  $("tExpected").innerHTML = money(plan.expectedGold);
  $("tSteps").textContent = `${arr(plan.steps).length} steps`;
  $("tRange").textContent = `skill ${plan.from} to ${plan.to}`;

  $("notes").innerHTML = arr(plan.notes).map((n) => `<li>${esc(n)}</li>`).join("");

  $("route").innerHTML = arr(plan.steps).map((s, i) => {
    const r = s.recipe;
    const mats = arr(r.reagents).map((g) => `${g.qty} × ${esc(g.name)}`).join(", ");
    const learn = s.learnHow && !["auto", "known"].includes(s.learnHow) || s.learnWhere
      ? `<div class="learn">${learnLine(s.learnHow, s.learnCost, s.learnWhere, s.learnFavor, s.learnItem)}</div>` : "";
    const stock = s.usesStock ? `<span class="badge">uses your stock</span>` : "";
    return `<li class="step">
      <div class="range"><span>${s.from}</span><span class="arrow">→</span><span>${s.to}</span></div>
      <div class="body">
        <div class="name">${esc(r.name)} ${stock}</div>
        <div class="meta">Craft about ${s.crafts}${r.makes > 1 ? ` (makes ${r.makes} each)` : ""} · ${money(s.costPerCraft)} each</div>
        <details><summary>Materials and colours</summary>
          <div class="mats">${mats}</div>
          <div class="colours"><span class="c-or">${r.orange}</span><span class="c-ye">${r.yellow}</span><span class="c-gr">${r.green}</span><span class="c-gy">${r.grey}</span></div>
        </details>
        ${learn}
      </div>
    </li>`;
  }).join("");

  $("shopping").innerHTML = arr(plan.shopping).map((b) => `
    <div class="line">
      <span class="qty">${b.buy}×</span>
      <span class="item">${esc(b.name)}${b.source === "vendor" ? ' <span class="badge">vendor</span>' : ""}${overrides[b.name] != null ? ' <span class="badge mine">your price</span>' : ""}</span>
      <span class="unit">${money(b.unit)}</span>
      <span class="total">${money(b.total)}</span>
    </div>`).join("") || `<p class="muted">Nothing to buy.</p>`;
  $("buyTotal").innerHTML = money(plan.buyTotal);

  const crafts = arr(plan.craftYourself);
  $("craftPanel").hidden = !crafts.length;
  $("craftYourself").innerHTML = crafts.map((c) => `<li>${c.crafts}× ${esc(c.name)}</li>`).join("");

  const learn = arr(plan.learn);
  $("learnPanel").hidden = !learn.length;
  $("learn").innerHTML = learn.map((l) => `
    <div class="line learnline">
      <span class="qty">${l.at ?? ""}</span>
      <span class="item">${esc(l.recipe)}<div class="where">${learnLine(l.how, null, l.where, l.favor, l.item)}</div></span>
      <span class="total">${l.cost ? money(l.cost) : l.favor ? "Favor" : "free"}</span>
    </div>`).join("");
  $("learnTotal").innerHTML = money(plan.learnTotal);

  renderPrices(plan);
}

// ---------- prices tab ----------
let reagentNames = {};
function renderPrices(plan) {
  const used = new Set(arr(plan && plan.shopping).map((b) => b.name));
  const names = arr(reagentNames[state.profession]);
  const q = $("priceSearch").value.trim().toLowerCase();
  const rows = names.filter((n) => !q || n.toLowerCase().includes(q))
    .sort((a, b) => (used.has(b) - used.has(a)) || a.localeCompare(b));
  $("priceList").innerHTML = rows.map((n) => {
    const snap = snapshot.prices[n], vend = snapshot.vendor[n];
    const mine = overrides[n];
    const shown = mine ?? (snap ? snap.p : null);
    return `<div class="line priceline${used.has(n) ? " used" : ""}">
      <span class="item">${esc(n)}${used.has(n) ? ' <span class="badge">on your list</span>' : ""}
        <div class="where">${snap ? `Scanned ${money(snap.p)}${snap.q ? `, ${snap.q.toLocaleString("en-GB")} listed` : ""}` : "Not seen on the auction house"}${vend ? ` · vendor ${money(vend)}` : ""}</div></span>
      <input class="price-input${mine != null ? " mine" : ""}" data-item="${esc(n)}" value="${shown != null ? money(shown, { plain: true }) : ""}" placeholder="e.g. 1g 20s" aria-label="Price of ${esc(n)}">
    </div>`;
  }).join("");
}

$("priceList").addEventListener("change", (e) => {
  const el = e.target.closest(".price-input");
  if (!el) return;
  const name = el.dataset.item, v = parseMoney(el.value);
  const snap = snapshot.prices[name];
  if (el.value.trim() === "" || (snap && v === snap.p)) delete overrides[name];
  else if (v != null) overrides[name] = v;
  else { el.classList.add("bad"); return; }
  store.set("prices", overrides);
  run();
});
$("priceSearch").addEventListener("input", () => renderPrices(lastPlan));
$("resetPrices").addEventListener("click", () => { overrides = {}; store.set("prices", overrides); run(); });

// ---------- controls ----------
function setupControls() {
  $("profTabs").innerHTML = PROFESSIONS.map((p) =>
    `<button role="tab" class="prof" data-prof="${p}" aria-selected="${p === state.profession}"><img src="assets/${p.toLowerCase()}.svg" alt="" width="22" height="22">${p}</button>`).join("");
  $("profTabs").addEventListener("click", (e) => {
    const b = e.target.closest("[data-prof]");
    if (!b) return;
    state.profession = b.dataset.prof;
    for (const el of $("profTabs").children) el.setAttribute("aria-selected", el.dataset.prof === state.profession);
    $("specField").hidden = state.profession !== "Engineering";
    $("allowFavor").closest("label").hidden = state.profession === "Cooking";
    run();
  });
  $("specField").hidden = state.profession !== "Engineering";
  $("allowFavor").closest("label").hidden = state.profession === "Cooking";
  for (const id of ["from", "to", "faction", "spec"]) {
    $(id).value = state[id];
    $(id).addEventListener("change", () => { state[id] = $(id).type === "number" ? +$(id).value : $(id).value; run(); });
  }
  for (const id of ["allowRecipeItems", "allowFavor", "levelCap"]) {
    $(id).checked = !!state[id];
    $(id).addEventListener("change", () => { state[id] = $(id).checked; run(); });
  }
  document.querySelectorAll(".tabs .tab").forEach((t) => t.addEventListener("click", () => {
    document.querySelectorAll(".tabs .tab").forEach((x) => x.setAttribute("aria-selected", x === t));
    document.querySelectorAll(".tabpanel").forEach((p) => { p.hidden = p.id !== "tab-" + t.dataset.tab; });
  }));
}

function priceNote() {
  const d = snapshot.updated ? new Date(snapshot.updated) : null;
  const when = d ? d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "unknown";
  const n = Object.keys(overrides).length;
  $("priceNote").innerHTML = `Prices from an auction house scan on <strong>${when}</strong> (Horde). ` +
    (n ? `You've changed ${n} price${n > 1 ? "s" : ""}. ` : "") + `Edit them on the Prices tab to match your realm.`;
}

async function main() {
  try {
    const text = (p) => fetch(p).then((r) => { if (!r.ok) throw new Error(p + " " + r.status); return r.text(); });
    const [eng, snap] = await Promise.all([
      createEngine(window.wasmoon.LuaFactory, text, new URL("vendor/glue.wasm", import.meta.url).href),
      fetch("data/prices.json").then((r) => r.json()),
    ]);
    engine = eng; snapshot = snap;
    const data = engine.data();
    for (const [p, v] of Object.entries(data.professions)) reagentNames[p] = v.reagents;
    setupControls();
    run();
  } catch (err) {
    $("loading").hidden = true;
    $("error").hidden = false;
    $("error").textContent = "The planner couldn't load: " + err.message;
  }
}

if (typeof document !== "undefined" && $("profTabs")) main();
