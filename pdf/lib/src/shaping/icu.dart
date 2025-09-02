import 'dart:ffi';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';

import 'unicode_utils.dart';

// This file needs library `ICU` to be available in the environment.
// OSX: brew install icu4c
// Linux: apt-get install libicu-dev

//ignore: avoid_classes_with_only_static_members
abstract class IcuBinding {
  // Returns offsets in terms of String offsets
  static List<int> getIcuLineBreakOffsets(String text) {
    final icuBreakOffsets = _getIcuLineBreakOffsetsUTF16(text);
    final mapping = createCodeUnitToStringIndexMap(text);
    return icuBreakOffsets.map((offset) => mapping[offset]).toList();
  }

  // Returns offsets in terms of UTF-16 code units.
  static List<int> _getIcuLineBreakOffsetsUTF16(String text) {
    // Prepare inputs for ICU
    final errorCodePtr = calloc<Int32>();
    final textPtr = text.toNativeUtf16();

    const UBRK_LINE = 2;
    final brkIter = _ubrkOpen(
      UBRK_LINE,
      nullptr,
      textPtr.cast<Void>(),
      -1,
      errorCodePtr,
    );
    if (errorCodePtr.value > 0) {
      print('ICU open error: ${errorCodePtr.value}');
      return [];
    }

    final icuBreakOffsets = _icuBreakOffsetsIterator(brkIter).toList();

    _ubrkClose(brkIter);

    calloc.free(textPtr);
    calloc.free(errorCodePtr);

    return icuBreakOffsets;
  }

  static Iterable<int> _icuBreakOffsetsIterator(Pointer<Opaque> brkIter) sync* {
    var pos = 0;
    while ((pos = _ubrkNext(brkIter)) != -1) {
      yield pos;
    }
  }

  // Change the path if needed for Linux/Windows!
  static final DynamicLibrary _icu = DynamicLibrary.open(_getIcuLibraryPath());

  static String _getIcuLibraryPath() {
    // Check for environment variable override first
    final envPath = Platform.environment['ICU_LIB_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      return envPath;
    }

    if (Platform.isMacOS) {
      return '/opt/homebrew/opt/icu4c/lib/libicuuc.dylib';
    }

    // For Linux, try common locations in order
    final commonPaths = [
      '/usr/lib/x86_64-linux-gnu/libicuuc.so',
      '/usr/lib/libicuuc.so',
      '/usr/lib/libicuuc.so.76',
      '/usr/lib/libicuuc.so.77',
      '/usr/lib64/libicuuc.so',
      '/lib/x86_64-linux-gnu/libicuuc.so',
    ];

    for (final path in commonPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // Fallback to the original hardcoded path
    return '/usr/lib/x86_64-linux-gnu/libicuuc.so';
  }

  static final _ubrkOpen = _icu.lookupFunction<_UBrkOpenC, _UBrkOpenDart>(
    _findFunctionName(_icu, 'ubrk_open'),
  );
  static final _ubrkNext = _icu.lookupFunction<_UBrkNextC, _UBrkNextDart>(
    _findFunctionName(_icu, 'ubrk_next'),
  );
  static final _ubrkClose = _icu.lookupFunction<_UBrkCloseC, _UBrkCloseDart>(
    _findFunctionName(_icu, 'ubrk_close'),
  );

  // Find the ICU function name based on known versions.
  static String _findFunctionName(DynamicLibrary icu, String name) {
    // Try common ICU versions, including Alpine Linux versions
    const versions = [
      '76',
      '77',
      '66',
      '74',
      '75',
      '73',
      '72',
      '71',
      '70',
      '69',
      '68',
      '67',
    ];

    // First try versioned function names
    final versionedName = versions
        .map((v) => '${name}_$v')
        .firstWhereOrNull((n) => icu.providesSymbol(n));
    if (versionedName != null) {
      return versionedName;
    }

    // If no versioned function found, try the unversioned name
    if (icu.providesSymbol(name)) {
      return name;
    }

    // If still not found, throw an exception with debugging info
    throw Exception(
      'Could not find ICU function "$name". Tried versions: ${versions.join(', ')} and unversioned name.',
    );
  }
}

// ICU uses opaque types and handles errors with UErrorCode (int32).
typedef _UBrkIterator = Opaque;

typedef _UBrkOpenC = Pointer<_UBrkIterator> Function(
  Int32,
  Pointer<Utf8>,
  Pointer<Void>,
  Int32,
  Pointer<Int32>,
);
typedef _UBrkOpenDart = Pointer<_UBrkIterator> Function(
  int,
  Pointer<Utf8>,
  Pointer<Void>,
  int,
  Pointer<Int32>,
);

typedef _UBrkNextC = Int32 Function(Pointer<_UBrkIterator>);
typedef _UBrkNextDart = int Function(Pointer<_UBrkIterator>);

typedef _UBrkCloseC = Void Function(Pointer<_UBrkIterator>);
typedef _UBrkCloseDart = void Function(Pointer<_UBrkIterator>);
