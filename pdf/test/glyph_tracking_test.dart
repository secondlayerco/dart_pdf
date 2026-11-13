import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/format/stream.dart';
import 'package:pdf/widgets.dart' as widgets;
import 'package:test/test.dart';

void main() {
  group('PDF glyph tracking ::', () {
    Future<image.Image> raster(
        List<int> characters, double spacing, String name,
        {bool fallback = false}) async {
      final artifacts = Platform.environment['PDF_TRACKING_ARTIFACT_DIR'];
      final directory = artifacts == null
          ? await Directory.systemTemp.createTemp('pdf-glyph-tracking-')
          : await Directory('$artifacts/$name').create(recursive: true);
      if (artifacts == null) {
        addTearDown(() => directory.delete(recursive: true));
      }
      late final List<int> pdfBytes;
      if (fallback) {
        final document = widgets.Document(compress: false)
          ..addPage(widgets.Page(
              pageFormat: const PdfPageFormat(200, 100),
              margin: widgets.EdgeInsets.zero,
              build: (_) => widgets.SvgImage(
                    svg:
                        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><text x="30" y="50" font-size="30" letter-spacing="$spacing">℠ƀ℠</text></svg>',
                    defaultFont: widgets.Font.ttf(File('open-sans.ttf')
                        .readAsBytesSync()
                        .buffer
                        .asByteData()),
                    fallbackFonts: [
                      widgets.Font.ttf(File('noto-sans.ttf')
                          .readAsBytesSync()
                          .buffer
                          .asByteData())
                    ],
                  )));
        pdfBytes = await document.save();
      } else {
        final document = PdfDocument(compress: false);
        final font = PdfTtfFont(document,
            File('open-sans.ttf').readAsBytesSync().buffer.asByteData());
        final glyphs = characters
            .map((character) => font.font.charToGlyphIndexMap[character]!)
            .toList();
        for (final character
            in characters.where((character) => character == 0x301)) {
          expect(font.glyphMetrics(character).advanceWidth, 0,
              reason: 'fixture must contain an uncomposable zero-advance mark');
        }
        final page =
            PdfPage(document, pageFormat: const PdfPageFormat(200, 100));
        page
            .getGraphics()
            .drawGlyphs(font, 30, glyphs, 30, 50, charSpace: spacing);
        pdfBytes = await document.save();
      }
      final file = File('${directory.path}/glyphs.pdf');
      await file.writeAsBytes(pdfBytes);
      final result = await Process.run(
          Platform.environment['PDF_RASTERIZER'] ?? 'pdftoppm', [
        '-r',
        '72',
        '-png',
        '-singlefile',
        file.path,
        '${directory.path}/glyphs'
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return image
          .decodePng(await File('${directory.path}/glyphs.png').readAsBytes())!;
    }

    for (final fixture in [
      (name: 'stacked', characters: [0x78, 0x301, 0x301]),
      (name: 'leading', characters: [0x301, 0x301, 0x78]),
      (name: 'marks-only', characters: [0x301, 0x301]),
    ]) {
      test('${fixture.name} marks retain their actual raster positions',
          () async {
        final reference =
            (await raster(fixture.characters, 0, '${fixture.name}-normal'))
                .getBytes();
        for (final spacing in [-2.0, 2.0]) {
          final tracked = (await raster(
                  fixture.characters, spacing, '${fixture.name}-$spacing'))
              .getBytes();
          expect(tracked.length, reference.length);
          expect(
              tracked.indexed.every((entry) => entry.$2 == reference[entry.$1]),
              isTrue,
              reason:
                  'tracking belongs after an advancing cluster, never between its glyphs');
        }
      });
    }

    test('right-to-left tracking follows each advancing glyph, after the marks that precede it', () async {
      final document = PdfDocument(compress: false);
      final font = PdfTtfFont(
          document, File('open-sans.ttf').readAsBytesSync().buffer.asByteData());
      final mark = font.font.charToGlyphIndexMap[0x301]!;
      final base = font.font.charToGlyphIndexMap[0x78]!;
      PdfPage(document, pageFormat: const PdfPageFormat(200, 100))
          .getGraphics()
          .drawGlyphs(font, 30, [mark, base, mark, base], 30, 50,
              charSpace: 2, leftToRight: false);
      final content = latin1.decode(await document.save());
      final cluster = PdfStream();
      font.putGlyphs(cluster, [mark, base]);
      final glyphs = latin1.decode(cluster.output());
      const step = '-66.66667';
      expect(content, contains('[$glyphs$step$glyphs$step]TJ'));
    });

    for (final fallback in [false, true]) {
      test(
          'a following advancing glyph moves once per preceding cluster, fallback $fallback',
          () async {
        int rightmostInk(image.Image drawing) => drawing
            .where((pixel) => pixel.r < 128)
            .map((pixel) => pixel.x)
            .reduce((left, right) => left > right ? left : right);
        final reference = rightmostInk(await raster(
            [0x78, 0x301, 0x301, 0x78], 0, 'following-$fallback-normal',
            fallback: fallback));
        for (final spacing in [-2.0, 2.0]) {
          final tracked = rightmostInk(await raster([
            0x78,
            0x301,
            0x301,
            0x78
          ], spacing, 'following-$fallback-$spacing', fallback: fallback));
          expect(tracked - reference, closeTo(spacing * (fallback ? 2 : 1), 1));
        }
      });
    }
  });
}
