"""Bounded read-only inspection of a local .nemo prefix; never extract or unpickle.
NOT archive authenticity verification. Caller must first verify whole archive size/hash.
Returns first exact root config member; does not validate later archive contents.
"""
import gzip
import zlib
import tarfile

class _BoundedReader:
    def __init__(self, stream, limit):self.stream,self.remaining=stream,limit
    def read(self,n=-1):
        if self.remaining<=0:raise ValueError('Read budget exceeded')
        n=self.remaining if n<0 else min(n,self.remaining)
        data=self.stream.read(n);self.remaining-=len(data);return data

def read_config(stream, *, max_scan=4*1024*1024,max_config=128*1024,max_raw=4*1024*1024):
    if max_scan<1 or max_config<1 or max_raw<2:raise ValueError('Invalid budget')
    # Seekable local input only. No network fetch, filesystem writes, YAML constructors.
    magic=stream.read(2);stream.seek(0)
    raw=_BoundedReader(stream,max_raw)
    decoded=gzip.GzipFile(fileobj=raw) if magic==b'\x1f\x8b' else raw
    bounded=_BoundedReader(decoded,max_scan)
    try:
        with tarfile.open(fileobj=bounded,mode='r|') as archive:
            for member in archive:
                name=member.name
                if name.startswith('/') or '..' in name.split('/'):
                    raise ValueError('Unsafe archive name')
                if name not in ('model_config.yaml','./model_config.yaml'):continue
                if member.type not in (tarfile.REGTYPE,tarfile.AREGTYPE) or member.sparse is not None or member.size<1 or member.size>max_config:
                    raise ValueError('Unsafe config type or size')
                file=archive.extractfile(member)
                data=file.read(max_config+1)
                if len(data)!=member.size:raise ValueError('Truncated config')
                data.decode('utf-8')
                return data
    except (tarfile.TarError,EOFError,UnicodeError,gzip.BadGzipFile,zlib.error) as exc:
        raise ValueError('Invalid archive/config') from exc
    finally:
        if isinstance(decoded,gzip.GzipFile):decoded.close()
    raise ValueError('Root model_config.yaml absent within budget')
