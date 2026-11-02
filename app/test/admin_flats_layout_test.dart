import 'package:apna_society/api/models/society_models.dart';
import 'package:apna_society/features/admin/admin_flats_page.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact rupees shortens thousands', () {
    expect(compactRupees(34000), '₹34k');
    expect(compactRupees(4000), '₹4k');
    expect(compactRupees(100000), '₹1L');
  });

  testWidgets('flat unit card matches occupancy chrome on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const owner = FlatSummary(
      id: 'f1',
      societyId: 's1',
      wingId: 'w1',
      number: 'A-101',
      floor: 1,
      position: 1,
      flatType: '2BHK',
      maintenanceRate: 4000,
      isActive: true,
      occupancyStatus: 'OWNER_OCCUPIED',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      wingCode: 'A',
      wingName: 'Wing A',
      activeOwner: ResidentSummary(
        id: 'u1',
        name: 'Rahul Mehta',
        email: 'rahul@example.com',
        role: 'OWNER',
      ),
    );
    const vacant = FlatSummary(
      id: 'f2',
      societyId: 's1',
      wingId: 'w1',
      number: 'A-201',
      floor: 2,
      position: 1,
      flatType: '2BHK',
      maintenanceRate: 4000,
      isActive: true,
      occupancyStatus: 'VACANT',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      wingCode: 'A',
      wingName: 'Wing A',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              AdminFlatsSearchBar(
                controller: TextEditingController(),
                onChanged: (_) {},
                onClear: () {},
                onTune: () {},
              ),
              const SizedBox(height: 12),
              AdminFlatsWingChips(
                wings: const [
                  WingSummary(
                    id: 'w1',
                    societyId: 's1',
                    name: 'Wing A',
                    code: 'A',
                    floors: 2,
                    flatsPerFloor: 2,
                    sortOrder: 1,
                    isActive: true,
                    flatCount: 4,
                    createdAt: '2026-01-01T00:00:00.000Z',
                    updatedAt: '2026-01-01T00:00:00.000Z',
                  ),
                ],
                selectedWingId: null,
                onSelect: (_) {},
              ),
              const SizedBox(height: 8),
              AdminFlatsStatusRow(
                selected: 'all',
                unitCount: 8,
                onSelect: (_) {},
              ),
              const SizedBox(height: 8),
              const AdminFlatsSummaryStrip(
                totals: DashboardTotals(
                  wings: 2,
                  flats: 8,
                  activeFlats: 8,
                  inactiveFlats: 0,
                  ownerOccupiedFlats: 4,
                  tenantOccupiedFlats: 2,
                  vacantFlats: 2,
                  twoBhkCount: 6,
                  threeBhkCount: 2,
                  monthlyMaintenanceTotal: 34000,
                ),
              ),
              const SizedBox(height: 12),
              AdminFlatUnitCard(flat: owner, onTap: () {}),
              const SizedBox(height: 12),
              AdminFlatUnitCard(flat: vacant, onTap: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Search flat, resident, or wing...'), findsOneWidget);
    expect(find.text('All Wings'), findsOneWidget);
    expect(find.text('Wing A (4)'), findsOneWidget);
    expect(find.text('8 units'), findsWidgets);
    expect(find.text('OCCUPIED'), findsOneWidget);
    expect(find.text('₹34k'), findsOneWidget);
    expect(find.text('Flat A-101'), findsOneWidget);
    expect(find.text('Rahul Mehta'), findsOneWidget);
    expect(find.text('Owner'), findsWidgets);
    expect(find.text('No occupant allotted'), findsOneWidget);
    expect(find.text('+ Assign'), findsOneWidget);
  });
}
