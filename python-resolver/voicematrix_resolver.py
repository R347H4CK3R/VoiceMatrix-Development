"""Bounded on-device yt-dlp adapter. Never downloads media or exposes raw errors.

Bundled yt-dlp 2026.10.26 only. Native host must run this off-main, serialize
requests, enforce a wall-clock deadline, and independently validate/download
returned parts. This is not general YouTube support.
"""
import json
import math
import re
from urllib.parse import parse_qs, urlsplit

MAX_BYTES = 536_870_912
YTDLP_VERSION = '2026.10.26'

class ResolverFailure(Exception):
    """Only fixed codes may cross the native boundary, never source/stream URLs."""
    def __init__(self, code):
        self.code = code
        super().__init__(code)

def _check_cancelled():
    """Cooperative only: native cancellation cannot interrupt a blocking Python read/DNS."""
    try:
        import vm_webkit
    except ImportError:
        return  # Standalone policy tests have no native request lifetime.
    try:
        cancelled = vm_webkit.is_cancelled()
    except Exception:
        raise ResolverFailure('cancellation_unavailable') from None
    if cancelled:
        raise ResolverFailure('cancelled')

def source_identity(raw):
    if not isinstance(raw, str) or len(raw.encode('utf-8')) > 16_384:
        raise ResolverFailure('invalid_source')
    try:
        u = urlsplit(raw.strip())
        if u.scheme != 'https' or u.username is not None or u.password is not None or u.port not in (None, 443) or u.fragment:
            raise ValueError()
        if u.hostname not in ('youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'):
            raise ValueError()
        segments = u.path.strip('/').split('/')
        if u.hostname == 'youtu.be' and len(segments) == 1:
            video_id = segments[0]
        elif len(segments) == 2 and segments[0] in ('shorts', 'embed', 'live'):
            video_id = segments[1]
        elif u.path == '/watch':
            ids = parse_qs(u.query, keep_blank_values=True).get('v', [])
            if len(ids) != 1:
                raise ValueError()
            video_id = ids[0]
        else:
            raise ValueError()
        if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
            raise ValueError()
    except (ValueError, TypeError):
        raise ResolverFailure('invalid_source') from None
    return 'https://www.youtube.com/watch?v=' + video_id, video_id

def _stream_url(value):
    if not isinstance(value, str) or len(value.encode('utf-8')) > 16_384:
        return False
    try:
        u = urlsplit(value)
        return (u.scheme == 'https' and u.username is None and u.password is None
                and u.port in (None, 443) and not u.fragment and u.hostname is not None
                and (u.hostname == 'googlevideo.com' or u.hostname.endswith('.googlevideo.com')))
    except ValueError:
        return False

def media_plan(info, video_id):
    _check_cancelled()
    if not isinstance(info, dict) or info.get('id') != video_id:
        raise ResolverFailure('identity_mismatch')
    if (info.get('age_limit', 0) != 0 or info.get('is_live') is True
            or info.get('live_status', 'not_live') != 'not_live'
            or info.get('availability') not in (None, 'public', 'unlisted')
            or info.get('has_drm')):
        raise ResolverFailure('restricted')
    seconds = info.get('duration')
    if not isinstance(seconds, (float, int)) or isinstance(seconds, bool) or not math.isfinite(seconds) or not 3 <= seconds <= 1800:
        raise ResolverFailure('duration_limit')
    formats = info.get('formats')
    if not isinstance(formats, list) or len(formats) > 300:
        raise ResolverFailure('no_supported_media')
    choices = []
    for f in formats:
        _check_cancelled()
        if not isinstance(f, dict) or f.get('has_drm') or f.get('protocol') not in (None, 'https') or f.get('fragments') or f.get('manifest_url') or not _stream_url(f.get('url')):
            continue
        size = f.get('filesize')
        if not isinstance(size, int) or isinstance(size, bool) or not 0 < size <= MAX_BYTES:
            continue
        v, a = f.get('vcodec', ''), f.get('acodec', '')
        if not isinstance(v, str) or not isinstance(a, str):
            continue
        if v == 'none' and a.startswith('mp4a') and f.get('ext') == 'm4a':
            kind, ext = 'audio', 'm4a'
        elif v.startswith('avc1') and f.get('ext') == 'mp4' and isinstance(f.get('height'), int) and 1 <= f['height'] <= 720:
            if a.startswith('mp4a'):
                kind, ext = 'combined', 'mp4'
            elif a == 'none':
                kind, ext = 'video', 'mp4'
            else:
                continue
        else:
            continue
        choices.append({'url': f['url'], 'kind': kind, 'ext': ext, 'bytes': size})
    choices.sort(key=lambda f: f['bytes'])
    combined = next((f for f in choices if f['kind'] == 'combined'), None)
    if combined:
        return [combined]
    video = next((f for f in choices if f['kind'] == 'video'), None)
    audio = next((f for f in choices if f['kind'] == 'audio'), None)
    if video and audio and video['bytes'] + audio['bytes'] <= MAX_BYTES:
        return [video, audio]
    raise ResolverFailure('no_supported_media')

