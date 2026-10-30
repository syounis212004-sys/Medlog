import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/access.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart';
import 'package:medlog/main.dart';
import 'package:medlog/screens_access.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePP extends PathProviderPlatform {
  final String dir;
  FakePP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

final GlobalKey shotKey = GlobalKey();

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final b = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('test_output/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> initStore(String lang) async {
  final dir = Directory.systemTemp.createTempSync('medlogacc').path;
  PathProviderPlatform.instance = FakePP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  File('$dir/medlog/settings.json')
      .writeAsStringSync(jsonEncode({'lang': lang, 'deviceId': 'x', 'libOnline': false}));
  await store.init();
}

AccessController mk(MemAccessKv kv, DateTime now) => AccessController()
  ..kv = kv
  ..clock = (() => now);

String adminJsonFor(String key, {List<String> revoked = const [], String? rotation}) =>
    jsonEncode({'v': 1, 'adminKey': key, 'name': 'Dr. Admin', 'revoked': revoked, 'minVersion': 0, if (rotation != null) 'rotation': rotation});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 10, 1, 12);

  group('crypto', () {
    test('sign / verify round trip, tamper, wrong device, expiry, revoked', () async {
      final adm = await newKeyPairText();
      final dev = await newKeyPairText();
      final other = await newKeyPairText();
      final req = AccessRequest(newMemberId(), dev.pub, 'Sara Ali', 's@x.com', 'intern', t0);
      final parsed = AccessRequest.parse(req.code)!;
      expect(parsed.name, 'Sara Ali');
      expect(parsed.dev, dev.pub);
      final tok = await signApproval(adm, parsed, 30, t0);

      Future<AccessCheck> v(String t, {String? d, Set<String> rev = const {}, DateTime? now, List<String>? pins}) =>
          verifyApproval(t, pins: pins ?? [adm.pub], devPub: d ?? dev.pub, revoked: rev, now: now ?? t0);

      expect((await v(tok)).status, AccessStatus.valid);
      expect((await v(tok)).approval!.name, 'Sara Ali');
      // tampered payload (extend expiry)
      final p = tok.split('.');
      final m = jsonDecode(utf8.decode(unb64u(p[1]))) as Map<String, dynamic>;
      m['exp'] = (m['exp'] as int) + 99999999;
      final forged = '${p[0]}.${b64u(utf8.encode(jsonEncode(m)))}.${p[2]}';
      expect((await v(forged)).status, AccessStatus.invalid);
      // truncated / garbage
      expect((await v('MLA1.abc.def')).status, AccessStatus.invalid);
      expect((await v('hello')).status, AccessStatus.invalid);
      // wrong device
      expect((await v(tok, d: other.pub)).status, AccessStatus.invalid);
      // signed by another admin key
      final fake = await signApproval(other, parsed, 30, t0);
      expect((await v(fake)).status, AccessStatus.invalid);
      // expiry
      expect((await v(tok, now: t0.add(const Duration(days: 29)))).status, AccessStatus.valid);
      expect((await v(tok, now: t0.add(const Duration(days: 31)))).status, AccessStatus.expired);
      // revoked
      expect((await v(tok, rev: {parsed.id})).status, AccessStatus.revoked);
    });

    test('request code garbage is rejected', () {
      expect(AccessRequest.parse('nope'), isNull);
      expect(AccessRequest.parse('MLREQ1.@@@'), isNull);
    });

    test('admin key backup: right passphrase restores, wrong does not', () async {
      final k = await newKeyPairText();
      final w = await wrapAdminKey(k, 'correct horse');
      expect((await unwrapAdminKey(w, 'correct horse'))!.pub, k.pub);
      expect(await unwrapAdminKey(w, 'wrong'), isNull);
    });
  });

  group('controller', () {
    test('ungated when admin.json is missing or has no key', () async {
      final kv = MemAccessKv();
      final c = mk(kv, t0);
      accessFetch = (_) async => null;
      await c.startup(fetch: false);
      await c.refresh();
      expect(c.gateOn, false);
      expect(c.blocking, false);
      accessFetch = (_) async => '{"v":1,"adminKey":"","revoked":[]}';
      await c.refresh(force: true);
      expect(c.gateOn, false);
      accessFetch = (_) async => 'not json';
      await c.refresh(force: true);
      expect(c.blocking, false);
    });

    test('full flow: pin on first use, request, approve, redeem, revoke, expiry, daily refresh', () async {
      final adminC = mk(MemAccessKv(), t0);
      await adminC.startup(fetch: false);
      await adminC.setupAdmin(name: 'Dr. Admin');
      expect(adminC.isAdmin, true);
      expect(adminC.blocking, false);

      var now = t0;
      var fetches = 0;
      var json = adminJsonFor(adminC.adminPub);
      accessFetch = (_) async {
        fetches++;
        return json;
      };
      final kv = MemAccessKv();
      final c = AccessController()
        ..kv = kv
        ..clock = (() => now);
      await c.startup(fetch: false);
      expect(c.blocking, false);
      await c.refresh();
      expect(c.pins, [adminC.adminPub]);
      expect(c.blocking, true); // gate on, no approval
      expect(c.check.status, AccessStatus.none);

      final req = await c.createRequest('Sara Ali', 's@x.com', '');
      final again = await c.createRequest('Sara Ali', 's@x.com', 'x');
      expect(again.id, req.id); // same member id while pending
      final code = await adminC.approve(AccessRequest.parse(req.code)!, 90);
      expect(await c.redeem('junk'), RedeemResult.invalid);
      expect(await c.redeem(code), RedeemResult.ok);
      expect(c.blocking, false);
      expect(c.daysLeft, 90);
      expect(adminC.members.length, 1);

      // restart: approval persists offline
      final c2 = AccessController()
        ..kv = kv
        ..clock = (() => now);
      accessFetch = (_) async => null;
      await c2.startup(fetch: false);
      expect(c2.blocking, false);
      expect(c2.check.approval!.name, 'Sara Ali');

      // another phone cannot use the same code
      final c3 = mk(MemAccessKv(), now);
      await c3.startup(fetch: false);
      accessFetch = (_) async => adminJsonFor(adminC.adminPub);
      await c3.refresh();
      await c3.createRequest('Eve', 'e@x.com', '');
      expect(await c3.redeem(code), RedeemResult.invalid);

      // daily throttle
      accessFetch = (_) async {
        fetches++;
        return json;
      };
      fetches = 0;
      await c.refresh(); // fetched a moment ago: throttled
      expect(fetches, 0);
      now = now.add(const Duration(hours: 25));
      await c.refresh();
      expect(fetches, 1);
      await c.refresh();
      expect(fetches, 1);

      // revoke on admin, publish, refresh
      await adminC.revoke(req.id);
      json = adminJsonFor(adminC.adminPub, revoked: adminC.revokedIds);
      expect(jsonDecode(adminC.adminJson())['revoked'], [req.id]);
      await c.refresh(force: true);
      expect(c.check.status, AccessStatus.revoked);
      expect(c.blocking, true);
      expect(await adminC.renew(req.id, 30), isNull);

      // expiry (new approved member on c2, offline)
      now = t0;
      final c4 = AccessController()..kv = MemAccessKv()..clock = (() => now);
      await c4.startup(fetch: false);
      json = adminJsonFor(adminC.adminPub);
      await c4.refresh(force: true);
      final r4 = await c4.createRequest('Tom', 't@x.com', '');
      expect(await c4.redeem(await adminC.approve(AccessRequest.parse(r4.code)!, 30)), RedeemResult.ok);
      now = t0.add(const Duration(days: 31));
      await c4.startup(fetch: false);
      expect(c4.check.status, AccessStatus.expired);
      expect(c4.blocking, true);
      // renew restores
      final renewed = await adminC.renew(r4.id, 30);
      now = t0.add(const Duration(days: 31));
      adminC.clock = () => t0.add(const Duration(days: 31));
      final renewed2 = await adminC.renew(r4.id, 30);
      expect(renewed, isNotNull);
      expect(await c4.redeem(renewed2!), RedeemResult.ok);
      expect(c4.blocking, false);

      // sign out
      await c4.signOut();
      expect(c4.blocking, true);
    });

    test('TOFU pin and rotation rule', () async {
      final a = await newKeyPairText();
      final b = await newKeyPairText();
      final evil = await newKeyPairText();
      final c = mk(MemAccessKv(), t0);
      await c.startup(fetch: false);
      expect(await c.applyAdminJson(adminJsonFor(a.pub)), true);
      expect(c.pins, [a.pub]);
      // different key without a rotation: ignored with a warning
      expect(await c.applyAdminJson(adminJsonFor(evil.pub)), false);
      expect(c.pins, [a.pub]);
      expect(c.keyWarning, true);
      // rotation signed by someone else: ignored
      final badRot = await signRotation(evil, evil.pub, t0);
      expect(await c.applyAdminJson(adminJsonFor(evil.pub, rotation: badRot)), false);
      expect(c.pins, [a.pub]);
      // rotation to a different key than the one listed: ignored
      final rotB = await signRotation(a, b.pub, t0);
      expect(await c.applyAdminJson(adminJsonFor(evil.pub, rotation: rotB)), false);
      // valid rotation signed by the pinned key
      expect(await c.applyAdminJson(adminJsonFor(b.pub, rotation: rotB)), true);
      expect(c.pins, [a.pub, b.pub]);
      expect(c.keyWarning, false);
      // survives a restart
      final kv = c.kv;
      final c2 = AccessController()..kv = kv;
      await c2.startup(fetch: false);
      expect(c2.pins, [a.pub, b.pub]);
      expect(c2.gateOn, true);
    });

    test('admin rotateKey produces a rotation members accept; restore on a new phone', () async {
      final adm = mk(MemAccessKv(), t0);
      await adm.startup(fetch: false);
      await adm.setupAdmin(name: 'Dr. Admin');
      final first = adm.adminPub;
      final member = mk(MemAccessKv(), t0);
      await member.startup(fetch: false);
      await member.applyAdminJson(adm.adminJson());
      final bk = await adm.exportAdminBackup('pass phrase');
      final j = await adm.rotateKey();
      expect(adm.adminPub, isNot(first));
      expect(await member.applyAdminJson(j), true);
      expect(member.pins.last, adm.adminPub);
      final fresh = mk(MemAccessKv(), t0);
      await fresh.startup(fetch: false);
      expect(await fresh.restoreAdmin(bk, 'bad'), false);
      expect(await fresh.restoreAdmin(bk, 'pass phrase'), true);
      expect(fresh.adminPub, first);
    });
  });

  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    HttpOverrides.global = null;
  });

  for (final lang in ['en', 'ar']) {
    for (final size in [const Size(412, 892), const Size(360, 640)]) {
      testWidgets('gate $lang ${size.width.toInt()}', (tester) async {
        await tester.runAsync(() => initStore(lang));
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final key = await tester.runAsync(newKeyPairText);
        final kv = MemAccessKv()..m['acc_pins'] = jsonEncode([key!.pub]);
        access
          ..kv = kv
          ..clock = DateTime.now;
        accessFetch = (_) async => null;
        await tester.runAsync(() => access.startup(fetch: false));
        var exported = 0;
        accessExportMyData = (_) async => exported++;
        final shared = <String>[];
        accessShareText = (t) async => shared.add(t);

        await tester.pumpWidget(RepaintBoundary(
            key: shotKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: appLocale,
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(useMaterial3: true, fontFamily: lang == 'ar' ? 'Cairo' : 'Roboto'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
              home: const AccessGate(),
            )));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        final ar = lang == 'ar';
        expect(find.text(ar ? 'تصدير بياناتي' : 'Export my data'), ar ? findsNothing : findsNothing);
        await shot(tester, 'access_gate_${lang}_${size.width.toInt()}');

        // fill the request
        await tester.enterText(find.byType(TextField).at(0), 'Sara Ali');
        await tester.enterText(find.byType(TextField).at(1), 'sara@example.com');
        await tester.ensureVisible(find.byKey(const Key('gate_send')));
        await tester.tap(find.byKey(const Key('gate_send')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(access.pending, isNotNull);
        await tester.scrollUntilVisible(find.byIcon(Icons.share_outlined), 200, scrollable: find.byType(Scrollable).first);
        await shot(tester, 'access_gate_${lang}_${size.width.toInt()}_code');
        // the request was shared at once by the send button; the Share button shares it again
        expect(shared.first, startsWith('MLREQ1.'));
        await tester.tap(find.byIcon(Icons.share_outlined));
        expect(shared.last, startsWith('MLREQ1.'));

        // escape hatch
        await tester.scrollUntilVisible(find.byIcon(Icons.backup_outlined), 300, scrollable: find.byType(Scrollable).first);
        await shot(tester, 'access_gate_${lang}_${size.width.toInt()}_bottom');
        await tester.tap(find.byIcon(Icons.backup_outlined));
        await tester.pump();
        expect(exported, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('MedLogApp: gated phone shows the gate, ungated shows the app; approval opens it', (tester) async {
    await tester.runAsync(() => initStore('en'));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.reset);
    final adm = await tester.runAsync(newKeyPairText);
    final kv = MemAccessKv()..m['acc_pins'] = jsonEncode([adm!.pub]);
    access
      ..kv = kv
      ..clock = DateTime.now;
    accessFetch = (_) async => null;
    accessExportMyData = (_) async {};
    access.loaded = false;
    await tester.pumpWidget(const MedLogApp());
    await tester.runAsync(() => access.startup(fetch: false)); // the app's own start-up hook does this after store.init
    await tester.pump(const Duration(milliseconds: 600));
    expect(access.blocking, true);
    expect(find.byType(AccessGate), findsOneWidget);
    expect(tester.takeException(), isNull);

    // approve this phone and paste the code
    final req = await tester.runAsync(() => access.createRequest('Sara', 's@x.com', ''));
    final code = await tester.runAsync(() => signApproval(adm, AccessRequest.parse(req!.code)!, 30, DateTime.now()));
    final r = await tester.runAsync(() => access.redeem(code!));
    expect(r, RedeemResult.ok);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(AccessGate), findsNothing);
  });
}
