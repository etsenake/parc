#!/usr/bin/env python3
"""Sign a release ZIP with Sparkle and write Parc's one-item appcast.xml."""
import argparse
import datetime
import email.utils
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import subprocess
from xml.sax.saxutils import escape, quoteattr

ROOT = Path(__file__).resolve().parents[1]
SIGNATURE = re.compile(r'sparkle:edSignature="([A-Za-z0-9+/]+={0,2})" length="([0-9]+)"')


def load(name):
    spec = importlib.util.spec_from_file_location("parc_appcast_" + name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sparkle = load("sparkle")
whats_new = load("whats_new")


def parse(output):
    """sign_update's enclosure attributes: the EdDSA signature and the signed length."""
    match = SIGNATURE.fullmatch(output.strip())
    if not match:
        raise ValueError("Unexpected sign_update output: " + output.strip())
    return match[1], int(match[2])


def sign(tools, archive, key):
    """The archive's signature, checked to cover every byte and verified by Sparkle itself."""
    output = subprocess.run([tools / "sign_update", *key, archive], check=True, stdout=subprocess.PIPE, text=True).stdout
    signature, length = parse(output)
    if length != archive.stat().st_size:
        raise ValueError(f"sign_update signed {length} bytes of a {archive.stat().st_size}-byte archive")
    subprocess.run([tools / "sign_update", *key, "--verify", archive, signature], check=True)
    return signature, length


def notes(path, version):
    """This version's release notes as HTML, grouped like the What's New page."""
    found = [release for release in whats_new.read_releases(path) if release["version"] == version]
    if not found:
        raise ValueError(f"{path} has no release {version}")
    return whats_new.render_groups(found[0]["changes"], "h3")


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def render(info, notes, url, signature, length, published):
    version = info["CFBundleShortVersionString"]
    return f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Parc</title>
    <item>
      <title>{escape("Parc " + version)}</title>
      <pubDate>{email.utils.format_datetime(published)}</pubDate>
      <sparkle:version>{escape(info["CFBundleVersion"])}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(info["LSMinimumSystemVersion"])}</sparkle:minimumSystemVersion>
      <description>{cdata(notes)}</description>
      <enclosure url={quoteattr(url)} length="{length}" type="application/octet-stream" sparkle:edSignature={quoteattr(signature)}/>
    </item>
  </channel>
</rss>
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="the packaged Parc.app")
    parser.add_argument("archive", type=Path, help="its notarized release ZIP")
    parser.add_argument("output", type=Path)
    parser.add_argument("--published", required=True, type=datetime.datetime.fromisoformat,
                        help="the release's fixed pubDate, ISO 8601 with a UTC offset")
    parser.add_argument("--ed-key-file", type=Path,
                        help="development only: sign with this private key file instead of the Keychain account")
    args = parser.parse_args()
    if args.published.tzinfo is None:
        parser.error("--published needs a UTC offset")
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    tools = sparkle.fetch(ROOT / "build/sparkle") / "bin"
    if args.ed_key_file:
        key = ["--ed-key-file", args.ed_key_file]
    else:
        key = ["--account", sparkle.ACCOUNT]
        trusted = subprocess.run([tools / "generate_keys", "--account", sparkle.ACCOUNT, "-p"],
                                 check=True, stdout=subprocess.PIPE, text=True).stdout.strip()
        if trusted != info.get("SUPublicEDKey"):
            parser.exit(1, "error: the Keychain signing key is not the one this app trusts\n")
    version = info["CFBundleShortVersionString"]
    signature, length = sign(tools, args.archive, key)
    url = f"{sparkle.RELEASES}/download/v{version}/{args.archive.name}"
    text = render(info, notes(ROOT / "release-notes.json", version), url, signature, length, args.published)
    temporary = args.output.with_suffix(".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, args.output)
    print(f"wrote {args.output}: Parc {version} ({info['CFBundleVersion']}), {length} signed bytes, verified")


if __name__ == "__main__":
    main()
