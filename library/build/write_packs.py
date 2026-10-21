import pickle,json,gzip,hashlib,os,sys
sys.path.insert(0,'/tmp/lib_build')
from build_packs import COURSES,GENERAL
by=pickle.load(open('/tmp/lib_build/by.pkl','rb'))
OUT='/tmp/lib_build/out'
os.makedirs(OUT,exist_ok=True)
titles_map={c[0]:c[1] for c in COURSES};titles_map[GENERAL[0]]=GENERAL[1]
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
for pid,items in sorted(by.items()):
    its=[(t,"https://en.wikipedia.org/wiki/"+path,secs) for t,path,secs in items]
    e=write(pid,titles_map[pid],titles_map[pid],its,"CC BY-SA 4.0","Wikipedia (WikiProject Medicine, via Kiwix, text only)","Medical articles from Wikipedia, text only (no images or tables).")
    cat.append(e);tot+=e["bytes"]
    print(f"{pid:28s}{e['count']:6d} {e['bytes']/1e6:7.2f} MB")
print("TOTAL",tot/1e6,"MB",sum(e['count'] for e in cat))
json.dump({"version":1,"packs":cat},open(f"{OUT}/catalog.json","w"),indent=1)
