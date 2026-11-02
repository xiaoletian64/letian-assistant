"""Adapt existing snapshots only; never query inference or mutate providers."""
import datetime as dt
import math
import re
from .rules import Observation

def num(v):
 if isinstance(v,bool):return None
 try:n=float(v)
 except (ValueError,TypeError):return None
 return n if math.isfinite(n) else None

def stamp(v):
 n=num(v)
 if n is not None:return n
 if not isinstance(v,str):return None
 try:
  d=dt.datetime.fromisoformat(v.replace('Z','+00:00'))
  if d.tzinfo is None:d=d.replace(tzinfo=dt.timezone(dt.timedelta(hours=8)))
  return d.timestamp()
 except ValueError:return None

def reset_stamp(value,source):
 explicit=stamp(value)
 if explicit is not None:return explicit
 if not isinstance(value,str) or not re.fullmatch(r'\d\d-\d\d \d\d:\d\d',value) or source is None:return None
 local=dt.datetime.fromtimestamp(source,dt.timezone(dt.timedelta(hours=8)));candidates=[]
 for y in (local.year-1,local.year,local.year+1):
  try:candidates.append(dt.datetime.strptime(str(y)+'-'+value,'%Y-%m-%d %H:%M').replace(tzinfo=local.tzinfo).timestamp())
  except ValueError:pass
 return min(candidates,key=lambda x:abs(x-source)) if candidates else None

def quota_observations(raw,now,account_id='1'):
 def make(provider,account,window,kind,value,unit,t,reset=None,used=None):
  t=stamp(t);boundary=reset_stamp(reset,t)
  return Observation(account_id,f'{provider}:{account}:{window}',t if t is not None else now,kind,num(value),unit,window=window,cycle=str(boundary) if boundary is not None else 'unknown',valid=t is not None and num(value) is not None,fresh=t is not None and -30<=now-t<=5400,reset_boundary=boundary,current_used=num(used))
 collected=raw.get('collected_at');accounts=raw.get('accounts') or {}
 for provider,a in accounts.items():
  if not isinstance(a,dict) or provider in (raw.get('errors') or {}):continue
  t=a.get('collected_at',a.get('ts',collected));identity=str(a.get('account_id','default'))
  if provider in ('deepseek','tencent'):
   yield make(provider,identity,'balance','balance',a.get('amount'),a.get('currency','unknown'),t)
  elif provider=='cursor':
   for key in ('total_percent','auto_percent','api_percent'):
    used=num(a.get(key))
    if used is not None:yield make(provider,identity,key,'subscription',(100-used)/100,'ratio',t,a.get('cycle_end'),used)
  else:
   for window,q in a.items():
    if isinstance(q,dict) and 'percent' in q:
     used=num(q.get('percent'))
     yield make(provider,identity,window,'subscription',(100-used)/100 if used is not None else None,'ratio',t,q.get('reset_at',q.get('reset')),used)
 for provider,group in (raw.get('push') or {}).items():
  if not isinstance(group,dict):continue
  if provider=='gha':
   for account in ('personal','org'):
    q=group.get(account) or {};left=num(q.get('left'));limit=num(q.get('included'))
    if left is not None and limit is not None and limit>0:yield make(provider,account,'billing','subscription',left/limit,'ratio',group.get('updated'))
  for a in group.get('accounts') or []:
   direct=accounts.get(provider) or {}
   if provider=='cursor' and a.get('account_id') is not None and a.get('account_id')==direct.get('account_id'):continue
   t=a.get('ts',group.get('updated_at'));account=str(a.get('account_id',a.get('n','default')))
   if isinstance(a.get('bal'),dict):
    q=a['bal'];yield make(provider,account,'balance','balance',q.get('amt'),q.get('cur','unknown'),t)
   if isinstance(a.get('quota'),dict):
    q=a['quota'];left=num(q.get('remaining'));limit=num(q.get('limit'))
    yield make(provider,account,'subscription','subscription',left/limit if left is not None and limit is not None and limit>0 else None,'ratio',t,q.get('reset_at'),q.get('used'))
   for window in ('fh','sd'):
    q=a.get(window)
    if isinstance(q,dict):
     used=num(q.get('u'));yield make(provider,account,window,'subscription',(100-used)/100 if used is not None else None,'ratio',t,q.get('reset_at'),used)
   if provider=='cursor':
    for key,used in re.findall(r'(total|auto|api)PercentUsed=([0-9.]+)% used',str(a.get('rem',''))):
     u=num(used);yield make(provider,account,key,'subscription',(100-u)/100,'ratio',t)

def server_observations(snapshot,now,account_id='1'):
 for server in snapshot.get('servers') or []:
  identity=str(server.get('id',''));t=stamp(server.get('sampled_at'))
  if not identity:continue
  valid=t is not None and not server.get('error');fresh=t is not None and -30<=now-t<=90
  yield Observation(account_id,f'server:{identity}:availability',t if valid else now,'server',0 if valid else None,'percent',valid=valid,fresh=fresh if valid else True)
  if not valid:
   # Interrupt confirmations without multiplying host-unreachable events.
   for key in ('cpu_percent','memory_percent','disk_percent'):
    yield Observation(account_id,f'server:{identity}:{key}',now,'server',None,'percent',valid=False,fresh=False)
  if valid:
   for key in ('cpu_percent','memory_percent','disk_percent'):
    value=num((server.get('metrics') or {}).get(key))
    yield Observation(account_id,f'server:{identity}:{key}',t,'server',value,'percent',valid=value is not None,fresh=fresh)
