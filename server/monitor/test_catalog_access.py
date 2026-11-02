import unittest
from catalog_access import filter_owner_entries

class CatalogAccessTests(unittest.TestCase):
    def test_only_owner_sees_monitor_and_other_entries_are_identical(self):
        public={'id':'example','renderer':'content','extra':{'unchanged':True}}
        monitor={'id':'server-monitor','renderer':'server-monitor'}
        rows=[public,monitor]
        for identity in (None,5,'1'):
            result=filter_owner_entries(rows,identity)
            self.assertEqual(result,[public])
            self.assertIs(result[0],public)
        self.assertEqual(filter_owner_entries(rows,1),rows)
        self.assertEqual(rows,[public,monitor])
