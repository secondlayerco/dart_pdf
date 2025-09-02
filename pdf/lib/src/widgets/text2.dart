import 'dart:math';

import '../../pdf.dart';
import '../shaping/shaping.dart';

import 'geometry.dart';
import 'text.dart';
import 'text_style.dart';
import 'widget.dart';

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

  List<ShapingOutput> shapedLines = [];

  @override
  void layout(Context context, BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    box = PdfRect(0, 0, 200, 100);

    final primaryFont = style!.font!.getFont(context) as PdfTtfFont;
    final fallbackFonts = style!.fontFallback
        .map((font) => font.getFont(context))
        .cast<PdfTtfFont>()
        .toList();

    final constraintWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth();
    final letterSpacing = style?.letterSpacing ?? 0.0;

    final fontSize = style!.fontSize ?? 1.0;

    final lines = Shaping().shapeLinesWithBreaks(
        text, primaryFont, fallbackFonts,
        maxWidth: constraintWidth / fontSize,
        letterSpacing: letterSpacing / fontSize);

    shapedLines
      ..clear()
      ..addAll(lines.linesVisual);

    _setBox();
  }

  @override
  void paint(Context context) {
    super.paint(context);

    final fontSize = style!.fontSize ?? 1.0;
    final letterSpacing = style?.letterSpacing ?? 0.0;

    var y = box!.y;

    for (final line in shapedLines.reversed) {
      final lineMetrics = line.metrics(letterSpacing: letterSpacing) * fontSize;

      final width = lineMetrics.width;
      var x = startX(width);
      var height = 0.0;
      for (final shaped in line.resultsVisual) {
        final metrics = shaped.metrics * fontSize;
        final spacing = metrics.advanceWidth > 0 ? letterSpacing : 0.0;
        final glyphIndicesLogical = shaped.glyphIndicesLogical;
        // TODO: I'm not sure this is the correct formula, it works for Latin
        final realY = y + lineMetrics.maxHeight - lineMetrics.ascent;
        context.canvas.drawGlyphs(
            shaped.font,
            fontSize,
            String.fromCharCodes(shaped.textLogical),
            glyphIndicesLogical,
            x,
            realY,
            charSpace: 0);
        x += metrics.advanceWidth + spacing;
        height = max(height, metrics.maxHeight);
      }
      y += height;
    }
  }

  double startX(double width) => switch (textAlign) {
        TextAlign.center => box!.x + (box!.width - width) / 2,
        TextAlign.right => box!.x + box!.width - width,
        _ => box!.x,
      };

  void _setBox() {
    final letterSpacing = style?.letterSpacing ?? 0.0;
    final fontSize = style!.fontSize ?? 1.0;

    final lineMetrics = shapedLines
        .map((line) => line.metrics(letterSpacing: letterSpacing) * fontSize);

    box = PdfRect(
        0.0,
        0.0,
        lineMetrics.fold(0.0, (a, b) => max(a, b.left + b.width)),
        lineMetrics.fold(0.0, (a, b) => a + b.maxHeight));
  }
}
