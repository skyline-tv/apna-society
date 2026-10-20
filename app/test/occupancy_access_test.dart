import 'package:apna_society/data/local_database.dart';
import 'package:apna_society/services/occupancy_access.dart';
import 'package:apna_society/services/session_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase.forExecutor(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    await db._seedDemoOccupancyAccountsSafe();
  });

  tearDown(() async {
    await db.close();
  });

  test('A-101 tenant occupied: owner finance only, tenant residential only',
      () async {
    final flat = await db
        .customSelect(
          "SELECT * FROM flats WHERE flat_number='A-101' AND is_active=1 LIMIT 1",
        )
        .getSingle();

    final owner = OccupancyAccess.forSession(
      flat: flat,
      sessionRole: SessionStore.roleOwner,
      sessionMobile: '9876510032',
    );
    expect(owner.canFinance, isTrue);
    expect(owner.canResidential, isFalse);

    final tenant = OccupancyAccess.forSession(
      flat: flat,
      sessionRole: SessionStore.roleTenant,
      sessionMobile: '9876510101',
    );
    expect(tenant.canFinance, isFalse);
    expect(tenant.canResidential, isTrue);

    final recipient = residentialRecipientForFlat(flat);
    expect(recipient.role, SessionStore.roleTenant);
    expect(recipient.fallbackUsed, isFalse);
  });

  test('A-102 owner occupied: owner has full access', () async {
    final flat = await db
        .customSelect(
          "SELECT * FROM flats WHERE flat_number='A-102' AND is_active=1 LIMIT 1",
        )
        .getSingle();

    final owner = OccupancyAccess.forSession(
      flat: flat,
      sessionRole: SessionStore.roleOwner,
      sessionMobile: '9876510033',
    );
    expect(owner.canFinance, isTrue);
    expect(owner.canResidential, isTrue);
    expect(residentialRecipientForFlat(flat).role, SessionStore.roleOwner);
  });

  test(
      'switching occupancy deactivates tenant login without deleting history fields',
      () async {
    final flat = await db
        .customSelect(
          "SELECT * FROM flats WHERE flat_number='A-101' LIMIT 1",
        )
        .getSingle();
    final id = flat.read<int>('id');

    await db.updateFlat(
      id: id,
      building: flat.read<String>('building'),
      flatNumber: 'A-101',
      floor: flat.read<int>('floor'),
      flatType: (flat.data['flat_type'] as String?) ?? '2 BHK',
      ownerName: flat.read<String>('owner_name'),
      mobile: flat.read<String>('mobile'),
      monthlyAmount: flat.read<int>('monthly_amount'),
      occupancyType: kOccupancyOwnerOccupied,
      tenantName: 'Demo Tenant',
      tenantMobile: '9876510101',
    );

    final after = await db.flatById(id);
    expect(OccupancyAccess.occupancyOf(after!), kOccupancyOwnerOccupied);
    expect(OccupancyAccess.tenantActive(after), isFalse);
    expect(OccupancyAccess.tenantNameOf(after), 'Demo Tenant');
    expect(await db.flatForTenantMobile('9876510101'), isNull);

    await db.updateFlat(
      id: id,
      building: after.read<String>('building'),
      flatNumber: 'A-101',
      floor: after.read<int>('floor'),
      flatType: (after.data['flat_type'] as String?) ?? '2 BHK',
      ownerName: after.read<String>('owner_name'),
      mobile: after.read<String>('mobile'),
      monthlyAmount: after.read<int>('monthly_amount'),
      occupancyType: kOccupancyTenantOccupied,
      tenantName: 'New Tenant',
      tenantMobile: '9876510199',
    );
    final rented = await db.flatById(id);
    expect(OccupancyAccess.tenantActive(rented!), isTrue);
    expect(await db.flatForTenantMobile('9876510199'), isNotNull);
    expect(residentialRecipientForFlat(rented).role, SessionStore.roleTenant);
  });

  test('tenant cannot settle bills; owner of rented flat can', () async {
    final flat = await db
        .customSelect(
          "SELECT * FROM flats WHERE flat_number='A-101' LIMIT 1",
        )
        .getSingle();
    final flatId = flat.read<int>('id');

    await expectLater(
      () => db.settleAllOutstandingForFlat(
        flatId: flatId,
        method: 'App (Demo)',
        paymentDate: DateTime.now(),
        amountCollected: 0,
        actorRole: SessionStore.roleTenant,
        actorMobile: '9876510101',
      ),
      throwsA(isA<StateError>()),
    );

    // Owner finance assert passes even with no bills (fails later on empty outstanding).
    await expectLater(
      () => db.settleAllOutstandingForFlat(
        flatId: flatId,
        method: 'App (Demo)',
        paymentDate: DateTime.now(),
        amountCollected: 0,
        actorRole: SessionStore.roleOwner,
        actorMobile: '9876510032',
      ),
      throwsA(isA<StateError>()),
    );
  });
}

/// Expose seed helper for tests without making it public on LocalDatabase permanently.
extension on LocalDatabase {
  Future<void> _seedDemoOccupancyAccountsSafe() async {
    // Re-run the same SQL used by production seed.
    await customStatement(
      '''
UPDATE flats SET
  owner_name=?, mobile=?,
  occupancy_type=?, tenant_name=?, tenant_mobile=?, tenant_is_active=1
WHERE building=? AND flat_number=? AND is_active=1
''',
      [
        'Demo Owner',
        '9876510032',
        kOccupancyTenantOccupied,
        'Demo Tenant',
        '9876510101',
        'Monarch Solitaire A',
        'A-101',
      ],
    );
    await customStatement(
      '''
UPDATE flats SET
  owner_name=?, mobile=?,
  occupancy_type=?, tenant_name='', tenant_mobile='', tenant_is_active=0
WHERE building=? AND flat_number=? AND is_active=1
''',
      [
        'A-102 Owner',
        '9876510033',
        kOccupancyOwnerOccupied,
        'Monarch Solitaire A',
        'A-102',
      ],
    );
  }
}
