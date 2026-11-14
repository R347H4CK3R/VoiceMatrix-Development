"""Hash-bound CPU runtime for the pinned, fixed-100-frame RVC ONNX synthesizer.

No export, training, downloads, implicit randomness, registry mutation or audio
publication. This is a reusable inference boundary, not full voice conversion.
Use only trusted model hashes from verified provenance. Model execution is not a
sandbox for untrusted graphs. Cancellation is honored before/after the ORT call.
"""
import hashlib
import os
import pathlib
import re
import stat
import threading

SHAPES = {
    'phone': [1, 100, 768], 'lengths': [1], 'pitch': [1, 100],
    'pitchf': [1, 100], 'speaker': [1], 'latent_noise': [1, 192, 100],
    'phase_noise': [1, 1, 1], 'excitation_noise': [1, 40000, 1],
}
INTEGER_INPUTS = {'lengths', 'pitch', 'speaker'}
MAX_MODEL_BYTES = 768 * 1024 * 1024

def _cancel(event):
    if event is not None and event.is_set():
        raise InterruptedError('RVC inference cancelled')

def _snapshot(path, expected, maximum=MAX_MODEL_BYTES):
    if not isinstance(expected, str) or not re.fullmatch('[a-f0-9]{64}', expected):
        raise ValueError('An explicit verified model SHA-256 is required')
    path = pathlib.Path(path)
    if path.is_symlink():
        raise ValueError('Linked model files are unsupported')
    flags = os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOFOLLOW', 0)
    with os.fdopen(os.open(path, flags), 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= maximum:
            raise ValueError('Model file is outside the supported bound')
        data = bytearray()
        while block := stream.read(1024 * 1024):
            data.extend(block)
            if len(data) > info.st_size:
                raise ValueError('Model grew during read')
    if len(data) != info.st_size or hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('Model SHA-256 or size changed')
    return bytes(data)

class RVCSynthesizer:
    def __init__(self, model_path, expected_sha256):
        import numpy as np
        import onnx
        import onnxruntime as ort
        if np.__version__ != '1.26.4' or onnx.__version__ != '1.17.0' or ort.__version__ != '1.24.2':
            raise ValueError('Use pinned NumPy 1.26.4, ONNX 1.17.0 and ORT 1.24.2')
        data = _snapshot(model_path, expected_sha256)
        graph = onnx.load_model_from_string(data)
        if not 1 <= graph.ir_version <= 10 or [(x.domain, x.version) for x in graph.opset_import] != [('', 17)]:
            raise ValueError('Unsupported ONNX IR or opset')
        random = {'RandomNormal','RandomNormalLike','RandomUniform','RandomUniformLike','Bernoulli','Multinomial'}
        if (any(t.external_data for t in graph.graph.initializer) or
                any(n.domain not in ('','ai.onnx') or n.op_type in random or
                    any(a.type in (onnx.AttributeProto.GRAPH,onnx.AttributeProto.GRAPHS) for a in n.attribute)
                    for n in graph.graph.node)):
            raise ValueError('External data, implicit randomness and custom/control-flow operators are unsupported')
        onnx.checker.check_model(graph, full_check=True)
        options = ort.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        session = ort.InferenceSession(data, sess_options=options, providers=['CPUExecutionProvider'])
        inputs = {x.name:(x.shape,x.type) for x in session.get_inputs()}
        expected = {n:(s,'tensor(int64)' if n in INTEGER_INPUTS else 'tensor(float)') for n,s in SHAPES.items()}
        outputs = [(x.name,x.shape,x.type) for x in session.get_outputs()]
        if (session.get_providers() != ['CPUExecutionProvider'] or inputs != expected or
                outputs != [('audio',[1,1,40000],'tensor(float)')]):
            raise ValueError('Model does not match the fixed RVC synthesizer contract')
        self._session = session
        self._lock = threading.Lock()
        self.model_sha256 = expected_sha256
        self._np = np

    @property
    def providers(self):
        with self._lock:
            return self._session.get_providers() if self._session else []

    def close(self):
        with self._lock:
            self._session = None

    def run(self, tensors, *, cancel=None):
        _cancel(cancel)
        np = self._np
        if not isinstance(tensors, dict) or set(tensors) != set(SHAPES):
            raise ValueError('Provide exactly the eight explicit synthesizer inputs')
        feed = {}
        for name,shape in SHAPES.items():
            value = tensors[name]
            dtype = np.dtype('int64' if name in INTEGER_INPUTS else 'float32')
            if not isinstance(value,np.ndarray) or list(value.shape) != shape or value.dtype != dtype:
                raise ValueError('Incorrect input shape or dtype: ' + name)
            # Own the inference snapshot; concurrent caller edits cannot change it.
            feed[name] = np.array(value, dtype=dtype, order='C', copy=True)
            if not np.isfinite(feed[name]).all():
                raise ValueError('Nonfinite input: ' + name)
        if (not 1 <= feed['lengths'][0] <= 100 or feed['speaker'][0] != 0 or
                (feed['pitch'] < 1).any() or (feed['pitch'] > 255).any() or
                (feed['pitchf'] < 0).any()):
            raise ValueError('Invalid lengths, speaker or pitch')
        with self._lock:
            _cancel(cancel)
            if self._session is None:
                raise RuntimeError('RVC runtime is closed')
            output = self._session.run(['audio'],feed)[0]
        _cancel(cancel)
        if output.dtype != np.float32 or list(output.shape) != [1,1,40000] or not np.isfinite(output).all():
            raise ValueError('Synthesizer returned invalid audio tensor')
        return output.copy()


def run_export_case(runtime, folder, case, manifest_sha256, *, cancel=None):
    """Run one hash-bound exporter fixture; no model download or audio publication."""
    import json
    import math
    import numpy as np
    if case not in ('voiced', 'unvoiced', 'mixed_pitch_edges', 'length_one', 'length_last'):
        raise ValueError('Unknown fixed-shape fixture case')
    folder = pathlib.Path(folder).absolute()
    if folder != folder.resolve() or any(p.is_symlink() for p in (folder, *folder.parents)):
        raise ValueError('Linked fixture directories are unsupported')
    _cancel(cancel)
    manifest = json.loads(_snapshot(folder / 'child-result.json', manifest_sha256, 1024 * 1024))
    artifacts = manifest.get('artifacts', {})
    if artifacts.get('synthesizer.onnx', {}).get('sha256') != runtime.model_sha256:
        raise ValueError('Fixture and loaded model hashes differ')
    tensors = {}
    for name, shape in {**SHAPES, 'original': [1, 1, 40000]}.items():
        _cancel(cancel)
        dtype = '<i8' if name in INTEGER_INPUTS else '<f4'
        relative = case + '/' + name + ('.i64' if dtype == '<i8' else '.f32')
        meta = artifacts.get(relative, {})
        size = math.prod(shape) * np.dtype(dtype).itemsize
        if meta.get('shape') != shape or meta.get('dtype') != dtype or meta.get('bytes') != size:
            raise ValueError('Incorrect fixture tensor metadata')
        path = folder / relative
        if path.parent.is_symlink():
            raise ValueError('Linked case directories are unsupported')
        raw = _snapshot(path, meta.get('sha256'), size)
        if len(raw) != size:
            raise ValueError('Incorrect fixture tensor byte count')
        tensors[name] = np.frombuffer(raw, dtype=dtype).reshape(shape).copy()
        if not np.isfinite(tensors[name]).all():
            raise ValueError('Nonfinite fixture tensor')
    reference = tensors.pop('original')
    output = runtime.run(tensors, cancel=cancel)
    delta = output.astype(np.float64) - reference.astype(np.float64)
    maximum = float(np.abs(delta).max())
    rms = float(np.sqrt(np.mean(delta * delta)))
    return dict(case=case, modelSHA256=runtime.model_sha256, manifestSHA256=manifest_sha256,
                samples=40000, maxAbs=maximum, rms=rms,
                referenceComparisonPassed=maximum <= 2e-4 and rms <= 2e-5,
                endToEndConversion=False, nativeIPhoneVerified=False)
