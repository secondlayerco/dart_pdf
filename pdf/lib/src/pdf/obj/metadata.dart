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
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../document.dart';
import '../format/dict_stream.dart';
import '../format/name.dart';
import 'object.dart';

/// Pdf Metadata
class PdfMetadata extends PdfObject<PdfDictStream> {
  /// Store an Xml object
  PdfMetadata(
    PdfDocument pdfDocument,
    this.metadata,
  ) : super(
          pdfDocument,
          params: PdfDictStream(
            compress: false,
            encrypt: false,
          ),
        ) {
    pdfDocument.catalog.metadata = this;
  }

  final XmlDocument metadata;

  @override
  void prepare() {
    super.prepare();
    params['/Type'] = const PdfName('/Metadata');
    params['/Subtype'] = const PdfName('/XML');
    params.data = Uint8List.fromList(utf8.encode(metadata.toString()));
  }

  /// Build an XMP packet declaring PDF/UA-1 conformance. Pass the result to
  /// the [PdfMetadata] constructor.
  ///
  /// The returned document includes the `pdfuaid:part = 1` marker that
  /// accessibility checkers (veraPDF, PAC) use to recognise a PDF/UA-1
  /// document, plus Dublin Core title/language/producer entries that mirror
  /// the Info dictionary. All strings are XML-escaped.
  static XmlDocument pdfUa1Xmp({
    String? title,
    String? language,
    String? producer,
    String? author,
    String? subject,
    String? keywords,
    DateTime? createDate,
    DateTime? modifyDate,
    List<String>? extraRdfDescriptions,
  }) {
    final create = (createDate ?? DateTime.now().toUtc()).toUtc();
    final modify = (modifyDate ?? create).toUtc();
    final buf = StringBuffer();
    buf.write('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>');
    buf.write('<x:xmpmeta xmlns:x="adobe:ns:meta/">');
    buf.write(
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">');
    buf.write('<rdf:Description rdf:about=""'
        ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
        ' xmlns:xmp="http://ns.adobe.com/xap/1.0/"'
        ' xmlns:pdf="http://ns.adobe.com/pdf/1.3/"'
        ' xmlns:pdfuaid="http://www.aiim.org/pdfua/ns/id/">');
    if (title != null) {
      buf.write('<dc:title><rdf:Alt>'
          '<rdf:li xml:lang="x-default">${_xmlEscape(title)}</rdf:li>'
          '</rdf:Alt></dc:title>');
    }
    if (author != null) {
      buf.write('<dc:creator><rdf:Seq>'
          '<rdf:li>${_xmlEscape(author)}</rdf:li>'
          '</rdf:Seq></dc:creator>');
    }
    if (subject != null) {
      buf.write('<dc:description><rdf:Alt>'
          '<rdf:li xml:lang="x-default">${_xmlEscape(subject)}</rdf:li>'
          '</rdf:Alt></dc:description>');
    }
    if (language != null) {
      buf.write('<dc:language><rdf:Bag>'
          '<rdf:li>${_xmlEscape(language)}</rdf:li>'
          '</rdf:Bag></dc:language>');
    }
    if (keywords != null) {
      buf.write('<pdf:Keywords>${_xmlEscape(keywords)}</pdf:Keywords>');
    }
    if (producer != null) {
      buf.write('<pdf:Producer>${_xmlEscape(producer)}</pdf:Producer>');
    }
    buf.write('<xmp:CreateDate>${_xmpDate(create)}</xmp:CreateDate>');
    buf.write('<xmp:ModifyDate>${_xmpDate(modify)}</xmp:ModifyDate>');
    buf.write('<xmp:MetadataDate>${_xmpDate(modify)}</xmp:MetadataDate>');
    buf.write('<pdfuaid:part>1</pdfuaid:part>');
    buf.write('</rdf:Description>');
    extraRdfDescriptions?.forEach(buf.write);
    buf.write('</rdf:RDF>');
    buf.write('</x:xmpmeta>');
    buf.write('<?xpacket end="w"?>');
    return XmlDocument.parse(buf.toString());
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _xmpDate(DateTime d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${pad(d.month)}-${pad(d.day)}'
        'T${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}Z';
  }
}
