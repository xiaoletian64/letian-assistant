"""SQLite atomic rule state and account-isolated event persistence."""
import json
import sqlite3
from .rules import evaluate, series_key

class Store:
    def __init__(self, path):
        self.connection=sqlite3.connect(path,timeout=30)
        self.connection.execute('PRAGMA journal_mode=WAL')
        self.connection.executescript('''
        CREATE TABLE IF NOT EXISTS alert_rule_state (series_key TEXT PRIMARY KEY, state TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS alert_events (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, source_time REAL NOT NULL, payload TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS alert_events_account ON alert_events(account_id,source_time);
        ''')
    def process(self, observation):
        """Serialize state transitions and inserts; return newly persisted events."""
        c=self.connection
        try:
            c.execute('BEGIN IMMEDIATE')
            key=series_key(observation)
            row=c.execute('SELECT state FROM alert_rule_state WHERE series_key=?',(key,)).fetchone()
            state,events=evaluate(observation,json.loads(row[0]) if row else {})
            c.execute('INSERT INTO alert_rule_state VALUES (?,?) ON CONFLICT(series_key) DO UPDATE SET state=excluded.state',(key,json.dumps(state,allow_nan=False)))
            inserted=[]
            for e in events:
                cur=c.execute('INSERT OR IGNORE INTO alert_events VALUES (?,?,?,?)',(e['id'],e['account_id'],e['source_time'],json.dumps(e)))
                if cur.rowcount: inserted.append(e)
            c.commit()
            return inserted
        except BaseException:
            c.rollback(); raise
    def list_events(self, account_id, limit=100):
        if not account_id: raise ValueError('account_id required')
        return [json.loads(r[0]) for r in self.connection.execute('SELECT payload FROM alert_events WHERE account_id=? ORDER BY source_time DESC,id LIMIT ?',(account_id,max(0,min(int(limit),1000))))]
    def close(self): self.connection.close()
    def __enter__(self): return self
    def __exit__(self,*args): self.close()
