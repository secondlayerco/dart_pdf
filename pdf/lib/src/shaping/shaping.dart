// This class uses Harfbuzz and bidi algorithm to shape text and return glyphs from a given font and text

import 'package:bidi/bidi.dart' as bidi;
import 'package:characters/characters.dart';

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
      {required this.leftToRight, List<String?>? sources})
      : sources = sources ?? List.filled(glyphsLogical.length, null, growable: true);

  ShapingResult.empty(this.font, {required this.leftToRight})
      : glyphsLogical = ListLogical.empty(), sources = [];

  ShapingResult clone() =>
      ShapingResult.fromLogicalOrder(font, ListLogical([...glyphsLogical]),
          leftToRight: leftToRight, sources: [...sources]);

  final List<String?> sources;
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
    sources.addAll(other.sources);
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

  ShapingOutput shape2(List<int> text, List<int> embeddingLevels,
      PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts,
      {required bool leftToRight}) =>
      _shapeSpans(
          BidiSpan.createBidiSpans2(text, embeddingLevels,
              leftToRight: leftToRight),
          primaryFont,
          fallbackFonts);

  ShapingOutput shape(
          String text, PdfTtfFont primaryFont, List<PdfTtfFont> fallbackFonts) =>
      _shapeSpans(BidiSpan.createBidiSpans(text), primaryFont, fallbackFonts);

  static final _defaultIgnorable =
      RegExp(r'^\p{Default_Ignorable_Code_Point}$', unicode: true);

  ShapingOutput _shapeSpans(List<BidiSpan> spans, PdfTtfFont primaryFont,
      List<PdfTtfFont> fallbackFonts) {
    if (spans.isEmpty) {
      return ShapingOutput.empty();
    }

    final primaryFontSubFamily = _getFontSubFamily(primaryFont);
    final orderedFonts = [
      primaryFont,
      ...fallbackFonts.where((f) => _getFontSubFamily(f) == primaryFontSubFamily),
      ...fallbackFonts.where((f) => _getFontSubFamily(f) != primaryFontSubFamily),
    ];

    final output = ListVisual<ShapingResult>.empty();
    for (final span in spans) {
      final codepoints = <int>[];
      List<int>? originalCodepoints;
      final runs = <_FontRun>[];
      void append(Iterable<int> runes, PdfTtfFont font) {
        if (runs.isEmpty || runs.last.font != font) {
          runs.add(_FontRun(font, codepoints.length));
        }
        codepoints.addAll(runes);
        runs.last.end = codepoints.length;
      }

      for (final cluster in span.text.characters) {
        final runes = cluster.runes;
        if (runes.every(primaryFont.isRuneSupported)) {
          append(runes, primaryFont);
          continue;
        }
        final requiredRunes = runes
            .where((rune) =>
                !_defaultIgnorable.hasMatch(String.fromCharCode(rune)))
            .toSet();
        final font = orderedFonts
            .where((font) => requiredRunes.every(font.isRuneSupported))
            .firstOrNull;
        if (font != null) {
          append(runes, font);
          continue;
        }
        var activeFont = primaryFont;
        for (final rune in runes) {
          if (!requiredRunes.contains(rune)) {
            append([rune], activeFont);
            continue;
          }
          final font = orderedFonts
              .where((font) => font.isRuneSupported(rune))
              .firstOrNull;
          if (font == null) {
            originalCodepoints ??= span.text.runes.toList();
          }
          activeFont = font ?? primaryFont;
          final renderedRune = font == null ? 0x3f : rune;
          append([renderedRune], activeFont);
        }
      }
      if (runs.isEmpty) {
        continue;
      }
      final text = HarfbuzzText(codepoints);
      try {
        for (final run in span.leftToRight ? runs : runs.reversed) {
          final face = _faces.putIfAbsent(run.font.fontName,
              () => _hb.faceFromData(run.font.font.bytes, 0));
          final faceFont = _hb.fontCreate(face);
          final buffer = _hb.bufferCreate();
          try {
            _hb.bufferAddText(buffer, text, run.start, run.end - run.start);
            _hb.bufferGuessSegmentProperties(buffer);
            _hb.bufferSetDirection(
                buffer,
                span.leftToRight
                    ? HarfBuzzDirection.leftToRight
                    : HarfBuzzDirection.rightToLeft);
            _hb.shape(faceFont, buffer);
            final glyphs = _hb.getGlyphInfos(buffer);
            output.add(ShapingResult.fromLogicalOrder(
                run.font,
                ListLogical(glyphs
                    .map((info) => GlyphIndex(info.codepoint))
                    .toList()),
                leftToRight: span.leftToRight,
                sources: _glyphSources(glyphs, originalCodepoints ?? codepoints, run.end, span.leftToRight)));
          } finally {
            _hb.bufferDestroy(buffer);
            _hb.fontDestroy(faceFont);
          }
        }
      } finally {
        text.release();
      }
    }

    return output.isEmpty
        ? ShapingOutput.empty()
        : ShapingOutput.fromVisualOrder(output,
            leftToRight: output.first.leftToRight);
  }

  static List<String?> _glyphSources(List<HarfbuzzGlyphInfo> glyphs,
      List<int> codepoints, int runEnd, bool leftToRight) {
    final sources = List<String?>.filled(glyphs.length, null, growable: true);
    // Only a single-glyph cluster has an unambiguous per-glyph source.
    var end = runEnd;
    for (var n = 0; n < glyphs.length; n++) {
      final i = leftToRight ? glyphs.length - 1 - n : n;
      final start = glyphs[i].cluster;
      final next = leftToRight ? i - 1 : i + 1;
      if (start < end && (next < 0 || next >= glyphs.length || glyphs[next].cluster != start)) {
        sources[i] = String.fromCharCodes(codepoints, start, end);
      }
      end = start;
    }
    return sources;
  }

  void dispose() {
    for (final face in _faces.values) {
      _hb.faceDestroy(face);
    }
    _faces.clear();
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

class _FontRun {
  _FontRun(this.font, this.start) : end = start;

  final PdfTtfFont font;
  final int start;
  int end;
}

class BidiSpan {
  const BidiSpan(this.text, int level) : leftToRight = level % 2 == 0;

  final String text;
  final bool leftToRight;

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  @override
  String toString() => 'BidiSpan(text: ` $text `  , leftToRight: $leftToRight)';

  static final _unpairedSurrogate = RegExp(r'[\uD800-\uDFFF]', unicode: true);

  static List<BidiSpan> createBidiSpans2(List<int> text, List<int> levels,
      {required bool leftToRight}) {
    if (text.isEmpty) return [];
    final spans = <BidiSpan>[];
    var start = 0;
    var level = levels.firstOrNull ?? (leftToRight ? 0 : 1);
    void finish(int end) {
      final source = String.fromCharCodes(text, start, end);
      spans.add(BidiSpan(source.replaceAll(_unpairedSurrogate, '\ufffd'), level));
    }

    // Each level indexes its input element: a UTF-16 unit from bidi, or a scalar from a rune list.
    for (var i = 1; i < text.length && i < levels.length; i++) {
      final unit = text[i];
      if (unit >= 0xdc00 && unit <= 0xdfff && text[i - 1] >= 0xd800 && text[i - 1] <= 0xdbff) {
        continue;
      }
      if (levels[i] != level) {
        finish(i);
        start = i;
        level = levels[i];
      }
    }
    finish(text.length);
    return leftToRight ? spans : spans.reversed.toList();
  }

  static List<BidiSpan> createBidiSpans(String text) =>
      bidi.BidiString.fromLogical(text, skipReshaping: true)
          .paragraphs
          .expand((p) => createBidiSpans2(p.text, p.embeddingLevels,
              leftToRight: p.isLeftToRight))
          .toList();
}
