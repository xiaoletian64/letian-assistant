"""Host adapter; call only after the existing account access gate."""
import os
from .service import NotificationService
from .gateway import push_status

def handle(handler,connection,service=None):
 user,_=handler._auth(connection)
 owner=user['user_id'] if user else None
 if owner is None:return handler._json(401,{'error':'authentication_required'})
 if type(owner) is not int or owner!=1:return handler._json(403,{'error':'notifications_owner_only'})
 if '?' in handler.path:return handler._json(400,{'error':'notification_query_not_supported'})
 allowed={('GET','/api/hub/notifications'),('POST','/api/hub/notifications/settings'),('POST','/api/hub/notifications/read'),('POST','/api/hub/notifications/devices'),('DELETE','/api/hub/notifications/devices')}
 if (handler.command,handler.path) not in allowed:return handler._json(404,{'error':'notification_route_not_found'})
 body={}
 if handler.command in ('POST','DELETE'):
  try:body=handler._body(max_size=16384)
  except Exception:return handler._json(400,{'error':'invalid_body'})
 try:
  if service is None:service=NotificationService(os.environ.get('LETIAN_NOTIFICATIONS_DB','/var/lib/letian-notifications/notifications.sqlite3'),push_status=push_status())
  code,result=service.handle(handler.command,handler.path,owner,body)
  return handler._json(code,result)
 except Exception:return handler._json(503,{'error':'notifications_unavailable'})
