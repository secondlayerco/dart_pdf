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
import 'dart:math';
import 'dart:typed_data';

import '../../shaping/shaping.dart';
import '../document.dart';
import '../font/font_metrics.dart';
import '../font/ttf_parser.dart';
import '../font/ttf_writer.dart';
import '../format/array.dart';
import '../format/dict.dart';
import '../format/name.dart';
import '../format/num.dart';
import '../format/stream.dart';
import '../format/string.dart';
import 'font.dart';
import 'font_descriptor.dart';
import 'object.dart';
import 'object_stream.dart';
import 'unicode_cmap.dart';

// We can support two types of CIDToGIDMap: identity and Map. map is better but it looks that identity is better supported by all viewers (e.g edge viewer)
enum CIDToGIDMapType { identity, map }

class PdfTtfFont extends PdfFont {
  /// Constructs a [PdfTtfFont]
  PdfTtfFont(PdfDocument pdfDocument, ByteData bytes, {bool protect = false})
      : font = TtfParser(bytes),
        super.create(pdfDocument, subtype: '/TrueType') {
    file = PdfObjectStream(pdfDocument, isBinary: true);
    unicodeCMap = PdfUnicodeCmap(pdfDocument, protect);
    descriptor = PdfFontDescriptor(this, file);
    widthsObject = PdfObject<PdfArray>(pdfDocument, params: PdfArray());

    // By default the font is not used
    _setInUse(false);
  }

  void _setInUse(bool s) {
    inUse = s;
    file.inUse = s;
    unicodeCMap.inUse = s;
    descriptor.inUse = s;
    widthsObject.inUse = s;
  }

  PdfObjectStream? _cidToGidMap;

  @override
  String get subtype => font.unicode ? '/Type0' : super.subtype;

  late PdfUnicodeCmap unicodeCMap;

  late PdfFontDescriptor descriptor;

  late PdfObjectStream file;

  late PdfObject<PdfArray> widthsObject;

  final TtfParser font;

  @override
  String get fontName => font.fontName;

  @override
  double get ascent => font.ascent.toDouble() / font.unitsPerEm;

  @override
  double get descent => font.descent.toDouble() / font.unitsPerEm;

  @override
  int get unitsPerEm => font.unitsPerEm;

  @override
  PdfFontMetrics glyphMetrics(int charCode) {
    final g = font.charToGlyphIndexMap[charCode];

    if (g == null) {
      return PdfFontMetrics.zero;
    }

    return font.glyphInfoMap[g] ?? PdfFontMetrics.zero;
  }

  void _buildTrueType(PdfDict params) {
    int charMin;
    int charMax;

    file.buf.putBytes(font.bytes.buffer.asUint8List());
    file.params['/Length1'] = PdfNum(font.bytes.lengthInBytes);

    params['/BaseFont'] = PdfName('/$fontName');
    params['/FontDescriptor'] = descriptor.ref();
    charMin = 32;
    charMax = 255;
    for (var i = charMin; i <= charMax; i++) {
      widthsObject.params.add(PdfNum((glyphMetrics(i).advanceWidth * 1000.0).toInt()));
    }
    params['/FirstChar'] = PdfNum(charMin);
    params['/LastChar'] = PdfNum(charMax);
    params['/Widths'] = widthsObject.ref();
  }

