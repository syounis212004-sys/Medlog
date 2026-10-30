import 'package:flutter/material.dart' hide Text;

import 'ai/ai_context.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'access.dart';
import 'data.dart';
import 'i18n.dart';
import 'widgets.dart';

// Gate, request screen, administrator tools and the "Access & members" settings rows.

/// Seams (tests replace them).
Future<void> Function(String text) accessShareText = (t) async {
  await Share.share(t);
};

/// Encrypted backup of the user's own data: never blocked by the gate.
Future<void> Function(BuildContext context) accessExportMyData = _exportMyData;

Future<void> _exportMyData(BuildContext context) async {
  final pw = await askPassword(context, 'Backup password',
      confirm: true,
      note: 'The backup is encrypted. If you forget this password nobody can open it. Write it down somewhere safe.');
  if (pw == null) return;
  try {
    final f = await store.exportBackup(pw);
    await Share.shareXFiles([XFile(f.path)], text: 'MedLog backup');
  } catch (e) {
    if (context.mounted) snack(context, '${tr('Export failed')}: $e');
  }
}

/// The code inside a pasted message (WhatsApp adds text around it): "MLREQ1..." or "MLA1...".
String? extractAccessCode(String text, String prefix) {
  final m = RegExp('$prefix\\.[A-Za-z0-9_\\-\\.]+').firstMatch(text);
  return m?.group(0);
}

/// What is in the clipboard now (empty when there is nothing readable).
Future<String> _clipText() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  } catch (_) {
    return '';
  }
}

String fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

// ---------------------------------------------------------------- the gate

/// Full-screen gate. Lives above the app content (and below the app-lock cover). Hosts its own
/// Navigator so dialogs and text selection work there.
class AccessGate extends StatelessWidget {
  const AccessGate({super.key});

