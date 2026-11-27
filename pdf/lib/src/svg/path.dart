/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';
import 'package:xml/xml.dart';

import '../../pdf.dart';
import 'brush.dart';
import 'clip_path.dart';
import 'color.dart';
import 'operation.dart';
import 'painter.dart';
import 'parser.dart';
import 'pattern.dart';
import 'transform.dart';

class SvgPath extends SvgOperation {
  SvgPath(
    this.d,
    SvgBrush brush,
    SvgClipPath clip,
    SvgTransform transform,
    SvgPainter painter,
  ) : super(brush, clip, transform, painter);

  factory SvgPath.fromXml(
    XmlElement element,
    SvgPainter painter,
    SvgBrush brush,
  ) {
    final d = element.getAttribute('d');
    if (d == null) {
      throw Exception('Path element must contain "d" attribute');
    }

    final _brush = SvgBrush.fromXml(element, brush, painter);

    return SvgPath(
      d,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  factory SvgPath.fromRectXml(
    XmlElement element,
    SvgPainter painter,
    SvgBrush brush,
  ) {
    final _brush = SvgBrush.fromXml(element, brush, painter);

    final x =
        SvgParser.getNumeric(element, 'x', _brush, defaultValue: 0)!.sizeValue;
    final y =
        SvgParser.getNumeric(element, 'y', _brush, defaultValue: 0)!.sizeValue;
    final width =
        SvgParser.getNumeric(element, 'width', _brush, defaultValue: 0)!
            .sizeValue;
    final height =
        SvgParser.getNumeric(element, 'height', _brush, defaultValue: 0)!
            .sizeValue;
    var rx = SvgParser.getNumeric(element, 'rx', _brush)?.sizeValue;
    var ry = SvgParser.getNumeric(element, 'ry', _brush)?.sizeValue;

    ry ??= rx ?? 0;
    rx ??= ry;
    final topRight = rx != 0 || ry != 0 ? 'a $rx $ry 0 0 1 $rx $ry' : '';
    final bottomRight = rx != 0 || ry != 0 ? 'a $rx $ry 0 0 1 ${-rx} $ry' : '';
    final bottomLeft =
        rx != 0 || ry != 0 ? 'a $rx $ry 0 0 1 ${-rx} ${-ry}' : '';
    final topLeft = rx != 0 || ry != 0 ? 'a $rx $ry 0 0 1 $rx ${-ry}' : '';
    final d =
        'M${x + rx} ${y}h${width - rx * 2}${topRight}v${height - ry * 2}${bottomRight}h${-(width - rx * 2)}${bottomLeft}v${-(height - ry * 2)}${topLeft}z';

    return SvgPath(
      d,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  factory SvgPath.fromCircleXml(
    XmlElement element,
    SvgPainter painter,
    SvgBrush brush,
  ) {
    final _brush = SvgBrush.fromXml(element, brush, painter);

    final cx = SvgParser.getNumeric(element, 'cx', _brush)!.sizeValue;
    final cy = SvgParser.getNumeric(element, 'cy', _brush)!.sizeValue;
    final r = SvgParser.getNumeric(element, 'r', _brush)!.sizeValue;
    final d =
        'M${cx - r},${cy}A$r,$r 0,0,0 ${cx + r},${cy}A$r,$r 0,0,0 ${cx - r},${cy}z';

    return SvgPath(
      d,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  factory SvgPath.fromEllipseXml(
    XmlElement element,
    SvgPainter painter,
    SvgBrush brush,
  ) {
    final _brush = SvgBrush.fromXml(element, brush, painter);

    final cx = SvgParser.getNumeric(element, 'cx', _brush)!.sizeValue;
    final cy = SvgParser.getNumeric(element, 'cy', _brush)!.sizeValue;
    final rx = SvgParser.getNumeric(element, 'rx', _brush)!.sizeValue;
    final ry = SvgParser.getNumeric(element, 'ry', _brush)!.sizeValue;
    final d =
        'M${cx - rx},${cy}A$rx,$ry 0,0,0 ${cx + rx},${cy}A$rx,$ry 0,0,0 ${cx - rx},${cy}z';

    return SvgPath(
      d,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  factory SvgPath.fromPolylineXml(
    XmlElement element,
    SvgPainter painter,
    SvgBrush brush,
  ) {
    final points = element.getAttribute('points');
    final d = 'M$points';

    final _brush = SvgBrush.fromXml(element, brush, painter);

    return SvgPath(
      d,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  factory SvgPath.fromPolygonXml(
    XmlElement element,
    SvgPainter painter,
    SvgBrush brush,
  ) {
    final points = element.getAttribute('points');
    final d = 'M${points}z';
    final _brush = SvgBrush.fromXml(element, brush, painter);

    return SvgPath(
      d,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  factory SvgPath.fromLineXml(
    XmlElement element,
    SvgPainter painter,
    SvgBrush brush,
  ) {
    final _brush = SvgBrush.fromXml(element, brush, painter);

    final x1 = SvgParser.getNumeric(element, 'x1', _brush)!.sizeValue;
    final y1 = SvgParser.getNumeric(element, 'y1', _brush)!.sizeValue;
    final x2 = SvgParser.getNumeric(element, 'x2', _brush)!.sizeValue;
    final y2 = SvgParser.getNumeric(element, 'y2', _brush)!.sizeValue;
    final d = 'M$x1 $y1 $x2 $y2';

    return SvgPath(
      d,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  final String d;

  @override
  void paintShape(PdfGraphics canvas) {
    final fill = brush.fill;
    if (fill != null && fill.isNotEmpty) {
      canvas.saveContext();
      final opacity = brush.effectiveFillOpacity;
      final background = fill is SvgPattern ? fill.opaqueBackground : null;
      if (background != null) {
        _paintBackedPattern(canvas, fill, background, opacity);
      } else {
        fill.setFillColor(this, canvas);
        if (opacity < 1) {
          canvas.setGraphicState(PdfGraphicState(opacity: opacity));
        }
        canvas
          ..drawShape(d)
          ..fillPath(evenOdd: brush.fillEvenOdd!);
      }
      canvas.restoreContext();
    }

    if (brush.stroke!.isNotEmpty) {
      canvas.saveContext();
      brush.stroke!.setStrokeColor(this, canvas);
      if (brush.effectiveStrokeOpacity < 1) {
        canvas.setGraphicState(
            PdfGraphicState(opacity: brush.effectiveStrokeOpacity));
      }
      canvas
        ..drawShape(d)
        ..setLineCap(brush.strokeLineCap!)
        ..setLineJoin(brush.strokeLineJoin!)
        ..setMiterLimit(math.max(1.0, brush.strokeMiterLimit!))
        ..setLineDashPattern(
            brush.strokeDashArray!, brush.strokeDashOffset!.toInt())
        ..setLineWidth(brush.strokeWidth!.sizeValue)
        ..strokePath();
      canvas.restoreContext();
    }
  }

  void _paintBackedPattern(
      PdfGraphics canvas, SvgColor fill, PdfColor background, double opacity) {
    final box = boundingBox();
    if (![box.x, box.y, box.width, box.height].every((v) => v.isFinite) ||
        box.width <= 0 ||
        box.height <= 0) {
      return;
    }
    final cover = PdfRect(box.x - 1, box.y - 1, box.width + 2, box.height + 2);
    canvas
      ..drawShape(d)
      ..clipPath(evenOdd: brush.fillEvenOdd!);
    if (opacity < 1) {
      canvas.setGraphicState(PdfGraphicState(opacity: opacity));
    }
    // Composite the opaque tile backdrop once through the shape's edge and opacity.
    canvas.drawTransparencyGroup(canvas.surfaceBounds ?? painter.boundingBox,
        (group) {
      group
        ..setFillColor(background)
        ..drawBox(cover)
        ..fillPath();
      fill.setFillColor(this, group);
      group
        ..drawBox(cover)
        ..fillPath();
    });
  }

  @override
  void drawShape(PdfGraphics canvas) {
    canvas.drawShape(d);
  }

  @override
  PdfRect boundingBox() => boundingBoxIn(null);

  @override
  PdfRect boundingBoxIn(Matrix4? matrix) =>
      PdfGraphics.shapeBoundingBox(d, matrix);
}
