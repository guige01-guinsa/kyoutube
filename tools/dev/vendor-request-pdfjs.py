"""Vendor pinned, same-origin PDF rendering assets with npm integrity verification."""
import base64
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request

VERSION = '5.7.284'
ROOT = Path(__file__).resolve().parents[2]
target = ROOT / 'web' / 'vendor' / 'pdfjs'
metadata = json.load(urllib.request.urlopen(f'https://registry.npmjs.org/pdfjs-dist/{VERSION}', timeout=30))
dist = metadata['dist']
expected_url = f'https://registry.npmjs.org/pdfjs-dist/-/pdfjs-dist-{VERSION}.tgz'
assert dist['tarball'] == expected_url
payload = urllib.request.urlopen(expected_url, timeout=90).read()
integrity = 'sha512-' + base64.b64encode(hashlib.sha512(payload).digest()).decode()
assert integrity == dist['integrity'], 'npm tarball integrity mismatch'
files = {}
with tarfile.open(fileobj=io.BytesIO(payload), mode='r:gz') as archive:
    for member in archive.getmembers():
        name = member.name
        keep = name in ('package/build/pdf.min.mjs', 'package/build/pdf.worker.min.mjs', 'package/LICENSE') or name.startswith('package/wasm/')
        if not keep or not member.isfile():
            continue
        relative = name.removeprefix('package/').removeprefix('build/')
        path = (target / relative).resolve()
        assert path.is_relative_to(target.resolve())
        data = archive.extractfile(member).read()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        files[relative] = hashlib.sha256(data).hexdigest()
target.joinpath('manifest.json').write_text(json.dumps({'version':VERSION,'source':expected_url,'integrity':integrity,'sha256':files},indent=2)+'\n',encoding='utf-8')
print(f'Verified pdfjs-dist {VERSION}: {len(files)} local assets')
