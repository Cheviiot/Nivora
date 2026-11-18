#!/usr/bin/env python3
"""Validate catalog metadata and its desktop integration in a built RPM.

The native validators run offline. RPM files are inspected without installing
the package; only its declared metainfo and desktop entry are extracted.
"""

from __future__ import annotations

import argparse
import configparser
import os
import posixpath
import re
import selectors
import stat
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
EXTRACTION_TIMEOUT = 180
# Preserve existing desktop identities without exempting new IDs or other
# validator warnings. The package name must also match the existing entry.
LEGACY_IDS = {
    "anidesk": "anidesk",
    "balena-etcher": "balena-etcher",
    "happ": "Happ",
    "parsec": "parsecd",
    "yandex-music": "yandexmusic",
}


class ValidationError(Exception):
    pass


def scalar(recipe: str, field: str) -> str | None:
    match = re.search(
        rf"^{re.escape(field)}=(?:'([^']*)'|\"([^\"]*)\"|([^#\n]+))",
        recipe,
        re.MULTILINE,
    )
    if match is None:
        return None
    return next(value.strip() for value in match.groups() if value is not None)


def run_checked(argv: list[str]) -> str:
    try:
        result = subprocess.run(
            argv, capture_output=True, text=True, errors="replace", timeout=60,
        )
    except FileNotFoundError as error:
        raise ValidationError(f"required command is not installed: {argv[0]}") from error
    except subprocess.TimeoutExpired as error:
        raise ValidationError(f"command timed out: {argv[0]}") from error
    if result.returncode != 0:
        detail = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
        raise ValidationError(f"{argv[0]} failed ({result.returncode})" + (f":\n{detail}" if detail else ""))
    return result.stdout


@dataclass(frozen=True)
class Metadata:
    component_id: str
    launchable: str
    name: str
    homepage: str | None
    developer: str | None
    developer_id: str | None
    stock_icons: tuple[str, ...] = ()
    project_license: str | None = None


def default_text(root: ET.Element, tag: str) -> str | None:
    values = [
        " ".join((node.text or "").split())
        for node in root.findall(tag)
        if node.get(XML_LANG) is None
    ]
    if len(values) > 1:
        raise ValidationError(f"duplicate unlocalized {tag}")
    return values[0] if values else None


def read_metadata(path: Path) -> Metadata:
    if not path.is_file() or path.is_symlink():
        raise ValidationError(f"metainfo must be a regular file: {path}")
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        raise ValidationError(f"invalid metainfo {path}: {error}") from error
    if root.tag != "component" or root.get("type") != "desktop-application":
        raise ValidationError(f"{path}: expected a desktop-application component")
    component_id = default_text(root, "id") or ""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", component_id):
        raise ValidationError(f"{path}: invalid component ID {component_id!r}")
    launchables = root.findall("launchable[@type='desktop-id']")
    if len(launchables) != 1:
        raise ValidationError(f"{path}: expected exactly one desktop-id launchable")
    launchable = (launchables[0].text or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.desktop", launchable):
        raise ValidationError(f"{path}: invalid desktop launchable {launchable!r}")
    name = default_text(root, "name")
    if not name:
        raise ValidationError(f"{path}: missing unlocalized application name")
    homepages = root.findall("url[@type='homepage']")
    if len(homepages) > 1:
        raise ValidationError(f"{path}: duplicate homepage")
    homepage = (homepages[0].text or "").strip() if homepages else None
    developers = root.findall("developer")
    if len(developers) > 1:
        raise ValidationError(f"{path}: duplicate developer")
    developer = default_text(developers[0], "name") if developers else None
    developer_id = developers[0].get("id") if developers else None
    legacy_developer = default_text(root, "developer_name")
    if developer and legacy_developer and developer != legacy_developer:
        raise ValidationError(f"{path}: conflicting modern and legacy developer names")
    stock_icons = tuple((node.text or "").strip() for node in root.findall("icon[@type='stock']"))
    if any(not icon or "/" in icon for icon in stock_icons):
        raise ValidationError(f"{path}: stock icon must be a nonempty icon name")
    return Metadata(
        component_id, launchable, name, homepage,
        developer or legacy_developer, developer_id, stock_icons,
        default_text(root, "project_license"),
    )


def validate_native(package: str, metadata: Metadata, path: Path) -> None:
    argv = ["appstreamcli", "validate", "--no-net"]
    if LEGACY_IDS.get(package) == metadata.component_id:
        argv += ["--override", "cid-desktopapp-is-not-rdns=info"]
    # AppStream 1.0.5's YAML path ignores overrides and can return success for
    # missing files. Use the normal text path and its exit status, not YAML.
    run_checked([*argv, str(path)])


def validate_sidecar(package: str, directory: Path, recipe: str) -> Metadata | None:
    app_id = scalar(recipe, "appstream_app_id")
    if not app_id:
        return None
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", app_id):
        raise ValidationError(f"{package}: invalid recipe AppStream ID")
    path = directory / f"{app_id}.metainfo.xml"
    metadata = read_metadata(path)
    if metadata.component_id != app_id:
        raise ValidationError(f"{package}: sidecar ID differs from recipe {app_id}")
    for field, expected, actual in (
        ("name", scalar(recipe, "appstream_name"), metadata.name),
        ("homepage", scalar(recipe, "homepage"), metadata.homepage),
        ("developer", scalar(recipe, "appstream_developer"), metadata.developer),
        ("desktop", scalar(recipe, "appstream_desktop_id"), metadata.launchable),
    ):
        if expected is not None and expected != actual:
            raise ValidationError(f"{package}: sidecar {field} {actual!r} differs from recipe {expected!r}")
    validate_native(package, metadata, path)
    return metadata


@dataclass(frozen=True)
class PayloadEntry:
    mode: int
    link: str


def read_manifest(rpm: Path) -> dict[str, PayloadEntry]:
    output = run_checked([
        "rpm", "-qp", "--queryformat",
        "[%{FILEMODES:octal}\t%{FILELINKTOS}\t%{FILENAMES}\n]", str(rpm),
    ])
    entries: dict[str, PayloadEntry] = {}
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) != 3:
            raise ValidationError("malformed RPM file metadata")
        mode, link, path = fields
        if not re.fullmatch(r"[0-7]+", mode):
            raise ValidationError(f"invalid RPM mode for {path!r}")
        if not path.startswith("/") or ".." in PurePosixPath(path).parts or str(PurePosixPath(path)) != path:
            raise ValidationError(f"noncanonical RPM payload path {path!r}")
        if path in entries:
            raise ValidationError(f"duplicate RPM payload path {path}")
        entries[path] = PayloadEntry(int(mode, 8), link)
    if not entries:
        raise ValidationError("RPM has no file metadata")
    return entries


