"""Fixed SSH-stdin gateway. No URLs, topics, message bodies or hosts from callers."""
import json
from pathlib import Path
import re
import sys
from .push import APNsSender

def respond(request,sender):
 if not isinstance(request,dict):return {'status':'rejected'}
 if request=={'op':'status'}:return {'ios':'configured' if sender and getattr(sender,'configured',False) else 'not_configured'}
 if set(request)!={'op','token','event_id'} or request.get('op')!='send':return {'status':'rejected'}
 token=request['token'];event=request['event_id']
 if not isinstance(token,str) or not re.fullmatch(r'[a-fA-F0-9]{64}',token) or not isinstance(event,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}',event):return {'status':'rejected'}
 if sender is None:return {'status':'not_configured'}
 payload={'aps':{'alert':{'title':'乐天助手状态提醒','body':'请打开乐天助手查看最新状态'},'sound':'default'},'event_id':event}
 try:return sender({'platform':'ios','token':token.lower()},payload)
 except Exception:return {'status':'unknown'}

def main():
 sender=None
 try:
  raw=sys.stdin.buffer.read(16385)
  if len(raw)>16384:raise ValueError()
  config_file=Path('/etc/letian-notifications/apns.json')
  if config_file.exists():
   if config_file.stat().st_mode & 0o077:raise ValueError()
   sender=APNsSender(json.loads(config_file.read_text()))
  result=respond(json.loads(raw),sender)
 except Exception:result={'status':'rejected'}
 finally:
  if sender:sender.close()
 print(json.dumps(result,separators=(',',':')))
if __name__=='__main__':main()
