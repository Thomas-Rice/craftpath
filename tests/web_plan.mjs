// Runs plans through the website's engine (wasmoon) for tests/test_web.py.
// usage: node tests/web_plan.mjs cases.json > results.json
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
const cases = JSON.parse(await readFile(process.argv[2], "utf8"));
const out = cases.map((c) => engine.plan(c));
process.stdout.write(JSON.stringify({ data: engine.data(), plans: out }));
