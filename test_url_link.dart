import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      build: (context) => pw.Column(
        children: [
          pw.Text('Test URL Links', style: pw.TextStyle(fontSize: 24)),
          pw.SizedBox(height: 20),
          pw.UrlLink(
            child: pw.Text(
              'Click here to visit GitHub',
              style: pw.TextStyle(
                decoration: pw.TextDecoration.underline,
                color: PdfColors.blue,
              ),
            ),
            destination: 'https://github.com/DavBfr/dart_pdf/',
          ),
          pw.SizedBox(height: 20),
          pw.Text('The link above should be clickable when viewing the PDF on screen.'),
        ],
      ),
    ),
  );

  final file = File('test_url_link.pdf');
  await file.writeAsBytes(await pdf.save());
  print('PDF created: ${file.path}');
  print('Open this PDF and verify the link is clickable on screen.');
}

