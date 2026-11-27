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

import 'dart:math';

import 'package:vector_math/vector_math_64.dart';
import 'package:xml/xml.dart';

import '../../pdf.dart';
import 'brush.dart';
import 'clip_path.dart';
import 'operation.dart';
import 'painter.dart';
import 'transform.dart';

class SvgGroup extends SvgOperation {
  SvgGroup(
    this.children,
    SvgBrush brush,
    SvgClipPath clip,
    SvgTransform transform,
    SvgPainter painter,
  ) : super(brush, clip, transform, painter);

  factory SvgGroup.fromXml(
      XmlElement element, SvgPainter painter, SvgBrush brush) {
    final _brush = SvgBrush.fromXml(element, brush, painter);

    final children = element.children
        .whereType<XmlElement>()
        .where((element) => element.name.local != 'symbol')
        .map<SvgOperation?>(
            (child) => SvgOperation.fromXml(child, painter, _brush))
        .whereType<SvgOperation>();

    return SvgGroup(
      children,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );
  }

  final Iterable<SvgOperation> children;

  @override
  void paintShape(PdfGraphics canvas) {
    for (final child in children) {
      child.paint(canvas);
    }
  }

  @override
  void drawShape(PdfGraphics canvas) {
    for (final child in children) {
      child.draw(canvas);
    }
  }

  @override
  PdfRect boundingBox() => boundingBoxIn(null);

  @override
  PdfRect boundingBoxIn(Matrix4? matrix) {
    var x = double.infinity, y = double.infinity;
    var right = double.negativeInfinity, top = double.negativeInfinity;
    for (final child in children) {
      final box = child.transformedBoundingBox(matrix);
      if (identical(box, PdfRect.zero)) {
        continue;
      }
      x = min(x, box.left);
      y = min(y, box.bottom);
      right = max(right, box.right);
      top = max(top, box.top);
    }
    return x.isFinite && y.isFinite && right.isFinite && top.isFinite
        ? PdfRect.fromLTRB(x, y, right, top)
        : PdfRect.zero;
  }
}
