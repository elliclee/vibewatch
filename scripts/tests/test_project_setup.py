import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from configure_apple import render


class ProjectSetupTests(unittest.TestCase):
    def test_personal_configuration_keeps_companion_and_shared_groups_consistent(self):
        source = (ROOT / 'apple/project.yml').read_text()
        result = render(source, 'com.example.quota', 'ABCDE12345')
        self.assertIn('VIBEWATCH_BUNDLE_PREFIX: com.example.quota', result)
        self.assertIn('VIBEWATCH_APP_GROUP: group.com.example.quota.shared', result)
        self.assertIn('VIBEWATCH_KEYCHAIN_GROUP: $(AppIdentifierPrefix)com.example.quota.shared', result)
        self.assertIn('DEVELOPMENT_TEAM: ABCDE12345', result)
        self.assertIn('WKCompanionAppBundleIdentifier: $(VIBEWATCH_BUNDLE_PREFIX).phone', result)
        self.assertIn('VibeWatchPrivatePhoneStorage: true', result)
        self.assertNotIn('target: VibeWatchPhoneWidgets', result)

    def test_invalid_identifiers_cannot_inject_yaml(self):
        for prefix, team in [('example\nINJECT: true', 'ABCDE12345'),
                             ('com.example.app', 'bad-team'), ('single', 'ABCDE12345')]:
            with self.assertRaises(ValueError):
                render('', prefix, team)
