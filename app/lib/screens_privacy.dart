import 'dart:io';

import 'package:flutter/material.dart' hide Text;

import 'app_lock.dart';
import 'data.dart';
import 'i18n.dart';
import 'privacy.dart';
import 'reminders.dart';
import 'screens_cases.dart';
import 'ui.dart';
import 'widgets.dart';

/// Tab of the case editor where a field lives (used to jump to it).
int tabOfField(String f) {
  const history = {'cc', 'hpi', 'pmh', 'psh', 'drugs', 'allergies', 'family', 'social', 'ros'};
  const exam = {'examGeneral', 'examSystemic', 'examFocused'};
  const assess = {'problems', 'ddx', 'workingDx', 'finalDx', 'redFlags', 'reasoning', 'evo'};
  const plan = {'mgmt', 'followUp', 'outcome'};
  if (history.contains(f)) return 1;
  if (exam.contains(f)) return 2;
  if (f == 'inv' || f == 'images') return 3;
  if (assess.contains(f)) return 4;
  if (plan.contains(f)) return 5;
  if (f == 'progress') return 6;
  return 7;
}

class PrivacyCheckScreen extends StatelessWidget {
  final CaseRec rec;
  const PrivacyCheckScreen({super.key, required this.rec});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final issues = scanCase(rec);
    final byField = <String, List<PrivacyIssue>>{};
    for (final i in issues) {
      (byField[i.field] ??= []).add(i);
    }
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Privacy check')} • ${rec.s('code')}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppCard(
            color: issues.isEmpty ? cs.primaryContainer.withAlpha(120) : cs.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(issues.isEmpty ? Icons.verified_user_outlined : Icons.privacy_tip_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      issues.isEmpty
                          ? tr('No obvious identifiers found. Still check photos and rare details.')
                          : trp('{n} possible identifiers found. Review them before sharing.', {'n': issues.length}),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final e in byField.entries) ...[
            SectionHeader(_fieldLabel(e.key)),
            for (final i in e.value)
              AppCard(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: m2(i.match),
                  subtitle: Text(kindLabel(i.kind)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: rec, initialTab: tabOfField(e.key))),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            'Removing the name is often not enough: initials, hospital numbers, exact dates and unusual details can identify a patient. '
            'This check only looks for common patterns on this phone and sends nothing anywhere.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }

  String _fieldLabel(String f) {
    const names = {
      'cc': 'Chief complaint + duration', 'hpi': 'History of presenting illness', 'pmh': 'Past medical history',
      'psh': 'Past surgical history', 'drugs': 'Drug history (name, dose)', 'allergies': 'Allergies',
      'family': 'Family history', 'social': 'Social history (smoking, occupation...)', 'ros': 'Review of systems',
      'examGeneral': 'General examination', 'examSystemic': 'Systemic examination (CVS / Resp / Abd / CNS / MSK)',
      'examFocused': 'Focused examination / positive findings', 'problems': 'Problem list',
      'ddx': 'Differential diagnosis (most likely first)', 'workingDx': 'Working / provisional diagnosis',
      'finalDx': 'Final diagnosis', 'redFlags': 'Red flags', 'reasoning': 'Clinical reasoning: what supports / argues against?',
      'followUp': 'Follow-up recommendations', 'outcome': 'Outcome', 'learned': 'What I learned',
      'mistakes': 'Mistakes / near-misses (mine or others) — for learning', 'questions': 'Questions I could not answer (to review)',
      'refs': 'References (book, guideline, page, link)', 'teaching': 'Supervisor teaching points',
      'inv': 'Investigations', 'mgmt': 'Management', 'progress': 'Progress', 'evo': 'Diagnostic evolution', 'images': 'Images',
      'initialDx': 'My first diagnosis (before results)', 'whatChanged': 'What changed my diagnosis?',
    };
    return tr(names[f] ?? f);
  }

  Widget m2(String s) => Text(s, maxLines: 2, overflow: TextOverflow.ellipsis);
}

/// Called before anything leaves the app (text share, encrypted pack). Returns true
/// if sharing may continue.
Future<bool> privacyGate(BuildContext context, List<CaseRec> cases) async {
  var n = 0;
  CaseRec? first;
  for (final c in cases) {
    final k = scanCase(c).length;
    if (k > 0) {
      n += k;
      first ??= c;
    }
  }
  if (n == 0) return true;
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.privacy_tip_outlined),
      title: Text('Possible identifiers found'),
      content: Text(trp(
          '{n} possible identifiers (numbers, names, initials or exact dates) were found in the case text. Review them before sharing.',
          {'n': n})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'share'), child: Text('Share anyway')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'review'), child: Text('Review')),
      ],
    ),
  );
  if (r == 'review' && first != null && context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PrivacyCheckScreen(rec: first!)));
    return false;
  }
  return r == 'share';
}

/// Removes hidden metadata (camera, time, GPS) from every stored JPEG.
Future<int> cleanAllPhotoMetadata() async {
  var n = 0;
  for (final f in store.imagesDir.listSync()) {
    if (f is! File) continue;
    final name = f.path.toLowerCase();
    if (!(name.endsWith('.jpg') || name.endsWith('.jpeg'))) continue;
    final b = await f.readAsBytes();
    if (jpegHasMetadata(b)) {
      await f.writeAsBytes(stripJpegMetadata(b), flush: true);
      n++;
    }
  }
  return n;
}


