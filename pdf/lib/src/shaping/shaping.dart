// This class uses Harfbuzz and bidi algorithm to shape text and return glyphs from a given font and text

import 'package:bidi/bidi.dart' as bidi;

import '../pdf/font/font_metrics.dart';
import '../pdf/font/ttf_parser.dart';
import '../pdf/obj/font.dart';
import '../pdf/obj/ttffont.dart';
import 'harfbuzz.dart';
import 'icu.dart';

// Important concepts when dealing with bidi and shaping:
//
// Logical order: order as bytes in memory (in RTL, the first character is displayed rightmost)
// Visual order: order as displayed on screen (in RTL, the first character is displayed leftmost)

extension type GlyphIndex(int index) {}

extension type IterableLogical<T>(Iterable<T> it) implements Iterable<T> {
  List<T> toListLogical() => ListLogical(it.toList());
}

extension type ListLogical<T>(List<T> list)
    implements IterableLogical<T>, List<T> {
  ListLogical.single(T element) : list = [element];
  ListLogical.empty() : list = [];

  IterableLogical<E> map<E>(E Function(T e) toElement) =>
      IterableLogical(list.map(toElement));

  IterableVisual<T> visual({bool leftToRight = true}) =>
      leftToRight ? IterableVisual(list) : IterableVisual(list.reversed);
}

extension type IterableVisual<T>(Iterable<T> it) implements Iterable<T> {
  List<T> toListVisual() => it.toList();
}

extension type ListVisual<T>(List<T> list)
    implements IterableVisual<T>, List<T> {
  ListVisual.fromLogical(ListLogical<T> logical, {required bool leftToRight})
      : list = leftToRight
            ? ListVisual(logical.list)
            : ListVisual(logical.list.reversed.toList());

  ListVisual.single(T element) : list = [element];
  ListVisual.empty() : list = [];

  IterableVisual<E> map<E>(E Function(T e) toElement) =>
      IterableVisual(list.map(toElement));

  IterableLogical<T> logical({bool leftToRight = true}) =>
      leftToRight ? IterableLogical(list) : IterableLogical(list.reversed);
}

class ShapingResult {
  ShapingResult.fromLogicalOrder(this.font, this.glyphsLogical,
      {required this.leftToRight});

  ShapingResult.empty(this.font, {required this.leftToRight})
      : glyphsLogical = ListLogical.empty();

  ShapingResult clone() =>
      ShapingResult.fromLogicalOrder(font, ListLogical([...glyphsLogical]),
          leftToRight: leftToRight);

  final PdfTtfFont font;
  final bool leftToRight;

  final ListLogical<GlyphIndex> glyphsLogical;

  bool compatible(ShapingResult other) =>
      leftToRight == other.leftToRight && font == other.font;

  PdfFontMetrics metrics({required double letterSpacing}) =>
      PdfFontMetrics.append(glyphsLogical.map(
          (g) => font.glyphIndexMetricsWithLetterSpacing(g, letterSpacing)));

  List<int> get glyphIndicesLogical =>
      glyphsLogical.map((g) => g.index).toList();

  void append(ShapingResult other) {
    assert(compatible(other), 'It does not make sense to append incompatible results');
    glyphsLogical.addAll(other.glyphsLogical);
  }

  @override
  String toString() =>
      'ShapingResult(leftToRight: $leftToRight, font: ${font.fontName}), glyphs: $glyphsLogical)';
}

class ShapingOutput {
  ShapingOutput.empty()
      : resultsVisual = ListVisual.empty(),
        leftToRight = true;

  ShapingOutput.fromVisualOrder(this.resultsVisual,
      {required this.leftToRight});

  factory ShapingOutput.fromShapingOutputs(
      ListLogical<ShapingOutput> outputsInLogicalOrder) {
    final leftToRight = outputsInLogicalOrder.firstOrNull?.leftToRight ?? true;
    final compacted = _compact(outputsInLogicalOrder, leftToRight: leftToRight);
    return ShapingOutput.fromVisualOrder(compacted, leftToRight: leftToRight);
  }