  @override
  Widget build(BuildContext context) {
    // own Navigator: it must not share the app's HeroController
    return HeroControllerScope.none(
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const GateScreen()),
      ),
    );
  }
}

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> with WidgetsBindingObserver {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _note = TextEditingController();
  final _paste = TextEditingController();
  String _msg = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = access.pending;
    final a = access.approval;
    _name.text = '${p?['name'] ?? a?.name ?? ''}';
    _email.text = '${p?['email'] ?? a?.email ?? ''}';
    _note.text = '${p?['note'] ?? ''}';
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_name, _email, _note, _paste]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scanClipboard();
  }

  String _tried = '';

  /// The approval code was copied from WhatsApp: when the app is opened it is found and used, nothing to paste.
  Future<void> _scanClipboard() async {
    if (access.pending == null) return;
    final code = extractAccessCode(await _clipText(), 'MLA1');
    if (code == null || code == _tried || !mounted) return;
    _tried = code;
    _paste.text = code;
    await _activate();
  }

  Future<void> _pasteNow() async {
    final t = await _clipText();
    final code = extractAccessCode(t, 'MLA1') ?? t.trim();
    if (!mounted) return;
    setState(() => _paste.text = code);
    if (code.isNotEmpty) await _activate();
  }

  /// Makes the request code and opens the share sheet at once (WhatsApp, email), so there is nothing to copy.
  Future<void> _sendRequest() async {
    await _create();
    final c = access.pending?['code'] as String?;
    if (c != null && _msg.isEmpty) await accessShareText(c);
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || !_email.text.contains('@')) {
      setState(() => _msg = tr('Enter your full name and a valid email.'));
      return;
    }
    await access.createRequest(_name.text, _email.text, _note.text);
    setState(() => _msg = '');
  }

  Future<void> _activate() async {
    final r = await access.redeem(extractAccessCode(_paste.text, 'MLA1') ?? _paste.text);
    if (!mounted) return;
    final m = {
      RedeemResult.ok: '',
      RedeemResult.invalid: 'This code is not valid for this phone. Check that you pasted the whole code you received for the request made on THIS phone.',
      RedeemResult.expired: 'This approval has already expired. Ask the administrator for a new one.',
      RedeemResult.revoked: 'This approval was withdrawn by the administrator.',
      RedeemResult.noKey: 'The administrator key is not known yet. Connect to the internet once and press "Check again".',
    }[r]!;
    setState(() => _msg = m.isEmpty ? '' : tr(m));
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    await access.refresh(force: true);
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = access.lastFetch == null ? tr('Could not reach the server. Check the connection.') : '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: access,
      builder: (context, _) {
        final st = access.check.status;
        final title = st == AccessStatus.expired
            ? 'Your access has expired'
            : st == AccessStatus.revoked
                ? 'Your access was withdrawn'
                : 'Access required';
        final code = access.pending?['code'] as String?;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  children: [
                    Icon(st == AccessStatus.expired ? Icons.hourglass_bottom_rounded : Icons.verified_user_outlined,
                        size: 48, color: cs.primary),
                    const SizedBox(height: 12),
                    Text(title, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(st == AccessStatus.expired
                        ? 'Ask the administrator to renew you: send a new request code below.'
                        : 'MedLog is for approved users only. Ask the administrator to approve you; it takes two short messages. Your logbook stays on this phone and nothing about patients is sent.'),
                    if (access.adminName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('${tr('Administrator')}: ${access.adminName}', style: tt.bodySmall),
                    ],
                    const SizedBox(height: 20),
                    Text('1. Request access', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(labelText: tr('Full name'), border: const OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(labelText: tr('Email'), border: const OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _note,
                        decoration: InputDecoration(labelText: tr('Note (optional)'), border: const OutlineInputBorder())),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                        key: const Key('gate_send'),
                        onPressed: _sendRequest,
                        icon: const Icon(Icons.send_outlined),
                        label: Text('Send request to the administrator')),
                    if (code != null) ...[
                      const SizedBox(height: 12),
                      Text('Send this code to the administrator by WhatsApp or email:', style: tt.bodySmall),
                      const SizedBox(height: 6),
                      CodeBox(text: code, shareSubject: tr('MedLog access request')),
                    ],
                    const SizedBox(height: 24),
                    Text('2. Paste the approval code', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _paste,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                            labelText: tr('Approval code'),
                            border: const OutlineInputBorder(),
                            alignLabelWithHint: true,
                            suffixIcon: IconButton(key: const Key('gate_paste'), tooltip: tr('Paste'), icon: const Icon(Icons.content_paste), onPressed: _pasteNow))),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                        onPressed: _activate, icon: const Icon(Icons.check_circle_outline), label: Text('Activate')),
                    if (_msg.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      m_Message(_msg, cs.error),
                    ],
                    if (access.keyWarning) ...[
                      const SizedBox(height: 10),
                      m_Message(
                          tr('The published administrator key changed without a valid signature, so it was ignored.'), cs.error),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                        onPressed: _busy ? null : _retry,
                        icon: const Icon(Icons.refresh),
                        label: Text('Check again (online)')),
                    const Divider(height: 32),
                    Text('Your data is yours. You can always save a copy of it, even without approval.', style: tt.bodySmall),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: () => accessExportMyData(context),
                        icon: const Icon(Icons.backup_outlined),
                        label: Text('Export my data')),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ignore: non_constant_identifier_names
Widget m_Message(String s, Color c) => Text(s, style: TextStyle(color: c, fontWeight: FontWeight.w600));

/// A selectable code with Copy and Share buttons.
class CodeBox extends StatelessWidget {
  final String text;
  final String shareSubject;
  const CodeBox({super.key, required this.text, this.shareSubject = ''});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: SelectableText(text,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            textDirection: TextDirection.ltr),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) snack(context, tr('Copied'));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text('Copy')),
        OutlinedButton.icon(
            onPressed: () => accessShareText(text),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: Text('Share')),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- settings rows

class AccessSettingsSection extends StatelessWidget {
  const AccessSettingsSection({super.key});

  void _open(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: access,
      builder: (context, _) {
        final a = access.approval;
        final left = access.daysLeft;
        final soon = left != null && left <= 14;
        final rows = <Widget>[];
        if (access.isAdmin) {
          rows.add(ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text('You are the administrator'),
              subtitle: Text('Approve requests, see members, publish the key'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const AdminHomeScreen())));
        } else {
          rows.add(ListTile(
            leading: Icon(!access.gateOn ? Icons.lock_open_outlined : Icons.verified_user_outlined),
            title: Text(!access.gateOn
                ? 'Open access'
                : a == null
                    ? 'Not approved'
                    : 'Approved'),
            subtitle: Text(!access.gateOn
                ? 'No administrator has turned access control on.'
                : a == null
                    ? 'Open the app again to request access.'
                    : '${tr('Approved by')} ${access.adminName.isEmpty ? tr('the administrator') : access.adminName}\n'
                        '${a.name}  ·  ${fmtDate(a.expires)}'
                        '${left == null ? '' : '  ·  ${trp('expires in {n} days', {'n': left})}'}'),
            isThreeLine: a != null,
            iconColor: soon ? Theme.of(context).colorScheme.error : null,
          ));
          if (a != null) {
            rows.add(ListTile(
                leading: const Icon(Icons.logout),
                title: Text('Sign out'),
                subtitle: Text('Removes the approval from this phone. Your data stays.'),
                onTap: () async {
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                            title: Text('Sign out?'),
                            content: Text('You will need a new approval code to open the app again. Your data is not deleted.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Sign out')),
                            ],
                          ));
                  if (ok == true) await access.signOut();
                }));
          }
        }
        rows.add(ListTile(
            leading: const Icon(Icons.refresh),
            title: Text('Check administrator list now'),
            subtitle: Text(access.lastFetch == null ? 'Never checked' : '${tr('Last check')}: ${fmtDate(access.lastFetch!)}'),
            onTap: () async {
              await access.refresh(force: true);
              if (context.mounted) snack(context, tr(access.gateOn ? 'Checked.' : 'No administrator key is published.'));
            }));
        if (!access.isAdmin) {
          rows.add(ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text('Administrator tools'),
              subtitle: Text('Only for the person who approves the members'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const AdminSetupScreen())));
        }
        return Column(children: rows);
      },
    );
  }
}

