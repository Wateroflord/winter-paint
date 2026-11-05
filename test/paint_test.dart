import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winter_paint/canvas_editor.dart';
import 'package:winter_paint/pixel.dart';
import 'package:winter_paint/store.dart';

void main() {
  test('пиксель-арт сохраняется и читается без потерь (кадры, fps, палитра)', () {
    final f1 = Uint32List(4 * 3)..[0] = 0xFFFF0000;
    final f2 = Uint32List(4 * 3)..[11] = 0x8000FF00;
    final doc = PixelDoc(4, 3, [f1, f2], fps: 12, palette: [0xFF000000, 0xFFFFFFFF]);
    final back = PixelDoc.fromJson(doc.toJson());
    expect(back.w, 4);
    expect(back.h, 3);
    expect(back.fps, 12);
    expect(back.palette, [0xFF000000, 0xFFFFFFFF]);
    expect(back.frames.length, 2);
    expect(back.frames[0][0], 0xFFFF0000);
    expect(back.frames[1][11], 0x8000FF00);
  });

  test('новый пиксель-арт получает стандартную палитру из 16 цветов', () {
    final doc = PixelDoc(8, 8, [Uint32List(64)]);
    expect(doc.palette.length, 16);
    expect(doc.fps, 8);
  });

  test('описание проекта сохраняется и читается', () {
    final m = ProjectMeta('id1', 'Рыцарь', 'pixel', 32, 32, 123);
    final back = ProjectMeta.fromJson(m.toJson());
    expect([back.id, back.name, back.kind, back.w, back.h, back.updated], ['id1', 'Рыцарь', 'pixel', 32, 32, 123]);
  });

  test('каждая кисть рисует штрих без ошибок', () {
    for (final b in Brush.values) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final s = Stroke(b, Colors.red, 12, 7);
      for (var i = 0; i < 20; i++) {
        s.pts.add(Offset(10.0 + i * 5, 20.0 + (i % 3) * 4));
        s.pressure.add(0.5 + (i % 5) / 10);
      }
      paintStroke(c, s);
      final one = Stroke(b, Colors.blue, 5, 1)
        ..pts.add(const Offset(5, 5))
        ..pressure.add(1);
      paintStroke(c, one);
      rec.endRecording();
      expect(brushNames.containsKey(b), isTrue, reason: '$b без названия');
    }
  });
}