  void _buildType0(PdfDict params) {
    final maxCid = _glyphByCid.keys.fold(0, max);
    final cidMap = _cidToGidMap;
    if (cidMap != null) {
      final mapping = ByteData(2 * (maxCid + 1));
      _glyphByCid.forEach((cid, gid) => mapping.setUint16(2 * cid, gid));
      cidMap.buf.putBytes(mapping.buffer.asUint8List());
    }

    final ttfWriter = TtfWriter(font);
    final data = ttfWriter.withGlyphIndices(font, _glyphByCid.values.toSet().toList(), identityCID: true);
    file.buf.putBytes(data);
    file.params['/Length1'] = PdfNum(data.length);

    final descendantFont = PdfDict.values({
      '/Type': const PdfName('/Font'),
      '/BaseFont': PdfName('/$fontName'),
      '/FontFile2': file.ref(),
      '/FontDescriptor': descriptor.ref(),
      '/W': PdfArray([
        const PdfNum(0),
        widthsObject.ref(),
      ]),
      '/CIDToGIDMap': cidMap?.ref() ?? const PdfName('/Identity'),
      '/DW': const PdfNum(1000),
      '/Subtype': const PdfName('/CIDFontType2'),
      '/CIDSystemInfo': PdfDict.values({
        '/Supplement': const PdfNum(0),
        '/Registry': PdfString.fromString('Adobe'),
        '/Ordering': PdfString.fromString('Identity-H'),
      })
    });

    params['/BaseFont'] = PdfName('/$fontName');
    params['/Encoding'] = const PdfName('/Identity-H');
    params['/DescendantFonts'] = PdfArray([descendantFont]);
    params['/ToUnicode'] = unicodeCMap.ref();

    for (var cid = 0; cid <= maxCid; cid++) {
      final glyph = _glyphByCid[cid] ?? cid;
      widthsObject.params.add(PdfNum((glyphIndexMetrics(GlyphIndex(glyph)).advanceWidth * 1000).toInt()));
    }
  }

  @override
  void prepare() {
    super.prepare();

    if (font.unicode) {
      _buildType0(params);
    } else {
      _buildTrueType(params);
    }
  }

  final _glyphByCid = <int, int>{};
  final _cidByGlyphAndSource = <(int, String), int>{};
  late final Map<int, int> _defaultSources = _invertCharacterMap();

  Map<int, int> _invertCharacterMap() {
    final sources = <int, int>{};
    for (final entry in font.charToGlyphIndexMap.entries) {
      sources.putIfAbsent(entry.value, () => entry.key);
    }
    return sources;
  }

  int _nextCid = 1;

  int _characterCode(int glyph, String? source) {
    final text = source ?? String.fromCharCode(_defaultSources[glyph] ?? 0x3f);
    return _cidByGlyphAndSource.putIfAbsent((glyph, text), () {
      var cid = glyph;
      if (_glyphByCid.containsKey(cid)) {
        while (_glyphByCid.containsKey(_nextCid)) {
          _nextCid++;
        }
        if (_nextCid > 0xffff) {
          throw StateError('PDF font character code space exhausted');
        }
        cid = _nextCid++;
        _cidToGidMap ??= PdfObjectStream(pdfDocument, isBinary: true);
      }
      _glyphByCid[cid] = glyph;
      unicodeCMap.setSource(cid, text);
      return cid;
    });
  }

  @override
  void putGlyphs(PdfStream stream, List<int> glyphIndices, {List<String?>? sources}) {
    _setInUse(true);
    stream.putByte(0x3c);
    for (var i = 0; i < glyphIndices.length; i++) {
      final cid = _characterCode(glyphIndices[i], sources?[i]);
      stream.putBytes(latin1.encode(cid.toRadixString(16).padLeft(4, '0')));
    }
    stream.putByte(0x3e);
  }

  @override
  void putText(PdfStream stream, String text) {
    final results = Shaping().shape(text, this, []);
    putGlyphs(stream, results.glyphIndicesVisual);
  }

  @override
  PdfFontMetrics stringMetrics(String s, {double letterSpacing = 0}) => Shaping().shape(s, this, []).metrics(letterSpacing: letterSpacing);

  PdfFontMetrics glyphIndexMetrics(GlyphIndex glyphIndex) => font.glyphInfoMap[glyphIndex.index] ?? PdfFontMetrics.zero;

  PdfFontMetrics glyphIndexMetricsWithLetterSpacing(GlyphIndex glyphIndex, double letterSpacing) {
    final metrics = font.glyphInfoMap[glyphIndex.index];
    if (metrics == null) {
      return PdfFontMetrics.zero;
    }
    if (metrics.advanceWidth <= 0) {
      return metrics;
    }

    return metrics.copyWith(advanceWidth: metrics.advanceWidth + letterSpacing);
  }

  @override
  bool isRuneSupported(int charCode) {
    return font.charToGlyphIndexMap.containsKey(charCode);
  }
}
