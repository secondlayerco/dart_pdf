import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/src/svg/brush.dart';
import 'package:pdf/src/svg/painter.dart';
import 'package:pdf/src/svg/parser.dart';
import 'package:pdf/src/svg/text.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'utils.dart';

void main() {
  final regular = loadFont('open-sans.ttf');
  final bold = loadFont('open-sans-bold.ttf');
  final fallback = loadFont('noto-sans.ttf');

  SvgText parseText(String text, String attributes, {double size = 20}) {
    final parser = SvgParser(
        xml: XmlDocument.parse(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 100">'
            '<text font-size="$size" x="200" y="30" text-anchor="end" $attributes>$text</text></svg>'));
    final document = PdfDocument();
    final painter = SvgPainter(
        parser, null, document, parser.viewBox, {}, regular, [fallback]);
    return SvgText.fromXml(parser.root.findAllElements('text').single, painter,
        SvgBrush.defaultContext);
  }

  group('SVG text tracking ::', () {
    test(
        'tracking preserves combining and directional shaping while moving the anchor',
        () {
      for (final text in ['Cafe\u0301 office', '\u202Babc 123\u202C']) {
        final plain = parseText(text, '');
        final tracked = parseText(text, 'letter-spacing="2"');
        expect(tracked.shapingOutput.glyphIndicesVisual,
            plain.shapingOutput.glyphIndicesVisual);
        expect(
            tracked.shapingOutput.resultsVisual
                .map((result) => result.leftToRight),
            plain.shapingOutput.resultsVisual
                .map((result) => result.leftToRight));
        expect(tracked.metrics.advanceWidth,
            greaterThan(plain.metrics.advanceWidth));
        expect(tracked.x, lessThan(plain.x!));
        expect(tracked.x! + tracked.metrics.width, closeTo(200, 0.001));
      }
    });

    test('a letter-spacing value that is not a length keeps the text, untracked', () {
      final plain = parseText('abc', '');
      for (final value in ['initial', 'unset', 'calc(1px + 2px)', '']) {
        final kept = parseText('abc', 'letter-spacing="$value"');
        expect(kept.metrics.advanceWidth, plain.metrics.advanceWidth, reason: value);
      }
    });

    test('text without letter-spacing sets no character spacing in the PDF', () async {
      final document = Document(compress: false)
        ..addPage(Page(
            pageFormat: const PdfPageFormat(200, 100),
            build: (_) => SvgImage(
                svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><text x="10" y="50" font-size="20">abc</text></svg>',
                defaultFont: regular)));
      expect(latin1.decode(await document.save()), isNot(contains(' Tc')));
    });

    test('fallback font runs retain the measured tracking advance', () {
      final plain = parseText('℠ƀ℠', '');
      final tracked = parseText('℠ƀ℠', 'letter-spacing="2"');
      expect(tracked.shapingOutput.resultsVisual.length, 3);
      expect(tracked.metrics.advanceWidth - plain.metrics.advanceWidth,
          closeTo(6, 0.001));
    });

    test('negative tracking tightens text and zero size stays finite', () {
      final normal = parseText('Label', '');
      final tight = parseText('Label', 'letter-spacing="-0.5px"');
      expect(tight.metrics.advanceWidth, lessThan(normal.metrics.advanceWidth));
      final hidden = parseText('Label', 'letter-spacing="2"', size: 0);
      expect(hidden.metrics.advanceWidth, 0);
      expect(hidden.x, 200);
    });

    test('inherited tracking survives mixed font runs and normal resets it',
        () async {
      final document = Document(compress: false)
        ..addPage(Page(
            build: (context) => SvgImage(
                  svg:
                      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 100">'
                      '<g font-size="20" letter-spacing="0.1em">'
                      '<text x="10" y="30">Same <tspan font-weight="bold">saved</tspan>'
                      '<tspan> document</tspan><tspan letter-spacing="normal"> reset</tspan></text>'
                      '</g></svg>',
                  defaultFont: regular,
                  customFontLookup: (family, style, weight) =>
                      weight == 'bold' ? bold : regular,
                )));
      final output = latin1.decode(await document.save());
      expect(RegExp(r'2 Tc').allMatches(output).length, 3);
      expect(output, contains('0 Tc'));
    });
  });
}
