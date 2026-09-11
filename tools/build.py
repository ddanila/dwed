#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the Pascal editor with a checksum-pinned Linux x86_64 FPC toolchain."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PIN = json.loads((ROOT / 'tools/toolchain.json').read_text())


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='use a previously downloaded pinned archive')
    parser.add_argument('--tests', action='store_true', help='also build DOS regression probes')
    parser.add_argument('--output', type=Path, default=ROOT / 'out/build')
    args = parser.parse_args()
    assembler = shutil.which('nasm')
    if assembler is None:
        parser.error('NASM is required to build the 8086 launcher')
    assembler_version = subprocess.check_output([assembler, '-v'], text=True).strip()
    output = args.output.resolve()
    if output.exists():
        parser.error('output must not exist; use a new directory for a clean build')
    cache = ROOT / 'out/toolchain'
    cache.mkdir(parents=True, exist_ok=True)
    archive = args.archive or cache / 'fpc-cross.tar.xz'
    if not archive.exists():
        if args.archive:
            parser.error('specified archive does not exist')
        with tempfile.NamedTemporaryFile(dir=cache, delete=False) as target:
            pending = Path(target.name)
            try:
                with urllib.request.urlopen(PIN['url'], timeout=60) as source:
                    shutil.copyfileobj(source, target)
                target.flush()
                if digest(pending) != PIN['sha256']:
                    raise ValueError('downloaded compiler archive checksum mismatch')
                pending.replace(archive)
            finally:
                pending.unlink(missing_ok=True)
    if digest(archive) != PIN['sha256']:
        raise ValueError('compiler archive checksum mismatch')
    # Extract privately every time: no stale or locally modified RTL/PPU input.
    with tempfile.TemporaryDirectory(prefix='fpc-', dir=cache) as temporary:
        compiler_root = Path(temporary)
        with tarfile.open(archive) as bundle:
            bundle.extractall(compiler_root, filter='data')
        lib = compiler_root / 'lib/fpc' / PIN['version']
        output.mkdir(parents=True)
        subprocess.run([assembler, '-f', 'bin', str(ROOT / 'SRC/LAUNCH.ASM'),
                        '-o', str(output / 'DWED.COM')], check=True)
        subprocess.run(['python3', str(ROOT / 'tools/build_help.py'),
                        str(ROOT / 'SRC/DWED.TXT'), str(output)], check=True)
        command = [str(lib / 'ppcross8086'), '-n', '-Mtp', '-Cp8086', '-Wmlarge', '-XX',
                   '-Fi' + str(output), '-Fu' + str(lib / 'units/msdos/8086-large/rtl'),
                   '-Fu' + str(ROOT / 'SRC'), '-Fu' + str(ROOT / 'vendor/system2'),
                   '-FU' + str(output), '-FE' + str(output), str(ROOT / 'SRC/DWEDOVL.PAS')]
        with (output / 'compiler.log').open('wb') as log:
            subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT, check=True)
            if args.tests:
                for probe in ('KEYTEST', 'UNDOTEST', 'STORTEST', 'CLIPTEST', 'TABTEST', 'SAVETEST'):
                    subprocess.run(command[:-1] + [str(ROOT / ('tests/' + probe + '.PAS'))],
                                   cwd=output, stdout=log, stderr=subprocess.STDOUT, check=True)
    shutil.copyfile(ROOT / 'BIN/DWED.CFG', output / 'DWED.CFG')
    artifacts = ['DWED.COM', 'DWEDOVL.exe', 'DWED.CFG', 'dwedhelp.hlp']
    if args.tests:
        artifacts.extend(['KEYTEST.exe', 'UNDOTEST.exe', 'STORTEST.exe', 'CLIPTEST.exe', 'TABTEST.exe', 'SAVETEST.exe'])
    report = {'toolchain': PIN, 'target': '8086-msdos-large',
              'assembler': assembler_version,
              'scope': 'source-built launcher, editor overlay and help',
              'artifacts': {name: {'bytes': (output / name).stat().st_size,
                                   'sha256': digest(output / name)} for name in artifacts}}
    (output / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
    print(output / 'build.json')


if __name__ == '__main__':
    main()
