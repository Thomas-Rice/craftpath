// Renders data/recipe-changes.json (written by the daily recipe sync).
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const SHOW = 12; // items shown per list before "show all"

function list(items, cls, label, fmt) {
  if (!items.length) return "";
  const li = items.map((x, i) => `<li${i >= SHOW ? " hidden" : ""}><span class="tag ${cls}">${label}</span>${fmt(x)}</li>`).join("");
  const more = items.length > SHOW ? `<button class="ghost more" type="button">Show all ${items.length}</button>` : "";
  return `<ul>${li}</ul>${more}`;
}

async function main() {
  const box = document.getElementById("runs");
  try {
    const runs = await fetch("data/recipe-changes.json").then((r) => r.json());
    if (!runs.length) { box.innerHTML = `<div class="panel muted">No changes recorded yet.</div>`; return; }
    box.innerHTML = runs.map((run) => {
      const date = new Date(run.date + "T12:00:00Z").toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
      const profs = run.professions.map((p) => `
        <div class="prof-change">
          <h3><img src="assets/${p.profession.toLowerCase()}.svg" alt="" width="20" height="20">${esc(p.profession)}</h3>
          <div class="counts">${p.before} → ${p.after} recipes · ${p.added.length} new, ${p.removed.length} removed, ${p.changed.length} changed</div>
          ${list(p.added, "new", "New", (a) => `<strong>${esc(a.name)}</strong> <span class="muted">skill ${a.skill}, ${esc(a.source)}${a.materials ? ` · ${esc(a.materials)}` : ""}</span>`)}
          ${list(p.removed, "gone", "Removed", (a) => `<strong>${esc(a.name)}</strong> <span class="muted">skill ${a.skill}</span>`)}
          ${list(p.changed, "chg", "Changed", (a) => `<strong>${esc(a.name)}</strong> <span class="muted">${esc(a.change)}</span>`)}
        </div>`).join("");
      return `<article class="panel run"><h2>${date} <small>game build ${esc(run.build)}</small></h2>${profs}</article>`;
    }).join("");
    box.addEventListener("click", (e) => {
      const b = e.target.closest(".more");
      if (!b) return;
      b.previousElementSibling.querySelectorAll("li[hidden]").forEach((li) => { li.hidden = false; });
      b.remove();
    });
  } catch (err) {
    box.innerHTML = `<div class="panel error">Couldn't load the updates: ${esc(err.message)}</div>`;
  }
}
main();
