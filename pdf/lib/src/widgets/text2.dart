import 'dart:math';

import '../../pdf.dart';
import '../shaping/shaping.dart';

import 'annotations.dart';
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
  void layout(Context context, BoxConstraints constraints, {bool parentUsesSize = false}) {
    final children = <_TextSpanWithAnnotation>[];
    text.visitChildren(
      (child, style, annotation) {
        if (child is TextSpan) {
          children.add(_TextSpanWithAnnotation(child, annotation));
          return true;
        }
        return false;
      },
      null,
      null,
    );

    final constraintWidth = constraints.hasBoundedWidth ? constraints.maxWidth : constraints.constrainWidth();

    _lines.clear();

    var startingPosition = 0.0;
    for (final textSpanWithAnnotation in children) {
      final textSpan = textSpanWithAnnotation.span;
      final letterSpacing = textSpan.style?.letterSpacing ?? 0.0;
      final lineSpacing = textSpan.style?.lineSpacing ?? 0.0;
      final fontSize = textSpan.style?.fontSize ?? 1.0;

      final spanLines = _layoutText(
        context,
        textSpan,
        startingLocation: startingPosition,
        maxWidth: constraintWidth,
        letterSpacing: letterSpacing,
        fontSize: fontSize,
      );
      if (spanLines.linesVisual.isEmpty) continue;

      if (_lines.isEmpty) {
        _lines.addAll(spanLines.linesVisual.map((line) => _RichTextLine.single(textSpanWithAnnotation, line, lineSpacing: lineSpacing)));
      } else {
        if (spanLines.linesVisual.first.isNotEmpty) {
          if (_lines.last.firstOrNull?.shapingOutput.leftToRight ?? true) {
            _lines.last.addLast(_RichTextShapingOutput(textSpanWithAnnotation, spanLines.linesVisual.first));
          } else {
            _lines.last.addFirst(_RichTextShapingOutput(textSpanWithAnnotation, spanLines.linesVisual.first));
          }
        }
        _lines.addAll(spanLines.linesVisual.skip(1).map((line) => _RichTextLine.single(textSpanWithAnnotation, line, lineSpacing: lineSpacing)));
      }
      startingPosition = spanLines.endingLocation * fontSize;
    }

    box = PdfRect(
      0.0,
      0.0,
      constraints.constrainWidth(_lines.fold(0.0, (a, b) => max(a, b.width))),
      constraints.constrainHeight(_lines.fold(0.0, (a, b) => a + b.maxHeight + b.lineSpacing)),
    );
  }

  LinesShapingOutput _layoutText(
    Context context,
    TextSpan textSpan, {
    required double startingLocation,
    required double maxWidth,
    required double letterSpacing,
    required double fontSize,
  }) {
    final primaryFont = textSpan.style!.font!.getFont(context) as PdfTtfFont;
    final fallbackFonts = textSpan.style!.fontFallback.map((font) => font.getFont(context)).whereType<PdfTtfFont>().toList();

    if (fallbackFonts.length != textSpan.style!.fontFallback.length) {
      print(
        'Some fallback fonts have been removed because they are not TTF: ${textSpan.style!.fontFallback.map((font) => font.getFont(context)).where((font) => font is! PdfTtfFont).map((font) => font.fontName).toList()}',
      );
    }

    return Shaping().shapeLinesWithBreaks(
      textSpan.text ?? '',
      primaryFont,
      fallbackFonts,
      startingLocation: startingLocation / fontSize,
      maxWidth: maxWidth / fontSize,
      letterSpacing: letterSpacing / fontSize,
    );
  }

  @override
  void paint(Context context) {
    super.paint(context);

    var y = box!.height;
    PdfColor? currentColor;

    for (var lineIndex = 0; lineIndex < _lines.length; lineIndex++) {
      final line = _lines[lineIndex];
      final isLastLine = lineIndex == _lines.length - 1;

      // Calculate justify spacing
      final isJustify = textAlign == TextAlign.justify && !isLastLine;
      var extraSpacePerSpace = 0.0;
      if (isJustify) {
        final totalSpaces = _countSpacesInLine(line);
        if (totalSpaces > 0) {
          extraSpacePerSpace = (box!.width - line.width) / totalSpaces;
        }
      }
      final useJustify = isJustify && extraSpacePerSpace > 0;

      var x = useJustify ? box!.x : startX(line.width);
      final lineMetrics = PdfFontMetrics.append(line.allMetrics);

      var height = 0.0;
      for (final item in line.items) {
        final fontSize = item.textSpan.style?.fontSize ?? 1.0;
        final letterSpacing = item.textSpan.style?.letterSpacing ?? 0.0;
        final color = item.textSpan.style?.color ?? PdfColors.black;
        if (color != currentColor) {
          context.canvas.setFillColor(color);
          currentColor = color;
        }

        final itemMetrics = item.shapingOutput.metrics(letterSpacing: letterSpacing / fontSize) * fontSize;

        final realY = y - itemMetrics.ascent;

        // Paint annotation if present
        if (item.annotation != null) {
          print('[pdf] RichText2: Building annotation for text at x=$x, y=$realY');
          final annotationBox = PdfRect(x, realY - itemMetrics.descent, itemMetrics.advanceWidth, itemMetrics.ascent + itemMetrics.descent);
          item.annotation!.build(context, annotationBox);
        }

        for (final shaped in item.shapingOutput.resultsVisual) {
          final metrics = shaped.metrics(letterSpacing: letterSpacing / fontSize) * fontSize;
          final glyphIndicesLogical = shaped.glyphIndicesLogical;

          if (useJustify) {
            final advanceWithExtra = _drawJustifiedGlyphs(context, shaped, fontSize, letterSpacing, glyphIndicesLogical, x, realY, extraSpacePerSpace);
            _foregroundPaint(context, item.textSpan.style, x, realY, metrics, lineMetrics, letterSpacing);
            x += advanceWithExtra;
          } else {
            context.canvas.drawGlyphs(shaped.font, fontSize, glyphIndicesLogical, x, realY, charSpace: letterSpacing);
            _foregroundPaint(context, item.textSpan.style, x, realY, metrics, lineMetrics, letterSpacing);
            x += metrics.advanceWidth;
          }
          height = max(height, (-itemMetrics.ascent + itemMetrics.descent).abs());
        }
      }
      y -= height + line.lineSpacing;
    }
  }

  // Draw glyphs with extra spacing at space boundaries for justify alignment
  double _drawJustifiedGlyphs(
    Context context,
    ShapingResult shaped,
    double fontSize,
    double letterSpacing,
    List<int> glyphIndicesLogical,
    double x,
    double y,
    double extraSpacePerSpace,
  ) {
    final spaceGlyphIndex = shaped.font.font.charToGlyphIndexMap[32];
    if (spaceGlyphIndex == null || !glyphIndicesLogical.contains(spaceGlyphIndex)) {
      // No space glyphs in this run, draw normally
      context.canvas.drawGlyphs(shaped.font, fontSize, glyphIndicesLogical, x, y, charSpace: letterSpacing);
      final metrics = shaped.metrics(letterSpacing: letterSpacing / fontSize) * fontSize;
      return metrics.advanceWidth;
    }

    var currentX = x;
    var segStart = 0;
    for (var i = 0; i <= glyphIndicesLogical.length; i++) {
      final isSpace = i < glyphIndicesLogical.length && glyphIndicesLogical[i] == spaceGlyphIndex;
      final isEnd = i == glyphIndicesLogical.length;

      if (isSpace || isEnd) {
        // Draw segment including the space glyph
        final segEnd = isSpace ? i + 1 : i;
        if (segEnd > segStart) {
          final segment = glyphIndicesLogical.sublist(segStart, segEnd);
          context.canvas.drawGlyphs(shaped.font, fontSize, segment, currentX, y, charSpace: letterSpacing);
          for (var j = segStart; j < segEnd; j++) {
            final gm = shaped.font.glyphIndexMetricsWithLetterSpacing(GlyphIndex(glyphIndicesLogical[j]), letterSpacing / fontSize);
            currentX += gm.advanceWidth * fontSize;
          }
        }
        if (isSpace) {
          currentX += extraSpacePerSpace;
          segStart = segEnd;
        }
      }
    }
    return currentX - x;
  }

  int _countSpacesInLine(_RichTextLine line) {
    var count = 0;
    for (final item in line.items) {
      for (final shaped in item.shapingOutput.resultsVisual) {
        final spaceGlyphIndex = shaped.font.font.charToGlyphIndexMap[32];
        if (spaceGlyphIndex != null) {
          count += shaped.glyphIndicesLogical.where((g) => g == spaceGlyphIndex).length;
        }
      }
    }
    return count;
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
    PdfFontMetrics spanMetrics,
    PdfFontMetrics lineMetrics,
    double letterSpacing,
  ) {
    if (style == null || style.decoration == null) {
      return;
    }

    if (style.decoration!.contains(TextDecoration.underline)) {
      final base = lineMetrics.descent / 2;
      context.canvas.drawLine(xLocation + spanMetrics.effectiveLeft, yLocation + base, xLocation + spanMetrics.advanceWidth, yLocation + base);
      context.canvas.strokePath();
    }

    if (style.decoration!.contains(TextDecoration.lineThrough)) {
      final base = (style.fontSize ?? 1) / 4;
      context.canvas.drawLine(xLocation + spanMetrics.effectiveLeft, yLocation + base, xLocation + spanMetrics.advanceWidth, yLocation + base);
      context.canvas.strokePath();
    }
  }
}

