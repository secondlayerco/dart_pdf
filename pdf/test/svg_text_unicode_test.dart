import 'dart:convert';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

void main() {
  test('SVG preserves source Unicode, contextual RTL and painted glyphs',
      () async {
    final work = await Directory.systemTemp.createTemp('svg-text-unicode-');
    addTearDown(() => work.delete(recursive: true));

    Future<File> export(String name, String latin, String han,
        {bool protect = false}) async {
      pw.Font load(String name) =>
          pw.TtfFont(File(name).readAsBytesSync().buffer.asByteData(),
              protect: protect);
      final document = pw.Document(compress: false, tagged: true);
      document.addPage(pw.Page(
          pageFormat: const PdfPageFormat(380, 160),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.MarkedContent(
                role: 'Figure',
                alt: 'Slide',
                child: pw.SvgImage(
                    defaultFont: load('open-sans.ttf'),
                    fallbackFonts: [
                      load('genyomintw.ttf'),
                      load('test/fixtures/JoiningFallback.ttf')
                    ],
                    svg:
                        '<svg viewBox="0 0 380 160" xmlns="http://www.w3.org/2000/svg">'
                        '<text x="10" y="40" font-size="20">$latin</text>'
                        '<text x="10" y="85" font-size="20" fill="red" stroke="blue" stroke-width="0.1">$han</text>'
                        '<text x="10" y="125" font-size="20">ببتب</text></svg>'),
              )));
      return File('${work.path}/$name.pdf').writeAsBytes(await document.save());
    }

    Future<String> extract(File pdf) async {
      final result = await Process.run('pdftotext', ['-raw', pdf.path, '-']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout.toString().trim();
    }

    Future<List<int>> raster(File pdf) async {
      final result = await Process.run('pdftoppm', ['-r', '72', pdf.path],
          stdoutEncoding: null);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout as List<int>;
    }

    const latin = 'fiﬁ ffiﬃ éé';
    const han = '⺂乛⺂🄀';
    final source = await export('source', latin, han);
    final evidence = Platform.environment['PDF_UNICODE_ARTIFACT_DIR'];
    if (evidence != null) {
      await source.copy('$evidence/source-text.pdf');
    }
    final lines = (await extract(source)).split('\n');
    expect(lines, hasLength(3));
    expect(lines.take(2), [latin, han]);
    expect(lines[2].replaceAll(RegExp('[\u202b\u202c]'), ''), 'ببتب');
    final encoded = latin1.decode(await source.readAsBytes());
    expect(encoded, contains('/StructTreeRoot'));
    expect(encoded, contains('006600660069'));
    expect(encoded, contains('D83CDD00'));
    final sameGlyphs = await export('same-glyphs', 'ﬁﬁ ﬃﬃ éé', '乛乛乛🄀');
    expect(await raster(source), orderedEquals(await raster(sameGlyphs)));
    expect(await extract(await export('protected', latin, han, protect: true)),
        isEmpty);
  });
}
