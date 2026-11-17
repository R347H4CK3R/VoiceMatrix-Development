import copy, importlib.util, pathlib, unittest
P=pathlib.Path(__file__).resolve().parents[2]/'python-resolver'/'voicematrix_resolver.py'
def load():
 spec=importlib.util.spec_from_file_location('vmresolver',P);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
class Policy(unittest.TestCase):
 def setUp(self):
  self.m=load();self.f={'url':'https://rr1.googlevideo.com/videoplayback?sig=private','ext':'mp4','vcodec':'avc1.42001E','acodec':'mp4a.40.2','height':360,'filesize':1000,'protocol':'https'}
  self.info={'id':'abcdefghijk','duration':30,'age_limit':0,'is_live':False,'live_status':'not_live','availability':'public','formats':[self.f]}
 def test_combined(self):
  p=self.m.media_plan(self.info,'abcdefghijk');self.assertEqual(p,[{'url':self.f['url'],'kind':'combined','ext':'mp4','bytes':1000}])
 def test_adaptive(self):
  self.f['acodec']='none';a=dict(self.f,vcodec='none',acodec='mp4a.40.2',ext='m4a');self.info['formats'].append(a)
  self.assertEqual([p['kind'] for p in self.m.media_plan(self.info,'abcdefghijk')],['video','audio'])
 def test_reject_restricted_or_mismatched(self):
  for key,value in [('id','other______'),('age_limit',18),('is_live',True),('live_status','is_live'),('availability','needs_auth'),('duration',1801),('duration',float('nan'))]:
   with self.subTest(key=key):
    info=copy.deepcopy(self.info);info[key]=value
    with self.assertRaises(self.m.ResolverFailure):self.m.media_plan(info,'abcdefghijk')
 def test_reject_bad_media(self):
  for patch in [{'has_drm':True},{'vcodec':'none','acodec':'none'},{'vcodec':'vp9'},{'protocol':'m3u8_native'},{'filesize':0},{'filesize':536870913},{'url':'http://rr1.googlevideo.com/a'},{'url':'https://rr1.googlevideo.com.evil.test/a'},{'url':'https://u:p@rr1.googlevideo.com/a'},{'url':'https://127.0.0.1/a'},{'url':'https://rr1.googlevideo.com:444/a'}]:
   with self.subTest(patch=patch):
    info=copy.deepcopy(self.info);info['formats'][0].update(patch)
    with self.assertRaises(self.m.ResolverFailure):self.m.media_plan(info,'abcdefghijk')
 def test_source_normalization(self):
  self.assertEqual(self.m.source_identity('https://youtu.be/abcdefghijk?si=tracking'),('https://www.youtube.com/watch?v=abcdefghijk','abcdefghijk'))
  for u in ['https://user:pw@youtube.com/watch?v=abcdefghijk','https://youtube.com.evil/watch?v=abcdefghijk','https://youtube.com/watch?v=abcdefghijk&v=lmnopqrstuv']:
   with self.assertRaises(self.m.ResolverFailure):self.m.source_identity(u)

class TransportPolicy(unittest.TestCase):
 def setUp(self):self.m=load()
 def test_reject_destinations_before_network(self):
  for url in ['http://www.youtube.com/watch','https://evil.test/','https://127.0.0.1/','https://u:p@www.youtube.com/','https://www.youtube.com:444/']:
   with self.assertRaises(self.m.ResolverFailure):self.m.metadata_url(url)
 def test_response_body_bound(self):
  import io
  with self.assertRaises(self.m.ResolverFailure):self.m.read_bounded(io.BytesIO(b'x'*11),10)
  self.assertEqual(self.m.read_bounded(io.BytesIO(b'abc'),10),b'abc')
 def test_bridge_invalid_request_has_no_echo(self):
  out=self.m.resolve('{"schemaVersion":1,"url":"secret private link","authorized":true}')
  self.assertNotIn('secret',out);self.assertEqual(__import__('json').loads(out)['error_code'],'invalid_source')
 def test_requires_source_authorization(self):
  out=self.m.resolve('{"schemaVersion":1,"url":"https://youtu.be/abcdefghijk","authorized":false}')
  self.assertEqual(__import__('json').loads(out)['error_code'],'authorization_required')

