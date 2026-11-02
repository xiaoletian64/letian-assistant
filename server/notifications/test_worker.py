import tempfile,unittest
from pathlib import Path
from server.notifications.worker import process_observations
from server.notifications.rules import Observation
class WorkerTests(unittest.TestCase):
 def test_reset_requires_elapsed_old_boundary_and_drop_not_just_cycle_change(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'n.db'
   def o(t,cycle,used,boundary):return Observation('1','glm:weekly',t,'subscription',1-used/100,'ratio',cycle=cycle,current_used=used,reset_boundary=boundary)
   self.assertEqual(process_observations(p,[o(100,'200',80,200)]),[])
   r=process_observations(p,[o(201,'300',0,300)])
   self.assertEqual([e['type'] for e in r],['quota_reset'])
 def test_same_or_old_observation_does_not_replace_reset_baseline(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'n.db'
   def o(t,used,b):return Observation('1','x',t,'subscription',1-used/100,'ratio',cycle=str(b),current_used=used,reset_boundary=b)
   process_observations(p,[o(100,80,200)]);process_observations(p,[o(99,0,300)])
   self.assertEqual([e['type'] for e in process_observations(p,[o(201,0,300)])],['quota_reset'])
if __name__=='__main__':unittest.main()
