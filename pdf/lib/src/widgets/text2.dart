import 'dart:math';
import 'package:bidi/bidi.dart' as bidi;

import '../../pdf.dart';
import '../pdf/font/font_metrics.dart';
import '../shaping/shaping.dart';

import 'geometry.dart';
import 'text.dart';
import 'text_style.dart';
import 'widget.dart';

typedef ShapedLine = List<ShapingResult>;

class Text2 extends Widget {
  Text2(
    this.text, {
    this.style,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.tightBounds = false,
    this.textScaleFactor = 1.0,
    this.overflow,
  });

  String text;
  TextStyle? style;
  TextAlign? textAlign;
  TextDirection? textDirection;
  bool? softWrap;
  bool tightBounds;
  double textScaleFactor;
  TextOverflow? overflow;

  List<ShapedLine> shapedLines = [];

  @override
  void layout(Context context, BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    box = PdfRect(0, 0, 200, 100);

    final primaryFont = style!.font!.getFont(context) as PdfTtfFont;
    final fallbackFonts = style!.fontFallback
        .map((font) => font.getFont(context))
        .cast<PdfTtfFont>()
        .toList();

    final paragraphs = bidi.BidiString.fromLogical(text).paragraphs;
    if (paragraphs.isEmpty) {
      box = PdfRect(0, 0, 0, 0);
      return;
    }

    final isLeftToRight = paragraphs.first.embeddingLevel % 2 == 0;
    if(!isLeftToRight) {
      // We want to paragraphs in visual order, so invert if not left-to-right
      paragraphs.setRange(0, paragraphs.length, paragraphs.reversed);
    }

    final constraintWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth();
    final fontSize = style!.fontSize ?? 1.0;

    shapedLines.clear();
    for (final p in paragraphs) {
      // Paragraphs are in logical order
      final lineCandidate = Shaping()
          .shape(String.fromCharCodes(p.text), primaryFont, fallbackFonts);
      shapedLines
          .addAll(_createLines(lineCandidate, fontSize, constraintWidth));
    }

    shapedLines.reversed.toList();

    _setBox();
  }

  List<ShapedLine> _createLines(
      ShapedLine lineCandidate, double fontSize, double constraintWidth) {
    final wholeLength = lineCandidate.fold(
        0.0, (sum, shaping) => sum + shaping.metrics.advanceWidth);
    if (wholeLength * fontSize <= constraintWidth) {
      return [lineCandidate];
    }

    final singleShapingResults = lineCandidate
        .expand((c) => c.glyphs.map((g) => ShapingResult('', c.font, [g])))
        .toList();

    final output = <ShapedLine>[];
    var width = 0.0;
    final currentLine = <ShapingResult>[];
    for (final single in singleShapingResults) {
      final advanceWidth = single.metrics.advanceWidth * fontSize;
      if (width + advanceWidth > constraintWidth) {
        output.add([...currentLine]);
        currentLine.clear();
        width = 0.0;
      }
      currentLine.add(single);
      width += advanceWidth;
    }

    if (currentLine.isNotEmpty) {
      output.add([...currentLine]);
    }

    return output;
  }

  @override
  void paint(Context context) {
    super.paint(context);

    final fontSize = style!.fontSize ?? 1.0;
    var y = box!.y;

    for (final line in shapedLines.reversed) {
      var x = box!.x;
      var height = 0.0;
      for (final shaped in line) {
        final metrics = shaped.metrics * fontSize;
        final glyphIndices = shaped.glyphIndices;
        context.canvas
            .drawGlyphs(shaped.font, fontSize, shaped.text, glyphIndices, x, y);
        x += metrics.advanceWidth;
        height = max(height, metrics.maxHeight);
      }
      x = box!.x;
      y += height;
    }
  }

  void _setBox() {
    final fontSize = style!.fontSize ?? 1.0;
    final lineMetrics = shapedLines
        .map((line) => PdfFontMetrics.append(
            line.map((shaped) => shaped.metrics * fontSize)))
        .toList();
    box = PdfRect(0, 0, lineMetrics.fold<double>(0, (a, b) => max(a, b.width)),
        lineMetrics.fold<double>(0, (a, b) => a + b.maxHeight));
  }
}
