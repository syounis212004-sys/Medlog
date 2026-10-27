import 'dart:typed_data';

import 'data.dart';
import 'search_index.dart' show normText;

/// Privacy guard. Everything here runs on the phone and nothing is sent anywhere.
/// It looks for the kinds of details that can identify a patient even when the
/// name is missing (long numbers, phone numbers, initials, exact dates, titles
/// followed by a name...) and removes hidden location data from photos.

enum PrivacyKind { number, phone, email, titledName, initials, exactDate, address, idWord }

class PrivacyIssue {
  final PrivacyKind kind;
  final String match;
  final String field; // case field key, or a list name
  const PrivacyIssue(this.kind, this.match, this.field);
}

final RegExp _long = RegExp(r'(?<![\d.])\d{6,}(?![\d.])');
final RegExp _phone = RegExp(r'(?<!\d)(\+?\d{1,3}[\s\-]?)?(\(?\d{2,4}\)?[\s\-]?)\d{3}[\s\-]?\d{3,4}(?!\d)');
final RegExp _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
final RegExp _titled = RegExp(r'\b(Mr|Mrs|Ms|Miss|Dr|Prof|Sir|Madam)\.?\s+[A-Z][a-z]{2,}');
final RegExp _titledAr = RegExp('(السيد|السيدة|الآنسة|الاستاذ|الأستاذ|الحاج|الحاجة|المرحوم|المرحومة|المدعو|المدعوة|اسمه|اسمها)\\s+[ء-ي]{2,}');
final RegExp _initials = RegExp(r'\b[A-Z]\.\s?[A-Z]\.(\s?[A-Z]\.)?');
final RegExp _date = RegExp(r'\b(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2})\b');
final RegExp _address = RegExp(r'\b(street|st\.|road|rd\.|avenue|camp|village)\b|شارع|مخيم|قرية|حارة|عمارة', caseSensitive: false);
final RegExp _idWord = RegExp(r'\b(MRN|file\s?(no|number)|ID\s?(no|number)|passport)\b|رقم الملف|رقم الهوية|رقم الهويه|جواز', caseSensitive: false);

/// Text fields of a case that are free text.
const List<String> kFreeTextFields = [
  'cc', 'hpi', 'pmh', 'psh', 'drugs', 'allergies', 'family', 'social', 'ros', 'examGeneral', 'examSystemic',
  'examFocused', 'problems', 'ddx', 'workingDx', 'finalDx', 'redFlags', 'reasoning', 'followUp', 'outcome',
  'initialDx', 'whatChanged', 'learned', 'mistakes', 'questions', 'refs', 'teaching',
];

List<PrivacyIssue> scanText(String text, {String field = ''}) {
  final t = text;
  if (t.trim().isEmpty) return const [];
  final n = normText(t); // Arabic-Indic digits become 0-9
  final out = <PrivacyIssue>[];
  void add(PrivacyKind k, Iterable<RegExpMatch> ms, String src) {
    for (final m in ms.take(3)) {
      out.add(PrivacyIssue(k, src.substring(m.start, m.end).trim(), field));
    }
  }

  add(PrivacyKind.number, _long.allMatches(n), n);
  final phones = _phone.allMatches(n).where((m) => RegExp(r'\d').allMatches(n.substring(m.start, m.end)).length >= 8);
  for (final m in phones.take(2)) {
    final s = n.substring(m.start, m.end).trim();
    // a long digit run is already reported as a number
    if (!out.any((e) => e.kind == PrivacyKind.number && s.contains(e.match))) {
      out.add(PrivacyIssue(PrivacyKind.phone, s, field));
    }
  }
  add(PrivacyKind.email, _email.allMatches(t), t);
  add(PrivacyKind.titledName, _titled.allMatches(t), t);
  add(PrivacyKind.titledName, _titledAr.allMatches(t), t);
  add(PrivacyKind.initials, _initials.allMatches(t), t);
  add(PrivacyKind.exactDate, _date.allMatches(n), n);
  add(PrivacyKind.address, _address.allMatches(t), t);
  add(PrivacyKind.idWord, _idWord.allMatches(t), t);
  return out;
}

final Map<String, List<PrivacyIssue>> _memo = {};

/// Issues across every free-text field and list entry of a case. Results are
/// remembered per case version, so scanning many cases stays fast.
List<PrivacyIssue> scanCase(CaseRec c) {
  final key = '${c.id}|${c.s('updated')}|${store.useInitials}';
  final hit = _memo[key];
  if (hit != null) return hit;
  final out = <PrivacyIssue>[];
  for (final f in kFreeTextFields) {
    out.addAll(scanText(c.s(f), field: f));
  }
  for (final l in ['inv', 'mgmt', 'progress', 'evo']) {
    for (final e in c.lst(l)) {
      for (final v in e.values) {
        if (v is String) out.addAll(scanText(v, field: l));
      }
    }
  }
  for (final i in c.lst('images')) {
    out.addAll(scanText('${i['caption'] ?? ''} ${i['interpretation'] ?? ''}', field: 'images'));
  }
  if (_memo.length > 400) _memo.clear();
  _memo[key] = out;
  return out;
}

