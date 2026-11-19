"""Native diagnostic export and fixed-threshold parity; never app/release publishing."""
import argparse,json,platform,pathlib,subprocess,sys,hashlib
import numpy as np
from native_reference import build_reference,verified_buffers,SOURCE_SHA
from oracle import features

ABS_MAX=1e-3
RMS_MAX=1e-4

def measure(expected,actual):
    if expected.shape!=actual.shape or not np.isfinite(actual).all():raise AssertionError('Shape/finite mismatch')
    delta=actual.astype(np.float64)-expected.astype(np.float64)
    result={'max_abs':float(np.max(np.abs(delta))),'rms':float(np.sqrt(np.mean(delta**2)))}
    return result

def compare(expected,actual):
    result=measure(expected,actual)
    if result['max_abs']>ABS_MAX or result['rms']>RMS_MAX:raise AssertionError('Fixed parity limit exceeded: '+str(result))
    return result

def cases():
    for n in (257,319,320,399,400,511,512,15999,16000,239999,240000):
        x=(.1*np.sin(2*np.pi*440*np.arange(n,dtype=np.float64)/16000)).astype(np.float32)
        yield f'tone-{n}',x,n
    for n in (400,16000,240000):
        yield f'silence-{n}',np.zeros(n,dtype=np.float32),n
        x=np.zeros(n,dtype=np.float32);x[0]=.5;x[-1]=-.5
        yield f'edge-impulses-{n}',x,n
    for valid in (160,319,16000,239999):
        x=np.zeros(240000,dtype=np.float32);x[:valid]=.1*np.sin(2*np.pi*440*np.arange(valid)/16000)
        yield f'padded-valid-{valid}',x,valid

def run(out):
    if platform.system()!='Darwin' or platform.machine()!='arm64':raise RuntimeError('macOS ARM64 required')
    import torch,coremltools as ct
    if ct.__version__!='9.0':raise RuntimeError('Unapproved coremltools')
    torch.set_num_threads(1)
    ref=build_reference();window,fb=verified_buffers()
    class Wrapper(torch.nn.Module):
        def __init__(self):super().__init__();self.model=ref
        def forward(self,a,n):
            mel,length=self.model(a,n.long())
            return mel,length.to(torch.int32)
    wrapper=Wrapper().eval()
    report={'status':'INCOMPLETE','source_sha256':SOURCE_SHA,'precision':'FLOAT32','compute_units':'CPU_ONLY','thresholds':{'max_abs':ABS_MAX,'rms':RMS_MAX},'python':sys.version,'platform':platform.platform(),'torch':torch.__version__,'numpy':np.__version__,'coremltools':ct.__version__,'scope':'valid-domain frontend parity only, NOT production ASR or whole RangeDim acceptance','cases':[]}
    out.mkdir(parents=True,exist_ok=False)
    try:
        # Trace on full15sec to preserve original export procedure; tests include other shapes.
        trace_audio=torch.from_numpy((.1*np.sin(2*np.pi*440*np.arange(240000)/16000)).astype(np.float32)).reshape(1,-1)
        traced=torch.jit.trace(wrapper,(trace_audio,torch.tensor([240000],dtype=torch.int32)),strict=False).eval()
        model=ct.convert(traced,convert_to='mlprogram',minimum_deployment_target=ct.target.iOS17,compute_precision=ct.precision.FLOAT32,compute_units=ct.ComputeUnit.CPU_ONLY,inputs=[ct.TensorType(name='audio_signal',shape=(1,ct.RangeDim(1,240000,default=240000)),dtype=np.float32),ct.TensorType(name='audio_length',shape=(1,),dtype=np.int32)],outputs=[ct.TensorType(name='mel',dtype=np.float32),ct.TensorType(name='mel_length',dtype=np.int32)])
        model.author='NVIDIA; independent NeMo2.3.1 frontend export'
        model.license='CC-BY-4.0 original model buffers; Apache-2.0 and retained upstream notices for conversion code'
        model.short_description='Original pinned NVIDIA Parakeet frontend; standalone regenerated CoreML, not FluidInference converted preprocessor'
        model.user_defined_metadata['original_model_revision']='541d1f99c6b0c3cd0b11a95167540bb8edefd82b'
        model.user_defined_metadata['original_checkpoint_sha256']='3cbdc85877e668ca7b82d0d56770eb1fac76691f55d6b97545e8d61ca588d10d'
        model.user_defined_metadata['frontend_source_revision']='abddc854389e9efcaf38c605ef66af675fc5f8f7'
        model.user_defined_metadata['scope']='independent original-buffer export; valid-domain parity only; production ASR not qualified'
        model.save(str(out/'Preprocessor.mlpackage'))
        for name,x,valid in cases():
            report['current_case']=name
            with torch.no_grad():mel,length=wrapper(torch.from_numpy(x).reshape(1,-1),torch.tensor([valid],dtype=torch.int32))
            expected=mel.numpy();count=valid//160+1
            if expected.shape!=(1,128,len(x)//160+1) or length.shape!=(1,) or length.dtype!=torch.int32 or length.tolist()!=[count]:raise AssertionError('Reference ABI differs')
            if not np.isfinite(expected).all():raise AssertionError('Nonfinite source output')
            numpy_mel,numpy_count=features(x,valid,fb[0],window,160)
            if numpy_count!=count:raise AssertionError('NumPy length differs')
            numpy_metrics=measure(expected[0],numpy_mel)
            prediction=model.predict({'audio_signal':x.reshape(1,-1),'audio_length':np.array([valid],dtype=np.int32)})
            actual=prediction['mel'];actual_length=prediction['mel_length']
            if actual.dtype!=np.float32 or actual_length.dtype!=np.int32 or actual_length.shape!=(1,) or actual_length.tolist()!=[count]:raise AssertionError('CoreML ABI differs')
            metrics=measure(expected,actual)
            if np.any(actual[:,:,count:]!=0):raise AssertionError('Invalid frames not masked')
            report['cases'].append({'name':name,'samples':len(x),'valid_samples':valid,'shape':list(actual.shape),'length':count,'numpy_vs_source':numpy_metrics,'coreml_vs_source':metrics})
        # Reflect padding makes short unpadded signals invalid in original implementation.
        for n in (1,159,160,256):
            try:wrapper(torch.zeros(1,n),torch.tensor([n],dtype=torch.int32))
            except RuntimeError:continue
            raise AssertionError('Unexpected original short-input behavior')
        report['unsupported_unpadded_lengths']=[1,159,160,256]
        report['current_case']=None
        failures=[case['name'] for case in report['cases'] if any(case[k]['max_abs']>ABS_MAX or case[k]['rms']>RMS_MAX for k in ('numpy_vs_source','coreml_vs_source'))]
        if failures:raise AssertionError('Fixed parity limits exceeded: '+', '.join(failures))
        report['status']='VALID_DOMAIN_FRONTEND_PARITY_PASSED'
    except Exception as e:
        report['status']='FAILED';report['error']=str(e);raise
    finally:
        (out/'report.json').write_text(json.dumps(report,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,required=True);run(p.parse_args().output)
