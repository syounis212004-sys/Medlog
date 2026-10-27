import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'secure_kv.dart';

// Access control by administrator-signed approval codes.
//
// No server, no account, no patient data involved. The administrator holds an Ed25519 key;
// the public half is published in the repository file below. A member's phone shows a
// request code (name, email, its own public key); the administrator signs an approval
// code that is bound to that phone and has an expiry date. Everything is verified offline.
//
// This is SOFT access control: it keeps casual users out and gives accountability, it is
// not DRM (the APK is public). See /tmp/eval/ACCESS_REPORT.md.

/// Where the phone looks for the administrator's public key. Missing file or no key: the app
/// is not gated (exactly as before).
const String kAdminJsonUrl =
    'https://raw.githubusercontent.com/syounis212004-sys/Medlog/main/library/admin.json';

/// Seam for tests: returns the body, or null when unreachable / not found.
Future<String?> Function(String url) accessFetch = _httpFetch;

Future<String?> _httpFetch(String url) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'MedLog (offline medical logbook)');
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    return body.length > 200000 ? null : body;
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

/// Key-value storage seam (SecureKv on the phone, a map in tests).
abstract class AccessKv {
  Future<String?> read(String k);
  Future<void> write(String k, String v);
  Future<void> delete(String k);
}

class SecureAccessKv implements AccessKv {
  @override
  Future<String?> read(String k) => SecureKv.read(k);
  @override
  Future<void> write(String k, String v) async {
    await SecureKv.write(k, v);
  }

  @override
  Future<void> delete(String k) => SecureKv.delete(k);
}

class MemAccessKv implements AccessKv {
  final Map<String, String> m = {};
  @override
  Future<String?> read(String k) async => m[k];
  @override
  Future<void> write(String k, String v) async => m[k] = v;
  @override
  Future<void> delete(String k) async => m.remove(k);
}

// ---------------------------------------------------------------- crypto + token formats

String b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');
List<int> unb64u(String s) => base64Url.decode(base64Url.normalize(s));

final Ed25519 _ed = Ed25519();

class KeyPairText {
  final String seed; // private (base64url)
  final String pub; // public (base64url)
  const KeyPairText(this.seed, this.pub);
}

Future<KeyPairText> newKeyPairText() async {
  final kp = await _ed.newKeyPair();
  final seed = await kp.extractPrivateKeyBytes();
  final pub = (await kp.extractPublicKey()).bytes;
  return KeyPairText(b64u(seed), b64u(pub));
}

SimpleKeyPairData _kp(String seed, String pub) => SimpleKeyPairData(unb64u(seed),
    publicKey: SimplePublicKey(unb64u(pub), type: KeyPairType.ed25519), type: KeyPairType.ed25519);

Future<String> _sign(String prefix, Map<String, dynamic> payload, KeyPairText key) async {
  final body = b64u(utf8.encode(jsonEncode(payload)));
  final sig = await _ed.sign(utf8.encode('$prefix.$body'), keyPair: _kp(key.seed, key.pub));
  return '$prefix.$body.${b64u(sig.bytes)}';
}

