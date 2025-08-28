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

Iterable<TextDecoration> permute(
    List<TextDecoration> prefix, List<TextDecoration> remaining) sync* {
  yield TextDecoration.combine(prefix);
  if (remaining.isNotEmpty) {
    for (final decoration in remaining) {
      final next = List<TextDecoration>.from(remaining);
      next.remove(decoration);
      yield* permute(prefix + <TextDecoration>[decoration], next);
    }
  }
}

void main() async {
  Document.debug = true;
  RichText.debug = true;

  final ttf = loadFont(
      '../../../secondlayer/napkin-web-client/web/fonts/Roboto/Roboto-Regular.ttf');

  final ttf2 = loadFont(
      '../../../secondlayer/napkin-web-client/web/fonts/Geeza_Pro/GeezaPro-01.ttf');

  pdf = Document(userDocumentID: '1234567890');

  pdf.addPage(Page(
      pageFormat: PdfPageFormat.a4,
      build: (Context context) => Text2(str,
          textDirection: TextDirection.ltr,
          style:
              TextStyle(fontSize: 12, font: ttf, fontFallback: [ttf2]))));

  final file = File('widgets-text.pdf');
  await file.writeAsBytes(await pdf.save());
}

// const str =
//     """Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
// """;

const str = '''
برنامه‌های وفاداری مبتنی بر ارزش (Value-Driven Loyalty Programs): این دسته از برنامه‌ها با عبور از رویکردهای صرفاً معاملاتی، بر ایجاد پیوندهای عمیق و پایدار با مشتریان تمرکز دارند. هم‌راستایی با ارزش‌های مشتریان نظیر پایداری زیست‌محیطی، مسئولیت‌پذیری اجتماعی، و ارائه تجربه‌های منحصربه‌فرد مانند دسترسی انحصاری به رویدادها یا محتوای ویژه، از جمله رویکردهای کلیدی در این حوزه به شمار می‌آید (شت و همکاران، 2020؛ فورنیه و آلوارز، 2024).
''';
