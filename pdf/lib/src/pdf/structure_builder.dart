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

import 'document.dart';
import 'format/base.dart';
import 'format/name.dart';
import 'graphics.dart';
import 'obj/object.dart';
import 'obj/page.dart';
import 'obj/struct_elem.dart';
import 'obj/struct_tree_root.dart';

/// Category of non-structural marked content. Determines which /Type value
/// is written into the artifact's property list.
enum PdfArtifactType {
  /// Features typical of the layout, such as footnote rules (not footnotes
  /// themselves), table/figure borders, and separators.
  layout,

  /// Page-specific decoration like watermarks, backgrounds, bleed marks.
  page,

  /// Running headers, footers, page numbers, and other pagination artifacts.
  pagination,

  /// Pure visual backgrounds with no informational content.
  background,
}

/// High-level builder that threads marked-content tagging through the widget
/// paint pass. Widgets with a semantic role call [beginContent]/[endContent]
/// around their drawing operators; grouping widgets call [beginGroup]/
/// [endGroup] to introduce structural parents (e.g., /Sect, /Table, /L);
/// decorative drawing is wrapped in [beginArtifact]/[endArtifact] so screen
/// readers skip it.
///
/// The builder owns:
/// - the stack of currently-open structure elements (so new elements get
///   the correct /P parent reference),
/// - the per-page MCID counter (so marked-content identifiers are unique
///   within a page and dense from 0),
/// - the per-page MCID → structure element mapping used to populate the
///   parent tree at [finalizeTree].
///
/// Access it via [PdfDocument.structureBuilder].
class PdfStructureBuilder {
  PdfStructureBuilder(this.document)
      : assert(
          document.tagged,
          'PdfStructureBuilder requires PdfDocument(tagged: true)',
        );

  final PdfDocument document;

  final List<PdfStructElem> _stack = <PdfStructElem>[];
  final Map<PdfPage, List<PdfStructElem>> _pageMcids =
      <PdfPage, List<PdfStructElem>>{};

  PdfStructElem? _documentRoot;

  /// Lazily-created /Document element directly under [PdfStructTreeRoot].
  /// All top-level content and grouping elements become its descendants.
  /// PDF/UA-1 §7.1 requires this root element for conforming documents.
  PdfStructElem get documentRoot {
    if (_documentRoot != null) {
      return _documentRoot!;
    }
    final root = PdfStructElem(
      document,
      role: 'Document',
      parent: document.structTreeRoot,
      lang: document.language,
    );
    document.structTreeRoot.kids.add(root);
    _documentRoot = root;
    return root;
  }

  PdfObject get _currentParent =>
      _stack.isNotEmpty ? _stack.last : documentRoot;

  /// Begin a grouping structure element (no marked content of its own).
  /// Typical roles: /Sect, /Part, /Div, /Table, /TR, /L. Must be paired with
  /// [endGroup].
  PdfStructElem beginGroup(
    String role, {
    String? title,
    String? lang,
  }) {
    final elem = PdfStructElem(
      document,
      role: role,
      parent: _currentParent,
      title: title,
      lang: lang,
    );
    _attachToParent(elem);
    _stack.add(elem);
    return elem;
  }

  /// Close the most-recent [beginGroup].
  void endGroup() {
    assert(
      _stack.isNotEmpty,
      'endGroup called with no open structure element',
    );
    _stack.removeLast();
  }

  /// Begin a leaf content structure element and open a marked-content
  /// section on [canvas]. Typical roles: /P, /H1–/H6, /Figure, /Caption,
  /// /TH, /TD, /LI, /Lbl, /LBody. Must be paired with [endContent].
  PdfStructElem beginContent(
    String role, {
    required PdfPage page,
    required PdfGraphics canvas,
    String? alt,
    String? actualText,
    String? lang,
    String? title,
  }) {
    final elem = PdfStructElem(
      document,
      role: role,
      parent: _currentParent,
      page: page,
      alt: alt,
      actualText: actualText,
      lang: lang,
      title: title,
    );
    _attachToParent(elem);

    final mcid = _allocateMcid(page, elem);
    elem.addMarkedContent(mcid);
    canvas.beginMarkedContent(role, mcid: mcid);

    _stack.add(elem);
    return elem;
  }

  /// Close the most-recent [beginContent].
  void endContent(PdfGraphics canvas) {
    assert(
      _stack.isNotEmpty,
      'endContent called with no open structure element',
    );
    canvas.endMarkedContent();
    _stack.removeLast();
  }

  /// Open an artifact marked-content section on [canvas]. Artifact content
  /// is excluded from the structure tree and skipped by screen readers.
  /// Used for backgrounds, decorative borders, page headers/footers, and
  /// anything else that is purely visual.
  void beginArtifact(
    PdfGraphics canvas, {
    PdfArtifactType type = PdfArtifactType.layout,
  }) {
    canvas.beginMarkedContent(
      'Artifact',
      properties: <String, PdfDataType>{
        '/Type': PdfName('/${_artifactTypeName(type)}'),
      },
    );
  }

  /// Close the most-recent [beginArtifact].
  void endArtifact(PdfGraphics canvas) {
    canvas.endMarkedContent();
  }

  /// Populate the parent tree from recorded per-page MCID assignments and
  /// make sure each tagged page has a /StructParents key allocated. Called
  /// automatically by [PdfDocument] before serialisation; safe to call more
  /// than once.
  void finalizeTree() {
    _pageMcids.forEach((page, elems) {
      final key = page.ensureStructParentsKey();
      document.structTreeRoot.parentTree.setPageEntries(key, elems);
    });
  }

  void _attachToParent(PdfStructElem elem) {
    final parent = elem.parent;
    if (parent is PdfStructElem) {
      parent.addChild(elem);
    } else if (parent is PdfStructTreeRoot) {
      parent.kids.add(elem);
    }
  }

  int _allocateMcid(PdfPage page, PdfStructElem elem) {
    final list = _pageMcids.putIfAbsent(page, () => <PdfStructElem>[]);
    final mcid = list.length;
    list.add(elem);
    return mcid;
  }

  String _artifactTypeName(PdfArtifactType type) {
    switch (type) {
      case PdfArtifactType.layout:
        return 'Layout';
      case PdfArtifactType.page:
        return 'Page';
      case PdfArtifactType.pagination:
        return 'Pagination';
      case PdfArtifactType.background:
        return 'Background';
    }
  }
}