String kindLabel(PrivacyKind k) {
  switch (k) {
    case PrivacyKind.number:
      return 'Long number (ID / file number?)';
    case PrivacyKind.phone:
      return 'Phone number';
    case PrivacyKind.email:
      return 'Email address';
    case PrivacyKind.titledName:
      return 'Title followed by a name';
    case PrivacyKind.initials:
      return 'Initials';
    case PrivacyKind.exactDate:
      return 'Exact date in the text';
    case PrivacyKind.address:
      return 'Place or address word';
    case PrivacyKind.idWord:
      return 'ID / file number wording';
  }
}

// ---------------------------------------------------------------- photos: hidden metadata

/// Removes EXIF (camera, time, GPS location...) and comment segments from a JPEG.
/// Image data is not re-encoded, so quality is untouched. The orientation flag is
/// kept (alone) so the photo does not turn sideways. Other formats are returned as is.
Uint8List stripJpegMetadata(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return b;
  final out = BytesBuilder();
  out.add([0xFF, 0xD8]);
  var i = 2;
  int? orientation;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) break;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xDA) {
      // start of scan: the rest is image data
      break;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) return b; // damaged: leave it alone
    final seg = b.sublist(i, i + 2 + len);
    if (marker == 0xE1) {
      orientation ??= _exifOrientation(seg);
    }
    final keep = marker == 0xE0 || // JFIF
        marker == 0xDB || // quantization tables
        marker == 0xC0 || marker == 0xC1 || marker == 0xC2 || marker == 0xC4 || // frames / huffman
        marker == 0xDD || // restart interval
        (marker == 0xE2 && _isIcc(seg)) ||
        (marker >= 0xC3 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC);
    if (keep) out.add(seg);
    i += 2 + len;
  }
  if (orientation != null && orientation != 1) {
    out.add(_orientationOnlyExif(orientation));
  }
  out.add(b.sublist(i));
  return out.toBytes();
}

bool _isIcc(Uint8List seg) {
  const tag = 'ICC_PROFILE';
  if (seg.length < 18) return false;
  for (var k = 0; k < tag.length; k++) {
    if (seg[4 + k] != tag.codeUnitAt(k)) return false;
  }
  return true;
}

int? _exifOrientation(Uint8List seg) {
  // seg: FF E1 len len 'Exif' 0 0 TIFF...
  if (seg.length < 22) return null;
  const exif = [0x45, 0x78, 0x69, 0x66, 0, 0];
  for (var k = 0; k < 6; k++) {
    if (seg[4 + k] != exif[k]) return null;
  }
  final t = 10; // start of TIFF header inside seg
  final big = seg[t] == 0x4D;
  int u16(int o) => big ? (seg[o] << 8) | seg[o + 1] : (seg[o + 1] << 8) | seg[o];
  int u32(int o) => big
      ? (seg[o] << 24) | (seg[o + 1] << 16) | (seg[o + 2] << 8) | seg[o + 3]
      : (seg[o + 3] << 24) | (seg[o + 2] << 16) | (seg[o + 1] << 8) | seg[o];
  if (t + 8 > seg.length) return null;
  final ifd = t + u32(t + 4);
  if (ifd + 2 > seg.length) return null;
  final count = u16(ifd);
  for (var e = 0; e < count; e++) {
    final o = ifd + 2 + e * 12;
    if (o + 12 > seg.length) return null;
    if (u16(o) == 0x0112) return u16(o + 8);
  }
  return null;
}

Uint8List _orientationOnlyExif(int orientation) {
  final body = <int>[
    0x45, 0x78, 0x69, 0x66, 0, 0, // "Exif\0\0"
    0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8, // big endian TIFF header, IFD0 at 8
    0, 1, // one entry
    0x01, 0x12, 0, 3, 0, 0, 0, 1, (orientation >> 8) & 0xFF, orientation & 0xFF, 0, 0,
    0, 0, 0, 0, // no next IFD
  ];
  final len = body.length + 2;
  return Uint8List.fromList([0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF, ...body]);
}

/// True when a JPEG still carries EXIF data other than the plain orientation flag.
bool jpegHasMetadata(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return false;
  var i = 2;
  while (i + 4 <= b.length && b[i] == 0xFF) {
    final marker = b[i + 1];
    if (marker == 0xDA) break;
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2) break;
    if (marker == 0xFE) return true;
    if (marker == 0xE1) {
      // our own orientation-only block is 38 bytes long
      if (len > 40) return true;
    }
    i += 2 + len;
  }
  return false;
}
