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

import 'package:xml/xml.dart';

import '../../pdf.dart';
import 'brush.dart';
import 'color.dart';
import 'operation.dart';
import 'painter.dart';
import 'parser.dart';
import 'transform.dart';

/// A `<pattern>` drawn as a native tiling pattern. Only
/// `patternUnits="userSpaceOnUse"` without `viewBox` is supported.
class SvgPattern extends SvgColor {
  SvgPattern._(
    this.painter,
    this.x,
    this.y,
    this.width,
    this.height,
    this.transform,
    this.children,
  );

  /// The pattern, or [SvgColor.unknown] when it cannot be drawn
  static SvgColor fromXml(XmlElement element, SvgPainter painter) {
    final id = element.getAttribute('id');
    final cached = id == null ? null : painter.patterns[id];
    if (cached != null) {
      return cached;
    }

    if (element.getAttribute('patternUnits') != 'userSpaceOnUse' ||
        (element.getAttribute('patternContentUnits') ?? 'userSpaceOnUse') !=
            'userSpaceOnUse' ||
        element.getAttribute('viewBox') != null) {
      return SvgColor.unknown;
    }

    final width = SvgParser.getNumeric(element, 'width', null)?.sizeValue;
    final height = SvgParser.getNumeric(element, 'height', null)?.sizeValue;
    final transform =
        SvgTransform.fromString(element.getAttribute('patternTransform'));
    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        (transform.isNotEmpty && transform.matrix!.determinant() == 0)) {
      return SvgColor.unknown;
    }

    // A tile that paints itself has no end
    if (!painter.patternsInProgress.add(element)) {
      return SvgColor.unknown;
    }

    try {
      // Tile content inherits from the pattern's ancestors, not from the shape
      var brush = painter.defaultBrush;
      for (final ancestor in element.ancestorElements.toList().reversed) {
        brush = SvgBrush.fromXml(ancestor, brush, painter);
      }
      brush = SvgBrush.fromXml(element, brush, painter);

      final result = SvgPattern._(
        painter,
        SvgParser.getNumeric(element, 'x', null, defaultValue: 0)!.sizeValue,
        SvgParser.getNumeric(element, 'y', null, defaultValue: 0)!.sizeValue,
        width,
        height,
        transform,
        element.children
            .whereType<XmlElement>()
            .map<SvgOperation?>(
                (child) => SvgOperation.fromXml(child, painter, brush))
            .whereType<SvgOperation>()
            .toList(),
      );
      if (id != null) {
        painter.patterns[id] = result;
      }
      return result;
    } finally {
      painter.patternsInProgress.remove(element);
    }
  }

  final SvgPainter painter;

  final double x;

  final double y;

  final double width;

  final double height;

  final SvgTransform transform;

  final List<SvgOperation> children;

  /// Tiles already built, by the matrix that places them
  final _tiles = <String, PdfTilingPattern>{};

  @override
  bool get isEmpty => false;

  @override
  SvgColor merge(SvgColor other) => other.isEmpty ? this : other;

  PdfTilingPattern _build(PdfGraphics canvas, {required bool translucent}) {
    // The tracked transform is from the stream's default space, where a pattern matrix lands
    final matrix = canvas.getTransform();
    if (transform.isNotEmpty) {
      matrix.multiply(transform.matrix!);
    }
    matrix.translate(x, y);

    final s = matrix.storage;
    final key = '${painter.patternDepth} $translucent ${s[0]} ${s[1]} ${s[4]} '
        '${s[5]} ${s[12]} ${s[13]}';
    final cached = _tiles[key];
    if (cached != null) {
      return cached;
    }

    final cell = PdfRect(0, 0, width, height);
    final pattern = PdfTilingPattern(
      painter.document,
      boundingBox: cell,
      matrix: matrix,
    );
    void paintChildren(PdfGraphics tile) {
      for (final child in children) {
        child.paint(tile);
      }
    }

    painter.patternDepth++;
    try {
      if (translucent) {
        // Some viewers apply the opacity to each object of the tile, not to the tile
        pattern.getGraphics().drawTransparencyGroup(cell, paintChildren);
      } else {
        paintChildren(pattern.getGraphics());
      }
    } finally {
      painter.patternDepth--;
    }
    return _tiles[key] = pattern;
  }

  @override
  void setFillColor(SvgOperation op, PdfGraphics canvas) {
    canvas.setFillPattern(
        _build(canvas, translucent: op.brush.effectiveFillOpacity < 1));
  }

  @override
  void setStrokeColor(SvgOperation op, PdfGraphics canvas) {
    canvas.setStrokePattern(
        _build(canvas, translucent: op.brush.effectiveStrokeOpacity < 1));
  }

  @override
  String toString() =>
      '$runtimeType x:$x y:$y width:$width height:$height transform:${transform.matrix}';
}
