import 'dart:convert';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/src/shaping/shaping.dart';
import 'package:test/test.dart';

void main() {
  late PdfDocument document;
  PdfTtfFont load(String file) =>
      PdfTtfFont(document, File(file).readAsBytesSync().buffer.asByteData());
  setUp(() => document = PdfDocument(compress: false));

  test('mixed Japanese and Latin preserve the primary face on either side', () {
    final primary = load('open-sans.ttf');
    final japanese = load('genyomintw.ttf');
    const text = 'WW日本語WW';
    final runes = text.runes.toList();

    expect(primary.isRuneSupported('W'.runes.single), isTrue);
    expect(primary.isRuneSupported('日'.runes.single), isFalse);
    expect(runes.every(japanese.isRuneSupported), isTrue);

    final shaper = Shaping();
    for (final output in [
      shaper.shape(text, primary, [japanese]),
      shaper.shape2(runes, List.filled(runes.length, 0), primary, [japanese],
          leftToRight: true),
    ]) {
      expect(
        output.resultsVisual.map((result) => result.font),
        [primary, japanese, primary],
      );
      expect(
        output.resultsVisual.map((result) => result.glyphsLogical.length),
        [2, 3, 2],
      );
    }
  });

  test('combining sequence uses one fallback face and keeps neighbouring Latin',
      () {
    final primary = load('open-sans.ttf');
    final fallback = load('noto-sans.ttf');
    expect(primary.isRuneSupported(0x0302), isFalse);
    expect(fallback.isRuneSupported(0x0302), isTrue);

    final output = Shaping().shape('WX̂W', primary, [fallback]);
    expect(output.resultsVisual.map((result) => result.font),
        [primary, fallback, primary]);
    expect(output.resultsVisual[1].glyphsLogical, hasLength(2));
  });

  test('bidi levels retain source length across Arabic and combining ligatures',
      () {
    expect(BidiSpan.createBidiSpans('AسلامZ').map((s) => s.text),
        ['A', 'سلام', 'Z']);
    expect(BidiSpan.createBidiSpans('بلا').single.text, 'بلا');
    final primary = load('open-sans.ttf');
    final output = Shaping().shape('é e\u0301', primary, []);
    expect(output.resultsVisual.single.sources.join(), 'é e\u0301');
    expect(output.glyphIndicesVisual.first, output.glyphIndicesVisual.last);
  });

  test(
      'both UTF-16 and scalar input preserve supplementary characters and trailing text',
      () {
    final primary = load('open-sans.ttf');
    final fallback = load('genyomintw.ttf');
    for (final text in ['X🄀Y', 'WW🄀']) {
      final shaper = Shaping();
      final outputs = [
        shaper.shape(text, primary, [fallback]),
        for (final units in [text.codeUnits, text.runes.toList()])
          shaper.shape2(
              units, List.filled(units.length, 0), primary, [fallback],
              leftToRight: true),
      ];
      for (final output in outputs) {
        expect(output.resultsVisual.expand((r) => r.sources).join(), text);
        expect(output.glyphIndicesVisual, hasLength(text.runes.length));
      }
    }
  });

  test('unpaired surrogates map to the Unicode replacement character',
      () async {
    final primary = load('open-sans.ttf');
    final page = PdfPage(document).getGraphics();
    for (final text in ['X\ud800Y', 'X\udfffY']) {
      final result = Shaping().shape(text, primary, []).resultsVisual.single;
      expect(result.sources.join(), 'X\ufffdY');
      page.drawGlyphs(primary, 16, result.glyphIndicesLogical, 20, 30,
          sources: result.sources);
    }
    final pdf = latin1.decode(await document.save());
    expect(pdf, matches(RegExp(r'<[0-9A-F]{4}> <FFFD>')));
    expect(pdf, isNot(matches(RegExp(r'<[0-9A-F]{4}> <D[89A-F][0-9A-F]{2}>'))));
  });

  test('a face covering both scripts remains a single shaped run', () {
    final primary = load('genyomintw.ttf');
    final fallback = load('open-sans.ttf');

    final output = Shaping().shape('WW日本語WW', primary, [fallback]);
    expect(output.resultsVisual.single.font, primary);
    expect(output.resultsVisual.single.glyphsLogical, hasLength(7));
  });

  test('Arabic letters retain their contextual forms across face boundaries',
      () {
    final primary = load('test/fixtures/JoiningPrimary.ttf');
    final fallback = load('test/fixtures/JoiningFallback.ttf');
    final shaper = Shaping();
    final primaryForms = shaper.shape('ببب', primary, []).glyphIndicesVisual;
    final fallbackForms = shaper.shape('بتب', fallback, []).glyphIndicesVisual;
    expect(primaryForms.toSet(), hasLength(3));
    final joined = shaper.shape('بتب', primary, [fallback]);
    expect(
        joined.resultsVisual.map((r) => r.font), [primary, fallback, primary]);
    expect(joined.glyphIndicesVisual,
        [primaryForms.first, fallbackForms[1], primaryForms.last]);
  });

  test('backwards spans place fallback runs in visual order', () {
    final primary = load('open-sans.ttf');
    final fallback = load('genyomintw.ttf');
    final runes = 'A日本Z'.runes.toList();

    final output = Shaping().shape2(
        runes, List.filled(runes.length, 1), primary, [fallback],
        leftToRight: false);
    expect(output.resultsVisual.map((result) => result.font),
        [primary, fallback, primary]);
    expect(output.resultsVisual.first.glyphIndicesLogical,
        [primary.font.charToGlyphIndexMap[0x5a]]);
    expect(output.resultsVisual.last.glyphIndicesLogical,
        [primary.font.charToGlyphIndexMap[0x41]]);
  });

  test('an unsupported mark does not turn its joiner into punctuation', () {
    final primary = load('open-sans.ttf');
    const codepoints = [0x58, 0x200d, 0x1ab0];
    expect(primary.isRuneSupported(0x200d), isFalse);
    expect(primary.isRuneSupported(0x1ab0), isFalse);

    final output = Shaping().shape2(
        codepoints, List.filled(codepoints.length, 0), primary, [],
        leftToRight: true);
    final question = primary.font.charToGlyphIndexMap[0x3f];
    expect(output.glyphIndicesVisual.where((index) => index == question),
        hasLength(1));
  });
}
