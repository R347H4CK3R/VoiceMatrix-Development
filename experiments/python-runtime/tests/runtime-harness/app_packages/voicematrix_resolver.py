"""TEST HOST ONLY. Native runtime probes; never production resolver replacement."""
import json
import vm_webkit

def resolve(request_json):
    request = json.loads(request_json)
    if request.get('schemaVersion') != 1 or request.get('authorized') is not True:
        raise ValueError('invalid test request')
    if request.get('mode') == 'native-production-smoke':
        import _ssl
        import ssl
        import yt_dlp.version
        import yt_dlp_ejs
        import certifi
        import production_voicematrix_resolver as resolver
        context = resolver._tls_context()
        bridge = json.loads(vm_webkit.evaluate("return {bridge: 'native-webkit'};", '{}'))
        return json.dumps({'status':'ready','yt_dlp':yt_dlp.version.__version__,
                          'certifi':certifi.__version__,'ssl':_ssl.OPENSSL_VERSION,
                          'roots':context.cert_store_stats()['x509_ca'],
                          'verify':context.verify_mode == ssl.CERT_REQUIRED,
                          'hostname':context.check_hostname,'bridge':bridge['bridge'],
                          'rejects_untrusted_tls':_reject_untrusted_tls(context)})
    return vm_webkit.evaluate('return input;', json.dumps(request))


def _reject_untrusted_tls(context):
    import pathlib, ssl
    root=pathlib.Path(__file__).parent
    server_context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_context.load_cert_chain(root/'tls-test-cert.pem',root/'tls-test-key.pem')
    ci,co,si,so=[ssl.MemoryBIO() for _ in range(4)]
    client=context.wrap_bio(ci,co,server_side=False,server_hostname='www.youtube.com')
    server=server_context.wrap_bio(si,so,server_side=True)
    for _ in range(20):
        try:client.do_handshake()
        except ssl.SSLCertVerificationError:return True
        except ssl.SSLWantReadError:pass
        outgoing=co.read()
        if outgoing:si.write(outgoing)
        try:server.do_handshake()
        except ssl.SSLWantReadError:pass
        outgoing=so.read()
        if outgoing:ci.write(outgoing)
    raise RuntimeError('native untrusted certificate was not rejected')
