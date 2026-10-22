import '../apna_api.dart';
import 'admin_guard_repository.dart';
import 'admin_user_repository.dart';
import 'announcement_repository.dart';
import 'billing_repository.dart';
import 'complaint_repository.dart';
import 'facility_repository.dart';
import 'notification_repository.dart';
import 'report_repository.dart';
import 'resident_repository.dart';
import 'society_repository.dart';
import 'staff_repository.dart';
import 'vehicle_repository.dart';
import 'visitor_repository.dart';

/// Process-wide live read repositories for the authenticated user.
///
/// Cleared on logout and whenever the session is wiped so the next account
/// never sees the previous user's cached society/resident data.
class LiveRepositories {
  LiveRepositories(ApnaApi api)
      : society = SocietyRepository(api.society),
        resident = ResidentRepository(api.residents),
        users = AdminUserRepository(api.adminUsers),
        guards = AdminGuardRepository(api.adminGuards),
        billing = BillingRepository(api.billing),
        reports = ReportRepository(api.reports),
        visitors = VisitorRepository(api.visitors),
        vehicles = VehicleRepository(api.vehicles),
        complaints = ComplaintRepository(api.complaints),
        staff = StaffRepository(api.staff),
        facilities = FacilityRepository(api.facilities),
        announcements = AnnouncementRepository(api.announcements),
        notifications = NotificationRepository(api.notifications);

  final SocietyRepository society;
  final ResidentRepository resident;
  final AdminUserRepository users;
  final AdminGuardRepository guards;
  final BillingRepository billing;
  final ReportRepository reports;
  final VisitorRepository visitors;
  final VehicleRepository vehicles;
  final ComplaintRepository complaints;
  final StaffRepository staff;
  final FacilityRepository facilities;
  final AnnouncementRepository announcements;
  final NotificationRepository notifications;

  void clear() {
    society.clear();
    resident.clear();
    users.clear();
    guards.clear();
    billing.clear();
    reports.clear();
    visitors.clear();
    vehicles.clear();
    complaints.clear();
    staff.clear();
    facilities.clear();
    announcements.clear();
    notifications.clear();
  }

  /// Clears caches affected by occupancy or resident provisioning mutations.
  void invalidateAfterResidentMutation({String? flatId}) {
    users.invalidateLists();
    resident.clear();
    vehicles.invalidateCaches();
    visitors.invalidateCaches();
    facilities.invalidateCaches();
    announcements.invalidateCaches();
    notifications.invalidateCaches();
    if (flatId != null) {
      society.invalidateAfterOccupancy(flatId);
    } else {
      society.lastFlatsPage = null;
      society.lastFlatsQueryKey = null;
    }
  }

  void invalidateAfterFinancialMutation({String? billId}) {
    billing.invalidateFinancialCaches(billId: billId);
    reports.clear();
  }

  /// Clears resident list caches when the active flat changes so screens
  /// cannot keep showing data from the previous selection.
  void invalidateAfterFlatSelectionChange() {
    billing.invalidateFinancialCaches();
    visitors.invalidateCaches();
    vehicles.invalidateCaches();
    complaints.invalidateCaches();
    facilities.invalidateCaches();
    announcements.invalidateCaches();
    notifications.invalidateCaches();
  }

  void invalidateAfterVisitorMutation({String? visitorId}) {
    visitors.invalidateCaches(visitorId: visitorId);
  }

  void invalidateAfterVehicleMutation({String? vehicleId, String? slotId}) {
    vehicles.invalidateCaches(vehicleId: vehicleId, slotId: slotId);
  }

  void invalidateAfterComplaintMutation({String? complaintId}) {
    complaints.invalidateCaches(complaintId: complaintId);
    reports.clear();
  }

  void invalidateAfterStaffMutation({
    String? staffId,
    String? attendanceId,
    String? shiftId,
  }) {
    staff.invalidateCaches(
      staffId: staffId,
      attendanceId: attendanceId,
      shiftId: shiftId,
    );
  }

  void invalidateAfterFacilityMutation({
    String? facilityId,
    String? bookingId,
  }) {
    facilities.invalidateCaches(
      facilityId: facilityId,
      bookingId: bookingId,
    );
  }

  void invalidateAfterAnnouncementMutation({String? announcementId}) {
    announcements.invalidateCaches(announcementId: announcementId);
    notifications.invalidateCaches();
  }

  void invalidateAfterNotificationMutation({String? notificationId}) {
    notifications.invalidateCaches(notificationId: notificationId);
  }
}

LiveRepositories? _liveRepositories;

LiveRepositories? get liveRepositories => _liveRepositories;

LiveRepositories ensureLiveRepositories(ApnaApi api) {
  return _liveRepositories ??= LiveRepositories(api);
}

void clearLiveRepositories() {
  _liveRepositories?.clear();
  _liveRepositories = null;
}
