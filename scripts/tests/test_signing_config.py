import datetime as dt
import hashlib
import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('signing_under_test', Path(__file__).resolve().parents[1] / 'prepare_testflight_signing.py')
signing = importlib.util.module_from_spec(SPEC)
with patch.dict(os.environ, {'VIBEWATCH_TEAM_ID':'ABCDE12345', 'VIBEWATCH_BUNDLE_PREFIX':'com.example.quota',
                             'VIBEWATCH_APP_GROUP':'group.com.example.quota.shared'}):
    SPEC.loader.exec_module(signing)


class SigningConfigTests(unittest.TestCase):
    def profile(self, bundle):
        return {
            'ExpirationDate': dt.datetime.now(dt.timezone.utc).replace(tzinfo=None) + dt.timedelta(days=1),
            'TeamIdentifier': [signing.TEAM], 'DeveloperCertificates': [b'synthetic-test-certificate'],
            'Entitlements': {'application-identifier': f'{signing.TEAM}.{bundle}',
                             'keychain-access-groups': [f'{signing.TEAM}.*']},
        }

    def valid(self, payload, bundle):
        return signing.valid_profile(payload, bundle, hashlib.sha1(b'synthetic-test-certificate').hexdigest().upper())

    def test_custom_prefix_phone_uses_private_distribution_profile(self):
        bundle = 'com.example.quota.phone'
        self.assertEqual(signing.BUNDLES[0], bundle)
        self.assertTrue(self.valid(self.profile(bundle), bundle))

    def test_watch_requires_own_app_group(self):
        bundle = signing.BUNDLES[1]
        payload = self.profile(bundle)
        self.assertFalse(self.valid(payload, bundle))
        payload['Entitlements']['com.apple.security.application-groups'] = [signing.GROUP]
        self.assertTrue(self.valid(payload, bundle))

    def test_development_profile_is_rejected(self):
        bundle = signing.BUNDLES[0]
        payload = self.profile(bundle)
        payload['Entitlements']['get-task-allow'] = True
        self.assertFalse(self.valid(payload, bundle))
