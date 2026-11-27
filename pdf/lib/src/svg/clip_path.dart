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

import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:xml/xml.dart';

import '../../pdf.dart';
import 'brush.dart';
import 'link_region.dart';
import 'operation.dart';
import 'painter.dart';
import 'parser.dart';
import 'transform.dart';

@immutable
class SvgClipPath {
  const SvgClipPath(this.children, this.isEmpty, this.painter,
      {this.evenOdd = false,
      this.transform = SvgTransform.none,
      this.objectBoundingBox = false});

  factory SvgClipPath.fromXml(
      XmlElement element, SvgPainter painter, SvgBrush brush) {
    final clipPathAttr = element.getAttribute('clip-path');
    if (clipPathAttr == null) {
      return const SvgClipPath(null, true, null);
    }

    if (clipPathAttr.startsWith('url(#') && clipPathAttr.endsWith(')')) {
      final id = clipPathAttr.substring(5, clipPathAttr.length - 1);
      final clipPath = painter.parser.findById(id);
      if (clipPath != null) {
        final elements = clipPath.children.whereType<XmlElement>().toList();
        SvgParser.convertStyle(clipPath);
        elements.forEach(SvgParser.convertStyle);
        final children = elements
            .map((child) => SvgOperation.fromXml(child, painter, brush))
            .whereType<SvgOperation>();
        final rule = elements.length == 1
            ? elements.single.getAttribute('clip-rule') ??
                clipPath.getAttribute('clip-rule')
            : null;
        return SvgClipPath(children, false, painter,
            evenOdd: rule == 'evenodd',
            objectBoundingBox:
                clipPath.getAttribute('clipPathUnits') == 'objectBoundingBox',
            transform: SvgTransform.fromXml(clipPath));
      }
    }

    return const SvgClipPath(null, true, null);
  }

  final Iterable<SvgOperation>? children;

  final bool evenOdd;
  final SvgTransform transform;
  final bool objectBoundingBox;

  final bool isEmpty;

  final SvgPainter? painter;

  bool get isNotEmpty => !isEmpty;

  SvgLinkClip? apply(PdfGraphics canvas, PdfRect Function() targetBounds) {
    if (isEmpty) {
      return null;
    }
    final units = objectBoundingBox
        ? SvgOperation.objectBoundingBoxTransform(targetBounds())
        : Matrix4.identity();
    final local = transform.matrix;
    if (local != null) {
      units.multiply(local);
    }
    final inverse = Matrix4.zero();
    final operations = children!.toList();
    if (inverse.copyInverse(units) == 0) {
      canvas.drawRect(0, 0, 0, 0);
      canvas.clipPath();
      return SvgLinkClip(const [], canvas.getTransform());
    }
    final transformed = objectBoundingBox || local != null;
    if (transformed) {
      canvas.setTransform(units);
    }
    for (final child in operations) {
      child.draw(canvas);
    }
    final pageTransform = canvas.getTransform();
    canvas.clipPath(evenOdd: evenOdd);
    if (transformed) {
      canvas.setTransform(inverse);
    }
    return painter?.page != null
        ? SvgLinkClip(operations, pageTransform, evenOdd: evenOdd)
        : null;
  }
}
