"""Portable diagnosis only; candidate changes FP32 operation order, not app code."""
import numpy as np

def _validate(x,count):
    x=np.asarray(x,dtype=np.float32)
    if x.ndim!=2 or not 2<=count<=x.shape[1] or not np.isfinite(x).all():raise ValueError('Invalid normalization domain')
    return x

def source_order_normalize(x,count):
    x=_validate(x,count)
    mean=np.sum(x[:,:count],axis=1,keepdims=True,dtype=np.float32)/np.float32(count)
    delta=x-mean
    std=np.sqrt(np.sum(delta[:,:count]**2,axis=1,keepdims=True,dtype=np.float32)/np.float32(count-1))
    out=delta/(std+np.float32(1e-5));out[:,count:]=0
    return out

def centered_normalize(x,count):
    x=_validate(x,count)
    centered=x-x[:,:1]
    mean=np.sum(centered[:,:count],axis=1,keepdims=True,dtype=np.float32)/np.float32(count)
    delta=centered-mean
    std=np.sqrt(np.sum(delta[:,:count]**2,axis=1,keepdims=True,dtype=np.float32)/np.float32(count-1))
    out=delta/(std+np.float32(1e-5));out[:,count:]=0
    return out

if __name__=='__main__':
    import json
    rows=[]
    for n in (3,101,1501):
        for amplitude in (0.,1e-6,1e-4):
            x=np.full((128,n),np.float32(np.log(2**-24)),dtype=np.float32)
            x+=np.float32(amplitude)*np.sin(np.arange(n,dtype=np.float32))[None,:]
            high=x.astype(np.float64);high=(high-high.mean(axis=1,keepdims=True))/(high.std(axis=1,keepdims=True,ddof=1)+1e-5)
            old=source_order_normalize(x,n);candidate=centered_normalize(x,n)
            rows.append({'frames':n,'logmel_variation':amplitude,'old_vs_fp64_max':float(np.max(np.abs(old-high))),'centered_vs_fp64_max':float(np.max(np.abs(candidate-high))),'old_vs_centered_max':float(np.max(np.abs(old-candidate)))})
    print(json.dumps({'scope':'NumPy FP32 operation-order diagnosis, not Torch/CoreML evidence','numpy':np.__version__,'cases':rows},indent=2))
