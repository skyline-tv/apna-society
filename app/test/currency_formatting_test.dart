import 'package:apna_society/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money — Indian rupee grouping', () {
    test('formats society rate totals with Indian grouping', () {
      expect(money(588000), '₹5,88,000');
      expect(money(4000), '₹4,000');
      expect(money(5000), '₹5,000');
    });

    test('handles small values and zero', () {
      expect(money(0), '₹0');
      expect(money(7), '₹7');
      expect(money(999), '₹999');
      expect(money(1000), '₹1,000');
    });

    test('handles larger Indian-style amounts', () {
      expect(money(1234567), '₹12,34,567');
      expect(money(10000000), '₹1,00,00,000');
    });
  });

  group('moneyPaise — remains paise-based with decimal rupees', () {
    test('does not use money() for paise fields', () {
      expect(moneyPaise(0), '₹0.00');
      expect(moneyPaise(100), '₹1.00');
      expect(moneyPaise(123456), '₹1,234.56');
      // 588000 paise is ₹5,880.00 — not the society rate-sum display.
      expect(moneyPaise(588000), '₹5,880.00');
      expect(money(588000), isNot(moneyPaise(588000)));
    });
  });
}
