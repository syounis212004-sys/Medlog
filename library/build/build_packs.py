import sys,re,json,gzip,hashlib,os,collections,time
from multiprocessing import Pool
sys.path.insert(0,'/tmp/lib_build')
from extract import parse
from libzim.reader import Archive
ZIM="/tmp/lib_build/med_nopic.zim"
OUT="/tmp/lib_build/out"
os.makedirs(OUT,exist_ok=True)
R=lambda s:re.compile(s,re.I)
COURSES=[ # (id,title,regex on category names)
("orthopedics","Orthopedics",R(r"orthop|fracture|skeletal|joint|musculoskeletal|arthr|tendon|ligament|spine|spinal|sports injur|osteo|bone|rheumat(?!o)|dislocation|limb|amputation|prosthe|scolio|cartilage")),
("cardiology","Cardiology",R(r"cardi|heart|vascular|arrhythm|hypertens|coronary|aort|valv|circulat|thromb|embol|artery disease|vein diseases|angio")),
("pulmonology","Pulmonology",R(r"respirat|pulmon|lung|asthma|bronch|pneumon|airway|ventilat|tuberculosis|pleur|cough|apnea")),
("gastroenterology","Gastroenterology",R(r"gastro|digestive|liver|hepat|intestin|bowel|colon|esophag|stomach|pancrea|biliary|gallbladder|celiac|colitis|crohn|rectal|anal ")),
("nephrology-urology","Nephrology & Urology",R(r"kidney|renal|nephr|urolog|urinary|bladder|prostat|urethr|dialysis|incontinence")),
("endocrinology","Endocrinology",R(r"endocrin|diabet|thyroid|hormon|adrenal|pituitar|metabolic|obesity|insulin|parathyroid|steroid|growth")),
("neurology","Neurology",R(r"neuro|brain|nervous system|epilep|seizure|dementia|parkinson|stroke|cerebr|migraine|headache|sclerosis|spinal cord|cranial|myopath|palsy|encephal|meningi")),
("psychiatry","Psychiatry",R(r"psychiat|mental|psycholog|anxiety|depress|schizo|bipolar|psychosis|autism|adhd|addiction|substance|eating disorder|personality|antidepress|antipsychot|anxiolytic|mood|sleep disorder|behavio")),
("infectious-diseases","Infectious Diseases",R(r"infect|bacterial dis|viral dis|parasit|fungal|pathogenic|sepsis|antibiotic|antiviral|antimicrob|antifung|hiv|aids|hepatitis|malaria|zoono|tropical|vaccin|sexually transmitted|covid|influenza|epidemic|pandemic")),
("hematology-oncology","Hematology & Oncology",R(r"hematolog|blood|anemia|leukemia|lymphoma|cancer|oncolog|tumou?r|neoplas|chemotherap|antineoplastic|carcinoma|sarcoma|coagul|transfusion|myeloma|radiotherap")),
("pediatrics","Pediatrics",R(r"pediatr|paediatr|child|infant|neonat|congenital|newborn|adolescen|genetic|chromosom|syndromes|inborn")),
("obstetrics-gynecology","Obstetrics & Gynecology",R(r"obstet|gynaec|gynec|pregnan|childbirth|labou?r|contracepti|menstru|ovar|uter|cervi|breast|women's health|midwif|fertility|prenatal|reproductive|abortion|menopause|sexual")),
("surgery","General Surgery",R(r"surgery|surgical|operation|suture|transplant|wound|hernia|appendic|anastom|laparosc|bariatric|plastic|burn|trauma")),
("emergency-critical-care","Emergency & Critical Care",R(r"emergenc|intensive care|critical care|resuscit|poison|toxicolog|overdose|shock|trauma|first aid|life support|antidote|envenom|bite|sting")),
("dermatology","Dermatology",R(r"dermat|skin|cutaneous|hair|nail|acne|psoria|eczema|rash|pigment|melan|derm")),
("ophthalmology","Ophthalmology",R(r"ophthalm|eye|vision|retina|cornea|glaucoma|cataract|optic|ocular|blind|refractive")),
("ent","ENT (Ear, Nose, Throat)",R(r"otorhinolaryng|otolaryng|ear|hearing|audiolog|nose|nasal|throat|laryn|pharyn|sinus|tonsil|deaf|vestibul|dentist|oral|dental|tooth|teeth|mouth|jaw")),
("anesthesiology","Anesthesiology & Pain",R(r"anesth|anaesth|analges|pain|sedat|opioid|neuromuscular block|nerve block|local anesthetic")),
("radiology","Radiology & Imaging",R(r"imaging|radiolog|radiograph|ultraso|tomograph|\bMRI\b|magnetic resonance|x-ray|nuclear medicine|radiologic|scintigraph|doppler|echocardio")),
("pharmacology","Pharmacology",R(r"pharmac|drug|medication|antagonist|agonist|inhibitor|blocker|antibiotic|essential medicines|anticoag|antihyperten|anti-inflammatory|nsaid|antihistamine|diuretic|statin|vaccine|hormonal|immunosuppress|anticonvuls|ATC code|therapeutic|dosage|prodrug|medicines")),
("rheumatology-immunology","Rheumatology & Immunology",R(r"rheumat|autoimmun|immun|allerg|lupus|vasculitis|arthritis|connective tissue|hypersensitiv|inflammat|transplant rejection")),
("anatomy-physiology","Anatomy & Physiology",R(r"anatom|physiolog|histolog|embryolog|human body|organ system|muscles of|arteries of|veins of|nerves of|bones of|cell biology|reflex|human cells|tissue|biochem|metabolism|genetics|cytolog|electrophysiolog")),
("pathology-laboratory","Pathology & Laboratory",R(r"patholog|laborator|blood test|medical test|diagnos|biopsy|cytolog|biomarker|urinalysis|assay|microbiolog|bacteriolog|virolog|parasitolog|clinical chemistry|screening|tests")),
("public-health","Public Health & Nutrition",R(r"public health|epidemiolog|prevent|nutrition|diet|vitamin|sanitation|health policy|health care|occupational|environmental health|global health|biostatistic|medical ethics|health informatics|clinical trial|evidence-based|research")),
("signs-symptoms","Signs & Symptoms",R(r"symptom|medical sign|signs and symptoms|syndrome|medical terminology|clinical sign|radiologic signs|medical mnemonic|physical examination|vital sign")),
]
TAXA=R(r"(bacteria described in|genera|monotypic|candidatus|gram-(negative|positive) bacteria|fungus species|species|taxa|marine microorganisms|halophiles|thermophiles|psychrophiles|cyanobacteria|archaea|virus genera|aceae$|ales$|streptomyces|penicillium|aspergillus|apicomplexa|actinomycet|clostridium$|chryseobacterium|microbacterium|nocardioides|anaerobes|extremophile|plant pathogens|plant disease|animal viral|veterinary|viral plant|fish|mammal|insect|taxon|plants)")
CLIN_KEEP=R(r"(pathogenic bacteria|bacterial diseases|infectious diseases|zoonoses|tropical diseases|human diseases|medical signs|medical tests|diseases and disorders|syndromes)")
CHEM=R(r"(compounds$|chembox|drugboxes|designer drugs|abandoned drugs|experimental drugs|withdrawn drugs|pihkal|tihkal|psychedelic|entactogens|euphoriants|substituted amphetamines|phenethylamines|tryptamines|cannabinoids|research chemicals|-arenes?$|esters$|amines$|alcohols$|ethers$|ketones$|amides$|heterocycles|piperidines|pyridines|indoles|nitriles|imidazoles|thiophenes|phenols$|diols|ureas|lactams|designer prodrugs|norepinephrine-dopamine|serotonin releasing|receptor (agonists|antagonists|modulators)$|releasing agents)")
CLIN_DRUG=R(r"(essential medicines|antibiotic|antiviral|analgesic|antineoplastic|antihypertensive|anticoagul|antidepress|antipsychotic|anticonvuls|antidiabetic|statin|beta blockers|diuretic|corticosteroid|glucocorticoid|vaccine|nonsteroidal|anesthetic|antiemetic|antihistamine|monoclonal antibod|immunosuppress|hormonal|contraceptive|bronchodilator|antimalarial|anthelmintic|antifungal|sedative|anxiolytic|hypnotic|opioid|ATC code [A-V])")
MED=R(r"(disease|disorder|syndrome|medical|medicine|drug|surg|anatom|physiolog|health|clinical|therap|treatment|diagnos|symptom|sign|cancer|infect|vaccin|hormon|antibiotic|ology|vessel|muscle|bone|nerve|gland|blood|organ|cell|pain|injur|pregnan|child|patholog|emergenc|toxic|poison|immun|genetic|epidemi|virus|bacteri|parasit|fung|nutrition|vitamin|dental|tooth|skin|eye|ear|nose|brain|heart|lung|liver|kidney|stomach|bowel)")
ORG=R(r"(universit|medical schools?|schools? of|alumni|people|births|deaths|organi[sz]ations|associations|societies|councils|charit|compan|hospitals|ambulance|health care in|healthcare in|health in |medicine in|by country|policy|policies|laws|legislation|politic|history of|in culture|society and culture|awards|journals|books|museums|buildings|outbreaks|pandemic by|epidemics in|fictional|films|television|popular culture|military|regulat|agencies|ministr|government|foundations|institutes|conferences|medical education|training|curricul|professions|occupations|nurses|physicians|doctors|surgeons|scientists|biograph|disasters|lawsuits|scandals|pseudoscience|alternative medicine|quackery|conspiracy|controvers|medical ethics|pharmaceutical industry|drug policy|drug culture|recreational drug|illicit|cannabis|trade)")
ORGTITLE=re.compile(r"\b(University|Hospital|Association|Society|Council|College|Institute|Foundation|Ministry|Agency|Organi[sz]ation|Federation|Academy|Authority|Commission|Board|Union|Center|Centre|Charity|Trust|Act)\b|^(\d{4}\b|Health in |Healthcare in |Health care in |Medicine in |Women's health in )|(in society and culture|outbreak in|pandemic in)")
GENERAL=("general-medicine","General Medicine")
def classify(cats):
    cs=[c for c in cats if not re.search(r"(articles|wikidata|dates|CS1|pages|use .* dates|short description|webarchive|wikipedia|infobox|commons|templates|containing|lacking|using|missing|unsourced|redirects|ISBN|citation|source attribution|dynamic lists|chembox|drugboxes)",c,re.I)]
    keep_clin=any(CLIN_KEEP.search(c) for c in cs)
    if any(TAXA.search(c) for c in cs) and not keep_clin: return None
    if any(CHEM.search(c) for c in cs) and not any(CLIN_DRUG.search(c) for c in cs): return None
    if not any(MED.search(c) for c in cs): return None
    if any(ORG.search(c) for c in cs): return None
    best=None;bs=0
    for cid,title,rx in COURSES:
        s=sum(1 for c in cs if rx.search(c))
        if s>bs: bs=s;best=cid
    return best or GENERAL[0]
