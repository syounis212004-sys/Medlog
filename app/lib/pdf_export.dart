import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'case_extras.dart';
import 'case_scores.dart';
import 'choices_engine.dart';
import 'data.dart';
import 'goals_signoff.dart' show isSigned, signCell;
import 'i18n.dart';

/// PDF export that is safe for Arabic: the text is drawn by Flutter's own text
/// engine (shaping, right-to-left, Cairo font) onto page images, and the images
/// are placed in the PDF. The text is not selectable, but it always looks right.
///
/// The look is a "study sheet": a header band with tags, numbered section headings
/// with icons, a red-flag box, boxed management steps, tables and coloured callouts.
/// Everything shown comes from the user's own entries; nothing is added or guessed.

const double _pw = 1240; // A4 at 150 dpi
const double _ph = 1754;
const double _margin = 90;
const double _footerH = 120;

// ---------------------------------------------------------------- colours

const Color _navy = Color(0xFF1F3A5F);
const Color _teal = Color(0xFF0F766E);
const Color _ink = Color(0xFF14181F);
const Color _muted = Color(0xFF5B6573);
const Color _line = Color(0xFFD5DAE1);
const Color _red = Color(0xFFC62828);
const Color _redBg = Color(0xFFFDECEC);
const Color _amberBg = Color(0xFFFFF4DC);
const Color _amberInk = Color(0xFF8A5A00);
const Color _greenBg = Color(0xFFE8F5E9);
const Color _green = Color(0xFF2E7D32);
const Color _blueBg = Color(0xFFEAF1FA);
const Color _white = Color(0xFFFFFFFF);

// ---------------------------------------------------------------- clinical status tag

/// Status at presentation, as chosen by the user in the case editor (stored in
/// `cstatus`; the field `status` is the record status Draft / Active ...).
/// Nothing is derived from free text. Empty = not recorded.
const List<String> kClinStatuses = ['Stable', 'Improving', 'Unstable', 'Critical'];

String clinStatusOf(CaseRec c) {
  final v = c.s('cstatus');
  return kClinStatuses.contains(v) ? v : '';
}

Color clinStatusColor(String s) {
  switch (s) {
    case 'Stable':
      return const Color(0xFF2E7D32);
    case 'Unstable':
      return const Color(0xFFD32F2F);
    case 'Critical':
      return const Color(0xFF7F0000);
    case 'Improving':
      return const Color(0xFFE69500);
  }
  return const Color(0xFF777777);
}

/// Text colour that reads on top of [clinStatusColor].
Color clinStatusOnColor(String s) => s == 'Improving' ? const Color(0xFF2B1D00) : _white;

// ---------------------------------------------------------------- text helpers

bool _isRtlLine(String s) {
  var ar = 0, lat = 0;
  for (final r in s.runes) {
    if (r >= 0x0600 && r <= 0x06FF) {
      ar++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      lat++;
    }
  }
  return ar > lat;
}

String get _family => isAr ? 'Cairo' : 'Tinos';

TextStyle _ts(double size, {bool bold = false, Color color = _ink, double height = 1.4}) => TextStyle(
      color: color,
      fontFamily: _family,
      fontFamilyFallback: const ['Cairo', 'Tinos'],
      fontSize: size,
      height: height,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    );

TextDirection _dir(String s) => _isRtlLine(s) ? TextDirection.rtl : TextDirection.ltr;

class PdfPill {
  final String label;
  final Color color;
  final Color onColor;
  const PdfPill(this.label, this.color, [this.onColor = _white]);
}

// ---------------------------------------------------------------- icons (vector, no font needed)

void _icon(Canvas c, String kind, Rect r, Color col) {
  final p = Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = r.width * 0.11
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final f = Paint()..color = col;
  final cx = r.center.dx, cy = r.center.dy, s = r.width;
  switch (kind) {
    case 'cross':
      p.strokeWidth = s * .18;
      c.drawLine(Offset(cx, cy - s * .32), Offset(cx, cy + s * .32), p);
      c.drawLine(Offset(cx - s * .32, cy), Offset(cx + s * .32, cy), p);
      break;
    case 'pulse':
      c.drawPath(
          Path()
            ..moveTo(cx - s * .38, cy)
            ..lineTo(cx - s * .16, cy)
            ..lineTo(cx - s * .06, cy - s * .3)
            ..lineTo(cx + s * .08, cy + s * .3)
            ..lineTo(cx + s * .18, cy)
            ..lineTo(cx + s * .38, cy),
          p);
      break;
    case 'flag':
      c.drawLine(Offset(cx - s * .22, cy - s * .34), Offset(cx - s * .22, cy + s * .36), p);
      c.drawPath(
          Path()
            ..moveTo(cx - s * .22, cy - s * .34)
            ..lineTo(cx + s * .3, cy - s * .2)
            ..lineTo(cx - s * .22, cy + s * .02)
            ..close(),
          f);
      break;
    case 'flask':
      c.drawPath(
          Path()
            ..moveTo(cx - s * .1, cy - s * .34)
            ..lineTo(cx - s * .1, cy - s * .08)
            ..lineTo(cx - s * .32, cy + s * .3)
            ..lineTo(cx + s * .32, cy + s * .3)
            ..lineTo(cx + s * .1, cy - s * .08)
            ..lineTo(cx + s * .1, cy - s * .34),
          p);
      c.drawLine(Offset(cx - s * .16, cy - s * .34), Offset(cx + s * .16, cy - s * .34), p);
      break;
    case 'arrow':
      c.drawLine(Offset(cx - s * .34, cy), Offset(cx + s * .3, cy), p);
      c.drawPath(
          Path()
            ..moveTo(cx + s * .06, cy - s * .24)
            ..lineTo(cx + s * .32, cy)
            ..lineTo(cx + s * .06, cy + s * .24),
          p);
      break;
    case 'list':
      for (var i = -1; i <= 1; i++) {
        final y = cy + i * s * .24;
        c.drawCircle(Offset(cx - s * .3, y), s * .05, f);
        c.drawLine(Offset(cx - s * .16, y), Offset(cx + s * .34, y), p);
      }
      break;
    case 'chart':
      for (var i = 0; i < 3; i++) {
        final h = s * (.22 + i * .16);
        c.drawRect(Rect.fromLTWH(cx - s * .32 + i * s * .24, cy + s * .32 - h, s * .17, h), f);
      }
      break;
    case 'check':
      p.strokeWidth = s * .15;
      c.drawPath(
          Path()
            ..moveTo(cx - s * .3, cy + s * .02)
            ..lineTo(cx - s * .08, cy + s * .26)
            ..lineTo(cx + s * .32, cy - s * .24),
          p);
      break;
    case 'person':
      c.drawCircle(Offset(cx, cy - s * .16), s * .14, f);
      c.drawArc(Rect.fromCenter(center: Offset(cx, cy + s * .36), width: s * .66, height: s * .66), math.pi, math.pi, true, f);
      break;
    default:
      c.drawCircle(Offset(cx, cy), s * .2, f);
  }
}

// ---------------------------------------------------------------- layout model

typedef _Draw = void Function(Canvas c, double x, double y, double w);

