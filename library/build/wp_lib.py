import pickle,json,gzip,hashlib,os,sys
sys.path.insert(0,'/tmp/lib_build')
from build_packs import COURSES,GENERAL
by={}
OUT='/tmp/lib_build/out'
os.makedirs(OUT,exist_ok=True)

DATE="2026-10-01"
cat=[];tot=0
def lead(secs):
    for s in secs:
        t=s["t"].replace("\n"," ").strip()
        if t: return (t[:180]+"…") if len(t)>180 else t
    return ""
def write(pid,title,course,items,license,source,desc,kind="wiki"):
    items=sorted(items,key=lambda x:x[0].lower())
    bin_=bytearray();T=[];L=[];O=[];N=[]
    for t,url,secs in items:
        m=gzip.compress(json.dumps({"t":t,"u":url,"s":secs},ensure_ascii=False,separators=(',',':')).encode(),9,mtime=0)
        T.append(t);L.append(lead(secs));O.append(len(bin_));N.append(len(m));bin_+=m
    meta={"id":pid,"title":title,"course":course,"count":len(items),"date":DATE,"license":license,"source":source,"kind":kind,"desc":desc}
    idx=gzip.compress(json.dumps({"meta":meta,"t":T,"l":L,"o":O,"n":N},ensure_ascii=False,separators=(',',':')).encode(),9,mtime=0)
    open(f"{OUT}/{pid}.bin","wb").write(bin_);open(f"{OUT}/{pid}.idx","wb").write(idx)
    e=dict(meta,bytes=len(bin_)+len(idx),idx=f"{pid}.idx",bin=f"{pid}.bin",sha256_bin=hashlib.sha256(bin_).hexdigest(),sha256_idx=hashlib.sha256(idx).hexdigest())
    return e
