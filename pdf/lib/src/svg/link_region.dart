import 'dart:math' as math;

import 'package:path_parsing/path_parsing.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../pdf.dart';
import 'color.dart';
import 'group.dart';
import 'operation.dart';
import 'path.dart';

typedef _Interval = ({double left, double right});
typedef _Crossing = ({double x, int winding});

class SvgLinkClip {
  SvgLinkClip(this._children, this._pageTransform,
      {this.evenOdd = false,
      this.mask = false,
      this.alphaMask = false,
      this.regionCorners});

  final Iterable<SvgOperation> _children;
  final Matrix4 _pageTransform;
  final bool evenOdd;
  final bool mask;
  final bool alphaMask;
  final List<Vector2>? regionCorners;

  late final _regionShape =
      regionCorners == null ? null : _LinkShape([regionCorners!], false);

  // Build the geometry only when linked text is drawn under this clip.
  late final List<_LinkShape>? _geometry = _shapes();

  List<_LinkShape>? _shapes() {
    final result = <_LinkShape>[];
    var vertexCount = 0;
    bool collect(SvgOperation operation, Matrix4 parent) {
      final transform = parent.clone();
      final local = operation.transform.matrix;
      if (local != null) {
        transform.multiply(local);
      }
      final brush = operation.brush;
      if (mask && (brush.opacity == 0 || transform.determinant() == 0)) {
        return true;
      }
      if (mask &&
          (brush.mask != null ||
              operation.clip.isNotEmpty ||
              brush.blendMode != null)) {
        return false;
      }
      if (operation is SvgGroup) {
        return (!mask || brush.opacity == 1) &&
            operation.children.every((child) => collect(child, transform));
      }
      if (operation is! SvgPath || (mask && brush.stroke!.isNotEmpty)) {
        return false;
      }
      final color = brush.fill?.color;
      final opacity = brush.effectiveFillOpacity * (brush.opacity ?? 1);
      if (mask && (color == null || opacity == 0)) {
        return opacity == 0 || identical(brush.fill, SvgColor.none);
      }
      final black = !alphaMask &&
          color?.red == 0 &&
          color?.green == 0 &&
          color?.blue == 0;
      if (mask && black && opacity < 1) {
        return true;
      }
      final outline = _PathOutline(transform);
      try {
        writeSvgPathDataToPath(operation.d, outline);
      } on StateError {
        return false;
      }
      final contours = outline.contours;
      if (contours == null) {
        return false;
      }
      vertexCount +=
          contours.fold(0, (count, contour) => count + contour.length);
      if (vertexCount > 2048) {
        return false;
      }
      result.add(_LinkShape(contours, mask && brush.fillEvenOdd == true,
          subtract: mask && black));
      return true;
    }

    return _children.every((operation) => collect(operation, _pageTransform))
        ? result
        : null;
  }

  List<_Interval> _at(double y) {
    final paths = _geometry!;
    if (!mask) {
      return _intervals(paths.expand((path) => path.crossings(y)), evenOdd);
    }

    var visible = <_Interval>[];
    for (final path in paths) {
      final painted = _intervals(path.crossings(y), path.evenOdd);
      visible = path.subtract
          ? _subtract(visible, painted)
          : _union(visible, painted);
    }
    final region = _regionShape;
    return region == null
        ? visible
        : _intersect(visible, _intervals(region.crossings(y), false));
  }

  List<Vector2>? get _convexOutline {
    final geometry = _geometry;
    if (mask ||
        geometry == null ||
        geometry.length != 1 ||
        geometry.single.contours.length != 1) {
      return null;
    }
    return _convex(geometry.single.contours.single);
  }
}

class _LinkShape {
  _LinkShape(this.contours, this.evenOdd, {this.subtract = false});

  final List<List<Vector2>> contours;
  final bool evenOdd;
  final bool subtract;

  bool get axisAligned => contours.every((contour) {
        for (var i = 0; i < contour.length; i++) {
          final a = contour[i];
          final b = contour[(i + 1) % contour.length];
          if ((a.x - b.x).abs() > 1e-8 && (a.y - b.y).abs() > 1e-8) {
            return false;
          }
        }
        return true;
      });

