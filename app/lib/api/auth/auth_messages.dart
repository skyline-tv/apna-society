import '../http/api_exception.dart';

/// User-facing copy for auth errors. Never reveals whether an email exists.
String authErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'OTP_COOLDOWN':
        return 'Please wait before requesting another code.';
      case 'OTP_RATE_LIMIT':
      case 'RATE_LIMITED':
        return 'Too many requests. Try again later.';
      case 'OTP_ATTEMPTS_EXCEEDED':
        return 'Too many invalid attempts. Request a new code.';
      case 'INVALID_OTP':
        return 'Invalid or expired code.';
      case 'LOGIN_DISABLED':
        return 'This account cannot sign in right now.';
      case 'NETWORK_TIMEOUT':
      case 'NETWORK_UNAVAILABLE':
      case 'NETWORK_ERROR':
      case 'TLS_ERROR':
        return error.message;
      case 'VALIDATION_ERROR':
        return 'Enter a valid email address.';
      default:
        if (error.statusCode == 401) {
          return 'Invalid or expired code.';
        }
        if (error.statusCode == 429) {
          return 'Too many requests. Try again later.';
        }
        return error.message;
    }
  }
  if (error is StateError) {
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}

final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidEmail(String value) => emailPattern.hasMatch(value.trim());
