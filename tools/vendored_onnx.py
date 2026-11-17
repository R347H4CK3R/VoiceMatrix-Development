"""Fail-closed same-version official ONNX dependency recovery."""
import hashlib,json,pathlib
INVENTORY_SHA256="60cb54b84ee044fc81fbb6cb67c7d82bfc3bc8d5d65f3b09babfe40a60204f95"
def verify(root):
 root=pathlib.Path(root);base=root/'Vendors/ONNXRuntime';inventory=root/'Vendors/ONNXRuntime.inventory.json'
 if base.is_symlink() or inventory.is_symlink():raise ValueError('Symlinked ONNX vendor')
 raw=inventory.read_bytes()
 if hashlib.sha256(raw).hexdigest()!=INVENTORY_SHA256:raise ValueError('Unreviewed ONNX inventory')
 m=json.loads(raw);seen=set()
 for p in base.rglob('*'):
  if p.is_symlink():raise ValueError('Symlinked ONNX source')
  if p.is_dir():continue
  name=p.relative_to(base).as_posix();seen.add(name)
  if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=m['files'].get(name):raise ValueError('Changed ONNX source: '+name)
 if seen!=set(m['files']):raise ValueError('Missing ONNX source')
 return dict(version=m['version'],sourceURL=m['sourceURL'],sourceArchiveSHA256=m['sourceArchiveSHA256'],binarySHA256=m['binarySHA256'],inventorySHA256=INVENTORY_SHA256)
def notices(root):
 root=pathlib.Path(root);verify(root)
 return {'onnx-runtime-vendored/LICENSE':(root/'Vendors/ONNXRuntime/LICENSE').read_bytes(),'onnx-runtime-vendored/inventory.json':(root/'Vendors/ONNXRuntime.inventory.json').read_bytes()}
if __name__=='__main__':print(json.dumps(verify(pathlib.Path(__file__).resolve().parents[1]),indent=2))
