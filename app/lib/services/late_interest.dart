/// Simple late-payment interest for Monarch Solitaire (non-compounding).
///
/// Annual rate defaults to 24% → 2% per completed overdue month.
/// Interest starts after the due date; the first month is chargeable only once
/// a full month has elapsed after the due date.
class LateInterest {
  LateInterest._();

  static const defaultAnnualRatePercent = 24.0;

  static double monthlyRateFromAnnual(double annualPercent) =>
      annualPercent / 12.0;

  /// Completed full months after [dueDate] as of [asOf] (date-only).
  /// On/before due date → 0. Due 10 Oct → 0 until 10 Nov; 1 on/after 10 Nov; etc.
  static int completedOverdueMonths(DateTime dueDate, DateTime asOf) {
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final day = DateTime(asOf.year, asOf.month, asOf.day);
    if (!day.isAfter(due)) return 0;
    var months = (day.year - due.year) * 12 + (day.month - due.month);
    if (day.day < due.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  /// One month's interest on [principal] at [monthlyRatePercent] (rupees, rounded).
  static int monthlyInterestAmount(int principal, double monthlyRatePercent) {
    if (principal <= 0 || monthlyRatePercent <= 0) return 0;
    return (principal * monthlyRatePercent / 100.0).round();
  }

  /// Simple interest for [completedMonths] on constant [principal] (no compounding).
  static int accruedInterest({
    required int principal,
    required int completedMonths,
    required double annualRatePercent,
  }) {
    if (principal <= 0 || completedMonths <= 0) return 0;
    final monthly = monthlyRateFromAnnual(annualRatePercent);
    return monthlyInterestAmount(principal, monthly) * completedMonths;
  }

  /// Period key / window for the Nth completed overdue month (1-based).
  static ({String key, DateTime start, DateTime end}) periodForMonth({
    required DateTime dueDate,
    required int monthIndex,
  }) {
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final start = DateTime(due.year, due.month + (monthIndex - 1), due.day)
        .add(const Duration(days: 1));
    final end = DateTime(due.year, due.month + monthIndex, due.day);
    final key = '${end.year}-${end.month.toString().padLeft(2, '0')}';
    return (key: key, start: start, end: end);
  }
}

class BillInterestSummary {
  const BillInterestSummary({
    required this.principalOriginal,
    required this.principalPaid,
    required this.principalOutstanding,
    required this.interestAccrued,
    required this.interestPaid,
    required this.interestOutstanding,
    required this.totalOutstanding,
    required this.overdueMonths,
    required this.annualRatePercent,
    required this.monthlyRatePercent,
    required this.dueDate,
  });

  final int principalOriginal;
  final int principalPaid;
  final int principalOutstanding;
  final int interestAccrued;
  final int interestPaid;
  final int interestOutstanding;
  final int totalOutstanding;
  final int overdueMonths;
  final double annualRatePercent;
  final double monthlyRatePercent;
  final DateTime? dueDate;
}

/// One outstanding bill line in a flat settlement statement.
class OutstandingBillLine {
  const OutstandingBillLine({
    required this.billId,
    required this.billNumber,
    required this.periodStart,
    required this.periodEnd,
    required this.monthsCovered,
    required this.dueDate,
    required this.status,
    required this.interest,
  });

  final int billId;
  final String billNumber;
  final String periodStart;
  final String periodEnd;
  final int monthsCovered;
  final String dueDate;
  final String status;
  final BillInterestSummary interest;

  int get principal => interest.principalOutstanding;
  int get lateInterest => interest.interestOutstanding;
  int get totalDue => interest.totalOutstanding;
}

/// Consolidated outstanding dues for one flat (oldest-first).
class FlatOutstandingStatement {
  const FlatOutstandingStatement({
    required this.flatId,
    required this.lines,
    required this.asOf,
  });

  final int flatId;
  final List<OutstandingBillLine> lines;
  final DateTime asOf;

  int get billCount => lines.length;
  int get totalPrincipal => lines.fold<int>(0, (s, l) => s + l.principal);
  int get totalInterest => lines.fold<int>(0, (s, l) => s + l.lateInterest);
  int get totalPayable => lines.fold<int>(0, (s, l) => s + l.totalDue);
  String? get oldestPeriodStart =>
      lines.isEmpty ? null : lines.first.periodStart;
}
