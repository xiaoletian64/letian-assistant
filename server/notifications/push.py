"""APNs alert sender, configured only from a private server file.

ASC signing keys are not APNs authorization. Require explicit APNs confirmation.
HTTP/2, TLS verification, fixed Apple hosts and generic lock-screen text only.
"""
import base64
import json
from pathlib import Path
import re
import time
import uuid

def _b64(raw):return base64.urlsafe_b64encode(raw).rstrip(b'=').decode()

class APNsSender:
 def __init__(self,config,client=None,jwt_factory=None):
  self.config=dict(config);self.client=client;self.jwt_factory=jwt_factory;self._jwt=None;self._jwt_time=0
 @property
 def configured(self):
  c=self.config
  return c.get('enabled') is True and c.get('apns_authorized') is True and c.get('environment') in ('production','sandbox') and all(isinstance(c.get(k),str) and c[k] for k in ('topic','team_id','key_id','key_file'))
 def token(self):
  if self.jwt_factory:return self.jwt_factory()
  now=int(time.time())
  if self._jwt and now-self._jwt_time<1800:return self._jwt
  from cryptography.hazmat.primitives import hashes,serialization
  from cryptography.hazmat.primitives.asymmetric import ec,utils
  p=Path(self.config['key_file'])
  if not p.is_absolute() or p.stat().st_mode & 0o077:raise ValueError('private_key_permissions')
  key=serialization.load_pem_private_key(p.read_bytes(),password=None)
  if not isinstance(key,ec.EllipticCurvePrivateKey) or not isinstance(key.curve,ec.SECP256R1):raise ValueError('invalid_apns_key')
  header=_b64(json.dumps({'alg':'ES256','kid':self.config['key_id']},separators=(',',':')).encode());claims=_b64(json.dumps({'iss':self.config['team_id'],'iat':now},separators=(',',':')).encode());message=header+'.'+claims
  r,s=utils.decode_dss_signature(key.sign(message.encode(),ec.ECDSA(hashes.SHA256())))
  self._jwt=message+'.'+_b64(r.to_bytes(32,'big')+s.to_bytes(32,'big'));self._jwt_time=now;return self._jwt
 def __call__(self,device,payload):
  if device.get('platform')!='ios' or not self.configured:return {'status':'not_configured'}
  token=device.get('token','')
  if not isinstance(token,str) or not re.fullmatch(r'[0-9a-fA-F]{64}',token):return {'status':'invalid_token'}
  if self.client is None:
   import httpx
   self.client=httpx.Client(http2=True,timeout=15,follow_redirects=False,trust_env=False)
  host='api.push.apple.com' if self.config['environment']=='production' else 'api.sandbox.push.apple.com'
  event=str(payload.get('event_id',''));headers={'authorization':'bearer '+self.token(),'apns-topic':self.config['topic'],'apns-push-type':'alert','apns-priority':'10','apns-expiration':str(int(time.time())+300),'apns-id':str(uuid.uuid5(uuid.NAMESPACE_URL,event+token)),'apns-collapse-id':event[:64] or 'state-update'}
  try:r=self.client.post('https://'+host+'/3/device/'+token,json=payload,headers=headers)
  except Exception:return {'status':'unknown'}
  if r.status_code==200:return {'status':'accepted'}
  try:reason=r.json().get('reason','')
  except Exception:reason=''
  if r.status_code==410 or r.status_code==400 and reason in ('BadDeviceToken','DeviceTokenNotForTopic'):return {'status':'invalid_token'}
  if r.status_code==429 or 500<=r.status_code<600:return {'status':'retry'}
  return {'status':'rejected'}
 def close(self):
  if self.client and hasattr(self.client,'close'):self.client.close()