class _Row {
  final double h;
  final _Draw draw;
  _Row(this.h, this.draw);
}

class _Page {
  bool hasBand = false;
  final List<void Function(Canvas)> ops = [];
}

abstract class _Item {
  /// Loads what the item needs (pictures) before the pages are laid out.
  Future<void> prepare() async {}
  void place(_Flow f);
}

/// The pictures of a case, two to a row, each with its caption. A file that is missing or cannot be read is
/// named in a note instead of silently disappearing.
class _ImagesItem extends _Item {
  final List<({String path, String caption})> files;
  final _loaded = <({ui.Image? img, String caption})>[];
  _ImagesItem(this.files);

  @override
  Future<void> prepare() async {
    for (final e in files) {
      ui.Image? img;
      try {
        final bytes = await File(e.path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1100);
        img = (await codec.getNextFrame()).image;
      } catch (_) {}
      _loaded.add((img: img, caption: e.caption));
    }
  }

  @override
  void place(_Flow f) {
    final k = f.k;
    final gap = 24.0 * k;
    final cellW = (f.contentW - gap) / 2;
    for (var i = 0; i < _loaded.length; i += 2) {
      final row = _loaded.skip(i).take(2).toList();
      final cells = <({ui.Image? img, TextPainter cap, double h, double w})>[];
      var rowH = 0.0;
      for (final e in row) {
        final cap = _layoutSpan(
            TextSpan(text: e.img == null ? '${tr('Image not available')}: ${e.caption}' : e.caption, style: _ts(24 * k, color: _muted, height: 1.3)),
            cellW,
            _isRtlLine(e.caption) ? TextDirection.rtl : TextDirection.ltr);
        var w = cellW, h = 0.0;
        if (e.img != null) {
          final ratio = e.img!.height / e.img!.width;
          h = cellW * ratio;
          if (h > 640 * k) {
            h = 640 * k;
            w = h / ratio;
          }
        }
        cells.add((img: e.img, cap: cap, h: h, w: w));
        rowH = math.max(rowH, h + cap.height + 14);
      }
      f.ensure(rowH + 20);
      final y = f.y;
      final x0 = f.left;
      f.page.ops.add((c) {
        for (var j = 0; j < cells.length; j++) {
          final cell = cells[j];
          final x = x0 + j * (cellW + gap);
          if (cell.img != null) {
            c.drawImageRect(cell.img!, Rect.fromLTWH(0, 0, cell.img!.width.toDouble(), cell.img!.height.toDouble()),
                Rect.fromLTWH(x, y, cell.w, cell.h), Paint()..filterQuality = FilterQuality.medium);
          }
          cell.cap.paint(c, Offset(x, y + cell.h + 8));
        }
      });
      f.y += rowH + 16;
    }
  }
}

class _Flow {
  final bool rtl;
  final double k;
  final pages = <_Page>[_Page()];
  double y = _margin;
  double bandBottom = 0;
  _Flow(this.rtl, this.k);

  double get contentW => _pw - 2 * _margin;
  double get bottom => _ph - _footerH;
  double get left => _margin;
  _Page get page => pages.last;
  bool get atTop => y <= _margin + 1 || y <= bandBottom + 1;

  void newPage() {
    pages.add(_Page());
    y = _margin;
    bandBottom = 0;
  }

  void ensure(double h) {
    if (y + h > bottom && !atTop) newPage();
  }
}

TextPainter _layoutSpan(InlineSpan span, double w, TextDirection dir, {TextAlign align = TextAlign.start}) {
  return TextPainter(text: span, textDirection: dir, textAlign: align)..layout(minWidth: w, maxWidth: w);
}

/// A paragraph that may flow over page boundaries.
class _ParaItem extends _Item {
  final String label;
  final String text;
  final bool boldText;
  final Color labelColor;
  _ParaItem(this.label, this.text, this.boldText, this.labelColor);

  @override
  void place(_Flow f) {
    final k = f.k;
    final body = text.trim();
    final spans = <InlineSpan>[
      if (label.isNotEmpty) TextSpan(text: '$label: ', style: _ts(25 * k, bold: true, color: labelColor)),
      TextSpan(text: body, style: _ts(25 * k, bold: boldText || k > 1.2)),
    ];
    final tp = _layoutSpan(TextSpan(children: spans), f.contentW, _dir(body.isEmpty ? label : body));
    _flowText(f, tp, f.left, f.contentW, gap: 8 * k);
  }
}

/// Places a painter, splitting between lines when it does not fit the page.
void _flowText(_Flow f, TextPainter tp, double x, double w, {double gap = 6}) {
  final lines = tp.computeLineMetrics();
  var start = 0.0; // y inside tp where the next chunk starts
  var li = 0;
  while (li < lines.length) {
    var avail = f.bottom - f.y;
    if (avail < lines[li].height && !f.atTop) {
      f.newPage();
      avail = f.bottom - f.y;
    }
    var end = start;
    var lj = li;
    while (lj < lines.length && (lines[lj].baseline + lines[lj].descent - start) <= avail + 0.5) {
      end = lines[lj].baseline + lines[lj].descent;
      lj++;
    }
    if (lj == li) {
      end = lines[li].baseline + lines[li].descent;
      lj = li + 1;
    }
    if (lj >= lines.length) end = tp.height;
    final top = f.y, s0 = start, hh = end - start;
    f.page.ops.add((c) {
      c.save();
      c.clipRect(Rect.fromLTWH(x - 4, top, w + 8, hh));
      tp.paint(c, Offset(x, top - s0));
      c.restore();
    });
    f.y += hh;
    start = end;
    li = lj;
    if (li < lines.length) f.newPage();
  }
  f.y += gap;
}

/// Blank lines to fill in by hand (name, role, signature, date). Labels sit two to a row.
class _SignItem extends _Item {
  final String title;
  final List<String> labels;
  _SignItem(this.title, this.labels);

  @override
  void place(_Flow f) {
    final k = f.k;
    final rtl = f.rtl;
    final rowH = 92 * k;
    final rows = (labels.length + 1) ~/ 2;
    final titleTp = title.isEmpty
        ? null
        : _layoutSpan(TextSpan(text: title, style: _ts(27 * k, bold: true, color: _navy, height: 1.2)), f.contentW,
            rtl ? TextDirection.rtl : TextDirection.ltr);
    final th = titleTp == null ? 0.0 : titleTp.height + 16 * k;
    f.ensure(th + rows * rowH + 10 * k);
    final x0 = f.left, w = f.contentW, gap = 40.0;
    final colW = (w - gap) / 2;
    final top = f.y;
    final tps = <TextPainter>[
      for (final l in labels) _layoutSpan(TextSpan(text: l, style: _ts(22 * k, color: _muted, height: 1.2)), colW, rtl ? TextDirection.rtl : TextDirection.ltr),
    ];
    f.page.ops.add((c) {
      if (titleTp != null) titleTp.paint(c, Offset(x0, top));
      for (var i = 0; i < tps.length; i++) {
        final col = i % 2, row = i ~/ 2;
        final cx = rtl ? x0 + w - colW - col * (colW + gap) : x0 + col * (colW + gap);
        final y = top + th + row * rowH;
        tps[i].paint(c, Offset(cx, y));
        c.drawLine(Offset(cx, y + rowH - 14 * k), Offset(cx + colW, y + rowH - 14 * k), Paint()..color = _ink..strokeWidth = 1.6);
      }
    });
    f.y += th + rows * rowH + 10 * k;
  }
}

