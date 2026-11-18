#!/usr/bin/env python3
"""Check the actual Stapler search/info contract used by GNOME Software.

Read-only after refresh. CI configures a local copy of the working tree inside
a disposable p11 container; this tool never changes system repositories.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path

from sync_appstream import scalar

SEARCH_FORMAT = (
    "{{ .Repository }}\x1f{{ .Name }}\x1f{{ .Version }}-{{ .Release }}\x1f"
    "{{ .AppStreamAppID }}\x1f"
    "{{ if and .AppStream .AppStream.Name }}{{ .AppStream.Name | localized }}"
    "{{ else }}{{ .Name }}{{ end }}\x1f"
    "{{ if and .AppStream .AppStream.Summary }}{{ .AppStream.Summary | localized }}"
    "{{ else }}{{ .Summary.Resolved }}{{ end }}\x1f"
    "{{ if and .AppStream .AppStream.Description }}{{ .AppStream.Description | localized }}"
    "{{ else }}{{ .Description.Resolved }}{{ end }}\x1e\n"
)
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


def run_stplr(*arguments: str) -> str:
    result = subprocess.run(
        ["stplr", "-i=false", *arguments],
        check=True, text=True, capture_output=True, timeout=120,
        env={**os.environ, "STPLR_AUTO_PULL": "false", "LANGUAGE": "en", "LANG": "C.UTF-8"},
    )
    return result.stdout


def search_rows(output: str) -> list[list[str]]:
    rows = []
    for record in output.split("\x1e"):
        if not record.strip():
            continue
        fields = record.lstrip("\n").split("\x1f")
        if len(fields) != 7:
            raise ValueError("Stapler search no longer returns the plugin's seven fields")
        rows.append(fields)
    return rows


def localized(document: ET.Element, path: str) -> dict[str, str]:
    return {
        element.get(XML_LANG, "C"): "".join(element.itertext()).strip()
        for element in document.findall(path)
    }


def validate_details(package: str, document: ET.Element, appstream: dict) -> None:
    if not isinstance(appstream, dict):
        raise ValueError(f"{package}: Stapler omitted AppStream")
    expected_id = document.findtext("id")
    desktop = document.findtext("launchable[@type='desktop-id']")
    if appstream.get("id") != expected_id or appstream.get("launchable", {}).get("desktop-id") != desktop:
        raise ValueError(f"{package}: Stapler changed the component or desktop identity")
    for field in ("name", "summary"):
        if appstream.get(field) != localized(document, field):
            raise ValueError(f"{package}: Stapler lost localized {field}")
    for locale in localized(document, "description/p"):
        if not appstream.get("description", {}).get(locale):
            raise ValueError(f"{package}: Stapler lost the {locale} description")
    developer = localized(document, "developer/name") or localized(document, "developer_name")
    actual_developer = (appstream.get("developer") or {}).get("name") or appstream.get("developer_name")
    if actual_developer != developer:
        raise ValueError(f"{package}: Stapler lost the developer")
    if appstream.get("urls", {}).get("homepage") != document.findtext("url[@type='homepage']"):
        raise ValueError(f"{package}: Stapler changed the homepage")
    if appstream.get("project_license") != document.findtext("project_license"):
        raise ValueError(f"{package}: Stapler changed the project license")
    expected_images = [image.text for image in document.findall("screenshots/screenshot/image")]
    actual_images = [
        image.get("url")
        for shot in appstream.get("screenshots", [])
        for image in shot.get("images", [])
    ]
    if expected_images != actual_images:
        raise ValueError(f"{package}: Stapler lost the official screenshots")


def check(repository: Path, cache: Path) -> None:
    with (repository / ".github/support-matrix.toml").open("rb") as stream:
        packages = [package["id"] for package in tomllib.load(stream)["packages"]]
    rows = search_rows(run_stplr("search", "--query", "repository == 'nivora'", "-f", SEARCH_FORMAT))
    if sorted(row[1] for row in rows) != sorted(packages) or any(row[0] != "nivora" for row in rows):
        raise ValueError("Stapler search catalog differs from the support matrix")
    records = json.loads(run_stplr("info", *(f"nivora/{package}" for package in packages), "--json"))
    if not isinstance(records, list) or sorted(record.get("name", "") for record in records) != sorted(packages):
        raise ValueError("Stapler info catalog differs from the support matrix")
    details = {record["name"]: record for record in records}
    gui_count = 0
    for row in rows:
        _, package, version, app_id, name, summary, description = row
        recipe = (repository / package / "Staplerfile").read_text()
        expected_version = f"{scalar(recipe, 'version')}-{scalar(recipe, 'release')}"
        if version != expected_version or details[package].get("repository") != "nivora":
            raise ValueError(f"{package}: wrong repository or version in Stapler")
        if app_id != (scalar(recipe, "appstream_app_id") or ""):
            raise ValueError(f"{package}: wrong AppStream ID in search")
        if not app_id:
            if details[package].get("appstream"):
                raise ValueError(f"{package}: service/CLI package acquired a desktop component")
            continue
        document = ET.parse(repository / package / f"{app_id}.metainfo.xml").getroot()
        validate_details(package, document, details[package].get("appstream"))
        if name != document.findtext("name") or not summary or not description:
            raise ValueError(f"{package}: incomplete plugin search result")
        matched = search_rows(run_stplr("search", "--query", f"appstream_app_id == '{app_id}'", "-f", SEARCH_FORMAT))
        if len(matched) != 1 or matched[0][:4] != row[:4]:
            raise ValueError(f"{package}: component ID does not resolve uniquely")
        icons = [repository / package / f"{app_id}{extension}" for extension in (".svg", ".png")]
        icons = [icon for icon in icons if icon.is_file()]
        if not icons or not any(
            (cached := cache / package / icon.name).is_file()
            and hashlib.sha256(cached.read_bytes()).digest() == hashlib.sha256(icon.read_bytes()).digest()
            for icon in icons
        ):
            raise ValueError(f"{package}: icon missing or changed in the plugin's repository cache")
        gui_count += 1
    print(f"OK: Stapler GNOME catalog — {len(packages)} packages, {gui_count} desktop components")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=Path("/var/cache/stplr/repo/nivora"))
    args = parser.parse_args()
    try:
        check(args.repository, args.cache)
    except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError) as error:
        print(f"GNOME catalog: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
