import 'package:apna_society/services/late_interest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no interest on or before due date', () {
    final due = DateTime(2026, 10, 10);
    expect(LateInterest.completedOverdueMonths(due, DateTime(2026, 10, 10)), 0);
    expect(LateInterest.completedOverdueMonths(due, DateTime(2026, 10, 9)), 0);
    expect(LateInterest.completedOverdueMonths(due, DateTime(2026, 10, 11)), 0);
  });

  test('first month completes on same day next month', () {
    final due = DateTime(2026, 10, 10);
    expect(LateInterest.completedOverdueMonths(due, DateTime(2026, 11, 9)), 0);
    expect(LateInterest.completedOverdueMonths(due, DateTime(2026, 11, 10)), 1);
    expect(LateInterest.completedOverdueMonths(due, DateTime(2026, 12, 10)), 2);
    expect(LateInterest.completedOverdueMonths(due, DateTime(2027, 1, 10)), 3);
  });

  test('simple interest example 12000 x 2% x 3 months', () {
    final interest = LateInterest.accruedInterest(
      principal: 12000,
      completedMonths: 3,
      annualRatePercent: 24,
    );
    expect(interest, 720);
    expect(12000 + interest, 12720);
  });

  test('flat outstanding statement sums principal + interest oldest first', () {
    BillInterestSummary interest({required int principal, required int late}) =>
        BillInterestSummary(
          principalOriginal: principal,
          principalPaid: 0,
          principalOutstanding: principal,
          interestAccrued: late,
          interestPaid: 0,
          interestOutstanding: late,
          totalOutstanding: principal + late,
          overdueMonths: late > 0 ? 1 : 0,
          annualRatePercent: 24,
          monthlyRatePercent: 2,
          dueDate: DateTime(2026, 10, 10),
        );

    final statement = FlatOutstandingStatement(
      flatId: 1,
      asOf: DateTime(2026, 11, 15),
      lines: [
        OutstandingBillLine(
          billId: 1,
          billNumber: 'Bill 001',
          periodStart: '2026-10-01',
          periodEnd: '2026-10-31',
          monthsCovered: 1,
          dueDate: '2026-10-10',
          status: 'overdue',
          interest: interest(principal: 4000, late: 80),
        ),
        OutstandingBillLine(
          billId: 2,
          billNumber: 'Bill 002',
          periodStart: '2026-11-01',
          periodEnd: '2026-11-30',
          monthsCovered: 1,
          dueDate: '2026-11-10',
          status: 'pending',
          interest: interest(principal: 4000, late: 0),
        ),
      ],
    );

    expect(statement.billCount, 2);
    expect(statement.totalPrincipal, 8000);
    expect(statement.totalInterest, 80);
    expect(statement.totalPayable, 8080);
    expect(statement.oldestPeriodStart, '2026-10-01');
    expect(statement.lines.first.billNumber, 'Bill 001');
  });
}
