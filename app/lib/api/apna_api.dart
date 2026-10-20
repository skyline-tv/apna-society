import 'config/api_config.dart';
import 'http/api_client.dart';
import 'services/admin_user_api.dart';
import 'services/announcement_api.dart';
import 'services/auth_api.dart';
import 'services/billing_api.dart';
import 'services/complaint_api.dart';
import 'services/facility_api.dart';
import 'services/notification_api.dart';
import 'services/report_api.dart';
import 'services/resident_api.dart';
import 'services/society_api.dart';
import 'services/staff_api.dart';
import 'services/vehicle_api.dart';
import 'services/visitor_api.dart';

/// Entry point for the backend-v2 HTTP layer.
class ApnaApi {
  ApnaApi({
    ApiConfig? config,
    ApiClient? client,
    AccessTokenReader? accessToken,
    UnauthorizedHandler? onUnauthorized,
    String? societyId,
  }) : client = client ??
            ApiClient(
              config: config ?? ApiConfig.fromEnvironment(),
              accessToken: accessToken,
              onUnauthorized: onUnauthorized,
              societyId: societyId,
            );

  final ApiClient client;

  late final AuthApi auth = AuthApi(client);
  late final SocietyApi society = SocietyApi(client);
  late final AdminUserApi adminUsers = AdminUserApi(client);
  late final ResidentApi residents = ResidentApi(client);
  late final BillingApi billing = BillingApi(client);
  late final VisitorApi visitors = VisitorApi(client);
  late final VehicleApi vehicles = VehicleApi(client);
  late final ComplaintApi complaints = ComplaintApi(client);
  late final StaffApi staff = StaffApi(client);
  late final FacilityApi facilities = FacilityApi(client);
  late final AnnouncementApi announcements = AnnouncementApi(client);
  late final NotificationApi notifications = NotificationApi(client);
  late final ReportApi reports = ReportApi(client);
}
