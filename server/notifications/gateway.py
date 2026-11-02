"""Private fixed-command SSH transport; device tokens travel on encrypted stdin."""
import json
from pathlib import Path
import re
import subprocess

CONFIG=Path('/etc/letian-notifications/gateway.json')
COMMAND='cd /opt/letian-notifications && /usr/bin/python3 -m server.notifications.send_rpc'
def configuration():
 if not CONFIG.exists():return {}
 if CONFIG.stat().st_mode & 0o077:raise ValueError('private_gateway_permissions')
 value=json.loads(CONFIG.read_text())
 if not isinstance(value,dict) or set(value)-{'enabled','ssh_alias','apns_ready'}:raise ValueError('invalid_gateway')
 return value

def push_status():
 try:c=configuration()
 except Exception:c={}
 return {'ios':'configured' if c.get('enabled') is True and c.get('apns_ready') is True else 'not_configured','android':'client_monitor'}

class GatewaySender:
 def __init__(self,config):
  self.config=config
  if config.get('enabled') is True and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}',str(config.get('ssh_alias',''))):raise ValueError('invalid_gateway_alias')
 def __call__(self,device,payload):
  if self.config.get('enabled') is not True or device.get('platform')!='ios':return {'status':'not_configured'}
  data=json.dumps({'op':'send','token':device.get('token'),'event_id':payload.get('event_id')}).encode()
  if len(data)>16384:return {'status':'rejected'}
  try:
   r=subprocess.run(['ssh','-oBatchMode=yes','-oConnectTimeout=5',self.config['ssh_alias'],COMMAND],input=data,capture_output=True,timeout=25,check=True)
   if len(r.stdout)>4096:return {'status':'unknown'}
   value=json.loads(r.stdout)
   if value.get('status') not in ('accepted','not_configured','invalid_token','retry','rejected','unknown'):return {'status':'unknown'}
   return {'status':value['status']}
  except Exception:return {'status':'unknown'}
