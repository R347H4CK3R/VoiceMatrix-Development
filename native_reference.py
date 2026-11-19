"""Pinned unmodified NeMo2.3.1 inference methods, with original stored buffers.
Only AST-selected trusted functions execute. No model checkpoint loading/NeMo imports.
"""
import ast,hashlib,pathlib,types
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parent
SOURCE_SHA='bd333719eec5b65053a97e29f12618c9e82121fb0ab0c1c8854bb47a1114b101'

def selected_source(path=ROOT/'upstream_features_231.py'):
    b=path.read_bytes()
    if hashlib.sha256(b).hexdigest()!=SOURCE_SHA:raise ValueError('Untrusted upstream source')
    names={'normalize_batch','splice_frames','FilterbankFeatures'}
    nodes=[n for n in ast.parse(b).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
    if {n.name for n in nodes}!=names or len(nodes)!=3:raise ValueError('Source selection differs')
    return ast.unparse(ast.Module(body=nodes,type_ignores=[]))

def verified_buffers(root=ROOT/'original-buffers'):
    from buffers import BUFFERS
    arrays=[]
    for name,key,size,shape,sha in BUFFERS:
        b=(root/(name+'.f32le')).read_bytes()
        if len(b)!=size or hashlib.sha256(b).hexdigest()!=sha:raise ValueError('Original buffer differs')
        a=np.frombuffer(b,dtype='<f4').reshape(shape).copy()
        if not np.isfinite(a).all():raise ValueError('Nonfinite original buffer')
        arrays.append(a)
    return tuple(arrays)

def build_reference():
    import torch,math,random,logging
    from typing import Optional,Tuple,Union
    if torch.__version__.split('+')[0]!='2.7.0' or np.__version__!='1.26.4':raise ValueError('Unapproved numeric toolchain')
    window,fb=verified_buffers()
    # Constructor's librosa call receives the original verified buffer instead of
    # regenerating it with a different library; only the exact known call accepted.
    def original_mel(**kwargs):
        if kwargs!={'sr':16000,'n_fft':512,'n_mels':128,'fmin':0,'fmax':8000.0,'norm':'slaney'}:raise ValueError('Unexpected mel parameters')
        return fb[0].copy()
    namespace=dict(torch=torch,nn=torch.nn,np=np,math=math,random=random,logging=logging,
                   Optional=Optional,Tuple=Tuple,Union=Union,CONSTANT=1e-5,
                   librosa=types.SimpleNamespace(filters=types.SimpleNamespace(mel=original_mel)))
    exec(compile(selected_source(),'<pinned-NeMo2.3.1-selected-methods>','exec'),namespace)
    model=namespace['FilterbankFeatures'](sample_rate=16000,n_window_size=400,n_window_stride=160,window='hann',normalize='per_feature',n_fft=512,preemph=.97,nfilt=128,lowfreq=0,highfreq=8000,log=True,log_zero_guard_type='add',log_zero_guard_value=2**-24,dither=1e-5,pad_to=0,frame_splicing=1,exact_pad=False,pad_value=0,mag_power=2.,use_grads=False,nb_augmentation_prob=0.,mel_norm='slaney')
    model.load_state_dict({'window':torch.from_numpy(window),'fb':torch.from_numpy(fb)},strict=True)
    return model.eval().cpu()
