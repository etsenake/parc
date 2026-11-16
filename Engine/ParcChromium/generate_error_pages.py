#!/usr/bin/env python3
"""Build Parc's network error page and security warning skin from Parc's templates."""

import argparse
from pathlib import Path
import re
from urllib.parse import quote

ARTS = ("plane", "plug", "signpost", "snail", "lock-badge", "barricade", "blocked-page")
NET_ERROR_ARTS = ("plane", "plug", "signpost", "snail", "blocked-page")
ALLOWED_NET_ERROR_KEYS = {"$i18n{textdirection}", "$i18n{language}"}
DELIMITER = "PARCPAGE"

PALETTES = {
    ("serious", "light"): {"ink": "#2B2938", "accent": "#D9263B", "page": "#FFFCEC", "wash": ("#D9263B", 0.08),
                           "button": "#FFFCEC", "secondary": ("#100E22", 0.66)},
    ("serious", "dark"): {"ink": "#E4E0D2", "accent": "#FF6B7A", "page": "#15141C", "wash": ("#FF6B7A", 0.12),
                          "button": "#15141C", "secondary": ("#FFFCEC", 0.66)},
    ("neutral", "light"): {"ink": "#2B2938", "accent": "#3139FB", "page": "#FFFCEC", "wash": None,
                           "button": "#FFFCEC", "secondary": ("#100E22", 0.66)},
    ("neutral", "dark"): {"ink": "#E4E0D2", "accent": "#7A80FF", "page": "#15141C", "wash": None,
                          "button": "#15141C", "secondary": ("#FFFCEC", 0.66)},
    ("danger", "light"): {"ink": "#FFFCEC", "accent": "#FFCF5C", "page": "#B71E2C", "wash": None,
                          "button": "#A51A27", "secondary": ("#FFFCEC", 1.0)},
    ("danger", "dark"): {"ink": "#F4EFDF", "accent": "#FFCF5C", "page": "#7E1520", "wash": None,
                         "button": "#7E1520", "secondary": ("#FFFCEC", 1.0)},
}


def blend(base, over, alpha):
    channels = []
    for index in (1, 3, 5):
        low = int(base[index:index + 2], 16)
        high = int(over[index:index + 2], 16)
        channels.append(round(low * (1 - alpha) + high * alpha))
    return "#" + "".join(f"{value:02X}" for value in channels)


def data_url(svg):
    return 'url("data:image/svg+xml,' + quote(svg, safe=" =:/;,.-()") + '")'


def art_body(svg):
    match = re.fullmatch(r"\s*<svg[^>]*>(.*)</svg>\s*", svg, re.S)
    if not match:
        raise ValueError("art must be a single <svg> element")
    return match.group(1).strip()


def art_url(arts, name, mode, scheme):
    palette = PALETTES[(mode, scheme)]
    fill = palette["page"]
    if palette["wash"]:
        fill = blend(palette["page"], *palette["wash"])
    ink, accent = palette["ink"], palette["accent"]
    style = (f".k{{stroke:{ink};fill:none}}.a{{stroke:{accent};fill:none}}"
             f".kf{{stroke:{ink};fill:{fill}}}.af{{stroke:{accent};fill:{fill}}}"
             f".p{{stroke:{fill};fill:{fill}}}.kd{{fill:{ink}}}.ad{{fill:{accent}}}")
    body = art_body(arts[name]).replace('visibility="hidden"', 'display="none"')
    svg = ("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 120 120' fill='none' "
           f"stroke-linecap='round' stroke-linejoin='round'><style>{style}</style>{body}</svg>")
    return data_url(svg.replace('"', "'"))


def chip_url(mode, scheme):
    color = PALETTES[(mode, scheme)]["button"]
    svg = ("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 26 20'>"
           f"<rect width='26' height='20' rx='6' fill='{color}' fill-opacity='0.16'/>"
           f"<path d='M17.5 6v3.5H9 M11.5 6.5 8.5 9.5 11.5 12.5' fill='none' stroke='{color}' "
           "stroke-opacity='0.85' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/></svg>")
    return data_url(svg)


