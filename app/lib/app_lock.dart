import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'data.dart';
import 'i18n.dart';

/// Optional lock with the phone's own fingerprint / face / screen lock.
/// Nothing leaves the phone. It is fail-soft: if the plugin or the phone cannot
/// do it, the app simply is not locked by this feature (the PIN lock is separate).

/// Seam for tests: the real implementation talks to the platform.
abstract class LockAuth {
  /// True when the phone has a screen lock or biometrics that can be used.
  Future<bool> supported();

  /// Shows the system prompt. False on cancel, failure or any error.
  Future<bool> authenticate(String reason);
}

class PlatformLockAuth implements LockAuth {
  final LocalAuthentication _a = LocalAuthentication();

  @override
  Future<bool> supported() async {
    try {
      return await _a.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _a.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

LockAuth lockAuth = PlatformLockAuth();

enum LockEnable { ok, unsupported, failed }

const List<int> kLockDelays = [0, 60, 300];

class AppLock extends ChangeNotifier {
  bool locked = false;
  bool busy = false; // the system prompt is open: app-lifecycle events are ignored
  DateTime? _leftAt;
  DateTime Function() clock = DateTime.now;

  bool get enabled => store.settings['bioLock'] == true;

  /// Seconds the app may stay in the background before it locks (0 = at once).
  int get delaySeconds {
    final v = store.settings['bioLockDelay'];
    final n = v is num ? v.toInt() : 0;
    return kLockDelays.contains(n) ? n : 0;
  }

  /// Call once the settings are loaded: a cold start is locked too.
  void startup() {
    if (enabled && !locked) {
      locked = true;
      notifyListeners();
    }
  }

  void onPaused() {
    if (!enabled || busy) return;
    _leftAt ??= clock();
    // "immediately": the cover is already up when the app is seen in the app-switcher
    if (delaySeconds == 0 && !locked) {
      locked = true;
      notifyListeners();
    }
  }

  void onResumed() {
    final left = _leftAt;
    _leftAt = null;
    if (!enabled || busy || locked || left == null) return;
    if (clock().difference(left).inSeconds >= delaySeconds) {
      locked = true;
      notifyListeners();
    }
  }

  /// Asks the system to confirm. If the phone no longer has any screen lock, the
  /// feature switches itself off instead of locking the user out for good.
  Future<bool> unlock() async {
    if (!locked || busy) return !locked;
    busy = true;
    notifyListeners();
    var ok = false;
    try {
      if (!await lockAuth.supported()) {
        await store.setLook('bioLock', false);
        ok = true;
      } else {
        ok = await lockAuth.authenticate(tr('Unlock MedLog'));
      }
    } catch (_) {
      ok = false;
    }
    busy = false;
    if (ok) {
      locked = false;
      _leftAt = null;
    }
    notifyListeners();
    return ok;
  }

  /// The setting can only be switched on after the phone confirmed it once.
  Future<LockEnable> enable() async {
    if (busy) return LockEnable.failed;
    busy = true;
    LockEnable r;
    try {
      if (!await lockAuth.supported()) {
        r = LockEnable.unsupported;
      } else if (await lockAuth.authenticate(tr('Confirm to turn on the app lock'))) {
        await store.setLook('bioLock', true);
        r = LockEnable.ok;
      } else {
        r = LockEnable.failed;
      }
    } catch (_) {
      r = LockEnable.failed;
    }
    busy = false;
    _leftAt = null;
    notifyListeners();
    return r;
  }

  Future<void> disable() async {
    await store.setLook('bioLock', false);
    locked = false;
    _leftAt = null;
    notifyListeners();
  }

  Future<void> setDelay(int seconds) async {
    await store.setLook('bioLockDelay', kLockDelays.contains(seconds) ? seconds : 0);
    notifyListeners();
  }
}

final AppLock appLock = AppLock();

/// Full-screen cover drawn above the Navigator.
class AppLockScreen extends StatefulWidget {
  final bool autoPrompt;
  const AppLockScreen({super.key, this.autoPrompt = true});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.autoPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) appLock.unlock();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: appLock,
      builder: (context, _) => Scaffold(
        key: const ValueKey('app-lock'),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 14),
                  Text(tr('MedLog is locked'), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(tr('Use your fingerprint, face or phone screen lock to open it.'),
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: appLock.busy ? null : () => appLock.unlock(),
                    icon: const Icon(Icons.fingerprint),
                    label: Text(tr('Unlock')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
