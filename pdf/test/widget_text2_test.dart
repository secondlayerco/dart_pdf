import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';

import 'utils.dart';

late Document pdf;
late Font ttf;
late Font ttfBold;

void main() {
  setUpAll(() {
    Document.debug = true;

    ttf = loadFont('open-sans.ttf');
    ttfBold = loadFont('open-sans-bold.ttf');
    pdf = Document();
  });

  test('Text2 justify alignment renders without error', () {
    const para =
        'This is a test paragraph with enough words to wrap across multiple lines when constrained to a narrow width.';

    pdf.addPage(
      Page(
        build: (Context context) => SizedBox(
          width: 200,
          child: Text2(
            para,
            style: TextStyle(font: ttf, fontSize: 12),
            textAlign: TextAlign.justify,
          ),
        ),
      ),
    );
  });

  test('Text2 justify with multiple paragraphs', () {
    const para =
        'First paragraph with enough text to span multiple lines in a narrow box.\nSecond paragraph that also needs to be long enough to wrap around.\nShort line.';

    pdf.addPage(
      Page(
        build: (Context context) => SizedBox(
          width: 200,
          child: Text2(
            para,
            style: TextStyle(font: ttf, fontSize: 12),
            textAlign: TextAlign.justify,
          ),
        ),
      ),
    );
  });

  test('Text2 justify single line does not stretch', () {
    pdf.addPage(
      Page(
        build: (Context context) => SizedBox(
          width: 400,
          child: Text2(
            'Short text',
            style: TextStyle(font: ttf, fontSize: 12),
            textAlign: TextAlign.justify,
          ),
        ),
      ),
    );
  });

  test('Text2 justify with no spaces', () {
    pdf.addPage(
      Page(
        build: (Context context) => SizedBox(
          width: 50,
          child: Text2(
            'Superlongwordwithoutanyspaces',
            style: TextStyle(font: ttf, fontSize: 12),
            textAlign: TextAlign.justify,
          ),
        ),
      ),
    );
  });

  test('RichText2 justify with multiple spans', () {
    pdf.addPage(
      Page(
        build: (Context context) => SizedBox(
          width: 200,
          child: RichText2(
            textAlign: TextAlign.justify,
            text: TextSpan(
              style: TextStyle(font: ttf, fontSize: 12),
              children: <InlineSpan>[
                TextSpan(
                  text:
                      'This is a long paragraph with mixed styling that should wrap across multiple lines. ',
                  style: TextStyle(font: ttf, fontSize: 12),
                ),
                TextSpan(
                  text: 'Bold text here ',
                  style: TextStyle(font: ttfBold, fontSize: 12),
                ),
                TextSpan(
                  text:
                      'and then normal text continues for a while to ensure wrapping occurs properly.',
                  style: TextStyle(font: ttf, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  });

  test('Text2 all alignments render correctly', () {
    const para =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.';

    final widgets = <Widget>[];
    for (final align in TextAlign.values) {
      widgets.add(
        SizedBox(
          width: 200,
          child: Text2(
            '[$align]: $para',
            style: TextStyle(font: ttf, fontSize: 10),
            textAlign: align,
          ),
        ),
      );
      widgets.add(SizedBox(height: 20));
    }

    pdf.addPage(MultiPage(build: (Context context) => widgets));
  });

  test('Text2 justify with large font size', () {
    const para =
        'Big text that needs to be justified across the available width of the container.';

    pdf.addPage(
      Page(
        build: (Context context) => SizedBox(
          width: 300,
          child: Text2(
            para,
            style: TextStyle(font: ttf, fontSize: 24),
            textAlign: TextAlign.justify,
          ),
        ),
      ),
    );
  });

  tearDownAll(() async {
    final file = File('widgets-text2.pdf');
    await file.writeAsBytes(await pdf.save());
  });
}
