"""Real CPU ONNX session checks using an explicitly non-neural contract graph."""
import hashlib,pathlib,tempfile,unittest,threading
try:
 import numpy as np
 import onnx
 import onnxruntime
 from onnx import helper,TensorProto
except ImportError:
 np = None

@unittest.skipIf(np is None, 'Optional ONNX CPU dependencies unavailable; install tools/rvc-runtime-requirements.txt')
class RuntimeTests(unittest.TestCase):
 def setUp(self):
  from tools import rvc_onnx_runtime as api
  self.api=api;self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.path=pathlib.Path(self.tmp.name)/'contract.onnx'
  inputs=[helper.make_tensor_value_info(n,TensorProto.INT64 if n in ('lengths','pitch','speaker') else TensorProto.FLOAT,s) for n,s in api.SHAPES.items()]
  graph=helper.make_graph([
   helper.make_node('ReduceMean',['phone'],['mean'],keepdims=0),
   helper.make_node('Expand',['mean','shape'],['audio'])],'not-a-neural-model',inputs,
   [helper.make_tensor_value_info('audio',TensorProto.FLOAT,[1,1,40000])],
   [helper.make_tensor('shape',TensorProto.INT64,[3],[1,1,40000])])
  model=helper.make_model(graph,opset_imports=[helper.make_opsetid('',17)]);model.ir_version=8
  self.path.write_bytes(model.SerializeToString());self.digest=hashlib.sha256(self.path.read_bytes()).hexdigest()
 def feed(self):
  x={n:np.zeros(s,dtype=np.int64 if n in ('lengths','pitch','speaker') else np.float32) for n,s in self.api.SHAPES.items()}
  x['phone'].fill(1);x['lengths'].fill(100);x['pitch'].fill(1);return x
 def load(self):return self.api.RVCSynthesizer(self.path,self.digest)
 def test_real_cpu_session_consumes_new_tensors_without_mutating_input(self):
  runtime=self.load();first=self.feed();original=first['phone'].copy()
  np.testing.assert_array_equal(runtime.run(first),np.ones((1,1,40000),dtype=np.float32))
  second=self.feed();second['phone'].fill(2)
  np.testing.assert_array_equal(runtime.run(second),np.full((1,1,40000),2,dtype=np.float32))
  np.testing.assert_array_equal(first['phone'],original)
  self.assertEqual(runtime.providers,['CPUExecutionProvider'])
 def test_wrong_hash_and_changed_model_fail_before_session(self):
  with self.assertRaises(ValueError):self.api.RVCSynthesizer(self.path,'0'*64)
  self.path.write_bytes(b'changed')
  with self.assertRaises(ValueError):self.load()
 def test_wrong_shape_dtype_nonfinite_and_semantic_inputs_fail(self):
  runtime=self.load()
  cases=[('phone',np.zeros((1,298,768),np.float32)),('phone',np.zeros((1,100,768),np.float64)),
   ('lengths',np.array([0],np.int64)),('lengths',np.array([101],np.int64)),
   ('speaker',np.array([1],np.int64)),('pitch',np.zeros((1,100),np.int64)),
   ('pitchf',np.full((1,100),-1,np.float32)),('phase_noise',np.full((1,1,1),np.nan,np.float32))]
  for name,value in cases:
   feed=self.feed();feed[name]=value
   with self.subTest(name=name),self.assertRaises(ValueError):runtime.run(feed)
  feed=self.feed();feed['extra']=np.zeros(1)
  with self.assertRaises(ValueError):runtime.run(feed)
 def test_cancellation_and_closed_runtime_cannot_return_audio(self):
  runtime=self.load();cancel=threading.Event();cancel.set()
  with self.assertRaises(InterruptedError):runtime.run(self.feed(),cancel=cancel)
  runtime.close()
  with self.assertRaises(RuntimeError):runtime.run(self.feed())
 def test_model_graph_contract_is_checked(self):
  model=onnx.load(self.path);model.graph.input[0].type.tensor_type.shape.dim[1].dim_value=298
  self.path.write_bytes(model.SerializeToString());self.digest=hashlib.sha256(self.path.read_bytes()).hexdigest()
  with self.assertRaises(ValueError):self.load()

 def test_nonregular_model_is_rejected_without_blocking(self):
  import os
  if not hasattr(os, 'mkfifo'):self.skipTest('POSIX FIFO unavailable')
  fifo=pathlib.Path(self.tmp.name)/'fifo';os.mkfifo(fifo)
  with self.assertRaises(ValueError):self.api.RVCSynthesizer(fifo,self.digest)
 def export_fixture(self):
  import json
  folder=pathlib.Path(self.tmp.name);(folder/'voiced').mkdir()
  artifacts={'synthesizer.onnx':{'sha256':self.digest}}
  tensors=self.feed();tensors['original']=np.ones((1,1,40000),np.float32)
  for name,value in tensors.items():
   dtype='<i8' if name in ('lengths','pitch','speaker') else '<f4'
   rel='voiced/'+name+('.i64' if dtype=='<i8' else '.f32')
   raw=value.astype(dtype).tobytes();(folder/rel).write_bytes(raw)
   artifacts[rel]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'shape':list(value.shape),'dtype':dtype}
  raw=json.dumps({'artifacts':artifacts}).encode();(folder/'child-result.json').write_bytes(raw)
  return folder,hashlib.sha256(raw).hexdigest()
 def test_exported_tensor_fixture_executes_and_compares_reference(self):
  self.assertTrue(hasattr(self.api,'run_export_case'),'Exported fixtures cannot yet enter the runtime')
  folder,digest=self.export_fixture()
  result=self.api.run_export_case(self.load(),folder,'voiced',digest)
  self.assertEqual(result['samples'],40000);self.assertEqual(result['maxAbs'],0)
  self.assertEqual(result['rms'],0);self.assertTrue(result['referenceComparisonPassed'])
 def test_exported_tensor_tampering_and_path_escape_fail(self):
  self.assertTrue(hasattr(self.api,'run_export_case'),'Fixture admission is missing')
  folder,digest=self.export_fixture();runtime=self.load()
  with self.assertRaises(ValueError):self.api.run_export_case(runtime,folder,'../voiced',digest)
  (folder/'voiced/phone.f32').write_bytes(b'changed')
  with self.assertRaises(ValueError):self.api.run_export_case(runtime,folder,'voiced',digest)
