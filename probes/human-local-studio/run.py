import pathlib,json,subprocess,sys
root=pathlib.Path(sys.argv[1]);binary=sys.argv[2];commit=sys.argv[3]
sources=json.loads(pathlib.Path(__file__).with_name('sources.json').read_text());results=[]
for source in sources:
    case=root/source['id']
    cmd=['sandbox-exec','-p','(version 1)(allow default)(deny network*)',binary,'VoiceMatrix/Resources',str(root/'corpus'/(source['id']+'.wav')),'tests/fixtures/DiagnosticVoices',str(case/'isolated-work'),str(case/'pipeline-evidence.json'),commit,'audio',str(case/'transcript.txt')]
    with (case/'run.log').open('w') as log:
        try: code=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=1200).returncode
        except subprocess.TimeoutExpired:code=124
    results.append(dict(id=source['id'],exitCode=code,passed=code==0))
    print(json.dumps(results[-1]),flush=True)
    (root/'human-results.json').write_text(json.dumps(results,indent=2)+'\n')
assert all(row['passed'] for row in results), 'Human pipeline failures preserved; no quality thresholds changed'
