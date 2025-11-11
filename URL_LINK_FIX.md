# AnnotationUrl Fix

## Problem

`AnnotationUrl` (and `AnnotationLink`) stopped working after commit `41d32371e797d07240dbb665194cd458620ec663` (PDF/A 3b, dated 2024-11-28).

### Root Cause

The commit changed the default flags for all PDF annotations to include `PdfAnnotFlags.print` by default. This was done to make annotations printable by default for PDF/A compliance.

However, `PdfAnnotFlags.print` means the annotation is **only visible when printing**, not when viewing the PDF on screen. This made URL links invisible and non-clickable when viewing PDFs.

### What Changed

In `pdf/lib/src/pdf/obj/annotation.dart`, the `PdfAnnotBase` constructor was modified:

```dart
PdfAnnotBase({
  // ... other parameters
  Set<PdfAnnotFlags>? flags,
  // ...
}) {
  this.flags = flags ??
      {
        PdfAnnotFlags.print,  // <-- This is the problem
      };
}
```

### PDF Annotation Flags Explained

- **No flags** (empty set): Annotation is visible both on screen and when printing
- **`PdfAnnotFlags.print`**: Annotation is ONLY visible when printing (invisible on screen)
- **`PdfAnnotFlags.noView`**: Annotation is NOT visible on screen (only when printing)
- **`PdfAnnotFlags.hidden`**: Annotation is completely hidden

## Solution

Fixed both `AnnotationUrl` and `AnnotationLink` in `pdf/lib/src/widgets/annotations.dart` by explicitly passing an empty flags set:

```dart
PdfAnnotUrlLink(
  rect: context.localToGlobal(box!),
  url: destination,
  date: date,
  author: author,
  subject: subject,
  // Empty flags set makes the link visible both on screen and when printing
  flags: {},
)
```

This ensures URL links are visible and clickable when viewing PDFs on screen, while still being visible when printing.

## Testing

To test the fix, run the test file:

```bash
dart test_url_link.dart
```

This will create a PDF with a clickable URL link. Open the PDF and verify:
1. The link is visible on screen
2. The link is clickable
3. Clicking the link opens the URL in a browser

## Files Changed

- `pdf/lib/src/widgets/annotations.dart`: Added `flags: {}` to both `AnnotationLink` and `AnnotationUrl`