/// Verifies `prefix.payload.sig` with [pubKey]; returns the payload or null.
Future<Map<String, dynamic>?> _verify(String token, String prefix, String pubKey) async {
  try {
    final p = token.trim().split('.');
    if (p.length != 3 || p[0] != prefix) return null;
    final ok = await _ed.verify(utf8.encode('${p[0]}.${p[1]}'),
        signature: Signature(unb64u(p[2]), publicKey: SimplePublicKey(unb64u(pubKey), type: KeyPairType.ed25519)));
    if (!ok) return null;
    final m = jsonDecode(utf8.decode(unb64u(p[1])));
    return m is Map<String, dynamic> ? m : null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _peek(String token, String prefix) {
  try {
    final p = token.trim().split('.');
    if (p.length != 3 || p[0] != prefix) return null;
    final m = jsonDecode(utf8.decode(unb64u(p[1])));
    return m is Map<String, dynamic> ? m : null;
  } catch (_) {
    return null;
  }
}

bool validPubKey(String k) {
  try {
    return unb64u(k).length == 32;
  } catch (_) {
    return false;
  }
}

String newMemberId() {
  final r = Random.secure();
  return b64u(List<int>.generate(16, (_) => r.nextInt(256)));
}

/// What a phone sends to the administrator.
class AccessRequest {
  final String id, dev, name, email, note;
  final DateTime ts;
  const AccessRequest(this.id, this.dev, this.name, this.email, this.note, this.ts);

  String get code {
    final body = b64u(utf8.encode(jsonEncode(
        {'v': 1, 'id': id, 'dev': dev, 'name': name, 'email': email, 'note': note, 'ts': ts.millisecondsSinceEpoch ~/ 1000})));
    return 'MLREQ1.$body';
  }

  static AccessRequest? parse(String code) {
    try {
      final p = code.trim().split('.');
      if (p.length != 2 || p[0] != 'MLREQ1') return null;
      final m = jsonDecode(utf8.decode(unb64u(p[1]))) as Map<String, dynamic>;
      final id = '${m['id']}', dev = '${m['dev']}';
      if (id.length < 16 || !validPubKey(dev)) return null;
      return AccessRequest(id, dev, '${m['name'] ?? ''}'.trim(), '${m['email'] ?? ''}'.trim(), '${m['note'] ?? ''}'.trim(),
          DateTime.fromMillisecondsSinceEpoch((m['ts'] as num).toInt() * 1000));
    } catch (_) {
      return null;
    }
  }
}

class AccessApproval {
  final String id, dev, name, email, role, adm, raw;
  final DateTime issued, expires;
  const AccessApproval(this.id, this.dev, this.name, this.email, this.role, this.adm, this.issued, this.expires, this.raw);
}

enum AccessStatus { ungated, valid, none, expired, revoked, invalid }

class AccessCheck {
  final AccessStatus status;
  final AccessApproval? approval;
  const AccessCheck(this.status, [this.approval]);
}

AccessApproval? _toApproval(Map<String, dynamic> m, String raw) {
  try {
    return AccessApproval('${m['id']}', '${m['dev']}', '${m['name']}', '${m['email']}', '${m['role']}', '${m['adm']}',
        DateTime.fromMillisecondsSinceEpoch((m['iat'] as num).toInt() * 1000),
        DateTime.fromMillisecondsSinceEpoch((m['exp'] as num).toInt() * 1000), raw);
  } catch (_) {
    return null;
  }
}

/// Administrator: signs an approval for [req] valid [days] days.
Future<String> signApproval(KeyPairText admin, AccessRequest req, int days, DateTime now,
    {String role = 'member'}) {
  return _sign('MLA1', {
    'v': 1,
    'id': req.id,
    'dev': req.dev,
    'name': req.name,
    'email': req.email,
    'role': role,
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': now.add(Duration(days: days)).millisecondsSinceEpoch ~/ 1000,
    'adm': admin.pub,
  }, admin);
}

/// Member phone: full verification of an approval code.
Future<AccessCheck> verifyApproval(String token, {required List<String> pins, required String devPub, required Set<String> revoked, required DateTime now}) async {
  final peek = _peek(token, 'MLA1');
  if (peek == null) return const AccessCheck(AccessStatus.invalid);
  final adm = '${peek['adm']}';
  if (!pins.contains(adm)) return const AccessCheck(AccessStatus.invalid);
  final m = await _verify(token, 'MLA1', adm);
  if (m == null) return const AccessCheck(AccessStatus.invalid);
  final a = _toApproval(m, token.trim());
  if (a == null || a.dev != devPub) return const AccessCheck(AccessStatus.invalid);
  if (revoked.contains(a.id)) return AccessCheck(AccessStatus.revoked, a);
  if (!now.isBefore(a.expires)) return AccessCheck(AccessStatus.expired, a);
  return AccessCheck(AccessStatus.valid, a);
}

/// Key rotation: the OLD key signs "from now on trust [next]".
Future<String> signRotation(KeyPairText old, String nextPub, DateTime now) =>
    _sign('MLROT1', {'v': 1, 'old': old.pub, 'next': nextPub, 'iat': now.millisecondsSinceEpoch ~/ 1000}, old);

/// Returns the new public key when [token] is a rotation signed by [pinned].
Future<String?> verifyRotation(String token, String pinned) async {
  final m = await _verify(token, 'MLROT1', pinned);
  if (m == null || m['old'] != pinned) return null;
  final next = '${m['next']}';
  return validPubKey(next) ? next : null;
}

// ---------------------------------------------------------------- encrypted key backup

final Pbkdf2 _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 150000, bits: 256);

Future<String> wrapAdminKey(KeyPairText k, String passphrase) async {
  final r = Random.secure();
  final salt = List<int>.generate(16, (_) => r.nextInt(256));
  final key = await _kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
  final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode({'seed': k.seed, 'pub': k.pub})), secretKey: key);
  return 'MLKEY1.${b64u(salt)}.${b64u(box.concatenation())}';
}

