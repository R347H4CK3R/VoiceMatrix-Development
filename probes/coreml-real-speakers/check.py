import json,sys
analysis=json.load(open(sys.argv[1]));fixture=json.load(open(sys.argv[2]));mapping={}
for group in analysis['speakerWindows']:
    labels=set()
    for window in group['windows']:
        matches=[t['speaker'] for t in fixture['truth'] if window['start']>=t['start'] and window['end']<=t['end']]
        assert len(matches)==1,'Candidate crosses known speaker boundary'
        labels.add(matches[0])
    if labels:mapping[group['speaker']]=sorted(labels)
print(json.dumps(dict(groupSourceMapping=mapping,physicalIPhoneVerified=False)))
assert sorted(mapping.values())==[['A'],['B']],'Expected two separate recovered source speakers'