class Bridge(unittest.TestCase):
 def setUp(self):self.m=load()
 def test_no_internal_exception_is_disclosed(self):
  self.m._extract=lambda *args:(_ for _ in ()).throw(RuntimeError('SECRET signed url'))
  out=self.m.resolve('{"schemaVersion":1,"url":"https://youtu.be/abcdefghijk","authorized":true}')
  self.assertNotIn('SECRET',out);self.assertEqual(__import__('json').loads(out)['error_code'],'source_unavailable')
 def test_no_token_or_cookie_options_from_request(self):
  calls=[]
  def extract(url,vid):calls.append((url,vid));raise self.m.ResolverFailure('no_supported_media')
  self.m._extract=extract
  self.m.resolve('{"schemaVersion":1,"url":"https://youtu.be/abcdefghijk","authorized":true,"cookies":"BAD","extractor_args":{"client":"tv"}}')
  self.assertEqual(calls,[('https://www.youtube.com/watch?v=abcdefghijk','abcdefghijk')])
 def test_deadline_and_aggregate_budget(self):
  import io,time
  with self.assertRaises(self.m.ResolverFailure):self.m.read_bounded(io.BytesIO(b'a'),10,time.monotonic()-1)
  transport=self.m._MetadataTransport()
  for _ in range(12):transport.admit()
  with self.assertRaises(self.m.ResolverFailure):transport.admit()

class NativeExtractorFixture(unittest.TestCase):
 @unittest.skipUnless(importlib.util.find_spec('yt_dlp'), 'bundled yt-dlp required')
 def test_real_pinned_extractor_public_fixture(self):
  import io,json
  from unittest.mock import patch
  from yt_dlp.networking.common import Response
  m=load()
  player={'playabilityStatus':{'status':'OK'},'videoDetails':{'videoId':'abcdefghijk','title':'Synthetic fixture','lengthSeconds':'30','isLiveContent':False,'author':'Fixture','channelId':'UC1234567890123456789012','viewCount':'0'},'streamingData':{'formats':[{'itag':18,'url':'https://rr1.googlevideo.com/video','mimeType':'video/mp4; codecs="avc1.42001E, mp4a.40.2"','height':360,'width':640,'contentLength':'1000','bitrate':1000,'audioQuality':'AUDIO_QUALITY_MEDIUM'}]}}
  html=('var ytInitialPlayerResponse = '+json.dumps(player)+';').encode()
  requests=[]
  def fixture_open(transport,request):
   url=request if isinstance(request,str) else request.url;requests.append(url)
   m.metadata_url(url)
   return Response(io.BytesIO(html if '/watch?' in url else b'{}'),url,{'Content-Type':'text/html' if '/watch?' in url else 'application/json'},status=200)
  from yt_dlp.extractor.youtube import YoutubeIE
  original=YoutubeIE._extract_player_responses;settings=[]
  def checked(extractor,*args,**kwargs):
   settings.append(extractor._configuration_arg('player_skip'))
   return original(extractor,*args,**kwargs)
  with patch.object(m._MetadataTransport,'open',fixture_open),patch.object(YoutubeIE,'_extract_player_responses',checked):
   result=json.loads(m.resolve(json.dumps({'schemaVersion':1,'url':'https://youtu.be/abcdefghijk','authorized':True})))
  self.assertEqual(settings,[['configs','js']])
  self.assertEqual(result['status'],'ready',result)
  self.assertEqual(result['parts'][0]['kind'],'combined')
  self.assertTrue(requests)

class RedirectSafety(unittest.TestCase):
 def test_redirect_is_validated_before_following(self):
  m=load();t=m._MetadataTransport()
  with self.assertRaises(m.ResolverFailure):t.redirect('http://127.0.0.1/')
  self.assertEqual(t.requests,0)
  for _ in range(5):t.redirect('https://www.youtube.com/watch?v=abcdefghijk')
  with self.assertRaises(m.ResolverFailure):t.redirect('https://www.youtube.com/watch?v=abcdefghijk')

class WebKitGlue(unittest.TestCase):
 @unittest.skipUnless(importlib.util.find_spec('yt_dlp') and importlib.util.find_spec('yt_dlp_ejs'), 'pinned bundled engines required')
 def test_native_json_contract_and_script_bound(self):
  import sys,types,json
  from unittest.mock import patch
  from yt_dlp.extractor.youtube.jsc._registry import _jsc_providers
  from yt_dlp.extractor.youtube.jsc.provider import JsChallengeProviderError
  m=load();calls=[]
  def evaluate(script,payload):calls.append((script,payload));return json.dumps('{"responses":[]}')
  with patch.dict(sys.modules,{'vm_webkit':types.SimpleNamespace(evaluate=evaluate,is_cancelled=lambda:False)}):
   self.assertTrue(m._install_webkit_provider())
   cls=next(c for c in _jsc_providers.value.values() if c.__name__=='VoiceMatrixWebKitJCP')
   obj=object.__new__(cls)
   self.assertEqual(obj._run_js_runtime('console.log("ok");'),'{"responses":[]}')
   self.assertEqual(calls[0][1],'{}')
   self.assertIn('return vmOutput',calls[0][0])
   with self.assertRaises(JsChallengeProviderError):obj._run_js_runtime('x'*(4*1024*1024))
   self.assertEqual(len(calls),1)

