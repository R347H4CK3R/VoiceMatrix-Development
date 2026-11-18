"""Derive the current graph from the authenticated historical graph without updating pins."""
import argparse,hashlib,json,pathlib
SOURCE_SHA256="ff9369012927524e241f0cf3bcca1a72177947e02ef7933beef716377c87de72"
OBSOLETE={"identity":"onnxruntime-swift-package-manager","kind":"remoteSourceControl","location":"https://github.com/microsoft/onnxruntime-swift-package-manager.git","state":{"revision":"b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2"}}
def derive(raw):
 if hashlib.sha256(raw).hexdigest()!=SOURCE_SHA256:raise ValueError("Unrecognized historical graph")
 graph=json.loads(raw)
 if [p for p in graph["pins"] if p["identity"]==OBSOLETE["identity"]]!=[OBSOLETE]:raise ValueError("Unexpected ONNX pin")
 graph["pins"]=[p for p in graph["pins"] if p["identity"]!=OBSOLETE["identity"]]
 return (json.dumps(graph,indent=2,sort_keys=True)+"\n").encode()
def migrate(path):
 from tools.vendored_onnx import verify
 root=pathlib.Path(__file__).resolve().parents[1];vendor=verify(root)
 if "path: Vendors/ONNXRuntime" not in (root/"project.yml").read_text():raise ValueError("ONNX is not vendored")
 path=pathlib.Path(path);raw=path.read_bytes();derived=derive(raw)
 original=path.with_name("Package.original.resolved")
 if original.exists() and original.read_bytes()!=raw:raise ValueError("Conflicting original graph")
 original.write_bytes(raw);path.write_bytes(derived)
 path.with_name("vendored-graph-receipt.json").write_text(json.dumps(dict(originalSHA256=SOURCE_SHA256,derivedSHA256=hashlib.sha256(derived).hexdigest(),removedPin=OBSOLETE,vendoredONNX=vendor,remainingPins=json.loads(derived)["pins"]),indent=2)+"\n")
if __name__=="__main__":
 p=argparse.ArgumentParser();p.add_argument("graph");migrate(p.parse_args().graph)
