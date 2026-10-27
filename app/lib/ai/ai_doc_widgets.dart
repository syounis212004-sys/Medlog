import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../sheet_widgets.dart' show toneColor;
import '../lib_sheet.dart' show Tone;
import 'ai_doc_api.dart';
import 'ai_prefs.dart';
import 'ai_render.dart';

/// Renderer of the AI document engine: per-kind cards (same accent colours and icons as the Study Sheet),
/// inline citation chips, tables, steps, jump bar, collapsible sections, raw-text toggle.

const String kAiDisclaimer = 'AI-generated, not medically reviewed. Verify with the cited source and your local protocol.';

bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

Color _kindColor(String kind, bool dark) {
  Color c;
  switch (kind) {
    case 'red_flags':
      return toneColor(Tone.red, dark);
    case 'dont_miss':
      return toneColor(Tone.amber, dark);
    case 'key_points':
      return toneColor(Tone.green, dark);
    case 'mnemonic':
      return dark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A);
    case 'overview':
      c = const Color(0xFF455A64);
      break;
    case 'presentation':
      c = const Color(0xFF00796B);
      break;
    case 'differential':
      c = const Color(0xFF3949AB);
      break;
    case 'investigations':
      c = const Color(0xFF00838F);
      break;
    case 'management':
    case 'steps':
      c = const Color(0xFF1565C0);
      break;
    case 'guidelines':
      c = const Color(0xFF5E35B1);
      break;
    case 'complications':
      c = const Color(0xFFE65100);
      break;
    case 'prognosis':
      c = const Color(0xFF6D4C41);
      break;
    case 'disposition':
      c = const Color(0xFF00695C);
      break;
    case 'uncertainties':
      c = const Color(0xFF8D6E00);
      break;
    default:
      c = const Color(0xFF607D8B);
  }
  return dark ? Color.lerp(c, Colors.white, 0.5)! : c;
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'overview':
      return Icons.info_outline;
    case 'presentation':
      return Icons.monitor_heart_outlined;
    case 'differential':
      return Icons.call_split;
    case 'investigations':
      return Icons.biotech_outlined;
    case 'management':
      return Icons.medical_services_outlined;
    case 'red_flags':
      return Icons.flag;
    case 'dont_miss':
      return Icons.error_outline;
    case 'key_points':
      return Icons.star_border;
    case 'mnemonic':
      return Icons.lightbulb_outline;
    case 'table':
      return Icons.table_chart_outlined;
    case 'steps':
      return Icons.format_list_numbered;
    case 'guidelines':
      return Icons.account_balance_outlined;
    case 'complications':
      return Icons.warning_amber;
    case 'prognosis':
      return Icons.trending_up;
    case 'disposition':
      return Icons.exit_to_app;
    case 'references':
      return Icons.menu_book_outlined;
    case 'uncertainties':
      return Icons.help_outline;
    case 'note':
      return Icons.notes;
    default:
      return Icons.article_outlined;
  }
}

bool _isCallout(String k) => k == 'red_flags' || k == 'dont_miss' || k == 'key_points' || k == 'mnemonic' || k == 'uncertainties';

final RegExp _unstableRx = RegExp(r'unstable|غير مستقر|critical|crashing', caseSensitive: false);
final RegExp _stableRx = RegExp(r'stable|مستقر', caseSensitive: false);

Color? _stabilityColor(String title, bool dark) {
  if (_unstableRx.hasMatch(title)) return toneColor(Tone.red, dark);
  if (RegExp(r'^\W*stable|^\W*مستقر', caseSensitive: false).hasMatch(title.trim()) || _stableRx.hasMatch(title) && title.trim().split(' ').length <= 3) return toneColor(Tone.green, dark);
  return null;
}

final RegExp _doseRx = RegExp(r'\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|ug|g|ml|mL|l|units?|iu|mmol|meq|mg/kg|mcg/kg|%|ملغ|مل|وحدة)\b|\b(?:bolus|infusion|stat|q\d+h|bid|tid|qid|od|prn)\b', caseSensitive: false);
final RegExp _guideRx = RegExp(r'guideline|recommend|first[- ]line|should be (given|started|used)|\b(?:NICE|AHA|ACC|ESC|WHO|IDSA|KDIGO|GOLD|GINA|ADA|SIGN|CDC)\b|إرشاد|توصي', caseSensitive: false);

