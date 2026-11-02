import unittest,json
from unittest.mock import patch
from types import SimpleNamespace
from server.notifications.gateway import GatewaySender
class GatewayTests(unittest.TestCase):
 def test_configured_alias_only_and_no_token_in_argv(self):
  with patch('subprocess.run',return_value=SimpleNamespace(returncode=0,stdout=b'{"status":"accepted"}')) as run:
   result=GatewaySender({'enabled':True,'ssh_alias':'fixture-push'})({'platform':'ios','token':'a'*64},{'event_id':'event'})
   self.assertEqual(result['status'],'accepted');self.assertNotIn('a'*64,str(run.call_args.args));self.assertIn('a'*64,run.call_args.kwargs['input'].decode())
 def test_unconfigured_no_network(self):
  with patch('subprocess.run') as run:self.assertEqual(GatewaySender({})({'platform':'ios'},{})['status'],'not_configured');run.assert_not_called()
 def test_shell_alias_is_rejected(self):
  with self.assertRaises(ValueError):GatewaySender({'enabled':True,'ssh_alias':'x;evil'})
if __name__=='__main__':unittest.main()
