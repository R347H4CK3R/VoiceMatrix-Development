"""Broad source discovery must use the same declared dependencies as platform CI."""
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]

class SourceWorkflowDependenciesTests(unittest.TestCase):
    def test_supported_python_and_declared_dependencies_precede_discovery(self):
        steps = yaml.safe_load((ROOT / '.github/workflows/ios.yml').read_text())['jobs']['source']['steps']
        discovery = next(i for i, s in enumerate(steps) if 'unittest discover' in s.get('run', ''))
        setup = next((i for i, s in enumerate(steps) if s.get('uses', '').startswith('actions/setup-python@')), None)
        self.assertIsNotNone(setup, 'Source suite must not inherit runner-default Python')
        self.assertEqual(steps[setup]['with']['python-version'], '3.12')
        install = next((i for i, s in enumerate(steps) if 'python3 -m pip install -r tests/requirements-native.txt' in s.get('run', '')), None)
        self.assertIsNotNone(install, 'Source suite needs all declared mandatory imports')
        self.assertLess(setup, install)
        self.assertLess(install, discovery)
        requirements = (ROOT / 'tests/requirements-native.txt').read_text()
        self.assertIn('numpy==2.3.5', requirements)
        self.assertIn('PyYAML==6.0.3', requirements)

if __name__ == '__main__':
    unittest.main()
