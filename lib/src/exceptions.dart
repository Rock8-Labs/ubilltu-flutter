/// Base class for all errors thrown by the ubilltu client.
class UbilltuException implements Exception {
  UbilltuException(this.message);

  final String message;

  @override
  String toString() => 'UbilltuException: $message';
}

/// Thrown when the API returns a non-2xx response.
///
/// [body] is the decoded JSON error payload when available (e.g. `{"detail": ...}`).
class UbilltuApiException extends UbilltuException {
  UbilltuApiException({
    required this.statusCode,
    required String message,
    this.body,
  }) : super(message);

  final int statusCode;
  final Map<String, dynamic>? body;

  @override
  String toString() => 'UbilltuApiException($statusCode): $message';
}

/// Thrown when an authenticated call is made before [UbilltuClient.login].
class UbilltuAuthException extends UbilltuException {
  UbilltuAuthException(
      [super.message = 'Not authenticated — call login() first.']);
}
