"""Exact-byte acquisition only. No checkpoint deserialization."""
import hashlib
import os
import pathlib
import urllib.request
import urllib.parse

REV='541d1f99c6b0c3cd0b11a95167540bb8edefd82b'
URL=f'https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/resolve/{REV}/parakeet-tdt-0.6b-v3.nemo'
SIZE=2509332480
SHA='3cbdc85877e668ca7b82d0d56770eb1fac76691f55d6b97545e8d61ca588d10d'

def verified_copy(response,path,size,digest):
    if response.status!=200 or response.headers.get('Content-Range'):
        raise ValueError('Full HTTP200 required')
    if response.headers.get('Content-Encoding','identity')!='identity':raise ValueError('Encoded response')
    length=response.headers.get('Content-Length')
    if length is not None and int(length)!=size:raise ValueError('Content length mismatch')
    path=pathlib.Path(path)
    # Exclusive creation, never delete or overwrite an existing destination.
    file=path.open('xb');good=False
    try:
        h=hashlib.sha256();count=0
        with file:
            while count<size:
                block=response.read(min(1024*1024,size-count))
                if not block:break
                if count+len(block)>size:raise ValueError('Overlong response')
                file.write(block);h.update(block);count+=len(block)
            if response.read(1):raise ValueError('Overlong response')
            if count!=size or h.hexdigest()!=digest:raise ValueError('Exact size/hash mismatch')
            file.flush();os.fsync(file.fileno())
        good=True
    finally:
        if not file.closed:file.close()
        if not good:path.unlink()

class TrustedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        p=urllib.parse.urlsplit(newurl)
        if p.scheme!='https' or p.hostname not in {'huggingface.co','cdn-lfs.huggingface.co','cdn-lfs-us-1.hf.co','cas-bridge.xethub.hf.co','us.aws.cdn.hf.co'}:
            raise ValueError('Unapproved download redirect')
        return super().redirect_request(req,fp,code,msg,headers,newurl)

if __name__=='__main__':
    import sys
    opener=urllib.request.build_opener(TrustedRedirect())
    with opener.open(urllib.request.Request(URL,headers={'Accept-Encoding':'identity'}),timeout=60) as response:
        verified_copy(response,sys.argv[1],SIZE,SHA)
    print('VERIFIED',SIZE,SHA,flush=True)
