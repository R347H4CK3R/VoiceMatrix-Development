"""Standalone CLI math/performance diagnostic, not ASR or product acceptance."""
import argparse,hashlib,json,pathlib,platform,re,subprocess,time
import numpy as np

PEAK=1e-5
RMS=1e-6

def metrics(expected,actual,count):
    if expected.shape!=actual.shape or expected.ndim!=2 or expected.shape[0]!=128 or not 2<=count<=expected.shape[1]:raise ValueError('Shape/count mismatch')
    if not np.isfinite(expected).all() or not np.isfinite(actual).all():raise ValueError('Nonfinite output')
    if np.any(actual[:,count:].view(np.uint32)!=0):raise ValueError('Invalid mask (positive zero required)')
    d=actual.astype(np.float64)-expected.astype(np.float64)
    return dict(peak=float(np.max(np.abs(d))),rms=float(np.sqrt(np.mean(d*d))),valid_rms=float(np.sqrt(np.mean(d[:,:count]**2))))

def read_checked(p,size,digest):
    if not p.is_file() or p.is_symlink() or p.stat().st_size!=size:raise ValueError('Fixture size/type mismatch')
    b=p.read_bytes()
    if hashlib.sha256(b).hexdigest()!=digest:raise ValueError('Fixture hash differs')
    return b

def validate_rows(rows):
    if not isinstance(rows,list) or len(rows)<38 or len(rows)>64 or len({r['name'] for r in rows})!=len(rows):raise ValueError('Expected unique bounded cases')
    base=[r for r in rows if not r['name'].startswith('native-synthetic-speech-')]
    speech=[r for r in rows if r['name'].startswith('native-synthetic-speech-')]
    if len(base)<36 or sum(r['samples']==240000 and r['validSamples']==240000 for r in speech)<2:raise ValueError('Require36base and2full15second synthesizedspeech windows')

def run(executable,fixtures,buffers,output):
    if platform.system()!='Darwin' or platform.machine()!='arm64':raise RuntimeError('Native macOS ARM64 required')
    manifest=(fixtures/'fixtures.json').read_bytes();rows=json.loads(manifest)
    validate_rows(rows)
    output.mkdir(mode=0o700,parents=True,exist_ok=False)
    report={'status':'INCOMPLETE','scope':'corrected frontend math and MacCLI resource observations only; NOT original FP32 parity or ASR','thresholds':{'peak':PEAK,'rms':RMS,'valid_rms':RMS},'fixture_manifest_sha256':hashlib.sha256(manifest).hexdigest(),'numpy':np.__version__,'platform':platform.platform(),'rss_units':'bytes as reported by Darwin /usr/bin/time -l','cases':[]}
    try:
        for row in rows:
            name=row['name'];n=row['samples'];frames=row['frames'];valid=row['validSamples'];count=row['validFrames']
            if not re.fullmatch(r'[A-Za-z0-9_-]+',name) or not(257<=n<=240000 and 160<=valid<=n and frames==n//160+1 and count==valid//160+1):raise ValueError('Invalid fixture contract')
            report['current_case']=name
            read_checked(fixtures/(name+'.audio.f32le'),n*4,row['audioSHA256'])
            expected=np.frombuffer(read_checked(fixtures/(name+'.mel.f32le'),128*frames*4,row['melSHA256']),dtype='<f4').reshape(128,frames)
            mel=output/(name+'.actual.f32le');meta=output/(name+'.metadata.json')
            cmd=['/usr/bin/time','-l',str(executable),'--input',str(fixtures/(name+'.audio.f32le')),'--valid',str(valid),'--window',str(buffers/'window.f32le'),'--filterbank',str(buffers/'filterbank.f32le'),'--output',str(mel),'--metadata',str(meta)]
            start=time.perf_counter();p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120,check=False);wall=time.perf_counter()-start
            stderr=p.stderr.decode('utf-8',errors='replace');(output/(name+'.resource.txt')).write_text(stderr)
            if p.returncode:raise RuntimeError(f'CLI returned {p.returncode} for {name}: '+stderr[-2000:])
            if json.loads(meta.read_text())!={'samples':n,'validSamples':valid,'frames':frames,'validFrames':count}:raise ValueError('CLI metadata mismatch')
            if mel.stat().st_size!=128*frames*4:raise ValueError('Wrong output bytes')
            actual=np.frombuffer(mel.read_bytes(),dtype='<f4').reshape(128,frames)
            values=metrics(expected,actual,count)
            rss=re.search(r'(\d+)\s+maximum resident set size',stderr)
            if rss is None:raise ValueError('Missing Darwin peakRSS evidence')
            report['cases'].append({'name':name,'samples':n,'valid_samples':valid,'wall_seconds':wall,'peak_rss_bytes':int(rss.group(1)),**values})
            mel.unlink() # own diagnostic output, metrics retained; no audio/model publication
        report['current_case']=None
        failed=[r['name'] for r in report['cases'] if r['peak']>PEAK or r['rms']>RMS or r['valid_rms']>RMS]
        if failed:raise AssertionError('Unchanged strict corrected-math limits failed: '+', '.join(failed))
        report['status']='DOUBLE_FRONTEND_MATH_PARITY_PASSED_NO_ASR_ACCEPTANCE'
    except Exception as e:
        report['status']='FAILED';report['error']=str(e);raise
    finally:(output/'report.json').write_text(json.dumps(report,indent=2,allow_nan=False))

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for key in ('executable','fixtures','buffers','output'):p.add_argument('--'+key,type=pathlib.Path,required=True)
    a=p.parse_args();run(a.executable.resolve(),a.fixtures.resolve(),a.buffers.resolve(),a.output.resolve())
