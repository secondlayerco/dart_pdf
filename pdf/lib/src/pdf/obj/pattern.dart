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

import 'package:vector_math/vector_math_64.dart';

import '../document.dart';
import '../format/array.dart';
import '../format/dict.dart';
import '../format/dict_stream.dart';
import '../format/num.dart';
import '../format/stream.dart';
import '../graphic_state.dart';
import '../graphics.dart';
import '../rect.dart';
import 'graphic_stream.dart';
import 'object.dart';
import 'shading.dart';

abstract class PdfPattern extends PdfObject<PdfDict> {
  PdfPattern(PdfDocument pdfDocument, this.patternType, this.matrix)
      : super(pdfDocument, params: PdfDict());

  /// Name of the Pattern object
  String get name => '/P$objser';

  final int patternType;

  final Matrix4? matrix;

  @override
  void prepare() {
    super.prepare();

    params['/PatternType'] = PdfNum(patternType);

    if (matrix != null) {
      final s = matrix!.storage;
      params['/Matrix'] =
          PdfArray.fromNum(<double>[s[0], s[1], s[4], s[5], s[12], s[13]]);
    }
  }
}

class PdfShadingPattern extends PdfPattern {
  PdfShadingPattern(
    PdfDocument pdfDocument, {
    required this.shading,
    Matrix4? matrix,
    this.graphicState,
  }) : super(pdfDocument, 2, matrix);

  final PdfShading shading;

  final PdfGraphicState? graphicState;

  @override
  void prepare() {
    super.prepare();

    params['/Shading'] = shading.ref();

    if (graphicState != null) {
      params['/ExtGState'] = graphicState!.output();
    }
  }
}

/// Colored tiling pattern (PatternType 1, PaintType 1, TilingType 1) whose
/// cell is a content stream with its own resources
class PdfTilingPattern extends PdfPattern with PdfGraphicStream {
  PdfTilingPattern(
    PdfDocument pdfDocument, {
    required PdfRect boundingBox,
    required Matrix4 matrix,
  })  : xStep = boundingBox.width,
        yStep = boundingBox.height,
        super(pdfDocument, 1, matrix) {
    params['/BBox'] = PdfArray.fromNum([
      boundingBox.x,
      boundingBox.y,
      boundingBox.right,
      boundingBox.top,
    ]);
    _graphics = PdfGraphics(this, buf);
  }

  /// Horizontal spacing between pattern cells, in pattern space
  final double xStep;

  /// Vertical spacing between pattern cells, in pattern space
  final double yStep;

  /// This holds the cell's content.
  final PdfStream buf = PdfStream();

  late final PdfGraphics _graphics;

  /// Canvas drawing the cell, in pattern space
  PdfGraphics getGraphics() => _graphics;

  @override
  void prepare() {
    super.prepare();

    params['/PaintType'] = const PdfNum(1);
    params['/TilingType'] = const PdfNum(1);
    params['/XStep'] = PdfNum(xStep);
    params['/YStep'] = PdfNum(yStep);
    // A pattern dictionary has no transparency group entry
    params.values.remove('/Group');
    if (!params.containsKey('/Resources')) {
      params['/Resources'] = PdfDict();
    }
  }

  @override
  void writeContent(PdfStream s) {
    PdfDictStream(
      values: params.values,
      data: buf.output(),
    ).output(this, s, settings.verbose ? 0 : null);
    s.putByte(0x0a);
  }
}