def metadata_url(raw):
    try:
        u = urlsplit(raw)
        if (not isinstance(raw, str) or len(raw.encode()) > 16_384 or u.scheme != 'https'
                or u.hostname not in ('www.youtube.com', 'youtube.com', 'm.youtube.com')
                or u.username is not None or u.password is not None or u.port not in (None, 443) or u.fragment):
            raise ValueError()
    except (ValueError, TypeError):
        raise ResolverFailure('network_policy') from None
    return raw

def metadata_headers(values):
    headers = {'Accept-Encoding':'identity', 'Content-Type':'application/json', 'User-Agent':'VoiceMatrix/OnDeviceResolver'}
    permitted = {'accept':'Accept', 'content-type':'Content-Type', 'user-agent':'User-Agent',
                 'x-youtube-client-name':'X-Youtube-Client-Name', 'x-youtube-client-version':'X-Youtube-Client-Version',
                 'x-goog-visitor-id':'X-Goog-Visitor-Id'}
    for key, value in values.items():
        name = permitted.get(key.lower())
        if name and isinstance(value, str) and len(value.encode()) <= 8192 and '\r' not in value and '\n' not in value:
            headers[name] = value
    return headers

def read_bounded(stream, maximum, deadline=None):
    import time
    chunks = []
    total = 0
    read = getattr(stream, 'read1', stream.read)
    while True:
        _check_cancelled()
        if deadline is not None and time.monotonic() >= deadline:
            raise ResolverFailure('timeout')
        chunk = read(min(65_536, maximum + 1 - total))
        _check_cancelled()
        if not chunk:
            return b''.join(chunks)
        total += len(chunk)
        if total > maximum:
            raise ResolverFailure('response_limit')
        chunks.append(chunk)

class _QuietLog:
    def debug(self, *args, **kwargs): pass
    def info(self, *args, **kwargs): pass
    def warning(self, *args, **kwargs): pass
    def error(self, *args, **kwargs): pass

CA_VERSION = '2026.10.23'
CA_SHA256 = '2ef52ad56b4803e264045c915e55c236cbfa045b84b81efefc218a19eb44bd2b'

def _tls_context():
    """Use the bundled pinned roots, not host paths/env overrides or disabled TLS."""
    import hashlib
    import ssl
    try:
        import certifi
        if certifi.__version__ != CA_VERSION:
            raise ValueError()
        pem = certifi.contents().encode('ascii')
        if len(pem) > 512_000 or hashlib.sha256(pem).hexdigest() != CA_SHA256:
            raise ValueError()
        # cadata uses the exact hash-checked bytes and avoids a file reopen race.
        context = ssl.create_default_context(cadata=pem.decode('ascii'))
        if not context.check_hostname or context.verify_mode != ssl.CERT_REQUIRED or not context.get_ca_certs():
            raise ValueError()
        return context
    except Exception:
        raise ResolverFailure('trust_store_unavailable') from None