class _SpaceItem extends _Item {
  final double h;
  _SpaceItem(this.h);
  @override
  void place(_Flow f) {
    f.y += h;
  }
}

class _BreakItem extends _Item {
  @override
  void place(_Flow f) {
    if (!f.atTop || f.page.ops.isNotEmpty) f.newPage();
  }
}

class _SectionItem extends _Item {
  final int n;
  final String title;
  final String icon;
  final Color color;
  _SectionItem(this.n, this.title, this.icon, this.color);

  @override
  void place(_Flow f) {
    final k = f.k;
    final size = 54.0 * k;
    final rtl = f.rtl;
    final tp = _layoutSpan(TextSpan(text: title, style: _ts(34 * k, bold: true, color: color, height: 1.2)), f.contentW - size - 120,
        rtl ? TextDirection.rtl : TextDirection.ltr);
    final h = math.max(size, tp.height) + 22;
    f.ensure(h + 170 * k); // keep the heading with the first lines below it
    final y = f.y + 14, x = f.left, w = f.contentW;
    final nt = _layoutSpan(TextSpan(text: '$n', style: _ts(32 * k, bold: true, color: color.withValues(alpha: .4), height: 1.0)), 80,
        TextDirection.ltr, align: rtl ? TextAlign.left : TextAlign.right);
    f.page.ops.add((c) {
      final bx = rtl ? x + w - size : x;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, y, size, size), const Radius.circular(12)), Paint()..color = color);
      _icon(c, icon, Rect.fromLTWH(bx + size * .12, y + size * .12, size * .76, size * .76), _white);
      tp.paint(c, Offset(rtl ? x + w - size - 18 - tp.width : x + size + 18, y + (size - tp.height) / 2));
      nt.paint(c, Offset(rtl ? x : x + w - 80, y + (size - nt.height) / 2));
      c.drawLine(Offset(x, y + size + 10), Offset(x + w, y + size + 10), Paint()..color = color.withValues(alpha: .5)..strokeWidth = 2.5);
    });
    f.y += h + 14;
  }
}

enum _GroupKind { callout, steps, table }

/// Boxed content made of rows (callout, steps, table). Rows move between pages whole.
class _GroupItem extends _Item {
  final _GroupKind kind;
  final String title;
  final String icon;
  final Color color; // accent
  final Color bg;
  final List<String> lines; // callout / steps
  final List<String> head; // table
  final List<List<String>> rows; // table
  final List<double> weights;
  final List<Color?> rowInk;
  _GroupItem(this.kind, this.title, this.icon, this.color, this.bg, this.lines, this.head, this.rows, this.weights, this.rowInk);

