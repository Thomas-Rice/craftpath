// Homepage: fills the profession cards and download details from site/data/summary.json.
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function gold(c) {
  if (c == null) return "—";
  const g = c / 10000;
  if (g >= 100) return `${Math.round(g).toLocaleString("en-GB")}g`;
  if (g >= 1) return `${Math.round(g)}g`;
  return `${Math.max(1, Math.round(c / 100))}s`;
}

const BLURB = {
  Alchemy: "Potions, elixirs and transmutes.",
  Blacksmithing: "Weapons, armour and stones, with Merchant's Favor plans.",
  Enchanting: "Enchants, rods and oils.",
  Engineering: "Bombs, goggles and gadgets, with Goblin and Gnomish recipes.",
  Leatherworking: "Armour, kits and cured hides.",
  Tailoring: "Cloth armour, bags and bolts.",
  Mining: "Smelting bars from ore.",
  Cooking: "The cheapest secondary profession, including the Artisan quest.",
  "First Aid": "Bandages, from linen to runecloth.",
};
const ORDER = Object.keys(BLURB);

async function main() {
  try {
    const s = await fetch("data/summary.json").then((r) => r.json());
    if (s.updated) {
      const d = new Date(s.updated).toLocaleDateString("en-GB", { day: "numeric", month: "long" });
      document.getElementById("pricedOn").textContent = `Cheapest routes at auction house prices from ${d} (Horde). The addon uses your own live prices.`;
    }
    document.getElementById("profCards").innerHTML = Object.entries(s.professions).sort((a, b) => ORDER.indexOf(a[0]) - ORDER.indexOf(b[0]))
      .map(([name, p]) => {
        const full = p.full && p.full.to === 300
          ? `<div class="pc-row"><span>1 → 300</span><b>${gold(p.full.total)}</b></div>`
          : `<div class="pc-row muted"><span>Above ${p.full ? p.full.to : 225}</span><span>waiting on auction house supply</span></div>`;
        return `<a class="prof-card" href="planner.html#p=${encodeURIComponent(name)}">
          <span class="pc-name">${esc(name)}</span>
          <span class="pc-blurb">${esc(BLURB[name] || "")}</span>
          <div class="pc-row big"><span>1 → 225</span><b>${p.expert ? gold(p.expert.total) : "—"}</b></div>
          ${full}
          <span class="pc-foot">${p.recipes} recipes · plan it →</span>
        </a>`;
      }).join("");
    if (s.version) {
      document.getElementById("dlMeta").textContent = `Version ${s.version} · free · works for Horde and Alliance`;
      document.getElementById("dlLink").textContent = `Download CraftPath ${s.version}`;
    }
  } catch {
    /* the static cards still link to the planner */
  }
}
main();
