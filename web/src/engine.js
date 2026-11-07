// Loads CraftPath's Lua planner into a wasmoon Lua VM. Works in the browser and in Node (tests).
export const LUA_FILES = ["Data/Shared.lua", "Data/Engineering.lua", "Data/Blacksmithing.lua", "Data/Cooking.lua",
  "Core/Recipes.lua", "Core/Planner.lua"];

export async function createEngine(LuaFactory, readText, wasmURL) {
  const factory = new LuaFactory(wasmURL);
  const lua = await factory.createEngine();
  await lua.doString("CP_NS = {}");
  for (const f of LUA_FILES) {
    lua.global.set("CP_SRC", await readText("lua/" + f));
    lua.global.set("CP_NAME", "@" + f);
    await lua.doString("assert(load(CP_SRC, CP_NAME))('CraftPath', CP_NS)");
  }
  await lua.doString(await readText("lua/bridge.lua"));
  const planFn = lua.global.get("CP_Plan");
  const dataFn = lua.global.get("CP_Data");
  return {
    plan: (opts) => JSON.parse(planFn(JSON.stringify(opts))),
    data: () => JSON.parse(dataFn()),
  };
}
