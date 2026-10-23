import '../../api/http/api_exception.dart';

String visitorErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'NO_ACTIVE_RESIDENT':
        return 'This flat has no active resident to approve visitors.';
      case 'FLAT_INACTIVE':
        return 'This flat is inactive.';
      case 'INVALID_OCCUPANCY':
        return 'This flat occupancy cannot receive visitors.';
      case 'VISITOR_EMAIL_REQUIRED':
        return 'A visitor or resident email is required for entry OTP delivery.';
      case 'NOT_APPROVED':
        return 'Visitor is not approved for entry yet.';
      case 'OTP_MISSING':
        return 'No active entry OTP for this visitor.';
      case 'OTP_EXPIRED':
        return 'This OTP has expired. Ask the resident to share a new one.';
      case 'OTP_INVALID':
        return 'Invalid or expired OTP. Try again.';
      case 'OTP_MAX_ATTEMPTS':
        return 'Too many incorrect OTP attempts. Entry is locked.';
      case 'OTP_NOT_VERIFIED':
        return 'Verify the visitor OTP before recording entry.';
      case 'ALREADY_ENTERED':
        return 'This visitor has already entered.';
      case 'NOT_ENTERED':
        return 'Visitor has not entered yet.';
      case 'CHECKOUT_CONFLICT':
        return 'Checkout conflict. Refresh and try again.';
      case 'NOT_CURRENT_APPROVER':
        return 'You are no longer the approver for this flat.';
      case 'INVALID_STATUS':
        return 'This action is not allowed in the current visitor status.';
      case 'ALREADY_PROCESSED':
        return 'This request was already processed.';
      case 'REQUEST_EXPIRED':
        return 'This request has expired. Keep the visitor outside.';
      case 'PARCEL_NOT_ENTRY':
        return 'Parcel authorization cannot be used for visitor entry.';
      case 'RATE_LIMITED':
        return 'Too many OTP attempts. Wait and try again.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this visitor action.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}
