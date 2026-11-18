import hashlib
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock
import zipfile
from tools import setup_windows_ffmpeg as setup

class SetupTests(unittest.TestCase):
    def archive(self,root,extra=None):
        path=root/'build.zip'
        with zipfile.ZipFile(path,'w') as z:
            for name in ('ffmpeg.exe','ffprobe.exe'):z.writestr(setup.ROOT+'/bin/'+name,b'MZsynthetic-test-not-executable')
            if extra:
                entry, payload = extra
                if isinstance(entry, str):
                    # ZipInfo normalizes native backslashes on Windows construction.
                    # Preserve the malicious raw ZIP name so the reader is exercised.
                    info = zipfile.ZipInfo('placeholder')
                    info.filename = entry
                    info.orig_filename = entry
                    entry = info
                z.writestr(entry, payload)
        return path
    def test_verified_extraction_and_exclusive_destination(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);archive=self.archive(root)
            setup.verify_archive(archive,hashlib.sha256(archive.read_bytes()).hexdigest(),archive.stat().st_size)
            binary=setup.extract_checked(archive,root/'installed')
            self.assertTrue((binary/'ffprobe.exe').is_file())
            with self.assertRaises(ValueError):setup.extract_checked(archive,root/'installed')
    def test_hash_or_size_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            archive=self.archive(Path(temp))
            with self.assertRaises(ValueError):setup.verify_archive(archive,'0'*64,archive.stat().st_size)
            with self.assertRaises(ValueError):setup.verify_archive(archive,'0'*64,1)
    def test_paths_duplicates_and_links_rejected(self):
        for name in ('../escape',setup.ROOT+'/../escape','C:/evil',setup.ROOT+'/bin/ffmpeg.exe',setup.ROOT+'\\evil',setup.ROOT+'/bad:stream'):
            with self.subTest(name=name),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);archive=self.archive(root,(name,b'bad'))
                with self.assertRaises(ValueError):setup.extract_checked(archive,root/'installed')
                self.assertFalse((root/'installed').exists())
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);entry=zipfile.ZipInfo(setup.ROOT+'/link');entry.external_attr=(stat.S_IFLNK|0o777)<<16
            archive=self.archive(root,(entry,b'outside'))
            with self.assertRaises(ValueError):setup.extract_checked(archive,root/'installed')
    def test_missing_tools_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);archive=root/'build.zip'
            with zipfile.ZipFile(archive,'w') as z:z.writestr(setup.ROOT+'/license.txt',b'test')
            with self.assertRaises(ValueError):setup.extract_checked(archive,root/'installed')

    def test_extraction_size_budget_and_non_pe_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);archive=self.archive(root)
            with mock.patch.object(setup,'MAX_TOTAL',1):
                with self.assertRaises(ValueError):setup.extract_checked(archive,root/'installed')
            self.assertFalse((root/'installed').exists())
            with zipfile.ZipFile(archive,'w') as z:
                for name in ('ffmpeg.exe','ffprobe.exe'):z.writestr(setup.ROOT+'/bin/'+name,b'not a PE')
            with self.assertRaises(ValueError):setup.extract_checked(archive,root/'installed')
            self.assertFalse((root/'installed').exists())
