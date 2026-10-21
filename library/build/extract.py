import re,json,zlib,html as H
from lxml import html as LH
DROP_SEC=re.compile(r"^(references|external links|further reading|see also|notes|footnotes|bibliography|sources|citations|works cited|general references|cited sources)$",re.I)
def parse(raw):
    m=re.search(r'"wgCategories":\[(.*?)\]',raw)
    cats=json.loads('['+m.group(1)+']') if m else []
    doc=LH.fromstring(raw)
    for bad in doc.xpath('//script|//style|//sup[contains(@class,"reference")]|//table|//figure|//*[contains(@class,"navbox")]|//*[contains(@class,"hatnote")]|//*[contains(@class,"mw-editsection")]|//*[contains(@class,"reflist")]|//*[contains(@class,"thumb")]|//*[@role="note"]|//style|//link|//math|//*[contains(@class,"sidebar")]|//*[contains(@class,"infobox")]|//*[contains(@class,"metadata")]|//img'):
        if bad.getparent() is not None: bad.drop_tree()
    secs=[];cur={"h":"","t":[]}
    body=doc.xpath('//section|//body')
    root=doc.xpath('//body')[0]
    def txt(e): return re.sub(r'\s+',' ',e.text_content()).strip()
    for el in root.iter():
        if el.tag in('h2','h3','h4'):
            if cur["t"]: secs.append(cur)
            cur={"h":txt(el),"t":[],"lvl":int(el.tag[1])}
        elif el.tag=='p':
            t=txt(el)
            if len(t)>1: cur["t"].append(t)
        elif el.tag=='li' and el.getparent() is not None and el.getparent().tag in('ul','ol') and not el.xpath('.//li'):
            t=txt(el)
            if len(t)>1: cur["t"].append("• "+t)
    if cur["t"]: secs.append(cur)
    out=[]
    skipping=False
    for s in secs:
        if DROP_SEC.match(s["h"]): skipping=True; continue
        if s.get("lvl",2)==2: skipping=False
        if skipping: continue
        body="\n".join(s["t"])
        body=re.sub(r'\[\s*(\d+|[a-z]|citation needed|when\?|who\?|clarification needed)\s*\]','',body)
        if body.strip(): out.append({"h":s["h"],"t":body})
    return cats,out
