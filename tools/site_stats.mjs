// Works out headline costs for the homepage from the current prices, with the same planner.
// usage: node tools/site_stats.mjs > site/data/summary.json
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createEngine } from "../web/src/engine.js";

const require = createRequire(import.meta.url);
const { LuaFactory } = require("wasmoon");
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (rel) => readFile(rel.startsWith("lua/bridge") ? path.join(root, "web/src/bridge.lua")
  : path.join(root, "CraftPath", rel.replace(/^lua\//, "")), "utf8");

const engine = await createEngine(LuaFactory, read);
const snap = JSON.parse(await readFile(path.join(root, "data/prices.json"), "utf8"));
const prices = Object.fromEntries(Object.entries(snap.prices).map(([k, v]) => [k, v.p]));
const base = { from: 1, faction: "Horde", charLevel: 60, prices, vendor: snap.vendor };

function plan(profession, to) {
  let p = engine.plan({ ...base, profession, to });
  const stuck = p.error && /past skill (\d+)/.exec(p.error);
  if (stuck) p = engine.plan({ ...base, profession, to: +stuck[1] });
  if (p.error) return null;
  return { to: p.to, total: Math.round(p.total), expected: Math.round(p.expectedGold), steps: p.steps.length };
}

const data = engine.data();
const out = { updated: snap.updated, professions: {} };
for (const prof of Object.keys(data.professions)) {
  out.professions[prof] = { recipes: data.professions[prof].count, expert: plan(prof, 225), full: plan(prof, 300) };
}
process.stdout.write(JSON.stringify(out, null, 1) + "\n");
