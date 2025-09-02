/// Creates a mapping from rune indices to string indices.
///
/// This is useful when working with Unicode text that contains surrogate pairs
/// (like emojis), where a single character may be represented by multiple
/// UTF-16 code units.
///
/// Returns a list where:
/// - The index in the list is the rune index
/// - The value at that index is the corresponding string index
/// - The last element is the length of the string
List<int> createRuneToStringIndexMap(String text) {
  final indices = <int>[];
  var stringIndex = 0;

  // Iterate through the string directly
  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    indices.add(stringIndex);

    // Check if this is a surrogate pair
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        // This is a surrogate pair, skip the low surrogate
        i++;
      }
    }

    stringIndex = i + 1;
  }

  // Add the length of the string as the last element
  indices.add(text.length);

  return indices;
}

/// Creates a mapping from code unit offsets to string indices.
///
/// This is useful when working with libraries like ICU that return offsets
/// in terms of UTF-16 code units, but you need to map these to actual
/// character positions in a Dart string.
///
/// Returns a list where:
/// - The index in the list is the code unit offset
/// - The value at that index is the corresponding string index
/// - The list length is the number of code units + 1, with the last element
///   being the length of the string
List<int> createCodeUnitToStringIndexMap(String text) {
  final indices = <int>[];

  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    indices.add(i);

    // Check if this is a surrogate pair
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        // This is a surrogate pair, add an entry for the low surrogate
        // that points to the same string index
        indices.add(i);
        i++; // Skip low surrogate
      }
    }
  }

  // Add the length of the string as the last element
  indices.add(text.length);

  return indices;
}
