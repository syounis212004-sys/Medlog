import re,html,json,gzip,hashlib,xml.etree.ElementTree as ET
from lxml import html as LH
import sys
sys.path.insert(0,'/tmp/lib_build')
t=ET.parse('/tmp/mp.xml').getroot()
items=[]
def clean(h):
    """Returns sections [(heading, text)]: <h2>/<h3> start a new section."""
    d=LH.fromstring('<div>'+h+'</div>')
    secs=[];head="";buf=[]
    def flush():
        nonlocal buf
        if buf: secs.append((head,"\n".join(buf)))
        buf=[]
    for el in d.iterchildren(tag=("p","ul","ol","div","h2","h3","h4")):
        if el.tag in("h2","h3","h4"):
            flush(); head=re.sub(r'\s+',' ',el.text_content()).strip(); continue
        if el.tag in('ul','ol'):
            for li in el.findall('.//li'): buf.append('• '+re.sub(r'\s+',' ',li.text_content()).strip())
        else:
            x=re.sub(r'\s+',' ',el.text_content()).strip()
            if x and not x.startswith('NIH:'): buf.append(x)
    flush()
    return secs
for ht in t.iter('health-topic'):
    if ht.get('language')!='English': continue
    title=ht.get('title');url=ht.get('url')
    secs=[]
    parts=clean(html.unescape(ht.findtext('full-summary') or ''))
    if not parts: continue
    for h,b in parts: secs.append({"h":h,"t":b})
    also=[a.text for a in ht.findall('also-called') if a.text]
    if also: secs.append({"h":"Also called","t":", ".join(also)})
    groups=[g.text for g in ht.findall('group') if g.text]
    if groups: secs.append({"h":"Topic groups","t":", ".join(groups)})
    rel=[r.text for r in ht.findall('related-topic') if r.text]
    if rel: secs.append({"h":"Related topics","t":", ".join(rel)})
    secs.append({"h":"Source","t":"MedlinePlus, National Library of Medicine (public domain summary). "+url})
    items.append((title,url,secs))
print(len(items))

import os
os.makedirs('/tmp/lib_build/out',exist_ok=True)
exec(open('/tmp/lib_build/wp_lib.py').read().replace("from build_packs import COURSES,GENERAL",""))
e=write("medlineplus","MedlinePlus (patient information)","Patient information",items,"Public domain (US government work); some MedlinePlus images and drug monographs excluded","MedlinePlus Health Topics, National Library of Medicine","Plain-language health topics from MedlinePlus: what patients are told. Useful for patient education and communication practice.",kind="medline")
print(e['count'],e['bytes']/1e6,"MB")
json.dump(e,open('/tmp/lib_build/medline_entry.json','w'))
