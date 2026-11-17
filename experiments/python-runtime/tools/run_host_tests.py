#!/usr/bin/env python3
"""Required CI tests: missing dependency or any skip is failure, not green."""
import importlib, pathlib, shutil, sys, unittest
for module in ('yt_dlp','yt_dlp_ejs','certifi','ssl'):
    importlib.import_module(module)
if not shutil.which('openssl'):raise SystemExit('OpenSSL CLI required for TLS rejection test')
root=pathlib.Path(__file__).resolve().parents[1]
result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.discover(str(root/'tests')))
if result.skipped:
    print('ERROR: required tests skipped:',result.skipped,file=sys.stderr)
    raise SystemExit(1)
raise SystemExit(0 if result.wasSuccessful() else 1)
