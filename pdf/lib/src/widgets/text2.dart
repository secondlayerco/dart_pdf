import 'dart:math';

import '../../pdf.dart';
import '../shaping/shaping.dart';

import 'geometry.dart';
import 'text.dart';
import 'text_style.dart';
import 'widget.dart';

class Text2 extends RichText2 {
  Text2(
    String text, {
    TextStyle? style,
    TextAlign? textAlign,
    TextDirection? textDirection,
    bool? softWrap,
    bool tightBounds = false,
    double textScaleFactor = 1.0,
    TextOverflow? overflow,
  }) : super(
          text: TextSpan(text: text, style: style),
          textAlign: textAlign,
          softWrap: softWrap,
          tightBounds: tightBounds,
          textDirection: textDirection,
          textScaleFactor: textScaleFactor,
          overflow: overflow,
        );
}

class RichText2 extends Widget {
  RichText2({
    required this.text,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.style,
    this.tightBounds = false,
    this.textScaleFactor = 1.0,
    this.overflow = TextOverflow.visible,
  });

  // In logical ordering
  final InlineSpan text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final bool tightBounds;
  final double textScaleFactor;
  final TextOverflow? overflow;

  final List<_RichTextLine> _lines = [];

  @override
  void layout(Context context, BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    final children = <TextSpan>[];
    text.visitChildren((child, style, parentStyle) {
      if (child is TextSpan) {
        children.add(child);
        return true;
      }
      return false;
    }, null, null);

    final constraintWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth();

    _lines.clear();

    var startingPosition = 0.0;
    for (final textSpan in children) {
      final letterSpacing = textSpan.style?.letterSpacing ?? 0.0;
      final lineSpacing = textSpan.style?.lineSpacing ?? 0.0;
      final fontSize = textSpan.style?.fontSize ?? 1.0;

      final spanLines = _layoutText(context, textSpan,
          startingLocation: startingPosition,
          maxWidth: constraintWidth,
          letterSpacing: letterSpacing,
          fontSize: fontSize);
      if (spanLines.linesVisual.isEmpty) continue;

      if (_lines.isEmpty) {
        _lines.addAll(spanLines.linesVisual.map((line) =>
            _RichTextLine.single(textSpan, line, lineSpacing: lineSpacing)));
      } else {
        if (spanLines.linesVisual.first.isNotEmpty) {
          _lines.last.add(_RichTextShapingOutput(
            textSpan,
            spanLines.linesVisual.first,
          ));
        }
        _lines.addAll(spanLines.linesVisual.skip(1).map((line) =>
            _RichTextLine.single(textSpan, line, lineSpacing: lineSpacing)));
      }
      startingPosition = spanLines.endingLocation * fontSize;
    }

    box = PdfRect(
        0.0,
        0.0,
        constraintWidth,
        constraints.constrainHeight(
            _lines.fold(0.0, (a, b) => a + b.maxHeight + b.lineSpacing)));
  }

  LinesShapingOutput _layoutText(Context context, TextSpan textSpan,
      {required double startingLocation,
      required double maxWidth,
      required double letterSpacing,
      required double fontSize}) {
    final primaryFont = textSpan.style!.font!.getFont(context) as PdfTtfFont;
    final fallbackFonts = textSpan.style!.fontFallback
        .map((font) => font.getFont(context))
        .whereType<PdfTtfFont>()
        .toList();

    if (fallbackFonts.length != textSpan.style!.fontFallback.length) {
      print(
          'Some fallback fonts have been removed because they are not TTF: ${textSpan.style!.fontFallback.map((font) => font.getFont(context)).where((font) => font is! PdfTtfFont).map((font) => font.fontName).toList()}');
    }

    return Shaping().shapeLinesWithBreaks(
        textSpan.text ?? '', primaryFont, fallbackFonts,
        startingLocation: startingLocation / fontSize,
        maxWidth: maxWidth / fontSize,
        letterSpacing: letterSpacing / fontSize);
  }