// ---------------------------------------------------------------- administrator

class AdminSetupScreen extends StatefulWidget {
  const AdminSetupScreen({super.key});

  @override
  State<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends State<AdminSetupScreen> {
  final _name = TextEditingController();
  final _backup = TextEditingController();
  final _pass = TextEditingController();
  String _msg = '';

  @override
  void dispose() {
    _name.dispose();
    _backup.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('Set up as administrator?'),
              content: Text(
                  'A secret signing key is created and kept ONLY on this phone. Anyone with this phone unlocked can approve members. If you lose the phone without the encrypted key backup you will not be able to approve anyone again. Do this only on the phone you will keep.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Create key')),
              ],
            ));
    if (ok != true) return;
    await access.setupAdmin(name: _name.text.trim());
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const AdminHomeScreen()));
  }

  Future<void> _restore() async {
    final good = await access.restoreAdmin(_backup.text, _pass.text);
    if (!mounted) return;
    if (good) {
      Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const AdminHomeScreen()));
    } else {
      setState(() => _msg = tr('Wrong passphrase, or the backup text is damaged.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AiContextScope(ctx: const AiScreenContext(kind: 'admin', title: 'Administration'), child: Scaffold(
      appBar: AppBar(title: Text('Administrator')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Make this phone the administrator', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('The administrator approves who can use MedLog. No server is involved: approvals are signed codes you send by WhatsApp or email.'),
        const SizedBox(height: 12),
        TextField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('Name shown to members'), border: const OutlineInputBorder())),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _setup, icon: const Icon(Icons.admin_panel_settings_outlined), label: Text('Set up as administrator')),
        const Divider(height: 32),
        Text('Restore on a new phone', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
            controller: _backup,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: tr('Encrypted key backup'), border: const OutlineInputBorder(), alignLabelWithHint: true)),
        const SizedBox(height: 10),
        TextField(
            controller: _pass,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Passphrase'), border: const OutlineInputBorder())),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _restore, icon: const Icon(Icons.restore), label: Text('Restore administrator key')),
        if (_msg.isNotEmpty) ...[const SizedBox(height: 10), m_Message(_msg, Theme.of(context).colorScheme.error)],
      ]),
    ));
  }
}

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  void _open(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));

  Future<void> _backup(BuildContext context) async {
    final pw = await askPassword(context, 'Passphrase for the key backup',
        confirm: true,
        note: 'The key backup is encrypted with this passphrase. Without the backup AND the passphrase a lost phone means nobody can be approved any more. Keep both safe, in different places.');
    if (pw == null) return;
    final t = await access.exportAdminBackup(pw);
    if (context.mounted) {
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text('Encrypted key backup'),
                content: SingleChildScrollView(child: CodeBox(text: t)),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close'))],
              ));
    }
  }

  Future<void> _rotate(BuildContext context) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('Rotate the key?'),
              content: Text(
                  'Creates a new key signed by the old one. Publish the new admin.json; phones that already trust you follow it automatically. Do it only if you must.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Rotate')),
              ],
            ));
    if (ok != true) return;
    final j = await access.rotateKey();
    if (context.mounted) {
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text('New admin.json'),
                content: SingleChildScrollView(child: CodeBox(text: j)),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close'))],
              ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: access,
      builder: (context, _) => AiContextScope(ctx: const AiScreenContext(kind: 'admin', title: 'Administration'), child: Scaffold(
        appBar: AppBar(title: Text('Administrator')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('1. Publish your key', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Commit this text as library/admin.json in the repository. Until it is published the app is open to everybody.'),
          const SizedBox(height: 8),
          CodeBox(text: access.adminJson()),
          const Divider(height: 28),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inbox_outlined),
              title: Text('Access requests'),
              subtitle: Text('Paste a request code to approve or reject'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const AccessRequestsScreen())),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_outlined),
              title: Text('Members'),
              subtitle: Text(trp('{n} approved', {'n': access.members.length})),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const MembersScreen())),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.save_alt),
              title: Text('Back up the secret key'),
              subtitle: Text('Encrypted with a passphrase; needed to restore on a new phone'),
              onTap: () => _backup(context)),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.autorenew),
              title: Text('Rotate the key'),
              onTap: () => _rotate(context)),
        ]),
      )),
    );
  }
}

