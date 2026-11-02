import pathlib,tempfile,unittest
from export_public import allowed,scan,export
class PrivacyTests(unittest.TestCase):
    def test_private_state_excluded(self):
        for p in ['.git/config','android/local.properties','lib/main.dart.bak-old','build/app.apk','ios/Runner/key.p12','server/router-reliability/original/a.py']:
            self.assertFalse(allowed(pathlib.Path(p)),p)
    def test_detects_sensitive_material(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d); (p/'lib').mkdir()
            (p/'lib/a.dart').write_text('-----BEGIN ' + 'PRIVATE KEY-----')
            self.assertTrue(scan(p))
    def test_accepts_generic_source(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d); (p/'lib').mkdir(); (p/'lib/a.dart').write_text('https://api.example.org')
            self.assertEqual(scan(p),[])
    def test_real_source_exports_without_local_state(self):
        with tempfile.TemporaryDirectory() as d:
            out=pathlib.Path(d)/'public'
            self.assertGreater(export(out),100)
            self.assertFalse((out/'.git').exists())
            self.assertFalse((out/'android/local.properties').exists())
            self.assertFalse((out/'server/router-reliability').exists())
if __name__=='__main__': unittest.main()
