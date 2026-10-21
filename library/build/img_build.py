import pickle,re,json,os,io,time,gzip,hashlib,urllib.request,urllib.parse,html as H,sys
from multiprocessing import Pool
from libzim.reader import Archive
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
ZIM="/tmp/lib_build/med_maxi.zim"
OUT="/tmp/lib_build/img_out";os.makedirs(OUT,exist_ok=True)
UA="MedLogBuild/1.0 (offline educational medical packs; contact ftreanoure@gmail.com)"
by=pickle.load(open('/tmp/lib_build/by.pkl','rb'))
def lead_img(raw):
    # only the lead: before the first top-level section heading
    cut=raw.find('<h2')
    head=raw if cut<0 else raw[:cut]
    for m in re.finditer(r'<img[^>]*class="mw-file-element"[^>]*>',head):
        t=m.group(0)
        src=re.search(r'src="([^"]+)"',t); w=re.search(r'data-file-width="(\d+)"',t); ty=re.search(r'data-file-type="(\w+)"',t)
        if not src or not w or int(w.group(1))<200: continue
        if ty and ty.group(1) not in('bitmap','drawing'): continue
        if re.search(r'\.svg',src.group(1),re.I): continue
        alt=re.search(r'alt="([^"]*)"',t)
        return src.group(1),(alt.group(1) if alt else '')
    return None
def scan(job):
    cid,items=job
    z=Archive(ZIM);out=[]
    for title,path,secs in items:
        try:
            raw=bytes(z.get_entry_by_path(path).get_item().content).decode('utf8','ignore')
        except Exception: continue
        r=lead_img(raw)
        if not r: continue
        src,alt=r
        p=src.lstrip('./')
        fn=urllib.parse.unquote(p.split('/')[-1])
        out.append((cid,title,p,fn,alt))
    return out
if __name__=="__main__":
    jobs=[]
    for cid,items in by.items():
        for k in range(0,len(items),500): jobs.append((cid,items[k:k+500]))
    found=[]
    with Pool(4) as pool:
        for r in pool.imap_unordered(scan,jobs): found+=r
    print("articles with lead image",len(found),flush=True)
    pickle.dump(found,open('/tmp/lib_build/lead_imgs.pkl','wb'))
