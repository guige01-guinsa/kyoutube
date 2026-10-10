import importlib.util, pathlib, unittest
spec=importlib.util.spec_from_file_location('storage',pathlib.Path(__file__).resolve().parents[1]/'ops/recovery_storage.py')
storage=importlib.util.module_from_spec(spec);spec.loader.exec_module(storage)
class StorageTests(unittest.TestCase):
    def test_metadata_and_bytes_are_captured_together(self):
        sql=b'COPY storage.objects (bucket_id, name, metadata) FROM stdin;\nrecipes\tphoto\\tname.png\t{"size":3}\n\\.\n'
        calls=[]
        def download(bucket,name):calls.append((bucket,name));return b'png'
        files,count,size=storage.capture(sql,download)
        self.assertEqual(calls,[('recipes','photo\tname.png')])
        self.assertEqual((count,size),(1,3))
        self.assertEqual(files['storage-objects/0.bin'],b'png')
        self.assertIn(b'photo',files['storage-index.json'])
        with self.assertRaises(ValueError):storage.capture(sql,lambda *_:b'changed')
    def test_missing_or_truncated_snapshot_cannot_claim_backup(self):
        for sql in [b'',b'COPY storage.objects (bucket_id, name) FROM stdin;\nb\tn\n']:
            with self.assertRaises(ValueError):storage.capture(sql,lambda *_:b'')
if __name__=='__main__':unittest.main()
