"""SQLite online backup, including committed WAL. No pruning of history/backups."""
from contextlib import closing
from datetime import datetime, timezone
import os
from pathlib import Path
import sqlite3

def backup(source,target):
    target=Path(target)
    target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    # Exclusive creation prevents overwriting a previous backup.
    fd=os.open(target,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600); os.close(fd)
    try:
        with closing(sqlite3.connect(Path(source).resolve().as_uri()+'?mode=ro',uri=True)) as src, closing(sqlite3.connect(target)) as dst:
            src.backup(dst)
            if dst.execute('PRAGMA integrity_check').fetchone()[0]!='ok': raise RuntimeError('backup_integrity_failed')
    except Exception:
        target.unlink(missing_ok=True)
        raise

if __name__=='__main__':
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    backup('/var/lib/quota-history/history.sqlite3','/var/backups/quota-history/'+stamp+'.sqlite3')
