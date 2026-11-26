import 'dart:math' as math;

import 'package:path_parsing/path_parsing.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../pdf.dart';
import 'path.dart';

class SvgLinkClip {
  SvgLinkClip(this._path, this._pageTransform);

  final SvgPath _path;
  final Matrix4 _pageTransform;

  // Most clipped shapes contain no linked text.
  late final List<Vector2>? outline = _outline();

  List<Vector2>? _outline() {
    final transform = _pageTransform.clone();
    final local = _path.transform.matrix;
    if (local != null) {
      transform.multiply(local);
    }
    final outline = _ConvexOutline(transform);
    try {
      writeSvgPathDataToPath(_path.d, outline);
    } on StateError {
      return null;
    }
    return outline.vertices;
  }
}

Vector2 _placed(Matrix4 matrix, double x, double y) {
  final p = matrix.transform3(Vector3(x, y, 0));
  return Vector2(p.x, p.y);
}

class _ConvexOutline extends PathProxy {
  _ConvexOutline(this._transform);

  static const _tolerance = .125; // PDF page points.
  static const _samePointDistance = _tolerance / 64;
  static const _samePointDistance2 = _samePointDistance * _samePointDistance;
  static const _maxVertices = 1024;
  final Matrix4 _transform;
  final _vertices = <Vector2>[];
  bool _singleOutline = true;
  bool _closed = false;

  @override
  void moveTo(double x, double y) {
    if (_vertices.isNotEmpty) {
      _singleOutline = false;
    }
    lineTo(x, y);
  }

  @override
  void lineTo(double x, double y) {
    if (_singleOutline) {
      _append(_placed(_transform, x, y));
    }
  }

  void _append(Vector2 point) {
    if (_closed ||
        _vertices.length == _maxVertices ||
        !point.x.isFinite ||
        !point.y.isFinite) {
      _singleOutline = false;
    } else if (_vertices.isEmpty ||
        point.distanceToSquared(_vertices.last) > _samePointDistance2) {
      _vertices.add(point);
    }
  }

  @override
  void cubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    if (!_singleOutline || _vertices.isEmpty) {
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
    if (!_singleOutline) {
      return;
    }
    if (_nearChord(b, a, d) && _nearChord(c, a, d)) {
      _append(d);
      return;
    }
    if (depth == 12) {
      _singleOutline = false;
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
  void close() => _closed = true;

  List<Vector2>? get vertices {
    if (!_singleOutline) {
      return null;
    }
    if (_vertices.length > 1 &&
        _vertices.first.distanceToSquared(_vertices.last) <=
            _samePointDistance2) {
      _vertices.removeLast();
    }
    if (_vertices.length < 3) {
      return [];
    }
    final sign = _area(_vertices).sign;
    var turning = 0.0;
    for (var i = 0; i < _vertices.length; i++) {
      final a = _vertices[i];
      final b = _vertices[(i + 1) % _vertices.length];
      final c = _vertices[(i + 2) % _vertices.length];
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
    return (turning.abs() - 2 * math.pi).abs() < 1e-6 ? _vertices : null;
  }
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
  var appliedClip = false;
  for (final clip in clips) {
    final outline = clip.outline;
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
