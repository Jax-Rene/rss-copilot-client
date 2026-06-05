class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401 || code == 'UNAUTHORIZED';

  bool get isBadRequest => statusCode == 400 || code == 'BAD_REQUEST';

  bool get isPayloadTooLarge =>
      statusCode == 413 || code == 'PAYLOAD_TOO_LARGE';

  bool get isNotFound => statusCode == 404 || code == 'NOT_FOUND';

  @override
  String toString() {
    return 'ApiException(statusCode: $statusCode, code: $code, message: $message)';
  }
}

class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ServerHealthException implements Exception {
  const ServerHealthException(this.message);

  final String message;

  @override
  String toString() => message;
}
