/** Resident FCM is for OWNER/TENANT accounts only. Staff never get device pushes. */
export function isResidentPushRole(roles: readonly string[] | undefined): boolean {
  if (!roles?.length) return false;
  if (roles.includes('ADMIN') || roles.includes('GUARD')) return false;
  return roles.includes('OWNER') || roles.includes('TENANT');
}