def require_regular(entries: dict[str, PayloadEntry], path: str) -> None:
    entry = entries.get(path)
    if entry is None or not stat.S_ISREG(entry.mode):
        raise ValidationError(f"RPM lacks required regular file {path}")


def extraction_time_left(deadline: float) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired("RPM metadata extraction", EXTRACTION_TIMEOUT)
    return remaining


def drain_pipe(stream, deadline: float) -> None:
    """Consume bytes after cpio's trailer without buffering the RPM payload."""
    descriptor = stream.fileno()
    os.set_blocking(descriptor, False)
    with selectors.DefaultSelector() as selector:
        selector.register(descriptor, selectors.EVENT_READ)
        while True:
            if not selector.select(extraction_time_left(deadline)):
                raise subprocess.TimeoutExpired("rpm2cpio drain", EXTRACTION_TIMEOUT)
            try:
                chunk = os.read(descriptor, 64 * 1024)
            except BlockingIOError:
                continue
            if not chunk:
                return


def extract_metadata(rpm: Path, paths: tuple[str, str], destination: Path) -> None:
    patterns = [pattern for path in paths for pattern in (path, path[1:], f".{path}")]
    with tempfile.TemporaryFile() as producer_errors, tempfile.TemporaryFile() as consumer_errors:
        producer = None
        consumer = None
        deadline = time.monotonic() + EXTRACTION_TIMEOUT
        try:
            producer = subprocess.Popen(
                ["rpm2cpio", str(rpm)], stdout=subprocess.PIPE, stderr=producer_errors,
            )
            consumer = subprocess.Popen(
                ["cpio", "-i", "--quiet", "--no-absolute-filenames", "--no-preserve-owner", "--make-directories", *patterns],
                stdin=producer.stdout, stdout=subprocess.DEVNULL, stderr=consumer_errors,
                cwd=destination,
            )
            assert producer.stdout is not None
            # cpio can exit at TRAILER!!! before rpm2cpio finishes writing
            # archive padding. Keep our read end open, then consume to EOF;
            # closing it early turns a valid RPM into a producer EPIPE.
            consumer_code = consumer.wait(timeout=extraction_time_left(deadline))
            drain_pipe(producer.stdout, deadline)
            producer_code = producer.wait(timeout=extraction_time_left(deadline))
        except FileNotFoundError as error:
            raise ValidationError(f"required extraction command is not installed: {error.filename}") from error
        except subprocess.TimeoutExpired as error:
            raise ValidationError("RPM metadata extraction timed out") from error
        finally:
            for process in (consumer, producer):
                if process is not None:
                    if process.stdout is not None:
                        process.stdout.close()
                    if process.poll() is None:
                        process.kill()
                    process.wait()
        if producer_code != 0 or consumer_code != 0:
            producer_errors.seek(0)
            consumer_errors.seek(0)
            details = (producer_errors.read() + consumer_errors.read()).decode("utf-8", errors="replace").strip()
            raise ValidationError(f"RPM metadata extraction failed (rpm2cpio={producer_code}, cpio={consumer_code}): {details}")
    for path in paths:
        extracted = destination / path[1:]
        if extracted.is_symlink() or not extracted.is_file() or not extracted.resolve().is_relative_to(destination.resolve()):
            raise ValidationError(f"RPM archive lacks required regular file {path}")