class _MetadataTransport:
    def __init__(self):
        import time
        self.deadline = time.monotonic() + 90
        self.requests = 0
        self.redirects = 0
        self.total = 0

    def open(self, req):
        import io
        import time
        import ssl
        import urllib.request
        import urllib.error
        from yt_dlp.networking.common import Response
        transport = self
        class Redirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, msg, headers, newurl):
                transport.redirect(newurl)
                return super().redirect_request(request, fp, code, msg, headers, newurl)
        url = req if isinstance(req, str) else req.url
        metadata_url(url)
        self.admit()
        method = 'GET' if isinstance(req, str) else req.method
        data = None if isinstance(req, str) else req.data
        if method not in ('GET', 'POST') or (data is not None and (not isinstance(data, bytes) or len(data) > 262_144)):
            raise ResolverFailure('network_policy')
        # No cookie/auth handlers, proxies, credential persistence, or decompression.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), Redirect(), urllib.request.HTTPSHandler(context=_tls_context()))
        request = urllib.request.Request(url, data=data, method=method, headers=metadata_headers({} if isinstance(req, str) else req.headers))
        remaining = min(4_000_000, 12_000_000 - self.total)
        try:
            _check_cancelled()
            with opener.open(request, timeout=max(1, min(20, self.deadline - time.monotonic()))) as response:
                _check_cancelled()
                metadata_url(response.url)
                if response.headers.get('Content-Encoding', 'identity').lower() not in ('', 'identity'):
                    raise ResolverFailure('unsupported_encoding')
                declared = response.headers.get('Content-Length')
                if declared is not None and (not declared.isdigit() or int(declared) > remaining):
                    raise ResolverFailure('response_limit')
                payload = read_bounded(response, remaining, self.deadline)
                if declared is not None and len(payload) != int(declared):
                    raise ResolverFailure('incomplete_response')
                self.total += len(payload)
                if time.monotonic() > self.deadline:
                    raise ResolverFailure('timeout')
                return Response(io.BytesIO(payload), response.url, response.headers, status=response.status)
        except (urllib.error.URLError, TimeoutError, OSError):
            raise ResolverFailure('network_unavailable') from None

    def redirect(self, url):
        _check_cancelled()
        metadata_url(url)
        self.redirects += 1
        if self.redirects > 5:
            raise ResolverFailure('redirect_limit')
        self.admit()

    def admit(self):
        import time
        _check_cancelled()
        self.requests += 1
        if self.requests > 12 or self.total >= 12_000_000 or time.monotonic() >= self.deadline:
            raise ResolverFailure('request_limit')

_provider_installed = False

def _install_webkit_provider():
    global _provider_installed
    if _provider_installed:
        return True
    try:
        import vm_webkit
        import yt_dlp_ejs
        if yt_dlp_ejs.version != '0.8.0':
            raise ResolverFailure('engine_version')
        from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
        from yt_dlp.extractor.youtube.jsc.provider import register_provider, register_preference, JsChallengeProviderError
    except ImportError:
        return False
    @register_provider
    class VoiceMatrixWebKitJCP(EJSBaseJCP):
        JS_RUNTIME_NAME = 'voicematrix-webkit'
        def is_available(self): return True
        def _construct_stdin(self, player, preprocessed, requests):
            # No preprocessed-player export or cache: avoid large output containing JS.
            data = {'type':'player', 'player':player, 'requests':[{'type':r.type.value,'challenges':r.input.challenges} for r in requests], 'output_preprocessed':False}
            return self._lib_script.code + '\nObject.assign(globalThis,lib);\n' + self._core_script.code + '\nconsole.log(JSON.stringify(jsc(' + json.dumps(data) + ')));'
        def _run_js_runtime(self, stdin):
            _check_cancelled()
            body = 'let vmOutput=null; const console=Object.freeze({log:(value)=>{vmOutput=String(value);}});\n' + stdin + '\nreturn vmOutput;'
            if len(body.encode()) > 4 * 1024 * 1024:
                raise JsChallengeProviderError('Script exceeds native limit')
            try:
                result = json.loads(vm_webkit.evaluate(body, '{}'))
                _check_cancelled()
                if not isinstance(result, str) or len(result.encode()) > 1024 * 1024:
                    raise ValueError()
                return result
            except ResolverFailure:
                raise
            except Exception:
                _check_cancelled()
                raise JsChallengeProviderError('Native WebKit evaluation unavailable') from None
    @register_preference(VoiceMatrixWebKitJCP)
    def prefer_native(provider, requests): return 1000
    _provider_installed = True
    return True