bool _needsSource(String text) => _doseRx.hasMatch(text) || _guideRx.hasMatch(text);
bool _hasCite(String text) => RegExp(r'\[\d{1,3}(?:\s*[,،–-]\s*\d{1,3})*\]').hasMatch(text) || orgYearRx.hasMatch(text) || RegExp(r'https?://').hasMatch(text);

class _Ctx {
  final List<AiCite> cites;
  final void Function(AiCite) onCite;
  final bool showCites;
  _Ctx(this.cites, this.onCite, this.showCites);

  AiCite? byNum(int n) => n >= 1 && n <= cites.length ? cites[n - 1] : null;

  AiCite match(String org, String year) {
    final first = org.toLowerCase().split(RegExp(r'[\s,]')).first;
    for (final c in cites) {
      if (c.label.toLowerCase().contains(first) && (year.isEmpty || c.label.contains(year) || c.year == year)) return c;
    }
    return AiCite(label: '$org ($year)', org: org.split(RegExp(r'[\s,]')).first, year: year.replaceAll(RegExp(r'[a-z]'), ''));
  }
}

TextDirection _dirOf(BuildContext c, String s) => textDirectionFor(stripInline(s)) ?? Directionality.of(c);

// ---------------------------------------------------------------------------------------------- inline text

final RegExp _inlineRx = RegExp(
  r'\*\*(.+?)\*\*' // 1 bold
  r'|__(.+?)__' // 2 bold
  r'|\[([^\]]+)\]\((https?://[^)\s]+)\)' // 3,4 link
  r'|\[(\d{1,3}(?:\s*[,،–-]\s*\d{1,3})*)\]' // 5 cite numbers
  r'|`([^`]+)`' // 6 code
  r'|(https?://[^\s)\]>"]+)' // 7 url
  r'|\(([A-Z][\w&/.\-]*(?:\s+(?:[A-Za-z][\w&/.\-]*|et al\.?)){0,5}?),?\s+((?:19|20)\d{2}[a-z]?)\)' // 8,9 org year
  r'|(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])', // 10 italic
);

class _Rich extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final _Ctx ctx;
  final bool noSource;
  const _Rich(this.text, this.ctx, {this.style, this.noSource = false});
  @override
  State<_Rich> createState() => _RichState();
}

class _RichState extends State<_Rich> {
  final List<TapGestureRecognizer> _rec = [];

  @override
  void dispose() {
    for (final r in _rec) {
      r.dispose();
    }
    super.dispose();
  }

  Widget _chip(BuildContext context, String label, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsetsDirectional.only(start: 2, end: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
        child: m.Text(label, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
      ),
    );
  }

