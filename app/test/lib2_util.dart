import 'dart:convert';
import 'dart:io';

import 'package:medlog/data.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePP2 extends PathProviderPlatform {
  final String dir;
  FakePP2(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// A temp store with a rotation and a few cases (no screens needed).
Future<String> initStoreLight({Map<String, dynamic> settings = const {}, List<String> dxs = const ['Osteoarthritis', 'Rheumatoid arthritis', 'Hip fracture', 'Acute coronary syndrome']}) async {
  final dir = Directory.systemTemp.createTempSync('medlog2').path;
  PathProviderPlatform.instance = FakePP2(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  void w(String name, Object o) => File('$dir/medlog/$name').writeAsStringSync(jsonEncode(o));
  w('settings.json', {'lang': 'en', 'deviceId': 'x', 'libOnline': false, ...settings});
  final today = DateTime.now();
  w('rotations.json', [
    {'id': 'r1', 'name': 'Orthopedics', 'hospital': 'Al-Shifa', 'start': fmtDate(today.subtract(const Duration(days: 5))), 'end': fmtDate(today.add(const Duration(days: 20)))},
  ]);
  var n = 0;
  for (final dx in dxs) {
    File('$dir/medlog/cases/c$n.json').writeAsStringSync(jsonEncode({
      'id': 'c$n', 'schema': 2, 'created': '2026-10-1${n}T08:00:00Z', 'date': fmtDate(today), 'specialty': 'Orthopedics', 'status': 'Active', 'code': 'ORT-000$n', 'workingDx': dx, 'cc': 'pain',
    }));
    n++;
  }
  await store.init();
  return dir;
}

/// Installs the given text packs of ../library (symlinks) into a fresh store folder.
Directory installPacks(List<String> ids) {
  final base = Directory.systemTemp.createTempSync('lib2base');
  final lib = Directory('${base.path}/library')..createSync(recursive: true);
  final cat = jsonDecode(File('../library/catalog.json').readAsStringSync()) as Map;
  final metas = <Map>[];
  for (final e in cat['packs'] as List) {
    final id = e['id'];
    if (!ids.contains(id)) continue;
    for (final ext in ['idx', 'bin']) {
      Link('${lib.path}/$id.$ext').createSync(File('../library/$id.$ext').absolute.path);
    }
    metas.add({...(e as Map), 'bytes': File('../library/$id.bin').lengthSync() + File('../library/$id.idx').lengthSync()});
  }
  File('${lib.path}/installed.json').writeAsStringSync(jsonEncode(metas));
  return base;
}

/// Serves the catalog and the small packs of ../library on localhost.
Future<HttpServer> serveBuild() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((req) async {
    final f = File('../library${req.uri.path}');
    if (await f.exists()) {
      req.response.add(await f.readAsBytes());
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return server;
}