/// Null when the passphrase is wrong or the text is damaged.
Future<KeyPairText?> unwrapAdminKey(String text, String passphrase) async {
  try {
    final p = text.trim().split('.');
    if (p.length != 3 || p[0] != 'MLKEY1') return null;
    final key = await _kdf.deriveKeyFromPassword(password: passphrase, nonce: unb64u(p[1]));
    final box = SecretBox.fromConcatenation(unb64u(p[2]), nonceLength: 12, macLength: 16);
    final m = jsonDecode(utf8.decode(await AesGcm.with256bits().decrypt(box, secretKey: key))) as Map<String, dynamic>;
    final k = KeyPairText('${m['seed']}', '${m['pub']}');
    // the seed must really give this public key
    final pub = (await _ed.newKeyPairFromSeed(unb64u(k.seed)).then((e) => e.extractPublicKey())).bytes;
    return b64u(pub) == k.pub ? k : null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- controller

enum RedeemResult { ok, invalid, expired, revoked, noKey }

class AccessController extends ChangeNotifier {
  AccessKv kv = SecureAccessKv();
  DateTime Function() clock = DateTime.now;

  bool loaded = false;
  List<String> pins = []; // trusted administrator keys, last = current
  String adminName = '';
  Set<String> revoked = {};
  DateTime? lastFetch;
  bool keyWarning = false; // a published key change was ignored (not signed by the pinned key)
  KeyPairText? _admin; // administrator phone only
  KeyPairText? _dev;
  AccessApproval? approval;
  AccessCheck check = const AccessCheck(AccessStatus.ungated);
  Map<String, dynamic>? pending; // my outstanding request
  List<Map<String, dynamic>> members = []; // administrator phone only
  bool refreshing = false;

  bool get gateOn => pins.isNotEmpty;
  bool get isAdmin => _admin != null;
  String get adminPub => _admin?.pub ?? '';
  String? get devPub => _dev?.pub;

  /// The gate is shown only when it is on, nothing valid is stored, and this is not the admin phone.
  /// Never blocks before loading finished (nobody is locked out by a slow start).
  bool get blocking => loaded && gateOn && !isAdmin && check.status != AccessStatus.valid;

  int? get daysLeft {
    final a = check.approval;
    if (a == null) return null;
    return (a.expires.difference(clock()).inMinutes / 1440).ceil();
  }

  Future<void> startup({bool fetch = true}) async {
    pins = _list(await kv.read('acc_pins'));
    adminName = await kv.read('acc_admname') ?? '';
    revoked = _list(await kv.read('acc_revoked')).toSet();
    final lf = int.tryParse(await kv.read('acc_lastfetch') ?? '');
    lastFetch = lf == null ? null : DateTime.fromMillisecondsSinceEpoch(lf);
    final seed = await kv.read('acc_adm_seed'), pub = await kv.read('acc_adm_pub');
    _admin = (seed != null && pub != null) ? KeyPairText(seed, pub) : null;
    final ds = await kv.read('acc_dev_seed'), dp = await kv.read('acc_dev_pub');
    _dev = (ds != null && dp != null) ? KeyPairText(ds, dp) : null;
    approval = null;
    final tok = await kv.read('acc_approval');
    pending = _map(await kv.read('acc_req'));
    members = _maps(await kv.read('acc_members'));
    await _recheck(tok);
    loaded = true;
    notifyListeners();
    if (fetch) unawaited(refresh());
  }

  List<String> _list(String? s) {
    try {
      return s == null ? [] : (jsonDecode(s) as List).map((e) => '$e').toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic>? _map(String? s) {
    try {
      return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _maps(String? s) {
    try {
      return s == null ? [] : (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _recheck([String? stored]) async {
    if (!gateOn) {
      check = const AccessCheck(AccessStatus.ungated);
      return;
    }
    final tok = stored ?? approval?.raw ?? await kv.read('acc_approval');
    if (tok == null || _dev == null) {
      check = const AccessCheck(AccessStatus.none);
      approval = null;
      return;
    }
    check = await verifyApproval(tok, pins: pins, devPub: _dev!.pub, revoked: revoked, now: clock());
    approval = check.approval;
    // a damaged or foreign stored code counts as "no approval"
    if (check.status == AccessStatus.invalid) check = const AccessCheck(AccessStatus.none);
  }

  /// Reads the published admin.json. At most once a day unless [force] (or until a key is pinned).
  Future<void> refresh({bool force = false}) async {
    if (refreshing) return;
    final now = clock();
    if (!force && gateOn && lastFetch != null && now.difference(lastFetch!).inHours < 24) return;
    refreshing = true;
    try {
      final body = await accessFetch(kAdminJsonUrl);
      if (body == null) return;
      await applyAdminJson(body);
    } catch (_) {
    } finally {
      refreshing = false;
    }
  }

  /// Processes the content of admin.json (also used by tests). Returns false when ignored.
  Future<bool> applyAdminJson(String body) async {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    final key = '${j['adminKey'] ?? ''}'.trim();
    if (key.isEmpty || !validPubKey(key)) return false;
    var changed = false;
    if (pins.isEmpty) {
      pins = [key]; // trust on first use
      changed = true;
    } else if (pins.last != key) {
      if (pins.contains(key)) {
        // an old key re-published: not a rotation, ignore
        keyWarning = true;
      } else {
        final rot = j['rotation'];
        final next = rot is String ? await verifyRotation(rot, pins.last) : null;
        if (next != null && next == key) {
          pins = [...pins, key];
          keyWarning = false;
          changed = true;
        } else {
          keyWarning = true;
          notifyListeners();
          return false;
        }
      }
    }
    if (changed) await kv.write('acc_pins', jsonEncode(pins));
    adminName = '${j['name'] ?? ''}';
    await kv.write('acc_admname', adminName);
    // the revoked list only counts when it comes from the pinned key's file
    final r = j['revoked'];
    revoked = r is List ? r.map((e) => '$e').toSet() : <String>{};
    await kv.write('acc_revoked', jsonEncode(revoked.toList()));
    lastFetch = clock();
    await kv.write('acc_lastfetch', '${lastFetch!.millisecondsSinceEpoch}');
    await _recheck();
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- member side

  Future<KeyPairText> _devKey() async {
    var d = _dev;
    if (d == null) {
      d = await newKeyPairText();
      _dev = d;
      await kv.write('acc_dev_seed', d.seed);
      await kv.write('acc_dev_pub', d.pub);
    }
    return d;
  }

  /// Builds (and remembers) my request. The member id stays the same on a renewal.
  Future<AccessRequest> createRequest(String name, String email, String note) async {
    final d = await _devKey();
    final id = (pending?['id'] as String?) ?? approval?.id ?? newMemberId();
    final req = AccessRequest(id, d.pub, name.trim(), email.trim(), note.trim(), clock());
    pending = {'id': id, 'name': req.name, 'email': req.email, 'note': req.note, 'code': req.code};
    await kv.write('acc_req', jsonEncode(pending));
    notifyListeners();
    return req;
  }

  Future<RedeemResult> redeem(String code) async {
    if (pins.isEmpty) return RedeemResult.noKey;
    final d = _dev;
    if (d == null) return RedeemResult.invalid;
    final c = await verifyApproval(code, pins: pins, devPub: d.pub, revoked: revoked, now: clock());
    switch (c.status) {
      case AccessStatus.valid:
        await kv.write('acc_approval', code.trim());
        await kv.delete('acc_req');
        pending = null;
        check = c;
        approval = c.approval;
        notifyListeners();
        return RedeemResult.ok;
      case AccessStatus.expired:
        return RedeemResult.expired;
      case AccessStatus.revoked:
        return RedeemResult.revoked;
      default:
        return RedeemResult.invalid;
    }
  }

  Future<void> signOut() async {
    await kv.delete('acc_approval');
    approval = null;
    await _recheck();
    notifyListeners();
  }

  // ---------------------------------------------------------------- administrator side

  /// Creates the administrator key on this phone and trusts it here.
  Future<KeyPairText> setupAdmin({String name = ''}) async {
    final k = await newKeyPairText();
    await _adoptAdmin(k, name);
    return k;
  }

  Future<void> _adoptAdmin(KeyPairText k, String name) async {
    _admin = k;
    await kv.write('acc_adm_seed', k.seed);
    await kv.write('acc_adm_pub', k.pub);
    if (!pins.contains(k.pub)) pins = [...pins, k.pub];
    await kv.write('acc_pins', jsonEncode(pins));
    if (name.isNotEmpty) {
      adminName = name;
      await kv.write('acc_admname', name);
    }
    await _recheck();
    notifyListeners();
  }

  Future<String> exportAdminBackup(String passphrase) => wrapAdminKey(_admin!, passphrase);

  Future<bool> restoreAdmin(String text, String passphrase) async {
    final k = await unwrapAdminKey(text, passphrase);
    if (k == null) return false;
    await _adoptAdmin(k, '');
    return true;
  }

  Future<void> _saveMembers() => kv.write('acc_members', jsonEncode(members));

  Future<String> approve(AccessRequest req, int days) async {
    final now = clock();
    final code = await signApproval(_admin!, req, days, now);
    members.removeWhere((m) => m['id'] == req.id);
    members.add({
      'id': req.id,
      'dev': req.dev,
      'name': req.name,
      'email': req.email,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(Duration(days: days)).millisecondsSinceEpoch ~/ 1000,
      'revoked': false,
    });
    await _saveMembers();
    notifyListeners();
    return code;
  }

  Future<String?> renew(String id, int days) async {
    final m = members.where((e) => e['id'] == id && e['revoked'] != true).firstOrNull;
    if (m == null) return null;
    final req = AccessRequest(id, '${m['dev']}', '${m['name']}', '${m['email']}', '', clock());
    return approve(req, days);
  }

  Future<void> revoke(String id) async {
    for (final m in members) {
      if (m['id'] == id) m['revoked'] = true;
    }
    await _saveMembers();
    notifyListeners();
  }

  List<String> get revokedIds => [for (final m in members) if (m['revoked'] == true) '${m['id']}'];

  /// The file the administrator commits as library/admin.json.
  String adminJson({String? rotation}) => const JsonEncoder.withIndent('  ').convert({
        'v': 1,
        'adminKey': _admin?.pub ?? '',
        'name': adminName,
        'revoked': revokedIds,
        'minVersion': 0,
        if (rotation != null) 'rotation': rotation,
      });

  /// New key; the old one signs the rotation so that every pinned phone follows.
  Future<String> rotateKey() async {
    final old = _admin!;
    final next = await newKeyPairText();
    final rot = await signRotation(old, next.pub, clock());
    await _adoptAdmin(next, '');
    return adminJson(rotation: rot);
  }
}

final AccessController access = AccessController();
