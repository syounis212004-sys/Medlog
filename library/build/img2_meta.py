import pickle,json,os,re,time,urllib.request,urllib.parse,html as H,threading
from concurrent.futures import ThreadPoolExecutor
UA="MedLogBuild/1.0 (offline educational medical packs; contact ftreanoure@gmail.com)"
figs=pickle.load(open('/tmp/lib_build/figs.pkl','rb'))
names=sorted({f[3] for f in figs})
OUTF='/tmp/lib_build/commons_meta3.json'
meta=json.load(open(OUTF)) if os.path.exists(OUTF) else {}
old=json.load(open('/tmp/lib_build/commons_meta2.json'))
def clean_author(a):
    a=a.split("|")[0].strip()
    a=re.sub(r"\s*\(See[^)]*\).*$","",a).strip(" *.")
    if a.startswith("Unknown author"): return ""
    if "=" in a or len(a)<2 or a.lower() in("permission","unknown","none","own","self"): return ""
    return a[:90]
for fn,m in old.items():
    if m and fn not in meta: meta[fn]={"exists":True,"author":clean_author(m["author"]),"lic":m["lic"]}
todo=[n for n in names if n not in meta]
print("names",len(names),"todo",len(todo),flush=True)
lock=threading.Lock()
def fetch(fn):
    u="https://commons.wikimedia.org/w/index.php?title="+urllib.parse.quote("File:"+fn.replace(' ','_'))+"&action=raw"
    for k in range(8):
        try:
            r=urllib.request.urlopen(urllib.request.Request(u,headers={"User-Agent":UA}),timeout=30)
            return r.read().decode('utf8','ignore')
        except urllib.error.HTTPError as e:
            if e.code==404: return None
            if e.code==429:
                try: ra=int(e.headers.get('Retry-After','30'))
                except: ra=30
                time.sleep(ra+5+k*5);continue
            time.sleep(5)
        except Exception: time.sleep(5)
    return ''
LIC=[
 (r'cc-by-sa-(\d\.\d)',lambda m:f'CC BY-SA {m.group(1)}'),
 (r'cc-by-(\d\.\d)',lambda m:f'CC BY {m.group(1)}'),
 (r'cc-zero|cc0|cc-0',lambda m:'CC0'),
 (r'pd-[a-z0-9\-]+|public domain|\{\{pd\}\}',lambda m:'Public domain'),
]
BAD=re.compile(r'\{\{\s*(copyvio|no permission|speedy|delete|npd|no source|non-free|fair use)')
def parse(txt):
    low=txt.lower()
    if BAD.search(low): return {"exists":False,"author":"","lic":"","why":"flagged"}
    lic=''
    for rx,f in LIC:
        m=re.search(rx,low)
        if m: lic=f(m);break
    a=re.search(r'\|\s*author\s*=\s*(.*?)(?=\n\s*\||\n\}\})',txt,re.I|re.S)
    au=a.group(1) if a else ''
    au=re.sub(r'\{\{[Uu]ser at project\|([^|}]+)[^}]*\}\}',r'\1',au)
    au=re.sub(r'\{\{[Cc]reator:([^}]+)\}\}',r'\1',au)
    au=re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]+)\]\]',r'\1',au)
    au=re.sub(r'\[https?://\S+\s+([^\]]+)\]',r'\1',au)
    au=re.sub(r'\{\{[^}]*\}\}','',au)
    au=re.sub(r"<[^>]+>|'''?",'',au)
    au=H.unescape(re.sub(r'\s+',' ',au)).strip(' |.')
    au=clean_author(au)
    own=re.search(r'\|\s*source\s*=\s*\{\{\s*own',low) is not None
    if not au and own: au='Wikimedia Commons contributor (own work)'
    return {"exists":True,"author":au,"lic":lic}
done=0
def work(fn):
    global done
    txt=fetch(fn)
    if txt=='': return
    r={"exists":False,"author":"","lic":"","why":"404"} if txt is None else parse(txt)
    with lock:
        meta[fn]=r
        done+=1
        if done%200==0:
            json.dump(meta,open(OUTF+'.tmp','w'));os.replace(OUTF+'.tmp',OUTF);print("done",done,"/",len(todo),flush=True)
    time.sleep(0.05)
with ThreadPoolExecutor(6) as ex: list(ex.map(work,todo))
json.dump(meta,open(OUTF+'.tmp','w'));os.replace(OUTF+'.tmp',OUTF)
print("finished",len(meta),"missing",len([n for n in names if n not in meta]),flush=True)
