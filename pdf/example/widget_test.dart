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

import 'dart:io';
import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';

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
  final ttf = loadFont(
      '../../../secondlayer/napkin-web-client/web/fonts/Roboto/Roboto-Regular.ttf');

  final ttf2 = loadFont(
      '../../../secondlayer/napkin-web-client/web/fonts/Shantell_Sans/static/ShantellSans-Regular.ttf');

  final fallbacks = [
    loadFont(
        '../../../secondlayer/napkin-web-client/web/fonts/Geeza_Pro/GeezaPro-01.ttf'),
    loadFont(
        '../../../secondlayer/napkin-web-client/web/fonts/Noto_Sans_Kannada/static/NotoSansKannada-Regular.ttf')
  ];

  pdf = Document(userDocumentID: '1234567890');

  pdf.addPage(Page(
      pageFormat: PdfPageFormat.a4,
      build: (Context context) => Stack(children: [
            Positioned(
                top: 400,
                left: 20,
                child: Container(
                  width: 400,
                  child: Text(str,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                          color: PdfColor.fromHex('#FF00FF'),
                          fontSize: 12,
                          font: ttf,
                          fontFallback: fallbacks)),
                )),
            Positioned(
                top: 100,
                left: 20,
                child: Container(
                    width: 400,
                    child: RichText2(
                        textAlign: TextAlign.left,
                        text: TextSpan(children: [
                          TextSpan(
                              text: str1,
                              style: TextStyle(
                                  fontSize: 12,
                                  decoration: TextDecoration.lineThrough,
                                  font: ttf,
                                  fontFallback: fallbacks)),
                          TextSpan(
                              text: str2,
                              style: TextStyle(
                                  color: PdfColor.fromHex('#FF00FF'),
                                  fontSize: 12,
                                  font: ttf,
                                  fontFallback: fallbacks)),
                          TextSpan(
                              text: str3,
                              style: TextStyle(
                                  decoration: TextDecoration.underline,
                                  fontSize: 12,
                                  font: ttf2,
                                  fontFallback: fallbacks)),
                          TextSpan(
                              text: str4,
                              style: TextStyle(
                                  color: PdfColor.fromHex('#0000FF'),
                                  fontSize: 12,
                                  font: ttf,
                                  fontFallback: fallbacks)),
                        ])))),
          ])));

  final file = File('widgets-text.pdf');
  await file.writeAsBytes(await pdf.save());
}

const str1 =
    'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ';
const str2 = 'ಇಲ್ಲ ಪಕ್ಕದಲ್ಲಿ ಹಾಂ ಬಳ ನೀವು ಹಾಂ ';
const str3 =
    'Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. ';
const str4 =
    'Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.';

const str =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.';

// const str = '''
// تجربه مشتری (Customer) به عنوان یکی از عوامل کلیدی در شکل‌گیری وفاداری مشتری شناخته می‌شود. تجربه‌ای یکپارچه و مثبت در تمامی نقاط تماس مشتری با سازمان، نقش مهمی در ارتقاء وفاداری ایفا می‌کند (اشمیت، ۲۰۱۷). این تجربه شامل عناصری همچون سهولت در تعامل، کارایی، لذت و ارزش ادراک‌شده در طول مسیر تعامل مشتری با برند است.
// ''';

// const str = '''
// لم أضف القوى تحرّكت الرئيسية. إيو أي إعمار واحدة قائمة, لم تطوير عرفها جعل. عل لها جسيمة فشكّل التبرعات, أم كان هناك هُزم والكساد. هنا؟ شمال السبب ضرب بل, لكل بل لإعادة بريطانيا. جُل تشكيل والتي عسكرياً ٣٠, أن بتحدّي الدنمارك الكونجرس تحت, أي جهة عرفها اللازمة ماليزيا،.
// ''';

// const str2 = '''
// مرحباً! أنا بأروح السوق اليوم (الساعة 5).
// ''';

// const str = '''
// של העיר וכמקובל כדי. עוד לחבר כלכלה דת, צעד אודות המלחמה מונחונים אל, בקר והוא ספורט לתרום על. מה טכניים קלאסיים עוד. של בקר ביוני בחירות ביולוגיה, ראשי עזרה על בקר, ב המשפט זכויות מדע. אל לחשבון התפתחות מלא, בה מוגש הספרות וכמקובל עזה, הראשי תקשורת קצרמרים בדף אל.
// ''';
