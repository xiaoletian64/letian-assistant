import sqlite3
import tempfile
import unittest
from pathlib import Path
from server.quota_history.history import Store
from server.quota_history.backup import backup
class BackupTests(unittest.TestCase):
 def test_online_backup_restores_history(self):
  with tempfile.TemporaryDirectory() as d:
   src=Path(d)/'source'; target=Path(d)/'backup'
   Store(src).append(dict(provider='mimo',account='a',source='cache',window='month',units='credits',source_time=1,observed_time=1,used=1))
   backup(src,target)
   self.assertEqual(Store(target).query()['items'][0]['used'],1)
   with sqlite3.connect(target) as db:self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0],'ok')
 def test_systemd_sandbox_allows_sqlite_wal_sidecars(self):
  unit=(Path(__file__).parent/'systemd/quota-history-backup.service').read_text()
  writable=[line.split('=',1)[1] for line in unit.splitlines() if line.startswith('ReadWritePaths=')]
  self.assertIn('/var/lib/quota-history',' '.join(writable).split())
  self.assertIn('/var/backups/quota-history',' '.join(writable).split())
  self.assertIn('ProtectSystem=strict',unit)
  self.assertIn("'?mode=ro'",(Path(__file__).parent/'backup.py').read_text())
