import struct, sys, lz4.block, zstandard
F=sys.argv[1]
data=open(F,'rb').read()
pos=32
def read_refs(b, n):
    vals=[]
    for i in range(n):
        v=(b[i]<<24)|(b[n+i]<<16)|(b[2*n+i]<<8)|b[3*n+i]
        vals.append((v>>1)^(-(v&1)))
    out=[];acc=0
    for v in vals: acc+=v; out.append(acc)
    return out
def read_floats(b, n):
    out=[]
    for i in range(n):
        v=(b[i]<<24)|(b[n+i]<<16)|(b[2*n+i]<<8)|b[3*n+i]
        v=((v>>1)|((v&1)<<31))&0xffffffff
        out.append(struct.unpack('>f',struct.pack('>I',v))[0])
    return out
classes={}; inst_class={}; props={}; parents={}; cf={}; tags={}
while pos < len(data):
    name=data[pos:pos+4]; clen,ulen=struct.unpack('<II',data[pos+4:pos+12]); pos+=16
    if clen==0: body=data[pos:pos+ulen]; pos+=ulen
    else:
        raw=data[pos:pos+clen]; pos+=clen
        body=zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen) if raw[:4]==b'\x28\xb5\x2f\xfd' else lz4.block.decompress(raw, uncompressed_size=ulen)
    if name==b'INST':
        cid,=struct.unpack('<I',body[0:4]); l,=struct.unpack('<I',body[4:8]); cname=body[8:8+l].decode()
        p=8+l+1; n,=struct.unpack('<I',body[p:p+4]); p+=4
        refs=read_refs(body[p:p+4*n], n); classes[cid]=(cname,refs)
        for r in refs: inst_class[r]=cname
    elif name==b'PROP':
        cid,=struct.unpack('<I',body[0:4]); l,=struct.unpack('<I',body[4:8]); pname=body[8:8+l].decode(); p=8+l
        t=body[p]; p+=1; refs=classes[cid][1]; n=len(refs)
        if t==1 and pname in ('Name','Tags'):
            for r in refs:
                sl,=struct.unpack('<I',body[p:p+4]); v=body[p+4:p+4+sl]; p+=4+sl
                if pname=='Name': props.setdefault(r,{})['Name']=v
                else: tags[r]=[x.decode('utf8','replace') for x in v.split(b'\0') if x]
        elif t==0x10 and pname=='CFrame':
            for r in refs:
                rid=body[p]; p+=1
                if rid==0: p+=36
            xs=read_floats(body[p:p+4*n],n); p+=4*n
            ys=read_floats(body[p:p+4*n],n); p+=4*n
            zs=read_floats(body[p:p+4*n],n)
            for r,x,y,z in zip(refs,xs,ys,zs): cf[r]=(x,y,z)
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
for r,(x,y,z) in cf.items():
    print("%s [%s] %.1f %.1f %.1f %s" % (path(r), inst_class[r], x,y,z, ",".join(tags.get(r,[]))))
