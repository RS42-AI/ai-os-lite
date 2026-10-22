import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location("structure", Path(__file__).parents[1]/"tools/project_structure.py")
structure=importlib.util.module_from_spec(spec);spec.loader.exec_module(structure)

class ResourceRoots(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.v=Path(self.temp.name);self.area=self.v/"2. Projects/2. Studio";self.area.mkdir(parents=True)
    def test_preserves_existing_unprefixed(self):
        target=self.v/"5. Resources/Studio";target.mkdir(parents=True)
        self.assertEqual(structure.area_resource_root(self.v,self.area),target)
    def test_new_area_uses_unprefixed(self):
        self.assertEqual(structure.area_resource_root(self.v,self.area),self.v/"5. Resources/Studio")
    def test_explicit_alias_preserved(self):
        p=self.v/"system-settings";p.mkdir()
        (p/"workspace-layout.json").write_text(json.dumps({"schema_version":1,"area_resource_roots":{"2. Studio":"5. Resources/Creative Work"}}))
        self.assertEqual(structure.area_resource_root(self.v,self.area),self.v/"5. Resources/Creative Work")
    def test_duplicate_roots_require_mapping(self):
        for name in ["Studio","2. Studio"]:(self.v/"5. Resources"/name).mkdir(parents=True)
        with self.assertRaises(structure.StructureError):structure.area_resource_root(self.v,self.area)
    def test_alias_cannot_escape(self):
        p=self.v/"system-settings";p.mkdir()
        (p/"workspace-layout.json").write_text(json.dumps({"schema_version":1,"area_resource_roots":{"2. Studio":"5. Resources/../../outside"}}))
        with self.assertRaises(structure.StructureError):structure.area_resource_root(self.v,self.area)
    def test_symlink_refused(self):
        p=self.v/"5. Resources";p.mkdir();(p/"Studio").symlink_to(self.v,target_is_directory=True)
        with self.assertRaises(structure.StructureError):structure.area_resource_root(self.v,self.area)

if __name__ == "__main__":unittest.main()
