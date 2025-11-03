import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';

// import 'utils.dart';

late Document pdf;
late Font ttf;
late Font ttfBold;
late Font asian;
late Font emoji;

Font loadFont(String filename) {
  final data = File(filename).readAsBytesSync();
  return Font.ttf(data.buffer.asByteData());
}

void main() async {
  final ttf = loadFont('../../../secondlayer/napkin-web-client/web/fonts/Geomanist-Complete-Webfont/Geomanist-Regular-Webfont/geomanist-regular-webfont.ttf');

  final fallbacks = [
    loadFont('../../../secondlayer/napkin-web-client/web/fonts/Geeza_Pro/GeezaPro-01.ttf'),
  ];

  pdf = Document(userDocumentID: '1234567890');

  final svgImage = SvgImage(
      svg: svgRaw(),
      fonts: {
        // 'roboto': [
        //   Font.ttf(File('../../../secondlayer/napkin-web-client/web/fonts/Roboto/Roboto-Regular.ttf').readAsBytesSync().buffer.asByteData()),
        //   Font.ttf(File('../../../secondlayer/napkin-web-client/web/fonts/Roboto/Roboto-Bold.ttf').readAsBytesSync().buffer.asByteData())
        // ],
        // 'shantell sans': [
        //   Font.ttf(File('../../../secondlayer/napkin-web-client/web/fonts/Shantell_Sans/static/ShantellSans-Regular.ttf').readAsBytesSync().buffer.asByteData())
        // ],
      },
      defaultFont: loadFont('../../../secondlayer/napkin-web-client/web/fonts/Roboto/Roboto-Regular.ttf'),
      fallbackFonts: [
        loadFont('../../../secondlayer/napkin-web-client/web/fonts/Noto_Sans_Kannada/static/NotoSansKannada-Regular.ttf'),
        loadFont('../../../secondlayer/napkin-web-client/web/fonts/Noto_Serif_JP/static/NotoSerifJP-Regular.ttf')
      ]);

  pdf.addPage(Page(
      pageFormat: PdfPageFormat(1104, 1440),
      build: (Context context) => Stack(children: [
            Positioned(
                left: 200,
                top: 100,
                child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: PdfColor.fromHex('#000000')),
                    ),
                    width: 684,
                    child: RichText2(
                        textAlign: TextAlign.right,
                        text: TextSpan(children: [
                          TextSpan(text: str, style: TextStyle(letterSpacing: 0.3333, fontSize: 16, font: ttf, fontFallback: fallbacks)),
                        ])))),
            Positioned(left: 250, top: 300, child: svgImage)
          ])));

  final file = File('pdf_test.pdf');
  await file.writeAsBytes(await pdf.save());
}

const str = '''
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
تجربه مشتری (Customer - Expe) به می‌کند (اشمیت، ۲۰۱۷).
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
''';

String svgRaw() => '''
<svg width="1128" height="500" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <g>
    <g>
      <text style="font: 30px 'Times new roman', serif; white-space: pre;" fill="red">
        <tspan y="0" dominant-baseline="ideographic">SVG</tspan>
      </text>
      <text style="font: 30px 'Times new roman', serif; white-space: pre;" fill="blue">
        <tspan y="50" dominant-baseline="ideographic"> ಇಲ್ಲ ಪಕ್ಕದಲ್ಲಿ ಹಾಂ ಬಳ ನೀವು ಹಾಂ </tspan>
      </text>
      <text style="font: 30px 'Helvetica', serif; white-space: pre;" fill="green">
        <tspan y="100" dominant-baseline="ideographic">内容に意味はありません</tspan>
      </text>
      <text style="font: 30px 'Courier', serif; white-space: pre;" fill="black">
        <tspan y="150" dominant-baseline="ideographic">HIJ ${DateTime.now().millisecond}</tspan>
      </text>
    </g>
  </g>
</svg>
''';
