import 'package:apna_society/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'maintenance period covers inclusive prepaid months across year boundary',
      () {
    expect(
      maintenancePeriodLabel(startMonth: DateTime(2026, 10), monthsCovered: 1),
      'October 2026',
    );
    expect(
      maintenancePeriodLabel(startMonth: DateTime(2026, 10), monthsCovered: 3),
      'October 2026 - December 2026',
    );
    expect(
      maintenancePeriodLabel(startMonth: DateTime(2026, 10), monthsCovered: 6),
      'October 2026 - March 2027',
    );
    expect(
      maintenancePeriodLabel(startMonth: DateTime(2026, 11), monthsCovered: 3),
      'November 2026 - January 2027',
    );
    expect(
      maintenancePeriodLabel(startMonth: DateTime(2026, 12), monthsCovered: 3),
      'December 2026 - February 2027',
    );
  });
}
