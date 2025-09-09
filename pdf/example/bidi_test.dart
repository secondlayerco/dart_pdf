import 'dart:io';

import '../lib/src/shaping/shaping.dart';
import '../lib/src/pdf/obj/ttffont.dart';
import '../lib/src/pdf/document.dart';
import '../lib/src/widgets/widget.dart';
import '../lib/widgets.dart' as pw;

void main() async {
  final document = PdfDocument();

  final primaryFont = PdfTtfFont(
      document,
      File('../../../secondlayer/napkin-web-client/web/fonts/Roboto/Roboto-Regular.ttf')
          .readAsBytesSync()
          .buffer
          .asByteData());
  final fallbackFonts0 = [
    PdfTtfFont(
        document,
        File('/Users/arnaudbrejeon/secondLayer/src/secondlayer/napkin-web-client/web/fonts/Geeza_Pro/GeezaPro-01.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData()),
  ];

  // const str = 'Hello, world!';
  // const str = '洛伦姆·伊普森假文是印刷和排版行业常用的占位文本';
  const str = 'ما‌‌ئده تباری##[123]،** فاطمه محمدی[2]';
  final lines = Shaping().shapeLinesWithBreaks(str, primaryFont, fallbackFonts0,
      startingLocation: 0.0, maxWidth: 10.0, letterSpacing: 0.0);

  print(lines);

  Shaping().dispose();
}
