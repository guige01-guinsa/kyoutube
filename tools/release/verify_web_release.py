"""Verify production web inputs/output without printing or copying credentials."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, base64, hashlib, json, re

ROOT = Path(__file__).resolve().parents[2]
PROJECT = 'dfczeudklykypysiseck'

def defines(path):
    result = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition('=')
        assert separator and re.fullmatch(r'[A-Z0-9_]+', key), 'Invalid define format'
        result[key] = value.strip().strip('"').strip("'")
    return result

def public_key(key):
    if key.startswith('sb_publishable_'):
        return True
    try:
        payload = key.split('.')[1]
        data = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        return data.get('role') == 'anon' and data.get('ref') == PROJECT
    except (IndexError, ValueError):
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--defines', default='.env.production')
    parser.add_argument('--output', default='build/web-production')
    parser.add_argument('--preflight', action='store_true')
    args = parser.parse_args()
    values = defines(ROOT / args.defines)
    required = {'APP_ENV', 'SUPABASE_URL_PRODUCTION', 'SUPABASE_ANON_KEY_PRODUCTION'}
    assert required <= values.keys(), 'Missing production defines'
    assert not (values.keys() - required - {'APP_BUILD'}), 'Unexpected web build define names'
    assert values['APP_ENV'] == 'production', 'Production APP_ENV required'
    assert values['SUPABASE_URL_PRODUCTION'].rstrip('/') == f'https://{PROJECT}.supabase.co', 'Production project mismatch'
    assert public_key(values['SUPABASE_ANON_KEY_PRODUCTION']), 'Public anonymous/publishable key required'
    assert (ROOT / 'supabase/.temp/project-ref').read_text().strip() == PROJECT, 'Linked project mismatch'
    if args.preflight:
        print('Production web inputs verified; no credential values written.')
        return
    out = (ROOT / args.output).resolve()
    assert out.is_relative_to(ROOT / 'build') and out != ROOT / 'build', 'Web output must be inside build/'
    for name in ('index.html', 'startup.js', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json'):
        assert (out / name).is_file(), 'Missing web asset: ' + name
    main_js = (out / 'main.dart.js').read_bytes()
    assert values['SUPABASE_URL_PRODUCTION'].encode() in main_js, 'Production endpoint absent from bundle'
    assert values['SUPABASE_ANON_KEY_PRODUCTION'].encode() in main_js, 'Public client key absent from bundle'
    assert b'http://127.0.0.1:54321' not in main_js, 'Local backend found in production bundle'
    assert not (out / 'main.dart.js.map').exists(), 'Application source map must not be published'
    html = (out / 'index.html').read_text(encoding='utf-8')
    assert '$FLUTTER_BASE_HREF' not in html and '<script>' not in html, 'Unsafe or unbuilt entry HTML'
    for file in out.rglob('*'):
        if not file.is_file():
            continue
        assert not file.name.startswith('.env'), 'Environment file in public output'
        if file.suffix not in ('.js', '.json', '.html', '.txt'):
            continue
        data = file.read_bytes()
        assert not re.search(rb'\bsbp_[A-Za-z0-9]{20,}|\bsb_secret_[A-Za-z0-9_-]{20,}', data), 'Privileged API credential found'
        assert not re.search(rb'-----BEGIN [A-Z ]*PRIVATE KEY-----(?:\s|\\n)+M[A-Za-z0-9+/]{30,}', data), 'Private key found'
        for token in set(re.findall(rb'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', data)):
            try:
                payload = token.split(b'.')[1]
                role = json.loads(base64.urlsafe_b64decode(payload + b'=' * (-len(payload) % 4))).get('role')
                assert role != 'service_role', 'Service credential found in public bundle'
            except (ValueError, UnicodeDecodeError):
                pass
    version = re.search(r'^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(), re.M).group(1)
    report = {'app': 'recipe-scout-web', 'version': version, 'appEnv': 'production',
              'projectRef': PROJECT, 'verifiedUtc': datetime.now(timezone.utc).isoformat(),
              'mainJsSha256': hashlib.sha256(main_js).hexdigest(), 'mainJsBytes': len(main_js),
              'fileCount': sum(p.is_file() for p in out.rglob('*')),
              'privilegedCredentialScan': 'passed', 'sourceMapAbsent': True}
    (out / 'release-info.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (ROOT / '.artifacts').mkdir(exist_ok=True)
    (ROOT / '.artifacts/web-production-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))

if __name__ == '__main__':
    main()
