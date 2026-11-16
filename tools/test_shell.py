"""Resolve an actual Bash executable for read-only workflow syntax tests.

Windows subprocess must receive an absolute executable, otherwise CreateProcess
can select System32's WSL launcher before PATH. Never run workflow bodies here.
"""
import os,pathlib,shutil,subprocess,sys

def bash_executable():
 if sys.platform=='win32':
  program_files=os.environ.get('ProgramFiles')
  if not program_files:raise RuntimeError('ProgramFiles missing; cannot locate Git Bash')
  location=str(pathlib.Path(program_files)/'Git'/'bin')
  executable=shutil.which('bash.exe',path=location)
 else:
  executable=shutil.which('bash')
 if not executable:raise RuntimeError('Bash executable missing; syntax checks cannot run')
 path=pathlib.Path(executable)
 if not path.is_absolute():raise RuntimeError('Bash resolution must be absolute')
 return str(path.resolve())


def check_bash_syntax(source):
 """Parse exact UTF-8/LF bytes without Windows text-mode newline conversion."""
 if not isinstance(source,str):raise TypeError('Shell source must be text')
 return subprocess.run([bash_executable(),'-n'],input=source.encode('utf-8'),check=True)
