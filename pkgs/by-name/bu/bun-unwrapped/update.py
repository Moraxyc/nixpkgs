#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p nix-prefetch-git python3
"""Update Bun's pinned sources and fixed-output hashes."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import TypedDict, cast

PACKAGE_DIR = Path(__file__).resolve().parent
NIXPKGS_ROOT = PACKAGE_DIR.parents[3]
SOURCES_FILE = PACKAGE_DIR / "sources.json"

BUN_REPOSITORY = "https://github.com/oven-sh/bun.git"
WEBKIT_REPOSITORY = "https://github.com/oven-sh/WebKit.git"
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


class DownloadPin(TypedDict):
    name: str
    url: str
    hash: str


class WebKitPin(TypedDict):
    rev: str
    version: str
    hash: str
    sparseCheckout: list[str]


class Sources(TypedDict):
    version: str
    revision: str
    sourceHash: str
    cargoHash: str
    nodeModulesHash: str
    downloads: list[DownloadPin]
    webkit: WebKitPin


class Arguments(argparse.Namespace):
    version: str | None = None
    force: bool = False


@dataclass(frozen=True, slots=True)
class Archive:
    name: str
    url: str


def print_command(arguments: list[str]) -> None:
    print("+", shlex.join(arguments), flush=True)


def output(
    arguments: list[str],
    *,
    cwd: Path = NIXPKGS_ROOT,
) -> str:
    print_command(arguments)
    return subprocess.check_output(arguments, cwd=cwd, text=True).strip()


def json_output(arguments: list[str]) -> dict[str, object]:
    return cast(dict[str, object], json.loads(output(arguments)))


def capture(
    pattern: str,
    text: str,
    source: str | Path,
    *,
    flags: int = 0,
) -> str:
    match = re.search(pattern, text, flags)
    if match is None:
        raise RuntimeError(f"Cannot parse {source}")
    return match.group(1)


def load_sources() -> Sources:
    return cast(Sources, json.loads(SOURCES_FILE.read_text(encoding="utf-8")))


def stable_releases() -> dict[str, str]:
    lines = output(
        [
            "git",
            "ls-remote",
            "--tags",
            "--refs",
            BUN_REPOSITORY,
            "refs/tags/bun-v*",
        ]
    ).splitlines()

    releases: dict[str, str] = {}
    for line in lines:
        revision, reference = line.split("\t", 1)
        match = re.fullmatch(r"refs/tags/bun-v(\d+\.\d+\.\d+)", reference)
        if match is not None:
            releases[match.group(1)] = revision
    if not releases:
        raise RuntimeError("No stable Bun releases found")
    return releases


def version_key(version: str) -> tuple[int, int, int]:
    parts = version.split(".")
    if len(parts) != 3:
        raise ValueError(f"Unsupported Bun version: {version}")
    return int(parts[0]), int(parts[1]), int(parts[2])


def prefetch_file(url: str, *, unpack: bool = False) -> tuple[str, Path]:
    arguments = ["nix", "store", "prefetch-file", "--json"]
    if unpack:
        arguments.append("--unpack")
    arguments.append(url)

    payload = json_output(arguments)
    hash_value = payload.get("hash")
    store_path = payload.get("storePath")
    if not isinstance(hash_value, str) or not isinstance(store_path, str):
        raise TypeError(f"Invalid prefetch result for {url}")
    return hash_value, Path(store_path)


def prefetch_hashes(archives: list[Archive]) -> dict[Archive, str]:
    def prefetch(archive: Archive) -> tuple[Archive, str]:
        hash_value, _ = prefetch_file(archive.url)
        return archive, hash_value

    with ThreadPoolExecutor(max_workers=4) as executor:
        return dict(executor.map(prefetch, archives))


def resolve_constant(text: str, expression: str, source: Path) -> str:
    expression = expression.strip()
    if expression.startswith('"'):
        value = cast(object, json.loads(expression))
        if isinstance(value, str):
            return value
        raise RuntimeError(f"Expected a string in {source}: {expression}")

    return capture(
        rf'(?:export\s+)?const\s+{re.escape(expression)}(?:\s*:[^=]+)?\s*=\s*"([^"]+)"',
        text,
        source,
    )


def validate_llvm_version(source: Path) -> None:
    tools_path = source / "scripts/build/tools.ts"
    version = capture(
        r'export const LLVM_VERSION = "([^"]+)";',
        tools_path.read_text(encoding="utf-8"),
        tools_path,
    )
    if not version.startswith("21.1."):
        raise RuntimeError(
            f"Bun requires LLVM {version}; update the llvmPackages assertion before updating"
        )


def source_archives(source: Path) -> list[Archive]:
    directory = source / "scripts/build/deps"
    archives_by_symbol: dict[str, Archive] = {}

    for path in sorted(directory.glob("*.ts")):
        text = path.read_text(encoding="utf-8")
        if 'kind: "github-archive"' not in text:
            continue
        if re.search(r"enabled:\s*cfg\s*=>\s*cfg\.windows\b", text) is not None:
            continue

        symbol = capture(r"export const (\w+): Dependency", text, path)
        name = capture(r'name:\s*"([^"]+)"', text, path)
        repository = capture(r'repo:\s*"([^"]+)"', text, path)
        commit = capture(r"commit:\s*([^,\n]+)", text, path)
        revision = resolve_constant(text, commit, path)
        archives_by_symbol[symbol] = Archive(
            name,
            f"https://github.com/{repository}/archive/{revision}.tar.gz",
        )

    index_path = directory / "index.ts"
    all_deps = capture(
        r"export const allDeps:[^=]+?=\s*\[(.*?)\];",
        index_path.read_text(encoding="utf-8"),
        index_path,
        flags=re.DOTALL,
    )
    order = [
        match.group(1)
        for match in re.finditer(
            r"^\s*(\w+)\s*,",
            re.sub(r"//.*", "", all_deps),
            re.MULTILINE,
        )
    ]
    archives = [
        archives_by_symbol[name] for name in order if name in archives_by_symbol
    ]

    node_headers_path = directory / "nodejs-headers.ts"
    node_headers = node_headers_path.read_text(encoding="utf-8")
    node_version = resolve_constant(node_headers, "NODEJS_VERSION", node_headers_path)
    archives.append(
        Archive(
            "nodejs-headers",
            f"https://nodejs.org/dist/v{node_version}/node-v{node_version}-headers.tar.gz",
        )
    )
    return archives


def pin_downloads(
    archives: list[Archive], hashes: dict[Archive, str]
) -> list[DownloadPin]:
    return [
        {"name": archive.name, "url": archive.url, "hash": hashes[archive]}
        for archive in archives
    ]


def unstable_version(commit_date: object) -> str:
    if not isinstance(commit_date, str):
        raise TypeError("nix-prefetch-git returned no WebKit commit date")

    match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})T.*", commit_date)
    if match is None:
        raise ValueError(f"Invalid WebKit commit date: {commit_date}")
    try:
        commit_day = date.fromisoformat(match.group(1))
    except ValueError as error:
        raise ValueError(f"Invalid WebKit commit date: {commit_date}") from error
    return f"0-unstable-{commit_day.isoformat()}"


def pin_webkit(source: Path, current: WebKitPin, *, force: bool) -> WebKitPin:
    webkit_path = source / "scripts/build/deps/webkit.ts"
    revision = capture(
        r'export const WEBKIT_VERSION = "([^"]+)";',
        webkit_path.read_text(encoding="utf-8"),
        webkit_path,
    )
    if revision == current["rev"] and not force:
        return current

    payload = json_output(
        [
            "nix-prefetch-git",
            "--quiet",
            "--url",
            WEBKIT_REPOSITORY,
            "--rev",
            revision,
            "--name",
            "bun-webkit-source",
            "--sparse-checkout",
            "\n".join(current["sparseCheckout"]),
        ]
    )
    version = unstable_version(payload.get("date"))
    hash_value = payload.get("hash")
    if not isinstance(hash_value, str):
        hash_value = payload.get("sha256")
    if not isinstance(hash_value, str):
        raise TypeError("nix-prefetch-git returned no WebKit hash")

    return {
        "rev": revision,
        "version": version,
        "hash": hash_value,
        "sparseCheckout": current["sparseCheckout"],
    }


def nix_hash_from_fake_build(expression: str, name: str) -> str:
    arguments = ["nix", "build", "--impure", "--no-link", "--expr", expression]
    print_command(arguments)
    result = subprocess.run(
        arguments,
        cwd=NIXPKGS_ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", result.stdout)
    if match is None:
        raise RuntimeError(f"Cannot determine {name}:\n{result.stdout}")
    return match.group(1)


def cargo_hash(version: str, source: Path) -> str:
    expression = f"""