  @override
  void place(_Flow f) {
    final k = f.k;
    final rtl = f.rtl;
    final w = f.contentW;
    final pad = 22.0 * k;
    final isTable = kind == _GroupKind.table;
    final inner = w - 2 * pad - (kind == _GroupKind.callout ? 14 : 0);
    final all = <_Row>[];
    _Row? titleRow;
    if (title.isNotEmpty) {
      final tp = _layoutSpan(TextSpan(text: title, style: _ts(28 * k, bold: true, color: color, height: 1.2)), inner - 50 * k,
          rtl ? TextDirection.rtl : TextDirection.ltr);
      final hh = math.max(tp.height, 34 * k) + 14 * k;
      titleRow = _Row(hh, (c, x, y, ww) {
        _icon(c, icon, Rect.fromLTWH(rtl ? x + ww - 34 * k : x, y + 2, 34 * k, 34 * k), color);
        tp.paint(c, Offset(rtl ? x : x + 46 * k, y + 3));
      });
    }
    switch (kind) {
      case _GroupKind.callout:
        for (final t in lines) {
          final tp = _layoutSpan(TextSpan(text: t, style: _ts(25 * k, bold: k > 1.2)), inner - 30 * k, _dir(t));
          all.add(_Row(tp.height + 8 * k, (c, x, y, ww) {
            c.drawCircle(Offset(rtl ? x + ww - 8 * k : x + 8 * k, y + 18 * k), 5 * k, Paint()..color = color);
            tp.paint(c, Offset(rtl ? x : x + 30 * k, y));
          }));
        }
        break;
      case _GroupKind.steps:
        for (var i = 0; i < lines.length; i++) {
          final parts = lines[i].split('\n');
          final tp = _layoutSpan(
              TextSpan(children: [
                TextSpan(text: parts.first, style: _ts(26 * k, bold: true)),
                if (parts.length > 1) TextSpan(text: '\n${parts.skip(1).join('\n')}', style: _ts(21 * k, color: _muted)),
              ]),
              inner - 100 * k,
              _dir(lines[i]));
          final bh = math.max(tp.height + 24 * k, 60 * k);
          final last = i == lines.length - 1;
          final n = i + 1;
          all.add(_Row(bh + (last ? 0 : 34 * k), (c, x, y, ww) {
            final box = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, ww, bh), const Radius.circular(12));
            c.drawRRect(box, Paint()..color = _white);
            c.drawRRect(box, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);
            final cr = 22 * k;
            final cx = rtl ? x + ww - 14 * k - cr : x + 14 * k + cr;
            c.drawCircle(Offset(cx, y + bh / 2), cr, Paint()..color = color);
            final nt = _layoutSpan(TextSpan(text: '$n', style: _ts(24 * k, bold: true, color: _white, height: 1.0)), cr * 2, TextDirection.ltr,
                align: TextAlign.center);
            nt.paint(c, Offset(cx - cr, y + bh / 2 - nt.height / 2));
            final tw = ww - 2 * 14 * k - cr * 2 - 16 * k;
            tp.paint(c, Offset(rtl ? x + 14 * k : x + 14 * k + cr * 2 + 16 * k, y + (bh - tp.height) / 2));
            assert(tw > 0);
            if (!last) {
              final ax = x + ww / 2, ay = y + bh + 4;
              final p = Paint()..color = color..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
              c.drawLine(Offset(ax, ay), Offset(ax, ay + 24 * k), p);
              c.drawPath(
                  Path()
                    ..moveTo(ax - 9 * k, ay + 14 * k)
                    ..lineTo(ax, ay + 26 * k)
                    ..lineTo(ax + 9 * k, ay + 14 * k),
                  p);
            }
          }));
        }
        break;
      case _GroupKind.table:
        final tk = math.min(k, 1.12); // tables grow less than text so cells keep their shape
        final colW = _colWidths(w, head.length, weights);
        _Row mk(List<String> cells, {required bool header, required bool zebra, Color? ink}) {
          final tps = <TextPainter>[];
          var maxH = 0.0;
          for (var i = 0; i < cells.length; i++) {
            final t = cells[i];
            final tp = _layoutSpan(
                TextSpan(
                    text: t.isEmpty ? ' ' : t,
                    style: _ts((header ? 22 : 23) * tk, bold: header || ink != null, color: header ? _white : (ink ?? _ink), height: 1.3)),
                colW[i] - 16 * tk,
                t.isEmpty ? (rtl ? TextDirection.rtl : TextDirection.ltr) : _dir(t));
            tps.add(tp);
            maxH = math.max(maxH, tp.height);
          }
          final rh = maxH + 16 * tk;
          return _Row(rh, (c, x, y, ww) {
            if (header) {
              c.drawRect(Rect.fromLTWH(x, y, ww, rh), Paint()..color = color);
            } else if (zebra) {
              c.drawRect(Rect.fromLTWH(x, y, ww, rh), Paint()..color = const Color(0xFFF3F5F8));
            }
            var cx = rtl ? x + ww : x;
            for (var i = 0; i < tps.length; i++) {
              final cw = colW[i];
              tps[i].paint(c, Offset(rtl ? cx - cw + 8 * tk : cx + 8 * tk, y + 8 * tk));
              cx += rtl ? -cw : cw;
            }
            c.drawLine(Offset(x, y + rh), Offset(x + ww, y + rh), Paint()..color = _line..strokeWidth = 1.5);
          });
        }
        all.add(mk(head, header: true, zebra: false));
        for (var i = 0; i < rows.length; i++) {
          all.add(mk(rows[i], header: false, zebra: i.isOdd, ink: i < rowInk.length ? rowInk[i] : null));
        }
        break;
    }

    // paginate rows into chunks; a table repeats its header row on each page
    var i = 0;
    var first = true;
    final hdr = isTable ? all.first : null;
    if (isTable) i = 1;
    while (first || i < all.length) {
      final tRow = first ? titleRow : null;
      final repeat = isTable && !first ? hdr : null;
      final extra = (tRow?.h ?? 0) + (repeat?.h ?? 0) + (isTable ? 0 : pad * 1.2);
      final headerH = isTable && first ? hdr!.h : 0.0;
      final nextH = i < all.length ? all[i].h : 0.0;
      final next2 = isTable && first && i + 1 < all.length ? all[i + 1].h : 0.0;
      f.ensure(extra + headerH + nextH + next2);
      var avail = f.bottom - f.y - extra - headerH;
      final chunk = <_Row>[];
      while (i < all.length && (all[i].h <= avail || chunk.isEmpty)) {
        chunk.add(all[i]);
        avail -= all[i].h;
        i++;
      }
      final rowsH = chunk.fold<double>(0, (a, r) => a + r.h);
      final boxH = extra + headerH + rowsH;
      final top = f.y, x = f.left;
      final showHdr = isTable ? (first ? hdr : repeat) : null;
      f.page.ops.add((c) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, top, w, boxH), const Radius.circular(14));
        if (!isTable) {
          c.drawRRect(r, Paint()..color = bg);
          c.drawRRect(r, Paint()..color = color.withValues(alpha: .55)..style = PaintingStyle.stroke..strokeWidth = 2);
          c.save();
          c.clipRRect(r);
          c.drawRect(Rect.fromLTWH(rtl ? x + w - 12 : x, top, 12, boxH), Paint()..color = color);
          c.restore();
        }
        var yy = top + (isTable ? 0 : pad * .6);
        final ix = x + pad + (kind == _GroupKind.callout && !rtl ? 14 : 0);
        final iw = w - 2 * pad - (kind == _GroupKind.callout ? 14 : 0);
        if (tRow != null) {
          tRow.draw(c, ix, yy, iw);
          yy += tRow.h;
        }
        if (isTable) {
          c.save();
          c.clipRRect(r);
          if (showHdr != null) {
            showHdr.draw(c, x, yy, w);
            yy += showHdr.h;
          }
          for (final rr in chunk) {
            rr.draw(c, x, yy, w);
            yy += rr.h;
          }
          c.restore();
          c.drawRRect(r, Paint()..color = _line..style = PaintingStyle.stroke..strokeWidth = 2);
        } else {
          for (final rr in chunk) {
            rr.draw(c, ix, yy, iw);
            yy += rr.h;
          }
        }
      });
      f.y += boxH + 14;
      first = false;
      if (i < all.length) f.newPage();
    }
  }
}

List<double> _colWidths(double total, int n, List<double> weights) {
  final w = weights.length == n ? weights : List<double>.filled(n, 1);
  final sum = w.fold<double>(0, (a, b) => a + b);
  return [for (final x in w) total * x / sum];
}

class _BandItem extends _Item {
  final String title;
  final String subtitle;
  final List<PdfPill> pills;
  final Color color;
  _BandItem(this.title, this.subtitle, this.pills, this.color);

  @override
  void place(_Flow f) {
    final k = f.k;
    if (f.page.ops.isNotEmpty) f.newPage();
    final rtl = f.rtl;
    final w = _pw - 2 * _margin;
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(title);
    final tt = _layoutSpan(TextSpan(text: title, style: _ts(44 * k, bold: true, color: _white, height: 1.15)), w,
        _isRtlLine(title) || (rtl && !hasLatin) ? TextDirection.rtl : TextDirection.ltr);
    final st = subtitle.isEmpty
        ? null
        : _layoutSpan(TextSpan(text: subtitle, style: _ts(25 * k, color: const Color(0xFFD6E2F3), height: 1.3)), w, _dir(subtitle));
    final pts = <TextPainter>[
      for (final p in pills)
        TextPainter(
          text: TextSpan(text: p.label, style: _ts(23 * k, bold: true, color: p.onColor, height: 1.1)),
          textDirection: _dir(p.label),
        )..layout()
    ];
    final ph = 44.0 * k;
    final lay = <List<int>>[];
    var cur = <int>[];
    var cw = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final pwid = pts[i].width + 36 * k;
      if (cur.isNotEmpty && cw + pwid + 12 > w) {
        lay.add(cur);
        cur = [];
        cw = 0;
      }
      cur.add(i);
      cw += pwid + 12;
    }
    if (cur.isNotEmpty) lay.add(cur);
    final pillsH = lay.length * (ph + 10);
    final bandH = 44 + tt.height + (st == null ? 0 : st.height + 8) + (pillsH > 0 ? pillsH + 14 : 0) + 34;
    f.page.hasBand = true;
    f.page.ops.add((c) {
      c.drawRect(Rect.fromLTWH(0, 0, _pw, bandH), Paint()..color = color);
      c.drawRect(Rect.fromLTWH(0, bandH, _pw, 8), Paint()..color = _teal);
      var y = 44.0;
      tt.paint(c, Offset(_margin, y));
      y += tt.height + 8;
      if (st != null) {
        st.paint(c, Offset(_margin, y));
        y += st.height + 8;
      }
      y += 14;
      for (final rowIdx in lay) {
        var x = rtl ? _pw - _margin : _margin;
        for (final i in rowIdx) {
          final pwid = pts[i].width + 36 * k;
          final rx = rtl ? x - pwid : x;
          final r = RRect.fromRectAndRadius(Rect.fromLTWH(rx, y, pwid, ph), Radius.circular(ph / 2));
          c.drawRRect(r, Paint()..color = pills[i].color);
          c.drawRRect(r, Paint()..color = _white..style = PaintingStyle.stroke..strokeWidth = 2.5);
          pts[i].paint(c, Offset(rx + 18 * k, y + (ph - pts[i].height) / 2));
          x += rtl ? -(pwid + 12) : (pwid + 12);
        }
        y += ph + 10;
      }
    });
    f.y = bandH + 8 + 30;
    f.bandBottom = f.y;
  }
}

