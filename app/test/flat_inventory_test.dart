import 'package:apna_society/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical society flats match official 140-flat inventory', () {
    final db = LocalDatabase();
    final specs = db.canonicalSocietyFlats();

    expect(specs.length, 140);
    expect(specs.map((s) => s['building']).toSet().length, 5);
    expect(
        specs.map((s) => '${s['building']}-${s['floor']}').toSet().length, 35);

    final twoBhk = specs.where((s) => s['flat_type'] == '2 BHK').length;
    final threeBhk = specs.where((s) => s['flat_type'] == '3 BHK').length;
    expect(twoBhk, 112);
    expect(threeBhk, 28);

    final monthly =
        specs.fold<int>(0, (sum, s) => sum + (s['monthly_amount'] as int));
    expect(monthly, 588000);
    expect(monthly * 12, 7056000);

    Map<String, Object?> byNumber(String n) =>
        specs.firstWhere((s) => s['flat_number'] == n);

    expect(byNumber('A-101')['flat_type'], '2 BHK');
    expect(byNumber('A-101')['monthly_amount'], 4000);
    expect(byNumber('A-103')['flat_type'], '3 BHK');
    expect(byNumber('A-103')['monthly_amount'], 5000);
    expect(byNumber('A-704')['flat_type'], '3 BHK');
    expect(byNumber('A-704')['monthly_amount'], 5000);

    expect(byNumber('B-101')['flat_type'], '2 BHK');
    expect(byNumber('B-104')['monthly_amount'], 4000);
    expect(byNumber('C-701')['monthly_amount'], 4000);
    expect(byNumber('D-402')['flat_type'], '2 BHK');

    expect(byNumber('E-101')['flat_type'], '3 BHK');
    expect(byNumber('E-101')['monthly_amount'], 5000);
    expect(byNumber('E-103')['flat_type'], '2 BHK');
    expect(byNumber('E-103')['monthly_amount'], 4000);
    expect(byNumber('E-704')['flat_type'], '2 BHK');

    // 3-month bill amounts from flat maintenance (billing reads monthly_amount × months).
    expect((byNumber('A-101')['monthly_amount'] as int) * 3, 12000);
    expect((byNumber('A-103')['monthly_amount'] as int) * 3, 15000);
  });
}