const List<int> kValidityDays = [30, 90, 180, 365];

class AccessRequestsScreen extends StatefulWidget {
  const AccessRequestsScreen({super.key});

  @override
  State<AccessRequestsScreen> createState() => _AccessRequestsScreenState();
}

class _AccessRequestsScreenState extends State<AccessRequestsScreen> {
  final _paste = TextEditingController();
  AccessRequest? _req;
  int _days = 90;
  String _code = '';
  String _msg = '';

  @override
  void initState() {
    super.initState();
    // a request copied from WhatsApp is already waiting here: read at once
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final code = extractAccessCode(await _clipText(), 'MLREQ1');
      if (code == null || !mounted || _paste.text.isNotEmpty) return;
      _paste.text = code;
      _read();
    });
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _read() {
    final r = AccessRequest.parse(extractAccessCode(_paste.text, 'MLREQ1') ?? _paste.text);
    setState(() {
      _req = r;
      _code = '';
      _msg = r == null ? tr('This is not a valid request code.') : '';
    });
  }

  Future<void> _approve() async {
    final c = await access.approve(_req!, _days);
    setState(() => _code = c);
    // straight to the share sheet: the member only has to copy it
    await accessShareText(c);
  }

  @override
  Widget build(BuildContext context) {
    final r = _req;
    return AiContextScope(ctx: const AiScreenContext(kind: 'admin', title: 'Administration'), child: Scaffold(
      appBar: AppBar(title: Text('Access requests')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _paste,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: tr('Paste request code'), border: const OutlineInputBorder(), alignLabelWithHint: true)),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _read, icon: const Icon(Icons.search), label: Text('Read request')),
        if (_msg.isNotEmpty) ...[const SizedBox(height: 10), m_Message(_msg, Theme.of(context).colorScheme.error)],
        if (r != null) ...[
          const SizedBox(height: 16),
          Card(
              child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name.isEmpty ? '-' : r.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(r.email),
              if (r.note.isNotEmpty) ...[const SizedBox(height: 4), Text(r.note)],
              const SizedBox(height: 4),
              Text('${tr('Requested')}: ${fmtDate(r.ts)}', style: Theme.of(context).textTheme.bodySmall),
              Text('${tr('Phone ID')}: ${r.id.substring(0, 8)}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          )),
          const SizedBox(height: 8),
          Text('Role: Member', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text('Valid for'),
          Wrap(spacing: 8, children: [
            for (final d in kValidityDays)
              ChoiceChip(label: Text(trp('{n} days', {'n': d})), selected: _days == d, onSelected: (_) => setState(() => _days = d)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _approve, icon: const Icon(Icons.check), label: Text('Approve'))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                          _req = null;
                          _code = '';
                          _paste.clear();
                        }),
                    icon: const Icon(Icons.close),
                    label: Text('Reject'))),
          ]),
          if (_code.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Send this approval code back to the member:', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            CodeBox(text: _code),
          ],
        ],
      ]),
    ));
  }
}

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  Future<void> _renew(Map<String, dynamic> m) async {
    var days = 90;
    final d = await showDialog<int>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                  title: Text('Renew'),
                  content: Wrap(spacing: 8, children: [
                    for (final v in kValidityDays)
                      ChoiceChip(label: Text(trp('{n} days', {'n': v})), selected: days == v, onSelected: (_) => set(() => days = v)),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, days), child: Text('Renew')),
                  ],
                )));
    if (d == null) return;
    final code = await access.renew('${m['id']}', d);
    if (code != null && mounted) {
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text('New approval code'),
                content: SingleChildScrollView(child: CodeBox(text: code)),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close'))],
              ));
    }
  }

  Future<void> _revoke(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('Revoke this member?'),
              content: Text(
                  'Publish the updated admin.json (shown below the list) so that the phone is blocked the next time it is online.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Revoke')),
              ],
            ));
    if (ok == true) await access.revoke('${m['id']}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: access,
      builder: (context, _) {
        final now = access.clock();
        return AiContextScope(ctx: const AiScreenContext(kind: 'admin', title: 'Administration'), child: Scaffold(
          appBar: AppBar(title: Text('Members')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            if (access.members.isEmpty) Text('Nobody is approved yet.'),
            for (final m in access.members)
              Builder(builder: (_) {
                final exp = DateTime.fromMillisecondsSinceEpoch((m['exp'] as int) * 1000);
                final rev = m['revoked'] == true;
                final expired = !now.isBefore(exp);
                final status = rev ? 'Revoked' : expired ? 'Expired' : 'Active';
                return Card(
                    child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m['name']}', style: Theme.of(context).textTheme.titleSmall),
                    Text('${m['email']}'),
                    Text('${tr(status)}  ·  ${fmtDate(exp)}',
                        style: TextStyle(color: rev || expired ? cs.error : cs.primary, fontWeight: FontWeight.w700)),
                    Wrap(spacing: 8, children: [
                      if (!rev) TextButton(onPressed: () => _renew(m), child: Text('Renew')),
                      if (!rev) TextButton(onPressed: () => _revoke(m), child: Text('Revoke')),
                    ]),
                  ]),
                ));
              }),
            const SizedBox(height: 12),
            Text('admin.json to publish', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            CodeBox(text: access.adminJson()),
          ]),
        ));
      },
    );
  }
}
