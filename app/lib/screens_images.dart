import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'widgets.dart';

/// Image tools: draw arrows / circles / text on a copy-free overlay (the file itself
/// is not changed), cover private details permanently, and compare two images.

const List<Color> kAnnColors = [Color(0xFFE53935), Color(0xFFFFEB3B), Color(0xFF43A047), Color(0xFF00ACC1), Colors.white];

Future<ui.Size> imageSizeOf(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final f = await codec.getNextFrame();
  final s = ui.Size(f.image.width.toDouble(), f.image.height.toDouble());
  f.image.dispose();
  return s;
}

/// Where a "contain"-fitted image sits inside a box.
Rect containRect(Size box, Size img) {
  if (img.width <= 0 || img.height <= 0) return Offset.zero & box;
  final s = math.min(box.width / img.width, box.height / img.height);
  final w = img.width * s, h = img.height * s;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

List<J> annotationsOf(J img) {
  final v = img['ann'];
  if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  return <J>[];
}

// ================================================================ painter

class AnnPainter extends CustomPainter {
  final List<J> ann;
  final Rect rect; // where the image is drawn
  AnnPainter(this.ann, this.rect);

  Offset _pt(num x, num y) => Offset(rect.left + x * rect.width, rect.top + y * rect.height);

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in ann) {
      final col = kAnnColors[((a['c'] ?? 0) as num).toInt().clamp(0, kAnnColors.length - 1)];
      final p = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, rect.shortestSide / 160)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final pts = (a['p'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const <double>[];
      switch (a['t']) {
        case 'arrow':
          if (pts.length < 4) break;
          final s = _pt(pts[0], pts[1]), e = _pt(pts[2], pts[3]);
          canvas.drawLine(s, e, p);
          final ang = math.atan2(e.dy - s.dy, e.dx - s.dx);
          final head = math.max(12.0, rect.shortestSide / 28);
          for (final d in [math.pi * 0.85, -math.pi * 0.85]) {
            canvas.drawLine(e, e + Offset(math.cos(ang + d), math.sin(ang + d)) * head, p);
          }
          break;
        case 'circle':
          if (pts.length < 4) break;
          canvas.drawOval(Rect.fromPoints(_pt(pts[0], pts[1]), _pt(pts[2], pts[3])), p);
          break;
        case 'rect':
          if (pts.length < 4) break;
          canvas.drawRect(Rect.fromPoints(_pt(pts[0], pts[1]), _pt(pts[2], pts[3])), p);
          break;
        case 'pen':
          if (pts.length < 4) break;
          final path = Path()..moveTo(_pt(pts[0], pts[1]).dx, _pt(pts[0], pts[1]).dy);
          for (var i = 2; i + 1 < pts.length; i += 2) {
            final o = _pt(pts[i], pts[i + 1]);
            path.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(path, p);
          break;
        case 'text':
          if (pts.length < 2) break;
          final tp = TextPainter(
            text: TextSpan(
              text: (a['s'] ?? '').toString(),
              style: TextStyle(
                color: col,
                fontSize: math.max(14.0, rect.shortestSide / 22),
                fontWeight: FontWeight.w800,
                shadows: const [Shadow(blurRadius: 3, color: Colors.black87)],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: rect.width * 0.8);
          tp.paint(canvas, _pt(pts[0], pts[1]));
          break;
      }
    }
  }

  @override
  bool shouldRepaint(AnnPainter old) => true;
}

/// Image with its annotations drawn on top, zoomable.
class AnnotatedImage extends StatefulWidget {
  final String path;
  final List<J> ann;
  const AnnotatedImage({super.key, required this.path, required this.ann});

  @override
  State<AnnotatedImage> createState() => _AnnotatedImageState();
}

class _AnnotatedImageState extends State<AnnotatedImage> {
  Size? _size;

  @override
  void initState() {
    super.initState();
    imageSizeOf(widget.path).then((s) {
      if (mounted) setState(() => _size = s);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      final r = _size == null ? Offset.zero & box : containRect(box, _size!);
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(widget.path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))),
          if (_size != null && widget.ann.isNotEmpty) CustomPaint(painter: AnnPainter(widget.ann, r)),
        ],
      );
    });
  }
}

// ================================================================ annotate editor

class ImageAnnotateScreen extends StatefulWidget {
  final String path;
  final List<J> initial;
  const ImageAnnotateScreen({super.key, required this.path, required this.initial});

  @override
  State<ImageAnnotateScreen> createState() => _ImageAnnotateScreenState();
}

class _ImageAnnotateScreenState extends State<ImageAnnotateScreen> {
  late final List<J> _ann = widget.initial.map((e) => Map<String, dynamic>.from(e)).toList();
  Size? _size;
  String _tool = 'arrow';
  int _color = 0;
  J? _cur;

  @override
  void initState() {
    super.initState();
    imageSizeOf(widget.path).then((s) {
      if (mounted) setState(() => _size = s);
    }).catchError((_) {});
  }

  Offset _norm(Offset local, Rect r) =>
      Offset(((local.dx - r.left) / r.width).clamp(0.0, 1.0), ((local.dy - r.top) / r.height).clamp(0.0, 1.0));

