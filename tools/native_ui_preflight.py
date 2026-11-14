"""Read-only runner admission before downloading models or creating simulators."""
import json, platform, shutil, subprocess, sys
from pathlib import Path

def check():
    report = {'ready': False, 'scope': 'native simulator UI only; no inference or device claim',
              'system': platform.system(), 'machine': platform.machine()}
    if report['system'] != 'Darwin' or report['machine'] != 'arm64':
        raise RuntimeError('An Apple Silicon macOS executor is required')
    if sys.version_info < (3, 12):
        raise RuntimeError('Python 3.12 or newer is required')
    for tool in ('xcodebuild', 'xcrun', 'python3', 'brew'):
        if not shutil.which(tool):
            raise RuntimeError('Required tool missing: ' + tool)
    version = subprocess.check_output(['xcodebuild', '-version'], text=True, timeout=30)
    report['xcode'] = version.strip()
    if not version.startswith('Xcode ') or int(version.split()[1].split('.')[0]) < 26:
        raise RuntimeError('Xcode 26 or newer is required')
    raw = subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j'], text=True, timeout=60)
    runtimes = json.loads(raw)['runtimes']
    available = [r['identifier'] for r in runtimes if r.get('isAvailable') and
                 'iOS' in r.get('name', '') and str(r.get('version', '')).startswith('26.')]
    if not available:
        raise RuntimeError('An installed iOS 26 simulator runtime is required; none will be downloaded automatically')
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j'], text=True, timeout=30))
    if not any(d.get('identifier') == 'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus' for d in devices['devicetypes']):
        raise RuntimeError('The iPhone 16 Plus simulator device type is unavailable')
    free = shutil.disk_usage('.').free
    if free < 15_000_000_000:
        raise RuntimeError('At least 15 GB free is required for dependencies, model fixture and build products')
    report.update(ready=True, simulatorRuntimes=available, freeBytes=free)
    return report

def main():
    try:
        report = check(); code = 0
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        report = {'ready': False, 'error': str(error), 'scope': 'runner admission only'}; code = 2
    print(json.dumps(report, indent=2))
    return code

if __name__ == '__main__':
    sys.exit(main())
