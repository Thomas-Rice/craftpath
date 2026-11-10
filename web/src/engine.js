// Loads CraftPath's Lua planner into a wasmoon Lua VM. Works in the browser and in Node (tests).
// The addon's pure-Lua files in load order (lua/files.json, written by the site build from the .toc).
export function luaFilesFromToc(toc) {
  const files = toc.split(/\r?\n/).map((l) => l.trim().replace(/\\/g, "/")).filter((l) => l && !l.startsWith("#"));
  const core = ["Core/Recipes.lua", "Core/Planner.lua", "Core/Profit.lua"];
  return [...files.filter((f) => f.startsWith("Data/")), ...files.filter((f) => core.includes(f))];
}

export async function createEngine(LuaFactory, readText, wasmURL) {
  const factory = new LuaFactory(wasmURL);
  const lua = await factory.createEngine();
  await lua.doString("CP_NS = {}");
  const files = JSON.parse(await readText("lua/files.json"));
  for (const f of files) {
    lua.global.set("CP_SRC", await readText("lua/" + f));
    lua.global.set("CP_NAME", "@" + f);
    await lua.doString("assert(load(CP_SRC, CP_NAME))('CraftPath', CP_NS)");
  }
  await lua.doString(await readText("lua/bridge.lua"));
  const planFn = lua.global.get("CP_Plan");
  const dataFn = lua.global.get("CP_Data");
  const profitFn = lua.global.get("CP_Profit");
  return {
    profit: (opts) => JSON.parse(profitFn(JSON.stringify(opts))),
    plan: (opts) => JSON.parse(planFn(JSON.stringify(opts))),
    data: () => JSON.parse(dataFn()),
  };
}
