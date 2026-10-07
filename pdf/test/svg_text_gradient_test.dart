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

import 'dart:convert';

import 'package:pdf/widgets.dart';
import 'package:test/test.dart';

import 'utils.dart';

// Napkin update: a gradient on SVG text is placed in the text element's user
// space, as on a path, and its stop-opacity mask covers the glyphs there
void main() {
  final font = loadFont('open-sans.ttf');

  Future<String> pdfOf(String body) async {
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" width="400" height="300">$body</svg>';
    final pdf = Document(compress: false)
      ..addPage(
          Page(build: (context) => SvgImage(svg: svg, defaultFont: font)));
    return latin1.decode(await pdf.save());
  }

  String gradient([String lastStop = '']) =>
      '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="200" y2="0">'
      '<stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff" $lastStop/>'
      '</linearGradient></defs>';

  group('SVG text gradients ::', () {
    test('every line of a label takes the gradient where its path sibling does',
        () async {
      final pdf = await pdfOf('${gradient()}'
          '<g transform="translate(20,40)">'
          '<path d="M0 0H200V40H0Z" fill="url(#g)"/>'
          '<text fill="url(#g)" stroke="url(#g)" stroke-width="1" font-size="30">'
          '<tspan x="100" y="90" text-anchor="middle">Hello world</tspan>'
          '<tspan x="100" y="130" text-anchor="middle">Second line</tspan>'
          '</text></g>');

      final matrices = RegExp(r'/PatternType 2/Matrix\[([^\]]*)\]')
          .allMatches(pdf)
          .map((m) => m.group(1)!)
          .toList();
      expect(matrices.length, 5,
          reason: 'path fill, two line fills and two line strokes; '
              'the glyph-less text wrapper builds none');
      expect(matrices.toSet(), {matrices.first},
          reason: 'the path and both lines share one user space');
    });

    test('a translucent stop on text masks over the glyphs, in the text space',
        () async {
      final pdf = await pdfOf('${gradient('stop-opacity="0.25"')}'
          '<text fill="url(#g)" font-size="30" x="120" y="200">Masked</text>');

      // The rectangle a soft mask form fills, as x, y, width, height.
      final masks = RegExp(
              r'([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) re\s*/Pattern cs\s*/P\d+ scn\s*f')
          .allMatches(pdf)
          .toList();
      expect(masks.length, 1);
      final box = masks.single
          .groups([1, 2, 3, 4])
          .map((g) => double.parse(g!))
          .toList();
      expect(box[0], closeTo(120, 5), reason: 'starts where the text starts');
      expect(box[1], inInclusiveRange(200 - 35, 200 - 15),
          reason: 'its top sits above the baseline by the ascent');
      expect(box[2], greaterThan(60));
      expect(box[3], inInclusiveRange(20, 45));
    });
  });
}