class _RichTextShapingOutput {
  _RichTextShapingOutput(this.textSpanWithAnnotation, this.shapingOutput);

  ShapingOutput shapingOutput;
  _TextSpanWithAnnotation textSpanWithAnnotation;

  TextSpan get textSpan => textSpanWithAnnotation.span;
  AnnotationBuilder? get annotation => textSpanWithAnnotation.annotation;

  @override
  String toString() => '$_RichTextShapingOutput(${textSpan.text}, $shapingOutput)';
}

class _RichTextLine {
  _RichTextLine(this.items, {required this.lineSpacing});
  _RichTextLine.single(_TextSpanWithAnnotation textSpanWithAnnotation, ShapingOutput shapingOutput, {required this.lineSpacing})
    : items = [_RichTextShapingOutput(textSpanWithAnnotation, shapingOutput)];

  List<_RichTextShapingOutput> items;
  double lineSpacing;

  _RichTextShapingOutput? get firstOrNull => items.firstOrNull;

  void addFirst(_RichTextShapingOutput item) => items.insert(0, item);
  void addLast(_RichTextShapingOutput item) => items.add(item);

  List<PdfFontMetrics> get allMetrics {
    return items.map((i) => i.shapingOutput.metrics(letterSpacing: i.textSpan.style?.letterSpacing ?? 0.0) * (i.textSpan.style?.fontSize ?? 0.0)).toList();
  }

  double get left => allMetrics.firstOrNull?.left ?? 0.0;
  double get width {
    var width = 0.0;
    for (final item in items) {
      final fontSize = item.textSpan.style?.fontSize ?? 1.0;
      final letterSpacing = item.textSpan.style?.letterSpacing ?? 0.0;
      for (final shaped in item.shapingOutput.resultsVisual) {
        final metrics = shaped.metrics(letterSpacing: letterSpacing / fontSize) * fontSize;
        width += metrics.advanceWidth;
      }
    }
    return width;
  }

  double get maxHeight => allMetrics.fold(0.0, (a, b) => max(a, b.maxHeight + lineSpacing));

  @override
  String toString() => '$_RichTextLine(${items.join('\n\t')})';
}

class _TextSpanWithAnnotation {
  final TextSpan span;
  final AnnotationBuilder? annotation;

  _TextSpanWithAnnotation(this.span, this.annotation);

  TextStyle? get style => span.style;
}
