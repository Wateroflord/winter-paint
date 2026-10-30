import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'common.dart';
import 'store.dart';
import 'ui.dart';

enum PxTool { pencil, eraser, fill, line, rect, picker }

/// Документ пиксель-арта: кадры анимации (ARGB на пиксель).
class PixelDoc {
  final int w, h;
  final List<Uint32List> frames;
  int fps;
  final List<int> palette;
  PixelDoc(this.w, this.h, this.frames, {this.fps = 8, List<int>? palette}) : palette = palette ?? [...defaultPalette];

  static const defaultPalette = [
    0xFF000000, 0xFF1D2B53, 0xFF7E2553, 0xFF008751, 0xFFAB5236, 0xFF5F574F, 0xFFC2C3C7, 0xFFFFF1E8,
    0xFFFF004D, 0xFFFFA300, 0xFFFFEC27, 0xFF00E436, 0xFF29ADFF, 0xFF83769C, 0xFFFF77A8, 0xFFFFCCAA,
  ];

  Map<String, dynamic> toJson() => {
        'w': w,
        'h': h,
        'fps': fps,
        'palette': palette,
        'frames': [for (final f in frames) base64Encode(f.buffer.asUint8List())],
      };

  static PixelDoc fromJson(Map j) {
    final w = (j['w'] as num).toInt(), h = (j['h'] as num).toInt();
    return PixelDoc(
      w,
      h,
      [for (final f in (j['frames'] as List)) Uint32List.view(Uint8List.fromList(base64Decode('$f')).buffer)],
      fps: (j['fps'] as num?)?.toInt() ?? 8,
      palette: [for (final c in (j['palette'] as List? ?? const [])) (c as num).toInt()],
    );
  }
}

class PixelEditor extends StatefulWidget {
  final ProjectMeta meta;
  const PixelEditor({super.key, required this.meta});

  @override
  State<PixelEditor> createState() => _PixelEditorState();
}

class _PixelEditorState extends State<PixelEditor> {
  PixelDoc? doc;
  int frame = 0;
  PxTool tool = PxTool.pencil;
  int color = 0xFF000000;
  bool mirror = false, onion = true, grid = true, playing = false;
  final List<(int, Uint32List)> undo = [], redo = [];
  double scale = 0; // пикселей экрана на пиксель рисунка (0 — подобрать)
  Offset offset = Offset.zero;
  Timer? _play;
  int playFrame = 0;
  Uint32List? _preview; // для линии и прямоугольника
  int? _sx, _sy;
  final Map<int, Offset> _pointers = {};
  double? _pinchDist;
  Offset? _pinchMid;
  bool _drawing = false;
  Timer? _saveT;

