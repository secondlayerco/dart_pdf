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
import '../format/array.dart';
import '../format/dict.dart';
import '../format/name.dart';
import '../format/num.dart';
import 'object.dart';
import 'parent_tree.dart';
import 'struct_elem.dart';

/// Root of the structure tree (PDF 1.7 §14.7.2).
///
/// The structure tree describes the logical document structure used by
/// assistive technology. A tagged PDF must have a [PdfStructTreeRoot]
/// referenced from the document catalog.
class PdfStructTreeRoot extends PdfObject<PdfDict> {
  PdfStructTreeRoot(PdfDocument pdfDocument)
      : super(
          pdfDocument,
          params: PdfDict.values({
            '/Type': const PdfName('/StructTreeRoot'),
          }),
        ) {
    parentTree = PdfParentTree(pdfDocument);
  }

  /// Top-level children. Usually a single Document element whose children
  /// make up the body of the tree.
  final List<PdfStructElem> kids = <PdfStructElem>[];

  /// Number tree mapping page /StructParents keys to arrays of structure
  /// element references (indexed by MCID).
  late final PdfParentTree parentTree;

  /// Maps non-standard role names to standard structure types. Required when
  /// a structure element uses a role that is not in the standard set.
  final Map<String, String> roleMap = <String, String>{};

  int _nextStructParentsKey = 0;

  /// Reserves the next /StructParents key for a page or annotation that
  /// contains marked content. The returned integer is stored on the page as
  /// its /StructParents value, and is used to look up the page's MCID → element
  /// mapping in the parent tree.
  int allocateStructParentsKey() => _nextStructParentsKey++;

  /// The next key that will be allocated. Emitted as /ParentTreeNextKey.
  int get nextStructParentsKey => _nextStructParentsKey;

  @override
  void prepare() {
    super.prepare();

    if (kids.isNotEmpty) {
      params['/K'] = kids.length == 1
          ? kids.single.ref()
          : PdfArray.fromObjects(kids);
    }

    params['/ParentTree'] = parentTree.ref();
    params['/ParentTreeNextKey'] = PdfNum(_nextStructParentsKey);

    if (roleMap.isNotEmpty) {
      final map = PdfDict();
      roleMap.forEach((from, to) {
        map['/$from'] = PdfName('/$to');
      });
      params['/RoleMap'] = map;
    }
  }
}