// ---------------------------------------------------------------- the document builder

class PdfDoc {
  final bool large;
  final String footer;
  final List<_Item> _items = [];
  int _sec = 0;
  PdfDoc({this.large = false, this.footer = 'MedLog  •  Dr. Mohammed Samir Abu Younis'});

  static const _secColors = [_navy, _teal, Color(0xFF6A4C93), Color(0xFF9A4D00), Color(0xFF1565C0), Color(0xFF455A64)];

  /// Header band (starts a new page) with a title, a sub line and coloured tags.
  void band(String title, {String subtitle = '', List<PdfPill> pills = const [], Color color = _navy}) {
    _sec = 0;
    _items.add(_BandItem(title, subtitle, pills, color));
  }

  /// Numbered section heading with an icon: cross, pulse, flag, flask, arrow, list, chart, check, person.
  void section(String title, {String icon = 'list'}) {
    _sec++;
    _items.add(_SectionItem(_sec, title, icon, _secColors[(_sec - 1) % _secColors.length]));
  }

  /// A paragraph; [label] is shown in bold colour in front of the text.
  void para(String label, String text, {bool boldText = false, Color labelColor = _navy}) {
    if (text.trim().isEmpty) return;
    _items.add(_ParaItem(label, text, boldText, labelColor));
  }

  /// Coloured box with bullet lines. kind: red, amber, green, info.
  void callout(String title, List<String> lines, {String kind = 'info', String icon = 'flag'}) {
    final items = lines.where((e) => e.trim().isNotEmpty).toList();
    if (items.isEmpty) return;
    Color c, bg;
    switch (kind) {
      case 'red':
        c = _red;
        bg = _redBg;
        break;
      case 'amber':
        c = _amberInk;
        bg = _amberBg;
        break;
      case 'green':
        c = _green;
        bg = _greenBg;
        break;
      default:
        c = _navy;
        bg = _blueBg;
    }
    _items.add(_GroupItem(_GroupKind.callout, title, icon, c, bg, items, const [], const [], const [], const []));
  }

  /// Boxed steps joined by arrows. A step's second line (after \n) is shown smaller.
  void steps(List<String> steps, {String title = ''}) {
    final items = steps.where((e) => e.trim().isNotEmpty).toList();
    if (items.isEmpty) return;
    _items.add(_GroupItem(_GroupKind.steps, title, 'arrow', _teal, const Color(0xFFE6F4F2), items, const [], const [], const [], const []));
  }

  void table(List<String> head, List<List<String>> rows, {List<double> weights = const [], List<Color?> rowInk = const []}) {
    if (rows.isEmpty) return;
    _items.add(_GroupItem(_GroupKind.table, '', 'list', _navy, _white, const [], head, rows, weights, rowInk));
  }

  /// Lines to fill in by hand: pass labels such as "Supervisor name", "Role", "Signature", "Date".
  void signLines(String title, List<String> labels) {
    if (labels.isEmpty) return;
    _items.add(_SignItem(title, labels));
  }

  void space([double h = 14]) => _items.add(_SpaceItem(h));
  void images(List<({String path, String caption})> files) => _items.add(_ImagesItem(files));
  void pageBreak() => _items.add(_BreakItem());