  Iterable<_Crossing> crossings(double y) sync* {
    for (final contour in contours) {
      var a = contour.last;
      for (final b in contour) {
        if ((a.y <= y) != (b.y <= y)) {
          yield (
            x: a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x),
            winding: a.y < b.y ? 1 : -1
          );
        }
        a = b;
      }
    }
  }
}

List<_Interval> _intervals(Iterable<_Crossing> crossings, bool evenOdd) {
  final ordered = crossings.toList()..sort((a, b) => a.x.compareTo(b.x));
  final result = <_Interval>[];
  var winding = 0;
  var left = 0.0;
  for (final crossing in ordered) {
    final inside = winding != 0;
    winding += evenOdd ? (inside ? -1 : 1) : crossing.winding;
    if (!inside && winding != 0) {
      left = crossing.x;
    } else if (inside && winding == 0 && crossing.x > left) {
      if (result.isNotEmpty && result.last.right == left) {
        left = result.removeLast().left;
      }
      result.add((left: left, right: crossing.x));
    }
  }
  return result;
}

List<_Interval> _union(List<_Interval> first, List<_Interval> second) {
  return _intervals([
    for (final interval in [...first, ...second]) ...[
      (x: interval.left, winding: 1),
      (x: interval.right, winding: -1),
    ],
  ], false);
}

List<_Interval> _intersect(List<_Interval> first, List<_Interval> second) {
  final intersections = <_Interval>[];
  var other = 0;
  for (final a in first) {
    while (other < second.length && second[other].right <= a.left) {
      other++;
    }
    for (var i = other; i < second.length && second[i].left < a.right; i++) {
      final b = second[i];
      final left = math.max(a.left, b.left);
      final right = math.min(a.right, b.right);
      if (right > left) {
        intersections.add((left: left, right: right));
      }
    }
  }
  return intersections;
}

List<_Interval> _subtract(List<_Interval> first, List<_Interval> second) {
  final result = <_Interval>[];
  for (final a in first) {
    var left = a.left;
    for (final b in second) {
      if (b.right <= left) {
        continue;
      }
      if (b.left >= a.right) {
        break;
      }
      if (b.left > left) {
        result.add((left: left, right: b.left));
      }
      left = math.max(left, b.right);
    }
    if (left < a.right) {
      result.add((left: left, right: a.right));
    }
  }
  return result;
}

Vector2 _placed(Matrix4 matrix, double x, double y) {
  final p = matrix.transform3(Vector3(x, y, 0));
  return Vector2(p.x, p.y);
}

class _PathOutline extends PathProxy {
  _PathOutline(this._transform);

  static const _tolerance = .125; // PDF page points.
  static const _samePointDistance = _tolerance / 64;
  static const _samePointDistance2 = _samePointDistance * _samePointDistance;
  static const _maxVertices = 1024;
  final Matrix4 _transform;
  final _contours = <List<Vector2>>[];
  var _vertices = <Vector2>[];
  var _vertexCount = 0;
  var _valid = true;

  @override
  void moveTo(double x, double y) {
    _finishContour();
    lineTo(x, y);
  }

  @override
  void lineTo(double x, double y) => _append(_placed(_transform, x, y));

  void _append(Vector2 point) {
    if (!_valid ||
        _vertexCount == _maxVertices ||
        !point.x.isFinite ||
        !point.y.isFinite) {
      _valid = false;
    } else if (_vertices.isEmpty ||
        point.distanceToSquared(_vertices.last) > _samePointDistance2) {
      _vertices.add(point);
      _vertexCount++;
    }
  }