  List<InlineSpan> _spans(BuildContext context, String text, TextStyle base, int depth) {
    final out = <InlineSpan>[];
    var pos = 0;
    void plain(String s) {
      if (s.isEmpty) return;
      out.add(TextSpan(text: s.replaceAll('**', '').replaceAll('__', ''), style: base));
    }

    for (final mt in _inlineRx.allMatches(text)) {
      plain(text.substring(pos, mt.start));
      pos = mt.end;
      if (mt.group(1) != null || mt.group(2) != null) {
        final inner = mt.group(1) ?? mt.group(2)!;
        final st = base.copyWith(fontWeight: FontWeight.w700);
        out.addAll(depth < 2 ? _spans(context, inner, st, depth + 1) : [TextSpan(text: inner, style: st)]);
      } else if (mt.group(3) != null) {
        final url = mt.group(4)!;
        final rec = TapGestureRecognizer()..onTap = () => widget.ctx.onCite(AiCite(label: mt.group(3)!, url: url));
        _rec.add(rec);
        out.add(TextSpan(text: mt.group(3), recognizer: rec, style: base.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)));
      } else if (mt.group(5) != null) {
        final nums = <int>[];
        for (final part in mt.group(5)!.split(RegExp(r'[,،]'))) {
          final rg = part.split(RegExp(r'[–-]'));
          final a = int.tryParse(rg.first.trim());
          final b = rg.length > 1 ? int.tryParse(rg.last.trim()) : a;
          if (a != null && b != null && b >= a && b - a < 10) {
            for (var i = a; i <= b; i++) {
              nums.add(i);
            }
          }
        }
        if (!widget.ctx.showCites) continue;
        // a number outside the list of sources (a PMID, a table number) stays plain text
        if (nums.isEmpty || nums.any((n) => widget.ctx.byNum(n) == null && (widget.ctx.cites.isNotEmpty || n > 30))) {
          plain(mt.group(0)!);
          continue;
        }
        for (final n in nums) {
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _chip(context, '$n', () => widget.ctx.onCite(widget.ctx.byNum(n) ?? AiCite(label: '${tr('Reference')} $n'))),
          ));
        }
      } else if (mt.group(6) != null) {
        out.add(TextSpan(text: mt.group(6), style: base.copyWith(fontFamily: 'monospace', backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest)));
      } else if (mt.group(7) != null) {
        var u = mt.group(7)!;
        var tail = '';
        final tm = RegExp(r'[.,;:]+$').firstMatch(u);
        if (tm != null) {
          tail = tm.group(0)!;
          u = u.substring(0, tm.start);
        }
        final rec = TapGestureRecognizer()..onTap = () => widget.ctx.onCite(AiCite(label: Uri.tryParse(u)?.host ?? u, url: u));
        _rec.add(rec);
        out.add(TextSpan(text: u, recognizer: rec, style: base.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)));
        plain(tail);
      } else if (mt.group(8) != null) {
        final org = mt.group(8)!;
        final year = mt.group(9)!;
        if (!widget.ctx.showCites) {
          plain(mt.group(0)!);
        } else {
          out.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _chip(context, '$org $year', () => widget.ctx.onCite(widget.ctx.match(org, year)))));
        }
      } else if (mt.group(10) != null) {
        out.addAll(depth < 2 ? _spans(context, mt.group(10)!, base.copyWith(fontStyle: FontStyle.italic), depth + 1) : [TextSpan(text: mt.group(10), style: base)]);
      }
    }
    plain(text.substring(pos));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _rec) {
      r.dispose();
    }
    _rec.clear();
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final spans = _spans(context, widget.text, base, 0);
    if (widget.noSource) {
      final cs = Theme.of(context).colorScheme;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.link_off, size: 11, color: cs.outline),
            const SizedBox(width: 2),
            Text('No source', style: TextStyle(fontSize: 10, color: cs.outline, fontStyle: FontStyle.italic)),
          ]),
        ),
      ));
    }
    return m.Text.rich(TextSpan(children: spans, style: base), textAlign: TextAlign.start);
  }
}

// ---------------------------------------------------------------------------------------------- tables and steps

class _AiTable extends StatelessWidget {
  final List<List<String>> rows;
  final Color color;
  final _Ctx ctx;
  const _AiTable(this.rows, this.color, this.ctx);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final cols = rows.first.length;
    final dir = _dirOf(context, rows.first.join(' '));
    final doseCols = <int>{
      for (var i = 0; i < cols; i++)
        if (RegExp(r'dose|dosage|جرعة|الجرعة', caseSensitive: false).hasMatch(rows.first[i])) i
    };
    double w(int c) {
      var mx = 0;
      for (final r in rows) {
        if (c < r.length) {
          final words = stripInline(r[c]).split(RegExp(r'\s+'));
          final longest = words.fold<int>(0, (a, e) => e.length > a ? e.length : a);
          mx = mx < stripInline(r[c]).length ? stripInline(r[c]).length : mx;
          if (longest > 14) mx = mx < longest * 2 ? longest * 2 : mx;
        }
      }
      return ((mx * 6.6 + 22) * scale.clamp(1.0, 1.5)).clamp(78.0 * scale.clamp(1.0, 1.4), 230.0 * scale.clamp(1.0, 1.4));
    }

