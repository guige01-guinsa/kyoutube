import importlib.util, json, subprocess, tempfile, unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('guard', Path(__file__).resolve().parents[1] / 'web_release_guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

class GuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        def run(*args):
            return subprocess.check_output(['git', *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL).strip()
        self.git = run
        run('init')
        (self.root / '.gitignore').write_text('/build/\n/.artifacts/\n')
        (self.root / 'source.txt').write_text('approved source')
        run('add', '.')
        run('-c', 'user.name=Guard Test', '-c', 'user.email=guard@example.invalid', 'commit', '-m', 'approved')
        self.sha = run('rev-parse', 'HEAD')
        self.out = self.root / 'build/web-production'
        self.out.mkdir(parents=True)
        (self.out / 'main.dart.js').write_text('verified bundle')
        report = {**guard.source(self.root, self.sha), 'qualityPassed': True, 'files': guard.files(self.out)}
        (self.out / guard.MANIFEST).write_text(json.dumps(report))

    def test_approved_clean_build(self):
        guard.check(self.root, self.sha)

    def test_wrong_commit_blocked(self):
        with self.assertRaisesRegex(RuntimeError, 'differs'):
            guard.check(self.root, '0' * 40)

    def test_dirty_source_blocked(self):
        (self.root / 'source.txt').write_text('unreviewed')
        with self.assertRaisesRegex(RuntimeError, 'working changes'):
            guard.check(self.root, self.sha)

    def test_untracked_source_blocked(self):
        (self.root / 'surprise.txt').write_text('new source')
        with self.assertRaisesRegex(RuntimeError, 'working changes'):
            guard.check(self.root, self.sha)

    def test_modified_added_deleted_bundle_blocked(self):
        for action in ('modified', 'added', 'deleted'):
            with self.subTest(action=action):
                (self.out / 'main.dart.js').write_text('verified bundle')
                extra = self.out / 'extra.js'
                extra.unlink(missing_ok=True)
                if action == 'modified': (self.out / 'main.dart.js').write_text('wrong bundle')
                if action == 'added': extra.write_text('surprise')
                if action == 'deleted': (self.out / 'main.dart.js').unlink()
                with self.assertRaisesRegex(RuntimeError, 'changed'):
                    guard.check(self.root, self.sha)

    def test_quality_failure_blocked(self):
        p = self.out / guard.MANIFEST
        data = json.loads(p.read_text()); data['qualityPassed'] = False; p.write_text(json.dumps(data))
        with self.assertRaisesRegex(RuntimeError, 'Quality'):
            guard.check(self.root, self.sha)

    def test_stale_manifest_blocked(self):
        p = self.out / guard.MANIFEST
        data = json.loads(p.read_text()); data['sourceCommit'] = '0' * 40; p.write_text(json.dumps(data))
        with self.assertRaisesRegex(RuntimeError, 'Stale'):
            guard.check(self.root, self.sha)

    def test_unsealed_build_blocked(self):
        (self.out / guard.MANIFEST).unlink()
        with self.assertRaises(FileNotFoundError): guard.check(self.root, self.sha)

    def test_nested_manifest_is_checked(self):
        nested = self.out / 'assets'; nested.mkdir()
        (nested / guard.MANIFEST).write_text('unexpected')
        with self.assertRaisesRegex(RuntimeError, 'changed'):
            guard.check(self.root, self.sha)

if __name__ == '__main__': unittest.main()
