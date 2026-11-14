import pathlib,subprocess
r=pathlib.Path(__file__).parent
for n in ('4b70','5b55'):
 subprocess.run([str(r/'tools/python.exe'),'-I','-B',str(r/'convert_vctk_fresh.py'),n],check=True)