  Future<void> _addText(Offset n) async {
    final t = await askText(context, 'Label', hint: 'e.g. fracture line');
    if (t == null || t.isEmpty) return;
    setState(() => _ann.add({'t': 'text', 'p': [n.dx, n.dy], 'c': _color, 's': t}));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Annotate'),
        actions: [
          IconButton(
            tooltip: tr('Undo'),
            icon: const Icon(Icons.undo),
            onPressed: _ann.isEmpty ? null : () => setState(_ann.removeLast),
          ),
          IconButton(
            tooltip: tr('Clear'),
            icon: const Icon(Icons.layers_clear_outlined),
            onPressed: _ann.isEmpty ? null : () => setState(_ann.clear),
          ),
          TextButton(onPressed: () => Navigator.pop(context, _ann), child: Text('Save')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _size == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final box = Size(c.maxWidth, c.maxHeight);
                    final r = containRect(box, _size!);
                    final live = [..._ann, if (_cur != null) _cur!];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: _tool == 'text' ? (d) => _addText(_norm(d.localPosition, r)) : null,
                      onPanStart: _tool == 'text'
                          ? null
                          : (d) {
                              final n = _norm(d.localPosition, r);
                              setState(() => _cur = {
                                    't': _tool,
                                    'c': _color,
                                    'p': _tool == 'pen' ? [n.dx, n.dy] : [n.dx, n.dy, n.dx, n.dy],
                                  });
                            },
                      onPanUpdate: _tool == 'text'
                          ? null
                          : (d) {
                              final n = _norm(d.localPosition, r);
                              final cur = _cur;
                              if (cur == null) return;
                              final p = List<double>.from((cur['p'] as List).map((e) => (e as num).toDouble()));
                              setState(() {
                                if (_tool == 'pen') {
                                  p.addAll([n.dx, n.dy]);
                                } else {
                                  p[2] = n.dx;
                                  p[3] = n.dy;
                                }
                                cur['p'] = p;
                              });
                            },
                      onPanEnd: _tool == 'text'
                          ? null
                          : (_) {
                              final cur = _cur;
                              if (cur != null) {
                                final p = (cur['p'] as List).map((e) => (e as num).toDouble()).toList();
                                final tiny = p.length >= 4 && (p[0] - p[p.length - 2]).abs() + (p[1] - p[p.length - 1]).abs() < 0.01;
                                if (!tiny) _ann.add(cur);
                              }
                              setState(() => _cur = null);
                            },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(widget.path), fit: BoxFit.contain),
                          CustomPaint(painter: AnnPainter(live, r)),
                        ],
                      ),
                    );
                  }),
          ),
          Container(
            color: cs.surfaceContainer,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final t in const [
                        ['arrow', Icons.north_east],
                        ['circle', Icons.circle_outlined],
                        ['rect', Icons.crop_square],
                        ['pen', Icons.edit],
                        ['text', Icons.text_fields],
                      ])
                        IconButton.filledTonal(
                          isSelected: _tool == t[0],
                          style: IconButton.styleFrom(
                            backgroundColor: _tool == t[0] ? cs.primary : null,
                            foregroundColor: _tool == t[0] ? cs.onPrimary : null,
                          ),
                          icon: Icon(t[1] as IconData),
                          onPressed: () => setState(() => _tool = t[0] as String),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < kAnnColors.length; i++)
                        GestureDetector(
                          onTap: () => setState(() => _color = i),
                          child: Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: kAnnColors[i],
                              shape: BoxShape.circle,
                              border: Border.all(color: _color == i ? cs.primary : cs.outlineVariant, width: _color == i ? 3 : 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Annotations are drawn on top. The original image is not changed.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================ cover (permanent)

/// Paints solid black boxes (given as 0..1 fractions of the image) onto the pixels
/// and returns a PNG. The covered area cannot be recovered from the result.
Future<Uint8List> burnBoxes(Uint8List imageBytes, List<Rect> boxes) async {
  final codec = await ui.instantiateImageCodec(imageBytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawImage(img, Offset.zero, Paint());
  final fill = Paint()..color = Colors.black;
  for (final b in boxes) {
    canvas.drawRect(
      Rect.fromLTRB(b.left * img.width, b.top * img.height, b.right * img.width, b.bottom * img.height),
      fill,
    );
  }
  final out = await rec.endRecording().toImage(img.width, img.height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  out.dispose();
  if (data == null) throw MedLogError('Could not save the image');
  return data.buffer.asUint8List();
}

/// Draws black boxes over private details and saves a new image file. Unlike
/// annotations, this changes the pixels, so the covered area cannot be recovered.
class ImageCoverScreen extends StatefulWidget {
  final String path;
  const ImageCoverScreen({super.key, required this.path});

  @override
  State<ImageCoverScreen> createState() => _ImageCoverScreenState();
}

class _ImageCoverScreenState extends State<ImageCoverScreen> {
  final List<Rect> _boxes = [];
  Rect? _cur;
  Size? _size;
  bool _busy = false;
  Offset? _start;

  @override
  void initState() {
    super.initState();
    imageSizeOf(widget.path).then((s) {
      if (mounted) setState(() => _size = s);
    }).catchError((_) {});
  }

  Offset _norm(Offset local, Rect r) =>
      Offset(((local.dx - r.left) / r.width).clamp(0.0, 1.0), ((local.dy - r.top) / r.height).clamp(0.0, 1.0));

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final bytes = await File(widget.path).readAsBytes();
      final png = await burnBoxes(bytes, _boxes);
      if (mounted) Navigator.pop(context, png);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Cover private details'),
        actions: [
          IconButton(
            tooltip: tr('Undo'),
            icon: const Icon(Icons.undo),
            onPressed: _boxes.isEmpty ? null : () => setState(_boxes.removeLast),
          ),
          TextButton(onPressed: _boxes.isEmpty || _busy ? null : _apply, child: Text('Apply')),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _size == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final r = containRect(Size(c.maxWidth, c.maxHeight), _size!);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _start = _norm(d.localPosition, r),
                      onPanUpdate: (d) => setState(() => _cur = Rect.fromPoints(_start!, _norm(d.localPosition, r))),
                      onPanEnd: (_) {
                        if (_cur != null && _cur!.width > 0.01 && _cur!.height > 0.01) _boxes.add(_cur!);
                        setState(() => _cur = null);
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(widget.path), fit: BoxFit.contain),
                          CustomPaint(painter: _BoxPainter([..._boxes, if (_cur != null) _cur!], r)),
                        ],
                      ),
                    );
                  }),
          ),
          Container(
            width: double.infinity,
            color: cs.errorContainer,
            padding: const EdgeInsets.all(12),
            child: SafeArea(
              top: false,
              child: Text(
                'Drag to draw black boxes over names, file numbers, faces or tattoos. Applying changes the image permanently.',
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final List<Rect> boxes;
  final Rect r;
  _BoxPainter(this.boxes, this.r);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final rr = Rect.fromLTRB(r.left + b.left * r.width, r.top + b.top * r.height, r.left + b.right * r.width, r.top + b.bottom * r.height);
      canvas.drawRect(rr, Paint()..color = Colors.black.withAlpha(220));
      canvas.drawRect(rr, Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => true;
}

// ================================================================ compare

class ImageCompareScreen extends StatefulWidget {
  final J a;
  final J b;
  const ImageCompareScreen({super.key, required this.a, required this.b});

  @override
  State<ImageCompareScreen> createState() => _ImageCompareScreenState();
}

class _ImageCompareScreenState extends State<ImageCompareScreen> {
  bool _wipe = false;
  double _pos = 0.5;

  String _title(J i) => [(i['type'] ?? '').toString(), (i['view'] ?? '').toString(), (i['date'] ?? '').toString()]
      .where((e) => e.isNotEmpty)
      .map(tr)
      .join(' • ');

  Widget _img(J i) => AnnotatedImage(path: store.imagePath(i['file'].toString()), ann: annotationsOf(i));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Compare images'),
        actions: [
          IconButton(
            tooltip: tr(_wipe ? 'Side by side' : 'Slider'),
            icon: Icon(_wipe ? Icons.view_column_outlined : Icons.compare),
            onPressed: () => setState(() => _wipe = !_wipe),
          ),
        ],
      ),
      body: _wipe
          ? Column(
              children: [
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _img(widget.b),
                        ClipRect(clipper: _WipeClipper(_pos), child: _img(widget.a)),
                        Positioned(
                          left: c.maxWidth * _pos - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: Colors.white),
                        ),
                      ],
                    );
                  }),
                ),
                Slider(value: _pos, onChanged: (v) => setState(() => _pos = v)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(_title(widget.a), style: theme.textTheme.labelMedium), Text(_title(widget.b), style: theme.textTheme.labelMedium)],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (final i in [widget.a, widget.b])
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                          child: Align(alignment: AlignmentDirectional.centerStart, child: Text(_title(i), style: theme.textTheme.labelLarge)),
                        ),
                        Expanded(child: InteractiveViewer(maxScale: 6, child: _img(i))),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _WipeClipper extends CustomClipper<Rect> {
  final double f;
  _WipeClipper(this.f);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(_WipeClipper old) => old.f != f;
}

/// Lets the user tick exactly two images of a case.
Future<List<J>?> pickTwoImages(BuildContext context, List<J> images) {
  final chosen = <J>[];
  return showDialog<List<J>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('Choose two images'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final i in images)
                InkWell(
                  onTap: () => setS(() {
                    if (!chosen.remove(i)) {
                      if (chosen.length < 2) chosen.add(i);
                    }
                  }),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(store.imagePath(i['file'].toString())), fit: BoxFit.cover, cacheWidth: 300),
                      ),
                      if (chosen.contains(i))
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Theme.of(ctx).colorScheme.primary, width: 4),
                            color: Colors.black26,
                          ),
                          child: Center(child: Text('${chosen.indexOf(i) + 1}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          FilledButton(onPressed: chosen.length == 2 ? () => Navigator.pop(ctx, chosen) : null, child: Text('Compare')),
        ],
      ),
    ),
  );
}
