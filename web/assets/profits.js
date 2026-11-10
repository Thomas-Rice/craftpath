// Profits page: the addon's profit finder (Core/Profit.lua) run in the browser on the site's prices.
import { createEngine } from "./engine.js";

const $ = (id) => document.getElementById(id);
const store = {
  get(k, d) { try { const v = localStorage.getItem("cp." + k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem("cp." + k, JSON.stringify(v)); } catch { /* private mode */ } },
};
const arr = (x) => (Array.isArray(x) ? x : []);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const ORDER = ["Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Mining", "Cooking", "First Aid"];
const SHOW = 60;

function money(c) {
  if (c == null || isNaN(c)) return "—";
  const neg = c < 0; c = Math.round(Math.abs(c));
  const g = Math.floor(c / 10000), s = Math.floor((c % 10000) / 100), cu = c % 100;
  const parts = [];
  if (g) parts.push(`<span class="coin gold">${g.toLocaleString("en-GB")}g</span>`);
  if (s || (g && cu)) parts.push(`<span class="coin silver">${s}s</span>`);
  if ((cu || !parts.length) && !g) parts.push(`<span class="coin copper">${cu}c</span>`);
  return (neg ? "−" : "") + parts.join(" ");
}

const HOW = {
  trainer: "Trainer", auto: "Learned automatically", favor: "Merchant's Favor", quest: "Quest reward",
  vendor: "Vendor", "vendor-est": "Vendor", ah: "Auction house", "not at trainer": "Not at trainers yet",
  "other faction": "Other faction only", goblin: "Goblin Engineering only", gnomish: "Gnomish Engineering only",
};
function learnText(e) {
  let t = HOW[e.learnHow] || "Drop or rare recipe";
  if (e.learnCost) t += " · " + money(e.learnCost);
  const w = e.learnWhere;
  if (w) {
    const who = w.quest ? `quest “${esc(w.quest)}”` + (w.npc ? ` from ${esc(w.npc)}` : "") : esc(w.npc || "");
    if (who || w.where) t += ` · ${who}${who && w.where ? ", " : ""}${esc(w.where || "")}`;
  }
  if (e.payback) t += ` · pays for itself after ${e.payback} crafts`;
  return t;
}

let all = [], snapshot;
let mine = new Set(store.get("myProfs", []));
const state = Object.assign({ showAll: false, onlyEasy: false, sort: "safe", find: "" }, store.get("profitView", {}));

const keyOf = (e) => state.sort === "profit" ? (e.profit ?? e.vendorProfit ?? -1e12)
  : state.sort === "margin" ? (e.margin ?? -1e12)
  : Math.max(e.safeProfit ?? -1e12, e.vendorProfit ?? -1e12);

function card(e, idx) {
  const badges = [];
  if (e.vendorProfit > 0) badges.push(`<span class="badge vendor">vendor pays more</span>`);
  if (e.swings) badges.push(`<span class="badge short">price swings</span>`);
  if (e.listed > 40) badges.push(`<span class="badge">${e.listed} listed</span>`);
  const mats = arr(e.materials).map((m) => `<div class="mat"><span class="mq">${m.qty}×</span><span>${esc(m.name)} <span class="muted">(${m.how === "craft" ? "craft it" : m.how === "vendor" ? "vendor" : "auction house"})</span></span><span class="mp">${money(m.unit * m.qty)}</span></div>`).join("");
  const st = e.stats;
  return `<article class="profit${idx >= SHOW ? " more-hidden" : ""}"${idx >= SHOW ? " hidden" : ""}>
    <div class="p-main">
      <div class="p-name">${esc(e.name)}${e.makes > 1 ? ` <span class="muted">×${e.makes}</span>` : ""}</div>
      <div class="p-meta"><span class="ptag">${esc(e.profession)} ${e.skill}</span> ${badges.join(" ")}</div>
    </div>
    <div class="p-nums">
      <div><span class="l">Cost</span>${money(e.cost)}</div>
      <div><span class="l">Sells for</span>${money(e.sale ?? e.vendorSell)}</div>
      <div class="big"><span class="l">${state.sort === "profit" ? "Profit" : "Safe profit"}</span>${money(state.sort === "profit" ? (e.profit ?? e.vendorProfit) : Math.max(e.safeProfit ?? -1e12, e.vendorProfit ?? -1e12))}</div>
    </div>
    <details><summary>Materials, prices and where to get the recipe</summary>
      <div class="mats">${mats}</div>
      <div class="p-facts">
        ${e.price != null ? `<div>Lowest on the auction house ${money(e.price)} → ${money(e.sale)} after the 5% cut · profit ${money(e.profit)}</div>` : ""}
        ${st ? `<div>Last ${st.days} days: low ${money(st.low)}, middle ${money(st.median)}, high ${money(st.high)}</div>` : ""}
        ${e.vendorSell ? `<div>A vendor pays ${money(e.vendorSell)}${e.vendorProfit > 0 ? ` (guaranteed ${money(e.vendorProfit)} profit)` : ""}</div>` : ""}
        ${e.listed ? `<div>${e.listed} listed at the last scan</div>` : ""}
        <div class="learn">${learnText(e)}</div>
      </div>
    </details>
  </article>`;
}

function section(title, list) {
  if (!list.length) return "";
  const more = list.length > SHOW ? `<button class="ghost more" type="button">Show all ${list.length}</button>` : "";
  return `<h2 class="section-title p-section">${title}</h2>${list.map(card).join("")}${more}`;
}

function render() {
  store.set("profitView", state); store.set("myProfs", [...mine]);
  $("myProfs").innerHTML = ORDER.map((p) => `<button type="button" class="chip" aria-pressed="${mine.has(p)}" data-p="${esc(p)}">${esc(p)}</button>`).join("");
  $("showAll").checked = state.showAll; $("onlyEasy").checked = state.onlyEasy; $("sort").value = state.sort;
  const q = state.find.trim().toLowerCase();
  const ok = (e) => (!state.onlyEasy || ["trainer", "auto"].includes(e.learnHow) || ["A", "T"].includes(e.source))
    && (!q || e.name.toLowerCase().includes(q) || arr(e.materials).some((m) => m.name.toLowerCase().includes(q)));
  const list = all.filter(ok).sort((a, b) => keyOf(b) - keyOf(a));
  const noneChosen = mine.size === 0;
  const yours = noneChosen ? [] : list.filter((e) => mine.has(e.profession));
  const rest = (state.showAll || noneChosen) ? list.filter((e) => !mine.has(e.profession)) : [];
  $("heroNum").textContent = noneChosen ? list.length : yours.length;
  $("heroText").textContent = noneChosen
    ? "Profitable crafts across every profession at today's prices. Choose your professions below to put yours first."
    : `Profitable crafts for ${[...mine].join(", ")} at today's prices, after the auction house's 5% cut.`;
  $("list").innerHTML = (noneChosen ? "" : section("Your professions", yours) || `<div class="panel muted">Nothing in your professions makes a profit at these prices.</div>`)
    + section(noneChosen ? "Every profession" : "Other professions", rest)
    + (!state.showAll && !noneChosen ? `<button class="btn show-all" type="button">Show other professions too</button>` : "");
}

$("myProfs").addEventListener("click", (ev) => {
  const b = ev.target.closest("[data-p]"); if (!b) return;
  const p = b.dataset.p; mine.has(p) ? mine.delete(p) : mine.add(p); render();
});
$("list").addEventListener("click", (ev) => {
  if (ev.target.closest(".show-all")) { state.showAll = true; render(); return; }
  const b = ev.target.closest(".more"); if (!b) return;
  let el = b.previousElementSibling;
  while (el && el.classList.contains("profit")) { el.hidden = false; el = el.previousElementSibling; }
  b.remove();
});
$("showAll").addEventListener("change", (e) => { state.showAll = e.target.checked; render(); });
$("onlyEasy").addEventListener("change", (e) => { state.onlyEasy = e.target.checked; render(); });
$("sort").addEventListener("change", (e) => { state.sort = e.target.value; render(); });
$("find").addEventListener("input", (e) => { state.find = e.target.value; render(); });

async function main() {
  try {
    const text = (p) => fetch(p).then((r) => { if (!r.ok) throw new Error(p + " " + r.status); return r.text(); });
    const [engine, snap] = await Promise.all([
      createEngine(window.wasmoon.LuaFactory, text, new URL("vendor/glue.wasm", import.meta.url).href),
      fetch("data/prices.json").then((r) => r.json()),
    ]);
    snapshot = snap;
    const res = engine.profit({ prices: snap.prices, vendor: snap.vendor, faction: "Horde" });
    if (res.error) throw new Error(res.error);
    all = arr(res);
    const d = snap.updated ? new Date(snap.updated).toLocaleString("en-GB", { day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }) : "unknown";
    $("priceNote").innerHTML = $("priceNote2").innerHTML = `Prices from an auction house scan on <strong>${d}</strong> (Horde). Your realm will differ a little.`;
    $("loading").hidden = true;
    render();
  } catch (err) {
    $("loading").hidden = true; $("error").hidden = false;
    $("error").textContent = "The profit finder couldn't load: " + err.message;
  }
}
main();
