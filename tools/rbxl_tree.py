import struct, sys, os, lz4.block, zstandard
F=sys.argv[1]; OUT=sys.argv[2]
data=open(F,'rb').read()
pos=32
def read_refs(b, n):
    # interleaved int32, zigzag-ish transform, then accumulate
    vals=[]
    for i in range(n):
        v=(b[i]<<24)|(b[n+i]<<16)|(b[2*n+i]<<8)|b[3*n+i]
        v=(v>>1)^(-(v&1))
        vals.append(v)
    out=[];acc=0
    for v in vals:
        acc+=v; out.append(acc)
    return out
classes={}; inst_class={}; props={}; parents={}
while pos < len(data):
    name=data[pos:pos+4]; clen,ulen=struct.unpack('<II',data[pos+4:pos+12]); pos+=16
    if clen==0:
        body=data[pos:pos+ulen]; pos+=ulen
    else:
        raw=data[pos:pos+clen]; pos+=clen
        if raw[:4]==b'\x28\xb5\x2f\xfd': body=zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen)
        else: body=lz4.block.decompress(raw, uncompressed_size=ulen)
    if name==b'INST':
        cid,=struct.unpack('<I',body[0:4]); l,=struct.unpack('<I',body[4:8]); cname=body[8:8+l].decode()
        p=8+l+1; n,=struct.unpack('<I',body[p:p+4]); p+=4
        refs=read_refs(body[p:p+4*n], n)
        classes[cid]=(cname,refs)
        for r in refs: inst_class[r]=cname
    elif name==b'PROP':
        cid,=struct.unpack('<I',body[0:4]); l,=struct.unpack('<I',body[4:8]); pname=body[8:8+l].decode(); p=8+l
        t=body[p]; p+=1
        if t==1 and pname in ('Name','Source','Text'):
            refs=classes[cid][1]; vals=[]
            for r in refs:
                sl,=struct.unpack('<I',body[p:p+4]); vals.append(body[p+4:p+4+sl]); p+=4+sl
            for r,v in zip(refs,vals): props.setdefault(r,{})[pname]=v
    elif name==b'PRNT':
        n,=struct.unpack('<I',body[1:5])
        ch=read_refs(body[5:5+4*n],n); pa=read_refs(body[5+4*n:5+8*n],n)
        for c,pp in zip(ch,pa): parents[c]=pp
    elif name==b'END\x00': break
def path(r):
    parts=[]
    while r is not None and r!=-1 and r in inst_class:
        parts.append(props.get(r,{}).get('Name',b'?').decode('utf8','replace')); r=parents.get(r)
    return '/'.join(reversed(parts))
n=0
for r,c in inst_class.items():
    src=props.get(r,{}).get('Source')
    if c in ('Script','LocalScript','ModuleScript') and src is not None:
        p=path(r).replace('/','__')[:180]
        open(os.path.join(OUT,f'{p}.{c}.lua'),'wb').write(src); n+=1
print('scripts:',n, 'instances:', len(inst_class))
with open(os.path.join(OUT,'..','tree.txt'),'w') as f:
    for r,c in inst_class.items():
        pr=props.get(r,{})
        t=pr.get('Text')
        f.write(f"{path(r)} [{c}]" + (f" Text={t.decode('utf8','replace')!r}" if t else "") + "\n")
