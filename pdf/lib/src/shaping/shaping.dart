// This class uses Harfbuzz and bidi algorithm to shape text and return glyphs from a given font and text

import 'package:bidi/bidi.dart' as bidi;

import '../pdf/font/font_metrics.dart';
import '../pdf/font/ttf_parser.dart';
import '../pdf/obj/font.dart';
import '../pdf/obj/ttffont.dart';
import 'harfbuzz.dart';

// Important concepts when dealing with bidi and shaping:
//
// Logical order: order as bytes in memory (in RTL, the first character is displayed rightmost)
// Visual order: order as displayed on screen (in RTL, the first character is displayed leftmost)

extension type GlyphIndex(int index) {}

class ShapingResult {
  ShapingResult(this.text, this.font, this.glyphs, {required this.leftToRight});

  ShapingResult.empty(this.font, {required this.leftToRight})
      : text = [],
        glyphs = [];

  final PdfTtfFont font;
  final bool leftToRight;

  // text is in logical order
  List<int> text;

  // glyphs are in logical order
  final List<GlyphIndex> glyphs;

  PdfFontMetrics get metrics =>
      PdfFontMetrics.append(glyphs.map((g) => font.glyphIndexMetrics(g)));
  List<int> get glyphIndices => glyphs.map((g) => g.index).toList();

  void append(int char, GlyphIndex index) {
    text.add(char);
    glyphs.add(index);
  }

  @override
  String toString() =>
      'ShapingResult(leftToRight: $leftToRight, text: $text, font: ${font.fontName}), glyphs: $glyphs)';
}

class ShapingOutput {
  ShapingOutput(this.results, {required this.leftToRight});

  // In visual order
  final List<ShapingResult> results;
  bool leftToRight;

  PdfFontMetrics metrics({double letterSpacing = 0}) =>
      PdfFontMetrics.append(results.map((sr) => sr.metrics),
          letterSpacing: letterSpacing);

  List<int> get glyphIndices =>
      results.expand((result) => result.glyphIndices).toList();

  @override
  String toString() =>
      'ShapingOutput(leftToRight: $leftToRight, results: ${results})';
}

class LinesShapingOutput {
  LinesShapingOutput(this.lines);

  // In visual order
  List<ShapingOutput> lines;

  @override
  String toString() => 'LinesShapingOutput(lines: $lines})';
}

class Shaping {
  factory Shaping() => _instance;

  // Singleton stuff
  Shaping._();
  static final Shaping _instance = Shaping._();

  final Map<String, HarfbuzzFace> _faces = {};
  final HarfbuzzBinding _hb = HarfbuzzBinding();

  LinesShapingOutput shapeLines(
      String text, PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts,
      {required double maxWidth, required double letterSpacing}) {
    // First split text into lines
    final paragraphs = bidi.BidiString.fromLogical(text).paragraphs;
    if (paragraphs.isEmpty) {
      return LinesShapingOutput([]);
    }

    // Paragraphs are logically ordered
    final splitParagraphs = paragraphs
        .map((paragraph) => _shapeParagraph(
            paragraph, primaryFont, fallbackFonts,
            maxWidth: maxWidth, letterSpacing: letterSpacing))
        .toList();

    return LinesShapingOutput(
        splitParagraphs.expand((paragraph) => paragraph).toList());
  }

  (List<ShapingResult>, ShapingResult, double) _splitSingleShapingResult(
      ShapingResult source, double currentWidth,
      {required double maxWidth, required double letterSpacing}) {
    final output = <ShapingResult>[];
    var current =
        ShapingResult.empty(source.font, leftToRight: source.leftToRight);

    for (var i = 0; i < source.glyphs.length; i++) {
      final advance =
          source.font.glyphIndexMetrics(source.glyphs[i]).advanceWidth;
      final spacing = advance > 0 ? letterSpacing : 0.0;
      if (currentWidth + advance > maxWidth) {
        currentWidth = 0.0;
        output.add(current);
        current =
            ShapingResult.empty(source.font, leftToRight: source.leftToRight);
      }
      final c = i < source.text.length ? source.text[i] : ''.runes.first;
      current.append(c, source.glyphs[i]);
      currentWidth += advance + spacing;
    }

    return (output, current, currentWidth);
  }