  static ListVisual<ShapingResult> _compact(ListLogical<ShapingOutput> items,
      {required bool leftToRight}) {
    final flattenedResults = ListVisual(items
        .visual(leftToRight: leftToRight)
        .expand((output) => output.resultsVisual)
        .toList());

    if (!leftToRight) {
      // We need to reverse the spans of consecutive LTR elements
      final reorderedResults = ListVisual<ShapingResult>([]);
      final ltrSpan = ListVisual<ShapingResult>([]);
      for (final result in flattenedResults) {
        if (!result.leftToRight) {
          reorderedResults.addAll(ltrSpan.reversed);
          ltrSpan.clear();
          reorderedResults.add(result);
          continue;
        }
        ltrSpan.add(result);
      }
      reorderedResults.addAll(ltrSpan.reversed);
      flattenedResults
        ..clear()
        ..addAll(reorderedResults);
    }

    final compacted = ListVisual<ShapingResult>.empty();
    for (final o in flattenedResults) {
      if (compacted.isNotEmpty && o.compatible(compacted.last)) {
        compacted.last.append(o);
      } else {
        compacted.add(o.clone());
      }
    }

    return compacted;
  }

  final ListVisual<ShapingResult> resultsVisual;
  bool leftToRight;

  bool get isEmpty => resultsVisual.isEmpty;
  bool get isNotEmpty => !isEmpty;

  IterableLogical<ShapingResult> get resultsLogical =>
      resultsVisual.logical(leftToRight: leftToRight);

  PdfFontMetrics metrics({required double letterSpacing}) =>
      PdfFontMetrics.append(
          resultsVisual.map((sr) => sr.metrics(letterSpacing: letterSpacing)),
          // We already add letterSpacing when calling metrics, we don't need to add it again.
          letterSpacing: 0.0);

  List<int> get glyphIndicesVisual =>
      resultsVisual.expand((result) => result.glyphIndicesLogical).toList();

  @override
  String toString() =>
      'ShapingOutput(leftToRight: $leftToRight, resultsVisual: $resultsVisual)';
}

class LinesShapingOutput {
  LinesShapingOutput.fromVisualOrder(this.linesVisual,
      {required this.startingLocation, required this.endingLocation});

  bool get isEmpty => linesVisual.isEmpty;

  final double startingLocation;
  final double endingLocation;

  final ListVisual<ShapingOutput> linesVisual;

  @override
  String toString() =>
      'LinesShapingOutput(${linesVisual.length} lines:\n${linesVisual.join('\n')}\n)';
}

class Shaping {
  factory Shaping() => _instance;

  // Singleton stuff
  Shaping._();
  static final Shaping _instance = Shaping._();

  final Map<String, HarfbuzzFace> _faces = {};
  final HarfbuzzBinding _hb = HarfbuzzBinding();

  LinesShapingOutput shapeLinesWithBreaks(
      String text, PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts,
      {required double startingLocation,
      required double maxWidth,
      required double letterSpacing}) {
    final paragraphs =
        bidi.BidiString.fromLogical(text, skipReshaping: true).paragraphs;
    final paragraphLines = paragraphs.map((paragraph) {
      return _shapeParagraphWithBreaks(paragraph, primaryFont, fallbackFonts,
          startingLocation: startingLocation,
          maxWidth: maxWidth,
          letterSpacing: letterSpacing);
    }).toList();
    final allLines =
        paragraphLines.expand((p) => p.linesVisual.toList()).toList();
    return LinesShapingOutput.fromVisualOrder(ListVisual(allLines),
        startingLocation:
            paragraphLines.firstOrNull?.startingLocation ?? startingLocation,
        endingLocation:
            paragraphLines.lastOrNull?.endingLocation ?? startingLocation);
  }

