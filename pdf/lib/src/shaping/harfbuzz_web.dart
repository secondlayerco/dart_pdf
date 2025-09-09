import 'harfbuzz_types.dart';
export 'harfbuzz_types.dart';

class HarfbuzzBinding {
  HarfbuzzBinding();

  T _error<T>() => throw Exception('Harfbuzz not supported on web');

  List<String> listLoaders() => _error();
  HarfbuzzFace faceFromFile(String filename, int faceIndex) => _error();
  void faceDestroy(HarfbuzzFace face) => _error();

  String faceGetName(HarfbuzzFace face, HarfBuzzName name) => _error();

  List<(int, int)> faceGetUnicodes(HarfbuzzFace face) => _error();

  HarfbuzzFont fontCreate(HarfbuzzFace face) => _error();
  void fontDestroy(HarfbuzzFont font) => _error();

  double fontStyleGetValue(HarfbuzzFont font, HarfBuzzStyle style) => _error();

  void fontSetScale(HarfbuzzFont font, double xScale, double yScale) => _error();
  HarfbuzzFontExtents fontExtentsForDirection(HarfbuzzFont font, HarfBuzzDirection direction) => _error();

  HarfbuzzBuffer bufferCreate() => _error();
  void bufferDestroy(HarfbuzzBuffer buffer) => _error();

  void bufferAddString(HarfbuzzBuffer buffer, String str) => _error();

  void bufferGuessSegmentProperties(HarfbuzzBuffer buffer) => _error();

  HarfBuzzDirection bufferGetDirection(HarfbuzzBuffer buffer) => _error();

  void bufferSetDirection(HarfbuzzBuffer buffer, HarfBuzzDirection direction) => _error();

  void shape(HarfbuzzFont font, HarfbuzzBuffer buffer) => _error();

  List<HarfbuzzGlyphPosition> getGlyphPositions(HarfbuzzBuffer buffer) => _error();

  List<HarfbuzzGlyphInfo> getGlyphInfos(HarfbuzzBuffer buffer) => _error();
}

final class HarfbuzzFace {}

final class HarfbuzzFont {}

final class HarfbuzzBuffer {}
