import '../http/api_exception.dart';

/// User-facing copy for auth errors. Never reveals whether a mobile exists.
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
      case 'SMS_SEND_FAILED':
      case 'SMS_TIMEOUT':
      case 'SMS_NOT_CONFIGURED':
      case 'SMS_VERIFY_FAILED':
        return 'Unable to send or verify SMS right now. Try again later.';
      case 'INVALID_MOBILE':
        return 'Enter a valid mobile number.';
      case 'NETWORK_TIMEOUT':
      case 'NETWORK_UNAVAILABLE':
      case 'NETWORK_ERROR':
      case 'TLS_ERROR':
        return error.message;
      case 'VALIDATION_ERROR':
        return 'Enter a valid mobile number.';
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

/// Indian mobile: 10 digits starting 6–9, optionally with +91 / 91 / 0 prefix.
bool isValidIndianMobile(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) {
    return RegExp(r'^[6-9]\d{9}$').hasMatch(digits);
  }
  if (digits.length == 12 && digits.startsWith('91')) {
    return RegExp(r'^91[6-9]\d{9}$').hasMatch(digits);
  }
  if (digits.length == 11 && digits.startsWith('0')) {
    return RegExp(r'^0[6-9]\d{9}$').hasMatch(digits);
  }
  return false;
}

/// Build API mobile payload from country dial code (+91) and local digits.
String composeMobileForApi({
  required String countryDialCode,
  required String localNumber,
}) {
  final dial = countryDialCode.trim().replaceAll(RegExp(r'[^\d+]'), '');
  final local = localNumber.replaceAll(RegExp(r'\D'), '');
  if (dial.startsWith('+')) {
    return '$dial$local';
  }
  return '+$dial$local';
}
