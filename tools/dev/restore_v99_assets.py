"""Restore the original v99 assets from the user-provided release ZIP."""
import hashlib
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import zipfile

EXPECTED_SHA256 = "9539bb1ebae44e1234bcbcd945473138793eaa6d7709b220a05ab334d5cdbe41"

def restore(archive, root):
    archive, root = Path(archive), Path(root).resolve()
    if hashlib.sha256(archive.read_bytes()).hexdigest() != EXPECTED_SHA256:
        raise ValueError("v99 assets ZIP checksum mismatch")
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        targets = []
        seen = set()
        if len(entries) > 1000 or sum(i.file_size for i in entries) > 100_000_000:
            raise ValueError("unexpected assets archive size")
        for entry in entries:
            name = PurePosixPath(entry.filename)
            if (name.is_absolute() or ".." in name.parts or "\\" in entry.filename
                    or not name.parts or name.parts[0] != "assets"
                    or stat.S_ISLNK(entry.external_attr >> 16)):
                raise ValueError("unsafe assets archive entry")
            if entry.is_dir():
                continue
            target = root.joinpath(*name.parts)
            if not target.resolve().is_relative_to(root / "assets"):
                raise ValueError("asset path escapes destination")
            if target in seen:
                raise ValueError("duplicate asset path")
            seen.add(target)
            if target.exists() and target.read_bytes() != bundle.read(entry):
                raise ValueError("existing asset differs from v99: " + entry.filename)
            targets.append((entry, target))
        required = [
            root / "assets/branding/recipe-scout-icon.png",
            root / "assets/fonts/NanumGothic-Regular.ttf",
            root / "assets/fonts/OFL-NanumGothic.txt",
        ]
        if not all(path in seen for path in required):
            raise ValueError("required v99 assets missing")
        if not all(any(p.is_relative_to(root / folder) for p in seen)
                   for folder in ("assets/ingredients", "assets/guide")):
            raise ValueError("required asset directories are empty")
        for entry, target in targets:
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(entry) as source, target.open("wb") as destination:
                shutil.copyfileobj(source, destination)
    print(f"Restored {len(targets)} original v99 assets; SHA-256 verified.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tools/dev/restore_v99_assets.py path/to/recipe-scout-v99-assets.zip")
    restore(sys.argv[1], Path(__file__).resolve().parents[2])
