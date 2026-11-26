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

import '../document.dart';
import 'object_stream.dart';

/// Unicode character map object
class PdfUnicodeCmap extends PdfObjectStream {
  /// Create a Unicode character map object
  PdfUnicodeCmap(PdfDocument pdfDocument, this.protect) : super(pdfDocument);

  // character code to unicode
  final cmap = <int, int>{0: 0};

  final _sequences = <int, String>{};
  void setSource(int cid, String source) {
    final runes = source.runes;
    if (runes.length == 1) {
      cmap[cid] = runes.first;
    } else {
      _sequences[cid] = source;
    }
  }

  /// Protects the text from being "seen" by the PDF reader.
  final bool protect;

  @override
  void prepare() {
    buf.putString('/CIDInit/ProcSet\nfindresource begin\n'
        '12 dict begin\n'
        'begincmap\n'
        '/CIDSystemInfo<<\n'
        '/Registry (Adobe)\n'
        '/Ordering (UCS)\n'
        '/Supplement 0\n'
        '>> def\n'
        '/CMapName/Adobe-Identity-UCS def\n'
        '/CMapType 2 def\n'
        '1 begincodespacerange\n'
        '<0000> <FFFF>\n'
        'endcodespacerange\n');

    final sources = {
      for (final entry in cmap.entries)
        entry.key: String.fromCharCode(entry.value),
      ..._sequences,
    };
    final entries = sources.entries.toList();
    for (var start = 0; start < entries.length; start += 100) {
      final block = entries.skip(start).take(100);
      buf.putString('${block.length} beginbfchar\n');
      for (final entry in block) {
        final text = protect ? (entry.key == 0 ? '\u0000' : ' ') : entry.value;
        final target = text.codeUnits.map(_hexUnit).join();
        buf.putString('<${_hexUnit(entry.key)}> <$target>\n');
      }
      buf.putString('endbfchar\n');
    }

    buf.putString('endcmap\n'
        'CMapName currentdict /CMap defineresource pop\n'
        'end\n'
        'end');
    super.prepare();
  }

  static String _hexUnit(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(4, '0');
}
