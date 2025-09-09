enum IcuBreakType {
  character(0),
  word(1),
  line(2),
  sentence(3);

  const IcuBreakType(this.value);
  final int value;
}