  @override
  void cubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    if (!_valid || _vertices.isEmpty) {
      return;
    }
    _flatten(
      _vertices.last,
      _placed(_transform, x1, y1),
      _placed(_transform, x2, y2),
      _placed(_transform, x3, y3),
      0,
    );
  }

  static bool _nearChord(Vector2 point, Vector2 a, Vector2 b) {
    final chord = b - a;
    final lengthSquared = chord.length2;
    final projection = lengthSquared == 0
        ? 0.0
        : ((point - a).dot(chord) / lengthSquared).clamp(0.0, 1.0);
    return (point - (a + chord * projection)).length2 <=
        _tolerance * _tolerance;
  }

  void _flatten(Vector2 a, Vector2 b, Vector2 c, Vector2 d, int depth) {
    if (!_valid) {
      return;
    }
    if (_nearChord(b, a, d) && _nearChord(c, a, d)) {
      _append(d);
      return;
    }
    if (depth == 12) {
      _valid = false;
      return;
    }
    final ab = (a + b) * .5;
    final bc = (b + c) * .5;
    final cd = (c + d) * .5;
    final abc = (ab + bc) * .5;
    final bcd = (bc + cd) * .5;
    final midpoint = (abc + bcd) * .5;
    _flatten(a, ab, abc, midpoint, depth + 1);
    _flatten(midpoint, bcd, cd, d, depth + 1);
  }

  @override
  void close() => _finishContour();

  void _finishContour() {
    if (_vertices.length >= 3) {
      _contours.add(_vertices);
    }
    _vertices = [];
  }

  List<List<Vector2>>? get contours {
    _finishContour();
    return _valid ? _contours : null;
  }
}

List<Vector2>? _convex(List<Vector2> contour) {
  final vertices = [...contour];
  if (vertices.length > 1 &&
      vertices.first.distanceToSquared(vertices.last) <= 1e-8) {
    vertices.removeLast();
  }
  if (vertices.length < 3) {
    return [];
  }
  final sign = _area(vertices).sign;
  var turning = 0.0;
  for (var i = 0; i < vertices.length; i++) {
    final a = vertices[i];
    final b = vertices[(i + 1) % vertices.length];
    final c = vertices[(i + 2) % vertices.length];
    final incoming = b - a;
    final outgoing = c - b;
    final cross = incoming.cross(outgoing);
    final noise = 1e-10 * incoming.length * outgoing.length;
    if ((sign == 0 && cross.abs() > noise) || sign * cross < -noise) {
      return null;
    }
    turning += math.atan2(cross, incoming.dot(outgoing));
  }
  if (sign == 0) {
    return [];
  }
  return (turning.abs() - 2 * math.pi).abs() < 1e-6 ? vertices : null;
}

double _area(List<Vector2> polygon) {
  var area = 0.0;
  for (var i = 1; i + 1 < polygon.length; i++) {
    area += (polygon[i] - polygon.first).cross(polygon[i + 1] - polygon.first);
  }
  return area / 2;
}

List<Vector2> _intersection(List<Vector2> polygon, List<Vector2> clip) {
  final sign = _area(clip).sign;
  if (sign == 0) {
    return [];
  }
  for (var i = 0; i < clip.length && polygon.isNotEmpty; i++) {
    final a = clip[i];
    final side = clip[(i + 1) % clip.length] - a;
    double distance(Vector2 point) => sign * side.cross(point - a);
    final inside = <Vector2>[];
    var previous = polygon.last;
    var before = distance(previous);
    for (final point in polygon) {
      final after = distance(point);
      if (before * after < 0) {
        inside.add(previous + (point - previous) * (before / (before - after)));
      }
      if (after >= 0) {
        inside.add(point);
      }
      previous = point;
      before = after;
    }
    polygon = inside;
  }
  return polygon;
}

