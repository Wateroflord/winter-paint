import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'store.dart';
import 'ui.dart';

enum Brush { pen, brush, pencil, marker, spray, eraser }

const brushNames = {
  Brush.pen: ('Ручка', Icons.create),
  Brush.brush: ('Мягкая кисть', Icons.brush),
  Brush.pencil: ('Карандаш', Icons.edit),
  Brush.marker: ('Маркер', Icons.highlight),
  Brush.spray: ('Аэрограф', Icons.blur_on),
  Brush.eraser: ('Ластик', Icons.auto_fix_normal),
};

class Stroke {
  final Brush brush;
  final Color color;
  final double size;
  final List<Offset> pts = [];
  final List<double> pressure = [];
  final int seed;
  Stroke(this.brush, this.color, this.size, this.seed);
}

class Layer {
  String name;
  bool visible = true;
  double opacity = 1;
  ui.Image? base; // загруженная картинка слоя
  final List<Stroke> strokes = [];
  ui.Image? cache; // base + strokes
  Layer(this.name);
}

/// Нарисовать штрих на холсте.
void paintStroke(Canvas c, Stroke s) {
  if (s.pts.isEmpty) return;
  final p = Paint()
    ..color = s.color
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  var size = s.size;
  switch (s.brush) {
    case Brush.brush:
      p.maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.35);
    case Brush.pencil:
      p.color = s.color.withValues(alpha: s.color.a * 0.85);
      size = math.max(1, size * 0.5);
    case Brush.marker:
      p.color = s.color.withValues(alpha: s.color.a * 0.35);
      p.strokeCap = StrokeCap.square;
    case Brush.eraser:
      p.blendMode = BlendMode.clear;
      p.color = const Color(0xFF000000);
    case Brush.spray:
      final rnd = math.Random(s.seed);
      final dot = Paint()..color = s.color.withValues(alpha: s.color.a * 0.6);
      for (final pt in s.pts) {
        for (var i = 0; i < 14; i++) {
          final a = rnd.nextDouble() * math.pi * 2, r = math.sqrt(rnd.nextDouble()) * size;
          c.drawCircle(pt + Offset(math.cos(a) * r, math.sin(a) * r), math.max(0.6, size * 0.04), dot);
        }
      }
      return;
    case Brush.pen:
      break;
  }
  if (s.pts.length == 1) {
    c.drawCircle(s.pts.first, size * s.pressure.first / 2, p..style = PaintingStyle.fill);
    return;
  }
  final varPressure = s.pressure.any((x) => (x - s.pressure.first).abs() > 0.05);
  if (varPressure) {
    for (var i = 1; i < s.pts.length; i++) {
      p.strokeWidth = size * (s.pressure[i - 1] + s.pressure[i]) / 2;
      c.drawLine(s.pts[i - 1], s.pts[i], p);
    }
    return;
  }
  p.strokeWidth = size * s.pressure.first;
  final path = Path()..moveTo(s.pts.first.dx, s.pts.first.dy);
  for (var i = 1; i < s.pts.length - 1; i++) {
    final mid = (s.pts[i] + s.pts[i + 1]) / 2;
    path.quadraticBezierTo(s.pts[i].dx, s.pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(s.pts.last.dx, s.pts.last.dy);
  c.drawPath(path, p);
}

class CanvasEditor extends StatefulWidget {
  final ProjectMeta meta;
  const CanvasEditor({super.key, required this.meta});

  @override
  State<CanvasEditor> createState() => _CanvasEditorState();
}

class _CanvasEditorState extends State<CanvasEditor> {
  final List<Layer> layers = [];
  int active = 0;
  Color bg = Colors.white;
  Brush brush = Brush.pen;
  Color color = const Color(0xFF1B1F2A);
  final Map<Brush, double> sizes = {Brush.pen: 6, Brush.brush: 24, Brush.pencil: 4, Brush.marker: 20, Brush.spray: 30, Brush.eraser: 30};
  final List<Color> recent = [];
  final List<(int, Stroke)> undo = [], redo = [];
  Stroke? cur;
  bool loading = true;
  double scale = 0;
  Offset offset = Offset.zero;
  final Map<int, Offset> _pointers = {};
  double? _pinchDist;
  Offset? _pinchMid;
  Timer? _saveT;
  bool dirty = false;

  ProjectMeta get meta => widget.meta;
  Size get docSize => Size(meta.w.toDouble(), meta.h.toDouble());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveT?.cancel();
    if (dirty) _save();
    super.dispose();
  }

  Future<void> _load() async {
    final j = await Projects.readBytes(meta.id, 'canvas.json');
    if (j != null) {
      final m = jsonDecode(utf8.decode(j)) as Map;
      bg = Color((m['bg'] as num?)?.toInt() ?? 0xFFFFFFFF);
      for (final l in (m['layers'] as List? ?? const []).whereType<Map>()) {
        final layer = Layer('${l['name']}')
          ..visible = l['visible'] != false
          ..opacity = (l['opacity'] as num?)?.toDouble() ?? 1;
        final b = await Projects.readBytes(meta.id, '${l['file']}');
        if (b != null) {
          final codec = await ui.instantiateImageCodec(b);
          layer.base = (await codec.getNextFrame()).image;
          layer.cache = layer.base;
        }
        layers.add(layer);
      }
    }
    if (layers.isEmpty) layers.add(Layer('Слой 1'));
    setState(() => loading = false);
  }

  Future<ui.Image> _render(Layer l) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Offset.zero & docSize);
    c.saveLayer(Offset.zero & docSize, Paint());
    if (l.base != null) c.drawImage(l.base!, Offset.zero, Paint());
    for (final s in l.strokes) {
      paintStroke(c, s);
    }
    c.restore();
    return rec.endRecording().toImage(meta.w, meta.h);
  }

  Future<void> _recache(Layer l) async {
    l.cache = await _render(l);
    if (mounted) setState(() {});
  }

  /// Сжимаем старые штрихи в картинку, чтобы рисование не тормозило.
  Future<void> _flatten(Layer l) async {
    if (l.strokes.length < 60) return;
    final keep = l.strokes.sublist(l.strokes.length - 20);
    l.strokes.removeRange(l.strokes.length - 20, l.strokes.length);
    l.base = await _render(l);
    l.strokes
      ..clear()
      ..addAll(keep);
    undo.removeWhere((u) => !keep.contains(u.$2) && layers.indexOf(l) == u.$1);
  }

  void _changed() {
    dirty = true;
    _saveT?.cancel();
    _saveT = Timer(const Duration(seconds: 3), _save);
  }

  Future<Uint8List> _composite({int? w, int? h}) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Offset.zero & docSize);
    c.drawRect(Offset.zero & docSize, Paint()..color = bg);
    for (final l in layers) {
      if (!l.visible || l.cache == null) continue;
      c.drawImage(l.cache!, Offset.zero, Paint()..color = Color.fromRGBO(0, 0, 0, l.opacity));
    }
    var image = await rec.endRecording().toImage(meta.w, meta.h);
    if (w != null && h != null) {
      final r2 = ui.PictureRecorder();
      final c2 = Canvas(r2);
      c2.drawImageRect(image, Offset.zero & docSize, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..filterQuality = FilterQuality.medium);
      image = await r2.endRecording().toImage(w, h);
    }
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Future<void> _save() async {
    dirty = false;
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < layers.length; i++) {
      final l = layers[i];
      final img = l.cache ?? await _render(l);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      await Projects.writeBytes(meta.id, 'layer_$i.png', bd!.buffer.asUint8List());
      list.add({'name': l.name, 'visible': l.visible, 'opacity': l.opacity, 'file': 'layer_$i.png'});
    }
    await Projects.writeBytes(meta.id, 'canvas.json', Uint8List.fromList(utf8.encode(jsonEncode({'bg': bg.toARGB32(), 'layers': list}))));
    final k = 256 / math.max(meta.w, meta.h);
    await Projects.writeBytes(meta.id, 'thumb.png', await _composite(w: (meta.w * k).round(), h: (meta.h * k).round()));
    await Projects.saveMeta(meta);
  }

  Offset _toDoc(Offset p) => (p - offset) / scale;

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1 && e.buttons != kMiddleMouseButton && e.buttons != kSecondaryMouseButton) {
      final l = layers[active];
      if (!l.visible) {
        toast(context, 'Этот слой скрыт — включи его, чтобы рисовать');
        return;
      }
      final s = Stroke(brush, color, sizes[brush]!, DateTime.now().microsecond);
      s.pts.add(_toDoc(e.localPosition));
      s.pressure.add(_pressure(e));
      setState(() => cur = s);
    } else if (_pointers.length == 2) {
      cur = null;
      final ps = _pointers.values.toList();
      _pinchDist = (ps[0] - ps[1]).distance;
      _pinchMid = (ps[0] + ps[1]) / 2;
      setState(() {});
    }
  }

  double _pressure(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus && e.kind != PointerDeviceKind.invertedStylus) return 1;
    final range = e.pressureMax - e.pressureMin;
    return range <= 0 ? 1 : (0.2 + 1.3 * ((e.pressure - e.pressureMin) / range)).clamp(0.2, 1.5);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.buttons == kMiddleMouseButton || e.buttons == kSecondaryMouseButton) {
      setState(() => offset += e.delta);
      return;
    }
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1 && cur != null) {
      final p = _toDoc(e.localPosition);
      if ((p - cur!.pts.last).distance * scale < 1.5) return;
      cur!.pts.add(p);
      cur!.pressure.add(_pressure(e));
      setState(() {});
    } else if (_pointers.length == 2 && _pinchDist != null) {
      final ps = _pointers.values.toList();
      final dist = (ps[0] - ps[1]).distance, mid = (ps[0] + ps[1]) / 2;
      final ns = (scale * dist / _pinchDist!).clamp(0.05, 20.0);
      setState(() {
        offset = mid - (_pinchMid! - offset) * (ns / scale);
        scale = ns;
      });
      _pinchDist = dist;
      _pinchMid = mid;
    }
  }

  Future<void> _onUp(PointerEvent e) async {
    _pointers.remove(e.pointer);
    if (_pointers.isNotEmpty) return;
    _pinchDist = null;
    final s = cur;
    if (s == null) return;
    cur = null;
    final l = layers[active];
    l.strokes.add(s);
    undo.add((active, s));
    redo.clear();
    if (!recent.contains(s.color) && s.brush != Brush.eraser) {
      recent.insert(0, s.color);
      if (recent.length > 8) recent.removeLast();
    }
    await _flatten(l);
    await _recache(l);
    _changed();
  }

  void _onScroll(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final ns = (scale * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.05, 20.0);
      setState(() {
        offset = e.localPosition - (e.localPosition - offset) * (ns / scale);
        scale = ns;
      });
    }
  }

  Future<void> _undo() async {
    if (undo.isEmpty) return;
    final (li, s) = undo.removeLast();
    if (li >= layers.length) return;
    layers[li].strokes.remove(s);
    redo.add((li, s));
    await _recache(layers[li]);
    _changed();
  }

  Future<void> _redo() async {
    if (redo.isEmpty) return;
    final (li, s) = redo.removeLast();
    if (li >= layers.length) return;
    layers[li].strokes.add(s);
    undo.add((li, s));
    await _recache(layers[li]);
    _changed();
  }

  Future<void> _export() async {
    final bytes = await _composite();
    if (!mounted) return;
    final path = await saveBytes(context, '${meta.name}.png', bytes);
    if (path != null && mounted) toast(context, 'Сохранено');
  }

  void _layersSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          void upd(VoidCallback f) {
            f();
            set(() {});
            setState(() {});
            _changed();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Text('Слои', style: W.h2),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => upd(() {
                      layers.insert(active + 1, Layer('Слой ${layers.length + 1}'));
                      active++;
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Новый'),
                  ),
                ]),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView(shrinkWrap: true, children: [
                    for (var i = layers.length - 1; i >= 0; i--)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: i == active ? W.accent.withValues(alpha: 0.15) : W.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: i == active ? W.accent : W.border),
                        ),
                        child: Column(children: [
                          ListTile(
                            dense: true,
                            onTap: () => upd(() => active = i),
                            leading: IconButton(
                              icon: Icon(layers[i].visible ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => upd(() => layers[i].visible = !layers[i].visible),
                            ),
                            title: Text(layers[i].name, style: W.body),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                onPressed: i == layers.length - 1
                                    ? null
                                    : () => upd(() {
                                          final l = layers.removeAt(i);
                                          layers.insert(i + 1, l);
                                          active = i + 1;
                                          undo.clear();
                                          redo.clear();
                                        }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward, size: 18),
                                onPressed: i == 0
                                    ? null
                                    : () => upd(() {
                                          final l = layers.removeAt(i);
                                          layers.insert(i - 1, l);
                                          active = i - 1;
                                          undo.clear();
                                          redo.clear();
                                        }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: layers.length == 1
                                    ? null
                                    : () => upd(() {
                                          layers.removeAt(i);
                                          active = active.clamp(0, layers.length - 1);
                                          undo.clear();
                                          redo.clear();
                                        }),
                              ),
                            ]),
                          ),
                          if (i == active)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(children: [
                                const Text('Непрозрачность', style: W.small),
                                Expanded(child: Slider(value: layers[i].opacity, onChanged: (v) => upd(() => layers[i].opacity = v))),
                              ]),
                            ),
                        ]),
                      ),
                  ]),
                ),
                ListTile(
                  dense: true,
                  leading: Container(width: 24, height: 24, decoration: BoxDecoration(color: bg, border: Border.all(color: W.border))),
                  title: const Text('Цвет фона', style: W.body),
                  onTap: () async {
                    final c = await pickColor(context, bg);
                    if (c != null) upd(() => bg = c);
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(meta.name),
        actions: [
          IconButton(tooltip: 'Отменить', icon: const Icon(Icons.undo), onPressed: undo.isEmpty ? null : _undo),
          IconButton(tooltip: 'Вернуть', icon: const Icon(Icons.redo), onPressed: redo.isEmpty ? null : _redo),
          IconButton(tooltip: 'Слои', icon: const Icon(Icons.layers_outlined), onPressed: _layersSheet),
          IconButton(tooltip: 'Сохранить картинку (PNG)', icon: const Icon(Icons.ios_share), onPressed: _export),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              if (scale == 0) {
                scale = math.min((box.maxWidth - 24) / meta.w, (box.maxHeight - 24) / meta.h);
                offset = Offset((box.maxWidth - meta.w * scale) / 2, (box.maxHeight - meta.h * scale) / 2);
              }
              return ClipRect(
                child: Listener(
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onUp,
                  onPointerSignal: _onScroll,
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _CanvasPainter(layers, active, cur, bg, scale, offset, docSize),
                  ),
                ),
              );
            }),
          ),
          Container(
            color: W.surface,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  GestureDetector(
                    onTap: () async {
                      final c = await pickColor(context, color, recent: recent);
                      if (c != null) setState(() => color = c);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: W.text, width: 2)),
                    ),
                  ),
                  for (final b in Brush.values)
                    IconButton(
                      tooltip: brushNames[b]!.$1,
                      style: IconButton.styleFrom(backgroundColor: brush == b ? W.accent.withValues(alpha: 0.25) : null),
                      icon: Icon(brushNames[b]!.$2, color: brush == b ? W.accent : W.text),
                      onPressed: () => setState(() => brush = b),
                    ),
                  for (final c in recent)
                    GestureDetector(
                      onTap: () => setState(() => color = c),
                      child: Container(width: 24, height: 24, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: W.border))),
                    ),
                ]),
              ),
              Row(children: [
                Text(brushNames[brush]!.$1, style: W.small),
                Expanded(
                  child: Slider(
                    value: sizes[brush]!,
                    min: 1,
                    max: 200,
                    onChanged: (v) => setState(() => sizes[brush] = v),
                  ),
                ),
                SizedBox(width: 36, child: Text('${sizes[brush]!.round()}', style: W.small)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final List<Layer> layers;
  final int active;
  final Stroke? cur;
  final Color bg;
  final double scale;
  final Offset offset;
  final Size doc;
  _CanvasPainter(this.layers, this.active, this.cur, this.bg, this.scale, this.offset, this.doc);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0E1525));
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    final r = Offset.zero & doc;
    canvas.drawRect(r.inflate(2 / scale), Paint()..color = const Color(0x55000000));
    canvas.clipRect(r);
    canvas.drawRect(r, Paint()..color = bg);
    for (var i = 0; i < layers.length; i++) {
      final l = layers[i];
      if (!l.visible) continue;
      canvas.saveLayer(r, Paint()..color = Color.fromRGBO(0, 0, 0, l.opacity));
      if (l.cache != null) canvas.drawImage(l.cache!, Offset.zero, Paint());
      if (i == active && cur != null) paintStroke(canvas, cur!);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}