class ActiveCancellation(unittest.TestCase):
 def test_cancel_before_request_prevents_network_admission(self):
  import sys,types
  from unittest.mock import patch
  m=load();transport=m._MetadataTransport()
  with patch.dict(sys.modules,{'vm_webkit':types.SimpleNamespace(is_cancelled=lambda:True)}):
   with self.assertRaises(m.ResolverFailure) as error:transport.admit()
  self.assertEqual(error.exception.code,'cancelled');self.assertEqual(transport.requests,0)
 def test_cancel_during_read_rejects_chunk_and_stops_next_read(self):
  import sys,types,threading
  from unittest.mock import patch
  m=load();started=threading.Event();release=threading.Event();cancel=threading.Event();result=[]
  class Stream:
   calls=0
   def read(self,n):
    self.calls+=1;started.set();release.wait(2);return b'x' if self.calls==1 else b''
  stream=Stream()
  def worker():
   try:result.append(m.read_bounded(stream,100))
   except m.ResolverFailure as error:result.append(error.code)
  with patch.dict(sys.modules,{'vm_webkit':types.SimpleNamespace(is_cancelled=cancel.is_set)}):
   thread=threading.Thread(target=worker);thread.start();self.assertTrue(started.wait(2));cancel.set();release.set();thread.join(2)
  self.assertFalse(thread.is_alive());self.assertEqual(result,['cancelled']);self.assertEqual(stream.calls,1)
 def test_cancelled_extraction_cannot_return_ready(self):
  import sys,types,json
  from unittest.mock import patch
  m=load();cancel=[False]
  def extract(*args):
   cancel[0]=True
   return {'id':'abcdefghijk','duration':30,'formats':[{'url':'https://rr1.googlevideo.com/a','ext':'mp4','vcodec':'avc1.42','acodec':'mp4a.40','height':360,'filesize':100}]}
  m._extract=extract
  with patch.dict(sys.modules,{'vm_webkit':types.SimpleNamespace(is_cancelled=lambda:cancel[0])}):
   out=json.loads(m.resolve('{"schemaVersion":1,"url":"https://youtu.be/abcdefghijk","authorized":true}'))
  self.assertEqual(out['error_code'],'cancelled');self.assertNotIn('parts',out)

class ActiveRequestCancellation(unittest.TestCase):
 @unittest.skipUnless(importlib.util.find_spec('yt_dlp'), 'bundled yt-dlp required')
 def test_cancel_during_open_closes_response_without_reading(self):
  import sys,types,threading
  from unittest.mock import patch
  m=load();started=threading.Event();release=threading.Event();cancel=threading.Event();results=[]
  class Response:
   closed=False;reads=0
   def __enter__(self):return self
   def __exit__(self,*args):self.closed=True
   def read(self,n):self.reads+=1;return b'never'
  response=Response()
  class Opener:
   def open(self,*args,**kwargs):started.set();release.wait(2);return response
  def worker():
   try:results.append(m._MetadataTransport().open('https://www.youtube.com/watch?v=abcdefghijk'))
   except m.ResolverFailure as error:results.append(error.code)
  with patch.dict(sys.modules,{'vm_webkit':types.SimpleNamespace(is_cancelled=cancel.is_set)}),patch('urllib.request.build_opener',return_value=Opener()):
   thread=threading.Thread(target=worker);thread.start();self.assertTrue(started.wait(2));cancel.set();release.set();thread.join(2)
  self.assertFalse(thread.is_alive());self.assertEqual(results,['cancelled']);self.assertTrue(response.closed);self.assertEqual(response.reads,0)

class PinnedTrustStore(unittest.TestCase):
 def test_explicit_bundle_preserves_hostname_and_certificate_validation(self):
  import ssl
  m=load();context=m._tls_context()
  self.assertTrue(context.check_hostname)
  self.assertEqual(context.verify_mode,ssl.CERT_REQUIRED)
  self.assertGreater(len(context.get_ca_certs()),0)
 def test_modified_or_wrong_version_bundle_fails_closed(self):
  import sys,types
  from unittest.mock import patch
  m=load()
  for fake in [types.SimpleNamespace(__version__='old',contents=lambda:'bad'),types.SimpleNamespace(__version__='2026.10.23',contents=lambda:'bad')]:
   with patch.dict(sys.modules,{'certifi':fake}):
    with self.assertRaises(m.ResolverFailure) as error:m._tls_context()
   self.assertEqual(error.exception.code,'trust_store_unavailable')

