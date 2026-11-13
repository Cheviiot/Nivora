#!/usr/bin/env python3
"""Enable production OAuth callbacks without replacing native Linux handling."""

import argparse
import re
from pathlib import Path


AUTH_BEFORE = """if (__DEV_SECRETS__) {
  possibleProtocols.add('x-github-desktop-dev-auth')
} else {
  possibleProtocols.add('x-github-desktop-auth')
}"""
AUTH_AFTER = """possibleProtocols.add('x-github-desktop-auth')
if (__DEV_SECRETS__) {
  possibleProtocols.add('x-github-desktop-dev-auth')
}"""
WINDOWS_ONLY = "if (__WIN32__ && args['protocol-launcher'] === true)"
LEGACY_LINUX = "if ((__WIN32__ || __LINUX__) && args['protocol-launcher'] === true)"


def patch_oauth(source: str) -> str:
    if AUTH_BEFORE in source:
        source = source.replace(AUTH_BEFORE, AUTH_AFTER, 1)
    elif not re.search(
        r"^possibleProtocols\.add\(['\"]x-github-desktop-auth['\"]\);?$",
        source, re.MULTILINE,
    ):
        raise ValueError('unsupported OAuth protocol registration')

    # Recent upstream versions already recognize plain .desktop URL arguments.
    # Keep that implementation; the old Windows-only replacement is obsolete.
    native_linux = re.search(
        r"const\s+isLinuxProtocolLaunch\s*=\s*__LINUX__\s*&&", source
    ) and re.search(
        r"if\s*\(\s*isWindowsProtocolLaunch\s*\|\|\s*isLinuxProtocolLaunch\s*\)",
        source,
    )
    if native_linux or LEGACY_LINUX in source:
        return source
    if WINDOWS_ONLY in source:
        return source.replace(WINDOWS_ONLY, LEGACY_LINUX, 1)
    raise ValueError('unsupported command-line protocol handler')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    try:
        patched = patch_oauth(args.source.read_text(encoding='utf-8'))
    except ValueError as error:
        parser.exit(1, f'GitHub Desktop OAuth patch: {error}\n')
    args.source.write_text(patched, encoding='utf-8')


if __name__ == '__main__':
    main()