    final widths = [for (var c = 0; c < cols; c++) w(c)];
    return Directionality(
      textDirection: dir,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: rows.map((r) => r.map(stripInline).join('\t')).join('\n')));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text('Copied')));
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.copy, size: 13, color: cs.outline),
                const SizedBox(width: 4),
                Text('Copy table', style: TextStyle(fontSize: 11, color: cs.outline)),
              ]),
            ),
          ),
        ),
        LayoutBuilder(builder: (context, bc) {
          final sum = widths.fold<double>(0, (a, b) => a + b);
          final k = sum < bc.maxWidth ? bc.maxWidth / sum : 1.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              columnWidths: {for (var c = 0; c < cols; c++) c: FixedColumnWidth(widths[c] * k)},
              border: TableBorder.all(color: cs.outlineVariant, width: 0.8, borderRadius: BorderRadius.circular(8)),
              children: [
                for (var r = 0; r < rows.length; r++)
                  TableRow(
                    decoration: r == 0 ? BoxDecoration(color: color.withValues(alpha: 0.16)) : (r.isEven ? BoxDecoration(color: cs.onSurface.withValues(alpha: 0.03)) : null),
                    children: [
                      for (var c = 0; c < cols; c++)
                        Directionality(
                          textDirection: _dirOf(context, c < rows[r].length ? rows[r][c] : ''),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: _Rich(
                              c < rows[r].length ? rows[r][c] : '',
                              ctx,
                              style: TextStyle(fontSize: 13, height: 1.35, fontWeight: r == 0 || doseCols.contains(c) ? FontWeight.w700 : FontWeight.w400, color: r > 0 && doseCols.contains(c) ? color : null),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
        }),
      ]),
    );
  }
}

class _GuidelineCards extends StatelessWidget {
  final List<List<String>> rows;
  final Color color;
  final _Ctx ctx;
  const _GuidelineCards(this.rows, this.color, this.ctx);

  @override
  Widget build(BuildContext context) {
    final head = rows.first.map((e) => e.toLowerCase()).toList();
    int idx(RegExp r) => head.indexWhere((h) => r.hasMatch(h));
    final oi = idx(RegExp(r'organi|society|guideline|body|issuer|الجهة|المنظمة|الإرشاد'));
    final yi = idx(RegExp(r'year|سنة|date'));
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      for (final r in rows.skip(1))
        Builder(builder: (context) {
          final org = oi >= 0 && oi < r.length ? stripInline(r[oi]) : '';
          final year = yi >= 0 && yi < r.length ? stripInline(r[yi]) : '';
          final rec = [for (var i = 0; i < r.length; i++) if (i != oi && i != yi && r[i].trim().isNotEmpty) r[i]].join('\n');
          Widget chip(String t, IconData? ic) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (ic != null) ...[Icon(ic, size: 13, color: color), const SizedBox(width: 4)],
                  Flexible(child: m.Text(t, textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
                ]),
              );
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => ctx.onCite(ctx.match(org, year)),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (org.isNotEmpty) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: chip(org, Icons.account_balance_outlined)),
                    if (year.isNotEmpty) chip(year, Icons.event),
                  ]),
                  if (rec.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Directionality(textDirection: _dirOf(context, rec), child: _Rich(rec, ctx, style: const TextStyle(fontSize: 14, height: 1.4))),
                    ),
                ]),
              ),
            ),
          );
        }),
    ]);
  }
}

class _Steps extends StatelessWidget {
  final List<String> steps;
  final Color color;
  final _Ctx ctx;
  final bool noSourceCheck;
  const _Steps(this.steps, this.color, this.ctx, this.noSourceCheck);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < steps.length; i++) ...[
          Directionality(
            textDirection: _dirOf(context, steps[i]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: m.Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _Rich(steps[i], ctx, style: const TextStyle(fontSize: 14.5, height: 1.4), noSource: noSourceCheck && ctx.showCites && _needsSource(steps[i]) && !_hasCite(steps[i])),
                ),
              ),
            ]),
          ),
          if (i + 1 < steps.length)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 5, top: 1, bottom: 1),
              child: Align(alignment: AlignmentDirectional.centerStart, child: Icon(Icons.south, size: 14, color: cs.outline)),
            ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------- section body

final RegExp _likeRx = RegExp(
  r'\s*[\(\[—–-]\s*((?:very |most |more |less )?(?:likely|common|unlikely|rare|possible|probable)|must exclude|consider|high|moderate|low|الأكثر احتمالا|الأكثر شيوعا|محتمل|شائع|نادر|غير محتمل|ممكن)\s*[\)\]]?\s*$',
  caseSensitive: false,
);
final RegExp _likePrefix = RegExp(r'^\s*((?:very |most |more |less )?(?:likely|common|unlikely|rare)|must exclude)\s*[:：\-–—]\s*', caseSensitive: false);

Color _likeColor(String l, bool dark) {
  final s = l.toLowerCase();
  if (s.contains('unlikely') || s.contains('rare') || s.contains('low') || s.contains('نادر') || s.contains('غير')) return const Color(0xFF78909C);
  if (s.contains('must') || s.contains('high') || s.contains('most') || s.contains('very') || s.contains('الأكثر')) return toneColor(Tone.red, dark);
  return toneColor(Tone.blue, dark);
}

