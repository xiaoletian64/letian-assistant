"""Credential-free, append-only quota observations; no provider/network calls."""
from contextlib import contextmanager
import hashlib
import json
import math
import os
import sqlite3
from pathlib import Path

FIELDS = ('provider','account','source','window','source_time','observed_time','used','remaining','limit','units','reset_at','reset_basis','error')
RAW_FIELDS = {'used','remaining','limit','units','reset_at','reset_basis','total','available','usage','usage_percent','remaining_percent','plan','window','period_start','period_end','rem','reset','billingCycleEnd','plan_expires_at','u','s','window_seconds'}

class Store:
    def __init__(self, path):
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self._db() as db:
            os.chmod(self.path, 0o600)
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('CREATE TABLE IF NOT EXISTS snapshots (id INTEGER PRIMARY KEY, fingerprint TEXT UNIQUE NOT NULL, provider TEXT NOT NULL, window TEXT NOT NULL, source_time REAL, observed_time REAL NOT NULL, payload TEXT NOT NULL)')
            db.execute('CREATE INDEX IF NOT EXISTS snapshots_filter ON snapshots(provider, window, id)')
            db.execute("CREATE INDEX IF NOT EXISTS snapshots_series ON snapshots(provider,window,json_extract(payload,'$.account'),json_extract(payload,'$.source'),json_extract(payload,'$.units'),source_time DESC,id DESC)")
            db.execute('CREATE INDEX IF NOT EXISTS snapshots_observed ON snapshots(observed_time,id)')
            db.execute("CREATE TRIGGER IF NOT EXISTS no_update BEFORE UPDATE ON snapshots BEGIN SELECT RAISE(ABORT, 'append only'); END")
            db.execute("CREATE TRIGGER IF NOT EXISTS no_delete BEFORE DELETE ON snapshots BEGIN SELECT RAISE(ABORT, 'append only'); END")
    @contextmanager
    def _db(self):
        db=sqlite3.connect(self.path, timeout=30)
        db.row_factory=sqlite3.Row
        try:
            with db: yield db
        finally: db.close()
    def append(self, snapshot):
        s={k:snapshot.get(k) for k in FIELDS}
        for k in ('provider','account','source','window','units'):
            if not isinstance(s[k], str) or not s[k]: raise ValueError(k+' required')
        for k in ('source_time','observed_time','used','remaining','limit','reset_at'):
            v=s[k]
            if v is not None and (isinstance(v,bool) or not isinstance(v,(float,int)) or (isinstance(v,float) and not math.isfinite(v))): raise ValueError(k+' must be finite numeric or null')
        if s['observed_time'] is None: raise ValueError('observed_time required')
        # Error must be a safe status code, never response bodies containing credentials.
        if s['error'] is not None and (not isinstance(s['error'],str) or not all(c.isalnum() or c in '_-.' for c in s['error']) or len(s['error'])>80): raise ValueError('safe error code required')
        raw=snapshot.get('raw') or {}
        s['raw']={k:v for k,v in raw.items() if k in RAW_FIELDS and (v is None or isinstance(v,(str,int,float,bool)))}
        identity={k:v for k,v in s.items() if k!='observed_time'}
        # Without a source time, observations are distinct, not falsely deduplicated.
        if s['source_time'] is None: identity['observed_time']=s['observed_time']
        fingerprint=hashlib.sha256(json.dumps(identity,sort_keys=True,allow_nan=False).encode()).hexdigest()
        s.update(delta=None,delta_basis=None,event=None)
        with self._db() as db:
            db.execute('BEGIN IMMEDIATE')
            prior=db.execute("SELECT payload FROM snapshots WHERE provider=? AND window=? AND json_extract(payload,'$.account')=? AND json_extract(payload,'$.source')=? AND json_extract(payload,'$.units')=? ORDER BY source_time DESC,id DESC LIMIT 1",(s['provider'],s['window'],s['account'],s['source'],s['units'])).fetchone()
            previous=json.loads(prior[0]) if prior else None
            if previous and s['source_time'] is not None and previous['source_time'] is not None and s['source_time']>previous['source_time'] and not s['error'] and not previous['error']:
                p=previous
                decrease=s['used'] is not None and p['used'] is not None and s['used']<p['used']
                increase=s['remaining'] is not None and p['remaining'] is not None and s['remaining']>p['remaining']
                if s['reset_basis']=='source_explicit': s['event']='confirmed'
                elif decrease and p['reset_at'] is not None and p['source_time']<p['reset_at']<=s['source_time']: s['event']='inferred'
                elif decrease or increase: s['event']='candidate'
                elif s['used'] is not None and p['used'] is not None and s['used']>=0 and p['used']>=0 and s['limit'] is not None and s['limit']==p['limit'] and s['reset_at'] is not None and s['reset_at']==p['reset_at'] and s['source_time']<s['reset_at']:
                    s['delta']=s['used']-p['used']; s['delta_basis']='estimated'
            db.execute('INSERT OR IGNORE INTO snapshots(fingerprint,provider,window,source_time,observed_time,payload) VALUES(?,?,?,?,?,?)',(fingerprint,s['provider'],s['window'],s['source_time'],s['observed_time'],json.dumps(s,allow_nan=False)))
            return db.execute('SELECT id FROM snapshots WHERE fingerprint=?',(fingerprint,)).fetchone()[0]
    def query(self, **params):
        if set(params)-{'provider','window','from','to','cursor','limit'}: raise ValueError('unknown parameter')
        try:
            limit=int(params.get('limit',100))
            if not 1<=limit<=200: raise ValueError()
            clauses=[]; args=[]
            for key in ('provider','window'):
                if key in params:
                    if not isinstance(params[key],str) or len(params[key])>200: raise ValueError()
                    clauses.append(key+'=?'); args.append(params[key])
            for key, column, operator, cast in [('from','observed_time','>=',float),('to','observed_time','<=',float),('cursor','id','<',int)]:
                if key in params:
                    v=cast(params[key])
                    if not math.isfinite(v): raise ValueError()
                    clauses.append(column+operator+'?'); args.append(v)
        except (TypeError,ValueError,OverflowError): raise ValueError('invalid query parameter') from None
        with self._db() as db:
            rows=db.execute('SELECT id,payload FROM snapshots'+(' WHERE '+' AND '.join(clauses) if clauses else '')+' ORDER BY id DESC LIMIT ?',args+[limit+1]).fetchall()
        items=[dict(json.loads(r['payload']),id=r['id']) for r in rows[:limit]]
        return {'items':items,'next_cursor':items[-1]['id'] if len(rows)>limit else None}
