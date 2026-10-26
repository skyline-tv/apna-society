import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../services/late_interest.dart';
import '../services/occupancy_access.dart';
import '../services/session_store.dart';

part 'local_database.g.dart';

/// Device-local SQLite store. Demo data never leaves this device.
@DriftDatabase(tables: [])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase() : super(driftDatabase(name: 'apna_society'));

  /// Test / in-memory constructor (does not open the on-device database file).
  LocalDatabase.forExecutor(super.e);

  @override
  int get schemaVersion => 19;

  /// Last calendar day for which overdue statuses were refreshed (yyyy-MM-dd).
  String? _overdueRefreshDay;

  static const maxOtherChargesPerFlat = 10;
  static const settingLateInterestAnnualRate = 'late_interest_annual_rate';

  /// Hours after expected arrival during which a visitor OTP remains valid.
  static const defaultOtpValidityHours = 6;
  static const maxOtpInvalidAttempts = 5;

  /// True when [table] exists in sqlite_master.
  Future<bool> tableExists(String table) async {
    final rows = await customSelect(
      "SELECT 1 AS ok FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      variables: [Variable<String>(table)],
    ).get();
    return rows.isNotEmpty;
  }

  /// True when [column] already exists on [table] (PRAGMA table_info).
  Future<bool> columnExists(String table, String column) async {
    if (!await tableExists(table)) return false;
    // table name is controlled by our migrations only — never user input.
    final rows = await customSelect('PRAGMA table_info($table)').get();
    final wanted = column.toLowerCase();
    for (final row in rows) {
      final name = (row.data['name'] as String?)?.toLowerCase();
      if (name == wanted) return true;
    }
    return false;
  }

  /// Adds a column only when missing. Never runs ALTER if the column exists.
  ///
  /// Important: do not use try/catch around ALTER inside Drift migrations —
  /// a failed statement aborts the migration transaction even when caught in Dart.
  Future<void> addColumnIfMissing({
    required String table,
    required String column,
    required String sqliteTypeAndConstraints,
  }) async {
    if (await columnExists(table, column)) return;
    await customStatement(
        'ALTER TABLE $table ADD COLUMN $column $sqliteTypeAndConstraints');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
CREATE TABLE flats(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  building TEXT NOT NULL,
  flat_number TEXT NOT NULL,
  floor INTEGER NOT NULL,
  flat_type TEXT NOT NULL DEFAULT '2 BHK',
  owner_name TEXT NOT NULL DEFAULT '',
  mobile TEXT NOT NULL DEFAULT '',
  email TEXT,
  monthly_amount INTEGER NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  occupancy_type TEXT NOT NULL DEFAULT 'owner_occupied',
  tenant_name TEXT NOT NULL DEFAULT '',
  tenant_mobile TEXT NOT NULL DEFAULT '',
  tenant_is_active INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  UNIQUE(building, flat_number)
)''');
          await customStatement('''
CREATE TABLE bills(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  bill_number TEXT NOT NULL UNIQUE,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  months_covered INTEGER NOT NULL DEFAULT 1,
  unit_amount INTEGER NOT NULL,
  maintenance_amount INTEGER NOT NULL DEFAULT 0,
  other_charges_total INTEGER NOT NULL DEFAULT 0,
  other_charges_json TEXT NOT NULL DEFAULT '[]',
  amount INTEGER NOT NULL,
  status TEXT NOT NULL,
  issue_date TEXT NOT NULL,
  due_date TEXT NOT NULL,
  remarks TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(flat_id, period_start)
)''');
          await customStatement('''
CREATE TABLE flat_other_charges(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  description TEXT NOT NULL,
  amount INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(flat_id) REFERENCES flats(id)
)''');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_flat_other_charges_flat ON flat_other_charges(flat_id)');
          await customStatement('''
CREATE TABLE payments(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  bill_ids TEXT NOT NULL,
  receipt_number TEXT NOT NULL UNIQUE,
  amount INTEGER NOT NULL,
  principal_amount INTEGER NOT NULL DEFAULT 0,
  interest_amount INTEGER NOT NULL DEFAULT 0,
  method TEXT NOT NULL,
  status TEXT NOT NULL,
  paid_at TEXT NOT NULL,
  remarks TEXT,
  cheque_number TEXT,
  cheque_date TEXT,
  bank_name TEXT,
  cheque_status TEXT,
  collected_by_admin_id INTEGER,
  collected_by_name TEXT,
  batch_id INTEGER
)''');
          await customStatement('''
CREATE TABLE payment_batches(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  receipt_number TEXT NOT NULL UNIQUE,
  total_amount INTEGER NOT NULL,
  total_principal INTEGER NOT NULL,
  total_interest INTEGER NOT NULL,
  bills_settled INTEGER NOT NULL,
  method TEXT NOT NULL,
  status TEXT NOT NULL,
  paid_at TEXT NOT NULL,
  remarks TEXT,
  cheque_number TEXT,
  cheque_date TEXT,
  bank_name TEXT,
  cheque_status TEXT,
  collected_by_admin_id INTEGER,
  collected_by_name TEXT,
  created_at TEXT NOT NULL
)''');
          await customStatement('''
CREATE TABLE payment_audit(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_id INTEGER,
  bill_id INTEGER,
  action TEXT NOT NULL,
  details TEXT NOT NULL,
  admin_id INTEGER,
  admin_name TEXT,
  created_at TEXT NOT NULL
)''');
          await customStatement('''
CREATE TABLE bill_interest_ledger(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bill_id INTEGER NOT NULL,
  period_key TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  principal_base INTEGER NOT NULL,
  annual_rate_percent REAL NOT NULL,
  monthly_rate_percent REAL NOT NULL,
  interest_amount INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(bill_id, period_key)
)''');
          await customStatement(
              'CREATE TABLE app_settings(setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL)');
          await customStatement('''
CREATE TABLE admins(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  mobile TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''');
          await _ensureQueryIndexes();
          await _seed();
          // Invitation / notification tables are created in [_seed].
          await _ensureQueryIndexesV19();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await addColumnIfMissing(
                table: 'flats',
                column: 'email',
                sqliteTypeAndConstraints: 'TEXT');
            await addColumnIfMissing(
                table: 'flats',
                column: 'is_active',
                sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 1');
          }
          if (from < 3) {
            await addColumnIfMissing(
                table: 'bills',
                column: 'bill_number',
                sqliteTypeAndConstraints: 'TEXT');
            await addColumnIfMissing(
                table: 'bills',
                column: 'months_covered',
                sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 1');
            await addColumnIfMissing(
                table: 'bills',
                column: 'unit_amount',
                sqliteTypeAndConstraints: 'INTEGER');
            await addColumnIfMissing(
                table: 'bills',
                column: 'issue_date',
                sqliteTypeAndConstraints: 'TEXT');
            await addColumnIfMissing(
                table: 'bills',
                column: 'remarks',
                sqliteTypeAndConstraints: 'TEXT');
            final rows = await customSelect(
                    'SELECT id, flat_id, amount, period_start, created_at FROM bills')
                .get();
            for (final row in rows) {
              final id = row.read<int>('id');
              final amount = row.read<int>('amount');
              final created = row.read<String>('created_at');
              final billNo = 'AS-BILL-${1000 + id}';
              await customStatement(
                'UPDATE bills SET bill_number=?, months_covered=1, unit_amount=?, issue_date=COALESCE(issue_date, ?), remarks=remarks WHERE id=?',
                [billNo, amount, created, id],
              );
            }
          }
          if (from < 4) {
            await customStatement(
              "UPDATE app_settings SET setting_value=? WHERE setting_key='society_name'",
              ['Monarch Solitaire'],
            );
            await customStatement(
              "UPDATE flats SET building=? WHERE building='Apna Heights A'",
              ['Monarch Solitaire A'],
            );
            await customStatement(
              "UPDATE flats SET building=? WHERE building='Apna Heights B'",
              ['Monarch Solitaire B'],
            );
          }
          if (from < 5) {
            await customStatement(
              "INSERT OR IGNORE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
              ['society_address', 'Monarch Solitaire Residential Society'],
            );
          }
          if (from < 6) {
            await customStatement('''
CREATE TABLE IF NOT EXISTS admins(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  mobile TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''');
            await customStatement(
              'INSERT OR IGNORE INTO admins(name,mobile,is_active,created_at) VALUES(?,?,?,?)',
              [
                'Society Admin',
                '9876500001',
                1,
                DateTime.now().toIso8601String()
              ],
            );
          }
          if (from < 7) {
            await _createSecurityTables();
            await _seedSecurityDemo();
          }
          if (from < 8) {
            await _createInvitationTables();
          }
          if (from < 9) {
            await customStatement(
              "UPDATE app_settings SET setting_value=? WHERE setting_key='society_name'",
              ['Monarch Solitaire A to E'],
            );
            await customStatement(
              "UPDATE app_settings SET setting_value=? WHERE setting_key='society_address'",
              ['Monarch Solitaire A to E Residential Society'],
            );
            await customStatement(
              "INSERT OR IGNORE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
              ['society_name', 'Monarch Solitaire A to E'],
            );
            await customStatement(
              "INSERT OR IGNORE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
              [
                'society_address',
                'Monarch Solitaire A to E Residential Society'
              ],
            );
            // Existing flat IDs / bills / payments are preserved. Wings C–E become available for new flats.
          }
          if (from < 10) {
            // Schema-aware: skip when flat_type already present (partial upgrades / rebuilt onCreate).
            await addColumnIfMissing(
              table: 'flats',
              column: 'flat_type',
              sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT '2 BHK'",
            );
            await syncSocietyFlatsStructure(assignDemoOwner: true);
          }
          if (from < 11) {
            await _migratePaymentsV11Columns();
            // Fresh billing start: remove demo bills/payments only. Flats and other society data stay.
            await clearAllBillsAndPayments();
            await customStatement(
              "INSERT OR REPLACE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
              ['billing_reset_v11', 'done'],
            );
          }
          if (from < 12) {
            await _migrateOtherChargesV12();
          }
          if (from < 13) {
            await _migrateLateInterestV13();
          }
          if (from < 14) {
            await _migrateSettlementBatchesV14();
          }
          if (from < 15) {
            await _migrateVisitorApprovalV15();
          }
          if (from < 16) {
            // Idempotent reconcile for devices that hit duplicate-column / partial upgrades.
            await reconcileSchemaColumns();
          }
          if (from < 17) {
            await _ensureQueryIndexes();
          }
          if (from < 18) {
            await _migrateOccupancyV18();
          }
          if (from < 19) {
            await _ensureQueryIndexesV19();
          }
        },
      );

  Future<void> _ensureQueryIndexesV19() async {
    if (await tableExists('visitor_invitations')) {
      await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_invite_status ON visitor_invitations(status)');
    }
    if (await tableExists('app_notifications')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_notif_role_flat_read ON app_notifications(recipient_role, recipient_flat_id, is_read)',
      );
    }
  }

  Future<void> _migrateOccupancyV18() async {
    await addColumnIfMissing(
      table: 'flats',
      column: 'occupancy_type',
      sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT 'owner_occupied'",
    );
    await addColumnIfMissing(
      table: 'flats',
      column: 'tenant_name',
      sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT ''",
    );
    await addColumnIfMissing(
      table: 'flats',
      column: 'tenant_mobile',
      sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT ''",
    );
    await addColumnIfMissing(
      table: 'flats',
      column: 'tenant_is_active',
      sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0',
    );
    await customStatement(
      "UPDATE flats SET occupancy_type='owner_occupied' WHERE occupancy_type IS NULL OR trim(occupancy_type)=''",
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_flats_tenant_mobile ON flats(tenant_mobile)',
    );
    await _seedDemoOccupancyAccounts();
  }

  Future<void> _ensureQueryIndexes() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_bills_flat_status ON bills(flat_id, status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_bills_status ON bills(status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_bills_period_start ON bills(period_start)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payments_flat_paid ON payments(flat_id, paid_at)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payments_bill_ids ON payments(bill_ids)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_flats_building_flat ON flats(building, flat_number)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_flats_active ON flats(is_active)');
  }

  /// Ensures every expected column/table exists without wiping data.
  /// Safe to run repeatedly; never deletes rows.
  Future<void> reconcileSchemaColumns() async {
    await addColumnIfMissing(
        table: 'flats', column: 'email', sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'flats',
        column: 'is_active',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 1');
    await addColumnIfMissing(
        table: 'flats',
        column: 'flat_type',
        sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT '2 BHK'");
    await addColumnIfMissing(
      table: 'flats',
      column: 'occupancy_type',
      sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT 'owner_occupied'",
    );
    await addColumnIfMissing(
      table: 'flats',
      column: 'tenant_name',
      sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT ''",
    );
    await addColumnIfMissing(
      table: 'flats',
      column: 'tenant_mobile',
      sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT ''",
    );
    await addColumnIfMissing(
      table: 'flats',
      column: 'tenant_is_active',
      sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0',
    );

    await addColumnIfMissing(
        table: 'bills',
        column: 'bill_number',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'bills',
        column: 'months_covered',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 1');
    await addColumnIfMissing(
        table: 'bills',
        column: 'unit_amount',
        sqliteTypeAndConstraints: 'INTEGER');
    await addColumnIfMissing(
        table: 'bills', column: 'issue_date', sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'bills', column: 'remarks', sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'bills',
        column: 'maintenance_amount',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(
        table: 'bills',
        column: 'other_charges_total',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(
        table: 'bills',
        column: 'other_charges_json',
        sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT '[]'");

    await addColumnIfMissing(
        table: 'payments', column: 'remarks', sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'cheque_number',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'cheque_date',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'bank_name',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'cheque_status',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'collected_by_admin_id',
        sqliteTypeAndConstraints: 'INTEGER');
    await addColumnIfMissing(
        table: 'payments',
        column: 'collected_by_name',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'principal_amount',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(
        table: 'payments',
        column: 'interest_amount',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(
        table: 'payments',
        column: 'batch_id',
        sqliteTypeAndConstraints: 'INTEGER');

    if (await tableExists('visitor_invitations')) {
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'source',
          sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT 'owner'");
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'created_by_guard_id',
          sqliteTypeAndConstraints: 'INTEGER');
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'photo_path',
          sqliteTypeAndConstraints: 'TEXT');
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'owner_decision',
          sqliteTypeAndConstraints: 'TEXT');
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'owner_decision_at',
          sqliteTypeAndConstraints: 'TEXT');
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'owner_decision_by_flat_id',
          sqliteTypeAndConstraints: 'INTEGER');
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'owner_decision_by_name',
          sqliteTypeAndConstraints: 'TEXT');
      await addColumnIfMissing(
          table: 'visitor_invitations',
          column: 'owner_decision_note',
          sqliteTypeAndConstraints: 'TEXT');
    }

    await _migrateOtherChargesV12();
    await _migrateLateInterestV13();
    await _migrateSettlementBatchesV14();
    await _migrateVisitorApprovalV15();
    await _ensureQueryIndexesV19();
  }

  Future<void> _migrateVisitorApprovalV15() async {
    if (!await tableExists('visitor_invitations')) {
      await _createInvitationTables();
      return;
    }
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'source',
        sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT 'owner'");
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'created_by_guard_id',
        sqliteTypeAndConstraints: 'INTEGER');
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'photo_path',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'owner_decision',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'owner_decision_at',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'owner_decision_by_flat_id',
        sqliteTypeAndConstraints: 'INTEGER');
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'owner_decision_by_name',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'visitor_invitations',
        column: 'owner_decision_note',
        sqliteTypeAndConstraints: 'TEXT');
    await customStatement(
        "UPDATE visitor_invitations SET source='owner' WHERE source IS NULL OR trim(source)=''");
    await customStatement('DROP INDEX IF EXISTS idx_invite_otp_active');
    await customStatement(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_invite_otp_active ON visitor_invitations(otp_code) WHERE status='pending' AND otp_used=0 AND COALESCE(source,'owner')='owner'",
    );
    await customStatement('''
CREATE TABLE IF NOT EXISTS app_notifications(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient_role TEXT NOT NULL,
  recipient_flat_id INTEGER,
  recipient_guard_id INTEGER,
  recipient_admin_id INTEGER,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  entity_table TEXT NOT NULL DEFAULT 'visitor_invitations',
  entity_id INTEGER,
  is_read INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_notif_owner ON app_notifications(recipient_role, recipient_flat_id, is_read)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_notif_guard ON app_notifications(recipient_role, recipient_guard_id, is_read)');
    await customStatement('''
CREATE TABLE IF NOT EXISTS visitor_request_audit(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invitation_id INTEGER NOT NULL,
  action TEXT NOT NULL,
  actor_role TEXT NOT NULL,
  actor_id INTEGER,
  actor_name TEXT,
  details TEXT,
  created_at TEXT NOT NULL
)''');
  }

  Future<void> _migrateSettlementBatchesV14() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS payment_batches(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  receipt_number TEXT NOT NULL UNIQUE,
  total_amount INTEGER NOT NULL,
  total_principal INTEGER NOT NULL,
  total_interest INTEGER NOT NULL,
  bills_settled INTEGER NOT NULL,
  method TEXT NOT NULL,
  status TEXT NOT NULL,
  paid_at TEXT NOT NULL,
  remarks TEXT,
  cheque_number TEXT,
  cheque_date TEXT,
  bank_name TEXT,
  cheque_status TEXT,
  collected_by_admin_id INTEGER,
  collected_by_name TEXT,
  created_at TEXT NOT NULL
)''');
    await addColumnIfMissing(
        table: 'payments',
        column: 'batch_id',
        sqliteTypeAndConstraints: 'INTEGER');
  }

  Future<void> _migrateLateInterestV13() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS bill_interest_ledger(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bill_id INTEGER NOT NULL,
  period_key TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  principal_base INTEGER NOT NULL,
  annual_rate_percent REAL NOT NULL,
  monthly_rate_percent REAL NOT NULL,
  interest_amount INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(bill_id, period_key)
)''');
    await addColumnIfMissing(
        table: 'payments',
        column: 'principal_amount',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(
        table: 'payments',
        column: 'interest_amount',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    // Backfill: existing successful payments were principal-only collections.
    await customStatement(
      "UPDATE payments SET principal_amount=amount, interest_amount=0 WHERE principal_amount=0 AND interest_amount=0",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
      [
        settingLateInterestAnnualRate,
        '${LateInterest.defaultAnnualRatePercent.toInt()}'
      ],
    );
  }

  Future<void> _migrateOtherChargesV12() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS flat_other_charges(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  description TEXT NOT NULL,
  amount INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(flat_id) REFERENCES flats(id)
)''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_flat_other_charges_flat ON flat_other_charges(flat_id)');
    await addColumnIfMissing(
        table: 'bills',
        column: 'maintenance_amount',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(
        table: 'bills',
        column: 'other_charges_total',
        sqliteTypeAndConstraints: 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(
        table: 'bills',
        column: 'other_charges_json',
        sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT '[]'");
    // Backfill: existing bills keep their grand total as maintenance-only snapshots.
    await customStatement(
      "UPDATE bills SET maintenance_amount=amount, other_charges_total=0, other_charges_json='[]' WHERE maintenance_amount=0 AND other_charges_total=0",
    );
  }

  /// Ensures demo bills were cleared once for the cash/cheque billing reset (idempotent).
  Future<Map<String, int>> ensureBillingResetV11() =>
      ensureFreshBillingStart(key: 'billing_reset_v11');

  /// One-shot wipe of all bills and payments. Flats and other society data are kept.
  Future<Map<String, int>> ensureFreshBillingStart(
      {required String key}) async {
    await _migratePaymentsV11Columns();
    final flag = await appSetting(key);
    if (flag == 'done') {
      return {
        'bills': await billCount(),
        'payments': (await customSelect('SELECT COUNT(*) AS n FROM payments')
                .getSingle())
            .read<int>('n'),
        'activeFlats': (await customSelect(
                    'SELECT COUNT(*) AS n FROM flats WHERE is_active=1')
                .getSingle())
            .read<int>('n'),
        'clearedNow': 0,
      };
    }
    final result = await clearAllBillsAndPayments();
    await customStatement(
      "INSERT OR REPLACE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
      [key, 'done'],
    );
    return {...result, 'clearedNow': 1};
  }

  Future<void> _migratePaymentsV11Columns() async {
    await addColumnIfMissing(
        table: 'payments', column: 'remarks', sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'cheque_number',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'cheque_date',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'bank_name',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'cheque_status',
        sqliteTypeAndConstraints: 'TEXT');
    await addColumnIfMissing(
        table: 'payments',
        column: 'collected_by_admin_id',
        sqliteTypeAndConstraints: 'INTEGER');
    await addColumnIfMissing(
        table: 'payments',
        column: 'collected_by_name',
        sqliteTypeAndConstraints: 'TEXT');
    await customStatement('''
CREATE TABLE IF NOT EXISTS payment_audit(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_id INTEGER,
  bill_id INTEGER,
  action TEXT NOT NULL,
  details TEXT NOT NULL,
  admin_id INTEGER,
  admin_name TEXT,
  created_at TEXT NOT NULL
)''');
  }

  Future<void> _deleteAllFromIfExists(String table) async {
    if (await tableExists(table)) {
      await customStatement('DELETE FROM $table');
    }
  }

  /// Deletes all bills and bill-linked payments / audit rows. Preserves flats and other society data.
  Future<Map<String, int>> clearAllBillsAndPayments() async {
    return transaction(() async {
      await _deleteAllFromIfExists('bill_interest_ledger');
      await _deleteAllFromIfExists('payment_audit');
      await _deleteAllFromIfExists('payments');
      await _deleteAllFromIfExists('payment_batches');
      await _deleteAllFromIfExists('bills');
      final bills = await tableExists('bills')
          ? (await customSelect('SELECT COUNT(*) AS n FROM bills').getSingle())
              .read<int>('n')
          : 0;
      final payments = await tableExists('payments')
          ? (await customSelect('SELECT COUNT(*) AS n FROM payments')
                  .getSingle())
              .read<int>('n')
          : 0;
      final flats = await tableExists('flats')
          ? (await customSelect(
                      'SELECT COUNT(*) AS n FROM flats WHERE is_active=1')
                  .getSingle())
              .read<int>('n')
          : 0;
      return {'bills': bills, 'payments': payments, 'activeFlats': flats};
    });
  }

  Future<int> billCount() async =>
      (await customSelect('SELECT COUNT(*) AS n FROM bills').getSingle())
          .read<int>('n');

  /// Canonical Monarch Solitaire A–E inventory (140 flats). No bills are generated here.
  List<Map<String, Object?>> canonicalSocietyFlats() {
    const wings = ['A', 'B', 'C', 'D', 'E'];
    final specs = <Map<String, Object?>>[];
    for (final wing in wings) {
      for (var floor = 1; floor <= 7; floor++) {
        for (var door = 1; door <= 4; door++) {
          final flatNo = '$wing-$floor${door.toString().padLeft(2, '0')}';
          late final String type;
          late final int amount;
          if (wing == 'A') {
            type = door <= 2 ? '2 BHK' : '3 BHK';
            amount = door <= 2 ? 4000 : 5000;
          } else if (wing == 'E') {
            type = door <= 2 ? '3 BHK' : '2 BHK';
            amount = door <= 2 ? 5000 : 4000;
          } else {
            type = '2 BHK';
            amount = 4000;
          }
          specs.add({
            'building': 'Monarch Solitaire $wing',
            'flat_number': flatNo,
            'floor': floor,
            'flat_type': type,
            'monthly_amount': amount,
          });
        }
      }
    }
    return specs;
  }

  /// Upserts the official 140 flats. Preserves existing row IDs when building+flat_number match.
  /// Does not create bills. Extra legacy flats are deactivated (IDs kept for history).
  Future<Map<String, int>> syncSocietyFlatsStructure(
      {bool assignDemoOwner = true}) async {
    final now = DateTime.now().toIso8601String();
    final specs = canonicalSocietyFlats();
    final keepKeys = <String>{};

    for (final s in specs) {
      final building = s['building'] as String;
      final flatNumber = s['flat_number'] as String;
      keepKeys.add('$building|$flatNumber');
      final existing = await customSelect(
        'SELECT id FROM flats WHERE building=? AND flat_number=? LIMIT 1',
        variables: [Variable<String>(building), Variable<String>(flatNumber)],
      ).get();
      if (existing.isEmpty) {
        await customStatement(
          'INSERT INTO flats(building,flat_number,floor,flat_type,owner_name,mobile,email,monthly_amount,is_active,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
          [
            building,
            flatNumber,
            s['floor'],
            s['flat_type'],
            '',
            '',
            null,
            s['monthly_amount'],
            1,
            now,
          ],
        );
      } else {
        await customStatement(
          'UPDATE flats SET floor=?, flat_type=?, owner_name=?, mobile=?, email=?, monthly_amount=?, is_active=1 WHERE id=?',
          [
            s['floor'],
            s['flat_type'],
            '',
            '',
            null,
            s['monthly_amount'],
            existing.first.read<int>('id'),
          ],
        );
      }
    }

    final all =
        await customSelect('SELECT id, building, flat_number FROM flats').get();
    for (final row in all) {
      final key =
          '${row.read<String>('building')}|${row.read<String>('flat_number')}';
      if (!keepKeys.contains(key)) {
        await customStatement(
            'UPDATE flats SET is_active=0 WHERE id=?', [row.read<int>('id')]);
      }
    }

    if (assignDemoOwner) {
      await _seedDemoOccupancyAccounts();
    }

    return verifyFlatInventory();
  }

  /// Demo accounts used in login hints (idempotent; preserves other flats).
  /// A-101 tenant occupied · A-102 owner occupied.
  Future<void> _seedDemoOccupancyAccounts() async {
    // Older upgrade paths may call sync before v18 occupancy columns exist.
    if (!await columnExists('flats', 'occupancy_type')) {
      await customStatement(
        "UPDATE flats SET owner_name=?, mobile=? WHERE building=? AND flat_number=? AND is_active=1",
        ['Demo Owner', '9876510032', 'Monarch Solitaire A', 'A-101'],
      );
      return;
    }
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

  Future<Map<String, int>> verifyFlatInventory() async {
    Future<int> n(String sql) async =>
        (await customSelect(sql).getSingle()).read<int>('n');
    final total = await n('SELECT COUNT(*) AS n FROM flats WHERE is_active=1');
    final wings = await n(
        'SELECT COUNT(DISTINCT building) AS n FROM flats WHERE is_active=1');
    final floors = await n(
        'SELECT COUNT(DISTINCT building || \'-\' || floor) AS n FROM flats WHERE is_active=1');
    final twoBhk = await n(
        "SELECT COUNT(*) AS n FROM flats WHERE is_active=1 AND flat_type='2 BHK'");
    final threeBhk = await n(
        "SELECT COUNT(*) AS n FROM flats WHERE is_active=1 AND flat_type='3 BHK'");
    final monthly = await n(
        'SELECT COALESCE(SUM(monthly_amount),0) AS n FROM flats WHERE is_active=1');
    return {
      'totalFlats': total,
      'wings': wings,
      'floorSlots': floors,
      'twoBhk': twoBhk,
      'threeBhk': threeBhk,
      'monthlyMaintenance': monthly,
      'annualMaintenance': monthly * 12,
    };
  }

  Future<void> _createInvitationTables() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS visitor_invitations(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  visitor_name TEXT NOT NULL,
  mobile TEXT NOT NULL,
  category TEXT NOT NULL,
  purpose TEXT NOT NULL,
  expected_date TEXT NOT NULL,
  expected_time TEXT NOT NULL,
  vehicle_number TEXT,
  otp_code TEXT NOT NULL,
  status TEXT NOT NULL,
  otp_used INTEGER NOT NULL DEFAULT 0,
  validity_hours INTEGER NOT NULL DEFAULT 6,
  invalid_attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  cancelled_at TEXT,
  entry_at TEXT,
  exit_at TEXT,
  verified_by_guard_id INTEGER,
  source TEXT NOT NULL DEFAULT 'owner',
  created_by_guard_id INTEGER,
  photo_path TEXT,
  owner_decision TEXT,
  owner_decision_at TEXT,
  owner_decision_by_flat_id INTEGER,
  owner_decision_by_name TEXT,
  owner_decision_note TEXT,
  FOREIGN KEY(flat_id) REFERENCES flats(id)
)''');
    await customStatement(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_invite_otp_active ON visitor_invitations(otp_code) WHERE status='pending' AND otp_used=0 AND COALESCE(source,'owner')='owner'",
    );
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_invite_flat_status ON visitor_invitations(flat_id, status)');
    await customStatement('''
CREATE TABLE IF NOT EXISTS vehicle_gate_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  vehicle_id INTEGER,
  registration_number TEXT NOT NULL,
  flat_id INTEGER,
  direction TEXT NOT NULL,
  is_registered INTEGER NOT NULL,
  requires_approval INTEGER NOT NULL DEFAULT 0,
  approval_note TEXT,
  recorded_by_guard_id INTEGER,
  recorded_at TEXT NOT NULL
)''');
    await customStatement('''
CREATE TABLE IF NOT EXISTS app_notifications(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient_role TEXT NOT NULL,
  recipient_flat_id INTEGER,
  recipient_guard_id INTEGER,
  recipient_admin_id INTEGER,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  entity_table TEXT NOT NULL DEFAULT 'visitor_invitations',
  entity_id INTEGER,
  is_read INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_notif_owner ON app_notifications(recipient_role, recipient_flat_id, is_read)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_notif_guard ON app_notifications(recipient_role, recipient_guard_id, is_read)');
    await customStatement('''
CREATE TABLE IF NOT EXISTS visitor_request_audit(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invitation_id INTEGER NOT NULL,
  action TEXT NOT NULL,
  actor_role TEXT NOT NULL,
  actor_id INTEGER,
  actor_name TEXT,
  details TEXT,
  created_at TEXT NOT NULL
)''');
    await customStatement(
      "INSERT OR IGNORE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
      ['visitor_otp_validity_hours', '$defaultOtpValidityHours'],
    );
  }

  Future<void> _createSecurityTables() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS security_guards(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  mobile TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 1,
  notes TEXT,
  created_at TEXT NOT NULL
)''');
    await customStatement('''
CREATE TABLE IF NOT EXISTS visitors(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  visitor_name TEXT NOT NULL,
  mobile TEXT NOT NULL,
  category TEXT NOT NULL,
  flat_id INTEGER NOT NULL,
  purpose TEXT NOT NULL,
  vehicle_number TEXT,
  photo_path TEXT,
  status TEXT NOT NULL,
  registered_at TEXT NOT NULL,
  registered_by_guard_id INTEGER,
  approval_decision TEXT,
  approval_at TEXT,
  entry_at TEXT,
  exit_at TEXT,
  FOREIGN KEY(flat_id) REFERENCES flats(id)
)''');
    await customStatement('''
CREATE TABLE IF NOT EXISTS vehicles(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  registration_number TEXT NOT NULL UNIQUE,
  vehicle_type TEXT NOT NULL,
  brand_model TEXT NOT NULL,
  colour TEXT,
  parking_slot TEXT,
  photo_path TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  FOREIGN KEY(flat_id) REFERENCES flats(id)
)''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_visitors_flat_status ON visitors(flat_id, status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_visitors_status ON visitors(status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_vehicles_reg ON vehicles(registration_number)');
  }

  Future<void> _seed() async {
    final now = DateTime.now();
    // Official 140-flat inventory. Billing starts empty — admin generates prepaid bills manually.
    await syncSocietyFlatsStructure(assignDemoOwner: true);
    await customStatement(
        'INSERT INTO app_settings(setting_key,setting_value) VALUES(?,?)',
        ['society_name', 'Monarch Solitaire A to E']);
    await customStatement(
        'INSERT INTO app_settings(setting_key,setting_value) VALUES(?,?)',
        ['society_address', 'Monarch Solitaire A to E Residential Society']);
    await customStatement(
      'INSERT INTO app_settings(setting_key,setting_value) VALUES(?,?)',
      [
        settingLateInterestAnnualRate,
        '${LateInterest.defaultAnnualRatePercent.toInt()}'
      ],
    );
    await customStatement(
      'INSERT INTO admins(name,mobile,is_active,created_at) VALUES(?,?,?,?)',
      ['Society Admin', '9876500001', 1, now.toIso8601String()],
    );
    await _createSecurityTables();
    await _seedSecurityDemo();
    await _createInvitationTables();
  }

  Future<void> _seedSecurityDemo() async {
    final now = DateTime.now().toIso8601String();
    await customStatement(
      'INSERT OR IGNORE INTO security_guards(name,mobile,is_active,notes,created_at) VALUES(?,?,?,?,?)',
      ['Gate Security', '9876500099', 1, 'Demo security guard account', now],
    );
    final flat = await customSelect(
            'SELECT id FROM flats WHERE is_active=1 ORDER BY id LIMIT 1')
        .get();
    if (flat.isNotEmpty) {
      final flatId = flat.first.read<int>('id');
      await customStatement(
        'INSERT OR IGNORE INTO vehicles(flat_id,registration_number,vehicle_type,brand_model,colour,parking_slot,photo_path,is_active,created_at) VALUES(?,?,?,?,?,?,?,?,?)',
        [
          flatId,
          'MH12AB1234',
          'Car',
          'Honda City',
          'White',
          'A-12',
          null,
          1,
          now
        ],
      );
    }
  }

  /// Authorized admin only — flat owners are never returned here.
  Future<QueryRow?> adminForMobile(String mobile) async {
    final rows = await customSelect(
      'SELECT * FROM admins WHERE mobile=? AND is_active=1 LIMIT 1',
      variables: [Variable<String>(mobile)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> adminById(int id) async {
    final rows = await customSelect(
      'SELECT * FROM admins WHERE id=? AND is_active=1 LIMIT 1',
      variables: [Variable<int>(id)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> flatById(int id) async {
    final rows = await customSelect(
      'SELECT * FROM flats WHERE id=? AND is_active=1 LIMIT 1',
      variables: [Variable<int>(id)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<QueryRow>> flats({bool includeInactive = true}) {
    final where = includeInactive ? '' : 'WHERE is_active=1';
    return customSelect(
            'SELECT * FROM flats $where ORDER BY is_active DESC, building, floor, flat_number')
        .get();
  }

  /// Official wings A–E for filters and mapping (always available).
  Future<List<String>> buildings() async => const [
        'Monarch Solitaire A',
        'Monarch Solitaire B',
        'Monarch Solitaire C',
        'Monarch Solitaire D',
        'Monarch Solitaire E',
      ];

  Future<QueryRow?> flatForMobile(String mobile) async {
    final number = mobile.trim();
    if (number.isEmpty) return null;
    final rows = await customSelect(
      "SELECT * FROM flats WHERE mobile=? AND is_active=1 AND trim(mobile) != '' LIMIT 1",
      variables: [Variable<String>(number)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Active tenant login for a tenant-occupied flat.
  Future<QueryRow?> flatForTenantMobile(String mobile) async {
    final number = mobile.trim();
    if (number.isEmpty) return null;
    final rows = await customSelect(
      '''
SELECT * FROM flats
WHERE tenant_mobile=? AND is_active=1 AND tenant_is_active=1
  AND occupancy_type=? AND trim(tenant_mobile) != ''
LIMIT 1
''',
      variables: [
        Variable<String>(number),
        Variable<String>(kOccupancyTenantOccupied)
      ],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Resolves owner or tenant login by mobile. Prefer exact owner match, then tenant.
  Future<({QueryRow flat, String role})?> resolveResidentByMobile(
      String mobile) async {
    final ownerFlat = await flatForMobile(mobile);
    if (ownerFlat != null) {
      return (flat: ownerFlat, role: SessionStore.roleOwner);
    }
    final tenantFlat = await flatForTenantMobile(mobile);
    if (tenantFlat != null) {
      return (flat: tenantFlat, role: SessionStore.roleTenant);
    }
    return null;
  }

  Future<OccupancyAccess> occupancyAccessFor({
    required int flatId,
    required String sessionRole,
    required String sessionMobile,
  }) async {
    final flat = await flatById(flatId);
    if (flat == null) throw StateError('Flat not found.');
    return OccupancyAccess.forSession(
      flat: flat,
      sessionRole: sessionRole,
      sessionMobile: sessionMobile,
    );
  }

  Future<void> _assertFinanceAccess({
    required int flatId,
    required String sessionRole,
    required String sessionMobile,
  }) async {
    final access = await occupancyAccessFor(
      flatId: flatId,
      sessionRole: sessionRole,
      sessionMobile: sessionMobile,
    );
    access.assertFinance();
  }

  Future<void> _assertResidentialAccess({
    required int flatId,
    required String sessionRole,
    required String sessionMobile,
  }) async {
    final access = await occupancyAccessFor(
      flatId: flatId,
      sessionRole: sessionRole,
      sessionMobile: sessionMobile,
    );
    access.assertResidential();
  }

  /// Marks pending bills overdue. Throttled to once per calendar day (and force).
  Future<void> refreshOverdueStatuses({bool force = false}) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (!force && _overdueRefreshDay == today) return;
    await customStatement(
      "UPDATE bills SET status='overdue' WHERE status='pending' AND substr(due_date,1,10) < ?",
      [today],
    );
    _overdueRefreshDay = today;
  }

  Future<List<QueryRow>> bills(
      {int? flatId, String? status, String? building}) async {
    await refreshOverdueStatuses();
    final clauses = <String>[];
    final vars = <Variable>[];
    if (flatId != null) {
      clauses.add('b.flat_id=?');
      vars.add(Variable<int>(flatId));
    }
    if (status != null && status != 'all') {
      clauses.add('b.status=?');
      vars.add(Variable<String>(status));
    } else if (flatId != null) {
      clauses.add("b.status!='cancelled'");
    }
    if (building != null && building.isNotEmpty && building != 'All') {
      clauses.add('f.building=?');
      vars.add(Variable<String>(building));
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    // Wing A → E first, then flat number, then newest period.
    return customSelect(
      'SELECT b.*,f.flat_number,f.owner_name,f.building,f.mobile,f.monthly_amount AS flat_monthly_amount '
      'FROM bills b JOIN flats f ON f.id=b.flat_id $where '
      'ORDER BY f.building ASC, f.flat_number ASC, b.period_start DESC, b.id DESC',
      variables: vars,
    ).get();
  }

  Future<QueryRow?> billById(int id) async {
    final rows = await customSelect(
      'SELECT b.*,f.flat_number,f.owner_name,f.building,f.mobile FROM bills b JOIN flats f ON f.id=b.flat_id WHERE b.id=? LIMIT 1',
      variables: [Variable<int>(id)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> paymentForBill(int billId,
      {bool includeReversed = false}) async {
    final statusClause = includeReversed ? '' : "AND p.status='success'";
    final rows = await customSelect(
      '''
SELECT p.*, f.flat_number, f.owner_name, f.building,
       b.bill_number, b.period_start, b.period_end, b.months_covered, b.unit_amount, b.amount AS bill_amount
FROM payments p
JOIN flats f ON f.id=p.flat_id
LEFT JOIN bills b ON CAST(b.id AS TEXT)=p.bill_ids
WHERE p.bill_ids=? $statusClause
ORDER BY p.paid_at DESC, p.id DESC
LIMIT 1
''',
      variables: [Variable<String>('$billId')],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<String?> appSetting(String key) async {
    final rows = await customSelect(
      'SELECT setting_value FROM app_settings WHERE setting_key=? LIMIT 1',
      variables: [Variable<String>(key)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('setting_value');
  }

  Future<List<QueryRow>> payments({int? flatId, bool includeReversed = true}) {
    final clauses = <String>[];
    final vars = <Variable>[];
    if (flatId != null) {
      clauses.add('p.flat_id=?');
      vars.add(Variable<int>(flatId));
    }
    if (!includeReversed) {
      clauses.add("p.status='success'");
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return customSelect(
      '''
SELECT p.*, f.flat_number, f.owner_name, f.building,
       b.bill_number, b.period_start, b.period_end, b.months_covered, b.unit_amount, b.amount AS bill_amount
FROM payments p
JOIN flats f ON f.id=p.flat_id
LEFT JOIN bills b ON CAST(b.id AS TEXT)=p.bill_ids
$where
ORDER BY p.paid_at DESC
''',
      variables: vars,
    ).get();
  }

  Future<Map<String, int>> summary() async {
    await refreshOverdueStatuses();
    Future<int> count(String sql) async =>
        (await customSelect(sql).getSingle()).read<int>('n');
    final unpaid = await customSelect(
      "SELECT id FROM bills WHERE status IN ('pending','overdue')",
    ).get();
    var outstandingPrincipal = 0;
    var outstandingInterest = 0;
    // Read-only: do not persist interest ledger rows on every dashboard open.
    for (final r in unpaid) {
      final s =
          await billInterestSummary(r.read<int>('id'), persistLedger: false);
      outstandingPrincipal += s.principalOutstanding;
      outstandingInterest += s.interestOutstanding;
    }
    return {
      'flats': await count('SELECT COUNT(*) AS n FROM flats WHERE is_active=1'),
      'bills': await count(
          "SELECT COUNT(*) AS n FROM bills WHERE status!='cancelled'"),
      'paid':
          await count("SELECT COUNT(*) AS n FROM bills WHERE status='paid'"),
      'pending':
          await count("SELECT COUNT(*) AS n FROM bills WHERE status='pending'"),
      'overdue':
          await count("SELECT COUNT(*) AS n FROM bills WHERE status='overdue'"),
      'collection': await count(
          "SELECT COALESCE(SUM(amount),0) AS n FROM payments WHERE status='success'"),
      'collectionPrincipal': await count(
          "SELECT COALESCE(SUM(principal_amount),0) AS n FROM payments WHERE status='success'"),
      'collectionInterest': await count(
          "SELECT COALESCE(SUM(interest_amount),0) AS n FROM payments WHERE status='success'"),
      'pendingAmount': await count(
          "SELECT COALESCE(SUM(amount),0) AS n FROM bills WHERE status='pending'"),
      'overdueAmount': await count(
          "SELECT COALESCE(SUM(amount),0) AS n FROM bills WHERE status='overdue'"),
      'billedAmount': await count(
          "SELECT COALESCE(SUM(amount),0) AS n FROM bills WHERE status!='cancelled'"),
      'unpaidBills': unpaid.length,
      'outstandingPrincipal': outstandingPrincipal,
      'outstandingInterest': outstandingInterest,
      'outstandingAmount': outstandingPrincipal + outstandingInterest,
    };
  }

  /// Financial report rows. Read-only — never mutates bills/payments.
  Future<List<QueryRow>> reportBills({
    String?
        status, // paid | pending | overdue | unpaid (pending+overdue) | all (non-cancelled)
    String? building,
    String? flatNumberContains,
    int? periodYear,
    int? periodMonth,
    String? paidFrom, // yyyy-MM-dd
    String? paidTo,
    String? dueFrom,
    String? dueTo,
    int? flatId,
  }) async {
    await refreshOverdueStatuses();
    final clauses = <String>["b.status!='cancelled'"];
    final vars = <Variable>[];

    if (status == 'paid') {
      clauses.add("b.status='paid'");
    } else if (status == 'pending') {
      clauses.add("b.status='pending'");
    } else if (status == 'overdue') {
      clauses.add("b.status='overdue'");
    } else if (status == 'unpaid') {
      clauses.add("b.status IN ('pending','overdue')");
    }

    if (building != null && building.isNotEmpty && building != 'All') {
      clauses.add('f.building=?');
      vars.add(Variable<String>(building));
    }
    if (flatNumberContains != null && flatNumberContains.trim().isNotEmpty) {
      clauses.add('lower(f.flat_number) LIKE ?');
      vars.add(
          Variable<String>('%${flatNumberContains.trim().toLowerCase()}%'));
    }
    if (flatId != null) {
      clauses.add('b.flat_id=?');
      vars.add(Variable<int>(flatId));
    }
    if (periodYear != null) {
      clauses.add("CAST(strftime('%Y', b.period_start) AS INTEGER)=?");
      vars.add(Variable<int>(periodYear));
    }
    if (periodMonth != null) {
      clauses.add("CAST(strftime('%m', b.period_start) AS INTEGER)=?");
      vars.add(Variable<int>(periodMonth));
    }
    if (paidFrom != null && paidFrom.isNotEmpty) {
      clauses.add("p.paid_at IS NOT NULL AND substr(p.paid_at,1,10)>=?");
      vars.add(Variable<String>(paidFrom));
    }
    if (paidTo != null && paidTo.isNotEmpty) {
      clauses.add("p.paid_at IS NOT NULL AND substr(p.paid_at,1,10)<=?");
      vars.add(Variable<String>(paidTo));
    }
    if (dueFrom != null && dueFrom.isNotEmpty) {
      clauses.add('substr(b.due_date,1,10)>=?');
      vars.add(Variable<String>(dueFrom));
    }
    if (dueTo != null && dueTo.isNotEmpty) {
      clauses.add('substr(b.due_date,1,10)<=?');
      vars.add(Variable<String>(dueTo));
    }

    final where = 'WHERE ${clauses.join(' AND ')}';
    // Latest successful payment only — avoids duplicate rows when multiple payment records exist.
    return customSelect(
      '''
SELECT b.*,
       f.flat_number, f.owner_name, f.building, f.mobile, f.flat_type,
       p.amount AS paid_amount, p.paid_at, p.method AS payment_method,
       p.receipt_number, p.status AS payment_status,
       p.cheque_number, p.cheque_date, p.bank_name, p.cheque_status,
       p.remarks AS payment_remarks, p.collected_by_name
FROM bills b
JOIN flats f ON f.id=b.flat_id
LEFT JOIN payments p ON p.id = (
  SELECT p2.id FROM payments p2
  WHERE p2.bill_ids=CAST(b.id AS TEXT) AND p2.status='success'
  ORDER BY p2.paid_at DESC, p2.id DESC
  LIMIT 1
)
$where
ORDER BY b.period_start DESC, f.building, f.flat_number
''',
      variables: vars,
    ).get();
  }

  Future<Map<String, int>> reportTotals(List<QueryRow> rows) async {
    var billed = 0;
    var collected = 0;
    var outstanding = 0;
    var outstandingInterest = 0;
    var paidCount = 0;
    var unpaidCount = 0;
    var overdueCount = 0;
    var overdueAmount = 0;
    var overdueInterest = 0;
    for (final r in rows) {
      final amount = r.read<int>('amount');
      final status = r.read<String>('status');
      if (status == 'cancelled') continue;
      billed += amount;
      if (status == 'paid') {
        paidCount++;
        collected += (r.data['paid_amount'] as int?) ?? amount;
      } else if (status == 'pending' || status == 'overdue') {
        unpaidCount++;
        final interest =
            await billInterestSummary(r.read<int>('id'), persistLedger: false);
        outstanding += interest.principalOutstanding;
        outstandingInterest += interest.interestOutstanding;
        if (status == 'overdue' || interest.overdueMonths > 0) {
          overdueCount++;
          overdueAmount += interest.principalOutstanding;
          overdueInterest += interest.interestOutstanding;
        }
      }
    }
    return {
      'rowCount': rows.length,
      'billed': billed,
      'collected': collected,
      'outstanding': outstanding + outstandingInterest,
      'outstandingPrincipal': outstanding,
      'outstandingInterest': outstandingInterest,
      'paidCount': paidCount,
      'unpaidCount': unpaidCount,
      'overdueCount': overdueCount,
      'overdueAmount': overdueAmount + overdueInterest,
      'overduePrincipal': overdueAmount,
      'overdueInterest': overdueInterest,
    };
  }

  Future<void> updateMaintenance(int id, int amount) => customStatement(
      'UPDATE flats SET monthly_amount=? WHERE id=?', [amount, id]);

  Future<String?> flatNumberConflict({
    required String building,
    required String flatNumber,
    int? excludeId,
  }) async {
    final rows = await customSelect(
      'SELECT id FROM flats WHERE building=? AND flat_number=? ${excludeId == null ? '' : 'AND id!=?'} LIMIT 1',
      variables: [
        Variable<String>(building),
        Variable<String>(flatNumber),
        if (excludeId != null) Variable<int>(excludeId),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return 'Flat number already exists in this building.';
  }

  Future<bool> flatHasHistory(int flatId) async {
    final billCount = await customSelect(
      'SELECT COUNT(*) AS n FROM bills WHERE flat_id=?',
      variables: [Variable<int>(flatId)],
    ).getSingle();
    if (billCount.read<int>('n') > 0) return true;
    final payCount = await customSelect(
      'SELECT COUNT(*) AS n FROM payments WHERE flat_id=?',
      variables: [Variable<int>(flatId)],
    ).getSingle();
    return payCount.read<int>('n') > 0;
  }

  void _validateOccupancyFields({
    required String occupancyType,
    required String tenantName,
    required String tenantMobile,
  }) {
    if (occupancyType != kOccupancyOwnerOccupied &&
        occupancyType != kOccupancyTenantOccupied) {
      throw StateError('Occupancy must be Owner Occupied or Tenant Occupied.');
    }
    if (occupancyType == kOccupancyTenantOccupied) {
      if (tenantName.trim().isEmpty)
        throw StateError('Tenant name is required for tenant-occupied flats.');
      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(tenantMobile.trim())) {
        throw StateError('Enter a valid 10-digit tenant mobile number.');
      }
    }
  }

  Future<int> createFlat({
    required String building,
    required String flatNumber,
    required int floor,
    required String flatType,
    required String ownerName,
    required String mobile,
    String? email,
    required int monthlyAmount,
    String occupancyType = kOccupancyOwnerOccupied,
    String tenantName = '',
    String tenantMobile = '',
  }) async {
    final conflict =
        await flatNumberConflict(building: building, flatNumber: flatNumber);
    if (conflict != null) throw StateError(conflict);
    if (flatType != '2 BHK' && flatType != '3 BHK')
      throw StateError('Flat type must be 2 BHK or 3 BHK.');
    _validateOccupancyFields(
      occupancyType: occupancyType,
      tenantName: tenantName,
      tenantMobile: tenantMobile,
    );
    final tenantActive = occupancyType == kOccupancyTenantOccupied ? 1 : 0;
    final storedTenantName = occupancyType == kOccupancyTenantOccupied
        ? tenantName.trim()
        : tenantName.trim();
    final storedTenantMobile = occupancyType == kOccupancyTenantOccupied
        ? tenantMobile.trim()
        : tenantMobile.trim();
    await customStatement(
      '''
INSERT INTO flats(
  building,flat_number,floor,flat_type,owner_name,mobile,email,monthly_amount,is_active,
  occupancy_type,tenant_name,tenant_mobile,tenant_is_active,created_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
      [
        building,
        flatNumber,
        floor,
        flatType,
        ownerName,
        mobile,
        email,
        monthlyAmount,
        1,
        occupancyType,
        storedTenantName,
        storedTenantMobile,
        tenantActive,
        DateTime.now().toIso8601String(),
      ],
    );
    final row =
        await customSelect('SELECT last_insert_rowid() AS id').getSingle();
    return row.read<int>('id');
  }

  Future<void> updateFlat({
    required int id,
    required String building,
    required String flatNumber,
    required int floor,
    required String flatType,
    required String ownerName,
    required String mobile,
    String? email,
    required int monthlyAmount,
    String occupancyType = kOccupancyOwnerOccupied,
    String tenantName = '',
    String tenantMobile = '',
  }) async {
    final conflict = await flatNumberConflict(
        building: building, flatNumber: flatNumber, excludeId: id);
    if (conflict != null) throw StateError(conflict);
    if (flatType != '2 BHK' && flatType != '3 BHK')
      throw StateError('Flat type must be 2 BHK or 3 BHK.');
    _validateOccupancyFields(
      occupancyType: occupancyType,
      tenantName: tenantName,
      tenantMobile: tenantMobile,
    );
    // Owner occupied → deactivate tenant account (keep name/mobile history on the row).
    // Tenant occupied → activate assigned tenant.
    final tenantActive = occupancyType == kOccupancyTenantOccupied ? 1 : 0;
    await customStatement(
      '''
UPDATE flats SET
  building=?, flat_number=?, floor=?, flat_type=?, owner_name=?, mobile=?, email=?, monthly_amount=?,
  occupancy_type=?, tenant_name=?, tenant_mobile=?, tenant_is_active=?
WHERE id=?
''',
      [
        building,
        flatNumber,
        floor,
        flatType,
        ownerName,
        mobile,
        email,
        monthlyAmount,
        occupancyType,
        tenantName.trim(),
        tenantMobile.trim(),
        tenantActive,
        id,
      ],
    );
  }

  Future<List<QueryRow>> otherChargesForFlat(int flatId) => customSelect(
        'SELECT * FROM flat_other_charges WHERE flat_id=? ORDER BY sort_order ASC, id ASC',
        variables: [Variable<int>(flatId)],
      ).get();

  /// Replaces all other charges for a flat. Empty / incomplete rows must be filtered by the caller.
  Future<void> replaceFlatOtherCharges(
      int flatId, List<Map<String, Object?>> charges) async {
    if (charges.length > maxOtherChargesPerFlat) {
      throw StateError(
          'A flat can have at most $maxOtherChargesPerFlat other charges.');
    }
    await transaction(() async {
      await customStatement(
          'DELETE FROM flat_other_charges WHERE flat_id=?', [flatId]);
      for (var i = 0; i < charges.length; i++) {
        final desc = (charges[i]['description'] as String?)?.trim() ?? '';
        final amount = charges[i]['amount'] as int? ?? 0;
        if (desc.isEmpty)
          throw StateError('Service / charge description is required.');
        if (amount <= 0)
          throw StateError('Charge amount must be a positive number.');
        await customStatement(
          'INSERT INTO flat_other_charges(flat_id,description,amount,sort_order) VALUES(?,?,?,?)',
          [flatId, desc, amount, i],
        );
      }
    });
  }

  Future<int> otherChargesTotalForFlat(int flatId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount),0) AS n FROM flat_other_charges WHERE flat_id=?',
      variables: [Variable<int>(flatId)],
    ).getSingle();
    return row.read<int>('n');
  }

  /// Snapshot list for bill storage: [{description, amount}, ...]
  Future<List<Map<String, Object?>>> otherChargesSnapshotForFlat(
      int flatId) async {
    final rows = await otherChargesForFlat(flatId);
    return rows
        .map((r) => <String, Object?>{
              'description': r.read<String>('description'),
              'amount': r.read<int>('amount'),
            })
        .toList();
  }

  static List<Map<String, dynamic>> parseOtherChargesJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => <String, dynamic>{
                'description': '${e['description'] ?? ''}',
                'amount': (e['amount'] as num?)?.toInt() ??
                    int.tryParse('${e['amount']}') ??
                    0,
              })
          .where((e) =>
              (e['description'] as String).isNotEmpty &&
              (e['amount'] as int) > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String> removeOrDeactivateFlat(int flatId) async {
    if (await flatHasHistory(flatId)) {
      await customStatement(
          'UPDATE flats SET is_active=0 WHERE id=?', [flatId]);
      return 'deactivated';
    }
    await customStatement(
        'DELETE FROM flat_other_charges WHERE flat_id=?', [flatId]);
    await customStatement('DELETE FROM flats WHERE id=?', [flatId]);
    return 'deleted';
  }

  Future<void> reactivateFlat(int flatId) =>
      customStatement('UPDATE flats SET is_active=1 WHERE id=?', [flatId]);

  DateTime periodEndFor(DateTime periodStart, int monthsCovered) {
    final lastMonthStart =
        DateTime(periodStart.year, periodStart.month + monthsCovered - 1);
    return DateTime(lastMonthStart.year, lastMonthStart.month + 1, 0);
  }

  /// Preview society-wide billing using each active flat's monthly amount + other charges (once).
  Future<Map<String, int>> previewSocietyBilling({
    required DateTime periodStart,
    required int monthsCovered,
  }) async {
    if (monthsCovered < 1)
      throw StateError('Months covered must be at least 1.');
    final start =
        DateTime(periodStart.year, periodStart.month).toIso8601String();
    final flats = await customSelect(
      'SELECT id, flat_number, monthly_amount FROM flats WHERE is_active=1 ORDER BY building, flat_number',
    ).get();
    var estimated = 0;
    var maintenanceTotal = 0;
    var otherChargesTotal = 0;
    var alreadyBilled = 0;
    for (final flat in flats) {
      final flatId = flat.read<int>('id');
      final unit = flat.read<int>('monthly_amount');
      final existing = await customSelect(
        'SELECT id FROM bills WHERE flat_id=? AND period_start=? LIMIT 1',
        variables: [Variable<int>(flatId), Variable<String>(start)],
      ).get();
      if (existing.isNotEmpty) {
        alreadyBilled++;
        continue;
      }
      final maint = unit * monthsCovered;
      final other = await otherChargesTotalForFlat(flatId);
      maintenanceTotal += maint;
      otherChargesTotal += other;
      estimated += maint + other;
    }
    return {
      'activeFlats': flats.length,
      'estimatedTotal': estimated,
      'maintenanceTotal': maintenanceTotal,
      'otherChargesTotal': otherChargesTotal,
      'billsToGenerate': flats.length - alreadyBilled,
      'alreadyBilled': alreadyBilled,
    };
  }

  /// Creates one bill per active flat.
  /// Grand total = (monthly × months) + other charges (other charges added once, snapshotted on the bill).
  Future<BillGenerationResult> createSocietyBills({
    required DateTime periodStart,
    required int monthsCovered,
    required DateTime issueDate,
    required DateTime dueDate,
    String? remarks,
  }) async {
    if (monthsCovered < 1)
      throw StateError('Months covered must be at least 1.');
    final flats = await customSelect(
      'SELECT id, flat_number, owner_name, monthly_amount FROM flats WHERE is_active=1 ORDER BY building, flat_number',
    ).get();
    if (flats.isEmpty) throw StateError('No active flats found.');
    final start = DateTime(periodStart.year, periodStart.month);
    final end = periodEndFor(start, monthsCovered);
    var created = 0;
    var createdAmount = 0;
    final skippedFlats = <String>[];
    for (final flat in flats) {
      final flatId = flat.read<int>('id');
      final flatNumber = flat.read<String>('flat_number');
      final unit = flat.read<int>('monthly_amount');
      if (unit <= 0) {
        skippedFlats.add('$flatNumber (invalid maintenance amount)');
        continue;
      }
      final existing = await customSelect(
        'SELECT id, status FROM bills WHERE flat_id=? AND period_start=? LIMIT 1',
        variables: [
          Variable<int>(flatId),
          Variable<String>(start.toIso8601String())
        ],
      ).get();
      if (existing.isNotEmpty) {
        final status = existing.first.read<String>('status');
        skippedFlats.add('$flatNumber (existing $status bill)');
        continue;
      }
      final snapshot = await otherChargesSnapshotForFlat(flatId);
      final otherTotal =
          snapshot.fold<int>(0, (sum, c) => sum + (c['amount'] as int));
      final maintenanceAmount = unit * monthsCovered;
      final amount = maintenanceAmount + otherTotal;
      final billNo = 'AS-BILL-${DateTime.now().millisecondsSinceEpoch}-$flatId';
      await customStatement(
        '''
INSERT INTO bills(
  flat_id,bill_number,period_start,period_end,months_covered,unit_amount,
  maintenance_amount,other_charges_total,other_charges_json,amount,
  status,issue_date,due_date,remarks,created_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
        [
          flatId,
          billNo,
          start.toIso8601String(),
          end.toIso8601String(),
          monthsCovered,
          unit,
          maintenanceAmount,
          otherTotal,
          jsonEncode(snapshot),
          amount,
          'pending',
          issueDate.toIso8601String(),
          dueDate.toIso8601String(),
          remarks,
          DateTime.now().toIso8601String(),
        ],
      );
      created++;
      createdAmount += amount;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return BillGenerationResult(
      created: created,
      createdAmount: createdAmount,
      skippedFlats: skippedFlats,
    );
  }

  /// Totals for bills that share a period_start (society generation batch).
  Future<Map<String, int>> periodBillReport(DateTime periodStart) async {
    final start =
        DateTime(periodStart.year, periodStart.month).toIso8601String();
    Future<int> sum(String status) async => (await customSelect(
          "SELECT COALESCE(SUM(amount),0) AS n FROM bills WHERE period_start=? AND status=?",
          variables: [Variable<String>(start), Variable<String>(status)],
        ).getSingle())
            .read<int>('n');
    Future<int> countAll() async => (await customSelect(
          'SELECT COUNT(*) AS n FROM bills WHERE period_start=?',
          variables: [Variable<String>(start)],
        ).getSingle())
            .read<int>('n');
    Future<int> sumAll() async => (await customSelect(
          'SELECT COALESCE(SUM(amount),0) AS n FROM bills WHERE period_start=?',
          variables: [Variable<String>(start)],
        ).getSingle())
            .read<int>('n');
    return {
      'totalBills': await countAll(),
      'totalAmount': await sumAll(),
      'paidAmount': await sum('paid'),
      'pendingAmount': await sum('pending'),
      'overdueAmount': await sum('overdue'),
    };
  }

  /// Monthly billing shortcut (1st issue / 10th due, 1 month) for all active flats.
  Future<BillGenerationResult> createCurrentBills() {
    final now = DateTime.now();
    return createSocietyBills(
      periodStart: DateTime(now.year, now.month),
      monthsCovered: 1,
      issueDate: DateTime(now.year, now.month, 1),
      dueDate: DateTime(now.year, now.month, 10),
      remarks: 'Monthly maintenance',
    );
  }

  Future<void> updateUnpaidBill({
    required int billId,
    required DateTime periodStart,
    required int monthsCovered,
    required int unitAmount,
    required DateTime issueDate,
    required DateTime dueDate,
    String? remarks,
  }) async {
    final bill = await billById(billId);
    if (bill == null) throw StateError('Bill not found.');
    final status = bill.read<String>('status');
    if (status == 'paid') throw StateError('Paid bills cannot be edited.');
    if (status == 'cancelled')
      throw StateError('Cancelled bills cannot be edited.');
    if (monthsCovered < 1)
      throw StateError('Months covered must be at least 1.');
    if (unitAmount <= 0) throw StateError('Amount must be greater than zero.');
    final start = DateTime(periodStart.year, periodStart.month);
    final end = periodEndFor(start, monthsCovered);
    // Keep snapshotted other charges; only recalculate maintenance subtotal from edited months/rate.
    final otherTotal = (bill.data['other_charges_total'] as int?) ?? 0;
    final maintenanceAmount = unitAmount * monthsCovered;
    final amount = maintenanceAmount + otherTotal;
    try {
      await customStatement(
        '''
UPDATE bills SET period_start=?, period_end=?, months_covered=?, unit_amount=?,
  maintenance_amount=?, amount=?, issue_date=?, due_date=?, remarks=?, status=?
WHERE id=? AND status IN ('pending','overdue')
''',
        [
          start.toIso8601String(),
          end.toIso8601String(),
          monthsCovered,
          unitAmount,
          maintenanceAmount,
          amount,
          issueDate.toIso8601String(),
          dueDate.toIso8601String(),
          remarks,
          DateTime.now().isAfter(dueDate) ? 'overdue' : 'pending',
          billId,
        ],
      );
    } catch (_) {
      throw StateError(
          'Could not update bill. Another bill may already exist for this period.');
    }
  }

  Future<void> cancelBill(int billId) async {
    final bill = await billById(billId);
    if (bill == null) throw StateError('Bill not found.');
    final status = bill.read<String>('status');
    if (status == 'paid') throw StateError('Paid bills cannot be cancelled.');
    if (status == 'cancelled') throw StateError('Bill is already cancelled.');
    await customStatement(
        "UPDATE bills SET status='cancelled' WHERE id=? AND status IN ('pending','overdue')",
        [billId]);
  }

  /// Unpaid / partially unpaid bills for a flat, oldest period first.
  Future<List<QueryRow>> outstandingBillsForFlat(int flatId) async {
    await refreshOverdueStatuses();
    return customSelect(
      '''
SELECT b.*, f.flat_number, f.owner_name, f.building, f.mobile
FROM bills b
JOIN flats f ON f.id=b.flat_id
WHERE b.flat_id=? AND b.status IN ('pending','overdue')
ORDER BY b.period_start ASC, b.due_date ASC, b.id ASC
''',
      variables: [Variable<int>(flatId)],
    ).get();
  }

  /// Consolidated outstanding statement with per-bill interest (oldest first).
  Future<FlatOutstandingStatement> flatOutstandingStatement(int flatId,
      {DateTime? asOf}) async {
    final asOfDay = asOf ?? DateTime.now();
    final bills = await outstandingBillsForFlat(flatId);
    final lines = <OutstandingBillLine>[];
    for (final b in bills) {
      final id = b.read<int>('id');
      await ensureInterestLedger(id, asOf: asOfDay);
      final interest =
          await billInterestSummary(id, asOf: asOfDay, persistLedger: false);
      if (interest.totalOutstanding <= 0) continue;
      final billNo = (b.data['bill_number'] as String?)?.isNotEmpty == true
          ? b.read<String>('bill_number')
          : 'AS-BILL-$id';
      lines.add(OutstandingBillLine(
        billId: id,
        billNumber: billNo,
        periodStart: b.read<String>('period_start'),
        periodEnd: b.read<String>('period_end'),
        monthsCovered: (b.data['months_covered'] as int?) ?? 1,
        dueDate: b.read<String>('due_date'),
        status: b.read<String>('status'),
        interest: interest,
      ));
    }
    return FlatOutstandingStatement(
        flatId: flatId, lines: lines, asOf: asOfDay);
  }

  /// True when any older unpaid bill exists for the same flat.
  Future<bool> hasOlderOutstandingBills(int billId) async {
    final bill = await billById(billId);
    if (bill == null) return false;
    final flatId = bill.read<int>('flat_id');
    final periodStart = bill.read<String>('period_start');
    final rows = await customSelect(
      '''
SELECT id FROM bills
WHERE flat_id=? AND status IN ('pending','overdue')
  AND (period_start < ? OR (period_start = ? AND id < ?))
LIMIT 1
''',
      variables: [
        Variable<int>(flatId),
        Variable<String>(periodStart),
        Variable<String>(periodStart),
        Variable<int>(billId),
      ],
    ).get();
    return rows.isNotEmpty;
  }

  void _validateCollectionMethod({
    required String method,
    String? chequeNumber,
    DateTime? chequeDate,
    String? bankName,
  }) {
    if (method != 'Cash' &&
        method != 'Cheque' &&
        method != 'NEFT' &&
        method != 'UPI' &&
        method != 'App (Demo)') {
      throw StateError(
          'Payment method must be Cash, Cheque, NEFT, UPI, or App (Demo).');
    }
    if (method == 'Cheque') {
      if ((chequeNumber ?? '').trim().isEmpty)
        throw StateError('Cheque number is required.');
    }
  }

  /// Settles every outstanding bill for [flatId] oldest-first in one transaction.
  /// Returns the batch receipt number.
  Future<String> settleAllOutstandingForFlat({
    required int flatId,
    required String method,
    required DateTime paymentDate,
    required int amountCollected,
    int? adminId,
    String? adminName,
    String? remarks,
    String? chequeNumber,
    DateTime? chequeDate,
    String? bankName,

    /// When set (owner/tenant self-pay), occupancy finance rules are enforced.
    String? actorRole,
    String? actorMobile,
  }) async {
    if (actorRole == SessionStore.roleOwner ||
        actorRole == SessionStore.roleTenant) {
      await _assertFinanceAccess(
        flatId: flatId,
        sessionRole: actorRole!,
        sessionMobile: actorMobile ?? '',
      );
    }
    return transaction(() async {
      final statement =
          await flatOutstandingStatement(flatId, asOf: paymentDate);
      if (statement.lines.isEmpty)
        throw StateError('No outstanding bills for this flat.');

      final totalDue = statement.totalPayable;
      if (amountCollected != totalDue) {
        throw StateError(
          'Amount collected must equal total outstanding for all bills ($totalDue = principal ${statement.totalPrincipal} + interest ${statement.totalInterest}).',
        );
      }

      final normalized = method.trim();
      _validateCollectionMethod(
        method: normalized,
        chequeNumber: chequeNumber,
        chequeDate: chequeDate,
        bankName: bankName,
      );

      String? chequeStatus;
      String? chequeNo;
      String? chequeDt;
      String? bank;
      if (normalized == 'Cheque') {
        chequeNo = chequeNumber!.trim();
        bank = bankName?.trim().isEmpty == true ? null : bankName?.trim();
        chequeDt = chequeDate?.toIso8601String();
        chequeStatus = 'Pending';
      }

      final batchReceipt = 'MS-BATCH-${DateTime.now().millisecondsSinceEpoch}';
      final paidAt = paymentDate.toIso8601String();
      final note = remarks?.trim().isEmpty == true ? null : remarks?.trim();
      final collector = adminName ?? 'Collector';

      await customStatement(
        '''
INSERT INTO payment_batches(
  flat_id,receipt_number,total_amount,total_principal,total_interest,bills_settled,
  method,status,paid_at,remarks,cheque_number,cheque_date,bank_name,cheque_status,
  collected_by_admin_id,collected_by_name,created_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
        [
          flatId,
          batchReceipt,
          totalDue,
          statement.totalPrincipal,
          statement.totalInterest,
          statement.billCount,
          normalized,
          'success',
          paidAt,
          note,
          chequeNo,
          chequeDt,
          bank,
          chequeStatus,
          adminId,
          collector,
          DateTime.now().toIso8601String(),
        ],
      );

      final batchId =
          (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
              .read<int>('id');

      // Allocate oldest → newest; each bill must be fully settled.
      for (final line in statement.lines) {
        final billId = line.billId;
        final existing = await customSelect(
          "SELECT id FROM payments WHERE bill_ids=? AND status='success' LIMIT 1",
          variables: [Variable<String>('$billId')],
        ).get();
        if (existing.isNotEmpty) {
          throw StateError(
              'Duplicate payment blocked for bill ${line.billNumber}.');
        }

        // Re-check no older unpaid slipped in (service-level lock).
        final older = await customSelect(
          '''
SELECT id FROM bills
WHERE flat_id=? AND status IN ('pending','overdue')
  AND (period_start < ? OR (period_start = ? AND id < ?))
LIMIT 1
''',
          variables: [
            Variable<int>(flatId),
            Variable<String>(line.periodStart),
            Variable<String>(line.periodStart),
            Variable<int>(billId),
          ],
        ).get();
        if (older.isNotEmpty) {
          throw StateError(
              'Cannot settle ${line.billNumber}: older outstanding bills remain.');
        }

        final principalDue = line.principal;
        final interestDue = line.lateInterest;
        final lineTotal = principalDue + interestDue;
        if (lineTotal != line.totalDue || lineTotal <= 0) {
          throw StateError(
              'Invalid outstanding amount for ${line.billNumber}.');
        }

        final lineReceipt = '$batchReceipt-B$billId';
        await customStatement(
          '''
INSERT INTO payments(
  flat_id,bill_ids,receipt_number,amount,principal_amount,interest_amount,method,status,paid_at,
  remarks,cheque_number,cheque_date,bank_name,cheque_status,
  collected_by_admin_id,collected_by_name,batch_id
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
          [
            flatId,
            '$billId',
            lineReceipt,
            lineTotal,
            principalDue,
            interestDue,
            normalized,
            'success',
            paidAt,
            note,
            chequeNo,
            chequeDt,
            bank,
            chequeStatus,
            adminId,
            collector,
            batchId,
          ],
        );

        await customStatement(
          "UPDATE bills SET status='paid' WHERE id=? AND status IN ('pending','overdue')",
          [billId],
        );
        final check = await customSelect('SELECT status FROM bills WHERE id=?',
            variables: [Variable<int>(billId)]).getSingle();
        if (check.read<String>('status') != 'paid') {
          throw StateError('Could not mark ${line.billNumber} as paid.');
        }

        final paymentId = (await customSelect(
          'SELECT id FROM payments WHERE receipt_number=? LIMIT 1',
          variables: [Variable<String>(lineReceipt)],
        ).getSingle())
            .read<int>('id');

        await customStatement(
          'INSERT INTO payment_audit(payment_id,bill_id,action,details,admin_id,admin_name,created_at) VALUES(?,?,?,?,?,?,?)',
          [
            paymentId,
            billId,
            'settle_batch',
            'Batch $batchReceipt · allocated principal $principalDue · interest $interestDue',
            adminId,
            collector,
            DateTime.now().toIso8601String(),
          ],
        );
      }

      // Final verification: no unpaid bills remain that were in the statement.
      for (final line in statement.lines) {
        final st = (await customSelect(
          'SELECT status FROM bills WHERE id=?',
          variables: [Variable<int>(line.billId)],
        ).getSingle())
            .read<String>('status');
        if (st != 'paid') {
          throw StateError(
              'Settlement incomplete for bill ${line.billNumber}.');
        }
      }

      await customStatement(
        'INSERT INTO payment_audit(payment_id,bill_id,action,details,admin_id,admin_name,created_at) VALUES(?,?,?,?,?,?,?)',
        [
          null,
          statement.lines.first.billId,
          'settle_batch_complete',
          'Batch $batchReceipt settled ${statement.billCount} bills · total $totalDue',
          adminId,
          collector,
          DateTime.now().toIso8601String(),
        ],
      );

      return batchReceipt;
    });
  }

  Future<double> lateInterestAnnualRate() async {
    final raw = await appSetting(settingLateInterestAnnualRate);
    final v = double.tryParse(raw ?? '');
    if (v == null || v < 0 || v > 100)
      return LateInterest.defaultAnnualRatePercent;
    return v;
  }

  Future<void> setLateInterestAnnualRate(double annualPercent) async {
    if (annualPercent < 0 || annualPercent > 100) {
      throw StateError('Annual interest rate must be between 0 and 100.');
    }
    await customStatement(
      "INSERT OR REPLACE INTO app_settings(setting_key,setting_value) VALUES(?,?)",
      [settingLateInterestAnnualRate, annualPercent.toString()],
    );
  }

  Future<int> _principalPaidForBill(int billId) async {
    final row = await customSelect(
      "SELECT COALESCE(SUM(principal_amount),0) AS n FROM payments WHERE bill_ids=? AND status='success'",
      variables: [Variable<String>('$billId')],
    ).getSingle();
    return row.read<int>('n');
  }

  Future<int> _interestPaidForBill(int billId) async {
    final row = await customSelect(
      "SELECT COALESCE(SUM(interest_amount),0) AS n FROM payments WHERE bill_ids=? AND status='success'",
      variables: [Variable<String>('$billId')],
    ).getSingle();
    return row.read<int>('n');
  }

  /// Writes missing simple-interest ledger rows for completed overdue months (idempotent).
  Future<void> ensureInterestLedger(int billId, {DateTime? asOf}) async {
    final bill = await billById(billId);
    if (bill == null) return;
    final status = bill.read<String>('status');
    if (status == 'cancelled') return;

    final due = DateTime.tryParse(bill.read<String>('due_date'));
    if (due == null) return;

    final asOfDay = asOf ?? DateTime.now();
    // Paid bills stop accruing after payment date.
    DateTime cutoff = asOfDay;
    if (status == 'paid') {
      final pay = await paymentForBill(billId);
      final paidAt = DateTime.tryParse(pay?.read<String>('paid_at') ?? '');
      if (paidAt != null && paidAt.isBefore(cutoff)) cutoff = paidAt;
    }

    final annual = await lateInterestAnnualRate();
    final monthly = LateInterest.monthlyRateFromAnnual(annual);
    final principalOriginal = bill.read<int>('amount');
    final principalPaid = await _principalPaidForBill(billId);
    final principalOutstanding =
        (principalOriginal - principalPaid).clamp(0, principalOriginal);
    if (principalOutstanding <= 0) return;

    final months = LateInterest.completedOverdueMonths(due, cutoff);
    if (months <= 0) return;

    final nowIso = DateTime.now().toIso8601String();
    for (var i = 1; i <= months; i++) {
      final period = LateInterest.periodForMonth(dueDate: due, monthIndex: i);
      final interest =
          LateInterest.monthlyInterestAmount(principalOutstanding, monthly);
      if (interest <= 0) continue;
      await customStatement(
        '''
INSERT OR IGNORE INTO bill_interest_ledger(
  bill_id,period_key,period_start,period_end,principal_base,
  annual_rate_percent,monthly_rate_percent,interest_amount,created_at
) VALUES(?,?,?,?,?,?,?,?,?)
''',
        [
          billId,
          period.key,
          period.start.toIso8601String(),
          period.end.toIso8601String(),
          principalOutstanding,
          annual,
          monthly,
          interest,
          nowIso,
        ],
      );
    }
  }

  Future<int> _interestAccruedFromLedger(int billId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(interest_amount),0) AS n FROM bill_interest_ledger WHERE bill_id=?',
      variables: [Variable<int>(billId)],
    ).getSingle();
    return row.read<int>('n');
  }

  /// Accrues ledger rows and returns principal/interest outstanding breakdown.
  Future<BillInterestSummary> billInterestSummary(int billId,
      {DateTime? asOf, bool persistLedger = true}) async {
    final bill = await billById(billId);
    if (bill == null) {
      return const BillInterestSummary(
        principalOriginal: 0,
        principalPaid: 0,
        principalOutstanding: 0,
        interestAccrued: 0,
        interestPaid: 0,
        interestOutstanding: 0,
        totalOutstanding: 0,
        overdueMonths: 0,
        annualRatePercent: LateInterest.defaultAnnualRatePercent,
        monthlyRatePercent: LateInterest.defaultAnnualRatePercent / 12,
        dueDate: null,
      );
    }

    final due = DateTime.tryParse(bill.read<String>('due_date'));
    final annual = await lateInterestAnnualRate();
    final monthly = LateInterest.monthlyRateFromAnnual(annual);
    final principalOriginal = bill.read<int>('amount');
    final principalPaid = await _principalPaidForBill(billId);
    final principalOutstanding =
        (principalOriginal - principalPaid).clamp(0, principalOriginal);
    final status = bill.read<String>('status');

    DateTime cutoff = asOf ?? DateTime.now();
    if (status == 'paid') {
      final pay = await paymentForBill(billId);
      final paidAt = DateTime.tryParse(pay?.read<String>('paid_at') ?? '');
      if (paidAt != null) cutoff = paidAt;
    }

    final overdueMonths =
        due == null ? 0 : LateInterest.completedOverdueMonths(due, cutoff);

    if (persistLedger && status != 'cancelled' && principalOutstanding > 0) {
      await ensureInterestLedger(billId, asOf: cutoff);
    }

    var interestAccrued = await _interestAccruedFromLedger(billId);
    // Fallback/display consistency if ledger empty and we skipped persist.
    if (interestAccrued == 0 && overdueMonths > 0 && principalOutstanding > 0) {
      interestAccrued = LateInterest.accruedInterest(
        principal: principalOutstanding,
        completedMonths: overdueMonths,
        annualRatePercent: annual,
      );
    }

    final interestPaid = await _interestPaidForBill(billId);
    final interestOutstanding =
        (interestAccrued - interestPaid).clamp(0, interestAccrued);
    final totalOutstanding =
        status == 'paid' ? 0 : principalOutstanding + interestOutstanding;

    return BillInterestSummary(
      principalOriginal: principalOriginal,
      principalPaid: principalPaid,
      principalOutstanding: status == 'paid' ? 0 : principalOutstanding,
      interestAccrued: interestAccrued,
      interestPaid: interestPaid,
      interestOutstanding: status == 'paid' ? 0 : interestOutstanding,
      totalOutstanding: totalOutstanding,
      overdueMonths: overdueMonths,
      annualRatePercent: annual,
      monthlyRatePercent: monthly,
      dueDate: due,
    );
  }

  /// Admin cash/cheque collection. Always settles every outstanding bill for the
  /// bill's flat (oldest first). Cannot settle a newer bill alone.
  Future<String> adminCollectPayment({
    required int billId,
    required String method, // Cash | Cheque
    required DateTime paymentDate,
    required int amountCollected,
    required int adminId,
    required String adminName,
    String? remarks,
    String? chequeNumber,
    DateTime? chequeDate,
    String? bankName,
  }) async {
    final bill = await billById(billId);
    if (bill == null) throw StateError('Bill not found.');
    final status = bill.read<String>('status');
    if (status == 'paid') throw StateError('This bill is already paid.');
    if (status == 'cancelled')
      throw StateError('Cancelled bills cannot be paid.');
    if (status != 'pending' && status != 'overdue')
      throw StateError('Bill cannot be paid.');

    final flatId = bill.read<int>('flat_id');
    final statement = await flatOutstandingStatement(flatId, asOf: paymentDate);
    if (statement.lines.isEmpty)
      throw StateError('No outstanding bills for this flat.');
    if (!statement.lines.any((l) => l.billId == billId)) {
      throw StateError('Bill is not outstanding for this flat.');
    }
    // Always settle the full flat chain (oldest first). Single newer-bill amounts are rejected.
    if (amountCollected != statement.totalPayable) {
      throw StateError(
        'Previous maintenance dues are pending. Amount must equal total outstanding for all bills '
        '(${statement.totalPayable} = principal ${statement.totalPrincipal} + interest ${statement.totalInterest}). '
        'Use Pay Outstanding Bills.',
      );
    }
    final normalized = method.trim();
    if (normalized != 'Cash' &&
        normalized != 'Cheque' &&
        normalized != 'NEFT' &&
        normalized != 'UPI') {
      throw StateError('Payment method must be Cash, Cheque, NEFT, or UPI.');
    }
    return settleAllOutstandingForFlat(
      flatId: flatId,
      method: normalized,
      paymentDate: paymentDate,
      amountCollected: amountCollected,
      adminId: adminId,
      adminName: adminName,
      remarks: remarks,
      chequeNumber: chequeNumber,
      chequeDate: chequeDate,
      bankName: bankName,
    );
  }

  Future<QueryRow?> paymentBatchByReceipt(String receiptNumber) async {
    final rows = await customSelect(
      '''
SELECT pb.*, f.flat_number, f.owner_name, f.building, f.mobile
FROM payment_batches pb
JOIN flats f ON f.id=pb.flat_id
WHERE pb.receipt_number=?
LIMIT 1
''',
      variables: [Variable<String>(receiptNumber)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<QueryRow>> paymentsForBatch(int batchId) {
    return customSelect(
      '''
SELECT p.*, b.bill_number, b.period_start, b.period_end, b.months_covered, b.amount AS bill_amount,
       b.maintenance_amount, b.other_charges_total
FROM payments p
LEFT JOIN bills b ON CAST(p.bill_ids AS INTEGER)=b.id
WHERE p.batch_id=?
ORDER BY b.period_start ASC, b.id ASC
''',
      variables: [Variable<int>(batchId)],
    ).get();
  }

  /// Update cheque lifecycle. Bounced cheques reverse the payment and restore the bill balance.
  Future<void> updateChequeStatus({
    required int paymentId,
    required String newStatus, // Pending | Cleared | Bounced
    required int adminId,
    required String adminName,
  }) async {
    final allowed = {'Pending', 'Cleared', 'Bounced'};
    if (!allowed.contains(newStatus))
      throw StateError('Invalid cheque status.');

    await transaction(() async {
      final rows = await customSelect(
        'SELECT * FROM payments WHERE id=?',
        variables: [Variable<int>(paymentId)],
      ).get();
      if (rows.isEmpty) throw StateError('Payment not found.');
      final payment = rows.first;
      if (payment.read<String>('method') != 'Cheque') {
        throw StateError('Only cheque payments have cheque status.');
      }

      final current = payment.data['cheque_status'] as String? ?? 'Pending';
      final payStatus = payment.read<String>('status');
      final billId = int.tryParse(payment.read<String>('bill_ids')) ?? 0;
      if (billId <= 0) throw StateError('Payment is not linked to a bill.');

      if (newStatus == 'Bounced') {
        if (payStatus != 'success')
          throw StateError('Only an active cheque payment can be bounced.');
        // Keep payment history; reverse collection and restore bill outstanding.
        await customStatement(
          "UPDATE payments SET status='reversed', cheque_status='Bounced' WHERE id=?",
          [paymentId],
        );
        final bill = await billById(billId);
        if (bill != null && bill.read<String>('status') == 'paid') {
          final due = DateTime.tryParse(bill.read<String>('due_date')) ??
              DateTime.now();
          final today = DateTime.now();
          final dueDay = DateTime(due.year, due.month, due.day);
          final nowDay = DateTime(today.year, today.month, today.day);
          final restore = nowDay.isAfter(dueDay) ? 'overdue' : 'pending';
          await customStatement(
              'UPDATE bills SET status=? WHERE id=?', [restore, billId]);
        }
        await customStatement(
          'INSERT INTO payment_audit(payment_id,bill_id,action,details,admin_id,admin_name,created_at) VALUES(?,?,?,?,?,?,?)',
          [
            paymentId,
            billId,
            'cheque_bounce',
            'Cheque bounced · payment reversed · bill restored to unpaid (was $current)',
            adminId,
            adminName,
            DateTime.now().toIso8601String(),
          ],
        );
        return;
      }

      if (payStatus == 'reversed') {
        throw StateError(
            'Reversed payments cannot be set to $newStatus. Collect payment again on the unpaid bill.');
      }
      await customStatement('UPDATE payments SET cheque_status=? WHERE id=?',
          [newStatus, paymentId]);
      await customStatement(
        'INSERT INTO payment_audit(payment_id,bill_id,action,details,admin_id,admin_name,created_at) VALUES(?,?,?,?,?,?,?)',
        [
          paymentId,
          billId,
          'cheque_status',
          'Cheque status $current → $newStatus',
          adminId,
          adminName,
          DateTime.now().toIso8601String(),
        ],
      );
    });
  }

  Future<List<QueryRow>> paymentAudit({int? billId, int? paymentId}) {
    final clauses = <String>[];
    final vars = <Variable>[];
    if (billId != null) {
      clauses.add('bill_id=?');
      vars.add(Variable<int>(billId));
    }
    if (paymentId != null) {
      clauses.add('payment_id=?');
      vars.add(Variable<int>(paymentId));
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return customSelect(
      'SELECT * FROM payment_audit $where ORDER BY created_at DESC',
      variables: vars,
    ).get();
  }

  // ─── Security guards ─────────────────────────────────────────────

  Future<QueryRow?> guardForMobile(String mobile) async {
    final rows = await customSelect(
      'SELECT * FROM security_guards WHERE mobile=? AND is_active=1 LIMIT 1',
      variables: [Variable<String>(mobile)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> guardById(int id) async {
    final rows = await customSelect(
      'SELECT * FROM security_guards WHERE id=? LIMIT 1',
      variables: [Variable<int>(id)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<QueryRow>> securityGuards({bool includeInactive = true}) {
    final where = includeInactive ? '' : 'WHERE is_active=1';
    return customSelect(
            'SELECT * FROM security_guards $where ORDER BY is_active DESC, name')
        .get();
  }

  Future<int> createSecurityGuard(
      {required String name, required String mobile, String? notes}) async {
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile))
      throw StateError('Enter a valid 10-digit mobile number.');
    final existing = await customSelect(
      'SELECT id FROM security_guards WHERE mobile=? LIMIT 1',
      variables: [Variable<String>(mobile)],
    ).get();
    if (existing.isNotEmpty)
      throw StateError(
          'A security account already exists for this mobile number.');
    await customStatement(
      'INSERT INTO security_guards(name,mobile,is_active,notes,created_at) VALUES(?,?,?,?,?)',
      [name.trim(), mobile, 1, notes, DateTime.now().toIso8601String()],
    );
    return (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
        .read<int>('id');
  }

  Future<void> updateSecurityGuard({
    required int id,
    required String name,
    required String mobile,
    String? notes,
  }) async {
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile))
      throw StateError('Enter a valid 10-digit mobile number.');
    final conflict = await customSelect(
      'SELECT id FROM security_guards WHERE mobile=? AND id!=? LIMIT 1',
      variables: [Variable<String>(mobile), Variable<int>(id)],
    ).get();
    if (conflict.isNotEmpty)
      throw StateError(
          'Another security account already uses this mobile number.');
    await customStatement(
      'UPDATE security_guards SET name=?, mobile=?, notes=? WHERE id=?',
      [name.trim(), mobile, notes, id],
    );
  }

  Future<void> setSecurityGuardActive(int id, bool active) => customStatement(
      'UPDATE security_guards SET is_active=? WHERE id=?',
      [active ? 1 : 0, id]);

  // ─── Visitor invitations (OTP) ───────────────────────────────────

  Future<int> otpValidityHours() async {
    final v = await appSetting('visitor_otp_validity_hours');
    return int.tryParse(v ?? '') ?? defaultOtpValidityHours;
  }

  Future<void> expireStaleInvitations() async {
    // Only owner-generated OTP invites expire. Guard approval requests do not use OTP windows.
    final rows = await customSelect(
      "SELECT id, expected_date, expected_time, validity_hours FROM visitor_invitations WHERE status='pending' AND otp_used=0 AND COALESCE(source,'owner')='owner'",
    ).get();
    final now = DateTime.now();
    for (final r in rows) {
      if (_invitationExpired(r, now)) {
        await customStatement(
            "UPDATE visitor_invitations SET status='expired' WHERE id=? AND status='pending'",
            [r.read<int>('id')]);
      }
    }
  }

  Future<QueryRow?> flatByWingAndNumber(String wing, String flatNumber) async {
    final w = wing.trim().toUpperCase();
    final flat = flatNumber.trim().toUpperCase();
    if (!RegExp(r'^[A-E]$').hasMatch(w)) return null;
    if (flat.isEmpty) return null;
    final building = 'Monarch Solitaire $w';
    final rows = await customSelect(
      'SELECT * FROM flats WHERE building=? AND upper(flat_number)=? AND is_active=1 LIMIT 1',
      variables: [Variable<String>(building), Variable<String>(flat)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Looks up a local demo flat by backend-style number (e.g. `A-101`).
  Future<QueryRow?> flatByNumber(String flatNumber) async {
    final flat = flatNumber.trim().toUpperCase();
    if (flat.isEmpty) return null;
    final rows = await customSelect(
      'SELECT * FROM flats WHERE upper(flat_number)=? AND is_active=1 LIMIT 1',
      variables: [Variable<String>(flat)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<String>> flatNumbersForWing(String wing) async {
    final w = wing.trim().toUpperCase();
    final building = 'Monarch Solitaire $w';
    final rows = await customSelect(
      'SELECT flat_number FROM flats WHERE building=? AND is_active=1 ORDER BY floor, flat_number',
      variables: [Variable<String>(building)],
    ).get();
    return rows.map((r) => r.read<String>('flat_number')).toList();
  }

  Future<void> _auditVisitorRequest({
    required int invitationId,
    required String action,
    required String actorRole,
    int? actorId,
    String? actorName,
    String? details,
  }) async {
    await customStatement(
      'INSERT INTO visitor_request_audit(invitation_id,action,actor_role,actor_id,actor_name,details,created_at) VALUES(?,?,?,?,?,?,?)',
      [
        invitationId,
        action,
        actorRole,
        actorId,
        actorName,
        details,
        DateTime.now().toIso8601String()
      ],
    );
  }

  Future<void> _notify({
    required String recipientRole,
    required String kind,
    required String title,
    required String body,
    int? recipientFlatId,
    int? recipientGuardId,
    int? recipientAdminId,
    int? entityId,
  }) async {
    await customStatement(
      '''
INSERT INTO app_notifications(
  recipient_role,recipient_flat_id,recipient_guard_id,recipient_admin_id,
  kind,title,body,entity_table,entity_id,is_read,created_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?)
''',
      [
        recipientRole,
        recipientFlatId,
        recipientGuardId,
        recipientAdminId,
        kind,
        title,
        body,
        'visitor_invitations',
        entityId,
        0,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  Future<List<QueryRow>> appNotifications({
    required String recipientRole,
    int? flatId,
    int? guardId,
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    final clauses = <String>['recipient_role=?'];
    final vars = <Variable>[Variable<String>(recipientRole)];
    if ((recipientRole == 'owner' || recipientRole == 'tenant') &&
        flatId != null) {
      clauses.add('recipient_flat_id=?');
      vars.add(Variable<int>(flatId));
    }
    if (recipientRole == 'guard' && guardId != null) {
      clauses.add('recipient_guard_id=?');
      vars.add(Variable<int>(guardId));
    }
    if (unreadOnly) clauses.add('is_read=0');
    return customSelect(
      '''
SELECT * FROM app_notifications
WHERE ${clauses.join(' AND ')}
ORDER BY created_at DESC, id DESC
LIMIT $limit
''',
      variables: vars,
    ).get();
  }

  Future<int> unreadNotificationCount({
    required String recipientRole,
    int? flatId,
    int? guardId,
  }) async {
    final rows = await appNotifications(
      recipientRole: recipientRole,
      flatId: flatId,
      guardId: guardId,
      unreadOnly: true,
      limit: 200,
    );
    return rows.length;
  }

  Future<void> markNotificationRead(int id) => customStatement(
      'UPDATE app_notifications SET is_read=1 WHERE id=?', [id]);

  Future<void> markAllNotificationsRead({
    required String recipientRole,
    int? flatId,
    int? guardId,
  }) async {
    if ((recipientRole == 'owner' || recipientRole == 'tenant') &&
        flatId != null) {
      await customStatement(
        'UPDATE app_notifications SET is_read=1 WHERE recipient_role=? AND recipient_flat_id=?',
        [recipientRole, flatId],
      );
      return;
    }
    if (recipientRole == 'guard' && guardId != null) {
      await customStatement(
        "UPDATE app_notifications SET is_read=1 WHERE recipient_role='guard' AND recipient_guard_id=?",
        [guardId],
      );
    }
  }

  Future<List<QueryRow>> visitorRequestAudit(int invitationId) {
    return customSelect(
      'SELECT * FROM visitor_request_audit WHERE invitation_id=? ORDER BY created_at DESC, id DESC',
      variables: [Variable<int>(invitationId)],
    ).get();
  }

  bool _invitationExpired(QueryRow r, DateTime now) {
    final date = r.read<String>('expected_date');
    final time = r.read<String>('expected_time');
    final hours = r.data['validity_hours'] as int? ?? defaultOtpValidityHours;
    final parts = time.split(':');
    final hh = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final mm = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final day = DateTime.tryParse(date) ?? now;
    final expected = DateTime(day.year, day.month, day.day, hh, mm);
    final windowEnd = expected.add(Duration(hours: hours));
    // Valid from start of expected day until window end.
    return now.isAfter(windowEnd);
  }

  DateTime invitationWindowEnd(QueryRow r) {
    final date = r.read<String>('expected_date');
    final time = r.read<String>('expected_time');
    final hours = r.data['validity_hours'] as int? ?? defaultOtpValidityHours;
    final parts = time.split(':');
    final hh = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final mm = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final day = DateTime.tryParse(date) ?? DateTime.now();
    return DateTime(day.year, day.month, day.day, hh, mm)
        .add(Duration(hours: hours));
  }

  Future<String> _generateUniqueOtp() async {
    final rnd = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < 40; i++) {
      final code = ((rnd + i * 7919) % 900000 + 100000).toString();
      final clash = await customSelect(
        "SELECT id FROM visitor_invitations WHERE otp_code=? AND status='pending' AND otp_used=0 LIMIT 1",
        variables: [Variable<String>(code)],
      ).get();
      if (clash.isEmpty) return code;
    }
    throw StateError('Could not generate a unique visitor OTP. Try again.');
  }

  Future<Map<String, int>> visitorDashboardStats({int? flatId}) async {
    await expireStaleInvitations();
    Future<int> count(String sql, [List<Variable> vars = const []]) async =>
        (await customSelect(sql, variables: vars).getSingle()).read<int>('n');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final flatClause = flatId == null ? '' : ' AND flat_id=?';
    final flatVars = flatId == null ? <Variable>[] : [Variable<int>(flatId)];
    return {
      'inside': await count(
          "SELECT COUNT(*) AS n FROM visitor_invitations WHERE status='inside'$flatClause",
          flatVars),
      'todayTotal': await count(
        "SELECT COUNT(*) AS n FROM visitor_invitations WHERE expected_date=?$flatClause",
        [Variable<String>(today), ...flatVars],
      ),
      'pending': await count(
          "SELECT COUNT(*) AS n FROM visitor_invitations WHERE status='pending'$flatClause",
          flatVars),
      'awaitingOwner': await count(
        "SELECT COUNT(*) AS n FROM visitor_invitations WHERE status='awaiting_owner'$flatClause",
        flatVars,
      ),
      'approved': await count(
          "SELECT COUNT(*) AS n FROM visitor_invitations WHERE status='approved'$flatClause",
          flatVars),
      'denied': await count(
          "SELECT COUNT(*) AS n FROM visitor_invitations WHERE status='denied'$flatClause",
          flatVars),
      'completedToday': await count(
        "SELECT COUNT(*) AS n FROM visitor_invitations WHERE status='completed' AND exit_at IS NOT NULL AND substr(exit_at,1,10)=?$flatClause",
        [Variable<String>(today), ...flatVars],
      ),
    };
  }

  Future<List<QueryRow>> invitations({
    int? flatId,
    String? status,
    String? search,
    String? date,
    bool includeOtp = false,
  }) async {
    await expireStaleInvitations();
    final clauses = <String>[];
    final vars = <Variable>[];
    if (flatId != null) {
      clauses.add('i.flat_id=?');
      vars.add(Variable<int>(flatId));
    }
    if (status != null && status != 'all') {
      clauses.add('i.status=?');
      vars.add(Variable<String>(status));
    }
    if (date != null && date.isNotEmpty) {
      clauses.add('i.expected_date=?');
      vars.add(Variable<String>(date));
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim().toLowerCase()}%';
      clauses.add(
          '(lower(i.visitor_name) LIKE ? OR i.mobile LIKE ? OR lower(f.flat_number) LIKE ? OR lower(COALESCE(i.vehicle_number,\'\')) LIKE ?)');
      vars.addAll([
        Variable<String>(q),
        Variable<String>(q),
        Variable<String>(q),
        Variable<String>(q)
      ]);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    // OTP only returned for owner views (includeOtp). Guards/admin never receive codes.
    final selectOtp = includeOtp ? 'i.otp_code,' : 'NULL AS otp_code,';
    return customSelect(
      '''
SELECT i.id, i.flat_id, i.visitor_name, i.mobile, i.category, i.purpose,
       i.expected_date, i.expected_time, i.vehicle_number, $selectOtp
       i.status, i.otp_used, i.validity_hours, i.invalid_attempts,
       i.created_at, i.cancelled_at, i.entry_at, i.exit_at, i.verified_by_guard_id,
       i.source, i.created_by_guard_id, i.photo_path,
       i.owner_decision, i.owner_decision_at, i.owner_decision_by_flat_id,
       i.owner_decision_by_name, i.owner_decision_note,
       f.flat_number, f.owner_name, f.building, f.mobile AS owner_mobile,
       g.name AS guard_name
FROM visitor_invitations i
JOIN flats f ON f.id=i.flat_id
LEFT JOIN security_guards g ON g.id=i.created_by_guard_id
$where
ORDER BY i.created_at DESC, i.id DESC
''',
      variables: vars,
    ).get();
  }

  Future<List<QueryRow>> adminVisitorRequests({
    String? wing,
    String? flatNumber,
    String? status,
    String? date,
    String? search,
  }) async {
    await expireStaleInvitations();
    final clauses = <String>[];
    final vars = <Variable>[];
    if (wing != null && wing != 'All' && wing.isNotEmpty) {
      clauses.add("f.building=?");
      vars.add(
          Variable<String>('Monarch Solitaire ${wing.trim().toUpperCase()}'));
    }
    if (flatNumber != null && flatNumber.trim().isNotEmpty) {
      clauses.add('upper(f.flat_number)=?');
      vars.add(Variable<String>(flatNumber.trim().toUpperCase()));
    }
    if (status != null && status != 'all') {
      clauses.add('i.status=?');
      vars.add(Variable<String>(status));
    }
    if (date != null && date.isNotEmpty) {
      clauses.add('i.expected_date=?');
      vars.add(Variable<String>(date));
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim().toLowerCase()}%';
      clauses.add(
          '(lower(i.visitor_name) LIKE ? OR i.mobile LIKE ? OR lower(f.flat_number) LIKE ? OR lower(COALESCE(i.vehicle_number,\'\')) LIKE ?)');
      vars.addAll([
        Variable<String>(q),
        Variable<String>(q),
        Variable<String>(q),
        Variable<String>(q)
      ]);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return customSelect(
      '''
SELECT i.id, i.flat_id, i.visitor_name, i.mobile, i.category, i.purpose,
       i.expected_date, i.expected_time, i.vehicle_number, NULL AS otp_code,
       i.status, i.otp_used, i.validity_hours, i.invalid_attempts,
       i.created_at, i.cancelled_at, i.entry_at, i.exit_at, i.verified_by_guard_id,
       i.source, i.created_by_guard_id, i.photo_path,
       i.owner_decision, i.owner_decision_at, i.owner_decision_by_flat_id,
       i.owner_decision_by_name, i.owner_decision_note,
       f.flat_number, f.owner_name, f.building, f.mobile AS owner_mobile,
       g.name AS guard_name
FROM visitor_invitations i
JOIN flats f ON f.id=i.flat_id
LEFT JOIN security_guards g ON g.id=i.created_by_guard_id
$where
ORDER BY i.created_at DESC, i.id DESC
''',
      variables: vars,
    ).get();
  }

  /// Owner-only: includes OTP for pending unused invitations on their flat.
  Future<List<QueryRow>> ownerInvitations(int flatId, {String? status}) =>
      invitations(flatId: flatId, status: status, includeOtp: true);

  Future<InviteCreateResult> createInvitation({
    required int flatId,
    required String visitorName,
    required String mobile,
    required String category,
    required String purpose,
    required String expectedDate,
    required String expectedTime,
    String? vehicleNumber,
    int? validityHours,
    String? actorRole,
    String? actorMobile,
  }) async {
    if (actorRole == SessionStore.roleOwner ||
        actorRole == SessionStore.roleTenant) {
      await _assertResidentialAccess(
        flatId: flatId,
        sessionRole: actorRole!,
        sessionMobile: actorMobile ?? '',
      );
    }
    if (visitorName.trim().isEmpty)
      throw StateError('Visitor name is required.');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile))
      throw StateError('Enter a valid 10-digit visitor mobile number.');
    if (purpose.trim().isEmpty)
      throw StateError('Purpose of visit is required.');
    if (DateTime.tryParse(expectedDate) == null)
      throw StateError('Select a valid visit date.');
    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(expectedTime))
      throw StateError('Select a valid arrival time.');
    final flat = await flatById(flatId);
    if (flat == null)
      throw StateError('Your flat was not found or is inactive.');
    final hours = validityHours ?? await otpValidityHours();
    final otp = await _generateUniqueOtp();
    await customStatement(
      '''
INSERT INTO visitor_invitations(
  flat_id,visitor_name,mobile,category,purpose,expected_date,expected_time,
  vehicle_number,otp_code,status,otp_used,validity_hours,invalid_attempts,created_at,source
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
      [
        flatId,
        visitorName.trim(),
        mobile,
        category,
        purpose.trim(),
        expectedDate,
        expectedTime,
        vehicleNumber?.trim().isEmpty == true
            ? null
            : vehicleNumber?.trim().toUpperCase(),
        otp,
        'pending',
        0,
        hours,
        0,
        DateTime.now().toIso8601String(),
        'owner',
      ],
    );
    final id =
        (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
            .read<int>('id');
    return InviteCreateResult(id: id, otp: otp);
  }

  /// Security guard gate registration → Pending Owner Approval (no OTP).
  Future<int> createGuardVisitorRequest({
    required int guardId,
    required String guardName,
    required String wing,
    required String flatNumber,
    required String visitorName,
    required String mobile,
    required String category,
    required String purpose,
    String? vehicleNumber,
    String? photoPath,
  }) async {
    return transaction(() async {
      final guard = await guardById(guardId);
      if (guard == null)
        throw StateError('Security guard session is not valid.');
      if (visitorName.trim().isEmpty)
        throw StateError('Visitor full name is required.');
      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile.trim())) {
        throw StateError('Enter a valid 10-digit visitor mobile number.');
      }
      if (purpose.trim().isEmpty)
        throw StateError('Purpose of visit is required.');
      final flat = await flatByWingAndNumber(wing, flatNumber);
      if (flat == null) {
        throw StateError(
            'Destination flat not found in Monarch Solitaire A to E. Check wing and flat number.');
      }
      final flatId = flat.read<int>('id');
      final now = DateTime.now();
      final date = now.toIso8601String().substring(0, 10);
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final placeholderOtp = 'GATE-${now.microsecondsSinceEpoch}';

      await customStatement(
        '''
INSERT INTO visitor_invitations(
  flat_id,visitor_name,mobile,category,purpose,expected_date,expected_time,
  vehicle_number,otp_code,status,otp_used,validity_hours,invalid_attempts,created_at,
  source,created_by_guard_id,photo_path
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
        [
          flatId,
          visitorName.trim(),
          mobile.trim(),
          category,
          purpose.trim(),
          date,
          time,
          vehicleNumber?.trim().isEmpty == true
              ? null
              : vehicleNumber?.trim().toUpperCase(),
          placeholderOtp,
          'awaiting_owner',
          0,
          defaultOtpValidityHours,
          0,
          now.toIso8601String(),
          'guard',
          guardId,
          photoPath,
        ],
      );
      final id =
          (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
              .read<int>('id');
      await _auditVisitorRequest(
        invitationId: id,
        action: 'gate_request_created',
        actorRole: 'guard',
        actorId: guardId,
        actorName: guardName,
        details:
            'Pending owner approval for ${flat.read<String>('building')} · ${flat.read<String>('flat_number')}',
      );
      final vehicle = vehicleNumber?.trim().isEmpty == true
          ? null
          : vehicleNumber?.trim().toUpperCase();
      final recipient = residentialRecipientForFlat(flat);
      await _notify(
        recipientRole: recipient.role,
        recipientFlatId: flatId,
        kind: 'visitor_approval_needed',
        title: 'Visitor approval needed',
        body:
            '${visitorName.trim()} ($category) requests entry to ${flat.read<String>('flat_number')}'
            '${vehicle == null ? '' : ' · Vehicle $vehicle'}. Gate request at $time.'
            '${recipient.fallbackUsed ? ' (Routed to owner — tenant inactive.)' : ''}',
        entityId: id,
      );
      return id;
    });
  }

  Future<void> ownerApproveVisitorRequest({
    required int invitationId,
    required int flatId,
    required String ownerName,
    String actorRole = SessionStore.roleOwner,
    String? actorMobile,
  }) async {
    await _assertResidentialAccess(
      flatId: flatId,
      sessionRole: actorRole,
      sessionMobile: actorMobile ?? '',
    );
    final access = await occupancyAccessFor(
      flatId: flatId,
      sessionRole: actorRole,
      sessionMobile: actorMobile ?? '',
    );
    final actorName =
        ownerName.trim().isEmpty ? access.displayName : ownerName.trim();
    await transaction(() async {
      final rows = await customSelect(
        'SELECT * FROM visitor_invitations WHERE id=? AND flat_id=? LIMIT 1',
        variables: [Variable<int>(invitationId), Variable<int>(flatId)],
      ).get();
      if (rows.isEmpty)
        throw StateError('Visitor request not found for your flat.');
      final row = rows.first;
      if (row.read<String>('status') != 'awaiting_owner') {
        throw StateError('This request is no longer awaiting your approval.');
      }
      if ((row.data['source'] as String? ?? 'owner') != 'guard') {
        throw StateError('Only security gate requests need resident approval.');
      }
      final now = DateTime.now().toIso8601String();
      await customStatement(
        '''
UPDATE visitor_invitations
SET status='approved',
    owner_decision='approved',
    owner_decision_at=?,
    owner_decision_by_flat_id=?,
    owner_decision_by_name=?,
    owner_decision_note=NULL
WHERE id=? AND flat_id=? AND status='awaiting_owner'
''',
        [now, flatId, actorName, invitationId, flatId],
      );
      final check = await customSelect(
        'SELECT status FROM visitor_invitations WHERE id=?',
        variables: [Variable<int>(invitationId)],
      ).getSingle();
      if (check.read<String>('status') != 'approved') {
        throw StateError(
            'Could not approve — request may already have been decided.');
      }
      await _auditVisitorRequest(
        invitationId: invitationId,
        action: 'resident_approved',
        actorRole: actorRole,
        actorId: flatId,
        actorName: actorName,
        details: 'Approved by $actorRole',
      );
      final guardId = row.data['created_by_guard_id'] as int?;
      if (guardId != null) {
        await _notify(
          recipientRole: 'guard',
          recipientGuardId: guardId,
          kind: 'visitor_approved',
          title: 'Visitor approved',
          body:
              '${row.read<String>('visitor_name')} was approved by $actorName ($actorRole). You may mark the visitor as entered.',
          entityId: invitationId,
        );
      }
    });
  }

  Future<void> ownerDenyVisitorRequest({
    required int invitationId,
    required int flatId,
    required String ownerName,
    String? reason,
    String actorRole = SessionStore.roleOwner,
    String? actorMobile,
  }) async {
    await _assertResidentialAccess(
      flatId: flatId,
      sessionRole: actorRole,
      sessionMobile: actorMobile ?? '',
    );
    final access = await occupancyAccessFor(
      flatId: flatId,
      sessionRole: actorRole,
      sessionMobile: actorMobile ?? '',
    );
    final actorName =
        ownerName.trim().isEmpty ? access.displayName : ownerName.trim();
    await transaction(() async {
      final rows = await customSelect(
        'SELECT * FROM visitor_invitations WHERE id=? AND flat_id=? LIMIT 1',
        variables: [Variable<int>(invitationId), Variable<int>(flatId)],
      ).get();
      if (rows.isEmpty)
        throw StateError('Visitor request not found for your flat.');
      final row = rows.first;
      if (row.read<String>('status') != 'awaiting_owner') {
        throw StateError('This request is no longer awaiting your approval.');
      }
      if ((row.data['source'] as String? ?? 'owner') != 'guard') {
        throw StateError('Only security gate requests need resident approval.');
      }
      final now = DateTime.now().toIso8601String();
      final note = reason?.trim().isEmpty == true ? null : reason?.trim();
      await customStatement(
        '''
UPDATE visitor_invitations
SET status='denied',
    owner_decision='denied',
    owner_decision_at=?,
    owner_decision_by_flat_id=?,
    owner_decision_by_name=?,
    owner_decision_note=?
WHERE id=? AND flat_id=? AND status='awaiting_owner'
''',
        [now, flatId, actorName, note, invitationId, flatId],
      );
      final check = await customSelect(
        'SELECT status FROM visitor_invitations WHERE id=?',
        variables: [Variable<int>(invitationId)],
      ).getSingle();
      if (check.read<String>('status') != 'denied') {
        throw StateError(
            'Could not deny — request may already have been decided.');
      }
      await _auditVisitorRequest(
        invitationId: invitationId,
        action: 'resident_denied',
        actorRole: actorRole,
        actorId: flatId,
        actorName: actorName,
        details: note ?? 'Denied by $actorRole',
      );
      final guardId = row.data['created_by_guard_id'] as int?;
      if (guardId != null) {
        await _notify(
          recipientRole: 'guard',
          recipientGuardId: guardId,
          kind: 'visitor_denied',
          title: 'Visitor denied',
          body:
              '${row.read<String>('visitor_name')} was denied by $actorName ($actorRole).'
              '${note == null ? '' : ' Reason: $note'}',
          entityId: invitationId,
        );
      }
    });
  }

  /// Guard marks an owner-approved gate visitor as entered (no OTP).
  Future<void> confirmApprovedVisitorEntry({
    required int invitationId,
    required int guardId,
  }) async {
    await transaction(() async {
      final rows = await customSelect(
        'SELECT * FROM visitor_invitations WHERE id=? LIMIT 1',
        variables: [Variable<int>(invitationId)],
      ).get();
      if (rows.isEmpty) throw StateError('Visitor request not found.');
      final row = rows.first;
      final status = row.read<String>('status');
      if (status == 'denied') throw StateError('Denied visitors cannot enter.');
      if (status == 'inside')
        throw StateError('Visitor is already marked as entered.');
      if (status == 'completed')
        throw StateError('This visit is already completed.');
      if (status == 'cancelled')
        throw StateError('This request was cancelled.');
      if (status != 'approved') {
        throw StateError(
            'Entry is allowed only after the flat owner approves this request.');
      }
      if ((row.data['owner_decision'] as String?) != 'approved') {
        throw StateError('Owner approval is required before entry.');
      }
      final now = DateTime.now().toIso8601String();
      await customStatement(
        "UPDATE visitor_invitations SET status='inside', entry_at=?, verified_by_guard_id=? WHERE id=? AND status='approved'",
        [now, guardId, invitationId],
      );
      final check = await customSelect(
        'SELECT status FROM visitor_invitations WHERE id=?',
        variables: [Variable<int>(invitationId)],
      ).getSingle();
      if (check.read<String>('status') != 'inside') {
        throw StateError('Could not record entry.');
      }
      await _auditVisitorRequest(
        invitationId: invitationId,
        action: 'guard_entry',
        actorRole: 'guard',
        actorId: guardId,
        details: 'Entered after owner approval',
      );
      final destFlat = await flatById(row.read<int>('flat_id'));
      final recipient = destFlat == null
          ? const ResidentialRecipient(
              role: SessionStore.roleOwner, name: 'Owner', fallbackUsed: false)
          : residentialRecipientForFlat(destFlat);
      await _notify(
        recipientRole: recipient.role,
        recipientFlatId: row.read<int>('flat_id'),
        kind: 'visitor_entered',
        title: 'Visitor entered',
        body:
            '${row.read<String>('visitor_name')} was marked entered at the gate.',
        entityId: invitationId,
      );
    });
  }

  Future<void> cancelInvitation(
      {required int invitationId, int? flatId}) async {
    final clauses = flatId == null ? 'id=?' : 'id=? AND flat_id=?';
    final vars = flatId == null ? [invitationId] : [invitationId, flatId];
    final rows = await customSelect(
        'SELECT status, source FROM visitor_invitations WHERE $clauses LIMIT 1',
        variables: [
          for (final v in vars) Variable<int>(v),
        ]).get();
    if (rows.isEmpty) throw StateError('Invitation not found.');
    final status = rows.first.read<String>('status');
    if (status == 'inside')
      throw StateError('Cannot cancel — visitor is already inside.');
    if (status == 'completed') throw StateError('Visit is already completed.');
    if (status == 'cancelled')
      throw StateError('Invitation is already cancelled.');
    if (status == 'denied')
      throw StateError('Denied requests cannot be cancelled.');
    await customStatement(
      "UPDATE visitor_invitations SET status='cancelled', cancelled_at=? WHERE id=? AND status IN ('pending','expired','awaiting_owner','approved')",
      [DateTime.now().toIso8601String(), invitationId],
    );
    await _auditVisitorRequest(
      invitationId: invitationId,
      action: 'cancelled',
      actorRole: flatId == null ? 'admin' : 'owner',
      actorId: flatId,
    );
  }

  /// Lookup by OTP for security. Never returns OTP in result columns beyond verification.
  Future<OtpVerifyResult> verifyVisitorOtp(String otp) async {
    await expireStaleInvitations();
    final code = otp.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return OtpVerifyResult.invalid('Invalid OTP');
    }
    final rows = await customSelect(
      '''
SELECT i.*, f.flat_number, f.owner_name, f.building
FROM visitor_invitations i
JOIN flats f ON f.id=i.flat_id
WHERE i.otp_code=? LIMIT 1
''',
      variables: [Variable<String>(code)],
    ).get();
    if (rows.isEmpty) return OtpVerifyResult.invalid('Invalid OTP');
    final row = rows.first;
    final status = row.read<String>('status');
    final used = (row.data['otp_used'] as int? ?? 0) == 1;
    final attempts = row.data['invalid_attempts'] as int? ?? 0;

    if (status == 'cancelled')
      return OtpVerifyResult.invalid(
          'This visitor invitation has been cancelled');
    if (used || status == 'inside' || status == 'completed') {
      return OtpVerifyResult.invalid('This OTP has already been used');
    }
    if (status == 'expired' || _invitationExpired(row, DateTime.now())) {
      if (status == 'pending') {
        await customStatement(
            "UPDATE visitor_invitations SET status='expired' WHERE id=?",
            [row.read<int>('id')]);
      }
      return OtpVerifyResult.invalid('This visitor OTP has expired');
    }
    if (attempts >= maxOtpInvalidAttempts) {
      return OtpVerifyResult.invalid(
          'Too many invalid attempts. Ask the owner for a new invitation.');
    }
    if (status != 'pending') return OtpVerifyResult.invalid('Invalid OTP');
    return OtpVerifyResult.ok(row);
  }

  Future<void> recordInvalidOtpAttempt(String otp) async {
    final code = otp.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return;
    await customStatement(
      "UPDATE visitor_invitations SET invalid_attempts=invalid_attempts+1 WHERE otp_code=? AND status='pending'",
      [code],
    );
  }

  Future<void> confirmInvitationEntry(
      {required int invitationId, required int guardId}) async {
    await expireStaleInvitations();
    final rows = await customSelect(
        'SELECT * FROM visitor_invitations WHERE id=? LIMIT 1',
        variables: [Variable<int>(invitationId)]).get();
    if (rows.isEmpty) throw StateError('Invitation not found.');
    final row = rows.first;
    if (row.read<String>('status') == 'cancelled')
      throw StateError('This visitor invitation has been cancelled');
    if ((row.data['otp_used'] as int? ?? 0) == 1 ||
        row.read<String>('status') == 'inside') {
      throw StateError('This OTP has already been used');
    }
    if (row.read<String>('status') == 'expired' ||
        _invitationExpired(row, DateTime.now())) {
      throw StateError('This visitor OTP has expired');
    }
    if (row.read<String>('status') != 'pending')
      throw StateError('Invitation is not valid for entry.');
    await customStatement(
      "UPDATE visitor_invitations SET status='inside', otp_used=1, entry_at=?, verified_by_guard_id=? WHERE id=? AND status='pending' AND otp_used=0",
      [DateTime.now().toIso8601String(), guardId, invitationId],
    );
  }

  Future<void> markInvitationExit(int invitationId) async {
    final rows = await customSelect(
        'SELECT * FROM visitor_invitations WHERE id=? LIMIT 1',
        variables: [Variable<int>(invitationId)]).get();
    if (rows.isEmpty) throw StateError('Visitor not found.');
    final row = rows.first;
    final status = row.read<String>('status');
    if (status == 'completed')
      throw StateError('Exit is already recorded for this visitor.');
    if (status != 'inside')
      throw StateError(
          'Only visitors currently inside can be marked as exited.');
    final now = DateTime.now().toIso8601String();
    await customStatement(
      "UPDATE visitor_invitations SET status='completed', exit_at=? WHERE id=? AND status='inside' AND exit_at IS NULL",
      [now, invitationId],
    );
    await _auditVisitorRequest(
      invitationId: invitationId,
      action: 'guard_exit',
      actorRole: 'guard',
      details: 'Exit recorded',
    );
    final destFlat = await flatById(row.read<int>('flat_id'));
    final recipient = destFlat == null
        ? const ResidentialRecipient(
            role: SessionStore.roleOwner, name: 'Owner', fallbackUsed: false)
        : residentialRecipientForFlat(destFlat);
    await _notify(
      recipientRole: recipient.role,
      recipientFlatId: row.read<int>('flat_id'),
      kind: 'visitor_exited',
      title: 'Visitor exited',
      body:
          '${row.read<String>('visitor_name')} exit was recorded at the gate.',
      entityId: invitationId,
    );
  }

  // Legacy visitors table kept for older demo rows (read-only admin optional).
  Future<List<QueryRow>> visitors({
    int? flatId,
    String? status,
    String? search,
    bool todayOnly = false,
  }) =>
      invitations(
          flatId: flatId,
          status: status,
          search: search,
          date: todayOnly
              ? DateTime.now().toIso8601String().substring(0, 10)
              : null);

  // ─── Vehicles ────────────────────────────────────────────────────

  Future<List<QueryRow>> vehicles({
    int? flatId,
    String? search,
    bool includeInactive = true,
  }) async {
    final clauses = <String>[];
    final vars = <Variable>[];
    if (flatId != null) {
      clauses.add('vh.flat_id=?');
      vars.add(Variable<int>(flatId));
    }
    if (!includeInactive) {
      clauses.add('vh.is_active=1');
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim().toLowerCase()}%';
      clauses.add(
          '(lower(vh.registration_number) LIKE ? OR lower(vh.brand_model) LIKE ? OR lower(COALESCE(vh.parking_slot,\'\')) LIKE ? OR lower(f.flat_number) LIKE ?)');
      vars.addAll([
        Variable<String>(q),
        Variable<String>(q),
        Variable<String>(q),
        Variable<String>(q)
      ]);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return customSelect(
      '''
SELECT vh.*, f.flat_number, f.owner_name, f.building
FROM vehicles vh
JOIN flats f ON f.id=vh.flat_id
$where
ORDER BY vh.is_active DESC, vh.registration_number
''',
      variables: vars,
    ).get();
  }

  /// Active vehicles only are treated as currently authorized at the gate.
  Future<QueryRow?> vehicleByRegistration(String registration,
      {bool activeOnly = true}) async {
    final reg = registration.trim().toUpperCase().replaceAll(' ', '');
    final activeClause = activeOnly ? ' AND vh.is_active=1' : '';
    final rows = await customSelect(
      '''
SELECT vh.*, f.flat_number, f.owner_name, f.building
FROM vehicles vh JOIN flats f ON f.id=vh.flat_id
WHERE replace(upper(vh.registration_number),' ','')=?$activeClause LIMIT 1
''',
      variables: [Variable<String>(reg)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> createVehicle({
    required int flatId,
    required String registrationNumber,
    required String vehicleType,
    required String brandModel,
    String? colour,
    String? parkingSlot,
    String? photoPath,
  }) async {
    final flat = await flatById(flatId);
    if (flat == null)
      throw StateError('Selected flat was not found or is inactive.');
    final reg = registrationNumber.trim().toUpperCase().replaceAll(' ', '');
    if (reg.length < 6)
      throw StateError('Enter a valid vehicle registration number.');
    if (brandModel.trim().isEmpty)
      throw StateError('Brand and model are required.');
    final conflict = await customSelect(
      "SELECT id FROM vehicles WHERE replace(upper(registration_number),' ','')=? LIMIT 1",
      variables: [Variable<String>(reg)],
    ).get();
    if (conflict.isNotEmpty)
      throw StateError('This registration number is already registered.');
    await customStatement(
      'INSERT INTO vehicles(flat_id,registration_number,vehicle_type,brand_model,colour,parking_slot,photo_path,is_active,created_at) VALUES(?,?,?,?,?,?,?,?,?)',
      [
        flatId,
        reg,
        vehicleType,
        brandModel.trim(),
        colour?.trim(),
        parkingSlot?.trim(),
        photoPath,
        1,
        DateTime.now().toIso8601String(),
      ],
    );
    return (await customSelect('SELECT last_insert_rowid() AS id').getSingle())
        .read<int>('id');
  }

  Future<void> updateVehicle({
    required int id,
    required int flatId,
    required String registrationNumber,
    required String vehicleType,
    required String brandModel,
    String? colour,
    String? parkingSlot,
    String? photoPath,
  }) async {
    final flat = await flatById(flatId);
    if (flat == null)
      throw StateError('Selected flat was not found or is inactive.');
    final reg = registrationNumber.trim().toUpperCase().replaceAll(' ', '');
    if (reg.length < 6)
      throw StateError('Enter a valid vehicle registration number.');
    final conflict = await customSelect(
      "SELECT id FROM vehicles WHERE replace(upper(registration_number),' ','')=? AND id!=? LIMIT 1",
      variables: [Variable<String>(reg), Variable<int>(id)],
    ).get();
    if (conflict.isNotEmpty)
      throw StateError('This registration number is already registered.');
    await customStatement(
      'UPDATE vehicles SET flat_id=?, registration_number=?, vehicle_type=?, brand_model=?, colour=?, parking_slot=?, photo_path=COALESCE(?, photo_path) WHERE id=?',
      [
        flatId,
        reg,
        vehicleType,
        brandModel.trim(),
        colour?.trim(),
        parkingSlot?.trim(),
        photoPath,
        id
      ],
    );
  }

  Future<void> setVehicleActive(int id, bool active) => customStatement(
      'UPDATE vehicles SET is_active=? WHERE id=?', [active ? 1 : 0, id]);

  Future<void> assignParkingSlot(int vehicleId, String? parkingSlot) =>
      customStatement('UPDATE vehicles SET parking_slot=? WHERE id=?',
          [parkingSlot?.trim(), vehicleId]);

  Future<void> recordVehicleGateEvent({
    required String registrationNumber,
    required String direction,
    required int guardId,
    String? approvalNote,
  }) async {
    final reg = registrationNumber.trim().toUpperCase().replaceAll(' ', '');
    final vehicle = await vehicleByRegistration(reg, activeOnly: true);
    final isReg = vehicle != null;
    await customStatement(
      '''
INSERT INTO vehicle_gate_logs(
  vehicle_id,registration_number,flat_id,direction,is_registered,requires_approval,approval_note,recorded_by_guard_id,recorded_at
) VALUES(?,?,?,?,?,?,?,?,?)
''',
      [
        vehicle?.read<int>('id'),
        reg,
        vehicle?.read<int>('flat_id'),
        direction,
        isReg ? 1 : 0,
        isReg ? 0 : 1,
        approvalNote,
        guardId,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  Future<List<QueryRow>> vehicleGateLogs({String? search}) async {
    final clauses = <String>[];
    final vars = <Variable>[];
    if (search != null && search.trim().isNotEmpty) {
      clauses.add('lower(l.registration_number) LIKE ?');
      vars.add(Variable<String>('%${search.trim().toLowerCase()}%'));
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return customSelect(
      '''
SELECT l.*, f.flat_number, f.owner_name
FROM vehicle_gate_logs l
LEFT JOIN flats f ON f.id=l.flat_id
$where
ORDER BY l.recorded_at DESC
LIMIT 200
''',
      variables: vars,
    ).get();
  }
}

class InviteCreateResult {
  InviteCreateResult({required this.id, required this.otp});
  final int id;
  final String otp;
}

class OtpVerifyResult {
  OtpVerifyResult._({required this.ok, this.invitation, this.message});
  factory OtpVerifyResult.ok(QueryRow invitation) =>
      OtpVerifyResult._(ok: true, invitation: invitation);
  factory OtpVerifyResult.invalid(String message) =>
      OtpVerifyResult._(ok: false, message: message);
  final bool ok;
  final QueryRow? invitation;
  final String? message;
}

/// Result of society-wide bill generation.
class BillGenerationResult {
  BillGenerationResult({
    required this.created,
    required this.createdAmount,
    required this.skippedFlats,
  });
  final int created;
  final int createdAmount;
  final List<String> skippedFlats;
  int get skipped => skippedFlats.length;
}
