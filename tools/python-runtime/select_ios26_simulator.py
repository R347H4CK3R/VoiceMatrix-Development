import json,sys

def select(data):
    for runtime, devices in sorted(data['devices'].items()):
        if not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-26-'):
            continue
        for device in devices:
            if device.get('isAvailable') is True and device.get('name','').startswith('iPhone'):
                return device['udid']
    raise ValueError('No available iPhone simulator on iOS26; refusing older runtime')
if __name__=='__main__':print(select(json.load(sys.stdin)))