  Future<List<Uint8List>> render() async {
    final f = _Flow(isAr, large ? 1.3 : 1.0);
    for (final it in _items) {
      await it.prepare();
      it.place(f);
    }
    final out = <Uint8List>[];
    final total = f.pages.length;
    for (var n = 0; n < total; n++) {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, _pw, _ph));
      canvas.drawRect(const Rect.fromLTWH(0, 0, _pw, _ph), Paint()..color = _white);
      if (!f.pages[n].hasBand) {
        canvas.drawRect(const Rect.fromLTWH(0, 0, _pw, 14), Paint()..color = _navy);
      }
      for (final op in f.pages[n].ops) {
        op(canvas);
      }
      _footer(canvas, n + 1, total, f.rtl);
      final img = await rec.endRecording().toImage(_pw.toInt(), _ph.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      out.add(data!.buffer.asUint8List());
    }
    return out;
  }

  void _footer(Canvas c, int n, int total, bool rtl) {
    final y = _ph - 100;
    c.drawLine(Offset(_margin, y), Offset(_pw - _margin, y), Paint()..color = _line..strokeWidth = 2);
    final left = TextPainter(
      text: TextSpan(text: footer, style: const TextStyle(color: _muted, fontFamily: 'Tinos', fontFamilyFallback: ['Cairo'], fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _pw - 2 * _margin - 200);
    final num = TextPainter(
      text: TextSpan(text: '$n / $total', style: const TextStyle(color: _navy, fontFamily: 'Tinos', fontSize: 22, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final note = TextPainter(
      text: TextSpan(
          text: tr('MedLog adds no patient names or ID numbers. Check the text before you share.'),
          style: TextStyle(color: _muted, fontFamily: _family, fontFamilyFallback: const ['Cairo', 'Tinos'], fontSize: 18)),
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
    )..layout(minWidth: _pw - 2 * _margin, maxWidth: _pw - 2 * _margin);
    left.paint(c, Offset(rtl ? _pw - _margin - left.width : _margin, y + 10));
    num.paint(c, Offset(rtl ? _margin : _pw - _margin - num.width, y + 10));
    note.paint(c, Offset(_margin, y + 44));
  }
}

// ---------------------------------------------------------------- case content

String _join(Iterable<String> a, [String sep = ' • ']) => a.where((e) => e.trim().isNotEmpty).join(sep);

List<String> _splitLines(String s) {
  final out = <String>[];
  for (final raw in s.split(RegExp(r'[\n;]'))) {
    final t = raw.trim().replaceFirst(RegExp(r'^[\-•*]\s*'), '');
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// Items the user flagged: the "Red flags" text and every system marked Abnormal.
List<String> flaggedItems(CaseRec c) {
  final out = <String>[..._splitLines(c.s('redFlags'))];
  final sys = c.d['sys'];
  if (sys is Map) {
    for (final e in sys.entries) {
      final v = e.value;
      if (v is Map && v['s'] == 'Abnormal') {
        final n = (v['n'] ?? '').toString().trim();
        out.add('${tr('Abnormal')}: ${tr(e.key.toString())}${n.isEmpty ? '' : ' - $n'}');
      }
    }
  }
  return out;
}

/// Adds one case (starting on a new page) to [d].
/// The quick choices of one part of the case as a small table under that part.
void _choiceTable(PdfDoc d, List<List<String>> rows) {
  if (rows.isEmpty) return;
  d.table([tr('Item'), tr('Selection'), tr('Details')], rows, weights: [1.6, 2.6, 1.6]);
}

/// The case read as a story, one paragraph per stage: who came and why, background, what was found, what was ordered,
/// what was thought, what was done, how it ended. Choices and the typed fields are woven together.
List<List<String>> caseStory(CaseRec c) {
  String s(String k) => c.s(k).trim();
  final cc = CaseChoices(c);
  String sel(String section) => [
        for (final r in cc.lines(section: section))
          if (r.length > 1 && r[1].trim().isNotEmpty) '${r[0]}: ${r[1]}${r.length > 2 && r[2].trim().isNotEmpty ? ' (${r[2]})' : ''}'
      ].join('; ');
  String lab(String l, String v) => v.trim().isEmpty ? '' : '$l: ${v.trim()}';
  final out = <List<String>>[];
  void add(String heading, List<String> parts) {
    final t = parts.where((e) => e.trim().isNotEmpty).map((e) => e.trim()).map((e) => e.endsWith('.') ? e : '$e.').join(' ');
    if (t.isNotEmpty) out.add([heading, t]);
  }

  final who = _join([tr(s('ageGroup')), tr(s('sex'))], ' ');
  final where = _join([tr(s('setting')), tr(s('encounter')), tr(s('specialty'))], ', ');
  add(tr('Presentation'), [_join([who, where], ' - '), lab(tr('Chief complaint'), s('cc')), lab(tr('History of present illness'), s('hpi')), sel('History')]);
  add(tr('Background'), [
    lab(tr('Past medical history'), s('pmh')),
    lab(tr('Past surgical history'), s('psh')),
    lab(tr('Drugs'), s('drugs')),
    lab(tr('Allergies'), s('allergies')),
    lab(tr('Family history'), s('family')),
    lab(tr('Social history'), s('social')),
  ]);
  final vit = [
    ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'], ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'], ['Wt', 'v_wt'],
  ].where((e) => s(e[1]).isNotEmpty).map((e) => '${e[0]} ${s(e[1])}').join(', ');
  add(tr('Examination'), [lab(tr('Vital signs'), vit), s('examGeneral'), s('examSystemic'), s('examFocused'), sel('Examination')]);
  final inv = [
    for (final i in c.lst('inv'))
      if ('${i['name'] ?? ''}'.trim().isNotEmpty)
        '${i['name']}${'${i['result'] ?? ''}'.trim().isEmpty ? ' (${tr('${i['status'] ?? ''}')})' : ': ${i['result']}'}${'${i['interpretation'] ?? ''}'.trim().isEmpty ? '' : ' - ${i['interpretation']}'}'
  ];
  add(tr('Investigations'), [inv.join('; '), sel('Investigations')]);
  add(tr('Assessment'), [
    lab(tr('Working diagnosis'), s('workingDx')),
    lab(tr('Final diagnosis'), s('finalDx')),
    lab(tr('Differential diagnosis'), s('ddx')),
    lab(tr('Problem list'), s('problems')),
    lab(tr('Reasoning'), s('reasoning')),
    sel('Assessment'),
  ]);
  final plan = [
    for (final m in c.lst('mgmt'))
      if ('${m['text'] ?? ''}'.trim().isNotEmpty) '${m['text']}${'${m['dose'] ?? ''}'.trim().isEmpty ? '' : ' (${m['dose']})'}'
  ];
  add(tr('Management'), [plan.join('; '), sel('Management')]);
  add(tr('Outcome and learning'), [
    lab(tr('Disposition'), tr(s('disposition'))),
    lab(tr('Outcome'), s('outcome')),
    lab(tr('Follow-up recommendations'), s('followUp')),
    lab(tr('What I learned'), s('learned')),
    lab(tr('Mistakes / near-misses'), s('mistakes')),
  ]);
  return out;
}

void addCase(PdfDoc d, CaseRec c, {bool signOff = false, bool summary = false, bool withStory = true}) {
  String s(String k) => c.s(k).trim();
  final cc = CaseChoices(c);
  final chHistory = cc.lines(section: 'History'), chExam = cc.lines(section: 'Examination'), chInv = cc.lines(section: 'Investigations');
  final chAssess = cc.lines(section: 'Assessment'), chMgmt = cc.lines(section: 'Management');
  final st = clinStatusOf(c);
  const tag = Color(0xFF3E5C86);
  final pills = <PdfPill>[
    if (st.isNotEmpty) PdfPill(tr(st), clinStatusColor(st), clinStatusOnColor(st)),
    if (s('status').isNotEmpty) PdfPill(tr(s('status')), tag),
    if (s('disposition').isNotEmpty) PdfPill(tr(s('disposition')), tag),
    if (s('role').isNotEmpty) PdfPill(tr(s('role')), tag),
  ];
  final dx = s('finalDx').isNotEmpty ? s('finalDx') : s('workingDx');
  d.band(
    '${tr('Case')} ${s('code')}${dx.isEmpty ? '' : '  -  $dx'}',
    subtitle: _join([tr(s('specialty')), s('date'), _join([tr(s('ageGroup')), tr(s('sex'))], ' '), tr(s('setting')), tr(s('encounter'))]),
    pills: pills,
  );

  final flags = flaggedItems(c);
  if (flags.isNotEmpty) d.callout(tr('Red flags'), flags, kind: 'red', icon: 'flag');

  // the case as a story first; the detailed record follows (a summary stops after the key stages)
  final story = withStory ? caseStory(c) : const <List<String>>[];
  const keyStages = {'Presentation', 'Assessment', 'Management', 'Outcome and learning'};
  final shownStory = summary ? [for (final p in story) if (keyStages.contains(_trKey(p[0]))) p] : story;
  if (shownStory.isNotEmpty) {
    d.section(summary ? tr('Case summary') : tr('Case presentation'), icon: 'person');
    for (final p in shownStory) {
      d.para(p[0], p[1]);
    }
  }
  if (summary) {
    _signOffBlock(d, c, signOff);
    return;
  }

  final extra = specialtyFieldsFor(s('specialty')) ?? const <List<String>>[];
  if (['cc', 'hpi', 'pmh', 'psh', 'drugs', 'allergies', 'family', 'social', 'ros'].any((k) => s(k).isNotEmpty) ||
      extra.any((f) => s(f[0]).isNotEmpty) || chHistory.isNotEmpty) {
    d.section(tr('Presentation'), icon: 'person');
    d.para(tr('Chief complaint'), s('cc'), boldText: true);
    d.para(tr('History of present illness'), s('hpi'));
    d.para(tr('Past medical history'), s('pmh'));
    d.para(tr('Past surgical history'), s('psh'));
    d.para(tr('Drugs'), s('drugs'));
    d.callout(tr('Allergies'), [s('allergies')], kind: 'amber', icon: 'flag');
    d.para(tr('Family history'), s('family'));
    d.para(tr('Social history'), s('social'));
    d.para(tr('Review of systems'), s('ros'));
    for (final f in extra) {
      d.para(tr(f[1]), s(f[0]));
    }
    _choiceTable(d, chHistory);
  }

  final vit = [
    ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'], ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'], ['Wt', 'v_wt'],
  ].where((e) => s(e[1]).isNotEmpty).toList();
  final sys = c.d['sys'];
  final sysRows = <List<String>>[];
  final sysInk = <Color?>[];
  if (sys is Map) {
    for (final e in sys.entries) {
      final v = e.value;
      if (v is Map && ((v['s'] ?? '').toString().isNotEmpty || (v['n'] ?? '').toString().isNotEmpty)) {
        sysRows.add([tr(e.key.toString()), tr((v['s'] ?? '').toString()), (v['n'] ?? '').toString()]);
        sysInk.add(v['s'] == 'Abnormal' ? _red : null);
      }
    }
  }
  if (vit.isNotEmpty || sysRows.isNotEmpty || ['examGeneral', 'examSystemic', 'examFocused'].any((k) => s(k).isNotEmpty) || chExam.isNotEmpty) {
    d.section(tr('Examination'), icon: 'pulse');
    if (vit.isNotEmpty) {
      d.table([for (final e in vit) tr(e[0])], [
        [for (final e in vit) s(e[1])]
      ]);
    }
    d.para(_join([tr('General exam'), tr(s('obsGeneral'))], ' - '), s('examGeneral'));
    d.para(_join([tr('Systemic exam'), tr(s('obsSystemic'))], ' - '), s('examSystemic'));
    d.para(_join([tr('Focused exam'), tr(s('obsFocused'))], ' - '), s('examFocused'));
    if (sysRows.isNotEmpty) {
      d.table([tr('System'), tr('State'), tr('Notes')], sysRows, weights: [1.1, 1, 2.4], rowInk: sysInk);
    }
    _choiceTable(d, chExam);
  }

  final inv = c.lst('inv');
  if (inv.isNotEmpty || chInv.isNotEmpty) {
    d.section(tr('Investigations'), icon: 'flask');
    if (inv.isNotEmpty) {
      d.table(
        [tr('Test'), tr('Status'), tr('Result'), tr('My interpretation')],
        [
          for (final i in inv)
            ['${i['name'] ?? ''}', tr('${i['status'] ?? ''}'), '${i['result'] ?? ''}', '${i['interpretation'] ?? ''}']
        ],
        weights: [1.4, 1, 1.8, 2],
      );
    }
    _choiceTable(d, chInv);
  }

  final pics = <({String path, String caption})>[
    for (final im in c.lst('images'))
      if ('${im['file'] ?? ''}'.isNotEmpty)
        (
          path: store.imagePath('${im['file']}'),
          caption: [for (final k in ['type', 'view', 'caption', 'date']) if ('${im[k] ?? ''}'.trim().isNotEmpty) '${im[k]}'.trim()].join(' • ')
        )
  ];
  if (pics.isNotEmpty) {
    d.section(tr('Images'), icon: 'list');
    d.images(pics);
  }

  final ls = labSeries(c);
  if (ls.isNotEmpty) {
    d.section(tr('Lab results and trends'), icon: 'list');
    d.table(
      [tr('Test'), tr('Results (oldest to newest)'), tr('Unit')],
      [for (final x in ls) [x.test, x.readings.map((r) => r.value == r.value.roundToDouble() ? r.value.toStringAsFixed(0) : r.value.toString()).join('  \u2192  '), x.unit]],
      weights: [1.2, 3, 1],
    );
  }

  if (s('outcomeCat').isNotEmpty) {
    d.para(tr('Outcome status'), tr(s('outcomeCat')), boldText: true);
  }

  final evo = c.lst('evo');
  if (['problems', 'ddx', 'workingDx', 'finalDx', 'reasoning'].any((k) => s(k).isNotEmpty) || evo.isNotEmpty || problemList(c).isNotEmpty || chAssess.isNotEmpty || scoresOf(c).isNotEmpty) {
    d.section(tr('Assessment'), icon: 'list');
    d.para(tr('Problem list'), s('problems'));
    final pl = problemsSorted(c);
    if (pl.isNotEmpty) {
      d.table(
        [tr('Problem'), tr('Status'), tr('Since')],
        [for (final p in pl) ['${p['text'] ?? ''}', tr(p['status'] == 'resolved' ? 'resolved' : 'active'), '${p['since'] ?? ''}']],
        weights: [3, 1, 1],
      );
    }
    d.para(tr('Differential diagnosis'), s('ddx'));
    d.para(tr('Working diagnosis'), s('workingDx'), boldText: true);
    d.para(tr('Final diagnosis'), s('finalDx'), boldText: true, labelColor: _red);
    d.para(tr('Reasoning'), s('reasoning'));
    if (evo.isNotEmpty) {
      d.table(
        [tr('Step'), tr('Date'), tr('Diagnosis'), tr('Because')],
        [
          for (final e in evo) [tr('${e['step'] ?? ''}'), '${e['date'] ?? ''}', '${e['text'] ?? ''}', '${e['evidence'] ?? ''}']
        ],
        weights: [1.1, 1, 2, 2],
      );
    }
    _choiceTable(d, chAssess);
    final sc = scoresOf(c);
    if (sc.isNotEmpty) {
      d.table(
        [tr('Score'), tr('Result'), tr('Chosen'), tr('Date')],
        [for (final x in sc) [x.name, _join([x.value, x.meaning], '\n'), x.items.join('; '), '${x.date} ${x.time}'.trim()]],
        weights: [1.6, 1.6, 2.6, 1.1],
      );
    }
  }

  // management: the user's own plan lines as boxed steps
  final mg = c.lst('mgmt');
  if (mg.isNotEmpty || chMgmt.isNotEmpty) {
    d.section(tr('Management'), icon: 'arrow');
    if (mg.isNotEmpty) d.steps([
      for (final m in mg)
        () {
          final dose = '${m['dose'] ?? ''}'.trim();
          final first = '${m['text'] ?? ''}${dose.isEmpty ? '' : '  \u2066[$dose]\u2069'}';
          final meta = _join([tr('${m['category'] ?? ''}'), tr('${m['by'] ?? ''}'), tr('${m['state'] ?? ''}')]);
          return meta.isEmpty ? first : '$first\n$meta';
        }()
    ]);
    _choiceTable(d, chMgmt);
  }

  final pr = c.lst('progress');
  if (pr.isNotEmpty) {
    d.section(tr('Progress'), icon: 'chart');
    d.table(
      [tr('Day'), 'S', 'O', 'A', 'P'],
      [
        for (final p in pr)
          [_join(['${p['day'] ?? ''}', '${p['date'] ?? ''}'], '\n'), '${p['s'] ?? ''}', '${p['o'] ?? ''}', '${p['a'] ?? ''}', '${p['p'] ?? ''}']
      ],
      weights: [1.5, 2, 2, 2, 2],
    );
  }

  if (['disposition', 'followUp', 'outcome', 'initialDx', 'whatChanged', 'learned', 'mistakes', 'questions', 'refs', 'teaching']
      .any((k) => s(k).isNotEmpty)) {
    d.section(tr('Outcome and learning'), icon: 'check');
    d.para(tr('Disposition'), tr(s('disposition')));
    d.para(tr('Follow-up recommendations'), s('followUp'));
    d.para(tr('Outcome'), s('outcome'));
    d.para(tr('My first diagnosis (before results)'), s('initialDx'));
    d.para(tr('What changed my diagnosis?'), s('whatChanged'));
    d.callout(tr('What I learned'), _splitLines(s('learned')), kind: 'green', icon: 'check');
    d.callout(tr('Mistakes / near-misses'), _splitLines(s('mistakes')), kind: 'amber', icon: 'flag');
    d.callout(tr('Questions to review'), _splitLines(s('questions')), kind: 'info', icon: 'list');
    d.para(tr('Supervisor teaching'), s('teaching'));
    d.para(tr('References'), s('refs'));
  }

  _signOffBlock(d, c, signOff);
}

/// Keys of the story headings are the English titles, so a summary can pick stages in any language.
String _trKey(String heading) {
  for (final k in ['Presentation', 'Assessment', 'Management', 'Outcome and learning']) {
    if (heading == tr(k)) return k;
  }
  return heading;
}

void _signOffBlock(PdfDoc d, CaseRec c, bool signOff) {
  if (!signOff) return;
  String s(String k) => c.s(k).trim();
  d.section(tr('Supervisor sign-off'), icon: 'check');
  if (isSigned(c.d)) {
    d.para(tr('Supervisor'), signCell(c.d).replaceAll('\n', '  -  '));
    final lvl = s('supLevel');
    if (lvl.isNotEmpty) d.para(tr('Level of supervision'), tr(lvl));
  } else {
    d.signLines('', [tr('Supervisor name'), tr('Role'), tr('Signature or initials'), tr('Date')]);
  }
}

/// One or many cases as a study-sheet document. With several cases a summary page comes first.
/// [signOff] adds a supervisor column to the summary and a sign-off block to every case.
PdfDoc casesDoc(List<CaseRec> cases, {String? title, bool large = false, bool signOff = false, bool summary = false}) {
  final d = PdfDoc(large: large);
  if (cases.length > 1) {
    d.band(title ?? tr('Cases'), subtitle: countLabel(cases.length, 'case'));
    d.section(tr('Summary'), icon: 'list');
    final ink = <Color?>[];
    final rows = <List<String>>[];
    for (final c in cases) {
      final st = clinStatusOf(c);
      rows.add([
        c.s('date'), c.s('code'), tr(c.s('specialty')), c.title, st.isEmpty ? '' : tr(st),
        if (signOff) signCell(c.d),
      ]);
      ink.add(st == 'Unstable' || st == 'Critical' ? clinStatusColor(st) : null);
    }
    d.table([tr('Date'), tr('Code'), tr('Specialty'), tr('Diagnosis'), tr('Status at presentation'), if (signOff) tr('Supervisor sign-off')], rows,
        weights: signOff ? [1.3, 1.3, 1.4, 2.0, 1.3, 1.9] : [1.5, 1.4, 1.6, 2.4, 1.6], rowInk: ink);
  }
  for (final c in cases) {
    addCase(d, c, signOff: signOff, summary: summary, withStory: cases.length == 1 || summary);
  }
  return d;
}

// ---------------------------------------------------------------- export range / options

/// What the export dialog asks: which entries, which format and which extras.
class ExportOptions {
  /// all | rotation | dates
  String range;
  String? rotationId;
  DateTime? from;
  DateTime? to;

  /// pdf | csv
  String format;
  bool large;
  bool signOff;

  /// false: the whole case (story and every detail); true: only the key stages on one page.
  bool summaryOnly = false;

  /// Optional AI paragraph per rotation (written from the counts only, clearly marked in the PDF).
  bool aiSummary = false;

  /// rotation id -> AI paragraph, filled by the export flow before the PDF is built.
  final Map<String, String> aiNarratives = {};
  ExportOptions({
    this.range = 'all',
    this.rotationId,
    this.from,
    this.to,
    this.format = 'pdf',
    this.large = false,
    this.signOff = true,
  });

  bool _dateOk(String date) {
    if (range != 'dates') return true;
    if (date.isEmpty) return false;
    if (from != null && date.compareTo(fmtDate(from!)) < 0) return false;
    if (to != null && date.compareTo(fmtDate(to!)) > 0) return false;
    return true;
  }

  bool includesCase(CaseRec c) {
    if (c.id.startsWith('demo_')) return false;
    if (range == 'rotation') return c.s('rotationId') == rotationId;
    return _dateOk(c.s('date'));
  }

  bool includesProc(J p) {
    if (p['demo'] == true) return false;
    if (range == 'rotation') return p['rotationId'] == rotationId;
    return _dateOk((p['date'] ?? '').toString());
  }

  List<CaseRec> cases() => store.casesSorted().where(includesCase).toList();

  List<J> procedures() {
    final l = store.procedures.where(includesProc).toList()
      ..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    return l;
  }
}

// ---------------------------------------------------------------- plain-text documents (kept API)

/// Plain text: '## ' lines become numbered headings, other lines are paragraphs.
PdfDoc _textDoc(String title, String body, {bool large = false, String footer = 'MedLog  •  Dr. Mohammed Samir Abu Younis'}) {
  final d = PdfDoc(large: large, footer: footer);
  d.band(title);
  for (final raw in body.split('\n')) {
    final t = raw.trimRight();
    if (t.isEmpty) continue;
    if (t.startsWith('## ')) {
      d.section(t.substring(3));
    } else {
      d.para('', t);
    }
  }
  return d;
}

Future<List<Uint8List>> renderPages(String title, String body, {String footer = 'MedLog', bool large = false}) =>
    _textDoc(title, body, large: large, footer: footer).render();

Future<Uint8List> pdfFromPages(List<Uint8List> pages, String title) async {
  final doc = pw.Document(title: title, author: 'MedLog', creator: 'MedLog');
  for (final p in pages) {
    final image = pw.MemoryImage(p);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
    ));
  }
  return Uint8List.fromList(await doc.save());
}

Future<Uint8List> buildDocPdf(PdfDoc d, String title) async => pdfFromPages(await d.render(), title);

Future<Uint8List> buildPdf(String title, String body, {bool large = false}) async =>
    buildDocPdf(_textDoc(title, body, large: large), title);

Future<Uint8List> buildCasesPdf(List<CaseRec> cases, {String? title, bool large = false, bool signOff = false, bool summary = false}) async =>
    buildDocPdf(casesDoc(cases, title: title, large: large, signOff: signOff, summary: summary), title ?? 'MedLog');

Future<File> _save(Uint8List bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
  final f = File('${dir.path}/$safe.pdf');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

Future<File> writePdf(String title, String body, {String fileName = 'MedLog', bool large = false}) async =>
    _save(await buildPdf(title, body, large: large), fileName);

Future<File> writeCasesPdf(List<CaseRec> cases, {String? title, String fileName = 'MedLog', bool large = false, bool signOff = false, bool summary = false}) async =>
    _save(await buildCasesPdf(cases, title: title, large: large, signOff: signOff, summary: summary), fileName);

Future<File> writeDocPdf(PdfDoc d, String title, {String fileName = 'MedLog'}) async => _save(await buildDocPdf(d, title), fileName);
