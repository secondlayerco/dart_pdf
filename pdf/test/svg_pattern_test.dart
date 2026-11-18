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
import 'dart:io';

import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  Future<List<int>> save(String body, {String viewBox = '0 0 400 300'}) {
    final size = viewBox.split(' ').map(double.parse).toList();
    final pdf = Document(compress: false)
      ..addPage(Page(
          pageFormat: PdfPageFormat(size[2], size[3]),
          margin: EdgeInsets.zero,
          build: (context) => SvgImage(
              defaultFont: loadFont('open-sans.ttf'),
              svg:
                  '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="$viewBox">$body</svg>')));
    return pdf.save();
  }

  Future<String> pdfOf(String body) async => latin1.decode(await save(body));

  // The tiling patterns of a PDF, dictionary and stream together
  List<String> tilingPatterns(String pdf) => pdf
      .split('endobj')
      .where((object) => object.contains('/PatternType 1'))
      .toList();

  List<double> numbers(String object, String key) {
    final values = RegExp('$key\\[([^\\]]*)\\]').firstMatch(object)!.group(1)!;
    return values.trim().split(RegExp(r'\s+')).map(double.parse).toList();
  }

  String pattern(String attributes, String content, {String id = 'p'}) =>
      '<pattern id="$id" patternUnits="userSpaceOnUse" '
      'patternContentUnits="userSpaceOnUse" overflow="hidden" $attributes>'
      '$content</pattern>';

  Future<im.Image> raster(String body) async {
    final directory = await Directory.systemTemp.createTemp('pdf-svg-pattern-');
    try {
      final file = File('${directory.path}/pattern.pdf');
      await file.writeAsBytes(await save(body, viewBox: '0 0 320 160'));
      final result = await Process.run(
          Platform.environment['PDF_RASTERIZER'] ?? 'pdftoppm', [
        '-r',
        '72',
        '-png',
        '-singlefile',
        file.path,
        '${directory.path}/pattern'
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      return im.decodePng(
          await File('${directory.path}/pattern.png').readAsBytes())!;
    } finally {
      await directory.delete(recursive: true);
    }
  }

  group('SVG pattern fills ::', () {
    test('a pattern becomes one tiling pattern placed in page space', () async {
      final pdf = await pdfOf('<defs>'
          '${pattern('x="2" y="3" width="12" height="8" patternTransform="translate(5 7) rotate(90)"', '<rect width="6" height="8" fill="#ff0000"/>')}'
          '</defs>'
          '<g transform="translate(10 20) scale(2 3)">'
          '<path d="M0 0H50V50H0Z" fill="url(#p)"/>'
          '<path d="M60 0H90V50H60Z" fill="url(#p)"/></g>');

      final tiles = tilingPatterns(pdf);
      expect(tiles.length, 1, reason: 'both paths are placed alike');
      final tile = tiles.single;
      expect(tile, contains('/PaintType 1'));
      expect(tile, contains('/TilingType 1'));
      expect(numbers(tile, '/BBox'), [0, 0, 12, 8]);
      expect(tile, contains('/XStep 12'));
      expect(tile, contains('/YStep 8'));
      expect(tile, contains('/Resources'));

      // Tile point (u, v) lands on page (14 - 2v, 253 - 3u): tile origin, pattern, group, flip
      final matrix = numbers(tile, '/Matrix');
      for (final (i, expected) in [0, -3, -2, 0, 14, 253].indexed) {
        expect(matrix[i], closeTo(expected, 1e-3));
      }

      expect(RegExp(r'/Pattern cs\s*/P\d+ scn').allMatches(pdf).length, 2);
      expect('1 0 0 rg'.allMatches(tile).length, 1,
          reason: 'the tile is drawn once, not once per repeat');
    });

    test('a pattern in another pattern is placed in its tile, not the page',
        () async {
      final pdf = await pdfOf('<defs>'
          '${pattern('width="10" height="10" patternTransform="scale(2)"', '<rect width="5" height="10" fill="#0000ff"/>', id: 'inner')}'
          '${pattern('width="40" height="30" patternTransform="translate(7 9)"', '<rect width="30" height="20" fill="url(#inner)"/>', id: 'outer')}'
          '</defs>'
          '<g transform="translate(100 50)"><path d="M0 0H80V60H0Z" fill="url(#outer)"/></g>');

      final tiles = tilingPatterns(pdf);
      expect(tiles.length, 2);
      final outer = tiles.firstWhere((t) => t.contains('/XStep 40'));
      final inner = tiles.firstWhere((t) => t.contains('/XStep 10'));
      expect(numbers(outer, '/Matrix'), [1, 0, 0, -1, 107, 241]);
      expect(numbers(inner, '/Matrix'), [2, 0, 0, 2, 0, 0],
          reason: 'a tile is its own space, so no page flip');
      final innerName =
          RegExp(r'/Pattern<</(P\d+)').firstMatch(outer)?.group(1);
      expect(innerName, isNotNull);
      expect(inner, isNot(contains('/$innerName ')));
      expect(RegExp('/Pattern cs\\s*/$innerName scn').hasMatch(outer), isTrue);
    });

    test('opacity and strokes apply to a pattern', () async {
      final pdf = await pdfOf('<defs>'
          '${pattern('width="10" height="10"', '<rect width="5" height="10" fill="#00ff00"/><rect x="2" width="5" height="10" fill="#0000ff"/>')}'
          '</defs>'
          '<path d="M10 10H90V90H10Z" fill="none" stroke="url(#p)" stroke-width="12" stroke-opacity=".5"/>'
          '<path d="M110 10H190V90H110Z" fill="url(#p)" fill-opacity=".25"/>'
          '<path d="M210 10H290V90H210Z" fill="url(#p)"/>');

      expect(RegExp(r'/Pattern CS\s*/P\d+ SCN').hasMatch(pdf), isTrue);
      expect(
          RegExp(r'/Pattern cs\s*/P\d+ scn\s*/a\d+ gs').hasMatch(pdf), isTrue);
      expect(pdf, contains('/CA 0.5/ca 0.5'));
      expect(pdf, contains('/CA 0.25/ca 0.25'));

      final tiles = tilingPatterns(pdf);
      expect(tiles.length, 2,
          reason: 'one translucent tile shared, one opaque');
      final grouped = tiles.where((t) => t.contains('/XObject<<'));
      expect(grouped.length, 1,
          reason: 'a translucent tile blends as one group');
    });

    test('tile content keeps its own fonts and images', () async {
      final bitmap = im.Image(width: 2, height: 2, numChannels: 4);
      im.fill(bitmap, color: im.ColorRgba8(255, 0, 0, 255));
      final source = base64Encode(im.encodePng(bitmap));
      final pdf = await pdfOf('<defs>'
          '${pattern('width="60" height="30"', '<text x="2" y="20" font-size="14" fill="#000">Tile</text><image x="40" y="5" width="10" height="10" xlink:href="data:image/png;base64,$source"/>')}'
          '</defs>'
          '<path d="M0 0H200V100H0Z" fill="url(#p)"/>');

      final tile = tilingPatterns(pdf).single;
      expect(tile, contains('BT'));
      expect(tile, contains('/Font<<'));
      expect(tile, contains('/XObject<<'));
      final page =
          pdf.split('endobj').firstWhere((o) => o.contains('/Type/Page/'));
      expect(page, isNot(contains('/Font')));
    });

    test('tiles land where a browser puts them, scaled and rotated', () async {
      // Cells are 20 wide, red for 10 then blue for 10, shifted right by 5
      final image = await raster('<defs>'
          '${pattern('width="20" height="20" patternTransform="translate(5 0)"', '<rect width="10" height="20" fill="#ff0000"/><rect x="10" width="10" height="20" fill="#0000ff"/>')}'
          '</defs>'
          '<g transform="translate(100 0)"><rect width="100" height="40" fill="url(#p)"/></g>'
          '<g transform="translate(0 60) scale(2 1)"><rect width="50" height="40" fill="url(#p)"/></g>'
          '<g transform="translate(300 0) rotate(90)"><rect width="100" height="40" fill="url(#p)"/></g>');

      String colorAt(int x, int y) {
        final pixel = image.getPixel(x, y);
        return pixel.r > 200 && pixel.b < 60
            ? 'red'
            : pixel.b > 200 && pixel.r < 60
                ? 'blue'
                : 'other';
      }

      // Colors change at 5, 15 and 25 from the group origin
      expect([102, 110, 120, 130].map((x) => colorAt(x, 20)),
          ['blue', 'red', 'blue', 'red']);
      // Under scale(2 1) the stripes are twice as wide
      expect([5, 20, 40, 60].map((x) => colorAt(x, 80)),
          ['blue', 'red', 'blue', 'red']);
      // Under rotate(90) the stripes run along the page height
      expect([2, 10, 20, 30].map((y) => colorAt(280, y)),
          ['blue', 'red', 'blue', 'red']);
    });

    test('a pattern that cannot be tiled draws nothing and breaks nothing',
        () async {
      final pdf = await pdfOf('<defs>'
          '${pattern('width="0" height="10"', '<rect width="5" height="5"/>', id: 'flat')}'
          '${pattern('height="10"', '<rect width="5" height="5"/>', id: 'nowidth')}'
          '${pattern('width="10" height="10" patternTransform="scale(0)"', '<rect width="5" height="5"/>', id: 'singular')}'
          '<pattern id="boxUnits" width="0.5" height="0.5"><rect width="5" height="5"/></pattern>'
          '</defs>'
          '<path d="M0 0H10V10H0Z" fill="url(#flat)" stroke="#ff0000"/>'
          '<path d="M20 0H30V10H20Z" fill="url(#nowidth)" stroke="#ff0000"/>'
          '<path d="M40 0H50V10H40Z" fill="url(#singular)" stroke="#ff0000"/>'
          '<path d="M60 0H70V10H60Z" fill="url(#boxUnits)" stroke="#ff0000"/>');

      expect(pdf, isNot(contains('/Pattern cs')));
      expect('1 0 0 RG'.allMatches(pdf).length, 4,
          reason: 'every path still strokes');
    });

    test('a pattern that paints itself ends with an empty tile', () async {
      final pdf = await pdfOf('<defs>'
          '${pattern('width="10" height="10"', '<rect width="5" height="5" fill="url(#p)"/><rect width="5" height="5" stroke="#ff0000"/>')}'
          '</defs>'
          '<path d="M0 0H10V10H0Z" fill="url(#p)"/>');

      final tile = tilingPatterns(pdf).single;
      expect('1 0 0 RG'.allMatches(tile).length, 1);
      expect(tile, isNot(contains('/Pattern cs')));
    });
  });
}
