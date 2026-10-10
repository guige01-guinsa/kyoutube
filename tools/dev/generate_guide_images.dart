import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('render original ingredient illustrations', () async {
    for (final id in ['carrot', 'onion', 'tofu', 'mushroom', 'egg', 'rice']) {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      final p = ui.Paint();
      void oval(double x, double y, double w, double h, int color) {
        p.color = ui.Color(color);
        c.drawOval(ui.Rect.fromLTWH(x, y, w, h), p);
      }

      void line(
          double x, double y, double x2, double y2, int color, double width) {
        p
          ..color = ui.Color(color)
          ..strokeWidth = width
          ..strokeCap = ui.StrokeCap.round;
        c.drawLine(ui.Offset(x, y), ui.Offset(x2, y2), p);
      }

      void shape(List<ui.Offset> pts, int color) {
        p.color = ui.Color(color);
        final path = ui.Path()..addPolygon(pts, true);
        c.drawPath(path, p);
      }

      p.shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          const ui.Offset(400, 250),
          [const ui.Color(0xffe8f2e9), const ui.Color(0xfffaf4e7)]);
      c.drawRect(const ui.Rect.fromLTWH(0, 0, 400, 250), p);
      p.shader = null;
      oval(74, 191, 256, 28, 0x18203e36);
      oval(57, 49, 285, 152, 0xfffcfbf5);
      switch (id) {
        case 'carrot':
          shape([
            const ui.Offset(255, 75),
            const ui.Offset(291, 111),
            const ui.Offset(111, 190)
          ], 0xffed8d40);
          shape([
            const ui.Offset(255, 75),
            const ui.Offset(273, 93),
            const ui.Offset(111, 190)
          ], 0xfff2ac59);
          for (var i = 0; i < 3; i++) {
            line(272, 90, 286 + i * 13, 38 + i * 6, 0xff397457, 12);
          }
          line(226, 110, 240, 125, 0xffc36c33, 5);
          line(195, 135, 203, 144, 0xffc36c33, 5);
        case 'onion':
          oval(128, 91, 139, 110, 0xffd2a06d);
          oval(138, 91, 110, 103, 0xffeac596);
          oval(148, 92, 75, 98, 0xfff3ddb6);
          shape([
            const ui.Offset(182, 99),
            const ui.Offset(183, 62),
            const ui.Offset(198, 82),
            const ui.Offset(211, 67),
            const ui.Offset(215, 98)
          ], 0xffbc8554);
          line(195, 194, 185, 211, 0xffbc8554, 3);
          line(204, 195, 209, 211, 0xffbc8554, 3);
        case 'tofu':
          shape([
            const ui.Offset(100, 108),
            const ui.Offset(196, 71),
            const ui.Offset(304, 113),
            const ui.Offset(207, 153)
          ], 0xfffff7d9);
          shape([
            const ui.Offset(100, 108),
            const ui.Offset(207, 153),
            const ui.Offset(207, 198),
            const ui.Offset(100, 153)
          ], 0xffe8dfbb);
          shape([
            const ui.Offset(207, 153),
            const ui.Offset(304, 113),
            const ui.Offset(304, 158),
            const ui.Offset(207, 198)
          ], 0xffd7cfae);
          line(149, 89, 254, 134, 0xffded5b4, 2);
          line(149, 129, 247, 90, 0xffded5b4, 2);
        case 'mushroom':
          for (final x in [140.0, 225.0]) {
            p.color = const ui.Color(0xffe8d9bb);
            c.drawRRect(
                ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(x, 118, 32, 74),
                    const ui.Radius.circular(12)),
                p);
            oval(x - 41, 78, 111, 68, 0xff99755d);
            oval(x - 35, 118, 101, 24, 0xffc4a68a);
          }
          oval(123, 94, 16, 9, 0xffc5aa8d);
          oval(211, 89, 13, 8, 0xffc5aa8d);
        case 'egg':
          oval(114, 85, 90, 116, 0xffd7b385);
          oval(122, 82, 76, 109, 0xffefd6b4);
          oval(211, 105, 92, 85, 0xfffefdf7);
          oval(232, 125, 50, 48, 0xffefb92c);
          oval(239, 129, 26, 20, 0xfff5cf4a);
        case 'rice':
          p.color = const ui.Color(0xff317762);
          c.drawArc(const ui.Rect.fromLTWH(107, 105, 191, 102), 0, 3.14159265,
              false, p);
          oval(107, 97, 191, 61, 0xffe9dfc6);
          oval(117, 85, 172, 60, 0xfffffdfa);
          for (var i = 0; i < 22; i++) {
            oval(132 + (i * 31 % 137).toDouble(),
                100 + (i * 13 % 30).toDouble(), 10, 4, 0xffdcd8c5);
          }
      }
      line(32, 226, 66, 226, 0xff9db8a7, 3);
      line(332, 30, 368, 30, 0xff9db8a7, 3);
      final picture = rec.endRecording();
      final image = await picture.toImage(400, 250);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('assets/guide/$id.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
      image.dispose();
      // Keep all artwork generated from local vector drawing commands.
    }
  });
}
