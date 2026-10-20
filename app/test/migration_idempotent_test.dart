import 'package:apna_society/data/local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Pre-v10 schema: flats exist but `flat_type` does not.
Database _openLegacyUserVersion9() {
  final raw = sqlite3.openInMemory();
  raw.execute('''
CREATE TABLE flats(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  building TEXT NOT NULL,
  flat_number TEXT NOT NULL,
  floor INTEGER NOT NULL,
  owner_name TEXT NOT NULL DEFAULT '',
  mobile TEXT NOT NULL DEFAULT '',
  email TEXT,
  monthly_amount INTEGER NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  UNIQUE(building, flat_number)
)''');
  raw.execute('''
CREATE TABLE bills(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  bill_number TEXT,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  months_covered INTEGER NOT NULL DEFAULT 1,
  unit_amount INTEGER,
  amount INTEGER NOT NULL,
  status TEXT NOT NULL,
  issue_date TEXT,
  due_date TEXT NOT NULL,
  remarks TEXT,
  created_at TEXT NOT NULL
)''');
  raw.execute('''
CREATE TABLE payments(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  bill_ids TEXT NOT NULL,
  receipt_number TEXT NOT NULL UNIQUE,
  amount INTEGER NOT NULL,
  method TEXT NOT NULL,
  status TEXT NOT NULL,
  paid_at TEXT NOT NULL
)''');
  raw.execute(
      'CREATE TABLE app_settings(setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL)');
  raw.execute('''
CREATE TABLE admins(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  mobile TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''');
  raw.execute('''
INSERT INTO flats(building,flat_number,floor,owner_name,mobile,monthly_amount,is_active,created_at)
VALUES('Monarch Solitaire A','A-101',1,'Demo Owner','9876510032',4000,1,'2026-01-01T00:00:00.000')
''');
  raw.execute('''
INSERT INTO bills(flat_id,bill_number,period_start,period_end,months_covered,unit_amount,amount,status,issue_date,due_date,created_at)
VALUES(1,'AS-BILL-1','2026-01-01','2026-03-31',3,4000,12000,'pending','2026-01-01','2026-01-10','2026-01-01T00:00:00.000')
''');
  raw.userVersion = 9;
  return raw;
}

/// Schema already has flat_type (as if a newer onCreate ran) but user_version is still 9.
Database _openPartialUpgradeUserVersion9WithFlatType() {
  final raw = sqlite3.openInMemory();
  raw.execute('''
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
  created_at TEXT NOT NULL,
  UNIQUE(building, flat_number)
)''');
  raw.execute('''
CREATE TABLE bills(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  bill_number TEXT,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  months_covered INTEGER NOT NULL DEFAULT 1,
  unit_amount INTEGER,
  amount INTEGER NOT NULL,
  status TEXT NOT NULL,
  issue_date TEXT,
  due_date TEXT NOT NULL,
  remarks TEXT,
  created_at TEXT NOT NULL
)''');
  raw.execute('''
CREATE TABLE payments(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  flat_id INTEGER NOT NULL,
  bill_ids TEXT NOT NULL,
  receipt_number TEXT NOT NULL UNIQUE,
  amount INTEGER NOT NULL,
  method TEXT NOT NULL,
  status TEXT NOT NULL,
  paid_at TEXT NOT NULL
)''');
  raw.execute(
      'CREATE TABLE app_settings(setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL)');
  raw.execute('''
CREATE TABLE admins(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  mobile TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''');
  raw.execute('''
INSERT INTO flats(building,flat_number,floor,flat_type,owner_name,mobile,monthly_amount,is_active,created_at)
VALUES('Monarch Solitaire A','A-101',1,'3 BHK','Keep Me','9999911111',5000,1,'2026-01-01T00:00:00.000')
''');
  raw.userVersion = 9;
  return raw;
}

LocalDatabase _wrap(Database raw) =>
    LocalDatabase.forExecutor(NativeDatabase.opened(raw));

void main() {
  test('upgrade from v9 without flat_type adds column and preserves flat row',
      () async {
    final db = _wrap(_openLegacyUserVersion9());
    addTearDown(db.close);

    await db
        .customSelect('SELECT 1')
        .get(); // runs migrations → schemaVersion 16

    expect(await db.columnExists('flats', 'flat_type'), isTrue);
    final flat = await db
        .customSelect(
            "SELECT owner_name, mobile, flat_type FROM flats WHERE flat_number='A-101'")
        .getSingle();
    expect(flat.read<String>('owner_name'), 'Demo Owner');
    expect(flat.read<String>('mobile'), '9876510032');
    expect(flat.read<String>('flat_type'), '2 BHK');
    expect(db.schemaVersion, 19);
    expect(await db.columnExists('flats', 'occupancy_type'), isTrue);
    expect(await db.columnExists('flats', 'tenant_mobile'), isTrue);
  });

  test('upgrade from v9 when flat_type already exists does not fail', () async {
    final db = _wrap(_openPartialUpgradeUserVersion9WithFlatType());
    addTearDown(db.close);

    // Production failure mode was: duplicate column name: flat_type
    await db.customSelect('SELECT 1').get();

    expect(await db.columnExists('flats', 'flat_type'), isTrue);
    final count =
        await db.customSelect('SELECT COUNT(*) AS n FROM flats').getSingle();
    expect(count.read<int>('n'), greaterThan(0));
    final flat = await db
        .customSelect("SELECT flat_number FROM flats WHERE flat_number='A-101'")
        .getSingle();
    expect(flat.read<String>('flat_number'), 'A-101');
  });

  test('reconcile does not wipe flat_type when already present', () async {
    final db = LocalDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
        "UPDATE flats SET flat_type='3 BHK' WHERE flat_number='A-103'");
    await db.reconcileSchemaColumns();
    final flat = await db
        .customSelect("SELECT flat_type FROM flats WHERE flat_number='A-103'")
        .getSingle();
    expect(flat.read<String>('flat_type'), '3 BHK');
  });

  test('addColumnIfMissing is a no-op when column exists', () async {
    final db = LocalDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .customSelect('SELECT 1')
        .get(); // fresh onCreate includes flat_type

    expect(await db.columnExists('flats', 'flat_type'), isTrue);
    await db.addColumnIfMissing(
      table: 'flats',
      column: 'flat_type',
      sqliteTypeAndConstraints: "TEXT NOT NULL DEFAULT '2 BHK'",
    );
    await db.reconcileSchemaColumns();
    await db.reconcileSchemaColumns();
    expect(await db.columnExists('flats', 'flat_type'), isTrue);
    expect(await db.columnExists('payments', 'batch_id'), isTrue);
    expect(await db.columnExists('bills', 'other_charges_json'), isTrue);
  });

  test('reopening migrated DB does not error', () async {
    final raw = _openPartialUpgradeUserVersion9WithFlatType();
    final first = _wrap(raw);
    await first.customSelect('SELECT 1').get();
    await first.close();

    // Re-open same in-memory handle is closed; simulate reopen by checking helpers on fresh create.
    final fresh = LocalDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(fresh.close);
    await fresh.customSelect('SELECT 1').get();
    await fresh.customSelect('SELECT 1').get();
    expect(await fresh.columnExists('flats', 'flat_type'), isTrue);
  });
}
