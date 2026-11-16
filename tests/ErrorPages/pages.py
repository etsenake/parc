import html
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CHROMIUM = HERE / "chromium"
GENERATOR = ROOT / "Engine/ParcChromium/generate_error_pages.py"
SOURCE = ROOT / "Engine/ParcChromium/error_pages"
PLACEHOLDER = re.compile(r"\$i18n(Raw|Polymer)?\{([^}]*)\}")


def generate(out: Path) -> dict:
    subprocess.run([sys.executable, str(GENERATOR), "--source", str(SOURCE), "--html-dir", str(out),
                    "--output", str(out / "error_pages.cc")], check=True)
    return {name: (out / f"{name}.html").read_text(encoding="utf-8")
            for name in ("net_error", "interstitial_style", "interstitial_script", "webapp_style")}


def replace_expressions(source: str, values: dict) -> str:
    def substitute(match):
        context, key = match.group(1), match.group(2)
        if key not in values:
            raise KeyError(f"Chromium would crash: $i18n replacement key {key!r} not found")
        value = values[key]
        text = value if isinstance(value, str) else json.dumps(value)
        return text if context == "Raw" else html.escape(text, quote=True)
    return PLACEHOLDER.sub(substitute, source)


def localized(template: str, data: dict) -> str:
    return replace_expressions(template, data) + "<script>var loadTimeDataRaw = " + json.dumps(data) + ";</script>"


def net_error_page(pieces: dict, data: dict) -> str:
    return localized(pieces["net_error"], data)


def chromium_script() -> str:
    order = ("interstitial_common.js", "interstitial_mobile_nav.js", "ssl.js", "extended_reporting.js",
             "enhanced_protection_message.js", "interstitial_large.js")
    shim = (HERE / "load_time_data.js").read_text(encoding="utf-8")
    parts = [shim]
    for name in order:
        text = (CHROMIUM / name).read_text(encoding="utf-8")
        text = re.sub(r"^import [^;]*;\s*$", "", text, flags=re.M | re.S)
        text = re.sub(r"^export (function|const|let) ", r"\1 ", text, flags=re.M)
        parts.append(text)
    return "\n".join(parts)


def chromium_interstitial_template() -> str:
    template = (CHROMIUM / "interstitial_large.html").read_text(encoding="utf-8")

    def stylesheet(match):
        return "<style>" + (CHROMIUM / Path(match.group(1)).name).read_text(encoding="utf-8") + "</style>"

    template = re.sub(r'<link rel="stylesheet" href="([^"]+)">', stylesheet, template)
    template = re.sub(r'<if expr="not optimize_webui">.*?</if>', "", template, flags=re.S)
    template = re.sub(r'<if expr="optimize_webui">.*?</if>', "<script>" + chromium_script() + "</script>",
                      template, count=1, flags=re.S)
    template = re.sub(r'<if expr="is_ios">.*?</if>', "", template, flags=re.S)
    return template


def skin(template: str, pieces: dict, style="interstitial_style", script="interstitial_script") -> str:
    head = template.find("</head>")
    if head < 0:
        return template
    template = template[:head] + pieces[style] + template[head:]
    body = template.rfind("</body>")
    if body < 0 or not script:
        return template
    return template[:body] + pieces[script] + template[body:]


def flattened(name: str) -> str:
    template = (CHROMIUM / name).read_text(encoding="utf-8")

    def stylesheet(match):
        return "<style>" + (CHROMIUM / Path(match.group(1)).name).read_text(encoding="utf-8") + "</style>"

    def script(match):
        return "<script>" + (CHROMIUM / Path(match.group(1)).name).read_text(encoding="utf-8") + "</script>"

    template = re.sub(r'<link rel="stylesheet" href="([^"]+)">', stylesheet, template)
    return re.sub(r'<script src="([^"]+)"></script>', script, template)


def alternative_page(pieces: dict, kind: str, data: dict) -> str:
    if kind.startswith("webapp"):
        template = skin(flattened("web_app_error_page.html"), pieces, "webapp_style", None)
    else:
        template = skin(flattened("enterprise_proxy_error_page.html"), pieces)
    return localized(template, data)


def text_defaults() -> str:
    css = (CHROMIUM / "text_defaults_md.css").read_text(encoding="utf-8")
    css = re.sub(r"<if expr=[^>]*>.*?</if>", "", css, flags=re.S)
    values = {"textdirection": "ltr", "fontfamily": "system-ui,sans-serif",
              "fontfamilyMd": "system-ui,sans-serif", "fontsize": "75%"}
    return "<style>" + replace_expressions(css, values) + "</style>"


def interstitial_page(pieces: dict, data: dict, parc: bool = True) -> str:
    template = chromium_interstitial_template()
    if parc:
        template = skin(template, pieces)
    return localized(template + text_defaults(), data)
