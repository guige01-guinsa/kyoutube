import importlib.util, pathlib, unittest
from cryptography.exceptions import InvalidTag
spec=importlib.util.spec_from_file_location('crypto',pathlib.Path(__file__).resolve().parents[1]/'ops/recovery_crypto.py')
crypto=importlib.util.module_from_spec(spec);spec.loader.exec_module(crypto)
class RecoveryTests(unittest.TestCase):
    def test_round_trip_without_windows_account(self):
        password=b'fake-fixture-password-at-least-24-bytes'
        sealed=crypto.seal(b'fake database and storage fixture',password)
        self.assertEqual(crypto.unseal(sealed,password),b'fake database and storage fixture')
        self.assertNotIn('windows_user_key',sealed)
        self.assertNotIn(password.decode(),str(sealed))
        with self.assertRaises(InvalidTag):crypto.unseal(sealed,b'another-fixture-password-at-least-24-bytes')
        sealed['ciphertext']=sealed['ciphertext'][:-4]+'AAAA'
        with self.assertRaises(InvalidTag):crypto.unseal(sealed,password)
    def test_weak_password_and_unbounded_kdf_rejected(self):
        with self.assertRaises(ValueError):crypto.seal(b'x',b'weak')
        with self.assertRaises(ValueError):crypto.unseal({'format':crypto.FORMAT,'kdf':'unbounded'},b'x'*32)
if __name__=='__main__':unittest.main()
