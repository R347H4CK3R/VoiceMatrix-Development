"""Extract ONLY two independently reviewed raw buffers from one exact original.
No pickle loading or opcode execution. data.pkl is compared as inert hash-bound bytes.
"""
import hashlib,json,pathlib,tarfile,zipfile
import numpy as np
from acquire import SIZE,SHA
META_SHA='360fd24a883d1328e7fb946a2b772b2379d389377f6c47f3ae6d510a05952cd6'
BUFFERS=[('window','0',1600,(400,),'744788a137aa808ccc97d9d3c185c649b2e9c2b99c3262887c3ac9bb3b7e1c4c'),('filterbank','1',131584,(1,128,257),'f5608e00763a20a191022fbb00a43346db5f1ec06828a97a6f4157f7d02b76c8')]

def read_exact_entry(z,name,size):
    matches=[x for x in z.infolist() if x.filename==name]
    if len(matches)!=1:raise ValueError('Missing or duplicate ZIP member')
    i=matches[0]
    if i.file_size!=size or i.compress_size!=size or i.compress_type!=zipfile.ZIP_STORED or i.flag_bits&1:
        raise ValueError('ZIP member type/size differs')
    with z.open(i) as f:b=f.read(size+1)
    if len(b)!=size:raise ValueError('Wrong entry length')
    return b

def extract(source,destination):
    source=pathlib.Path(source);dest=pathlib.Path(destination)
    with source.open('rb') as f:
        if source.stat().st_size!=SIZE:raise ValueError('Original size differs')
        h=hashlib.sha256()
        while b:=f.read(1024*1024):h.update(b)
        if h.hexdigest()!=SHA:raise ValueError('Original hash differs')
        f.seek(0)
        with tarfile.open(fileobj=f,mode='r:') as t:
            members=t.getmembers()
            if len(members)!=6:raise ValueError('Archive inventory differs')
            ms=[m for m in members if m.name=='./model_weights.ckpt']
            if len(ms)!=1:raise ValueError('Checkpoint member differs')
            m=ms[0]
            if m.type!=tarfile.REGTYPE or m.sparse is not None or m.size!=2508649346 or m.offset_data!=680448:
                raise ValueError('Checkpoint layout differs')
            with zipfile.ZipFile(t.extractfile(m)) as z:
                names=z.namelist()
                if len(names)!=722 or len(set(names))!=722:raise ValueError('ZIP inventory differs')
                meta=read_exact_entry(z,'model_weights/data.pkl',145537)
                if hashlib.sha256(meta).hexdigest()!=META_SHA:raise ValueError('Metadata differs')
                if read_exact_entry(z,'model_weights/byteorder',6)!=b'little':raise ValueError('Byteorder differs')
                result=[]
                for name,key,size,shape,digest in BUFFERS:
                    b=read_exact_entry(z,'model_weights/data/'+key,size)
                    if hashlib.sha256(b).hexdigest()!=digest:raise ValueError('Buffer hash differs')
                    array=np.frombuffer(b,dtype='<f4').reshape(shape)
                    if not np.isfinite(array).all():raise ValueError('Nonfinite buffer')
                    if name=='filterbank' and (array<0).any():raise ValueError('Negative filterbank')
                    result.append((name,b,shape,digest))
    # New output directory only, after verification; never clobber.
    dest.mkdir(mode=0o700)
    manifest={'original_sha256':SHA,'original_bytes':SIZE,'metadata_sha256':META_SHA,'buffers':[],'native_parity':'NOT RUN'}
    for name,b,shape,digest in result:
        with (dest/(name+'.f32le')).open('xb') as out:out.write(b)
        manifest['buffers'].append({'name':name,'shape':shape,'dtype':'<f4','bytes':len(b),'sha256':digest})
    with (dest/'provenance.json').open('x') as out:json.dump(manifest,out,indent=2)
    return manifest

if __name__=='__main__':
    import sys
    print(json.dumps(extract(sys.argv[1],sys.argv[2]),indent=2))