  List<ShapingOutput> _shapeParagraph(
      bidi.Paragraph p, PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts,
      {required double maxWidth, required double letterSpacing}) {
    final text = String.fromCharCodes(p.text);

    final shapingOutput = shape(text, primaryFont, fallbackFonts);

    final lines = <ShapingOutput>[];
    final currentLine = <ShapingResult>[];
    var width = 0.0;
    // shapingOutput.results are in visual order => lines will be in visual order
    for (final shapingResult in shapingOutput.results) {
      final (newLines, current, updatedWidth) = _splitSingleShapingResult(
          shapingResult, width,
          maxWidth: maxWidth, letterSpacing: letterSpacing);

      if (newLines.isNotEmpty) {
        final newOutputs = newLines
            .map((line) => ShapingOutput([line], leftToRight: line.leftToRight))
            .toList();
        newOutputs.first.results.insertAll(0, currentLine);
        lines.addAll(newOutputs);
        currentLine.clear();
      }

      width = updatedWidth;
      currentLine.add(current);
    }
    if (currentLine.isNotEmpty) {
      lines.add(ShapingOutput(currentLine,
          leftToRight: currentLine.first.leftToRight));
    }

    return p.isLeftToRight ? lines : lines.reversed.toList();
  }

  // Input text and output shaping results are in logical order
  ShapingOutput shape(
      String text, PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts) {
    for (final font in [primaryFont, ...fallbackFonts]) {
      if (_faces.containsKey(font.fontName)) continue;
      _addFont(font);
    }

    if (text.isEmpty) {
      return ShapingOutput([], leftToRight: true);
    }

    final primaryFontSubFamily = _getFontSubFamily(primaryFont);
    final orderedFonts = <PdfTtfFont?>[
      primaryFont,
      primaryFont,
      ...fallbackFonts
          .where((f) => _getFontSubFamily(f) == primaryFontSubFamily),
      ...fallbackFonts
          .where((f) => _getFontSubFamily(f) != primaryFontSubFamily),
      null
    ];

    // Is there a font that supports all runes?
    // Skip first one because it's given twice in the ordered fonts
    final commonFont = orderedFonts.skip(1).firstWhere(
        (f) => text.runes.every((rune) => f?.isRuneSupported(rune) == true),
        orElse: () => null);

    final bidiSpans = BidiSpan.createBidiSpans(text);

    final runeAndFonts = <_RunesAndFont>[];
    for (final span in bidiSpans) {
      final spanRuneAndFonts = <_RunesAndFont>[];
      for (var rune in span.text.runes) {
        var font = commonFont ??
            orderedFonts.firstWhere((f) => f?.isRuneSupported(rune) != false);
        if (font != null) {
          orderedFonts[1] = font;
        }
        if (font == null) {
          rune = '?'.runes.first;
          font = primaryFont;
        }

        if (spanRuneAndFonts.isEmpty || font != spanRuneAndFonts.last.font) {
          spanRuneAndFonts
              .add(_RunesAndFont([rune], font, leftToRight: span.leftToRight));
        } else {
          spanRuneAndFonts.last.runes.add(rune);
        }
      }

      if (span.leftToRight) {
        runeAndFonts.addAll(spanRuneAndFonts);
      } else {
        runeAndFonts.addAll(spanRuneAndFonts.reversed);
      }
    }

    final textsAndFonts =
        runeAndFonts.map((raf) => raf.toTextAndFont()).toList();

    final output = <ShapingResult>[];

    for (final textAndFont in textsAndFonts) {
      final face = Shaping._instance._faces[textAndFont.font.fontName];
      if (face == null) {
        throw Exception('Font is missing');
      }

      final faceFont = _hb.fontCreate(face);
      final buffer = _hb.bufferCreate();

      _hb.bufferAddString(buffer, textAndFont.text);
      _hb.bufferGuessSegmentProperties(buffer);
      _hb.bufferSetDirection(
          buffer,
          textAndFont.leftToRight
              ? HarfBuzzDirection.leftToRight
              : HarfBuzzDirection.rightToLeft);

      _hb.shape(faceFont, buffer);

      output.add(ShapingResult(
        textAndFont.text.runes.toList(),
        textAndFont.font,
        _hb
            .getGlyphInfos(buffer)
            .map((info) => GlyphIndex(info.codepoint))
            .toList(),
        leftToRight: textAndFont.leftToRight,
      ));

      _hb.bufferDestroy(buffer);
      _hb.fontDestroy(faceFont);
    }

    return ShapingOutput(output, leftToRight: output.first.leftToRight);
  }

