"""CraftPath works on its own, without its companion Prophet: loads, plans, records a
purchase, and points /cpath profit at Prophet instead of erroring."""
import os
import sys

from lupa import lua51

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_addon  # noqa: E402  (stubbed WoW API)


def main():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(check_addon.STUBS)
    toc = open(os.path.join(check_addon.ROOT, "CraftPath.toc"), encoding="utf-8").read().splitlines()
    ns = lua.table()
    loader = lua.eval("function(src, name) return assert(loadstring(src, name)) end")
    for rel in [l.strip().replace("\\", "/") for l in toc if l.strip() and not l.startswith("##")]:
        with open(os.path.join(check_addon.ROOT, rel), encoding="utf-8") as fh:
            loader(fh.read(), "@" + rel)("CraftPath", ns)
    G = lua.globals()
    printed = []
    ns.Print = lambda msg: printed.append(str(msg))
    G.__fire("ADDON_LOADED", "CraftPath")
    G.__fire("PLAYER_LOGIN")
    assert ns.ProfitUI is None and ns.LedgerUI is None and ns.pdb is None
    G.SlashCmdList.CRAFTPATH("profit")
    assert any("Prophet" in p for p in printed), printed
    G.SlashCmdList.CRAFTPATH("history")
    ns.Shopping.Record("Copper Bar", 5, 100)  # no History to record into: fine
    G.SlashCmdList.CRAFTPATH("")
    G.__runTimers()
    assert G.CraftPathFrame.__shown
    check_addon.check_layout(G, "CraftPathFrame")
    print("CraftPath alone (no Prophet): OK")


if __name__ == "__main__":
    main()
