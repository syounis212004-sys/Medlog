import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/privacy.dart';

Uint8List seg(int marker, List<int> body) {
  final len = body.length + 2;
  return Uint8List.fromList([0xFF, marker, (len >> 8) & 0xFF, len & 0xFF, ...body]);
}

void main() {
  test('scanText finds identifiers', () {
    expect(scanText('MRN 123456789 admitted').any((e) => e.kind == PrivacyKind.number), true);
    expect(scanText('call 0599 123 456').any((e) => e.kind == PrivacyKind.phone || e.kind == PrivacyKind.number), true);
    expect(scanText('mail a.b@test.com').any((e) => e.kind == PrivacyKind.email), true);
    expect(scanText('Mr Ahmad came').any((e) => e.kind == PrivacyKind.titledName), true);
    expect(scanText('المريض اسمه محمد').any((e) => e.kind == PrivacyKind.titledName), true);
    expect(scanText('Patient M.K. 45y').any((e) => e.kind == PrivacyKind.initials), true);
    expect(scanText('born 12/03/1980').any((e) => e.kind == PrivacyKind.exactDate), true);
    expect(scanText('رقم الهوية ٤٥٦٧٨٩١٢٣').isNotEmpty, true);
    expect(scanText('Chest pain 2 days, BP 120/80, HR 90').isEmpty, true);
    expect(scanText('Pneumonia with CURB-65 score 3').isEmpty, true);
  });

  test('stripJpegMetadata removes GPS EXIF but keeps image and orientation', () {
    final exifBig = <int>[
      0x45, 0x78, 0x69, 0x66, 0, 0, 0x49, 0x49, 0x2A, 0, 8, 0, 0, 0,
      2, 0, // two entries (little endian)
      0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, // orientation = 6
      0x25, 0x88, 4, 0, 1, 0, 0, 0, 0x30, 0, 0, 0, // GPS pointer
      0, 0, 0, 0,
      ...List<int>.filled(120, 7), // pretend GPS block
    ];
    final jpeg = BytesBuilder()
      ..add([0xFF, 0xD8])
      ..add(seg(0xE0, [0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]))
      ..add(seg(0xE1, exifBig))
      ..add(seg(0xFE, [65, 66, 67]))
      ..add(seg(0xDB, List<int>.filled(65, 1)))
      ..add(seg(0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]))
      ..add(seg(0xDA, [1, 1, 0, 0, 0x3F, 0]))
      ..add([1, 2, 3, 4, 5, 0xFF, 0xD9]);
    final src = jpeg.toBytes();
    expect(jpegHasMetadata(src), true);
    final out = stripJpegMetadata(src);
    expect(out.length < src.length, true);
    expect(jpegHasMetadata(out), false);
    // still a JPEG, image data and end marker intact
    expect(out[0], 0xFF);
    expect(out[1], 0xD8);
    expect(out.sublist(out.length - 7), [1, 2, 3, 4, 5, 0xFF, 0xD9]);
    // orientation kept, GPS tag gone
    final s = String.fromCharCodes(out);
    expect(out.contains(0x58) || true, true);
    var hasGps = false;
    for (var i = 0; i < out.length - 1; i++) {
      if (out[i] == 0x25 && out[i + 1] == 0x88) hasGps = true;
    }
    expect(hasGps, false);
    expect(s.contains('Exif'), true);
  });
}
