#!/usr/bin/env python3
"""Builds the GitHub Pages site into _site/.

Hand-written pages are HTML fragments in site/pages/; PRIVACY.md and NETWORK.md are rendered from the repo
root with pandoc, so the site can never disagree with them. Every page shares site/layout.html.

    python3 scripts/build_site.py            # build into _site/
    python3 -m http.server -d _site 8090     # preview at http://localhost:8090
"""
import html
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
OUT = ROOT / "_site"
REPO = "https://github.com/msitarzewski/AudioPaper"
BASE_URL = "https://msitarzewski.github.io/AudioPaper/"

# (output file, nav label or None). Order is the nav order.
NAV = [("index.html", "Home"), ("help.html", "Help"), ("shortcuts.html", "Shortcuts"),
       ("reference.html", "Reference"), ("privacy.html", "Privacy"), ("network.html", "Network")]

# Markdown documents rendered into pages: source → (output, description).
MARKDOWN = {
    "PRIVACY.md": ("privacy.html", "What AudioPaper sends, to whom, and what stays on your Mac."),
    "NETWORK.md": ("network.html", "Every network request AudioPaper makes: host, trigger, what's sent, how often."),
}
# Links between the rendered documents stay on the site; other repo paths go to GitHub.
LOCAL_LINKS = {"PRIVACY.md": "privacy.html", "NETWORK.md": "network.html"}


def front_matter(text):
    """Reads the leading <!-- key: value --> block of a page fragment."""
    match = re.match(r"\s*<!--(.*?)-->", text, re.S)
    meta = {}
    if match:
        for line in match.group(1).strip().splitlines():
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
        text = text[match.end():]
    return meta, text


def render_markdown(source):
    body = subprocess.run(
        ["pandoc", "--from=gfm", "--to=html5", "--wrap=none", str(ROOT / source)],
        check=True, capture_output=True, text=True,
    ).stdout

    def link(match):
        target = match.group(1)
        if re.match(r"[a-z]+:|#", target):
            return match.group(0)
        path, _, anchor = target.removeprefix("./").partition("#")
        if path in LOCAL_LINKS:
            url = LOCAL_LINKS[path]
        else:
            url = f"{REPO}/{'tree' if path.endswith('/') else 'blob'}/main/{path}"
        return f'href="{url}{"#" + anchor if anchor else ""}"'

    body = re.sub(r'href="([^"]+)"', link, body)
    title = re.search(r"<h1[^>]*>(.*?)</h1>", body, re.S).group(1)
    source_note = (f'<p class="doc-source">This page is <a href="{REPO}/blob/main/{source}">{source}</a> '
                   f'from the repository, published as written.</p>')
    body = re.sub(r"(</h1>)", r"\1" + source_note, body, count=1)
    # Wide tables scroll inside their own box on narrow screens.
    body = body.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")
    return re.sub(r"<[^>]+>", "", title), f'<article class="doc">{body}</article>'


def page(layout, name, title, description, content):
    nav = "\n".join(
        f'<a href="{href}"{" aria-current=\"page\"" if href == name else ""}>{label}</a>'
        for href, label in NAV
    )
    full_title = "AudioPaper" if name == "index.html" else f"{title} — AudioPaper"
    return (layout
            .replace("{{title}}", html.escape(full_title))
            .replace("{{description}}", html.escape(description, quote=True))
            .replace("{{url}}", BASE_URL + ("" if name == "index.html" else name))
            .replace("{{nav}}", nav)
            .replace("{{content}}", content))


def main():
    if not shutil.which("pandoc"):
        sys.exit("pandoc is required (brew install pandoc)")
    shutil.rmtree(OUT, ignore_errors=True)
    shutil.copytree(SITE / "static", OUT)
    layout = (SITE / "layout.html").read_text()

    for fragment in sorted((SITE / "pages").glob("*.html")):
        meta, content = front_matter(fragment.read_text())
        (OUT / fragment.name).write_text(page(layout, fragment.name, meta["title"], meta["description"], content))

    for source, (name, description) in MARKDOWN.items():
        title, content = render_markdown(source)
        (OUT / name).write_text(page(layout, name, title, description, content))

    (OUT / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"  <url><loc>{BASE_URL}{'' if n == 'index.html' else n}</loc></url>\n" for n, _ in NAV)
        + "</urlset>\n")
    print(f"Built {len(list(OUT.glob('*.html')))} pages into {OUT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
