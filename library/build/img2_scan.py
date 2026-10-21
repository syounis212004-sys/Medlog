import pickle,re,os,urllib.parse
from multiprocessing import Pool
from libzim.reader import Archive
from lxml import html as LH
ZIM="/tmp/lib_build/med_maxi.zim"
by=pickle.load(open('/tmp/lib_build/by.pkl','rb'))
BADN=re.compile(r'(?:^|[_\-\s.])(?:icon|flag|logo|symbol|stub|disambig|padlock)s?(?:$|[_\-\s.])|commons-logo|ambox|question_book|^wiki|^(?:crystal_clear|nuvola|edit-clear|red_pencil|blue_pencil|merge-arrow|text_document|folder_hexagonal|loudspeaker|speaker_icon|oojs|ooui|cc-|cc_)',re.I)
BADC=re.compile(r'navbox|ambox|metadata|sidebar|hatnote|mw-editsection|noprint|navigation-not-searchable|side-box|mbox')
def sq(e): return re.sub(r'\s+',' ',e.text_content()).strip()
def scan_art(raw):
    doc=LH.fromstring(raw)
    for bad in doc.xpath('//script|//style|//*[contains(@class,"mw-editsection")]'):
        if bad.getparent() is not None: bad.drop_tree()
    sec='';out=[];seen=set()
    for el in doc.iter():
        if not isinstance(el.tag,str): continue
        if el.tag in('h2','h3','h4'): sec=sq(el);continue
        if el.tag!='img': continue
        cl=el.get('class') or ''
        if 'mw-file-element' not in cl: continue
        try: w=int(el.get('data-file-width') or 0)
        except: w=0
        if w<150: continue
        if el.get('data-file-type') not in('bitmap','drawing'): continue
        src=el.get('src') or ''
        if not src or re.search(r'\.svg',src,re.I): continue
        bad=False;cap='';fig=None
        for a in el.iterancestors():
            c=a.get('class') or ''
            if BADC.search(c): bad=True;break
            if fig is None and a.tag=='figure': fig=a
        if bad: continue
        p=src
        while p.startswith('./') or p.startswith('/'): p=p[1:] if p.startswith('/') else p[2:]
        fn=urllib.parse.unquote(p.split('/')[-1])
        if BADN.search(fn) or fn in seen: continue
        if fig is not None:
            fc=fig.find('.//figcaption')
            if fc is not None: cap=sq(fc)
        if not cap:
            for a in el.iterancestors():
                c=a.get('class') or ''
                if 'thumb' in c or 'infobox' in c or a.tag=='table':
                    tc=a.xpath('.//*[contains(@class,"thumbcaption") or contains(@class,"infobox-caption")]')
                    if tc: cap=sq(tc[0]);break
                    if 'thumb' in c: break
        seen.add(fn);out.append((p,fn,sec,cap[:300]))
        if len(out)>=12: break
    return out
def scan(job):
    cid,items=job
    z=Archive(ZIM);res=[]
    for title,path,secs in items:
        try: raw=bytes(z.get_entry_by_path(path).get_item().content).decode('utf8','ignore')
        except Exception: continue
        try: r=scan_art(raw)
        except Exception: continue
        for p,fn,sec,cap in r: res.append((cid,title,p,fn,sec,cap))
    return res
if __name__=="__main__":
    jobs=[(c,items[k:k+300]) for c,items in by.items() for k in range(0,len(items),300)]
    found=[]
    with Pool(4) as pool:
        for i,r in enumerate(pool.imap_unordered(scan,jobs)):
            found+=r
            if i%20==0: print(i,len(jobs),len(found),flush=True)
    pickle.dump(found,open('/tmp/lib_build/figs.pkl','wb'))
    print("figures",len(found),"files",len({f[3] for f in found}),"articles",len({(f[0],f[1]) for f in found}),flush=True)