  ProjectMeta get meta => widget.meta;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _play?.cancel();
    _saveT?.cancel();
    _save();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await Projects.readBytes(meta.id, 'pixel.json');
    final d = b == null ? null : PixelDoc.fromJson(jsonDecode(utf8.decode(b)) as Map);
    setState(() => doc = d ?? PixelDoc(meta.w, meta.h, [Uint32List(meta.w * meta.h)]));
  }

  Future<void> _save() async {
    final d = doc;
    if (d == null) return;
    await Projects.writeBytes(meta.id, 'pixel.json', Uint8List.fromList(utf8.encode(jsonEncode(d.toJson()))));
    await Projects.writeBytes(meta.id, 'thumb.png', _png(d.frames[0], d.w, d.h, math.max(1, 128 ~/ math.max(d.w, d.h))));
    await Projects.saveMeta(meta);
  }

  void _changed() {
    _saveT?.cancel();
    _saveT = Timer(const Duration(seconds: 2), _save);
    setState(() {});
  }

  Uint32List get px => doc!.frames[frame];

  void _snapshot() {
    undo.add((frame, Uint32List.fromList(px)));
    if (undo.length > 80) undo.removeAt(0);
    redo.clear();
  }

  void _undo() {
    if (undo.isEmpty) return;
    final (f, data) = undo.removeLast();
    if (f >= doc!.frames.length) return;
    redo.add((f, Uint32List.fromList(doc!.frames[f])));
    doc!.frames[f] = data;
    frame = f;
    _changed();
  }

  void _redo() {
    if (redo.isEmpty) return;
    final (f, data) = redo.removeLast();
    if (f >= doc!.frames.length) return;
    undo.add((f, Uint32List.fromList(doc!.frames[f])));
    doc!.frames[f] = data;
    frame = f;
    _changed();
  }

  void _set(Uint32List p, int x, int y, int c) {
    final d = doc!;
    if (x < 0 || y < 0 || x >= d.w || y >= d.h) return;
    p[y * d.w + x] = c;
    if (mirror) p[y * d.w + (d.w - 1 - x)] = c;
  }

  void _lineTo(Uint32List p, int x0, int y0, int x1, int y1, int c) {
    final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    while (true) {
      _set(p, x0, y0, c);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y0 += sy;
      }
    }
  }

  void _fill(int x, int y, int c) {
    final d = doc!;
    final p = px;
    final target = p[y * d.w + x];
    if (target == c) return;
    final stack = [y * d.w + x];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (p[i] != target) continue;
      p[i] = c;
      final ix = i % d.w, iy = i ~/ d.w;
      if (ix > 0) stack.add(i - 1);
      if (ix < d.w - 1) stack.add(i + 1);
      if (iy > 0) stack.add(i - d.w);
      if (iy < d.h - 1) stack.add(i + d.w);
    }
  }

  (int, int) _cell(Offset local) {
    final p = (local - offset) / scale;
    return (p.dx.floor(), p.dy.floor());
  }

  int? _lx, _ly;

  void _down(Offset local) {
    final (x, y) = _cell(local);
    final d = doc!;
    if (tool == PxTool.picker) {
      if (x >= 0 && y >= 0 && x < d.w && y < d.h && px[y * d.w + x] != 0) setState(() => color = px[y * d.w + x]);
      return;
    }
    _snapshot();
    _drawing = true;
    if (tool == PxTool.fill) {
      if (x >= 0 && y >= 0 && x < d.w && y < d.h) _fill(x, y, color);
      _drawing = false;
      _changed();
      return;
    }
    if (tool == PxTool.line || tool == PxTool.rect) {
      _sx = x;
      _sy = y;
      _preview = Uint32List.fromList(px);
      _shape(x, y);
      return;
    }
    _set(px, x, y, tool == PxTool.eraser ? 0 : color);
    _lx = x;
    _ly = y;
    setState(() {});
  }

  void _shape(int x, int y) {
    final base = undo.last.$2;
    final p = Uint32List.fromList(base);
    if (tool == PxTool.line) {
      _lineTo(p, _sx!, _sy!, x, y, color);
    } else {
      _lineTo(p, _sx!, _sy!, x, _sy!, color);
      _lineTo(p, x, _sy!, x, y, color);
      _lineTo(p, x, y, _sx!, y, color);
      _lineTo(p, _sx!, y, _sx!, _sy!, color);
    }
    _preview = p;
    setState(() {});
  }

  void _move(Offset local) {
    if (!_drawing) return;
    final (x, y) = _cell(local);
    if (tool == PxTool.line || tool == PxTool.rect) {
      _shape(x, y);
      return;
    }
    if (_lx != null) _lineTo(px, _lx!, _ly!, x, y, tool == PxTool.eraser ? 0 : color);
    _lx = x;
    _ly = y;
    setState(() {});
  }

  void _up() {
    if (!_drawing) return;
    _drawing = false;
    if (_preview != null) {
      doc!.frames[frame] = _preview!;
      _preview = null;
    }
    _lx = _ly = null;
    _changed();
  }

  // ---------- жесты: один палец рисует, два — двигают и масштабируют ----------

  void _onDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && e.buttons == kSecondaryMouseButton) {
      final (x, y) = _cell(e.localPosition);
      final d = doc!;
      if (x >= 0 && y >= 0 && x < d.w && y < d.h && px[y * d.w + x] != 0) setState(() => color = px[y * d.w + x]);
      return;
    }
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1 && e.buttons != kMiddleMouseButton) {
      _down(e.localPosition);
    } else if (_pointers.length == 2) {
      // Второй палец — отменяем начатый штрих.
      if (_drawing) {
        _drawing = false;
        _preview = null;
        if (undo.isNotEmpty) {
          final (f, data) = undo.removeLast();
          doc!.frames[f] = data;
        }
      }
      final ps = _pointers.values.toList();
      _pinchDist = (ps[0] - ps[1]).distance;
      _pinchMid = (ps[0] + ps[1]) / 2;
      setState(() {});
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.buttons == kMiddleMouseButton) {
      setState(() => offset += e.delta);
      return;
    }
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _move(e.localPosition);
    } else if (_pointers.length == 2 && _pinchDist != null) {
      final ps = _pointers.values.toList();
      final dist = (ps[0] - ps[1]).distance, mid = (ps[0] + ps[1]) / 2;
      final k = dist / _pinchDist!;
      final ns = (scale * k).clamp(1.0, 80.0);
      final real = ns / scale;
      setState(() {
        offset = mid - (_pinchMid! - offset) * real + Offset.zero;
        scale = ns;
      });
      _pinchDist = dist;
      _pinchMid = mid;
    }
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      _up();
      _pinchDist = null;
    }
  }

  void _onScroll(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final k = e.scrollDelta.dy > 0 ? 0.9 : 1.1;
      final ns = (scale * k).clamp(1.0, 80.0);
      setState(() {
        offset = e.localPosition - (e.localPosition - offset) * (ns / scale);
        scale = ns;
      });
    }
  }

  // ---------- кадры ----------

  void _addFrame({bool copy = false}) {
    final d = doc!;
    d.frames.insert(frame + 1, copy ? Uint32List.fromList(px) : Uint32List(d.w * d.h));
    frame++;
    _changed();
  }

  void _deleteFrame() {
    final d = doc!;
    if (d.frames.length <= 1) {
      _snapshot();
      px.fillRange(0, px.length, 0);
      _changed();
      return;
    }
    d.frames.removeAt(frame);
    frame = frame.clamp(0, d.frames.length - 1);
    undo.clear();
    redo.clear();
    _changed();
  }

  void _togglePlay() {
    _play?.cancel();
    playing = !playing;
    if (playing) {
      playFrame = frame;
      _play = Timer.periodic(Duration(milliseconds: 1000 ~/ doc!.fps), (_) {
        setState(() => playFrame = (playFrame + 1) % doc!.frames.length);
      });
    }
    setState(() {});
  }

  // ---------- экспорт ----------

  static Uint8List _png(Uint32List p, int w, int h, int k) {
    final im = img.Image(width: w * k, height: h * k, numChannels: 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final c = p[y * w + x];
        for (var dy = 0; dy < k; dy++) {
          for (var dx = 0; dx < k; dx++) {
            im.setPixelRgba(x * k + dx, y * k + dy, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, (c >> 24) & 0xFF);
          }
        }
      }
    }
    return img.encodePng(im);
  }

  Future<void> _export() async {
    final d = doc!;
    var k = math.max(1, 512 ~/ math.max(d.w, d.h));
    final what = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Экспорт', style: W.h2),
              Row(children: [
                const Text('Увеличение', style: W.body),
                Expanded(child: Slider(value: k.toDouble(), min: 1, max: 32, divisions: 31, label: '×$k', onChanged: (v) => set(() => k = v.round()))),
                Text('×$k  (${d.w * k}×${d.h * k})', style: W.small),
              ]),
              ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Текущий кадр (PNG)'), onTap: () => Navigator.pop(ctx, 'png')),
              ListTile(leading: const Icon(Icons.view_column_outlined), title: const Text('Спрайт-лист: все кадры в ряд (PNG)'), onTap: () => Navigator.pop(ctx, 'sheet')),
              ListTile(leading: const Icon(Icons.gif_box_outlined), title: const Text('Анимация (GIF)'), onTap: () => Navigator.pop(ctx, 'gif')),
            ]),
          ),
        ),
      ),
    );
    if (what == null || !mounted) return;
    Uint8List bytes;
    String name;
    if (what == 'png') {
      bytes = _png(px, d.w, d.h, k);
      name = '${meta.name}_${frame + 1}.png';
    } else if (what == 'sheet') {
      final n = d.frames.length;
      final sheet = Uint32List(d.w * n * d.h);
      for (var f = 0; f < n; f++) {
        for (var y = 0; y < d.h; y++) {
          for (var x = 0; x < d.w; x++) {
            sheet[y * d.w * n + f * d.w + x] = d.frames[f][y * d.w + x];
          }
        }
      }
      bytes = _png(sheet, d.w * n, d.h, k);
      name = '${meta.name}_sheet.png';
    } else {
      final enc = img.GifEncoder(delay: 100 ~/ d.fps, repeat: 0);
      for (final f in d.frames) {
        final im = img.decodePng(_png(f, d.w, d.h, k))!;
        enc.addFrame(im, duration: 100 ~/ d.fps);
      }
      bytes = enc.finish()!;
      name = '${meta.name}.gif';
    }
    if (!mounted) return;
    final path = await saveBytes(context, name, bytes);
    if (path != null && mounted) toast(context, 'Сохранено');
  }

  Future<void> _addColor() async {
    final c = await pickColor(context, Color(color));
    if (c == null) return;
    setState(() {
      color = c.toARGB32();
      if (!doc!.palette.contains(color)) doc!.palette.add(color);
    });
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final d = doc;
    if (d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final tools = [
      (PxTool.pencil, Icons.edit, 'Карандаш'),
      (PxTool.eraser, Icons.auto_fix_normal, 'Ластик'),
      (PxTool.fill, Icons.format_color_fill, 'Заливка'),
      (PxTool.line, Icons.horizontal_rule, 'Линия'),
      (PxTool.rect, Icons.crop_square, 'Прямоугольник'),
      (PxTool.picker, Icons.colorize, 'Пипетка'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(meta.name),
        actions: [
          IconButton(tooltip: 'Отменить', icon: const Icon(Icons.undo), onPressed: undo.isEmpty ? null : _undo),
          IconButton(tooltip: 'Вернуть', icon: const Icon(Icons.redo), onPressed: redo.isEmpty ? null : _redo),
          IconButton(tooltip: 'Экспорт', icon: const Icon(Icons.ios_share), onPressed: _export),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() {
              if (v == 'grid') grid = !grid;
              if (v == 'onion') onion = !onion;
              if (v == 'mirror') mirror = !mirror;
              if (v == 'fit') scale = 0;
            }),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'grid', checked: grid, child: const Text('Сетка')),
              CheckedPopupMenuItem(value: 'onion', checked: onion, child: const Text('Луковая кожура (прошлый кадр)')),
              CheckedPopupMenuItem(value: 'mirror', checked: mirror, child: const Text('Зеркальное рисование')),
              const PopupMenuItem(value: 'fit', child: Text('Вписать в экран')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              if (scale == 0) {
                scale = math.max(1.0, math.min((box.maxWidth - 24) / d.w, (box.maxHeight - 24) / d.h).floorToDouble());
                offset = Offset((box.maxWidth - d.w * scale) / 2, (box.maxHeight - d.h * scale) / 2);
              }
              final show = playing ? d.frames[playFrame] : (_preview ?? px);
              return ClipRect(
                child: Listener(
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onUp,
                  onPointerSignal: _onScroll,
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _PixelPainter(
                      d.w,
                      d.h,
                      show,
                      onion && !playing && frame > 0 ? d.frames[frame - 1] : null,
                      scale,
                      offset,
                      grid && scale >= 6,
                    ),
                  ),
                ),
              );
            }),
          ),
          // Инструменты
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (final t in tools)
                IconButton(
                  tooltip: t.$3,
                  isSelected: tool == t.$1,
                  style: IconButton.styleFrom(backgroundColor: tool == t.$1 ? W.accent.withValues(alpha: 0.25) : null),
                  icon: Icon(t.$2, color: tool == t.$1 ? W.accent : W.text),
                  onPressed: () => setState(() => tool = t.$1),
                ),
              IconButton(
                tooltip: 'Зеркало',
                icon: Icon(Icons.flip, color: mirror ? W.accent : W.muted),
                onPressed: () => setState(() => mirror = !mirror),
              ),
            ]),
          ),
          // Палитра
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              GestureDetector(
                onTap: _addColor,
                child: Container(
                  width: 34,
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(6), border: Border.all(color: W.text, width: 2)),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ),
              for (final c in d.palette)
                GestureDetector(
                  onTap: () => setState(() {
                    color = c;
                    if (tool == PxTool.eraser || tool == PxTool.picker) tool = PxTool.pencil;
                  }),
                  onLongPress: () => setState(() => d.palette.remove(c)),
                  child: Container(
                    width: 30,
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Color(c),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c == color ? W.accent : W.border, width: c == color ? 3 : 1),
                    ),
                  ),
                ),
            ]),
          ),
          // Кадры
          Container(
            color: W.surface,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              IconButton(tooltip: playing ? 'Стоп' : 'Просмотр анимации', icon: Icon(playing ? Icons.stop : Icons.play_arrow), onPressed: _togglePlay),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (var i = 0; i < d.frames.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => frame = i),
                        child: Container(
                          width: 52,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(border: Border.all(color: i == frame ? W.accent : W.border, width: i == frame ? 2 : 1), borderRadius: BorderRadius.circular(6)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: CustomPaint(painter: _PixelPainter.thumb(d.w, d.h, d.frames[i])),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                onSelected: (v) {
                  if (v == 'add') _addFrame();
                  if (v == 'dup') _addFrame(copy: true);
                  if (v == 'del') _deleteFrame();
                  if (v == 'left' && frame > 0) {
                    final f = d.frames.removeAt(frame);
                    d.frames.insert(--frame, f);
                    _changed();
                  }
                  if (v == 'right' && frame < d.frames.length - 1) {
                    final f = d.frames.removeAt(frame);
                    d.frames.insert(++frame, f);
                    _changed();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('Новый пустой кадр')),
                  PopupMenuItem(value: 'dup', child: Text('Копия кадра')),
                  PopupMenuItem(value: 'left', child: Text('Сдвинуть влево')),
                  PopupMenuItem(value: 'right', child: Text('Сдвинуть вправо')),
                  PopupMenuItem(value: 'del', child: Text('Удалить кадр')),
                ],
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Text('Кадр ${frame + 1}/${d.frames.length}', style: W.small),
              const Spacer(),
              const Text('Скорость', style: W.small),
              SizedBox(
                width: 140,
                child: Slider(
                  value: d.fps.toDouble(),
                  min: 1,
                  max: 24,
                  divisions: 23,
                  onChanged: (v) {
                    d.fps = v.round();
                    if (playing) {
                      _togglePlay();
                      _togglePlay();
                    }
                    _changed();
                  },
                ),
              ),
              Text('${d.fps} к/с', style: W.small),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PixelPainter extends CustomPainter {
  final int w, h;
  final Uint32List px;
  final Uint32List? onion;
  final double scale;
  final Offset offset;
  final bool grid;
  final bool thumb;
  _PixelPainter(this.w, this.h, this.px, this.onion, this.scale, this.offset, this.grid) : thumb = false;
  _PixelPainter.thumb(this.w, this.h, this.px)
      : onion = null,
        scale = 0,
        offset = Offset.zero,
        grid = false,
        thumb = true;

  @override
  void paint(Canvas canvas, Size size) {
    var s = scale;
    var o = offset;
    if (thumb) {
      s = math.min(size.width / w, size.height / h);
      o = Offset((size.width - w * s) / 2, (size.height - h * s) / 2);
    }
    final area = Rect.fromLTWH(o.dx, o.dy, w * s, h * s);
    // Шахматка прозрачности
    canvas.save();
    canvas.clipRect(area);
    final cell = math.max(s, 6.0);
    final a = Paint()..color = const Color(0xFFE8ECF2), b = Paint()..color = const Color(0xFFC9D1DC);
    canvas.drawRect(area, a);
    for (var y = area.top; y < area.bottom; y += cell) {
      for (var x = area.left + (((y - area.top) / cell).round().isOdd ? cell : 0); x < area.right; x += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), b);
      }
    }
    final p = Paint()..isAntiAlias = false;
    if (onion != null) {
      for (var i = 0; i < onion!.length; i++) {
        final c = onion![i];
        if (c >> 24 == 0) continue;
        p.color = Color(c).withValues(alpha: 0.25);
        canvas.drawRect(Rect.fromLTWH(o.dx + (i % w) * s, o.dy + (i ~/ w) * s, s + 0.5, s + 0.5), p);
      }
    }
    for (var i = 0; i < px.length; i++) {
      final c = px[i];
      if (c >> 24 == 0) continue;
      p.color = Color(c);
      canvas.drawRect(Rect.fromLTWH(o.dx + (i % w) * s, o.dy + (i ~/ w) * s, s + 0.5, s + 0.5), p);
    }
    if (grid) {
      final g = Paint()
        ..color = const Color(0x22000000)
        ..strokeWidth = 1;
      for (var x = 0; x <= w; x++) {
        canvas.drawLine(Offset(o.dx + x * s, o.dy), Offset(o.dx + x * s, o.dy + h * s), g);
      }
      for (var y = 0; y <= h; y++) {
        canvas.drawLine(Offset(o.dx, o.dy + y * s), Offset(o.dx + w * s, o.dy + y * s), g);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PixelPainter old) => true;
}
