import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'ui.dart';

/// Сохранить файл: телефон — системное окно «Сохранить как», ПК — выбор папки и имени.
Future<String?> saveBytes(BuildContext context, String name, Uint8List bytes) async {
  try {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Сохранить', fileName: name, bytes: bytes);
    if (path == null) return null;
    if (Platform.isWindows) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  } catch (e) {
    if (context.mounted) toast(context, 'Не удалось сохранить: $e');
    return null;
  }
}

/// Выбор цвета: квадрат насыщенность/яркость, полоса оттенка, прозрачность и последние цвета.
Future<Color?> pickColor(BuildContext context, Color initial, {List<Color> recent = const []}) => showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ColorSheet(initial: initial, recent: recent),
    );

class _ColorSheet extends StatefulWidget {
  final Color initial;
  final List<Color> recent;
  const _ColorSheet({required this.initial, required this.recent});

  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  late final hex = TextEditingController(text: _hex(widget.initial));

  static String _hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  static const swatches = [
    Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFF7F7F7F), Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFDD835),
    Color(0xFF43A047), Color(0xFF00ACC1), Color(0xFF1E88E5), Color(0xFF5E35B1), Color(0xFFD81B60), Color(0xFF6D4C41),
    Color(0xFFFFCCBC), Color(0xFFD7B899), Color(0xFF8D5524), Color(0xFF3B2219),
  ];

  void _set(HSVColor c) {
    setState(() => hsv = c);
    hex.text = _hex(c.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final color = hsv.toColor();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10), border: Border.all(color: W.border))),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: hex,
                style: W.body,
                decoration: const InputDecoration(prefixText: '#', isDense: true),
                onSubmitted: (v) {
                  final n = int.tryParse(v.replaceAll('#', ''), radix: 16);
                  if (n != null) _set(HSVColor.fromColor(Color(0xFF000000 | n).withValues(alpha: hsv.alpha)));
                },
              ),
            ),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context, color), child: const Text('Готово')),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: LayoutBuilder(builder: (context, box) {
              void at(Offset p) => _set(hsv.withSaturation((p.dx / box.maxWidth).clamp(0.0, 1.0)).withValue(1 - (p.dy / box.maxHeight).clamp(0.0, 1.0)));
              return GestureDetector(
                onPanDown: (d) => at(d.localPosition),
                onPanUpdate: (d) => at(d.localPosition),
                child: CustomPaint(size: Size(box.maxWidth, box.maxHeight), painter: _SVPainter(hsv)),
              );
            }),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: LayoutBuilder(builder: (context, box) {
              void at(Offset p) => _set(hsv.withHue((p.dx / box.maxWidth).clamp(0.0, 1.0) * 360));
              return GestureDetector(
                onPanDown: (d) => at(d.localPosition),
                onPanUpdate: (d) => at(d.localPosition),
                child: CustomPaint(size: Size(box.maxWidth, 28), painter: _HuePainter(hsv.hue)),
              );
            }),
          ),
          Row(children: [
            const Text('Прозрачность', style: W.small),
            Expanded(child: Slider(value: hsv.alpha, onChanged: (v) => _set(hsv.withAlpha(v)))),
            Text('${(hsv.alpha * 100).round()}%', style: W.small),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in [...widget.recent, ...swatches])
              GestureDetector(
                onTap: () => _set(HSVColor.fromColor(c)),
                child: Container(width: 30, height: 30, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6), border: Border.all(color: W.border))),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _SVPainter extends CustomPainter {
  final HSVColor hsv;
  _SVPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()]).createShader(r));
    canvas.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]).createShader(r));
    canvas.restore();
    final p = Offset(hsv.saturation * s.width, (1 - hsv.value) * s.height);
    canvas.drawCircle(p, 9, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    canvas.drawCircle(p, 9, Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _SVPainter old) => old.hsv != hsv;
}

class _HuePainter extends CustomPainter {
  final double hue;
  _HuePainter(this.hue);

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(8)),
      Paint()..shader = LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()]).createShader(r),
    );
    final x = hue / 360 * s.width;
    canvas.drawRect(Rect.fromLTWH(x - 3, 0, 6, s.height), Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant _HuePainter old) => old.hue != hue;
}

/// Шахматный фон «прозрачности».
class CheckerPainter extends CustomPainter {
  final double cell;
  const CheckerPainter({this.cell = 10});

  @override
  void paint(Canvas canvas, Size s) {
    final a = Paint()..color = const Color(0xFFE8ECF2);
    final b = Paint()..color = const Color(0xFFC9D1DC);
    canvas.drawRect(Offset.zero & s, a);
    for (var y = 0.0; y < s.height; y += cell) {
      for (var x = ((y / cell).round().isOdd ? cell : 0.0); x < s.width; x += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerPainter old) => false;
}
