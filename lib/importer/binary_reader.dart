import 'dart:typed_data';

import 'import_error.dart';

final class BinaryReader {
  BinaryReader(Uint8List bytes, {this.path})
    : _data = ByteData.sublistView(bytes),
      length = bytes.length;

  final ByteData _data;
  final String? path;
  final int length;
  int offset = 0;

  void seek(int newOffset) {
    if (newOffset < 0 || newOffset > length) {
      throw ImportException(
        code: ImportErrorCode.invalidValue,
        message: 'Offset is outside the input.',
        path: path,
        offset: offset,
        details: {'target': newOffset, 'length': length},
      );
    }
    offset = newOffset;
  }

  int readUint8() {
    _require(1);
    return _data.getUint8(offset++);
  }

  int readUint16([Endian endian = Endian.little]) {
    _require(2);
    final value = _data.getUint16(offset, endian);
    offset += 2;
    return value;
  }

  int readUint32([Endian endian = Endian.little]) {
    _require(4);
    final value = _data.getUint32(offset, endian);
    offset += 4;
    return value;
  }

  Uint8List readBytes(int count) {
    if (count < 0) {
      throw ImportException(
        code: ImportErrorCode.invalidValue,
        message: 'Byte count must not be negative.',
        path: path,
        offset: offset,
        details: {'count': count},
      );
    }
    _require(count);
    final bytes = _data.buffer.asUint8List(_data.offsetInBytes + offset, count);
    offset += count;
    return Uint8List.fromList(bytes);
  }

  void _require(int count) {
    if (offset + count <= length) return;
    throw ImportException(
      code: ImportErrorCode.truncatedInput,
      message: 'Input ends before the requested value.',
      path: path,
      offset: offset,
      details: {'requested': count, 'remaining': length - offset},
    );
  }
}