  void dispose() {
    for (final face in _faces.values) {
      _hb.faceDestroy(face);
    }
    _faces.clear();
  }

  void _addFont(PdfTtfFont font) {
    _faces[font.fontName] = _hb.faceFromData(font.font.bytes, 0);
  }
}

String _getFontSubFamily(PdfFont font) {
  if (font is PdfTtfFont) {
    return font.font
            .getNameID(TtfParserName.fontSubfamily)
            ?.toLowerCase()
            .trim() ??
        'regular';
  }
  final name = font.fontName;
  if (name.endsWith('-Bold')) {
    return 'bold';
  }
  return 'regular';
}

class _RunesAndFont {
  _RunesAndFont(this.runes, this.font, {required this.leftToRight});

  final List<int> runes;
  final PdfTtfFont font;
  final bool leftToRight;

  _TextAndFont toTextAndFont() =>
      _TextAndFont(String.fromCharCodes(runes), font, leftToRight: leftToRight);

  @override
  String toString() =>
      'RuneAndFont(font: ${font.fontName}, LTR: $leftToRight, runes: $runes)';
}

class _TextAndFont {
  _TextAndFont(this.text, this.font, {required this.leftToRight});

  String text;
  final PdfTtfFont font;
  final bool leftToRight;

  void addRune(int rune) {
    text += String.fromCharCode(rune);
  }

  @override
  String toString() =>
      'TextAndFont(font: ${font.fontName}, LTR: $leftToRight, text: ` $text ` )';
}

class BidiSpan {
  const BidiSpan(this.text, int level) : leftToRight = level % 2 == 0;

  final String text;
  final bool leftToRight;

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  @override
  String toString() => 'BidiSpan(text: ` $text `  , leftToRight: $leftToRight)';

  static List<BidiSpan> createBidiSpans(String text) {
    final paragraphs = bidi.BidiString.fromLogical(text).paragraphs;

    final spans = <BidiSpan>[];

    for (final paragraph in paragraphs) {
      final paragraphText = String.fromCharCodes(paragraph.text);
      final paragraphSpans = <BidiSpan>[];
      final levels = paragraph.embeddingLevels;
      if (levels.isEmpty) {
        continue;
      }

      var start = 0;
      var level = levels.first;

      for (var i = 1; i < levels.length; i++) {
        final curLevel = levels[i];
        if (level == curLevel) {
          continue;
        }

        paragraphSpans.add(BidiSpan(paragraphText.substring(start, i), level));
        start = i;
        level = curLevel;
      }

      paragraphSpans
          .add(BidiSpan(paragraphText.substring(start, levels.length), level));

      if (paragraph.isLeftToRight) {
        spans.addAll(paragraphSpans);
      } else {
        spans.addAll(paragraphSpans.reversed);
      }
    }

    return spans.toList();
  }
}
