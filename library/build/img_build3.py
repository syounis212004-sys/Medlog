import pickle,re,json,os,io,time,gzip,hashlib,urllib.request,urllib.parse,html as H,sys,collections
from multiprocessing import Pool
from libzim.reader import Archive
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
ZIM="/tmp/lib_build/med_maxi.zim"
OUT="/tmp/lib_build/img_out";os.makedirs(OUT,exist_ok=True)
UA="MedLogBuild/1.0 (offline educational medical packs; contact ftreanoure@gmail.com)"
found=pickle.load(open('/tmp/lib_build/lead_imgs.pkl','rb'))
meta=json.load(open('/tmp/lib_build/commons_meta2.json'))
def clean_author(a):
    a=a.split("|")[0].strip()
    a=re.sub(r"\s*\(See[^)]*\).*$","",a).strip(" *.")
    if "=" in a or len(a)<2 or a.lower() in("permission","unknown","none"): return "Unknown author — see the file page"
    return a[:90]
allowed={fn:(clean_author(m["author"]),m["lic"]) for fn,m in meta.items() if m}
print("allowed files",len(allowed),"of",len(meta),flush=True)
def proc(args):
    cid,title,p,fn=args
    try:
        z=Archive(ZIM)
        data=bytes(z.get_entry_by_path(p).get_item().content)
        im=Image.open(io.BytesIO(data));im.seek(0)
        if im.mode in("P","LA","RGBA"):
            im=im.convert("RGBA");bg=Image.new("RGB",im.size,(255,255,255));bg.paste(im,mask=im.split()[3]);im=bg
        else: im=im.convert("RGB")
        w,h=im.size
        if w<160: return None
        im.thumbnail((320,320))
        buf=io.BytesIO();im.save(buf,"WEBP",quality=52,method=5)
        return (cid,title,fn,buf.getvalue())
    except Exception as e:
        return None
jobs=[(c,t,p,f) for c,t,p,f,_ in found if f in allowed]
print("jobs",len(jobs),flush=True)
res=collections.defaultdict(list)
with Pool(4) as pool:
    for k,r in enumerate(pool.imap_unordered(proc,jobs,chunksize=20)):
        if r: res[r[0]].append(r[1:])
        if k%1000==0: print("img",k,flush=True)
tot=0;cat=[]
for cid,items in sorted(res.items()):
    items.sort(key=lambda x:x[0].lower())
    blob=bytearray();T=[];O=[];N=[];C=[];F=[]
    for title,fn,data in items:
        T.append(title);O.append(len(blob));N.append(len(data));blob+=data
        a,l=allowed[fn];C.append(f"{a} — {l}");F.append(fn)
    idx=gzip.compress(json.dumps({"meta":{"id":cid+"-images","kind":"images","for":cid},"t":T,"o":O,"n":N,"c":C,"f":F},ensure_ascii=False,separators=(',',':')).encode(),9,mtime=0)
    open(f"{OUT}/{cid}-images.img","wb").write(blob);open(f"{OUT}/{cid}-images.imx","wb").write(idx)
    cat.append({"id":cid+"-images","for":cid,"count":len(T),"bytes":len(blob)+len(idx),"sha256_bin":hashlib.sha256(blob).hexdigest(),"sha256_idx":hashlib.sha256(idx).hexdigest(),"img":cid+"-images.img","imx":cid+"-images.imx"})
    tot+=len(blob)+len(idx);print(f"{cid:28s}{len(T):6d} {(len(blob)+len(idx))/1e6:7.2f} MB",flush=True)
json.dump(cat,open(f"{OUT}/images_catalog.json","w"),indent=1)
print("TOTAL",tot/1e6,"MB")
