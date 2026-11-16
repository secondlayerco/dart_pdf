import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart';
import 'package:pdf/src/svg/gradient.dart';
import 'package:pdf/src/svg/painter.dart';
import 'package:pdf/src/svg/parser.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'utils.dart';

void main() {
  Future<im.Image> raster(String body, {String viewBox = '0 0 200 160'}) async {
    final directory = await Directory.systemTemp.createTemp('pdf-svg-masks-');
    try {
      final document = Document()
        ..addPage(Page(
            pageFormat: const PdfPageFormat(200, 160),
            margin: EdgeInsets.zero,
            build: (_) => SvgImage(
                defaultFont: loadFont('open-sans.ttf'),
                svg:
                    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox">$body</svg>')));
      final file = File('${directory.path}/mask.pdf');
      await file.writeAsBytes(await document.save());
      final result = await Process.run(
          Platform.environment['PDF_RASTERIZER'] ?? 'pdftoppm', [
        '-r',
        '72',
        '-png',
        '-singlefile',
        file.path,
        '${directory.path}/mask'
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stderr, isEmpty);
      return im
          .decodePng(await File('${directory.path}/mask.png').readAsBytes())!;
    } finally {
      await directory.delete(recursive: true);
    }
  }

  group('SVG mask composition ::', () {
    test('nested masks multiply gradient alpha at actual painted pixels',
        () async {
      final image = await raster('''
<defs>
 <linearGradient id="fade"><stop stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient>
 <linearGradient id="color"><stop stop-color="red" stop-opacity=".5"/><stop offset="1" stop-color="blue" stop-opacity=".5"/></linearGradient>
 <mask id="a"><rect width="100" height="100" fill="url(#fade)"/></mask>
 <mask id="b"><circle cx="50" cy="50" r="40" fill="white"/></mask>
</defs>
<g mask="url(#a)"><g mask="url(#b)"><rect width="100" height="100" fill="url(#color)"/></g></g>''');
      final left = image.getPixel(25, 50);
      final right = image.getPixel(75, 50);
      expect([left.r, left.g, left.b], orderedEquals([247, 223, 231]));
      expect([right.r, right.g, right.b], orderedEquals([183, 159, 231]));
      expect(image.getPixel(5, 50).r, 255);
    });

    test('transformed clipping and group opacity composite in their own spaces',
        () async {
      final image = await raster('''
<defs><clipPath id="c"><rect x="10" y="10" width="80" height="80"/></clipPath></defs>
<g transform="translate(50 20)" clip-path="url(#c)" opacity=".5">
 <rect width="100" height="100" fill="red"/>
 <rect x="50" width="100" height="100" fill="blue"/>
</g>''');
      final overlap = image.getPixel(120, 50);
      expect(overlap.r, inInclusiveRange(127, 128));
      expect(overlap.g, inInclusiveRange(127, 128));
      expect(overlap.b, 255);
      expect(image.getPixel(25, 50).r, 255);
      expect(image.getPixel(25, 50).g, 255);
    });

    test('mask bounds retain negative SVG coordinates', () async {
      final image = await raster('''
<defs><mask id="m"><rect x="-80" y="-60" width="100" height="100" fill="white"/></mask></defs>
<g mask="url(#m)" opacity=".6"><rect x="-80" y="-60" width="100" height="100" fill="red"/></g>''',
          viewBox: '-100 -80 200 160');
      final interior = image.getPixel(25, 25);
      expect(interior.r, 255);
      expect(interior.g, inInclusiveRange(101, 103));
      expect(interior.b, inInclusiveRange(101, 103));
      expect(image.getPixel(125, 125).g, 255);
    });

    for (final mask in [
      (
        name: 'paint opacity',
        body:
            '<rect x="-80" y="-60" width="100" height="100" fill="white" opacity=".5"/>'
      ),
      (
        name: 'group opacity',
        body:
            '<g opacity=".5"><rect x="-80" y="-60" width="100" height="100" fill="white"/></g>'
      ),
      (
        name: 'gradient alpha',
        body: '<rect x="-80" y="-60" width="100" height="100" fill="url(#f)"/>'
      ),
    ]) {
      test('negative mask coordinates retain ${mask.name}', () async {
        final image = await raster('''
<defs>
 <linearGradient id="f"><stop stop-color="white" stop-opacity=".5"/><stop offset="1" stop-color="white" stop-opacity=".5"/></linearGradient>
 <mask id="m">${mask.body}</mask>
</defs>
<g mask="url(#m)" opacity=".6"><rect x="-80" y="-60" width="100" height="100" fill="red"/></g>''',
            viewBox: '-100 -80 200 160');
        final interior = image.getPixel(25, 25);
        expect(interior.r, 255);
        expect(interior.g, inInclusiveRange(178, 180));
        expect(interior.b, inInclusiveRange(178, 180));
        expect(image.getPixel(125, 125).g, 255);
      });
    }

    test('masked images and text retain group alpha', () async {
      final bitmap = im.Image(width: 2, height: 2, numChannels: 4);
      im.fill(bitmap, color: im.ColorRgba8(255, 0, 0, 255));
      final source = base64Encode(im.encodePng(bitmap));
      final image = await raster('''
<defs><mask id="m"><rect width="100" height="100" fill="white"/></mask></defs>
<g mask="url(#m)" opacity=".5">
 <image width="100" height="50" href="data:image/png;base64,$source"/>
 <text x="10" y="85" font-size="20" fill="blue">Masked</text>
</g>''');
      final picture = image.getPixel(25, 25);
      expect(picture.r, 255);
      expect(picture.g, inInclusiveRange(127, 128));
      final glyphs = [
        for (var y = 60; y < 90; y++)
          for (var x = 10; x < 90; x++) image.getPixel(x, y)
      ].where((pixel) => pixel.r < 160 && pixel.b > 240);
      expect(glyphs, isNotEmpty);
      expect(glyphs.every((pixel) => pixel.r >= 127 && pixel.g >= 127), isTrue);
    });

    test(
        'gradient fill alpha does not mask an independently translucent stroke',
        () async {
      final image = await raster('''
<defs><linearGradient id="a"><stop stop-color="red" stop-opacity="0"/><stop offset="1" stop-color="blue" stop-opacity=".5"/></linearGradient></defs>
<path d="M20 40H120V100H20Z" fill="url(#a)" stroke="#d68cff33" stroke-width="8"/>''');
      final stroke = image.getPixel(50, 38);
      expect(stroke.r, inInclusiveRange(246, 248));
      expect(stroke.g, inInclusiveRange(231, 233));
      expect(stroke.b, 255);
    });
    test('nested masks and gradient alpha paint in separate vector groups',
        () async {
      final document = Document(compress: false)
        ..addPage(Page(
            pageFormat: PdfPageFormat(200, 160),
            margin: EdgeInsets.zero,
            build: (_) => SvgImage(
                svg:
                    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 160">
<defs>
  <linearGradient id="alpha"><stop stop-color="red" stop-opacity=".5"/><stop offset="1" stop-color="blue"/></linearGradient>
  <mask id="outer"><rect width="100" height="100" fill="white"/></mask>
  <mask id="inner"><circle cx="50" cy="50" r="40" fill="white"/></mask>
</defs>
<g mask="url(#outer)" transform="translate(30 20)">
 <g mask="url(#inner)"><rect width="100" height="100" fill="url(#alpha)"/></g>
</g></svg>''')));
      final output = latin1.decode(await document.save());
      expect(RegExp(r'/SMask').allMatches(output).length, 3);
      expect(RegExp(r'/X\d+ Do').allMatches(output).length, 2,
          reason:
              'each authored mask composites vector content before its parent mask');
      expect(output, isNot(contains('/Subtype/Image')));
    });

    test(
        'path and text color alpha multiply paint opacity inside group opacity',
        () async {
      final font = loadFont('open-sans.ttf');
      final document = Document(compress: false)
        ..addPage(Page(build: (_) => SvgImage(defaultFont: font, svg: '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 160">
 <g opacity=".6" fill-opacity=".5" stroke-opacity=".5">
  <path d="M10 10H80V80H10Z" fill="#ff000033" stroke="#0000ff33"/>
  <text x="10" y="100" font-size="20" fill="#ff000033" stroke="#0000ff33">Text</text>
 </g>
</svg>''')));
      final output = latin1.decode(await document.save());
      expect(output, contains('/CA 0.1/ca 0.1'));
      expect(output, contains('/CA 0.6/ca 0.6'));
      expect(RegExp(r'/X\d+ Do').allMatches(output).length, 1);
    });

    test('gradient stop color alpha multiplies stop opacity', () {
      final parser = SvgParser(xml: XmlDocument.parse('''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
 <linearGradient id="linear"><stop stop-color="#ff000080" stop-opacity=".5"/></linearGradient>
 <radialGradient id="radial"><stop stop-color="#ff000080" stop-opacity=".5"/></radialGradient>
</svg>'''));
      final painter =
          SvgPainter(parser, null, PdfDocument(), parser.viewBox, {}, null, []);
      final linear =
          SvgLinearGradient.fromXml(parser.findById('linear')!, painter);
      final radial =
          SvgRadialGradient.fromXml(parser.findById('radial')!, painter);
      expect(linear.opacityList.single, closeTo(64 / 255, 0.00001));
      expect(radial.opacityList.single, closeTo(64 / 255, 0.00001));
    });

    test('zero-scale masked groups paint no content or invalid matrix',
        () async {
      final document = Document(compress: false)
        ..addPage(Page(build: (_) => SvgImage(svg: '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
 <mask id="m"><rect width="100" height="100" fill="white"/></mask>
 <g mask="url(#m)" transform="scale(0)"><rect width="100" height="100"/></g>
</svg>''')));
      final output = latin1.decode(await document.save());
      expect(output, isNot(contains('NaN')));
      expect(output, isNot(contains('Infinity')));
      expect(RegExp(r'/X\d+ Do').allMatches(output), isEmpty);
    });
  });
}