  LinesShapingOutput _shapeParagraphWithBreaks(bidi.Paragraph paragraph,
      PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts,
      {required double startingLocation,
      required double maxWidth,
      required double letterSpacing}) {
    final text = String.fromCharCodes(paragraph.text);
    final libeBreakOffsets = IcuBinding.getIcuBreakOffsets(text, IcuBreakType.line);

    if (libeBreakOffsets.isEmpty) {
      final shapingOutput = shape(text, primaryFont, fallbackFonts);
      return LinesShapingOutput.fromVisualOrder(
        ListVisual.single(shapingOutput),
        startingLocation: startingLocation,
        endingLocation:
            shapingOutput.metrics(letterSpacing: letterSpacing).width,
      );
    }

    if (libeBreakOffsets.first != 0) {
      libeBreakOffsets.insert(0, 0);
    }

    final lines = ListVisual<ShapingOutput>.empty();
    final currentLine = ListLogical<ShapingOutput>.empty();
    var currentWidth = startingLocation;
    for (var i = 0; i < libeBreakOffsets.length - 1; i++) {
      final subString =
          paragraph.text.sublist(libeBreakOffsets[i], libeBreakOffsets[i + 1]);
      final embeddingLevels =
          paragraph.embeddingLevels.sublist(libeBreakOffsets[i], libeBreakOffsets[i + 1]);
      final shapingOutput = shape2(
          subString, embeddingLevels, primaryFont, fallbackFonts,
          leftToRight: paragraph.isLeftToRight);
      final advanceWidth =
          shapingOutput.metrics(letterSpacing: letterSpacing).advanceWidth;

      if (currentWidth + advanceWidth > maxWidth) {
        // New line
        lines.add(ShapingOutput.fromShapingOutputs(currentLine));
        currentLine.clear();
        currentWidth = 0.0;
      }
      currentLine.add(shapingOutput);
      currentWidth += advanceWidth;
    }

    if (currentLine.isNotEmpty) {
      lines.add(ShapingOutput.fromShapingOutputs(currentLine));
    }

    return LinesShapingOutput.fromVisualOrder(lines,
        startingLocation: startingLocation, endingLocation: currentWidth);
  }

  // Input text and output shaping results are in logical order
  ShapingOutput shape2(List<int> text, List<int> embeddingLevels,
      PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts,
      {required bool leftToRight}) {
    for (final font in [primaryFont, ...fallbackFonts]) {
      if (_faces.containsKey(font.fontName)) continue;
      _addFont(font);
    }

    if (text.isEmpty) {
      return ShapingOutput.empty();
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
    ].map((font) => font).toList();

    // Is there a font that supports all runes?
    // Skip first one because it's given twice in the ordered fonts
    final commonFont = orderedFonts.skip(1).firstWhere(
        (f) => text.every((rune) => f?.isRuneSupported(rune) == true),
        orElse: () => null);

    final bidiSpans = BidiSpan.createBidiSpans2(text, embeddingLevels,
        leftToRight: leftToRight);

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

    final output = ListVisual<ShapingResult>.empty();

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

      output.add(ShapingResult.fromLogicalOrder(
        textAndFont.font,
        ListLogical(
          _hb
              .getGlyphInfos(buffer)
              .map((info) => GlyphIndex(info.codepoint))
              .toList(),
        ),
        leftToRight: textAndFont.leftToRight,
      ));

      _hb.bufferDestroy(buffer);
      _hb.fontDestroy(faceFont);
    }

    return ShapingOutput.fromVisualOrder(output,
        leftToRight: output.first.leftToRight);
  }

  // Input text and output shaping results are in logical order
  ShapingOutput shape(
      String text, PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts) {
    for (final font in [primaryFont, ...fallbackFonts]) {
      if (_faces.containsKey(font.fontName)) continue;
      _addFont(font);
    }

    if (text.isEmpty) {
      return ShapingOutput.empty();
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
    ].map((font) => font).toList();

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

    final output = ListVisual<ShapingResult>.empty();

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

      output.add(ShapingResult.fromLogicalOrder(
        textAndFont.font,
        ListLogical(
          _hb
              .getGlyphInfos(buffer)
              .map((info) => GlyphIndex(info.codepoint))
              .toList(),
        ),
        leftToRight: textAndFont.leftToRight,
      ));

      _hb.bufferDestroy(buffer);
      _hb.fontDestroy(faceFont);
    }

    return ShapingOutput.fromVisualOrder(output,
        leftToRight: output.first.leftToRight);
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

  static List<BidiSpan> createBidiSpans2(List<int> text, List<int> levels,
      {required bool leftToRight}) {
    if (levels.isEmpty) {
      return [];
    }

    final spans = <BidiSpan>[];

    // for (final paragraph in paragraphs) {
    final paragraphText = String.fromCharCodes(text);
    final paragraphSpans = <BidiSpan>[];
    // final levels = paragraph.embeddingLevels;
    // if (levels.isEmpty) {
    //   continue;
    // }

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

    if (leftToRight) {
      spans.addAll(paragraphSpans);
    } else {
      spans.addAll(paragraphSpans.reversed);
    }
    // }

    return spans.toList();
  }

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
