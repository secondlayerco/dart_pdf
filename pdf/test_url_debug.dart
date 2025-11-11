import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  print('Creating PDF with URL link...');
  
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Test URL Link:', style: pw.TextStyle(fontSize: 20)),
          pw.SizedBox(height: 20),
          pw.UrlLink(
            child: pw.Text(
              'Click here to visit GitHub',
              style: pw.TextStyle(
                fontSize: 16,
                color: PdfColors.blue,
                decoration: pw.TextDecoration.underline,
              ),
            ),
            destination: 'https://github.com/DavBfr/dart_pdf/',
          ),
          pw.SizedBox(height: 20),
          pw.Text('If the link above is clickable, the fix works!'),
        ],
      ),
    ),
  );

  print('Saving PDF...');
  final file = File('test_url_debug.pdf');
  await file.writeAsBytes(await pdf.save());
  print('PDF saved to: ${file.absolute.path}');
  print('Please open the PDF in Chrome and try clicking the link.');
}