let
  pkgs = import (builtins.toPath {json.dumps(str(NIXPKGS_ROOT))}) {{}};
in
pkgs.rustPlatform.fetchCargoVendor {{
  pname = "bun-cargo-deps";
  version = {json.dumps(version)};
  src = builtins.storePath {json.dumps(str(source))};
  hash = {json.dumps(FAKE_HASH)};
}}
"""
    return nix_hash_from_fake_build(expression, "Cargo vendor hash")


def node_modules_hash(version: str, source: Path) -> str:
    expression = f"""
let
  pkgs = import (builtins.toPath {json.dumps(str(NIXPKGS_ROOT))}) {{}};
  nodeModules = pkgs.callPackage (builtins.toPath {json.dumps(str(PACKAGE_DIR / "node-modules.nix"))}) {{}};
in
nodeModules {{
  version = {json.dumps(version)};
  src = builtins.storePath {json.dumps(str(source))};
  hash = {json.dumps(FAKE_HASH)};
}}
"""
    return nix_hash_from_fake_build(expression, "node modules hash")


def save_sources(sources: Sources) -> None:
    content = json.dumps(sources, indent=2) + "\n"
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=SOURCES_FILE.parent,
            prefix=f".{SOURCES_FILE.name}.",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(content)
        temporary_path.replace(SOURCES_FILE)
    except Exception:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
        raise


def parse_arguments() -> Arguments:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="Update to this stable Bun version")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Regenerate hashes when the version is unchanged",
    )
    return parser.parse_args(namespace=Arguments())


def main() -> None:
    arguments = parse_arguments()
    current = load_sources()
    releases = stable_releases()
    version = arguments.version or max(releases, key=version_key)

    revision = releases.get(version)
    if revision is None:
        raise RuntimeError(f"Bun release bun-v{version} does not exist")
    if version == current["version"] and not arguments.force:
        print(f"Bun {version} is already up to date")
        return

    source_hash, source = prefetch_file(
        f"https://github.com/oven-sh/bun/archive/{revision}.tar.gz",
        unpack=True,
    )
    validate_llvm_version(source)

    downloads = source_archives(source)
    download_hashes = prefetch_hashes(downloads)
    webkit = pin_webkit(source, current["webkit"], force=arguments.force)
    cargo = cargo_hash(version, source)
    node_modules = node_modules_hash(version, source)

    updated: Sources = {
        "version": version,
        "revision": revision,
        "sourceHash": source_hash,
        "cargoHash": cargo,
        "nodeModulesHash": node_modules,
        "downloads": pin_downloads(downloads, download_hashes),
        "webkit": webkit,
    }
    save_sources(updated)
    print(f"Updated {SOURCES_FILE.relative_to(NIXPKGS_ROOT)}")


if __name__ == "__main__":
    main()