def _extract(url, video_id):
    _check_cancelled()
    from yt_dlp import YoutubeDL
    from yt_dlp.version import __version__
    from yt_dlp.extractor.youtube import YoutubeIE
    if __version__ != YTDLP_VERSION:
        raise ResolverFailure('engine_version')
    webkit = _install_webkit_provider()
    transport = _MetadataTransport()
    class LocalYoutubeDL(YoutubeDL):
        def urlopen(self, request): return transport.open(request)
    class PublicYouTubeIE(YoutubeIE):
        @classmethod
        def ie_key(cls): return YoutubeIE.ie_key()
        def _get_requested_clients(self, *args): return ['web']
        def fetch_po_token(self, *args, **kwargs): return None
        def _download_ytcfg(self, client, *args, **kwargs):
            if client not in ('web', 'visionos'): raise ResolverFailure('restricted')
            return super()._download_ytcfg(client, *args, **kwargs)
        def _extract_player_response(self, client, *args, **kwargs):
            if client not in ('web', 'visionos'): raise ResolverFailure('restricted')
            response = super()._extract_player_response(client, *args, **kwargs)
            if (not isinstance(response, dict) or response.get('playabilityStatus', {}).get('status') != 'OK'
                    or response.get('videoDetails', {}).get('videoId') != video_id
                    or response.get('videoDetails', {}).get('isLiveContent') is not False
                    or response.get('microformat', {}).get('playerMicroformatRenderer', {}).get('isFamilySafe') is False):
                raise ResolverFailure('restricted')
            return response
        def _extract_player_responses(self, clients, current_id, webpage, *args, **kwargs):
            _check_cancelled()
            initial = self._search_json(self._YT_INITIAL_PLAYER_RESPONSE_RE, webpage, 'public player', current_id, fatal=True)
            details = initial.get('videoDetails', {})
            if (initial.get('playabilityStatus', {}).get('status') != 'OK'
                    or details.get('videoId') != video_id or details.get('isLiveContent') is not False
                    or initial.get('microformat', {}).get('playerMicroformatRenderer', {}).get('isFamilySafe') is False):
                raise ResolverFailure('restricted')
            streams = initial.get('streamingData', {})
            formats = streams.get('formats', []) + streams.get('adaptiveFormats', [])
            if not isinstance(formats, list) or len(formats) > 300:
                raise ResolverFailure('response_limit')
            # Only after the ordinary page proves public access. No restriction,
            # authentication, CAPTCHA, attestation or DRM fallback is permitted.
            has_direct_candidate = any(isinstance(f, dict) and (f.get('url') or f.get('signatureCipher') or f.get('cipher')) for f in formats)
            selected = ['web'] if has_direct_candidate else ['web', 'visionos']
            return super()._extract_player_responses(selected, current_id, webpage, *args, **kwargs)
    options = {'skip_download':True, 'noplaylist':True, 'quiet':True, 'logger':_QuietLog(),
               'socket_timeout':20, 'retries':0, 'extractor_retries':0, 'cachedir':False,
               'js_runtimes':{}, 'remote_components':[], 'plugin_dirs':[],
               'extractor_args':{'youtube':{'player_client':['web'], 'player_skip':['configs'] if webkit else ['configs','js'], 'fetch_pot':['never']}}}
    with LocalYoutubeDL(options) as downloader:
        _check_cancelled()
        result = PublicYouTubeIE(downloader).extract(url)
        _check_cancelled()
        return result

def resolve(request_json):
    envelope = {'schemaVersion':1, 'status':'unavailable'}
    try:
        _check_cancelled()
        if not isinstance(request_json, str) or len(request_json.encode()) > 20_000:
            raise ResolverFailure('invalid_request')
        request = json.loads(request_json)
        if not isinstance(request, dict) or request.get('schemaVersion') != 1:
            raise ResolverFailure('invalid_request')
        if request.get('authorized') is not True:
            raise ResolverFailure('authorization_required')
        url, video_id = source_identity(request.get('url'))
        _check_cancelled()
        info = _extract(url, video_id)
        _check_cancelled()
        parts = media_plan(info, video_id)
        _check_cancelled()
        return json.dumps({'schemaVersion':1, 'status':'ready', 'parts':parts}, separators=(',', ':'))
    except ResolverFailure as error:
        envelope['error_code'] = error.code
    except ImportError:
        envelope['error_code'] = 'engine_unavailable'
    except Exception:
        try:
            _check_cancelled()
        except ResolverFailure as error:
            envelope['error_code'] = error.code
        else:
            envelope['error_code'] = 'source_unavailable'
    return json.dumps(envelope, separators=(',', ':'))
