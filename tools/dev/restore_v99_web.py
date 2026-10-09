"""Restore the user's v99 web sources from their pinned Release archive."""
import hashlib
from pathlib import Path, PurePosixPath
import stat
import sys
import zipfile

EXPECTED_SHA256 = "8011b2d8e108ce392f11a42e48f8a59696d6c6748fa1945177deec0d709cd724"

def restore(archive, root):
    root = Path(root).resolve()
    if hashlib.sha256(Path(archive).read_bytes()).hexdigest() != EXPECTED_SHA256:
        raise ValueError("v99 web archive checksum mismatch")
    with zipfile.ZipFile(archive) as bundle:
        targets = []
        seen = set()
        entries = bundle.infolist()
        if len(entries) > 1000 or sum(e.file_size for e in entries) > 100_000_000:
            raise ValueError("unexpected web archive size")
        for entry in entries:
            name = PurePosixPath(entry.filename.replace("\\", "/"))
            if name.is_absolute() or ".." in name.parts or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("unsafe web archive entry")
            if name.as_posix() == "verify_web_release.py":
                continue  # The verification script is tracked under tools/release/.
            if not name.parts or name.parts[0] != "web":
                raise ValueError("unexpected web archive entry")
            if entry.is_dir() or entry.filename.replace("\\", "/").endswith("/"):
                continue
            target = root.joinpath(*name.parts)
            if not target.resolve().is_relative_to(root / "web") or target in seen:
                raise ValueError("unsafe or duplicate web target")
            seen.add(target)
            data = bundle.read(entry)
            if target.exists() and target.read_bytes() != data:
                raise ValueError("existing web file differs from v99: " + name.as_posix())
            targets.append((target, data))
        for required in ("index.html", "manifest.json", "startup.js", "icon.png"):
            if root / "web" / required not in seen:
                raise ValueError("required web source missing")
        for target, data in targets:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    print(f"Restored {len(targets)} original web source files; SHA-256 verified.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tools/dev/restore_v99_web.py path/to/recipe-scout-web-20261009-184000.zip")
    restore(sys.argv[1], Path(__file__).resolve().parents[2])