/// A PDF link uses quadrilaterals for active areas whose enclosing rectangle includes clipped corners.
void addSvgTextLink(PdfPage page, String url, Matrix4 transform, double width,
    double bottom, double top, List<SvgLinkClip> clips) {
  var visible = [
    _placed(transform, 0, bottom),
    _placed(transform, width, bottom),
    _placed(transform, width, top),
    _placed(transform, 0, top),
  ];
  final shape = _LinkShape([visible], false);
  if (clips.isNotEmpty &&
      shape.axisAligned &&
      clips.every((clip) =>
          (clip._geometry?.every((path) => path.axisAligned) ?? false) &&
          (clip._regionShape?.axisAligned ?? true))) {
    final rectangles = _orthogonalRectangles(shape, clips);
    if (rectangles.length <= 8) {
      for (final rect in rectangles) {
        PdfAnnot(page, PdfAnnotUrlLink(rect: rect, url: url));
      }
    } else {
      final first = rectangles.first;
      final box = Aabb2.minMax(
          Vector2(first.left, first.bottom), Vector2(first.right, first.top));
      final quads = <PdfPoint>[];
      for (final rect in rectangles) {
        box.hullPoint(Vector2(rect.left, rect.bottom));
        box.hullPoint(Vector2(rect.right, rect.top));
        quads.addAll([
          PdfPoint(rect.left, rect.bottom),
          PdfPoint(rect.right, rect.bottom),
          PdfPoint(rect.right, rect.top),
          PdfPoint(rect.left, rect.top),
        ]);
      }
      PdfAnnot(
          page,
          PdfAnnotUrlLink(
            rect: PdfRect.fromLTRB(box.min.x, box.min.y, box.max.x, box.max.y),
            url: url,
            quadPoints: quads,
          ));
    }
    return;
  }
  var appliedClip = false;
  for (final clip in clips) {
    final outline = clip._convexOutline ?? clip.regionCorners;
    if (outline == null) {
      continue;
    }
    appliedClip = true;
    visible = _intersection(visible, outline);
    if (visible.length < 3) {
      return;
    }
  }
  final area = _area(visible);
  if (area.abs() < 1e-9) {
    return;
  }
  if (area < 0) {
    visible = visible.reversed.toList();
  }
  final bounds = Aabb2.minMax(visible.first, visible.first);
  visible.skip(1).forEach(bounds.hullPoint);
  final rect =
      PdfRect.fromLTRB(bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y);
  List<PdfPoint>? quads;
  if (appliedClip && (rect.width * rect.height - area.abs()) > 1e-8) {
    if (visible.length == 4) {
      quads = [for (final p in visible) PdfPoint(p.x, p.y)];
    } else {
      // Each edge midpoint and the center split a convex intersection into four-sided regions.
      final center =
          visible.reduce((a, b) => a + b) / visible.length.toDouble();
      final midpoints = [
        for (var i = 0; i < visible.length; i++)
          (visible[i] + visible[(i + 1) % visible.length]) * .5
      ];
      quads = [
        for (var i = 0; i < visible.length; i++)
          for (final p in [
            visible[i],
            midpoints[i],
            center,
            midpoints[(i + visible.length - 1) % visible.length]
          ])
            PdfPoint(p.x, p.y)
      ];
    }
  }
  PdfAnnot(page, PdfAnnotUrlLink(rect: rect, url: url, quadPoints: quads));
}

List<PdfRect> _orthogonalRectangles(_LinkShape shape, List<SvgLinkClip> clips) {
  final points = shape.contours.single;
  final bottom = points.map((point) => point.y).reduce(math.min);
  final top = points.map((point) => point.y).reduce(math.max);
  if (top <= bottom) {
    return [];
  }
  final edges = <double>{bottom, top};
  for (final clip in clips) {
    for (final path in [
      ...clip._geometry!,
      if (clip._regionShape != null) clip._regionShape!
    ]) {
      for (final contour in path.contours) {
        for (final point in contour) {
          if (bottom < point.y && point.y < top) {
            edges.add(point.y);
          }
        }
      }
    }
  }
  final boundaries = edges.toList()..sort();
  final rectangles = <PdfRect>[];
  var open = <_Interval, double>{};
  for (var i = 0; i + 1 < boundaries.length; i++) {
    final low = boundaries[i];
    final y = low + (boundaries[i + 1] - low) / 2;
    var visible = _intervals(shape.crossings(y), false);
    for (final clip in clips) {
      visible = _intersect(visible, clip._at(y));
      if (visible.isEmpty) {
        break;
      }
    }
    final next = <_Interval, double>{
      for (final interval in visible) interval: open.remove(interval) ?? low,
    };
    for (final entry in open.entries) {
      rectangles.add(
          PdfRect.fromLTRB(entry.key.left, entry.value, entry.key.right, low));
    }
    open = next;
  }
  for (final entry in open.entries) {
    rectangles.add(
        PdfRect.fromLTRB(entry.key.left, entry.value, entry.key.right, top));
  }
  return rectangles;
}
