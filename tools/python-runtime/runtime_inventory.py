"""Signing-aware native identity and exact pure-Python wheel resources."""
import hashlib,struct,zipfile

def sha(data):return hashlib.sha256(data).hexdigest()
def wheel_inventory(path):
    with zipfile.ZipFile(path) as z:
        entries={}
        for name in z.namelist():
            if name.endswith('/') or '.data/' in name or name.endswith('.dist-info/RECORD'):continue
            if name.startswith('/') or '..' in name.split('/'):raise ValueError('Invalid wheel path')
            data=z.read(name);entries[name]={'bytes':len(data),'sha256':sha(data)}
        return entries

def arm64_slice(data):
    if data[:4]==b'\xca\xfe\xba\xbe':
        count=struct.unpack_from('>I',data,4)[0];found=[]
        if count!=1:raise ValueError('Expected device-only single-slice fat binary')
        for i in range(count):
            cpu,sub,offset,size,align=struct.unpack_from('>IIIII',data,8+i*20)
            if align>30 or offset<28 or offset%(1<<align) or offset+size>len(data):raise ValueError('Invalid fat slice')
            if any(data[28:offset]) or any(data[offset+size:]):raise ValueError('Unexpected data outside device slice')
            if cpu==0x100000c:found.append(data[offset:offset+size])
        if len(found)!=1:raise ValueError('Expected one arm64 slice')
        data=found[0]
    if data[:4]!=b'\xcf\xfa\xed\xfe' or struct.unpack_from('<I',data,4)[0]!=0x100000c:raise ValueError('Expected arm64 Mach-O')
    return data

def verify_signed_native(expected,actual):
    """Allow ONLY signing command, terminal signature and LINKEDIT size changes.

    Every remaining byte (headers, all load commands, exports, rebases, chained
    fixups, symbols, sections, padding) must match the pinned unsigned SDK slice.
    Intentional stripping/install-name edits fail closed and require review.
    """
    source=arm64_slice(expected);built=arm64_slice(actual)
    def commands(data):
        count,extent=struct.unpack_from('<II',data,16);pos=32;items=[]
        if count>1024 or 32+extent>len(data):raise ValueError('Invalid commands')
        for _ in range(count):
            cmd,size=struct.unpack_from('<II',data,pos)
            if size<8 or pos+size>32+extent:raise ValueError('Invalid command size')
            items.append((cmd,pos,data[pos:pos+size]));pos+=size
        if pos!=32+extent:raise ValueError('Invalid command extent')
        return items,extent
    original,oldextent=commands(source);current,newextent=commands(built)
    if any(c==0x1d for c,_,_ in original):raise ValueError('Signed upstream requires separate reviewed normalization')
    sig=[(p,c) for cmd,p,c in current if cmd==0x1d]
    if not sig:
        if built!=source:raise ValueError('Unsigned binary mismatch')
        return {'canonicalUnsignedSHA256':sha(source),'packagedSliceSHA256':sha(built),'normalization':'none'}
    if len(sig)!=1 or len(sig[0][1])!=16:raise ValueError('Invalid code signature command')
    sigoff,sigsize=struct.unpack_from('<II',sig[0][1],8)
    if not sigsize or sigoff<len(source) or sigoff-len(source)>15 or sigoff+sigsize!=len(built):raise ValueError('Unexpected signed binary extent')
    if any(built[len(source):sigoff]):raise ValueError('Nonzero signature alignment padding')
    filtered=[(cmd,pos,bytearray(blob)) for cmd,pos,blob in current if cmd!=0x1d]
    if len(filtered)!=len(original) or newextent!=oldextent+16:raise ValueError('Unexpected added/removed load commands')
    normalized=bytearray(built[:len(source)])
    oldheader=bytearray(source[:32]);newheader=bytearray(built[:32]);newheader[16:24]=oldheader[16:24]
    if newheader!=oldheader:raise ValueError('Mach-O header changed beyond signing counts')
    normalized[:32]=source[:32]
    output=[]
    for (oldcmd,oldpos,oldblob),(cmd,pos,blob) in zip(original,filtered):
        if cmd!=oldcmd or len(blob)!=len(oldblob):raise ValueError('Load command ordering/type changed')
        if cmd==0x19 and bytes(blob[8:24]).startswith(b'__LINKEDIT\0'):
            oldfileoff,oldfilesize=struct.unpack_from('<QQ',oldblob,40)
            fileoff,filesize=struct.unpack_from('<QQ',blob,40);vmsize=struct.unpack_from('<Q',blob,32)[0]
            if fileoff!=oldfileoff or oldfileoff+oldfilesize!=len(source) or fileoff+filesize!=len(built) or vmsize not in {((filesize+4095)//4096)*4096,((filesize+16383)//16384)*16384}:raise ValueError('Unexpected LINKEDIT extent')
            blob[32:40]=oldblob[32:40];blob[48:56]=oldblob[48:56]
        if bytes(blob)!=oldblob:raise ValueError('Load command changed beyond signing sizes')
        output.append(bytes(blob))
    normalized[32:32+oldextent]=b''.join(output)
    if any(source[32+oldextent:32+newextent]):raise ValueError('No zero header padding for signature command')
    normalized[32+oldextent:32+newextent]=b'\0'*16
    if bytes(normalized)!=source:raise ValueError('Native binary content/linkedit mismatch')
    return {'canonicalUnsignedSHA256':sha(source),'packagedSliceSHA256':sha(built),'normalization':'LC_CODE_SIGNATURE+terminal signature+LINKEDIT sizes only'}
