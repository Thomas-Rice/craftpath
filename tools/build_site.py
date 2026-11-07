"""Builds the website into site/ (what Cloudflare Pages serves).

    npm ci && python3 tools/build_site.py

The planner page runs the addon's own Lua files, so they're copied in unchanged.
"""
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
WEB = os.path.join(ROOT, "web")
OUT = os.path.join(ROOT, "site")
SITE_URL = os.environ.get("SITE_URL", "https://craftpath.pages.dev")
LUA = ["Data/Shared.lua", "Data/Engineering.lua", "Data/Blacksmithing.lua", "Data/Cooking.lua",
       "Core/Recipes.lua", "Core/Planner.lua"]


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    for name in ("index.html", "updates.html"):
        copy(os.path.join(WEB, name), os.path.join(OUT, name))
    shutil.copytree(os.path.join(WEB, "assets"), os.path.join(OUT, "assets"))
    copy(os.path.join(WEB, "src", "engine.js"), os.path.join(OUT, "assets", "engine.js"))
    wm = os.path.join(ROOT, "node_modules", "wasmoon", "dist")
    copy(os.path.join(wm, "index.js"), os.path.join(OUT, "assets", "vendor", "wasmoon.js"))
    copy(os.path.join(wm, "glue.wasm"), os.path.join(OUT, "assets", "vendor", "glue.wasm"))
    fonts = {"anton": ["anton-latin-400-normal"], "inter-tight": [f"inter-tight-latin-{w}-normal" for w in (500, 600, 700)],
             "inter": [f"inter-latin-{w}-normal" for w in (400, 500, 600)]}
    for pkg, files in fonts.items():
        for f in files:
            copy(os.path.join(ROOT, "node_modules", "@fontsource", pkg, "files", f + ".woff2"),
                 os.path.join(OUT, "assets", "fonts", f + ".woff2"))
    for rel in LUA:
        copy(os.path.join(ROOT, "CraftPath", rel), os.path.join(OUT, "lua", rel))
    copy(os.path.join(WEB, "src", "bridge.lua"), os.path.join(OUT, "lua", "bridge.lua"))
    for name in ("prices.json", "recipe-changes.json"):
        copy(os.path.join(ROOT, "data", name), os.path.join(OUT, "data", name))

    with open(os.path.join(OUT, "_headers"), "w") as fh:
        fh.write("/lua/*\n  Content-Type: text/plain; charset=utf-8\n  Cache-Control: public, max-age=300\n"
                 "/data/*\n  Cache-Control: public, max-age=300\n"
                 "/assets/vendor/*\n  Cache-Control: public, max-age=604800\n"
                 "/assets/fonts/*\n  Cache-Control: public, max-age=31536000, immutable\n"
                 "/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n")
    with open(os.path.join(OUT, "robots.txt"), "w") as fh:
        fh.write(f"User-agent: *\nAllow: /\nSitemap: {SITE_URL}/sitemap.xml\n")
    with open(os.path.join(ROOT, "data", "recipe-changes.json"), encoding="utf-8") as fh:
        last = (json.load(fh) or [{}])[0].get("date", "")
    urls = [("", ""), ("updates.html", last)]
    with open(os.path.join(OUT, "sitemap.xml"), "w") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n')
        for path, mod in urls:
            fh.write(f"  <url><loc>{SITE_URL}/{path}</loc>" + (f"<lastmod>{mod}</lastmod>" if mod else "") + "</url>\n")
        fh.write("</urlset>\n")
    total = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(OUT) for f in fs)
    print(f"Built site/ ({total // 1024} KB)")


if __name__ == "__main__":
    main()
