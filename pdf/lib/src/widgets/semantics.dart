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
import 'widget.dart';

/// Wraps a child in a grouping structure element (PDF 1.7 §14.7.3). The
/// element has no marked content of its own; it exists to parent other
/// structure elements in the tree.
///
/// Example roles: `Sect`, `Part`, `Div`, `BlockQuote`, `Table`, `TR`, `L`,
/// `LI`, `Lbl`, `LBody`, `THead`, `TBody`, `TFoot`.
///
/// Has no effect when the document was not constructed with `tagged: true`;
/// in that case it transparently paints its child.
class Semantics extends SingleChildWidget {
  Semantics({
    required this.role,
    required Widget child,
    this.lang,
    this.title,
  }) : super(child: child);

  /// Structure type without the leading slash. See [PdfStructElem] for the
  /// catalogue of standard roles.
  final String role;

  /// BCP 47 language tag override for this subtree.
  final String? lang;

  /// Short human-readable label for the element (/T entry).
  final String? title;

  @override
  void paint(Context context) {
    super.paint(context);
    if (child == null) {
      return;
    }

    final document = context.document;
    if (!document.tagged) {
      paintChild(context);
      return;
    }

    final builder = document.structureBuilder;
    builder.beginGroup(role, lang: lang, title: title);
    try {
      paintChild(context);
    } finally {
      builder.endGroup();
    }
  }
}

/// Wraps a child in a leaf content structure element whose drawing operators
/// make up a single marked-content section. Used for anything a screen reader
/// should read as one semantic unit: paragraphs, headings, figures, captions,
/// table cells, list labels.
///
/// Typical roles: `P`, `H1`–`H6`, `Figure`, `Caption`, `Formula`, `Note`,
/// `TH`, `TD`, `Lbl`, `LBody`, `Code`, `Quote`.
///
/// For figures, provide [alt]. If the content is decorative, prefer
/// [Artifact] instead so it is excluded from the structure tree.
///
/// Has no effect when the document was not constructed with `tagged: true`;
/// in that case it transparently paints its child.
class MarkedContent extends SingleChildWidget {
  MarkedContent({
    required this.role,
    required Widget child,
    this.alt,
    this.actualText,
    this.lang,
    this.title,
  }) : super(child: child);

  /// Structure type without the leading slash.
  final String role;

  /// Alternative text announced by screen readers. Required on `Figure`
  /// elements for PDF/UA compliance.
  final String? alt;

  /// Exact textual replacement for the element's content. Use when the
  /// spoken form differs from the rendered glyphs (e.g., abbreviations).
  final String? actualText;

  /// BCP 47 language tag override for this element.
  final String? lang;

  /// Short human-readable label for the element (/T entry).
  final String? title;

  @override
  void paint(Context context) {
    super.paint(context);
    if (child == null) {
      return;
    }

    final document = context.document;
    if (!document.tagged) {
      paintChild(context);
      return;
    }

    final builder = document.structureBuilder;
    builder.beginContent(
      role,
      page: context.page,
      canvas: context.canvas,
      alt: alt,
      actualText: actualText,
      lang: lang,
      title: title,
    );
    try {
      paintChild(context);
    } finally {
      builder.endContent(context.canvas);
    }
  }
}

/// Wraps a child in an artifact marked-content section. Artifact content is
/// excluded from the structure tree and not announced by screen readers.
/// Use for decorative backgrounds, running headers/footers, page numbers,
/// and anything else that carries no information.
///
/// Has no effect when the document was not constructed with `tagged: true`;
/// in that case it transparently paints its child.
class Artifact extends SingleChildWidget {
  Artifact({
    required Widget child,
    this.type = PdfArtifactType.layout,
  }) : super(child: child);

  final PdfArtifactType type;

  @override
  void paint(Context context) {
    super.paint(context);
    if (child == null) {
      return;
    }

    final document = context.document;
    if (!document.tagged) {
      paintChild(context);
      return;
    }

    final builder = document.structureBuilder;
    builder.beginArtifact(context.canvas, type: type);
    try {
      paintChild(context);
    } finally {
      builder.endArtifact(context.canvas);
    }
  }
}