def chevron_url(mode, scheme):
    color, opacity = PALETTES[(mode, scheme)]["secondary"]
    svg = ("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 6'>"
           f"<path d='M1.5 1.25 5 4.75 8.5 1.25' fill='none' stroke='{color}' stroke-opacity='{opacity}' "
           "stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/></svg>")
    return data_url(svg)


def filled_style(source, name, arts):
    css = (source / name).read_text(encoding="utf-8")

    def substitute(match):
        kind, *rest = match.group(1).split()
        if kind == "art":
            return art_url(arts, *rest)
        if kind == "chip":
            return chip_url(*rest)
        if kind == "chevron":
            return chevron_url(*rest)
        raise ValueError(f"unknown placeholder {match.group(0)}")

    return "<style>" + re.sub(r"\{\{([^}]+)\}\}", substitute, css) + "</style>"


def net_error_page(source, arts):
    font = "".join((source / "display-font.woff.b64").read_text(encoding="ascii").split())
    style = (source / "neterror.css").read_text(encoding="utf-8").replace("{{font}}", font)
    script = (source / "neterror.js").read_text(encoding="utf-8")
    templates = "\n".join(f'<template id="art-{name.replace("-page", "")}">{arts[name].strip()}</template>'
                          for name in NET_ERROR_ARTS)
    page = (source / "neterror.html").read_text(encoding="utf-8")
    for key, value in (("{{style}}", style), ("{{art}}", templates), ("{{script}}", script)):
        if page.count(key) != 1:
            raise ValueError(f"neterror.html needs exactly one {key}")
        page = page.replace(key, value)
    return page


def check(name, text, allowed=frozenset()):
    for key in re.findall(r"\$i18n\w*\{[^}]*\}|\$i18n\w*", text):
        if key not in allowed:
            raise ValueError(f"{name} must not contain {key}: Chromium fills every $i18n placeholder")
    if "{{" in text:
        raise ValueError(f"{name} has an unfilled placeholder")
    if f"){DELIMITER}\"" in text:
        raise ValueError(f"{name} contains the raw string delimiter")
    for script in re.findall(r"<script>(.*?)</script>", text, re.S):
        if "</script" in script.lower() or "<!--" in script:
            raise ValueError(f"{name} has a script that ends early")


def build(source):
    arts = {name: (source / "art" / f"{name}.svg").read_text(encoding="utf-8") for name in ARTS}
    pages = {
        "net_error": net_error_page(source, arts),
        "interstitial_style": filled_style(source, "interstitial.css", arts),
        "webapp_style": filled_style(source, "webapp.css", arts),
        "interstitial_script": "<script>" + (source / "interstitial.js").read_text(encoding="utf-8") + "</script>",
    }
    check("net_error", pages["net_error"], ALLOWED_NET_ERROR_KEYS)
    check("interstitial_style", pages["interstitial_style"])
    check("interstitial_script", pages["interstitial_script"])
    check("webapp_style", pages["webapp_style"])
    return pages


def cpp(pages):
    lines = ['#include "parc/error_pages.h"', "", "namespace parc {", "namespace {"]
    names = {"net_error": "kNetErrorPage", "interstitial_style": "kInterstitialStyle",
             "interstitial_script": "kInterstitialScript", "webapp_style": "kWebAppErrorStyle"}
    for key, symbol in names.items():
        lines.append(f'constexpr char {symbol}[] = R"{DELIMITER}({pages[key]}){DELIMITER}";')
    lines += ["}  // namespace", "",
              "std::string_view NetErrorPageTemplate() {", "  return kNetErrorPage;", "}", "",
              "std::string_view InterstitialStyle() {", "  return kInterstitialStyle;", "}", "",
              "std::string_view InterstitialScript() {", "  return kInterstitialScript;", "}", "",
              "std::string_view WebAppErrorStyle() {", "  return kWebAppErrorStyle;", "}", "",
              "}  // namespace parc", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--html-dir", type=Path)
    arguments = parser.parse_args()
    pages = build(arguments.source)
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(cpp(pages), encoding="utf-8")
    if arguments.html_dir:
        arguments.html_dir.mkdir(parents=True, exist_ok=True)
        for key, text in pages.items():
            (arguments.html_dir / f"{key}.html").write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