  @override
  void paint(Context context) {
    super.paint(context);

    var y = box!.height;
    PdfColor? currentColor;

    // Reversed because of PDF ordering
    for (final line in _lines) {
      final width = line.width;
      var x = startX(width);
      var height = 0.0;
      for (final item in line.items) {
        final fontSize = item.textSpan.style?.fontSize ?? 1.0;
        final letterSpacing = item.textSpan.style?.letterSpacing ?? 0.0;
        final color = item.textSpan.style?.color ?? PdfColors.black;
        if (color != currentColor) {
          context.canvas.setFillColor(color);
          currentColor = color;
        }

        final itemMetrics =
            item.shapingOutput.metrics(letterSpacing: letterSpacing) * fontSize;

        final realY = y - itemMetrics.ascent;
        for (final shaped in item.shapingOutput.resultsVisual) {
          final metrics = shaped.metrics * fontSize;
          final spacing = metrics.advanceWidth > 0 ? letterSpacing : 0.0;
          final glyphIndicesLogical = shaped.glyphIndicesLogical;
          context.canvas.drawGlyphs(
              shaped.font, fontSize, glyphIndicesLogical, x, realY,
              charSpace: 0);
          _foregroundPaint(
              context, item.textSpan.style, x, realY, metrics, letterSpacing);
          x += metrics.advanceWidth + spacing;
          height =
              max(height, (-itemMetrics.ascent + itemMetrics.descent).abs());
        }
      }
      y -= height + line.lineSpacing;
    }
  }

  double startX(double width) => switch (textAlign) {
        TextAlign.center => box!.x + (box!.width - width) / 2,
        TextAlign.right => box!.x + box!.width - width,
        _ => box!.x,
      };

  void _foregroundPaint(
    Context context,
    TextStyle? style,
    double xLocation,
    double yLocation,
    PdfFontMetrics metrics,
    double letterSpacing,
  ) {
    if (style == null || style.decoration == null) {
      return;
    }

    if (style.decoration!.contains(TextDecoration.underline)) {
      final base = metrics.descent / 2;
      context.canvas.drawLine(
        xLocation + metrics.effectiveLeft,
        yLocation + base,
        xLocation + metrics.advanceWidth,
        yLocation + base,
      );
      context.canvas.strokePath();
    }

    if (style.decoration!.contains(TextDecoration.lineThrough)) {
      final base = (style.fontSize ?? 1) / 4;
      context.canvas.drawLine(
        xLocation + metrics.effectiveLeft,
        yLocation + base,
        xLocation + metrics.advanceWidth,
        yLocation + base,
      );
      context.canvas.strokePath();
    }
  }
}

class _RichTextShapingOutput {
  _RichTextShapingOutput(this.textSpan, this.shapingOutput);

  ShapingOutput shapingOutput;
  TextSpan textSpan;

  @override
  String toString() =>
      '$_RichTextShapingOutput(${textSpan.text}, $shapingOutput)';
}

class _RichTextLine {
  _RichTextLine(this.items, {required this.lineSpacing});
  _RichTextLine.single(TextSpan textSpan, ShapingOutput shapingOutput,
      {required this.lineSpacing})
      : items = [_RichTextShapingOutput(textSpan, shapingOutput)];

  List<_RichTextShapingOutput> items;
  double lineSpacing;

  void add(_RichTextShapingOutput item) => items.add(item);

  List<PdfFontMetrics> get allMetrics {
    return items
        .map((i) =>
            i.shapingOutput.metrics(
                letterSpacing: i.textSpan.style?.letterSpacing ?? 0.0) *
            (i.textSpan.style?.fontSize ?? 0.0))
        .toList();
  }

  double get left => allMetrics.firstOrNull?.left ?? 0.0;
  double get width {
    final widths = items.map((i) {
      final letterSpacing = i.textSpan.style?.letterSpacing ?? 0.0;
      final fontSize = i.textSpan.style?.fontSize ?? 1.0;
      final m =
          i.shapingOutput.metrics(letterSpacing: letterSpacing) * fontSize;
      return m.advanceWidth + (m.advanceWidth > 0 ? letterSpacing : 0.0);
    }).toList();
    return widths.fold(0.0, (a, b) => a + b);
  }

  double get maxHeight =>
      allMetrics.fold(0.0, (a, b) => max(a, b.maxHeight + lineSpacing));

  @override
  String toString() => '$_RichTextLine(${items.join('\n\t')})';
}