class _Body extends StatelessWidget {
  final AiDocSection s;
  final Color color;
  final _Ctx ctx;
  const _Body(this.s, this.color, this.ctx);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = _dark(context);
    final blocks = s.allBlocks;
    final children = <Widget>[];
    final checkSrc = ctx.showCites && ctx.cites.isNotEmpty && s.cites.isEmpty && s.kind != 'mnemonic' && s.kind != 'references';
    const txt = TextStyle(fontSize: 14.5, height: 1.42);
    Color sectionColor = color;
    var i = 0;
    while (i < blocks.length) {
      final b = blocks[i];
      switch (b.type) {
        case 'n':
          final run = <String>[];
          while (i < blocks.length && blocks[i].type == 'n') {
            run.add(blocks[i].text);
            i++;
          }
          children.add(_Steps(run, sectionColor, ctx, checkSrc));
          continue;
        case 't':
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: (s.kind == 'guidelines' && b.rows.isNotEmpty && b.rows.first.length >= 2 && b.rows.first.length <= 4 && RegExp(r'organi|society|guideline|body|issuer|الجهة|المنظمة|الإرشاد', caseSensitive: false).hasMatch(b.rows.first.join(' ')))
                ? _GuidelineCards(b.rows, sectionColor, ctx)
                : _AiTable(b.rows, sectionColor, ctx),
          ));
          break;
        case 'h':
          final sc = _stabilityColor(b.text, dark);
          if (sc != null) sectionColor = sc;
          children.add(Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 5),
            child: Directionality(
              textDirection: _dirOf(context, b.text),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: sc != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: sc.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10), border: Border.all(color: sc.withValues(alpha: 0.6))),
                        child: _Rich(b.text, ctx, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: sc)),
                      )
                    : _Rich(b.text, ctx, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
              ),
            ),
          ));
          break;
        case 'm':
          final mc = _kindColor('mnemonic', dark);
          children.add(Container(
            margin: const EdgeInsets.only(bottom: 8, top: 2),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: mc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: mc.withValues(alpha: 0.5))),
            child: Directionality(
              textDirection: _dirOf(context, b.text),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_outline, size: 18, color: mc),
                const SizedBox(width: 8),
                Expanded(child: _Rich(b.text, ctx, style: txt.copyWith(fontWeight: FontWeight.w600))),
              ]),
            ),
          ));
          break;
        case 'c':
          children.add(Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Directionality(textDirection: TextDirection.ltr, child: m.Text(b.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5))),
          ));
          break;
        case 'b':
          {
            var text = b.text;
            String? like;
            if (s.kind == 'differential') {
              final lm = _likeRx.firstMatch(text);
              if (lm != null) {
                like = lm.group(1);
                text = text.substring(0, lm.start);
              } else {
                final pm = _likePrefix.firstMatch(text);
                if (pm != null) {
                  like = pm.group(1);
                  text = text.substring(pm.end);
                }
              }
            }
            final flag = checkSrc && _needsSource(text) && !_hasCite(text);
            final lc = like == null ? null : _likeColor(like, dark);
            children.add(Padding(
              padding: EdgeInsets.only(bottom: 5, left: 0, right: 0, top: 0).copyWith(),
              child: Directionality(
                textDirection: _dirOf(context, text),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: 12.0 * b.level),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
                      child: b.level == 0
                          ? Container(width: 6, height: 6, decoration: BoxDecoration(color: sectionColor, shape: BoxShape.circle))
                          : Container(width: 7, height: 2, color: cs.outline),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _Rich(text, ctx, style: txt, noSource: flag)),
                    if (lc != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6, top: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: lc.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(9), border: Border.all(color: lc.withValues(alpha: 0.5))),
                          child: m.Text(like!.trim(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: lc)),
                        ),
                      ),
                  ]),
                ),
              ),
            ));
          }
          break;
        default:
          {
            final flag = checkSrc && _needsSource(b.text) && !_hasCite(b.text);
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Directionality(textDirection: _dirOf(context, b.text), child: _Rich(b.text, ctx, style: txt.copyWith(fontWeight: s.kind == 'mnemonic' ? FontWeight.w600 : null), noSource: flag)),
            ));
          }
      }
      i++;
    }
    if (s.cites.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          for (final c in s.cites)
            ActionChip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: const Icon(Icons.menu_book_outlined, size: 14),
              label: m.Text(c.short, style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis),
              onPressed: () => ctx.onCite(c),
            ),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

