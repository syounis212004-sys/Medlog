import pickle,json,os,io,gzip,hashlib,collections,sys
from multiprocessing import Pool
from libzim.reader import Archive
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
ZIM="/tmp/lib_build/med_maxi.zim";OUT="/tmp/lib_build/img2_out"
MAXS=int(os.environ.get("MAXS","360"));Q=int(os.environ.get("Q","50"));Q2=int(os.environ.get("Q2","40"))
figs=pickle.load(open('/tmp/lib_build/figs.pkl','rb'))
meta=json.load(open('/tmp/lib_build/commons_meta3.json'))
_z=None
def proc(a):
    global _z
    p,fn=a
    try:
        if _z is None: _z=Archive(ZIM)
        data=bytes(_z.get_entry_by_path(p).get_item().content)
        im=Image.open(io.BytesIO(data));im.seek(0)
        if im.mode in("P","LA","RGBA","PA"):
            im=im.convert("RGBA");bg=Image.new("RGB",im.size,(255,255,255));bg.paste(im,mask=im.split()[3]);im=bg
        else: im=im.convert("RGB")
        if im.size[0]<160: return (fn,None)
        im.thumbnail((MAXS,MAXS))
        b=io.BytesIO();im.save(b,"WEBP",quality=Q,method=5);d=b.getvalue()
        if len(d)>40000:
            b=io.BytesIO();im.save(b,"WEBP",quality=Q2,method=5);d=b.getvalue()
        return (fn,d)
    except Exception: return (fn,None)
def credit(m):
    a,l=m.get("author",""),m.get("lic","")
    if a and l: return f"{a} — {l}"
    return a or l or "Wikimedia Commons"
if __name__=="__main__":
    by=collections.defaultdict(lambda:collections.defaultdict(list));path={}
    for cid,t,p,fn,sec,cap in figs:
        m=meta.get(fn)
        if not m or not m["exists"]: continue
        by[cid][t].append((fn,sec,cap));path[fn]=p
    report=[];tot=0;nimg=0;narts=0;bad=0;unk=0
    for cid in sorted(by):
        fns=sorted({fn for l in by[cid].values() for fn,_,_ in l})
        blobs={}
        with Pool(4) as pool:
            for fn,d in pool.imap_unordered(proc,[(path[f],f) for f in fns],chunksize=16):
                if d: blobs[fn]=d
        bad+=len(fns)-len(blobs)
        blob=bytearray();pos={}
        for fn in fns:
            if fn in blobs: pos[fn]=(len(blob),len(blobs[fn]));blob+=blobs[fn]
        T=[];A=[];cnt=0
        for t in sorted(by[cid],key=lambda s:s.lower()):
            L=[]
            for fn,sec,cap in by[cid][t]:
                if fn not in pos: continue
                m=meta[fn];o,n=pos[fn]
                L.append({"o":o,"n":n,"s":sec,"c":cap,"f":fn,"u":credit(m)})
                if not m["author"]: unk+=1
            if L: T.append(t);A.append(L);cnt+=len(L)
        idx=gzip.compress(json.dumps({"meta":{"id":cid+"-images","kind":"images","for":cid,"v":2},"v":2,"t":T,"a":A},ensure_ascii=False,separators=(',',':')).encode(),9,mtime=0)
        open(f"{OUT}/{cid}-images.img","wb").write(blob);open(f"{OUT}/{cid}-images.imx","wb").write(idx)
        report.append({"id":cid+"-images","for":cid,"arts":len(T),"count":cnt,"blob":len(blob),"idx":len(idx),"sha256_bin":hashlib.sha256(blob).hexdigest(),"sha256_idx":hashlib.sha256(idx).hexdigest()})
        tot+=len(blob)+len(idx);nimg+=cnt;narts+=len(T)
        print(f"{cid:28s}{len(T):6d} {cnt:6d} {(len(blob)+len(idx))/1e6:7.2f} MB",flush=True)
    json.dump({"packs":report,"unknown_author":unk,"decode_fail":bad},open(f"{OUT}/build_report.json","w"),indent=1)
    print("TOTAL",tot/1e6,"MB imgs",nimg,"arts",narts,"unk",unk,"decodefail",bad)
