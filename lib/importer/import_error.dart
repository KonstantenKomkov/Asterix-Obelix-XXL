import 'dart:convert';

enum ImportErrorCode {
  invalidArguments,
  fileNotFound,
  truncatedInput,
  invalidMagic,
  invalidValue,
  unsupportedVersion,
  ioFailure,
}

final class ImportException implements Exception {
  const ImportException({
    required this.code,
    required this.message,
    this.path,
    this.offset,
    this.details = const {},
  });

  final ImportErrorCode code;
  final String message;
  final String? path;
  final int? offset;
  final Map<String, Object> details;

  Map<String, Object> toJson() => {
    'error': code.name,
    'message': message,
    if (path case final value?) 'path': value,
    if (offset case final value?) 'offset': value,
    if (details.isNotEmpty) 'details': details,
  };

  @override
  String toString() => jsonEncode(toJson());
}
