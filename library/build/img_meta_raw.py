import pickle,json,os,re,time,urllib.request,urllib.parse,html as H,threading
from concurrent.futures import ThreadPoolExecutor
UA="MedLogBuild/1.0 (offline educational medical packs; contact ftreanoure@gmail.com)"
found=pickle.load(open('/tmp/lib_build/lead_imgs.pkl','rb'))
names=sorted({f for _,_,_,f,_ in found})
OUTF='/tmp/lib_build/commons_meta2.json'
meta=json.load(open(OUTF)) if os.path.exists(OUTF) else {}
todo=[n for n in names if n not in meta]
print("todo",len(todo),flush=True)
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
                ra=int(e.headers.get('Retry-After','30'));time.sleep(ra+5+k*5);continue
            time.sleep(5)
        except Exception: time.sleep(5)
    return ''
LIC=[
 (r'cc-by-sa-(\d\.\d)',lambda m:f'CC BY-SA {m.group(1)}'),
 (r'cc-by-(\d\.\d)',lambda m:f'CC BY {m.group(1)}'),
 (r'cc-zero|cc0|cc-0',lambda m:'CC0'),
 (r'pd-[a-z0-9\-]+|public domain|\{\{pd\}\}',lambda m:'Public domain'),
]
def parse(txt):
    low=txt.lower()
    if re.search(r'non-?free|fair use|cc-by-nc|cc-nc|cc-by-nd|noncommercial|no derivative|\{\{copyvio|\{\{no permission|\{\{npd|\{\{no source|\{\{speedy|\{\{delete',low): return None
    lic=None
    for rx,f in LIC:
        m=re.search(rx,low)
        if m: lic=f(m);break
    if not lic: return None
    a=re.search(r'\|\s*author\s*=\s*(.*?)(?=\n\s*\||\n\}\})',txt,re.I|re.S)
    au=a.group(1) if a else ''
    au=re.sub(r'\{\{[Uu]ser at project\|([^|}]+)[^}]*\}\}',r'\1',au)
    au=re.sub(r'\{\{[Cc]reator:([^}]+)\}\}',r'\1',au)
    au=re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]+)\]\]',r'\1',au)
    au=re.sub(r'\[https?://\S+\s+([^\]]+)\]',r'\1',au)
    au=re.sub(r'\{\{[^}]*\}\}','',au)
    au=re.sub(r"<[^>]+>|'''?",'',au)
    au=H.unescape(re.sub(r'\s+',' ',au)).strip(' |.')
    if not au or au.lower() in('unknown','own','self','{{own}}'): au=''
    own=re.search(r'\|\s*source\s*=\s*\{\{\s*own',low) is not None
    if not au and own: au='Wikimedia Commons contributor (own work)'
    if not au: au='Unknown author — see the file page'
    return {"lic":lic,"author":au[:90]}
done=0
def work(fn):
    global done
    txt=fetch(fn)
    r=None if not txt else parse(txt)
    with lock:
        meta[fn]=r if txt is not None else None
        done+=1
        if done%50==0:
            json.dump(meta,open(OUTF,'w'));print("done",done,"/",len(todo),flush=True)
    time.sleep(0.05)
with ThreadPoolExecutor(6) as ex: list(ex.map(work,todo))
json.dump(meta,open(OUTF,'w'))
print("finished",sum(1 for v in meta.values() if v),"usable of",len(meta),flush=True)
