import '../http/api_exception.dart';

/// User-facing copy for admin provisioning and occupancy errors.
String adminApiErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'DUPLICATE_EMAIL':
        return 'A user with this email already exists.';
      case 'PROTECTED_ROLE':
        return 'This account cannot be managed through resident APIs.';
      case 'DUPLICATE_ACTIVE_ASSIGNMENT':
        return 'This user already has an active assignment in the society.';
      case 'ACTIVE_OWNER_EXISTS':
        return 'This flat already has an active owner. End that occupancy first.';
      case 'ACTIVE_TENANT_EXISTS':
        return 'This flat already has an active tenant. End that occupancy first.';
      case 'NO_ACTIVE_OWNER':
        return 'This flat does not have an active owner.';
      case 'NO_ACTIVE_TENANT':
        return 'This flat does not have an active tenant.';
      case 'TENANT_STILL_ACTIVE':
        return 'End the tenant occupancy before ending the owner occupancy.';
      case 'INVALID_OCCUPANCY_TRANSITION':
        return 'That occupancy change is not allowed for the current flat state.';
      case 'OWNER_TENANT_SAME':
        return 'The owner cannot also be assigned as the tenant of the same flat.';
      case 'USER_INACTIVE':
        return 'That user account is inactive.';
      case 'INVALID_RESIDENT_ROLE':
        return 'That user does not have the required owner or tenant role.';
      case 'SOCIETY_MISMATCH':
        return 'That user is not a member of this society.';
      case 'FLAT_INACTIVE':
        return 'This flat is inactive.';
      case 'ACTIVE_OCCUPANCY_EXISTS':
        return 'End active occupancy assignments before deactivating the user.';
      case 'SELF_DEACTIVATION':
        return 'You cannot deactivate your own admin account.';
      case 'VALIDATION_ERROR':
        return error.message;
      case 'FORBIDDEN':
      case 'AUTH_REQUIRED':
      case 'UNAUTHORIZED':
        return 'You are not allowed to perform this action.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}