class TLSRejection(unittest.TestCase):
 @unittest.skipUnless(__import__('shutil').which('openssl'), 'OpenSSL CLI required for synthetic TLS fixture')
 def test_pinned_context_rejects_untrusted_server_certificate(self):
  import ssl,tempfile,subprocess,pathlib
  m=load()
  with tempfile.TemporaryDirectory() as tmp:
   cert=pathlib.Path(tmp)/'cert.pem';key=pathlib.Path(tmp)/'key.pem'
   subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-subj','/CN=www.youtube.com','-days','1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
   server_context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);server_context.load_cert_chain(cert,key)
   ci,co,si,so=[ssl.MemoryBIO() for _ in range(4)]
   client=m._tls_context().wrap_bio(ci,co,server_side=False,server_hostname='www.youtube.com')
   server=server_context.wrap_bio(si,so,server_side=True)
   rejected=False
   for _ in range(20):
    try:client.do_handshake()
    except ssl.SSLCertVerificationError:rejected=True;break
    except ssl.SSLWantReadError:pass
    outgoing=co.read()
    if outgoing:si.write(outgoing)
    try:server.do_handshake()
    except ssl.SSLWantReadError:pass
    outgoing=so.read()
    if outgoing:ci.write(outgoing)
   self.assertTrue(rejected,'Pinned TLS context accepted an untrusted synthetic certificate')

class PublicClientStrategy(unittest.TestCase):
 @unittest.skipUnless(importlib.util.find_spec('yt_dlp'), 'pinned extractor required')
 def test_metadata_only_public_page_can_use_standard_public_client(self):
  self._case('OK',False,'ready')
 @unittest.skipUnless(importlib.util.find_spec('yt_dlp'), 'pinned extractor required')
 def test_client_access_requirement_is_not_bypassed(self):
  self._case('LOGIN_REQUIRED',False,'unavailable')
 @unittest.skipUnless(importlib.util.find_spec('yt_dlp'), 'pinned extractor required')
 def test_drm_client_format_is_never_returned(self):
  self._case('OK',True,'unavailable')
 def _case(self,status,drm,expected):
  import io,json
  from unittest.mock import patch
  from yt_dlp.networking.common import Response
  m=load();clients=[]
  details={'videoId':'abcdefghijk','title':'Synthetic fixture','lengthSeconds':'30','isLiveContent':False,'author':'Fixture','channelId':'UC1234567890123456789012','viewCount':'0'}
  stream={'itag':18,'mimeType':'video/mp4; codecs="avc1.42001E, mp4a.40.2"','height':360,'width':640,'contentLength':'1000','bitrate':1000,'audioQuality':'AUDIO_QUALITY_MEDIUM'}
  initial={'playabilityStatus':{'status':'OK'},'videoDetails':details,'streamingData':{'formats':[stream]}}
  final={'playabilityStatus':{'status':status},'videoDetails':details,'streamingData':{'formats':[dict(stream,url='https://rr1.googlevideo.com/video',**({'drmFamilies':['WIDEVINE']} if drm else {}))]}}
  def open_fixture(transport,request):
   url=request if isinstance(request,str) else request.url;m.metadata_url(url)
   if '/watch?' in url:payload=('var ytInitialPlayerResponse = '+json.dumps(initial)+';').encode()
   elif '/player' in url:
    body=json.loads(request.data);clients.append(body['context']['client']['clientName']);payload=json.dumps(final).encode()
   else:payload=b'{}'
   return Response(io.BytesIO(payload),url,{'Content-Type':'text/html'},status=200)
  with patch.object(m._MetadataTransport,'open',open_fixture):
   result=json.loads(m.resolve('{"schemaVersion":1,"url":"https://youtu.be/abcdefghijk","authorized":true}'))
  self.assertEqual(result['status'],expected,result)
  self.assertEqual(clients,['VISIONOS'])
  if status!='OK':self.assertEqual(result['error_code'],'restricted')

class MetadataHeaders(unittest.TestCase):
 def test_only_public_client_headers_forwarded(self):
  m=load();h=m.metadata_headers({'User-Agent':'public-client','X-Youtube-Client-Name':'101','Cookie':'SECRET','Authorization':'SECRET','Accept-Encoding':'gzip'})
  self.assertEqual(h['User-Agent'],'public-client');self.assertEqual(h['Accept-Encoding'],'identity')
  self.assertNotIn('Cookie',h);self.assertNotIn('Authorization',h)
