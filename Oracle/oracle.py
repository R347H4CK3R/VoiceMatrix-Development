"""Portable semantic oracle for NeMo 2.3.1 centered frontend subset.
NOT a drop-in model, native implementation, or bitwise PyTorch oracle.
Caller must supply verified original filterbank and window; no model downloads.
"""
import numpy as np

def features(audio, valid_samples, filterbank, window, hop, *, preemph=.97, normalize=True):
    x=np.asarray(audio,dtype=np.float64)
    fb=np.asarray(filterbank,dtype=np.float64)
    w=np.asarray(window,dtype=np.float64)
    nfft=(fb.shape[1]-1)*2
    if x.ndim!=1 or w.ndim!=1 or len(w)>nfft or nfft<2 or hop<1 or not 0<=valid_samples<=len(x) or len(x)<=nfft//2:
        raise ValueError('Unsupported frontend dimensions')
    if not all(np.isfinite(v).all() for v in (x,fb,w)) or (fb<0).any():raise ValueError('Invalid numeric inputs')
    count=valid_samples//hop+1
    if normalize and count<2:raise ValueError('One-frame sample normalization is undefined')
    if preemph is not None:x=np.concatenate((x[:1],x[1:]-preemph*x[:-1]))
    padded=np.pad(x,(nfft//2,nfft//2),mode='reflect')
    window_pad=np.pad(w,((nfft-len(w))//2,(nfft-len(w)+1)//2))
    frames=np.lib.stride_tricks.sliding_window_view(padded,nfft)[::hop]
    power=np.abs(np.fft.rfft(frames*window_pad,axis=1)).T**2
    mel=np.log(fb@power+2**-24)
    if normalize:
        mean=mel[:,:count].mean(axis=1,keepdims=True)
        std=mel[:,:count].std(axis=1,ddof=1,keepdims=True)
        mel=(mel-mean)/(std+1e-5)
    mel[:,count:]=0
    return mel,count
