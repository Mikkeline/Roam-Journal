#!/usr/bin/env python3
"""Local release preflight; --distribution deliberately fails without real published URLs."""
import json, plistlib, sys
from pathlib import Path
from urllib.parse import urlparse
app = Path(sys.argv[1]); distribution = '--distribution' in sys.argv[2:]
info = plistlib.loads((app/'Info.plist').read_bytes())
manifest = plistlib.loads((app/'PrivacyInfo.xcprivacy').read_bytes())
assert manifest.get('NSPrivacyTracking') is False
assert manifest.get('NSPrivacyTrackingDomains') == []
assert manifest.get('NSPrivacyCollectedDataTypes') == []
reasons = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons'] for entry in manifest['NSPrivacyAccessedAPITypes']}
assert 'CA92.1' in reasons['NSPrivacyAccessedAPICategoryUserDefaults']
assert 'C617.1' in reasons['NSPrivacyAccessedAPICategoryFileTimestamp']
assert info.get('NSFaceIDUsageDescription')
assert info.get('NSLocationWhenInUseUsageDescription')
assert info.get('RoamCloudBuildEnabled') is False, 'Cloud release remains gated on two-device validation'
for name in ['AirportCatalog.json','AirlineCatalog.json','PrivacyPolicy.md','AirportData-LICENSE.txt','AirlineData-LICENSE.txt']:
    assert (app/name).is_file(), name
for name in ['AirportCatalog.json','AirlineCatalog.json']:
    assert isinstance(json.loads((app/name).read_text()), list)
if distribution:
    for key in ['RoamPrivacyPolicyURL','RoamSupportURL']:
        url = urlparse(info.get(key, ''))
        assert url.scheme == 'https' and url.netloc and 'example.' not in url.netloc, f'Publish and configure {key} before distribution'
print('Release preflight passed' + (' (distribution)' if distribution else ' (local; public URLs and device acceptance still required)'))