// ---------------------------------------------------------------- app lock + reminders settings

/// Two folds for the Settings screen: "Lock the app" (fingerprint / face / screen
/// lock) and "Reminders". Put `const SysSettingsSection()` in the settings list.
class SysSettingsSection extends StatefulWidget {
  /// Which parts to show. With [folds] false the rows come without the folding card, so the
  /// Settings screen can place them inside its own sections.
  final bool lock;
  final bool reminders;
  final bool folds;
  const SysSettingsSection({super.key, this.lock = true, this.reminders = true, this.folds = true});

  @override
  State<SysSettingsSection> createState() => _SysSettingsSectionState();
}

class _SysSettingsSectionState extends State<SysSettingsSection> {
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  String _delayLabel(int s) => s == 0
      ? tr('Immediately')
      : s == 60
          ? tr('After 1 minute')
          : tr('After 5 minutes');

  Future<void> _toggleLock(bool v) async {
    if (!v) {
      await appLock.disable();
      return;
    }
    final r = await appLock.enable();
    if (!mounted) return;
    if (r == LockEnable.unsupported) {
      snack(context, tr('This phone has no screen lock or fingerprint set up. Set one in the phone settings first; the app lock stays off.'));
    } else if (r == LockEnable.failed) {
      snack(context, tr('Could not confirm, so the app lock stays off.'));
    }
  }

  Future<void> _toggleRem(String key, bool v) async {
    if (v && !await Reminders.ensurePermission()) {
      if (mounted) snack(context, tr('Notifications are blocked for MedLog. Allow them in the phone settings to get reminders.'));
      return;
    }
    await Reminders.set(key, v);
  }

  Future<void> _pickTime(String hKey, String mKey, int h, int m) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
    if (t == null) return;
    await store.setLook(hKey, t.hour);
    await Reminders.set(mKey, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([store, appLock]),
      builder: (context, _) {
        String two(int n) => n.toString().padLeft(2, '0');
        final lockRows = <Widget>[
            SwitchListTile(
              secondary: const Icon(Icons.lock_person_outlined),
              title: Text(tr('Lock the app')),
              subtitle: Text(tr('Ask for your fingerprint, face or phone screen lock when you open MedLog')),
              value: appLock.enabled,
              onChanged: appLock.busy ? null : _toggleLock,
            ),
            if (appLock.enabled)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(tr('Lock after')),
                trailing: DropdownButton<int>(
                  value: appLock.delaySeconds,
                  underline: const SizedBox.shrink(),
                  items: [for (final d in kLockDelays) DropdownMenuItem(value: d, child: Text(_delayLabel(d)))],
                  onChanged: (v) {
                    if (v != null) appLock.setDelay(v);
                  },
                ),
              ),
        ];
        final remRows = <Widget>[
            SwitchListTile(
              secondary: const Icon(Icons.style_outlined),
              title: Text(tr('Daily review reminder')),
              value: Reminders.dailyOn,
              onChanged: (v) => _toggleRem('remDaily', v),
            ),
            if (Reminders.dailyOn)
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(tr('Time')),
                trailing: Text('${two(Reminders.dailyHour)}:${two(Reminders.dailyMinute)}'),
                onTap: () => _pickTime('remDailyH', 'remDailyM', Reminders.dailyHour, Reminders.dailyMinute),
              ),
            SwitchListTile(
              secondary: const Icon(Icons.edit_note),
              title: Text(tr('Remind me to finish my draft case')),
              value: Reminders.draftOn,
              onChanged: (v) => _toggleRem('remDraft', v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.flag_outlined),
              title: Text(tr('Weekly goals reminder')),
              value: Reminders.weeklyOn,
              onChanged: (v) => _toggleRem('remWeekly', v),
            ),
            if (Reminders.weeklyOn) ...[
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(tr('Day')),
                trailing: DropdownButton<int>(
                  value: Reminders.weeklyDay,
                  underline: const SizedBox.shrink(),
                  items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i + 1, child: Text(tr(_days[i])))],
                  onChanged: (v) {
                    if (v != null) Reminders.set('remWeeklyD', v);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(tr('Time')),
                trailing: Text('${two(Reminders.weeklyHour)}:${two(Reminders.weeklyMinute)}'),
                onTap: () => _pickTime('remWeeklyH', 'remWeeklyM', Reminders.weeklyHour, Reminders.weeklyMinute),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(tr('Reminders are made on this phone. They never contain patient information.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ];
        if (!widget.folds) {
          return Column(children: [if (widget.lock) ...lockRows, if (widget.reminders) ...remRows]);
        }
        return Column(children: [
          if (widget.lock) Fold(id: 'set_applock', title: tr('Lock the app'), icon: Icons.fingerprint, children: lockRows),
          if (widget.reminders) Fold(id: 'set_reminders', title: tr('Reminders'), icon: Icons.notifications_outlined, children: remRows),
        ]);
      },
    );
  }
}
