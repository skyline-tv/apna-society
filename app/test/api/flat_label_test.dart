import 'package:apna_society/api/models/flat_label.dart';
import 'package:apna_society/api/models/society_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatFlatLabel', () {
    test('joins wing and bare number', () {
      expect(formatFlatLabel('E', '303'), 'E-303');
      expect(formatFlatLabel('A', '101'), 'A-101');
    });

    test('does not duplicate a wing already stored on the number', () {
      expect(formatFlatLabel('E', 'E-303'), 'E-303');
      expect(formatFlatLabel('E', 'E-E-303'), 'E-303');
      expect(formatFlatLabel('B', 'B204'), 'B-204');
    });
  });

  test('SocietyFlatPick label ignores occupancy and does not double wing', () {
    final pick = SocietyFlatPick.fromLeanJson({
      'id': '507f1f77bcf86cd799439013',
      'wingId': '507f1f77bcf86cd799439012',
      'wingCode': 'E',
      'number': 'E-303',
      'label': 'E-303',
    });
    expect(pick.label, 'E-303');
    expect(pick.wingCode, 'E');
  });
}
