"""Diagnostic-only parity decomposition. No model is saved or packaged."""
import argparse
import json
from pathlib import Path
import platform
import sys
import numpy as np

ABS_MAX, RMS_MAX = 1e-3, 1e-4  # preserve original limits, not a new acceptance gate


def cases():
    def tone(n, amp):
        return (amp*np.sin(2*np.pi*440*np.arange(n,dtype=np.float64)/16000)).astype(np.float32)
    for n in (400,16000,240000):
        yield f"silence-{n}", np.zeros(n,dtype=np.float32), n
        yield f"near-silence-440hz-{n}", tone(n,1e-5), n
        yield f"tone-440hz-{n}", tone(n,.1), n
    for valid in (160,16000):
        audio=np.zeros(240000,dtype=np.float32)
        audio[:valid]=tone(valid,.1)
        yield f"padded-tone-valid-{valid}-of-240000", audio, valid


def _checked(x,count):
    a=np.asarray(x)
    if a.ndim!=3 or a.shape[0]!=1 or not 2<=count<=a.shape[-1] or not np.isfinite(a).all():
        raise ValueError("Expected finite batch-one bin/frame tensor with valid count >=2")
    return a


def errors(expected,actual,count):
    expected=_checked(expected,count);actual=_checked(actual,count)
    if expected.shape!=actual.shape:
        raise ValueError("Tensor shape mismatch")
    delta=actual.astype(np.float64)-expected.astype(np.float64)
    def region(d):
        idx=np.unravel_index(np.argmax(np.abs(d)),d.shape)
        return {"max_abs":float(abs(d[idx])), "rms":float(np.sqrt(np.mean(d*d))),
            "worst_index":[int(x) for x in idx], "expected_at_worst":float(expected[idx]),
            "actual_at_worst":float(actual[idx])}
    full=region(delta)
    return {"shape":list(expected.shape),"count":count,"all":full,"valid":region(delta[:,:,:count]),
        "old_limit_numeric_check":full["max_abs"]<=ABS_MAX and full["rms"]<=RMS_MAX}


def normalize_numpy(log_mel,count):
    a=_checked(log_mel,count).astype(np.float64)
    a=a-a[:,:,:1]
    delta=a-a[:,:,:count].mean(axis=2,keepdims=True)
    s=np.sqrt(np.sum(delta[:,:,:count]**2,axis=2,keepdims=True)/(count-1))
    result=delta/(s+1e-5)
    result[:,:,count:]=0
    return result