// ---------------------------------------------------------------------------------------------- view

class AiDocView extends StatefulWidget {
  final AiDoc doc;
  final void Function(AiCite cite)? onCite;
  final bool showCopy;
  final bool showDisclaimer;
  const AiDocView({super.key, required this.doc, this.onCite, this.showCopy = true, this.showDisclaimer = true});
  @override
  State<AiDocView> createState() => _AiDocViewState();
}

class _AiDocViewState extends State<AiDocView> {
  final Set<int> _collapsed = {};
  bool _raw = false;
  bool _refsOpen = true;
  late List<GlobalKey> _keys;

  @override
  void initState() {
    super.initState();
    _keys = [for (final _ in widget.doc.sections) GlobalKey()];
    _refsOpen = widget.doc.citations.length <= 6;
  }

  @override
  void didUpdateWidget(AiDocView old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) {
      _keys = [for (final _ in widget.doc.sections) GlobalKey()];
      _collapsed.clear();
      _refsOpen = widget.doc.citations.length <= 6;
    }
  }

  bool get _showCites {
    try {
      return AiPrefs.showCitations;
    } catch (_) {
      return true;
    }
  }

  void _cite(AiCite c) {
    final f = widget.onCite;
    if (f != null) {
      f(c);
    } else {
      showAiCiteSheet(context, c);
    }
  }

  Future<void> _copy(bool md) async {
    await Clipboard.setData(ClipboardData(text: md ? aiDocToMarkdown(widget.doc) : aiDocToPlain(widget.doc)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied')));
  }

  int _count(String kind) {
    var n = 0;
    for (final s in widget.doc.sections) {
      if (s.kind == kind) {
        final b = s.allBlocks.where((b) => b.type == 'b' || b.type == 'n' || b.type == 'p').length;
        n += b == 0 ? 1 : b;
      }
    }
    return n;
  }

  Widget _chipBox(BuildContext context, IconData icon, String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.45))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Flexible(child: m.Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c))),
        ]),
      );

  Widget _summary(BuildContext context) {
    final d = widget.doc;
    final dark = _dark(context);
    final chips = <Widget>[];
    final rf = _count('red_flags');
    final dm = _count('dont_miss');
    final steps = d.sections.fold<int>(0, (a, s) => a + s.allBlocks.where((b) => b.type == 'n').length);
    final tables = d.sections.fold<int>(0, (a, s) => a + s.allBlocks.where((b) => b.type == 't').length);
    if (rf > 0) chips.add(_chipBox(context, Icons.flag, trp(rf == 1 ? '{n} red flag' : '{n} red flags', {'n': rf}), toneColor(Tone.red, dark)));
    if (dm > 0) chips.add(_chipBox(context, Icons.error_outline, trp("{n} don't miss", {'n': dm}), toneColor(Tone.amber, dark)));
    if (steps > 1) chips.add(_chipBox(context, Icons.format_list_numbered, trp('{n} steps', {'n': steps}), _kindColor('management', dark)));
    if (tables > 0) chips.add(_chipBox(context, Icons.table_chart_outlined, trp(tables == 1 ? '{n} table' : '{n} tables', {'n': tables}), _kindColor('table', dark)));
    final claims = d.sections.any((s) => s.allBlocks.any((b) => b.type != 't' && _needsSource(b.text)));
    if (_showCites) {
      if (d.citations.isNotEmpty) {
        chips.add(_chipBox(context, Icons.menu_book_outlined, trp(d.citations.length == 1 ? '{n} source' : '{n} sources', {'n': d.citations.length}), toneColor(Tone.green, dark)));
      } else if (claims) {
        chips.add(_chipBox(context, Icons.link_off, tr('No sources given'), toneColor(Tone.amber, dark)));
      }
    }
    if (d.uncertainties.isNotEmpty) chips.add(_chipBox(context, Icons.help_outline, tr('Unverified parts'), _kindColor('uncertainties', dark)));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Wrap(spacing: 6, runSpacing: 6, children: chips));
  }

  /// One plain paragraph (a translation, a one-line answer): no toolbar, no chips.
  bool get _trivial {
    final d = widget.doc;
    return d.sections.length <= 1 &&
        d.citations.isEmpty &&
        d.uncertainties.isEmpty &&
        d.title.isEmpty &&
        d.sections.every((s) => s.kind == 'note' || s.allBlocks.every((b) => b.type == 'p'));
  }

  Widget _toolbar(BuildContext context) {
    if (_trivial && !widget.showCopy) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final n = widget.doc.sections.length;
    Widget btn(IconData ic, String label, VoidCallback f) => TextButton.icon(
          onPressed: f,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), foregroundColor: cs.onSurfaceVariant),
          icon: Icon(ic, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        );
    final allOpen = _collapsed.isEmpty;
    return Wrap(spacing: 2, runSpacing: 0, children: [
      if (n >= 3 && !_raw) btn(allOpen ? Icons.unfold_less : Icons.unfold_more, allOpen ? 'Collapse all' : 'Expand all', () => setState(() {
            if (allOpen) {
              _collapsed.addAll([for (var i = 0; i < n; i++) i]);
            } else {
              _collapsed.clear();
            }
          })),
      btn(_raw ? Icons.auto_awesome_mosaic_outlined : Icons.code, _raw ? 'Formatted' : 'Raw text', () => setState(() => _raw = !_raw)),
      if (widget.showCopy)
        PopupMenuButton<bool>(
          tooltip: tr('Copy'),
          onSelected: _copy,
          itemBuilder: (_) => [
            PopupMenuItem(value: false, child: Text('Copy as plain text')),
            PopupMenuItem(value: true, child: Text('Copy as Markdown')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.copy, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('Copy', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
    ]);
  }

  Widget _jump(BuildContext context) {
    final secs = widget.doc.sections;
    final dark = _dark(context);
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: secs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = secs[i];
          final c = _kindColor(s.kind, dark);
          final label = s.title.isNotEmpty ? s.title : tr(kKindLabel[s.kind] ?? 'Details');
          return ActionChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            avatar: Icon(_kindIcon(s.kind), size: 15, color: c),
            label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 130), child: m.Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
            onPressed: () {
              setState(() => _collapsed.remove(i));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final ctx = _keys[i].currentContext;
                if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.02);
              });
            },
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, {required Key? key, required String kind, required Color color, required IconData icon, required Widget title, required bool open, required VoidCallback onToggle, required Widget body, bool hideHeader = false}) {
    final cs = Theme.of(context).colorScheme;
    final callout = _isCallout(kind);
    final dark = _dark(context);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: callout ? color.withValues(alpha: dark ? 0.16 : 0.09) : cs.surface.withValues(alpha: dark ? 0.5 : 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: callout ? 0.6 : 0.3), width: kind == 'red_flags' ? 1.6 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!hideHeader)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 9),
                Expanded(child: title),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 22, color: cs.outline),
              ]),
            ),
          ),
        if (open || hideHeader) Padding(padding: EdgeInsets.fromLTRB(12, hideHeader ? 10 : 0, 12, 8), child: body),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final cs = Theme.of(context).colorScheme;
    final dark = _dark(context);
    final ctx = _Ctx(d.citations, _cite, _showCites);
    if (_keys.length != d.sections.length) _keys = [for (final _ in d.sections) GlobalKey()];

    if (_raw) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _toolbar(context),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
          child: SelectableText(d.raw, textDirection: textDirectionFor(d.raw), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4)),
        ),
      ]);
    }

    final cards = <Widget>[];
    for (var i = 0; i < d.sections.length; i++) {
      final s = d.sections[i];
      var color = _kindColor(s.kind, dark);
      var icon = _kindIcon(s.kind);
      if (s.kind == 'management') {
        final sc = _stabilityColor(s.title, dark);
        if (sc != null) {
          color = sc;
          icon = _unstableRx.hasMatch(s.title) ? Icons.emergency_outlined : Icons.check_circle_outline;
        }
      }
      final plainNote = s.kind == 'note' && s.title.isEmpty;
      final titleText = s.title.isNotEmpty ? s.title : tr(kKindLabel[s.kind] ?? 'Details');
      if (plainNote) {
        cards.add(Padding(key: _keys[i], padding: const EdgeInsets.only(bottom: 6), child: _Body(s, color, ctx)));
        continue;
      }
      cards.add(_card(
        context,
        key: _keys[i],
        kind: s.kind,
        color: color,
        icon: icon,
        open: !_collapsed.contains(i),
        onToggle: () => setState(() => _collapsed.contains(i) ? _collapsed.remove(i) : _collapsed.add(i)),
        hideHeader: plainNote,
        title: Directionality(
          textDirection: s.title.isNotEmpty ? _dirOf(context, s.title) : Directionality.of(context),
          child: m.Text(titleText, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ),
        body: _Body(s, color, ctx),
      ));
    }

    if (d.uncertainties.isNotEmpty) {
      final c = _kindColor('uncertainties', dark);
      cards.add(_card(
        context,
        key: null,
        kind: 'uncertainties',
        color: c,
        icon: Icons.help_outline,
        open: true,
        onToggle: () {},
        title: Text('What I could not verify', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final u in d.uncertainties)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Directionality(
                textDirection: _dirOf(context, u),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 3), child: Icon(Icons.help_outline, size: 14, color: c)),
                  const SizedBox(width: 8),
                  Expanded(child: _Rich(_cleanBullet(u), ctx, style: const TextStyle(fontSize: 14.5, height: 1.4))),
                ]),
              ),
            ),
        ]),
      ));
    }

    if (d.citations.isNotEmpty && _showCites) {
      final c = _kindColor('references', dark);
      cards.add(_card(
        context,
        key: null,
        kind: 'references',
        color: c,
        icon: Icons.menu_book_outlined,
        open: _refsOpen,
        onToggle: () => setState(() => _refsOpen = !_refsOpen),
        title: Text('References', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < d.citations.length; i++) _RefRow(i + 1, d.citations[i], () => _cite(d.citations[i])),
        ]),
      ));
    }

    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (d.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Directionality(textDirection: _dirOf(context, d.title), child: m.Text(d.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.3))),
          ),
        if (!_trivial) _summary(context),
        if (d.sections.length > 4) _jump(context),
        _toolbar(context),
        if (!_trivial || widget.showCopy) const SizedBox(height: 4),
        ...cards,
        if (d.disclaimer.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Directionality(textDirection: _dirOf(context, d.disclaimer), child: m.Text(d.disclaimer, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          ),
        if (widget.showDisclaimer)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 14, color: cs.outline),
              const SizedBox(width: 6),
              Expanded(child: Text(kAiDisclaimer, style: TextStyle(fontSize: 11.5, color: cs.outline, height: 1.35))),
            ]),
          ),
      ]),
    );
  }
}