def work(args):
    lo,hi=args
    z=Archive(ZIM)
    out=[]
    for i in range(lo,hi):
        try:
            e=z._get_entry_by_id(i)
            if e.is_redirect: continue
            it=e.get_item()
            if not it.mimetype.startswith('text/html'): continue
            raw=bytes(it.content).decode('utf8','ignore')
            m=re.search(r'"wgCategories":\[(.*?)\]',raw)
            if not m: continue
            cats=json.loads('['+m.group(1)+']')
            if any(re.search(r"(disambiguation|^Lists? of|^List of|redirects)",c,re.I) for c in cats) or e.title.startswith(('List of','Lists of','Index of','Outline of')) or ORGTITLE.search(e.title): continue
            cid=classify(cats)
            if not cid: continue
            c2,secs=parse(raw)
            text="".join(s["t"] for s in secs)
            if len(text)<500: continue
            secs=secs[:40]
            out.append((cid,e.title,e.path,secs))
        except Exception as ex:
            pass
    return out
if __name__=="__main__":
    z=Archive(ZIM);n=z.entry_count;del z
    step=4000
    jobs=[(a,min(a+step,n)) for a in range(0,n,step)]
    t0=time.time()
    by=collections.defaultdict(list)
    with Pool(4) as p:
        for k,res in enumerate(p.imap_unordered(work,jobs)):
            for cid,t,path,secs in res: by[cid].append((t,path,secs))
            print(k+1,len(jobs),sum(len(v) for v in by.values()),int(time.time()-t0),flush=True)
    import pickle
    pickle.dump(dict(by),open('/tmp/lib_build/by.pkl','wb'))
    print({k:len(v) for k,v in by.items()})
