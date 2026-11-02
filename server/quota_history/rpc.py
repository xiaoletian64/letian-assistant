"""Read-only fixed-command RPC. JSON parameters on stdin, never in shell text."""
from contextlib import contextmanager
import json
from pathlib import Path
import sqlite3
import sys
from .history import Store

class Reader(Store):
    def __init__(self,path): self.path=str(Path(path).resolve())
    @contextmanager
    def _db(self):
        db=sqlite3.connect(Path(self.path).as_uri()+'?mode=ro',uri=True,timeout=5)
        db.row_factory=sqlite3.Row
        db.execute('PRAGMA query_only=ON')
        try:
            yield db
        finally: db.close()

def query(path,params):
    if not isinstance(params,dict): raise ValueError('object required')
    return Reader(path).query(**params)

def main():
    try:
        raw=sys.stdin.buffer.read(4097)
        if len(raw)>4096: raise ValueError('request too large')
        result=query('/var/lib/quota-history/history.sqlite3',json.loads(raw))
        print(json.dumps(result,ensure_ascii=False,allow_nan=False))
    except ValueError:
        print(json.dumps({'error':'invalid_history_query'})); sys.exit(2)
    except Exception:
        print(json.dumps({'error':'history_unavailable'})); sys.exit(1)
if __name__=='__main__': main()
