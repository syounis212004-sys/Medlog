import 'templates_data.dart';

/// One-tap structured starters for the history and the examination.
/// Clinical text stays in English on purpose (it is what you write in the chart).
class CaseTemplate {
  final String label;
  final String hpi;
  final String exam;
  final bool mine;
  const CaseTemplate(this.label, {this.hpi = '', this.exam = '', this.mine = false});
}

const String _socrates = 'Site: \nOnset: \nCharacter: \nRadiation: \nAssociations: \n'
    'Time course: \nExacerbating/relieving: \nSeverity: \n';

const Map<String, List<CaseTemplate>> kTemplates = {
  'Internal Medicine': [
    CaseTemplate('Chest pain', hpi: _socrates +
        'Cardiac risk factors: \nExertional? Pleuritic? Positional? \nSOB / sweating / palpitations: \n',
        exam: 'CVS: S1 S2, murmurs, JVP, peripheral pulses\nResp: air entry, added sounds\nCalves: tenderness / swelling\n'),
    CaseTemplate('Shortness of breath', hpi: 'Onset (sudden / gradual): \nExertional / at rest: \nOrthopnea / PND: \n'
        'Cough / sputum / wheeze: \nFever: \nLeg swelling: \nPast chest disease: \n',
        exam: 'Resp rate, work of breathing, SpO2\nChest: expansion, percussion, breath sounds\nCVS: JVP, edema, heart sounds\n'),
    CaseTemplate('Abdominal pain', hpi: _socrates + 'Nausea / vomiting: \nBowel habit: \nUrinary symptoms: \nLast meal: \n',
        exam: 'Inspection: distension, scars\nPalpation: tenderness, guarding, rebound\nMasses / organomegaly: \nBowel sounds: \n'),
    CaseTemplate('Fever', hpi: 'Duration / pattern: \nRigors: \nLocalizing symptoms (cough, dysuria, diarrhea, rash): \n'
        'Sick contacts / travel: \nMedications / immunosuppression: \n',
        exam: 'Temp, HR, BP, RR\nENT / chest / abdomen / skin / meningism\n'),
    CaseTemplate('Diabetes review', hpi: 'Type / duration: \nTreatment: \nHypoglycemia episodes: \nHome glucose readings: \n'
        'Complications screen (eyes, kidneys, feet, neuropathy): \n',
        exam: 'BMI, BP\nFeet: pulses, sensation, ulcers\nFundus if available: \n'),
  ],
  'Emergency': [
    CaseTemplate('Primary survey (ABCDE)',
        hpi: 'Mechanism / time of event: \nPre-hospital treatment: \nAMPLE (Allergies, Meds, Past hx, Last meal, Events): \n',
        exam: 'A - Airway + C-spine: \nB - Breathing (RR, SpO2, chest): \nC - Circulation (HR, BP, CRT, bleeding): \n'
            'D - Disability (GCS, pupils, glucose): \nE - Exposure / temp: \n'),
    CaseTemplate('Chest pain', hpi: _socrates + 'Risk factors: \nECG done at: \n',
        exam: 'CVS / Resp / peripheral pulses both arms\nECG: \n'),
    CaseTemplate('Abdominal pain', hpi: _socrates + 'Vomiting / bowel / urinary: \nLMP (females): \n',
        exam: 'Tenderness site, guarding, rebound\nHernial orifices, DRE if indicated\n'),
    CaseTemplate('Head injury', hpi: 'Mechanism: \nLOC / amnesia: \nVomiting / seizure: \nAnticoagulants: \n',
        exam: 'GCS: \nPupils: \nScalp / skull / base of skull signs: \nNeuro deficit: \n'),
  ],
  'Orthopedics': [
    CaseTemplate('Fracture / injury', hpi: 'Mechanism of injury: \nTime of injury: \nHand dominance: \n'
        'Pain / swelling / deformity: \nPrevious injury to same site: \n',
        exam: 'Look: swelling, deformity, wounds (open?), bruising\nFeel: tenderness, warmth, pulses, cap refill\n'
            'Move: active / passive ROM\nNeurovascular status distal to injury: \nJoint above and below: \n'),
    CaseTemplate('Joint pain', hpi: _socrates + 'Morning stiffness: \nSwelling / redness: \nFever / systemic: \nPrevious episodes: \n',
        exam: 'Look / Feel / Move\nEffusion, warmth, erythema\nSpecial tests: \n'),
    CaseTemplate('Back pain', hpi: _socrates + 'Red flags: trauma, weight loss, fever, night pain, cancer hx: \n'
        'Bladder / bowel / saddle numbness: \nLeg weakness / sciatica: \n',
        exam: 'Spine: tenderness, ROM\nNeuro LL: power, tone, reflexes, sensation\nSLR: \nDRE / saddle sensation if indicated: \n'),
  ],
  'General Surgery': [
    CaseTemplate('Acute abdomen', hpi: _socrates + 'Vomiting: \nBowels / flatus: \nPrevious abdominal surgery: \nLast meal: \n',
        exam: 'Inspection / palpation / percussion / auscultation\nPeritonism: \nHernial orifices: \nDRE: \n'),
    CaseTemplate('Wound / abscess', hpi: 'Site: \nDuration: \nDischarge / fever: \nDiabetes / immunosuppression: \nTetanus status: \n',
        exam: 'Size, erythema, fluctuance, warmth\nSurrounding cellulitis: \nNeurovascular: \n'),
    CaseTemplate('Pre-operative', hpi: 'Planned procedure: \nIndication: \nComorbidities: \nAnesthesia history: \nNPO since: \n',
        exam: 'Airway, heart, chest\nSite marked / consent: \n'),
  ],
  'Pediatrics': [
    CaseTemplate('Fever in a child', hpi: 'Duration / max temp: \nFeeding / wet diapers: \nCough / cold / ear pulling: \n'
        'Vomiting / diarrhea: \nRash: \nVaccinations: \nSick contacts: \n',
        exam: 'General: alert, playful, hydration\nENT / chest / abdomen / skin\nFontanelle / meningism: \nCRT: \n'),
    CaseTemplate('Vomiting / diarrhea', hpi: 'Duration / frequency: \nBlood / mucus: \nIntake / urine output: \nSick contacts: \n',
        exam: 'Hydration: eyes, mucosa, skin turgor, CRT\nAbdomen: \nWeight: \n'),
    CaseTemplate('Respiratory distress', hpi: 'Onset: \nCough / wheeze / stridor: \nFever: \nFeeding: \nAsthma / atopy: \n',
        exam: 'RR, retractions, nasal flaring, SpO2\nChest: air entry, wheeze, crackles\n'),
  ],
  'OB/GYN': [
    CaseTemplate('Antenatal visit', hpi: 'G / P / A: \nLMP / EDD / GA: \nFetal movements: \nBleeding / leaking / contractions: \n'
        'Headache / visual / epigastric pain: \n',
        exam: 'BP, urine protein, weight\nFundal height, lie, presentation\nFHR: \nEdema: \n'),
    CaseTemplate('Vaginal bleeding', hpi: 'Amount (pads/hour): \nPregnant? LMP: \nPain: \nDischarge: \nContraception: \n',
        exam: 'Vitals, pallor\nAbdomen: tenderness, uterine size\nSpeculum / bimanual if indicated: \n'),
  ],
};

List<CaseTemplate> builtInTemplatesFor(String specialty) => kTemplates[specialty] ?? kTemplatesExtra[specialty] ?? const [];
