import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/ui/industrial.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('static dots are uniform and schedule no frames: $brightness', (
      t,
    ) async {
      final key = GlobalKey();
      var builds = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: industrialTheme(brightness),
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 96,
              height: 96,
              child: RepaintBoundary(
                key: key,
                child: IndustrialPaper(
                  child: Builder(
                    builder: (_) {
                      builds++;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      Future<Uint8List> capture() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();
        return bytes;
      }

      final first = (await t.runAsync(capture))!;
      List<int> pixel(Uint8List data, int x, int y) =>
          data.sublist((y * 96 + x) * 4, (y * 96 + x) * 4 + 4);
      expect(pixel(first, 12, 12), isNot(equals(pixel(first, 0, 0))));
      for (var x = 12; x < 96; x += 24) {
        for (var y = 12; y < 96; y += 24) {
          for (var dx = -3; dx <= 3; dx++) {
            for (var dy = -3; dy <= 3; dy++) {
              expect(
                pixel(first, x + dx, y + dy),
                pixel(first, 12 + dx, 12 + dy),
              );
            }
          }
          expect(pixel(first, x - 3, y), pixel(first, 0, 0));
        }
      }
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.pump(const Duration(seconds: 10));
      expect(t.binding.hasScheduledFrame, isFalse);
      expect(builds, 1);
      expect((await t.runAsync(capture))!, first);
      await t.pumpWidget(const SizedBox());
    });
  }
}