def run(destination):
    if platform.system()!="Darwin" or platform.machine()!="arm64":
        raise RuntimeError("Native stage probe requires macOS ARM64")
    from native_reference import build_reference, SOURCE_SHA
    import coremltools as ct
    import torch
    if ct.__version__!="9.0":
        raise RuntimeError("Unapproved CoreMLTools version")
    torch.set_num_threads(1)
    ref=build_reference()
    normalize=type(ref).forward.__globals__["normalize_batch"]

    def mask(x,lengths):
        invalid=torch.arange(x.shape[-1],device=x.device)[None,:]>=lengths[:,None]
        return x.masked_fill(invalid[:,None,:],0.0)

    class Stages(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.ref=ref

        def forward(self,a,n):
            # Exact pinned source branch. mel/log replicate the next unchanged
            # operations for this known model's log-add, frame-splicing=1 configuration.
            power,l=self.ref(a,n.long(),linear_spec=True)
            mel=torch.matmul(self.ref.fb.to(power.dtype),power)
            log_mel=torch.log(mel+2**-24)
            original,_,_=normalize(log_mel,l,"per_feature")
            return power,mel,log_mel,mask(original,l),l.to(torch.int32)

    class Whole(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.ref=ref

        def forward(self,a,n):
            m,l=self.ref(a,n.long())
            return m,l.to(torch.int32)

    class Controls(torch.nn.Module):
        def forward(self,x,n):
            lengths=n.long()
            original,_,_=normalize(x,lengths,"per_feature")
            # Translation invariance in real arithmetic; new FP32 operation
            # order changes actual values. No old-parity claim for this branch.
            anchored,_,_=normalize(x-x[:,:,:1],lengths,"per_feature")
            return mask(original,lengths),mask(anchored,lengths)

    stage_names=("power","mel","log_mel","original","mel_length")
    whole_names=("mel","mel_length")
    control_names=("original","anchored")

    def export(module,trace_inputs,inputs,names,int_names=()):
        module.eval()
        with torch.no_grad():
            traced=torch.jit.trace(module,trace_inputs,strict=False).eval()
        return ct.convert(traced,convert_to="mlprogram",minimum_deployment_target=ct.target.iOS17,
            compute_precision=ct.precision.FLOAT32,compute_units=ct.ComputeUnit.CPU_ONLY,
            inputs=inputs,outputs=[ct.TensorType(name=n,dtype=np.int32 if n in int_names else np.float32) for n in names])

    def t(x):
        return torch.from_numpy(x)

    def scalar_count(x,count):
        if x.shape!=(1,) or x.dtype!=np.int32 or int(x[0])!=count:
            raise ValueError("Unexpected length ABI")

    def check_float(x,shape):
        if x.dtype!=np.float32 or x.shape!=shape or not np.isfinite(x).all():
            raise ValueError("Unexpected float ABI")

    def check_mask(x,count):
        if np.any(x[:,:,count:]!=0):
            raise ValueError("Invalid frames were not masked")

    def audio_inputs():
        return [ct.TensorType(name="audio_signal",shape=(1,ct.RangeDim(1,240000,default=240000)),dtype=np.float32),
            ct.TensorType(name="audio_length",shape=(1,),dtype=np.int32)]

    out=Path(destination)
    out.mkdir(mode=0o700,parents=True,exist_ok=False)
    report={"schema":1,"status":"INCOMPLETE","scope":"Defect isolation only: no candidate acceptance or model artifact",
        "source_sha256":SOURCE_SHA,"comparison_thresholds":{"max_abs":ABS_MAX,"rms":RMS_MAX,"scope":"prior full-output gate, not per-stage acceptance"},
        "stage_location_semantics":["batch","bin","frame"],"precision":"FLOAT32","compute_units":"CPU_ONLY",
        "versions":{"torch":torch.__version__,"coremltools":ct.__version__,"numpy":np.__version__,"python":sys.version,"platform":platform.platform()},
        "cases":[]}
    try:
        report["current_step"]="export"
        stages=Stages().eval()
        whole=Whole().eval()
        controls=Controls().eval()
        trace_a=(.1*np.sin(2*np.pi*440*np.arange(240000)/16000)).astype(np.float32).reshape(1,-1)
        trace_n=np.array([240000],dtype=np.int32)
        trace=(t(trace_a),t(trace_n))
        ct_stages=export(stages,trace,audio_inputs(),stage_names,("mel_length",))
        # Keeping a separate baseline checks whether tracing extra observable
        # stages changes CoreML lowering/fusion relative to the original export.
        ct_whole=export(whole,trace,audio_inputs(),whole_names,("mel_length",))
        with torch.no_grad():
            trace_log=stages(*trace)[2]
        ct_controls=export(controls,(trace_log,t(np.array([1501],dtype=np.int32))),
            [ct.TensorType(name="log_mel",shape=(1,128,ct.RangeDim(2,1501,default=1501)),dtype=np.float32),
             ct.TensorType(name="mel_length",shape=(1,),dtype=np.int32)],control_names)

        for name,a,valid in cases():
            report["current_step"]=name
            frames=len(a)//160+1
            count=valid//160+1
            a=a.reshape(1,-1)
            n=np.array([valid],dtype=np.int32)
            c=np.array([count],dtype=np.int32)
            with torch.no_grad():
                source=dict(zip(stage_names,(x.numpy() for x in stages(t(a),t(n))),strict=True))
                source_end,source_count=(x.numpy() for x in whole(t(a),t(n)))
                old_t,new_t=(x.numpy() for x in controls(t(source["log_mel"]),t(c)))
            input_audio={"audio_signal":a,"audio_length":n}
            lowered=ct_stages.predict(input_audio)
            lowered_end=ct_whole.predict(input_audio)
            from_same_log=ct_controls.predict({"log_mel":source["log_mel"],"mel_length":c})
            for x in (source["mel_length"],source_count,lowered["mel_length"],lowered_end["mel_length"]):
                scalar_count(x,count)
            for key in stage_names[:-1]:
                shape=(1,257 if key=="power" else 128,frames)
                check_float(source[key],shape)
                check_float(lowered[key],shape)
            for x in (source_end,lowered_end["mel"],old_t,new_t,from_same_log["original"],from_same_log["anchored"]):
                check_float(x,(1,128,frames))
            for x in (source_end,lowered_end["mel"],source["original"],lowered["original"],old_t,new_t,from_same_log["original"],from_same_log["anchored"]):
                check_mask(x,count)
            if not np.array_equal(source_end,source["original"]) or not np.array_equal(source_end,old_t):
                raise ValueError("Decomposed Torch result differs bitwise from original source forward")
            exact64=normalize_numpy(source["log_mel"],count)
            report["cases"].append({"name":name,"samples":len(a[0]),"valid_samples":valid,"count":count,
                "source_vs_lowered_stages":{key:errors(source[key],lowered[key],count) for key in stage_names[:-1]},
                "whole_export_vs_source":errors(source_end,lowered_end["mel"],count),
                "decomposed_export_vs_whole_export":errors(lowered_end["mel"],lowered["original"],count),
                "same_logmel_normalization":{
                    "torch_original_vs_coreml_original":errors(old_t,from_same_log["original"],count),
                    "torch_anchored_vs_coreml_anchored":errors(new_t,from_same_log["anchored"],count),
                    "torch_original_vs_torch_anchored":errors(old_t,new_t,count),
                    "coreml_original_vs_coreml_anchored":errors(from_same_log["original"],from_same_log["anchored"],count),
                    "numpy_fp64_vs_torch_original":errors(exact64,old_t,count),
                    "numpy_fp64_vs_torch_anchored":errors(exact64,new_t,count),
                    "numpy_fp64_vs_coreml_original":errors(exact64,from_same_log["original"],count),
                    "numpy_fp64_vs_coreml_anchored":errors(exact64,from_same_log["anchored"],count)},
                "same_fp64_normalizer_on_different_logmel":errors(exact64,normalize_numpy(lowered["log_mel"],count),count)})
        report["status"]="DIAGNOSTIC_COMPLETED_NO_ACCEPTANCE"
        report["current_step"]=None
    except Exception as error:
        report["status"]="DIAGNOSTIC_FAILED"
        report["error"]=str(error)
        raise
    finally:
        with (out/"stage-probe-report.json").open("x") as f:
            json.dump(report,f,indent=2,allow_nan=False)


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--output",type=Path,required=True)
    run(parser.parse_args().output)
