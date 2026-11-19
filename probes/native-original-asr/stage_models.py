"""Explicit offline preparation helper, never called by the application."""
import argparse, hashlib, json, pathlib, urllib.request, urllib.parse
ROOT=pathlib.Path(__file__).resolve().parent
LOCK_SHA='f58c59e24e41e17f701d7b2b7fc4aa45343c232a2119fb6540357f676a6416ce'
BUDGET=631653214

def load_lock(path=ROOT/'resource-lock.json'):
    raw=pathlib.Path(path).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=LOCK_SHA: raise ValueError('Unreviewed resource lock')
    lock=json.loads(raw)
    remote=[v for v in lock['files'].values() if 'sourcePath' in v]
    if len(remote)!=16 or sum(v['size'] for v in remote)!=BUDGET: raise ValueError('Wrong download boundary')
    return lock

def copy_verified(source, destination, expected):
    digest=hashlib.sha256(); count=0
    with destination.open('xb') as out:
        while True:
            block=source.read(min(1048576,expected['size']-count+1))
            if not block: break
            count+=len(block)
            if count>expected['size']: raise ValueError('Oversized resource')
            digest.update(block);out.write(block)
    if count!=expected['size'] or digest.hexdigest()!=expected['sha256']: raise ValueError('Resource integrity mismatch')

class TrustedRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        u=urllib.parse.urlsplit(newurl); h=u.hostname or ''
        if u.scheme!='https' or not (h=='huggingface.co' or h.endswith('.huggingface.co') or h.endswith('.hf.co')):
            raise ValueError('Unexpected resource redirect')
        return super().redirect_request(req,fp,code,msg,headers,newurl)

def stage(destination):
    lock=load_lock();destination=pathlib.Path(destination)
    # Exclusive directory prevents reusing incomplete or stale packages; failed directories remain diagnostic only.
    destination.mkdir(parents=False,exist_ok=False)
    opener=urllib.request.build_opener(TrustedRedirects())
    for name,item in sorted(lock['files'].items()):
        target=destination/name;target.parent.mkdir(parents=True,exist_ok=True)
        if 'sourcePath' in item:
            url=f"https://huggingface.co/{lock['repository']}/resolve/{lock['revision']}/{item['sourcePath']}"
            request=urllib.request.Request(url,headers={'Accept-Encoding':'identity'})
            with opener.open(request,timeout=90) as source:
                if source.status!=200 or source.headers.get('Content-Range') or source.headers.get('Content-Encoding','identity')!='identity':
                    raise ValueError('Partial or encoded response refused')
                length=source.headers.get('Content-Length')
                if length is not None and int(length)!=item['size']: raise ValueError('Wrong advertised size')
                copy_verified(source,target,item)
        else:
            with (ROOT/item['localSource']).open('rb') as source: copy_verified(source,target,item)
        print(name,item['size'],item['sha256'],flush=True)
    # Completion marker written only after every original byte passed.
    with (destination/'resource-lock.json').open('xb') as out: out.write((ROOT/'resource-lock.json').read_bytes())

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--validate-only',action='store_true');parser.add_argument('--destination',type=pathlib.Path)
    args=parser.parse_args();load_lock()
    if args.validate_only: print(f'Validated immutable lock: 16 remote files, {BUDGET} bytes; no downloads')
    elif args.destination: stage(args.destination)
    else: parser.error('Explicit --destination or --validate-only required')
