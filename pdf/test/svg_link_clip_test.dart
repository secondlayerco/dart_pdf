import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  test('PDF link rectangles leave holes and hidden areas unclickable',
      () async {
    final document = Document(compress: false)
      ..addPage(Page(
        pageFormat: const PdfPageFormat(200, 145),
        margin: EdgeInsets.zero,
        build: (_) => SvgImage(
          defaultFont: loadFont('open-sans.ttf'),
          svg: '''<svg viewBox="0 0 200 145" xmlns="http://www.w3.org/2000/svg">
<defs>
  <clipPath id="hole">
    <path clip-rule="evenodd" d="M0 0H130V35H0Z M40 0H80V35H40Z"/>
  </clipPath>
  <clipPath id="overlap" clip-rule="evenodd">
    <rect width="80" height="35"/><rect x="40" width="90" height="35"/>
  </clipPath>
  <mask id="ink"><g><rect width="130" height="35" fill="white"/><rect x="40" width="40" height="35" fill="black"/></g></mask>
</defs>
<g fill="#111111" font-size="20">
  <g clip-path="url(#hole)"><text x="5" y="23" data-href="https://example.org/compound">MMMMMMMM</text></g>
  <g transform="translate(0 50)" clip-path="url(#overlap)"><text x="5" y="23" data-href="https://example.org/overlap">MMMMMMMM</text></g>
  <g transform="translate(0 100)" mask="url(#ink)"><text x="5" y="23" data-href="https://example.org/masked">MMMMMMMM</text></g>
</g></svg>''',
        ),
      ));
    final bytes = await document.save();
    final artifact = Platform.environment['PDF_LINK_REGION_ARTIFACT'];
    if (artifact != null) {
      await File(artifact).writeAsBytes(bytes);
    }
    final pdf = latin1.decode(bytes);
    bool clickable(String link, double x, double y) =>
        RegExp(r'/Subtype/Link(?:(?!endobj).)*?/URI\(https://example.org/(\w+)\)',
                dotAll: true)
            .allMatches(pdf)
            .where((match) => match[1] == link)
            .any((match) {
          final rect = RegExp(r'/Rect\s*\[([^\]]+)\]')
              .firstMatch(match[0]!)![1]!
              .trim()
              .split(RegExp(r'\s+'))
              .map(double.parse)
              .toList();
          final pdfY = 145 - y;
          return x > rect[0] && x < rect[2] && pdfY > rect[1] && pdfY < rect[3];
        });

    expect(clickable('compound', 25, 18.2), isTrue);
    expect(clickable('compound', 100, 18.2), isTrue);
    expect(clickable('compound', 60, 18.2), isFalse);
    expect(clickable('overlap', 60, 68.2), isTrue);
    expect(clickable('masked', 25, 118.2), isTrue);
    expect(clickable('masked', 100, 118.2), isTrue);
    expect(clickable('masked', 60, 118.2), isFalse);
  });

  test('SVG link annotations match the visible parts of clipped runs',
      () async {
    final directory = await Directory.systemTemp.createTemp('pdf-link-clips-');
    addTearDown(() => directory.delete(recursive: true));
    final document = Document(compress: false)
      ..addPage(Page(
        pageFormat: const PdfPageFormat(220, 230),
        margin: EdgeInsets.zero,
        build: (_) => SvgImage(
          defaultFont: loadFont('open-sans.ttf'),
          svg: '''<svg viewBox="0 0 220 230" xmlns="http://www.w3.org/2000/svg">
<defs>
  <clipPath id="first"><rect width="40" height="30"/></clipPath>
  <clipPath id="nested"><path d="M5 0 H35 V30 H5Z" transform="translate(2 0)"/></clipPath>
  <clipPath id="circle"><circle cx="30" cy="30" r="30"/></clipPath>
  <clipPath id="round"><rect width="60" height="60" rx="20"/></clipPath>
  <clipPath id="diamond"><path d="M30 0 L60 27 L30 54 L0 27 Z"/></clipPath>
</defs>
<g font-size="20" fill="#111111">
  <g transform="translate(10 10)" clip-path="url(#first)">
    <text x="55" y="20" data-href="https://example.org/hidden">INVISIBLE</text>
    <g clip-path="url(#nested)"><text y="20" data-href="https://example.org/partial">Visible words</text></g>
  </g>
  <g transform="translate(80 55) rotate(30)" clip-path="url(#first)">
    <text y="20" data-href="https://example.org/rotated">Rotated words</text>
    <text y="-10" data-href="https://example.org/rotatedhidden">Outside</text>
  </g>
  <g transform="translate(163 49)" clip-path="url(#first)">
    <text x="-10" y="22" transform="rotate(20 15 15)" data-href="https://example.org/crossing">Across the box</text>
  </g>
  <text x="70" y="130" data-href="https://example.org/plain">Plain words</text>
  <g transform="translate(0 160)" clip-path="url(#circle)" font-size="10">
    <text y="7" data-href="https://example.org/circlehidden">I</text>
    <text x="20" y="33" data-href="https://example.org/circle">Yes</text>
    <text x="31" y="15" data-href="https://example.org/circleedge">Along the edge</text>
  </g>
  <g transform="translate(75 160)" clip-path="url(#round)" font-size="10">
    <text y="5" data-href="https://example.org/roundhidden">I</text>
    <text x="20" y="33" data-href="https://example.org/round">Yes</text>
    <text x="31" y="15" data-href="https://example.org/roundedge">Along the edge</text>
  </g>
  <g transform="translate(150 160)" clip-path="url(#diamond)" font-size="10">
    <text y="7" data-href="https://example.org/diamondhidden">I</text>
    <text x="20" y="33" data-href="https://example.org/diamond">Yes</text>
    <text x="31" y="15" data-href="https://example.org/diamondedge">Along the edge</text>
  </g>
</g></svg>''',
        ),
      ));
    final bytes = await document.save();
    final file = File('${directory.path}/links.pdf');
    await file.writeAsBytes(bytes);
    final evidence = Platform.environment['PDF_LINK_CLIP_ARTIFACT'];
    if (evidence != null) {
      await file.copy(evidence);
    }
    final raster = await Process.run(
        Platform.environment['PDF_RASTERIZER'] ?? 'pdftoppm', [
      '-png',
      '-singlefile',
      '-r',
      '72',
      file.path,
      '${directory.path}/links'
    ]);
    expect(raster.exitCode, 0, reason: '${raster.stderr}');
    final image =
        im.decodePng(await File('${directory.path}/links.png').readAsBytes())!;
    int dark(int x0, int x1, int y0, int y1) => image
        .where(
            (p) => x0 <= p.x && p.x < x1 && y0 <= p.y && p.y < y1 && p.r < 100)
        .length;
    expect(dark(62, 170, 10, 39), 0);
    expect(dark(17, 47, 10, 40), greaterThan(50));
    expect(dark(70, 180, 109, 138), greaterThan(80));
    for (final left in [0, 75, 150]) {
      expect(dark(left, left + 10, 160, 171), 0);
      expect(dark(left + 20, left + 42, 180, 197), greaterThan(10));
    }
    final annotations = {
      for (final match in RegExp(
              r'/Subtype/Link(?:(?!endobj).)*?/URI\(https://example.org/(\w+)\)',
              dotAll: true)
          .allMatches(latin1.decode(bytes)))
        match[1]!: match[0]!,
    };
    List<double> points(String link, String field) =>
        RegExp('/$field\\s*\\[([^\\]]+)\\]')
            .firstMatch(annotations[link]!)![1]!
            .trim()
            .split(RegExp(r'\s+'))
            .map(double.parse)
            .toList();
    expect(
        annotations.keys,
        unorderedEquals([
          'partial',
          'rotated',
          'crossing',
          'plain',
          'circle',
          'round',
          'diamond',
          'circleedge',
          'roundedge',
          'diamondedge'
        ]));
    for (final (name, left) in [
      ('circle', 20),
      ('round', 95),
      ('diamond', 170)
    ]) {
      expect(points(name, 'Rect')[0], closeTo(left, .001));
      expect(annotations[name], isNot(contains('/QuadPoints')));
      expect(points('${name}edge', 'Rect')[2],
          inExclusiveRange(left + 11, left + 40));
      expect(annotations['${name}edge'], contains('/QuadPoints'));
    }
    final partial = points('partial', 'Rect');
    expect(partial[0], closeTo(17, .001));
    expect(partial[2], closeTo(47, .001));
    final quad = points('rotated', 'QuadPoints');
    expect(quad.length, 8);
    for (var i = 0; i < quad.length; i += 2) {
      final x = quad[i] - 80;
      final y = 230 - quad[i + 1] - 55;
      final localX = x * .8660254 + y * .5;
      final localY = -x * .5 + y * .8660254;
      expect(localX, inInclusiveRange(-.001, 40.001));
      expect(localY, inInclusiveRange(-.001, 30.001));
    }
    final crossing = points('crossing', 'QuadPoints');
    expect(crossing.length, greaterThan(8));
    expect(crossing.length % 8, 0);
    var activeArea = 0.0;
    for (var i = 0; i < crossing.length; i += 8) {
      for (var j = 0; j < 8; j += 2) {
        final x = crossing[i + j] - 163;
        final y = 230 - crossing[i + j + 1] - 49;
        expect(x, inInclusiveRange(-.001, 40.001));
        expect(y, inInclusiveRange(-.001, 30.001));
        final next = i + (j + 2) % 8;
        activeArea += (crossing[i + j] * crossing[next + 1] -
                crossing[next] * crossing[i + j + 1]) /
            2;
      }
    }
    expect(activeArea, inInclusiveRange(850, 1200));
    expect(points('plain', 'Rect')[0], closeTo(70, .001));
    expect(annotations['plain'], isNot(contains('/QuadPoints')));
  });
}
