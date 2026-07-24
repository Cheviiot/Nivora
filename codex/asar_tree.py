#!/usr/bin/env python3
"""Extract and rebuild an Electron ASAR while preserving its metadata tree."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import tempfile
from pathlib import Path
from typing import Any, Iterator


class AsarError(RuntimeError):
    pass


def align4(value: int) -> int:
    return (value + 3) & ~3


def read_archive(path: Path) -> tuple[dict[str, Any], bytes, int]:
    payload = path.read_bytes()
    if len(payload) < 16:
        raise AsarError(f"{path}: truncated ASAR header")

    size_pickle_payload, header_pickle_size, header_payload_size, json_size = (
        struct.unpack_from("<IIII", payload)
    )
    expected_header_payload_size = 4 + align4(json_size)
    if (
        size_pickle_payload != 4
        or header_pickle_size != 4 + header_payload_size
        or header_payload_size != expected_header_payload_size
    ):
        raise AsarError(f"{path}: unsupported ASAR header layout")

    data_offset = 8 + header_pickle_size
    if data_offset > len(payload) or 16 + json_size > data_offset:
        raise AsarError(f"{path}: invalid ASAR header size")

    try:
        header = json.loads(payload[16 : 16 + json_size].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AsarError(f"{path}: invalid ASAR JSON header") from error
    if not isinstance(header, dict) or not isinstance(header.get("files"), dict):
        raise AsarError(f"{path}: ASAR header has no file tree")
    return header, payload, data_offset


def safe_component(name: str) -> None:
    if (
        not name
        or name in {".", ".."}
        or "/" in name
        or "\\" in name
        or "\0" in name
    ):
        raise AsarError(f"unsafe ASAR entry name: {name!r}")


def entries(
    files: dict[str, Any], prefix: tuple[str, ...] = ()
) -> Iterator[tuple[tuple[str, ...], dict[str, Any]]]:
    for name, metadata in files.items():
        safe_component(name)
        if not isinstance(metadata, dict):
            raise AsarError(f"invalid metadata for {'/'.join((*prefix, name))}")
        relative = (*prefix, name)
        children = metadata.get("files")
        if children is not None:
            if not isinstance(children, dict):
                raise AsarError(f"invalid directory entry: {'/'.join(relative)}")
            yield from entries(children, relative)
        else:
            yield relative, metadata


def output_path(root: Path, relative: tuple[str, ...]) -> Path:
    candidate = root.joinpath(*relative)
    try:
        candidate.resolve().relative_to(root.resolve())
    except ValueError as error:
        raise AsarError(f"entry escapes extraction root: {'/'.join(relative)}") from error
    return candidate


def extract(archive: Path, destination: Path) -> None:
    header, payload, data_offset = read_archive(archive)
    destination.mkdir(parents=True, exist_ok=True)

    for relative, metadata in entries(header["files"]):
        if metadata.get("unpacked") is True or "link" in metadata:
            continue
        try:
            size = int(metadata["size"])
            offset = int(metadata["offset"])
        except (KeyError, TypeError, ValueError) as error:
            raise AsarError(f"invalid file entry: {'/'.join(relative)}") from error
        start = data_offset + offset
        end = start + size
        if offset < 0 or size < 0 or end > len(payload):
            raise AsarError(f"file lies outside archive: {'/'.join(relative)}")

        target = output_path(destination, relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload[start:end])
        if metadata.get("executable") is True:
            target.chmod(target.stat().st_mode | 0o111)


def integrity(content: bytes, block_size: int) -> dict[str, Any]:
    blocks = [
        hashlib.sha256(content[offset : offset + block_size]).hexdigest()
        for offset in range(0, len(content), block_size)
    ]
    if not blocks:
        blocks = [hashlib.sha256(b"").hexdigest()]
    return {
        "algorithm": "SHA256",
        "hash": hashlib.sha256(content).hexdigest(),
        "blockSize": block_size,
        "blocks": blocks,
    }


def rebuild(archive: Path, source: Path, output: Path) -> None:
    header, _, _ = read_archive(archive)
    content_chunks: list[bytes] = []
    offset = 0

    for relative, metadata in entries(header["files"]):
        if metadata.get("unpacked") is True or "link" in metadata:
            continue
        target = output_path(source, relative)
        if not target.is_file():
            raise AsarError(f"missing extracted file: {'/'.join(relative)}")
        content = target.read_bytes()
        metadata["size"] = len(content)
        metadata["offset"] = str(offset)
        if "integrity" in metadata:
            block_size = int(metadata["integrity"].get("blockSize", 4 * 1024 * 1024))
            metadata["integrity"] = integrity(content, block_size)
        content_chunks.append(content)
        offset += len(content)

    json_payload = json.dumps(
        header, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    padded_json_size = align4(len(json_payload))
    header_payload_size = 4 + padded_json_size
    prefix = struct.pack(
        "<IIII",
        4,
        4 + header_payload_size,
        header_payload_size,
        len(json_payload),
    )
    result = (
        prefix
        + json_payload
        + b"\0" * (padded_json_size - len(json_payload))
        + b"".join(content_chunks)
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    if output.resolve() == archive.resolve():
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{output.name}.", dir=output.parent
        )
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(result)
            temporary.chmod(archive.stat().st_mode)
            temporary.replace(output)
        finally:
            temporary.unlink(missing_ok=True)
    else:
        output.write_bytes(result)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    extract_parser = subparsers.add_parser("extract")
    extract_parser.add_argument("archive", type=Path)
    extract_parser.add_argument("destination", type=Path)

    rebuild_parser = subparsers.add_parser("rebuild")
    rebuild_parser.add_argument("archive", type=Path)
    rebuild_parser.add_argument("source", type=Path)
    rebuild_parser.add_argument("output", type=Path, nargs="?")

    arguments = parser.parse_args()
    if arguments.command == "extract":
        extract(arguments.archive, arguments.destination)
    else:
        rebuild(
            arguments.archive,
            arguments.source,
            arguments.output or arguments.archive,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
