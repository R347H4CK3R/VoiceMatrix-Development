#!/usr/bin/env python3
import importlib,pathlib,shutil,sys,unittest
for name in ('yt_dlp','yt_dlp_ejs','certifi','ssl'):importlib.import_module(name)
if not shutil.which('openssl'):raise SystemExit('OpenSSL CLI required for TLS rejection test')
root=pathlib.Path(__file__).resolve().parents[2]
result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.discover(str(root/'tests/python-runtime')))
if result.skipped:raise SystemExit('Required resolver tests skipped')
raise SystemExit(0 if result.wasSuccessful() else 1)
