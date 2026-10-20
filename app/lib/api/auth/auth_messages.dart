import '../http/api_exception.dart';

/// User-facing copy for auth errors. Avoids username enumeration where practical.
String authErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'INVALID_CREDENTIALS':
        return 'Invalid username or password.';
      case 'LOGIN_LOCKED':
      case 'RATE_LIMITED':
        return 'Too many attempts. Try again later.';
      case 'LOGIN_DISABLED':
        return 'This account cannot sign in right now.';
      case 'INVALID_CURRENT_PASSWORD':
        return 'Current password is incorrect.';
      case 'WEAK_PASSWORD':
      case 'PASSWORD_UNCHANGED':
        return error.message;
      case 'INVALID_USERNAME':
        return 'Enter a valid username.';
      case 'NETWORK_TIMEOUT':
      case 'NETWORK_UNAVAILABLE':
      case 'NETWORK_ERROR':
      case 'TLS_ERROR':
        return error.message;
      case 'VALIDATION_ERROR':
        return 'Check your username and password and try again.';
      default:
        if (error.statusCode == 401) {
          return 'Invalid username or password.';
        }
        if (error.statusCode == 429) {
          return 'Too many attempts. Try again later.';
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

final usernamePattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{2,31}$');

bool isValidUsername(String value) => usernamePattern.hasMatch(value.trim());

bool isValidPasswordStrength(String value) {
  if (value.length < 10 || value.length > 128) return false;
  if (RegExp(r'\s').hasMatch(value)) return false;
  return RegExp(r'[A-Za-z]').hasMatch(value) && RegExp(r'\d').hasMatch(value);
}
