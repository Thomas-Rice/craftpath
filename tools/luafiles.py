"""The addon's pure-Lua files (no game API), in .toc load order: every Data file, then the
recipe, planner and profit code. Tests, the website build and the price export all use this
list, so a new profession only needs adding to CraftPath.toc."""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CraftPath")
PURE_CORE = ["Core/Recipes.lua", "Core/Planner.lua", "Core/Profit.lua"]


def pure_files(root=ROOT):
    with open(os.path.join(root, "CraftPath.toc"), encoding="utf-8") as fh:
        files = [l.strip().replace("\\", "/") for l in fh if l.strip() and not l.startswith("#")]
    data = [f for f in files if f.startswith("Data/")]
    return data + [f for f in files if f in PURE_CORE]
