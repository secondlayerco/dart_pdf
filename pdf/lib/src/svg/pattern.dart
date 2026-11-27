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

import 'package:path_parsing/path_parsing.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:xml/xml.dart';

import '../../pdf.dart';
import '../pdf/format/array.dart';
import '../pdf/obj/graphic_stream.dart';
import 'brush.dart';
import 'color.dart';
import 'group.dart';
import 'operation.dart';
import 'painter.dart';
import 'parser.dart';
import 'path.dart';
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

  // Smaller cells would repeat millions of times
  static const _minimumSize = 0.1;

  /// A length in user units, or null when it needs a context a pattern lacks
  static double? _length(XmlElement element, String name, [double? fallback]) {
    final attribute = element.getAttribute(name);
    if (attribute == null) {
      return fallback;
    }

    try {
      final length = SvgNumeric(attribute, null);
      if (length.unit == SvgUnit.em || length.unit == SvgUnit.percent) {
        return null;
      }
      return length.sizeValue;
    } on StateError {
      return null;
    }
  }

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

    final x = _length(element, 'x', 0);
    final y = _length(element, 'y', 0);
    final width = _length(element, 'width');
    final height = _length(element, 'height');
    final transform =
        SvgTransform.fromString(element.getAttribute('patternTransform'));
    if (x == null ||
        y == null ||
        width == null ||
        height == null ||
        width < _minimumSize ||
        height < _minimumSize ||
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
        x,
        y,
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

  late final PdfColor? opaqueBackground = _findOpaqueBackground();

  PdfColor? _findOpaqueBackground() {
    Iterable<SvgOperation> layers = children;
    while (layers.isNotEmpty) {
      final first = layers.first;
      final brush = first.brush;
      if (brush.opacity != 1 ||
          brush.blendMode != null ||
          brush.mask != null ||
          first.clip.isNotEmpty ||
          first.transform.matrix?.isIdentity() == false) {
        return null;
      }
      if (first is SvgGroup) {
        layers = first.children;
        continue;
      }
      if (first is! SvgPath || brush.effectiveFillOpacity != 1) {
        return null;
      }
      final rectangle = _TileRectangle();
      try {
        writeSvgPathDataToPath(first.d, rectangle);
      } on StateError {
        return null;
      }
      return rectangle.matches(width, height) ? brush.fill?.color : null;
    }
    return null;
  }

  /// Tiles already built, by the matrix that places them
  final _tiles = <String, PdfTilingPattern>{};

  PdfGraphicXObject? _content;

  PdfTilingPattern? _empty;

  bool _painting = false;

  @override
  bool get isEmpty => false;

  @override
  SvgColor merge(SvgColor other) => other.isEmpty ? this : other;

  /// The cell drawing, written once for every tile that repeats it
  PdfGraphicXObject _paintContent() {
    // Isolated, so a viewer applying an opacity per object blends the cell as one
    final content = PdfGraphicXObject(painter.document, '/Form')
      ..isolatedTransparency = true;
    content.params['/BBox'] = PdfArray.fromNum([0, 0, width, height]);
    final tile = PdfGraphics(content, content.buf);
    _painting = true;
    painter.linkDefinitionDepth++;
    try {
      for (final child in children) {
        child.paint(tile);
      }
    } finally {
      painter.linkDefinitionDepth--;
      _painting = false;
    }
    return content;
  }

  /// A tile that paints nothing, for a cell that reaches itself or has no area
  PdfTilingPattern _emptyTile() => _empty ??= PdfTilingPattern(
        painter.document,
        boundingBox: PdfRect(0, 0, width, height),
        matrix: Matrix4.identity(),
      );

  PdfTilingPattern _build(PdfGraphics canvas) {
    // The tracked transform is from the stream's default space, where a pattern matrix lands
    final matrix = canvas.getTransform();
    if (transform.isNotEmpty) {
      matrix.multiply(transform.matrix!);
    }
    matrix.translate(x, y);

    if (_painting || matrix.determinant() == 0) {
      return _emptyTile();
    }

    final s = matrix.storage;
    final key = '${s[0]} ${s[1]} ${s[4]} ${s[5]} ${s[12]} ${s[13]}';
    final cached = _tiles[key];
    if (cached != null) {
      return cached;
    }

    final content = _content ??= _paintContent();
    return _tiles[key] = PdfTilingPattern(
      painter.document,
      boundingBox: PdfRect(0, 0, width, height),
      matrix: matrix,
      content: content,
    );
  }

  @override
  void setFillColor(SvgOperation op, PdfGraphics canvas) {
    canvas.setFillPattern(_build(canvas));
  }

  @override
  void setStrokeColor(SvgOperation op, PdfGraphics canvas) {
    canvas.setStrokePattern(_build(canvas));
  }

  @override
  String toString() =>
      '$runtimeType x:$x y:$y width:$width height:$height transform:${transform.matrix}';
}

class _TileRectangle implements PathProxy {
  final _points = <(double, double)>[];
  bool _valid = true;
  bool _closed = false;

  @override
  void moveTo(double x, double y) {
    _valid = _points.isEmpty;
    lineTo(x, y);
  }

  @override
  void lineTo(double x, double y) {
    if (_closed || _points.length == 5) {
      _valid = false;
    }
    if (_valid) {
      _points.add((x, y));
    }
  }

  @override
  void cubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    _valid = false;
  }

  @override
  void close() => _closed = true;

  bool matches(double width, double height) {
    if (!_valid || _points.length < 4) {
      return false;
    }
    if (_points.length == 5 && _points.last != _points.first) {
      return false;
    }
    final corners = {(0.0, 0.0), (width, 0.0), (width, height), (0.0, height)};
    for (var i = 0; i < 4; i++) {
      final point = _points[i];
      final next = _points[(i + 1) % 4];
      if (!corners.remove(point) ||
          (point.$1 != next.$1 && point.$2 != next.$2)) {
        return false;
      }
    }
    return true;
  }
}
