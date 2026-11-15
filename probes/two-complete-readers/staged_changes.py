"""Fail closed on any tracked change beyond known asset staging and test host."""
import pathlib,subprocess
EXPECTED=[b'D',b'VoiceMatrix/Resources/F5TTS/BUILD-INPUTS.txt',b'M',b'probes/native-local-studio/Diagnostic.swift',b'']
def verify(raw):
 assert raw.split(b'\0')==EXPECTED, 'Unexpected tracked change: '+repr(raw)
if __name__=='__main__':
 raw=subprocess.check_output(['git','diff','--name-status','-z'])
 pathlib.Path('local-evidence/staged-changes.bin').write_bytes(raw)
 verify(raw)
