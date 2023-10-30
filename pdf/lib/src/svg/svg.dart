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

import 'package:xml/xml.dart';

import '../../pdf.dart';
import '../../widgets.dart';
import 'brush.dart';
import 'clip_path.dart';
import 'operation.dart';
import 'painter.dart';
import 'parser.dart';
import 'transform.dart';

class EmbeddedSvg extends SvgOperation {
  EmbeddedSvg(
    this.children,
    this.width,
    this.height,
    this.x,
    this.y,
    SvgBrush brush,
    SvgClipPath clip,
    SvgTransform transform,
    SvgPainter painter,
  ) : super(brush, clip, transform, painter);

  factory EmbeddedSvg.fromXml(
      XmlElement element, SvgPainter painter, SvgBrush brush) {
    final _brush = SvgBrush.fromXml(element, brush, painter);

    print('element.outerXml: ${element.outerXml}');
    print('element.root.outerXml: ${element.root.outerXml}');
    print('element.attributes: ${element.attributes}');
  

    // TODO:
    // - Get the width and height from the SVG
    // - Get the transform X & Y position from the parent transform

    final width =
        SvgParser.getNumeric(element, 'width', _brush, defaultValue: 0)!
            .sizeValue;
    final height =
        SvgParser.getNumeric(element, 'height', _brush, defaultValue: 0)!
            .sizeValue;
    final x =
        SvgParser.getNumeric(element, 'x', _brush, defaultValue: 0)!.sizeValue;
    final y =
        SvgParser.getNumeric(element, 'y', _brush, defaultValue: 0)!.sizeValue;

    print('width: $width height: $height x: $x y: $y');

    final hrefAttr = element.getAttribute('href') ??
        element.getAttribute('href', namespace: 'http://www.w3.org/1999/xlink');

    if (hrefAttr != null && hrefAttr.startsWith('data:image/svg+xml')) {
      final px = hrefAttr.substring(hrefAttr.indexOf(';') + 1);
      if (px.startsWith('base64,')) {
        final b = px.substring(7).replaceAll(RegExp(r'\s'), '');
        final bytes = base64.decode(b);

        final svgValue = utf8.decode(bytes);
        print('svgValue: $svgValue');
        // final svgImage = SvgImage(svg: svgValue);
        // print('svgImage: $svgImage');

        final xml = XmlDocument.parse(svgValue);
        final parser = SvgParser(
          xml: xml,
          // colorFilter: colorFilter,
        );

        print('VERSION 1');



        final rootChildren = <XmlNode>[];

        for (final child in parser.root.children) {
          if (child is! XmlElement) {
            continue;
          }
          print('child.name.local: ${child.name.local}');
          if (child.name.local == 'g') {
            rootChildren.addAll(child.children);
          } else {
            rootChildren.add(child);
          }
        }

        final children = rootChildren
          .whereType<XmlElement>()
          .where((element) => element.name.local != 'symbol')
          .map<SvgOperation?>(
              (child) => SvgOperation.fromXml(child, painter, _brush))
          .whereType<SvgOperation>();

        print('\n\n------------\n\n');

        void logChildren(List<XmlNode> nodes, int level) {
          for (final node in nodes) {
            if (node is XmlElement) {
              print('${'CHILD =>  ' * level}${node.name.local}');
              logChildren(node.children, level + 1);
            }
          }
        }

        logChildren(rootChildren, 0);

        print('\n\n------------\n\n');

        


        return EmbeddedSvg(
          children,
          width,
          height,
          x,
          y,
          _brush,
          SvgClipPath.fromXml(element, painter, _brush),
          SvgTransform.fromXml(element),
          painter,
        );

      }
    }

    return EmbeddedSvg(
      [],
      width,
      height,
      x,
      y,
      _brush,
      SvgClipPath.fromXml(element, painter, _brush),
      SvgTransform.fromXml(element),
      painter,
    );

    // final children = element.children
    //     .whereType<XmlElement>()
    //     .where((element) => element.name.local != 'symbol')
    //     .map<SvgOperation?>(
    //         (child) => SvgOperation.fromXml(child, painter, _brush))
    //     .whereType<SvgOperation>();

    // return EmbeddedSvg(
    //   children,
    //   _brush,
    //   SvgClipPath.fromXml(element, painter, _brush),
    //   SvgTransform.fromXml(element),
    //   painter,
    // );
  }

  final double x;

  final double y;

  final double width;

  final double height;

  final Iterable<SvgOperation> children;

  @override
  void paintShape(PdfGraphics canvas) {
    for (final child in children) {
      child.paint(canvas);
    }
  }

  @override
  void drawShape(PdfGraphics canvas) {
    for (final child in children) {
      child.draw(canvas);
    }
  }

  @override
  PdfRect boundingBox() => PdfRect(x, y, width, height);
  // PdfRect boundingBox() {
  //   var x = double.infinity, y = double.infinity, w = 0.0, h = 0.0;
  //   for (final child in children) {
  //     final b = child.boundingBox();
  //     x = min(b.x, x);
  //     y = min(b.y, y);
  //     w = max(b.width, w);
  //     h = max(b.height, w);
  //   }

  //   return PdfRect(x, y, w, h);
  // }
}
