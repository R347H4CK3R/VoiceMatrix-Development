import os,pathlib,subprocess,tempfile,unittest
from unittest.mock import patch
from tools import test_shell

class TestShellResolutionTests(unittest.TestCase):
 def test_windows_uses_only_git_bin_and_returns_absolute_executable(self):
  with tempfile.TemporaryDirectory() as d:
   executable=pathlib.Path(d)/'Git/bin/bash.exe';executable.parent.mkdir(parents=True);executable.touch()
   with patch.object(test_shell.sys,'platform','win32'),patch.dict(os.environ,{'ProgramFiles':d}),patch.object(test_shell.shutil,'which',return_value=str(executable)) as which:
    self.assertEqual(test_shell.bash_executable(),str(executable.resolve()))
    which.assert_called_once_with('bash.exe',path=str(executable.parent))
 def test_windows_missing_git_bash_does_not_fall_back_to_wsl(self):
  with patch.object(test_shell.sys,'platform','win32'),patch.dict(os.environ,{'ProgramFiles':'C:/Program Files'}),patch.object(test_shell.shutil,'which',return_value=None) as which:
   with self.assertRaisesRegex(RuntimeError,'missing'):test_shell.bash_executable()
   self.assertEqual(which.call_count,1)
 def test_missing_programfiles_or_relative_resolution_fails_closed(self):
  with patch.object(test_shell.sys,'platform','win32'),patch.dict(os.environ,{},clear=True):
   with self.assertRaisesRegex(RuntimeError,'ProgramFiles'):test_shell.bash_executable()
  with patch.object(test_shell.sys,'platform','linux'),patch.object(test_shell.shutil,'which',return_value='bash'):
   with self.assertRaisesRegex(RuntimeError,'absolute'):test_shell.bash_executable()
 def test_parser_passes_exact_utf8_bytes_without_text_translation(self):
  source="if true; then\ncat <<'EOF'\ncafé\nEOF\nfi\n"
  with patch.object(test_shell,'bash_executable',return_value='/absolute/bash'),patch.object(test_shell.subprocess,'run') as run:
   test_shell.check_bash_syntax(source)
   run.assert_called_once_with(['/absolute/bash','-n'],input=source.encode('utf-8'),check=True)
   self.assertNotIn(b'\r\n',run.call_args.kwargs['input'])
 def test_real_bash_accepts_multiline_heredoc_and_if_without_execution(self):
  with tempfile.TemporaryDirectory() as d:
   marker=pathlib.Path(d)/'must-not-exist'
   source="if true; then\ncat <<'EOF'\ncafé\nEOF\nfi\n"+"touch '"+marker.as_posix()+"'\nexit 99\n"
   self.assertEqual(test_shell.check_bash_syntax(source).returncode,0)
   self.assertFalse(marker.exists(),'Syntax check executed workflow commands')
   with self.assertRaises(subprocess.CalledProcessError):test_shell.check_bash_syntax('if then\n')
 def test_nontext_source_rejected(self):
  with self.assertRaises(TypeError):test_shell.check_bash_syntax(b'exit 0')
