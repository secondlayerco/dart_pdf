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
import '../format/base.dart';
import '../format/dict.dart';
import '../format/name.dart';
import '../format/num.dart';
import '../format/string.dart';
import 'object.dart';
import 'page.dart';

/// A single structure element in the structure tree (PDF 1.7 §14.7.2).
///
/// Each element has a [role] (structure type) that describes its semantic
/// purpose: a paragraph, heading, figure, table cell, list item, etc.
/// Elements form a tree via [parent]/[kids], and leaf elements reference
/// marked-content sections in page content streams via [addMarkedContent].
class PdfStructElem extends PdfObject<PdfDict> {
  PdfStructElem(
    PdfDocument pdfDocument, {
    required this.role,
    required this.parent,
    this.page,
    this.alt,
    this.actualText,
    this.lang,
    this.title,
  }) : super(
          pdfDocument,
          params: PdfDict.values({
            '/Type': const PdfName('/StructElem'),
          }),
        );

  /// Structure type, without the leading slash. Examples: "P", "H1", "Figure",
  /// "Document", "Sect", "Table", "TR", "TH", "TD", "L", "LI", "Lbl", "LBody".
  final String role;

  /// Parent object in the structure tree. This is either a
  /// [PdfStructTreeRoot] or another [PdfStructElem].
  final PdfObject parent;

  /// Page on which this element's marked content lives. When set, individual
  /// kid MCIDs do not need a per-kid /Pg entry.
  PdfPage? page;

  /// Alternative text. Required on /Figure elements for PDF/UA.
  String? alt;

  /// Exact textual replacement for the element's content. Used for Unicode
  /// mapping fallbacks and non-text content whose spoken form differs from
  /// its glyphs (e.g., abbreviations expanded to full words).
  String? actualText;

  /// BCP 47 language tag override for this element's content.
  String? lang;

  /// Short human-readable title for the element. Not the same as the heading
  /// text in /H1..H6 — this is an element-level label.
  String? title;

  /// Children. Entries are one of:
  /// - [PdfStructElem] — a child structure element
  /// - [int] — a marked-content identifier (MCID) on [page]
  /// - [_MarkedContentRef] — an MCID on a different page (built via
  ///   [addMarkedContent] when [onPage] differs from [page])
  final List<Object> kids = <Object>[];

  /// Append a child structure element.
  void addChild(PdfStructElem child) => kids.add(child);

  /// Reference a marked-content section in a page content stream. If [onPage]
  /// matches this element's [page] (or [page] is set and [onPage] is null),
  /// the kid is emitted as a bare integer. Otherwise a /MCR dictionary is
  /// emitted to disambiguate the page.
  void addMarkedContent(int mcid, {PdfPage? onPage}) {
    final targetPage = onPage ?? page;
    if (targetPage != null && targetPage == page) {
      kids.add(mcid);
    } else if (targetPage != null) {
      kids.add(_MarkedContentRef(targetPage, mcid));
    } else {
      // No page recorded; store as MCID and let caller set /Pg on the element.
      kids.add(mcid);
    }
  }

  @override
  void prepare() {
    super.prepare();

    params['/S'] = PdfName('/$role');
    params['/P'] = parent.ref();

    if (page != null) {
      params['/Pg'] = page!.ref();
    }
    if (alt != null) {
      params['/Alt'] = PdfString.fromString(alt!);
    }
    if (actualText != null) {
      params['/ActualText'] = PdfString.fromString(actualText!);
    }
    if (lang != null) {
      params['/Lang'] = PdfString.fromString(lang!);
    }
    if (title != null) {
      params['/T'] = PdfString.fromString(title!);
    }

    if (kids.isEmpty) {
      return;
    }
    if (kids.length == 1) {
      params['/K'] = _kidToPdf(kids.single);
    } else {
      final array = PdfArray();
      for (final kid in kids) {
        array.add(_kidToPdf(kid));
      }
      params['/K'] = array;
    }
  }

  PdfDataType _kidToPdf(Object kid) {
    if (kid is int) {
      return PdfNum(kid);
    }
    if (kid is PdfStructElem) {
      return kid.ref();
    }
    if (kid is _MarkedContentRef) {
      return PdfDict.values({
        '/Type': const PdfName('/MCR'),
        '/Pg': kid.page.ref(),
        '/MCID': PdfNum(kid.mcid),
      });
    }
    throw StateError('Unsupported structure element kid: $kid');
  }
}

class _MarkedContentRef {
  const _MarkedContentRef(this.page, this.mcid);
  final PdfPage page;
  final int mcid;
}
