"""Fail closed on stale, modified, or unverified web releases. No credentials read."""
import argparse, hashlib, json, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = '.artifacts/web-source-verification.json'
MANIFEST = 'web-integrity.json'

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()

def source(root, expected):
    require(bool(re.fullmatch(r'[0-9a-f]{40}', expected)), 'Explicit full source commit required')
    require(Path(git(root, 'rev-parse', '--show-toplevel')).resolve() == root.resolve(), 'Use a real repository checkout')
    require(git(root, 'rev-parse', 'HEAD') == expected, 'Source commit differs from approved commit')
    require(not git(root, 'status', '--porcelain', '--untracked-files=normal'), 'Commit or review working changes before release')
    return {'sourceCommit': expected, 'sourceBranch': git(root, 'branch', '--show-current')}

def files(out):
    require(out.is_dir(), 'Web output missing')
    return {p.relative_to(out).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(out.rglob('*')) if p.is_file() and p.relative_to(out).as_posix() != MANIFEST}

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def check(root, expected):
    current = source(root, expected)
    out = root / 'build/web-production'
    sealed = read(out / MANIFEST)
    require(sealed['sourceCommit'] == current['sourceCommit'], 'Stale build from another commit')
    require(sealed.get('qualityPassed') is True, 'Quality verification missing')
    require(sealed['files'] == files(out), 'Web files changed after verification')
    return sealed

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['source', 'record-quality', 'seal', 'check', 'remote'])
    parser.add_argument('--expected-commit', required=True)
    args = parser.parse_args()
    current = source(ROOT, args.expected_commit)
    receipt = ROOT / RECEIPT
    out = ROOT / 'build/web-production'
    if args.action == 'record-quality':
        receipt.parent.mkdir(exist_ok=True)
        receipt.write_text(json.dumps({**current, 'qualityPassed': True}, indent=2), encoding='utf-8')
    elif args.action == 'seal':
        quality = read(receipt)
        require(quality == {**current, 'qualityPassed': True}, 'Quality receipt does not match source')
        require((out / 'release-info.json').is_file(), 'Production verification missing')
        require(read(out / 'release-info.json')['mainJsSha256'] == files(out).get('main.dart.js'), 'Bundle verification differs')
        report = {**quality, 'sealedUtc': datetime.now(timezone.utc).isoformat(), 'files': files(out)}
        (out / MANIFEST).write_text(json.dumps(report, indent=2), encoding='utf-8')
    elif args.action in ('check', 'remote'):
        report = check(ROOT, args.expected_commit)
        if args.action == 'remote':
            base = 'https://recipe-scout-workspace.web.app/'
            for name in ('main.dart.js', 'index.html', 'release-info.json'):
                request = Request(base + name + '?verify=' + args.expected_commit, headers={'Cache-Control': 'no-cache'})
                with urlopen(request, timeout=90) as response:
                    require(hashlib.sha256(response.read()).hexdigest() == report['files'][name], 'Published file mismatch: ' + name)
            with urlopen(base + MANIFEST + '?verify=' + args.expected_commit, timeout=30) as response:
                require(json.loads(response.read()) == report, 'Published source manifest mismatch')
    print('Web release guard passed: ' + args.action)

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        print('Web release blocked: ' + str(error), file=sys.stderr)
        sys.exit(1)
