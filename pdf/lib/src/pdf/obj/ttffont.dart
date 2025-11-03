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
import '../format/base.dart';
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

  final CIDToGIDMapType _cidToGidMapType = CIDToGIDMapType.identity;

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
    _buildCmap();

    int charMin;
    int charMax;

    final ttfWriter = TtfWriter(font);
    final data = ttfWriter.withGlyphIndices(font, _glyphIndices, _usedGlyphs);
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
      '/CIDToGIDMap': _cidToGidMapType == CIDToGIDMapType.identity ? const PdfName('/Identity') : _cidToGidMap(),
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

    if (_cidToGidMapType == CIDToGIDMapType.identity) {
      charMin = 0;
      charMax = _usedGlyphs.fold<int>(0, max);
      for (var i = charMin; i <= charMax; i++) {
        widthsObject.params.add(PdfNum((glyphIndexMetrics(GlyphIndex(i)).advanceWidth * 1000.0).toInt()));
      }
    } else {
      charMin = 0;
      charMax = _glyphIndices.length - 1;
      for (var i = charMin; i <= charMax; i++) {
        widthsObject.params.add(PdfNum((glyphIndexMetrics(GlyphIndex(_glyphIndices[i])).advanceWidth * 1000.0).toInt()));
      }
    }
  }

  PdfDataType _cidToGidMap() {
    assert(_cidToGidMapType == CIDToGIDMapType.map);
    return PdfArray(_invertGlyphIndex().map((value) => [PdfNum((value >> 16) & 0xFFFF), PdfNum(value & 0xFFFF)]).expand((value) => value));
  }

  List<int> _invertGlyphIndex() {
    assert(_cidToGidMapType == CIDToGIDMapType.map);
    final inverted = List.filled(_glyphIndices.fold(0, max) + 1, 0);
    for (var i = 0; i < _glyphIndices.length; i++) {
      inverted[_glyphIndices[i]] = i;
    }
    return inverted;
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

  final Set<int> _usedGlyphs = {};
  final List<int> _glyphIndices = [];

  void _buildCmap() {
    final glyphNotFound = '?'.runes.first;
    if (_cidToGidMapType == CIDToGIDMapType.identity) {
      for (var i = 0; i < _glyphIndices.length; i++) {
        final char = font.charToGlyphIndexMap.entries.where((entry) => entry.value == _glyphIndices[i]).map((e) => e.key).firstOrNull;
        unicodeCMap.cmap[_glyphIndices[i]] = char ?? glyphNotFound;
      }
      return;
    }

    for (var i = 0; i < _glyphIndices.length; i++) {
      final char = font.charToGlyphIndexMap.entries.where((entry) => entry.value == _glyphIndices[i]).map((e) => e.key).firstOrNull;
      unicodeCMap.cmap[i] = char ?? glyphNotFound;
    }
  }

  @override
  void putGlyphs(PdfStream stream, List<int> glyphIndices) {
    _setInUse(true);
    stream.putByte(0x3c);
    final indices = <int>[];
    for (final glyphIndex in glyphIndices) {
      final indexInMap = _glyphIndexToMapIndex(glyphIndex);
      stream.putBytes(latin1.encode(indexInMap.toRadixString(16).padLeft(4, '0')));
      indices.add(indexInMap);
    }
    stream.putByte(0x3e);
  }

  int _glyphIndexToMapIndex(int glyphIndex) {
    _usedGlyphs.add(glyphIndex);
    if (_cidToGidMapType == CIDToGIDMapType.identity) {
      if (glyphIndex >= _glyphIndices.length) {
        _glyphIndices.addAll(List.generate(glyphIndex - _glyphIndices.length + 1, (index) => index + _glyphIndices.length));
        assert(_glyphIndices.length == glyphIndex + 1);
      }
      return glyphIndex;
    }

    var indexInMap = _glyphIndices.indexOf(glyphIndex);
    if (indexInMap == -1) {
      indexInMap = _glyphIndices.length;
      _glyphIndices.add(glyphIndex);
    }
    return indexInMap;
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
