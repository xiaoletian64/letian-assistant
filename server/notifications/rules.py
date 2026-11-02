"""Deterministic notification rules. Times are UTC epoch seconds; no I/O.

series_id MUST identify a canonical source/account/metric, shared by verified
mirrors only. Subscription values are remaining fractions (0..1). Each server
metric is a separate series (CPU, memory, disk or sampling availability).
"""
from dataclasses import dataclass
import hashlib
import json
import math

@dataclass(frozen=True)
class Observation:
    account_id: str
    series_id: str
    source_time: float
    kind: str
    value: float | None
    unit: str
    window: str = 'default'
    cycle: str = 'default'
    valid: bool = True
    fresh: bool = True
    reset_evidence: str | None = None
    reset_boundary: float | None = None
    previous_used: float | None = None
    current_used: float | None = None


def series_key(o):
    return json.dumps([o.account_id,o.series_id,o.kind,o.unit,o.window],separators=(',',':'))


def evaluate(o, state):
    """Return (copied state, event dicts); duplicates/older samples are ignored.

    Invalid or stale observations interrupt confirmation. Reset verification
    accepts source_explicit, or verified_cycle plus an elapsed boundary and
    a strictly decreased nonnegative used counter.
    """
    if not o.account_id or not o.series_id or not math.isfinite(o.source_time):
        raise ValueError('canonical identity and finite source_time required')
    s=dict(state); events=[]
    if o.source_time <= s.get('last_time',float('-inf')):
        return s, events
    s['last_time']=o.source_time
    def emit(event_type):
        identity=json.dumps([series_key(o),o.cycle,o.source_time,event_type],separators=(',',':'))
        events.append(dict(id=hashlib.sha256(identity.encode()).hexdigest(),account_id=o.account_id,series_id=o.series_id,type=event_type,source_time=o.source_time,window=o.window,cycle=o.cycle))
    numeric=isinstance(o.value,(int,float)) and not isinstance(o.value,bool) and math.isfinite(o.value) and o.value >= 0
    usable=o.valid and o.fresh and numeric
    if o.kind=='server':
        usable = usable and o.unit == 'percent' and o.value <= 100
        if not o.fresh:
            s['healthy']=0; s['high_since']=None; s['fail_count']=0; s['fail_since']=None
            return s, events
        if not usable:
            s['healthy']=0; s['high_since']=None
            s['fail_count']=s.get('fail_count',0)+1
            if s.get('fail_since') is None: s['fail_since']=o.source_time
            if s['fail_count']>=3 and o.source_time-s['fail_since']>=60 and not s.get('unreachable'):
                s['unreachable']=True; emit('monitor_unreachable')
        else:
            s['fail_count']=0; s['fail_since']=None
            if o.value>=90:
                s['healthy']=0
                if s.get('high_since') is None: s['high_since']=o.source_time
                if o.source_time-s['high_since']>=300 and not s.get('anomaly'):
                    s['anomaly']=True; emit('server_anomaly')
            else:
                s['high_since']=None; s['healthy']=s.get('healthy',0)+1
                if s['healthy']>=2 and (s.get('anomaly') or s.get('unreachable')):
                    s['anomaly']=False; s['unreachable']=False; emit('server_recovered')
        return s, events
    threshold=({'CNY':5,'USD':1}.get(o.unit) if o.kind=='balance' else .1 if o.kind=='subscription' and o.unit=='ratio' else None)
    if not usable or threshold is None or (o.kind=='subscription' and o.value>1):
        s['healthy']=0
        return s, events
    previous_cycle=s.get('cycle')
    verified=(o.reset_evidence=='source_explicit' or (
        o.reset_evidence=='verified_cycle' and o.reset_boundary is not None
        and s.get('valid_time',o.source_time)<o.reset_boundary<=o.source_time
        and all(isinstance(v,(int,float)) and math.isfinite(v) and v>=0 for v in (o.previous_used,o.current_used))
        and o.current_used<o.previous_used))
    reset=o.kind=='subscription' and previous_cycle is not None and previous_cycle!=o.cycle and verified
    if reset:
        emit('quota_reset'); s['low']=False; s['healthy']=0
    s['cycle']=o.cycle; s['valid_time']=o.source_time
    prefix='balance' if o.kind=='balance' else 'quota'
    if o.value<threshold:
        s['healthy']=0
        if not s.get('low'):
            s['low']=True; emit(prefix+'_low')
    elif s.get('low'):
        s['healthy']=s.get('healthy',0)+1
        if s['healthy']>=2:
            s['low']=False; s['healthy']=0; emit(prefix+'_recovered')
    else:
        s['healthy']=0
    return s,events