def resolves_to_file(entries: dict[str, PayloadEntry], path: str) -> bool:
    seen: set[str] = set()
    while path not in seen:
        seen.add(path)
        entry = entries.get(path)
        if entry is None:
            return False
        if stat.S_ISREG(entry.mode):
            return True
        if not stat.S_ISLNK(entry.mode) or not entry.link:
            return False
        path = posixpath.normpath(posixpath.join(posixpath.dirname(path), entry.link))
    return False


def require_icon(icon: str, entries: dict[str, PayloadEntry], label: str) -> None:
    if not icon or any(character in icon for character in "\r\n\t"):
        raise ValidationError(f"{label} is empty or invalid")
    if icon.startswith("/"):
        candidates = [posixpath.normpath(icon)]
    elif "/" in icon:
        raise ValidationError(f"{label} is neither an absolute path nor an icon name: {icon}")
    else:
        names = [icon] if Path(icon).suffix in {".png", ".svg", ".xpm"} else [f"{icon}{suffix}" for suffix in (".png", ".svg", ".xpm")]
        candidates = [
            candidate for candidate in entries
            if PurePosixPath(candidate).name in names
            and (
                PurePosixPath(candidate).parent == PurePosixPath("/usr/share/pixmaps")
                or (
                    candidate.startswith("/usr/share/icons/hicolor/")
                    and PurePosixPath(candidate).parent.name == "apps"
                )
            )
        ]
    if not any(resolves_to_file(entries, candidate) for candidate in candidates):
        raise ValidationError(f"{label} {icon!r} has no file in the RPM payload")


def validate_desktop(path: Path, entries: dict[str, PayloadEntry]) -> None:
    run_checked(["desktop-file-validate", str(path)])
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    try:
        parser.read_string(path.read_text(encoding="utf-8"))
        icon = parser.get("Desktop Entry", "Icon")
    except (configparser.Error, OSError, UnicodeError) as error:
        raise ValidationError(f"desktop entry has no valid Icon: {error}") from error
    escapes = {"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}
    icon = re.sub(r"\\([sntr\\])", lambda match: escapes[match.group(1)], icon)
    require_icon(icon, entries, "desktop Icon")


def validate_rpm(package: str, expected: Metadata, rpm: Path) -> None:
    if not rpm.is_file():
        raise ValidationError(f"RPM does not exist: {rpm}")
    rpm = rpm.resolve()
    entries = read_manifest(rpm)
    metainfo = f"/usr/share/metainfo/{expected.component_id}.metainfo.xml"
    desktop = f"/usr/share/applications/{expected.launchable}"
    for path in (metainfo, desktop):
        require_regular(entries, path)
    with tempfile.TemporaryDirectory(prefix="nivora-appstream-") as temporary:
        directory = Path(temporary)
        extract_metadata(rpm, (metainfo, desktop), directory)
        metadata_path = directory / metainfo[1:]
        actual = read_metadata(metadata_path)
        for field in ("component_id", "launchable", "name", "homepage", "developer", "developer_id", "project_license"):
            value = getattr(expected, field)
            if value is not None and value != getattr(actual, field):
                raise ValidationError(f"{package}: RPM {field} {getattr(actual, field)!r} differs from catalog {value!r}")
        if expected.stock_icons and actual.stock_icons != expected.stock_icons:
            raise ValidationError(f"{package}: RPM stock icons differ from catalog")
        for icon in actual.stock_icons:
            require_icon(icon, entries, "metainfo stock icon")
        validate_native(package, actual, metadata_path)
        validate_desktop(directory / desktop[1:], entries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="validate all GUI sidecars")
    parser.add_argument("--rpm", type=Path, help="also validate one package's built RPM")
    parser.add_argument("packages", nargs="*")
    args = parser.parse_args()
    if args.all and (args.packages or args.rpm):
        parser.error("--all cannot be combined with packages or --rpm")
    if not args.all and not args.packages:
        parser.error("specify --all or package names")
    if args.rpm and len(args.packages) != 1:
        parser.error("--rpm requires exactly one package")
    packages = sorted(path.parent.name for path in ROOT.glob("*/Staplerfile")) if args.all else args.packages
    checked = 0
    try:
        for package in packages:
            if not re.fullmatch(r"[a-z0-9][a-z0-9+-]*", package):
                raise ValidationError(f"invalid package name: {package}")
            directory = ROOT / package
            recipe = (directory / "Staplerfile").read_text(encoding="utf-8")
            metadata = validate_sidecar(package, directory, recipe)
            if metadata is None:
                if args.rpm:
                    raise ValidationError(f"{package}: recipe has no desktop AppStream component")
                continue
            if args.rpm:
                validate_rpm(package, metadata, args.rpm)
            checked += 1
            print(f"OK: {package} AppStream" + (" and RPM desktop/icon" if args.rpm else ""))
    except (ValidationError, OSError, UnicodeError) as error:
        print(f"AppStream validation failed: {error}", file=sys.stderr)
        return 1
    print(f"OK: native AppStream validation passed for {checked} GUI package(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
