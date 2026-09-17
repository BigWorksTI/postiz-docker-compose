#!/usr/bin/env python3
"""Baixa Terms of Service e Privacy Policy do postiz.com e gera HTML estatico."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from bs4 import BeautifulSoup, NavigableString, Tag

ROOT = Path(__file__).resolve().parent.parent
LEGAL_DIR = ROOT / "legal"
UA = "Mozilla/5.0 (compatible; BigWorks-Postiz-Legal/1.0)"
PAGES = (
    ("terms-of-service", "https://postiz.com/terms-of-service", "Terms of Service"),
    ("privacy-policy", "https://postiz.com/privacy-policy", "Privacy Policy"),
)
STOP_MARKERS = ("Ready to get started", "Open-source social media scheduling tool")

CSS = """
:root {
  color-scheme: dark;
  --bg: #0e0e0e;
  --text: #f5f5f5;
  --muted: #a3a3a3;
  --accent: #8b5cf6;
  --border: #262626;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: "Plus Jakarta Sans", system-ui, -apple-system, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.65;
}
.wrap {
  max-width: 820px;
  margin: 0 auto;
  padding: 48px 20px 80px;
}
header {
  margin-bottom: 40px;
  padding-bottom: 24px;
  border-bottom: 1px solid var(--border);
}
header a {
  color: var(--text);
  text-decoration: none;
  font-weight: 700;
  letter-spacing: -0.02em;
}
h1 {
  font-size: clamp(2rem, 5vw, 3rem);
  line-height: 1.1;
  margin: 0 0 12px;
  font-weight: 800;
  text-align: center;
}
h2 {
  font-size: 1.35rem;
  margin: 2rem 0 0.75rem;
  font-weight: 700;
}
h3 {
  font-size: 1.05rem;
  margin: 1.5rem 0 0.5rem;
  font-weight: 600;
}
p, li { color: #e5e5e5; }
em, .muted { color: var(--muted); }
a { color: var(--accent); }
ul, ol { padding-left: 1.25rem; }
li { margin: 0.35rem 0; }
footer {
  margin-top: 48px;
  padding-top: 24px;
  border-top: 1px solid var(--border);
  color: var(--muted);
  font-size: 0.9rem;
}
"""


def fetch(url: str) -> str:
    result = subprocess.run(
        ["curl", "-sL", "-A", UA, url],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    return result.stdout


def strip_noise(node: Tag) -> None:
    for tag in node.find_all(["script", "style", "nav", "footer", "svg", "button"]):
        tag.decompose()


def should_stop(node: Tag) -> bool:
    text = node.get_text(" ", strip=True)
    return any(marker in text for marker in STOP_MARKERS)


def extract_body(html: str, title: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    main = soup.find("main") or soup.body
    if not main:
        raise RuntimeError(f"conteudo principal nao encontrado em {title}")

    h1 = main.find("h1")
    if not h1:
        raise RuntimeError(f"h1 nao encontrado em {title}")

    parts: list[str] = []
    strip_noise(h1)
    parts.append(h1.decode())

    for sibling in h1.find_next_siblings():
        if isinstance(sibling, NavigableString):
            continue
        if not isinstance(sibling, Tag):
            continue
        if should_stop(sibling):
            break
        strip_noise(sibling)
        parts.append(sibling.decode())

    return "\n".join(parts)


def render_page(slug: str, title: str, body_html: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title} - BigWorks Social</title>
  <style>{CSS}</style>
</head>
<body>
  <div class="wrap">
    <header><a href="/">BigWorks Social</a></header>
    {body_html}
    <footer>
      <p>Content from <a href="https://postiz.com/{slug}">postiz.com/{slug}</a>.
      Served on this instance for OAuth and compliance requirements.</p>
    </footer>
  </div>
</body>
</html>
"""


def main() -> int:
    LEGAL_DIR.mkdir(parents=True, exist_ok=True)
    for slug, url, title in PAGES:
        print(f"fetch {url}")
        html = fetch(url)
        body = extract_body(html, title)
        out = LEGAL_DIR / f"{slug}.html"
        out.write_text(render_page(slug, title, body), encoding="utf-8")
        print(f"wrote {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
