"""Owner-only bounded history bridge. Hosts and commands never come from users."""
import json
import math
import re
import subprocess
import tempfile
import urllib.parse

RPC_COMMAND = 'cd /opt/quota-history && /usr/bin/python3 -m server.quota_history.rpc'
MAX_OUTPUT = 2 * 1024 * 1024

def parse_query(query):
    if len(query.encode()) > 4096: raise ValueError('query too large')
    pairs = urllib.parse.parse_qsl(query, keep_blank_values=True, strict_parsing=True, max_num_fields=6)
    params = {}
    for key,value in pairs:
        if key in params or key not in {'provider','window','from','to','cursor','limit'}: raise ValueError('invalid parameter')
        if key in {'provider','window'}:
            if not value or len(value)>128 or any(ord(c)<32 or ord(c)==127 for c in value): raise ValueError('invalid filter')
            params[key]=value
        elif key in {'cursor','limit'}:
            if not re.fullmatch(r'[0-9]{1,18}',value): raise ValueError('invalid integer')
            params[key]=int(value)
            if params[key]<1 or key=='limit' and params[key]>200: raise ValueError('invalid range')
        else:
            number=float(value)
            if not math.isfinite(number) or number<0:raise ValueError('invalid timestamp')
            params[key]=number
    if 'from' in params and 'to' in params and params['from']>params['to']: raise ValueError('invalid interval')
    return params

def invoke_rpc(params):
    payload=json.dumps(params,allow_nan=False).encode()
    if len(payload)>4096:raise ValueError('query too large')
    # Capture bounded-duration output to private temporary storage, never logs.
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        result=subprocess.run(['ssh','-oBatchMode=yes','-oConnectTimeout=3','monitor-primary',RPC_COMMAND],input=payload,stdout=output,stderr=errors,timeout=12,check=False)
        if result.returncode!=0:raise RuntimeError('history_unavailable')
        size=output.tell()
        if size>MAX_OUTPUT:raise RuntimeError('history_output_too_large')
        output.seek(0)
        data=json.load(output)
    if not isinstance(data,dict) or not isinstance(data.get('items'),list) or len(data['items'])>params.get('limit',100):raise RuntimeError('invalid_history_response')
    cursor=data.get('next_cursor')
    if cursor is not None and (type(cursor) is not int or cursor<1):raise RuntimeError('invalid_history_cursor')
    return data

def handle(handler, connection, rpc=invoke_rpc):
    user,_=handler._auth(connection)
    if user is None:return handler._json(401,{'error':'authentication_required'})
    if user['user_id']!=1:return handler._json(403,{'error':'forbidden'})
    try:params=parse_query(urllib.parse.urlsplit(handler.path).query)
    except (ValueError,TypeError):return handler._json(400,{'error':'invalid_history_query'})
    try:return handler._json(200,rpc(params))
    except Exception:return handler._json(503,{'error':'history_unavailable'})
