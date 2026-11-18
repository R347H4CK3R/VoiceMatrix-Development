"""Read-only exact separation-resource inspection of an already-built IPA.

The helper lives on the packaging harness, separate from the immutable app source.
No source, package, model or IPA bytes are modified.
"""
import argparse,hashlib,importlib.util,json,pathlib,stat,subprocess,zipfile

TARGET_SOURCE='2daf7bc843edc2a11cfa44eaa85cdd1d83923fe3'

def inspect_resources(ipa,models,provenance,notices):
    ipa=pathlib.Path(ipa)
    prefix='Payload/VoiceMatrix.app/Separation/'
    expected=set(models)|set(notices)|{'manifest.json'}
    with zipfile.ZipFile(ipa) as bundle:
        members=bundle.infolist()
        if len(members)>100000:raise ValueError('Too many IPA members')
        names=[m.filename for m in members]
        if len(names)!=len(set(n.casefold() for n in names)):raise ValueError('Duplicate/case-colliding IPA members')
        selected=[m for m in members if m.filename.startswith(prefix)]
        files={}
        for member in selected:
            if member.orig_filename!=member.filename:raise ValueError('Normalized resource path')
            name=member.filename[len(prefix):]
            mode=stat.S_IFMT(member.external_attr>>16)
            if member.flag_bits&1 or mode not in (0,stat.S_IFREG,stat.S_IFDIR):raise ValueError('Unsafe resource type')
            if member.is_dir():
                if name!='':raise ValueError('Unexpected resource directory')
                continue
            if mode==stat.S_IFDIR or name not in expected:raise ValueError('Unexpected resource file')
            files[name]=member
        if set(files)!=expected:raise ValueError('Missing separation models or licenses')
        evidence={}
        for name,(size,sha) in models.items():
            member=files[name]
            if member.file_size!=size:raise ValueError('Model size mismatch')
            digest=hashlib.sha256();count=0
            with bundle.open(member) as stream:
                while block:=stream.read(1024*1024):
                    count+=len(block)
                    if count>size:raise ValueError('Model size overflow')
                    digest.update(block)
            if count!=size or digest.hexdigest()!=sha:raise ValueError('Model hash mismatch')
            evidence[name]={'bytes':count,'sha256':sha}
        for name in [*notices,'manifest.json']:
            if files[name].file_size>65536:raise ValueError('Oversized separation receipt')
            data=bundle.read(files[name])
            if name=='manifest.json':
                if json.loads(data)!=provenance:raise ValueError('Model provenance mismatch')
            elif data!=notices[name].encode():raise ValueError('Model license/notice mismatch')
            evidence[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    return {'passed':True,'ipa':ipa.name,'resources':evidence,'sampleRate':44100,'maximumSeconds':10,
            'physicalDeviceVerified':False,'scope':'Exact pinned neural model bytes, manifest and licenses in original IPA; not a device or music-quality claim'}

def inspect_pinned(ipa,target):
    target=pathlib.Path(target).resolve()
    actual=subprocess.check_output(['git','-C',str(target),'rev-parse','HEAD'],text=True).strip()
    if actual!=TARGET_SOURCE:raise ValueError('Incorrect immutable app source')
    spec=importlib.util.spec_from_file_location('pinned_separation_preparation',target/'tools/prepare_vocal_separation.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    result=inspect_resources(ipa,module.MODELS,module.PROVENANCE,module.pack_notices())
    result['sourceCommit']=actual
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('ipa',type=pathlib.Path);p.add_argument('--target',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True)
    a=p.parse_args();a.output.write_text(json.dumps(inspect_pinned(a.ipa,a.target),indent=2)+'\n')
