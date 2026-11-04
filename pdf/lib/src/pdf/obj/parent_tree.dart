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

import 'dart:collection';

import '../document.dart';
import '../format/array.dart';
import '../format/dict.dart';
import '../format/null_value.dart';
import '../format/num.dart';
import 'object.dart';
import 'struct_elem.dart';

/// Number tree (PDF 1.7 §7.9.7) mapping each page's /StructParents integer
/// key to the structure elements referenced by marked content on that page.
///
/// For a page with MCIDs 0..N, the entry at that page's /StructParents key
/// is an array of length N+1 where index `i` is the structure element that
/// contains MCID `i` (or null for MCIDs that are artifacts and have no
/// structure element reference).
///
/// This implementation emits a single-leaf number tree. Documents with
/// very large numbers of pages may benefit from a balanced tree; we can
/// add that later if needed.
class PdfParentTree extends PdfObject<PdfDict> {
  PdfParentTree(PdfDocument pdfDocument)
      : super(pdfDocument, params: PdfDict());

  /// Entries keyed by /StructParents integer. Values are either:
  /// - `List<PdfStructElem?>` — one element per MCID on the page
  /// - `PdfStructElem` — single element for an annotation key
  final SplayTreeMap<int, Object> entries = SplayTreeMap<int, Object>();

  /// Record the structure elements for a page. [structElems] must be ordered
  /// so that index `i` is the element containing MCID `i`. Null entries are
  /// allowed for MCIDs that are artifacts (marked content not referenced by
  /// any structure element).
  void setPageEntries(int key, List<PdfStructElem?> structElems) {
    entries[key] = List<PdfStructElem?>.unmodifiable(structElems);
  }

  /// Record the structure element referenced by a single annotation.
  void setAnnotationEntry(int key, PdfStructElem elem) {
    entries[key] = elem;
  }

  @override
  void prepare() {
    super.prepare();

    final nums = PdfArray();
    entries.forEach((key, value) {
      nums.add(PdfNum(key));
      if (value is List<PdfStructElem?>) {
        final array = PdfArray();
        for (final elem in value) {
          array.add(elem == null ? const PdfNull() : elem.ref());
        }
        nums.add(array);
      } else if (value is PdfStructElem) {
        nums.add(value.ref());
      }
    });

    params['/Nums'] = nums;
  }
}
