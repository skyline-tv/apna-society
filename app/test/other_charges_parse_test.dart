import 'package:apna_society/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('other charges JSON snapshot parses and totals correctly', () {
    const raw =
        '[{"description":"Car Washing","amount":500},{"description":"Two Wheeler Washing","amount":200},{"description":"Sub-Lease Charges","amount":1000}]';
    final list = LocalDatabase.parseOtherChargesJson(raw);
    expect(list.length, 3);
    expect(list.first['description'], 'Car Washing');
    final total = list.fold<int>(0, (s, c) => s + (c['amount'] as int));
    expect(total, 1700);

    // Multi-month maintenance + one-time other charges.
    const unit = 4000;
    const months = 3;
    final grand = unit * months + total;
    expect(grand, 13700);
  });

  test('empty and invalid snapshots are ignored', () {
    expect(LocalDatabase.parseOtherChargesJson(null), isEmpty);
    expect(LocalDatabase.parseOtherChargesJson('[]'), isEmpty);
    expect(LocalDatabase.parseOtherChargesJson('not-json'), isEmpty);
  });
}
