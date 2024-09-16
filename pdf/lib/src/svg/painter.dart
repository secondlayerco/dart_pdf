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

import '../../pdf.dart';
import '../widgets/font.dart';
import '../widgets/widget.dart';
import 'brush.dart';
import 'color.dart';
import 'group.dart';
import 'parser.dart';

class SvgPainter {
  SvgPainter(
    this.parser,
    this._canvas,
    this.document,
    this.boundingBox,
    Map<String, List<Font>> fonts,
    this.defaultFont,
    this.fallbackFonts,
  )    : fonts = fonts.map((key, value) => MapEntry(_cleanFontName(key), value));

  final SvgParser parser;

  final PdfGraphics? _canvas;

  final PdfDocument document;

  final PdfRect boundingBox;

  final Map<String, List<Font>> fonts;

  Font? defaultFont;

  final List<Font> fallbackFonts;

  void paint() {
    final brush = parser.colorFilter == null
        ? SvgBrush.defaultContext
        : SvgBrush.defaultContext
            .copyWith(fill: SvgColor(color: parser.colorFilter));

    SvgGroup.fromXml(parser.root, this, brush).paint(_canvas!);
  }

  final _fontCache = <String, PdfFont>{};

  PdfFont getFontCache(String fontFamily, String fontStyle, String fontWeight) {
    final cache = '$fontFamily-$fontStyle-$fontWeight';
    return _fontCache[cache] ??= getFont(fontFamily, fontStyle, fontWeight);
  }

  static String _cleanFontName(String fontName) =>
      fontName.toLowerCase().replaceAll(RegExp(r'''("|'|\s)'''), '');

  static String _removeFontFallbacks(String fontName) {
    // Font names may contain fallbacks separated by commas
    // We just remove them for now, in the future we may want to use them
    final regExp = RegExp(r'(?<font>[^,]+)(,.+)?');
    final match = regExp.firstMatch(fontName);
    return match?.namedGroup('font') ?? fontName;
  }

  List<PdfTtfFont> get fallbackFontsTtf => fallbackFonts
      .map((f) => f.getFont(Context(document: document)))
      .whereType<PdfTtfFont>()
      .toList();


  List<PdfTtfFont> _getFamilyFonts(Context context, String fontFamily) {
        final cleanFontFamilyQuery = _cleanFontName(_removeFontFallbacks(fontFamily));
        return fonts[cleanFontFamilyQuery]?.map((f) => f.getFont(context)).whereType<PdfTtfFont>().toList() ?? [];
        }

  PdfTtfFont? _findBestFont(Context context, String fontFamily, String fontStyle, String fontWeight) {
    final familyFonts = _getFamilyFonts(context, fontFamily);
    if (familyFonts.length <= 1) {
      return defaultFont?.getFont(context) as PdfTtfFont?;
    }

    // Find best by style or weight
    // Based on https://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-chapter08#3054f18b

    // This is the default font
    final regularFont = familyFonts.firstWhere(
        (f) =>
            (f.font.getNameID(TtfParserName.fontSubfamily)?.toLowerCase() ??
                'regular') ==
            'regular',
        orElse: () => familyFonts.first);

    // Expect normal | italic | oblique
    final cleanFontStyle = fontStyle.toLowerCase();

    // Expect normal | bold | bolder | lighter | <number>
    final cleanFontWeight = fontWeight.toLowerCase();

    for (final font in familyFonts) {
      final fontSubFamily =
          font.font.getNameID(TtfParserName.fontSubfamily) ?? 'Regular';
      final cleanSubFamily = _cleanFontName(fontSubFamily);

      if (cleanSubFamily == cleanFontStyle ||
          cleanSubFamily == cleanFontWeight) {
        return font;
      }
    }

    return regularFont;
  }

  PdfFont getFont(String fontFamily, String fontStyle, String fontWeight) {
    final context = Context(document: document);

    switch (_cleanFontName(_removeFontFallbacks(fontFamily))) {
      case 'serif':
      case 'timesnewroman':
        switch (fontStyle) {
          case 'normal':
            switch (fontWeight) {
              case 'normal':
              case 'lighter':
                return Font.times().getFont(context);
            }
            return Font.timesBold().getFont(context);
        }
        switch (fontWeight) {
          case 'normal':
          case 'lighter':
            return Font.timesItalic().getFont(context);
        }
        return Font.timesBoldItalic().getFont(context);

      case 'monospace':
      case 'courier':
        switch (fontStyle) {
          case 'normal':
            switch (fontWeight) {
              case 'normal':
              case 'lighter':
                return Font.courier().getFont(context);
            }
            return Font.courierBold().getFont(context);
        }
        switch (fontWeight) {
          case 'normal':
          case 'lighter':
            return Font.courierOblique().getFont(context);
        }
        return Font.courierBoldOblique().getFont(context);

        case 'helvetica':
          switch (fontStyle) {
            case 'normal':
              switch (fontWeight) {
                case 'normal':
                case 'lighter':
                  return Font.helvetica().getFont(context);
              }
              return Font.helveticaBold().getFont(context);
          }
          switch (fontWeight) {
            case 'normal':
            case 'lighter':
              return Font.helveticaOblique().getFont(context);
          }
          return Font.helveticaBoldOblique().getFont(context);
    }

    final documentFont = _findBestFont(context, fontFamily, fontStyle, fontWeight);
    if (documentFont != null) {
      return documentFont;
    }

    return Font.helvetica().getFont(context);
  }
}
