#!/usr/bin/env python3
"""Boot an available iPhone from the selected Xcode's SDK runtime."""
import json
import os
import subprocess
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True, timeout=30).strip()


sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
runtime_prefix = 'com.apple.CoreSimulator.SimRuntime.iOS-' + sdk.replace('.', '-')
devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
candidates = [device for runtime, items in devices.items()
              if runtime == runtime_prefix or runtime.startswith(runtime_prefix + '-')
              for device in items if device['name'].startswith('iPhone')]
if not candidates:
    raise SystemExit(f'No available iPhone simulator for selected iOS SDK {sdk}')
device = next((d for d in candidates if d['state'] == 'Booted'), candidates[0])
udid = device['udid']
print(f"Booting {device['name']} ({udid}), iOS {sdk}", flush=True)
if device['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', udid], check=True, timeout=120)
subprocess.run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True, timeout=480)
if os.environ.get('GITHUB_ENV'):
    with Path(os.environ['GITHUB_ENV']).open('a') as env_file:
        env_file.write(f'ROAM_SIMULATOR_ID={udid}\n')
print(f'ROAM_SIMULATOR_ID={udid}', flush=True)