String _cleanBullet(String s) => s.replaceFirst(RegExp(r'^\s*[-*•–]\s+'), '');

class _RefRow extends StatelessWidget {
  final int n;
  final AiCite c;
  final VoidCallback onTap;
  const _RefRow(this.n, this.c, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = c.label.isNotEmpty ? c.label : c.short;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Directionality(
          textDirection: _dirOf(context, label),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
              child: m.Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                m.Text(stripInline(label), style: const TextStyle(fontSize: 13.5, height: 1.35)),
                if (c.url.isNotEmpty && !label.contains(c.url))
                  m.Text(c.url, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: cs.primary)),
              ]),
            ),
            if (c.url.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2, left: 4, right: 4), child: Icon(Icons.open_in_new, size: 14, color: cs.outline)),
          ]),
        ),
      ),
    );
  }
}

/// Default tap on a citation: details sheet with copy / open link.
Future<void> showAiCiteSheet(BuildContext context, AiCite c) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final label = c.label.isNotEmpty ? c.label : c.short;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.menu_book_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Source', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            Directionality(textDirection: textDirectionFor(label) ?? Directionality.of(ctx), child: SelectableText(stripInline(label), style: const TextStyle(fontSize: 15, height: 1.4))),
            if (c.org.isNotEmpty || c.year.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: m.Text([c.org, c.year].where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: cs.onSurfaceVariant))),
            if (c.url.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(c.url, textDirection: TextDirection.ltr, style: TextStyle(color: cs.primary, fontSize: 13))),
            const SizedBox(height: 8),
            Text('Always verify with the original source and your local protocol.', style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (c.url.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final u = Uri.tryParse(c.url);
                    if (u != null) {
                      try {
                        await launchUrl(u, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text('Open link'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: c.url.isNotEmpty ? c.url : label));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(c.url.isNotEmpty ? 'Copy link' : 'Copy'),
              ),
            ]),
          ]),
        ),
      );
    },
  );
}
