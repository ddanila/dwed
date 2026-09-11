#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Stage a deterministic EDIT development package from verified build artifacts."""

import argparse
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = {
    "DWED.COM": "EDIT.COM",
    "DWEDOVL.exe": "DWEDOVL.EXE",
    "DWED.CFG": "DWED.CFG",
}
NOTICES = {
    "LICENSE": "LICENSES/DWED.TXT",
    "vendor/system2/LICENSE": "LICENSES/SYSTEM2.TXT",
    "licenses/fpc/COPYING.FPC": "LICENSES/FPC/COPYING.FPC",
    "licenses/fpc/COPYING.txt": "LICENSES/FPC/COPYING.TXT",
}


def fingerprint(data):
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def package(build, output):
    report = json.loads((build / "build.json").read_text())
    files = {}
    for source, target in ARTIFACTS.items():
        data = (build / source).read_bytes()
        if fingerprint(data) != report["artifacts"][source]:
            raise ValueError("build artifact does not match its manifest: " + source)
        files[target] = data
    for source, target in NOTICES.items():
        files[target] = (
            (ROOT / source).read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        )
    files["README.TXT"] = (
        "EDIT development build\r\n\r\n"
        "This DWED-based editor is still undergoing release qualification.\r\n"
        "Copy all files and the LICENSES directory to one DOS directory.\r\n"
        "Run EDIT filename. Keep DWEDOVL.EXE and DWED.CFG beside EDIT.COM.\r\n"
        "F1 opens the embedded help; F10 opens the classic menus.\r\n\r\n"
        "Editor and system2 sources are MIT licensed. The linked Free Pascal\r\n"
        "runtime has separate terms, including a linking exception. Preserve\r\n"
        "the LICENSES directory and these notices when redistributing.\r\n"
        "See SOURCES.TXT for source locations and runtime version.\r\n\r\n"
        "Recovery cleanup and broader platform qualification remain open.\r\n"
        "This package does not establish completion of the EDIT release gates.\r\n"
    ).encode("ascii")
    runtime = report["toolchain"]
    system2 = json.loads((ROOT / "vendor/system2/UPSTREAM.json").read_text())
    files["SOURCES.TXT"] = (
        "Editor project: https://github.com/ddanila/dwed\r\n"
        "Upstream editor: https://github.com/DosWorld/dwed\r\n"
        "System2 source: "
        + system2["repository"]
        + "/tree/"
        + system2["commit"]
        + "\r\n"
        "Free Pascal runtime version: " + runtime["version"] + "\r\n"
        "Runtime source: " + runtime["source"] + "\r\n"
    ).encode("ascii")
    output.mkdir(parents=True, exist_ok=False)
    directory = output / "files"
    for name, data in sorted(files.items()):
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    archive = output / "EDIT.ZIP"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as bundle:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 0
            entry.external_attr = 0x20
            bundle.writestr(entry, data)
    manifest = {
        "status": "development",
        "build": report,
        "files": {name: fingerprint(data) for name, data in sorted(files.items())},
        "archive": fingerprint(archive.read_bytes()),
    }
    (output / "package.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    package(args.build, args.output)
    print(args.output / "EDIT.ZIP")


if __name__ == "__main__":
    main()
