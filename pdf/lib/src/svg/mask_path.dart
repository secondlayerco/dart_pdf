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

@immutable
class SvgMaskPath {
  const SvgMaskPath(this.children, this.painter,
      {required this.useAlpha, required this.objectBoundingBox, this.region});

  static SvgMaskPath? fromXml(
      XmlElement element, SvgPainter painter, SvgBrush brush) {
    final maskPathAttr = element.getAttribute('mask');
    if (maskPathAttr == null) {
      return null;
    }

    Iterable<SvgOperation?> children;

    if (maskPathAttr.startsWith('url(#')) {
      final id = maskPathAttr.substring(5, maskPathAttr.lastIndexOf(')'));
      final maskPath = painter.parser.findById(id);
      if (maskPath != null) {
        final maskBrush = SvgBrush.fromXml(maskPath, brush, painter);
        children = maskPath.children.whereType<XmlElement>().map<SvgOperation?>(
            (c) => SvgOperation.fromXml(c, painter, maskBrush));
        return SvgMaskPath(children, painter,
            useAlpha: maskPath.getAttribute('mask-type')?.trim() == 'alpha',
            objectBoundingBox: maskPath.getAttribute('maskContentUnits') ==
                'objectBoundingBox',
            region: _readRegion(maskPath, maskBrush, painter.parser.viewBox));
      }
    }

    return null;
  }

  final Iterable<SvgOperation?> children;

  final SvgPainter painter;

  final bool useAlpha;
  final bool objectBoundingBox;
  final PdfRect Function(PdfRect Function())? region;

  static PdfRect Function(PdfRect Function())? _readRegion(
      XmlElement mask, SvgBrush brush, PdfRect viewport) {
    final attributes = ['x', 'y', 'width', 'height'];
    final lengths = attributes
        .map((name) => SvgParser.getNumeric(mask, name, brush))
        .toList();
    if (lengths.every((length) => length == null)) {
      return null;
    }
    final userSpace = mask.getAttribute('maskUnits') == 'userSpaceOnUse';
    double resolve(int index, double extent) {
      final length = lengths[index];
      final fallback = index < 2 ? -.1 : 1.2;
      if (length == null) {
        return fallback * extent;
      }
      return userSpace && length.unit != SvgUnit.percent
          ? length.sizeValue
          : length.sizeValue * extent;
    }

    return (targetBounds) {
      final box = userSpace ? viewport : targetBounds();
      final x = resolve(0, box.width);
      final y = resolve(1, box.height);
      return PdfRect(
        userSpace ? x : box.x + x,
        userSpace ? y : box.y + y,
        resolve(2, box.width).clamp(0.0, double.infinity),
        resolve(3, box.height).clamp(0.0, double.infinity),
      );
    };
  }

  SvgLinkClip? apply(PdfGraphics canvas, PdfRect Function() targetBounds) {
    final bounds = region?.call(targetBounds);
    final mask = PdfSoftMask(
      painter.document,
      boundingBox: bounds ?? painter.localBoundingBox(canvas),
      useAlpha: useAlpha,
    );

    final maskCanvas = mask.getGraphics();
    final pageTransform = canvas.getTransform();
    final Matrix4? regionTransform =
        bounds == null ? null : pageTransform.clone();
    if (objectBoundingBox) {
      final transform = SvgOperation.objectBoundingBoxTransform(targetBounds());
      maskCanvas!.setTransform(transform);
      pageTransform.multiply(transform);
    }

    final operations = children.whereType<SvgOperation>().toList();
    painter.linkDefinitionDepth++;
    try {
      for (final child in operations) {
        child.paint(maskCanvas!);
      }
    } finally {
      painter.linkDefinitionDepth--;
    }

    canvas.setGraphicState(PdfGraphicState(softMask: mask));
    if (painter.page == null) {
      return null;
    }
    final regionCorners = bounds == null || regionTransform == null
        ? null
        : [
            for (final corner in [
              bounds.topLeft,
              bounds.topRight,
              bounds.bottomRight,
              bounds.bottomLeft
            ])
              regionTransform.transform3(Vector3(corner.x, corner.y, 0)).xy,
          ];
    return SvgLinkClip(operations, pageTransform,
        mask: true, alphaMask: useAlpha, regionCorners: regionCorners);
  }
}
