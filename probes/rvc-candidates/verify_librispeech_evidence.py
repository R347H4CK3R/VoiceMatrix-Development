import json,pathlib,ast
import sys
r=pathlib.Path(sys.argv[1]);d=r/'docs/qa/librispeech-retrieval'
scores=json.loads((d/'objective-evaluation.json').read_text());chunks=0
for case in ('6930-75918-0000','8455-210777-0028'):
 for rate,tag in ((0,'0'),(.375,'0375'),(.75,'075')):
  proof=json.loads((d/(case+'-'+tag+'.json')).read_text())
  assert proof['status']=='passed' and proof['retrievalAblation']['retrievalRate']==rate
  c=proof['cases'][0];chunks+=c['chunks']
  assert c['outputSamples']==(c['input16kSamples']*5+1)//2 and c['tailCovered']
  assert scores['records'][case][tag]['sha256']==c['outputSHA256']
  assert len(c['perChunkParity'])==c['chunks']
  for e in c['perChunkParity']:assert e['maxAbs']<=2e-4 and e['rms']<=2e-5
  assert c['reconstructionMaxAbs']<=2e-4
  assert scores['records'][case][tag]['decoderSequenceTokens']<128
  assert scores['metrics'][case][tag]['asrWERAgainstPublishedReference']['referenceTokens']==len(scores['referenceTexts'][case].split())
assert chunks==9
for name in ('convert_librispeech_retrieval.py','run_librispeech_retrieval.py','evaluate_librispeech_retrieval.py','unpack_librispeech_reference.py','prepare_librispeech_reference.py','download_vctk_index.py'):
 ast.parse((r/'probes/rvc-candidates'/name).read_text())
print('Verified six output hashes against scoring evidence, nine parity checks, full durations, decoder lengths, references and six script syntax checks')
