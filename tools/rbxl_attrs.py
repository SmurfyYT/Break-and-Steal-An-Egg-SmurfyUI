# Dumps every instance of a saved place (.rbxl) with its class, position,
# tags, attributes and a few text properties (ActionText, ObjectText, Value).
# usage: python3 tools/rbxl_attrs.py place.rbxl out.txt [path-prefix]
import struct, sys, lz4.block, zstandard
F=sys.argv[1]; OUT=sys.argv[2]; PREFIX=sys.argv[3] if len(sys.argv)>3 else ''
data=open(F,'rb').read(); pos=32
def refs_(b,n):
    out=[];acc=0
    for i in range(n):
        v=(b[i]<<24)|(b[n+i]<<16)|(b[2*n+i]<<8)|b[3*n+i]; acc+=(v>>1)^(-(v&1)); out.append(acc)
    return out
def floats_(b,n):
    out=[]
    for i in range(n):
        v=(b[i]<<24)|(b[n+i]<<16)|(b[2*n+i]<<8)|b[3*n+i]; v=((v>>1)|((v&1)<<31))&0xffffffff
        out.append(struct.unpack('>f',struct.pack('>I',v))[0])
    return out
def ints_(b,n):
    out=[]
    for i in range(n):
        v=(b[i]<<24)|(b[n+i]<<16)|(b[2*n+i]<<8)|b[3*n+i]; out.append((v>>1)^(-(v&1)))
    return out
def attrs(blob):
    try:
        p=0; n,=struct.unpack('<I',blob[0:4]); p=4; out={}
        def s():
            nonlocal p
            l,=struct.unpack('<I',blob[p:p+4]); v=blob[p+4:p+4+l]; p+=4+l; return v.decode('utf8','replace')
        for _ in range(n):
            k=s(); t=blob[p]; p+=1
            if t==2: v=s()
            elif t==3: v=bool(blob[p]); p+=1
            elif t==5: v=struct.unpack('<f',blob[p:p+4])[0]; p+=4
            elif t==6: v=struct.unpack('<d',blob[p:p+8])[0]; p+=8
            elif t==9: v='UDim'; p+=8
            elif t==10: v='UDim2'; p+=16
            elif t==14: v='Brick'; p+=4
            elif t==15: v='Color3(%.2f,%.2f,%.2f)'%struct.unpack('<fff',blob[p:p+12]); p+=12
            elif t==16: v='V2(%.1f,%.1f)'%struct.unpack('<ff',blob[p:p+8]); p+=8
            elif t==17: v='V3(%.1f,%.1f,%.1f)'%struct.unpack('<fff',blob[p:p+12]); p+=12
            elif t==20:
                x=struct.unpack('<fff',blob[p:p+12]); p+=12; rid=blob[p]; p+=1
                if rid==0: p+=36
                v='CF(%.1f,%.1f,%.1f)'%x
            elif t==23:
                c,=struct.unpack('<I',blob[p:p+4]); p+=4+12*c; v='NumSeq'
            elif t==25:
                c,=struct.unpack('<I',blob[p:p+4]); p+=4+20*c; v='ColSeq'
            elif t==27: v='NumRange(%g,%g)'%struct.unpack('<ff',blob[p:p+8]); p+=8
            elif t==28: v='Rect'; p+=16
            elif t==33: s(); p+=3; s(); v='Font'
            else: out[k]='?type%d'%t; break
            out[k]=v
        return out
    except Exception as e: return {'_err':str(e)}
classes={}; ic={}; P={}; par={}; cf={}
WANT=('Name','Tags','AttributesSerialize','ActionText','ObjectText','Value','Text')
while pos<len(data):
    name=data[pos:pos+4]; clen,ulen=struct.unpack('<II',data[pos+4:pos+12]); pos+=16
    if clen==0: body=data[pos:pos+ulen]; pos+=ulen
    else:
        raw=data[pos:pos+clen]; pos+=clen
        body=zstandard.ZstdDecompressor().decompress(raw,max_output_size=ulen) if raw[:4]==b'\x28\xb5\x2f\xfd' else lz4.block.decompress(raw,uncompressed_size=ulen)
    if name==b'INST':
        cid,=struct.unpack('<I',body[0:4]); l,=struct.unpack('<I',body[4:8]); cn=body[8:8+l].decode()
        p=8+l+1; n,=struct.unpack('<I',body[p:p+4]); p+=4; r=refs_(body[p:p+4*n],n); classes[cid]=(cn,r)
        for x in r: ic[x]=cn
    elif name==b'PROP':
        cid,=struct.unpack('<I',body[0:4]); l,=struct.unpack('<I',body[4:8]); pn=body[8:8+l].decode(); p=8+l
        t=body[p]; p+=1; r=classes[cid][1]; n=len(r)
        if t==1 and pn in WANT:
            for x in r:
                sl,=struct.unpack('<I',body[p:p+4]); P.setdefault(x,{})[pn]=body[p+4:p+4+sl]; p+=4+sl
        elif t==0x10 and pn=='CFrame':
            for x in r:
                rid=body[p]; p+=1
                if rid==0: p+=36
            xs=floats_(body[p:p+4*n],n); p+=4*n; ys=floats_(body[p:p+4*n],n); p+=4*n; zs=floats_(body[p:p+4*n],n)
            for x,a,b,c in zip(r,xs,ys,zs): cf[x]=(a,b,c)
        elif t==0x0E and pn=='size':
            xs=floats_(body[p:p+4*n],n); p+=4*n; ys=floats_(body[p:p+4*n],n); p+=4*n; zs=floats_(body[p:p+4*n],n)
            for x,a,b,c in zip(r,xs,ys,zs): P.setdefault(x,{})['Size']=(a,b,c)
        elif t==0x04 and pn=='Value':
            for x,v in zip(r,floats_(body[p:p+4*n],n)): P.setdefault(x,{})['NumValue']=v
        elif t==0x03 and pn=='Value':
            for x,v in zip(r,ints_(body[p:p+4*n],n)): P.setdefault(x,{})['NumValue']=v
        elif t==0x02 and pn=='Value':
            for x,v in zip(r,body[p:p+n]): P.setdefault(x,{})['NumValue']=bool(v)
    elif name==b'PRNT':
        n,=struct.unpack('<I',body[1:5]); ch=refs_(body[5:5+4*n],n); pa=refs_(body[5+4*n:5+8*n],n)
        for c,pp in zip(ch,pa): par[c]=pp
    elif name==b'END\x00': break
def path(r):
    parts=[]
    while r is not None and r!=-1 and r in ic:
        parts.append(P.get(r,{}).get('Name',b'?').decode('utf8','replace')); r=par.get(r)
    return '/'.join(reversed(parts))
with open(OUT,'w') as f:
    for r,c in ic.items():
        pa=path(r)
        if not pa.startswith(PREFIX): continue
        pr=P.get(r,{}); line=f"{pa} [{c}]"
        if r in cf: line+=" @(%.1f,%.1f,%.1f)"%cf[r]
        if 'Size' in pr: line+=" size=(%.1f,%.1f,%.1f)"%pr['Size']
        if pr.get('Tags'): line+=" tags="+",".join(x.decode() for x in pr['Tags'].split(b'\0') if x)
        for k in ('ActionText','ObjectText','Text','Value'):
            if pr.get(k): line+=f" {k}={pr[k].decode('utf8','replace')!r}"
        if 'NumValue' in pr: line+=f" Value={pr['NumValue']}"
        if pr.get('AttributesSerialize') and len(pr['AttributesSerialize'])>4: line+=" attrs="+repr(attrs(pr['AttributesSerialize']))
        f.write(line+"\n")
