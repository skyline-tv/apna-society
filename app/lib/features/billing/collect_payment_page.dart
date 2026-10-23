import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_core.dart';
import '../../services/late_interest.dart';
import '../../services/receipt_pdf.dart';
import '../../services/session_store.dart';
import '../../ui/components.dart';

/// Consolidated cash / cheque collection for every outstanding bill on a flat.
/// Oldest bills are settled first; newer bills cannot be paid alone.
class CollectPaymentPage extends StatefulWidget {
  const CollectPaymentPage({
    super.key,
    required this.flatId,
    this.seedBill,
    this.ownerMode = false,
  });

  final int flatId;
  final dynamic seedBill;
  final bool ownerMode;

  @override
  State<CollectPaymentPage> createState() => _CollectPaymentPageState();
}

class _CollectPaymentPageState extends State<CollectPaymentPage> {
  String method = 'Cash';
  DateTime paymentDate = DateTime.now();
  final amountCtrl = TextEditingController();
  final remarksCtrl = TextEditingController();
  final chequeNoCtrl = TextEditingController();
  bool saving = false;
  bool loading = true;
  String? error;
  FlatOutstandingStatement? statement;
  String? flatNumber;
  String? ownerName;
  String? building;

  @override
  void initState() {
    super.initState();
    if (widget.ownerMode) method = 'App (Demo)';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final flat = await db.flatById(widget.flatId);
      final stmt =
          await db.flatOutstandingStatement(widget.flatId, asOf: paymentDate);
      if (!mounted) return;
      setState(() {
        flatNumber = flat?.read<String>('flat_number');
        ownerName = flat?.read<String>('owner_name');
        building = flat?.read<String>('building');
        statement = stmt;
        amountCtrl.text = '${stmt.totalPayable}';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error =
            e is StateError ? e.message : 'Could not load outstanding bills.';
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    remarksCtrl.dispose();
    chequeNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => paymentDate = picked);
      await _load();
    }
  }

  Future<void> submit() async {
    final stmt = statement;
    if (stmt == null || stmt.lines.isEmpty) {
      setState(() => error = 'No outstanding bills for this flat.');
      return;
    }
    setState(() {
      error = null;
      saving = true;
    });
    try {
      final collected = int.tryParse(amountCtrl.text.trim());
      if (collected == null)
        throw StateError('Enter a valid amount collected.');
      if (collected != stmt.totalPayable) {
        throw StateError(
            'Amount collected must equal total outstanding (${money(stmt.totalPayable)}).');
      }

      String receipt;
      if (widget.ownerMode) {
        final session = await SessionStore.read();
        if (session == null || !session.isOwner) {
          throw StateError(
              'Only the flat owner can pay outstanding maintenance for this flat.');
        }
        receipt = await db.settleAllOutstandingForFlat(
          flatId: widget.flatId,
          method: 'App (Demo)',
          paymentDate: paymentDate,
          amountCollected: collected,
          adminId: null,
          adminName: 'Owner (app)',
          remarks:
              remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
          actorRole: session.role,
          actorMobile: session.mobile,
        );
      } else {
        final session = await SessionStore.read();
        if (session == null || !session.isAdmin || session.adminId == null) {
          throw StateError('Only an admin session can collect payments.');
        }
        final admin = await db.adminById(session.adminId!);
        final adminName = admin?.read<String>('name') ?? 'Society Admin';
        receipt = await db.settleAllOutstandingForFlat(
          flatId: widget.flatId,
          method: method,
          paymentDate: paymentDate,
          amountCollected: collected,
          adminId: session.adminId!,
          adminName: adminName,
          remarks:
              remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
          chequeNumber: method == 'Cheque' ? chequeNoCtrl.text : null,
        );
      }

      final batch = await db.paymentBatchByReceipt(receipt);
      final allocations = batch == null
          ? <dynamic>[]
          : await db.paymentsForBatch(batch.read<int>('id'));
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon:
              const Icon(Icons.check_circle_rounded, color: C.green, size: 52),
          title: Text(widget.ownerMode
              ? 'Bills settled'
              : (method == 'Cheque' ? 'Cheque recorded' : 'Cash collected')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(money(collected),
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900, color: C.navy)),
            const SizedBox(height: 8),
            Text(
              '${stmt.billCount} bill(s) · Principal ${money(stmt.totalPrincipal)}'
              '${stmt.totalInterest > 0 ? ' + Interest ${money(stmt.totalInterest)}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: C.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Receipt: $receipt',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (!widget.ownerMode && method == 'Cheque') ...[
              const SizedBox(height: 8),
              const Text('Status: Cheque Recorded (pending clearance)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: C.muted)),
            ],
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            if (batch != null && allocations.isNotEmpty)
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdf.shareBatch(
                    batch: Map<String, dynamic>.from(batch.data as Map),
                    allocations: allocations
                        .map((r) => Map<String, dynamic>.from(r.data as Map))
                        .toList(),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Share receipt'),
              ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() =>
          error = e is StateError ? e.message : 'Could not record payment.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stmt = statement;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ownerMode ? 'Pay outstanding bills' : 'Collect outstanding',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: loading
          ? const LoadingView(label: 'Loading outstanding bills…')
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                const InfoNote(
                  'Previous maintenance dues must be cleared in chronological order. '
                  'All unpaid bills for this flat are settled together — oldest first.',
                ),
                const SizedBox(height: 14),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        billDetailLine('Flat number', flatNumber ?? '—'),
                        billDetailLine('Owner name', ownerName ?? '—'),
                        if ((building ?? '').isNotEmpty)
                          billDetailLine('Building', building!),
                        if (stmt != null) ...[
                          billDetailLine(
                              'Outstanding bills', '${stmt.billCount}'),
                          if (stmt.oldestPeriodStart != null)
                            billDetailLine(
                              'Oldest unpaid period',
                              maintenancePeriodLabel(
                                startMonth: DateTime.tryParse(
                                        stmt.oldestPeriodStart!) ??
                                    DateTime.now(),
                                monthsCovered: stmt.lines.first.monthsCovered,
                                periodEnd: DateTime.tryParse(
                                    stmt.lines.first.periodEnd),
                              ),
                            ),
                          billDetailLine(
                              'Total principal', money(stmt.totalPrincipal)),
                          billDetailLine('Accumulated interest',
                              money(stmt.totalInterest)),
                          billDetailLine(
                              'Total payable', money(stmt.totalPayable)),
                        ],
                      ]),
                ),
                if (stmt != null && stmt.lines.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Bill-wise breakdown',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, color: C.navy)),
                  const SizedBox(height: 8),
                  ...stmt.lines.map((line) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.billNumber,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: C.navy)),
                                const SizedBox(height: 6),
                                billDetailLine(
                                  'Maintenance Period',
                                  maintenancePeriodLabel(
                                    startMonth:
                                        DateTime.tryParse(line.periodStart) ??
                                            DateTime.now(),
                                    monthsCovered: line.monthsCovered,
                                    periodEnd:
                                        DateTime.tryParse(line.periodEnd),
                                  ),
                                ),
                                billDetailLine(
                                    'Principal', money(line.principal)),
                                billDetailLine(
                                    'Late interest', money(line.lateInterest)),
                                billDetailLine(
                                    'Line total', money(line.totalDue)),
                                billDetailLine(
                                    'Status', line.status.toUpperCase()),
                              ]),
                        ),
                      )),
                ],
                if (stmt == null || stmt.lines.isEmpty) ...[
                  const SizedBox(height: 16),
                  const EmptyState('No outstanding bills for this flat.'),
                ] else ...[
                  if (!widget.ownerMode) ...[
                    const SizedBox(height: 8),
                    const Text('Payment method',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: C.navy)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      ChoiceChip(
                        label: const Text('Cash'),
                        selected: method == 'Cash',
                        onSelected: saving
                            ? null
                            : (_) => setState(() => method = 'Cash'),
                      ),
                      ChoiceChip(
                        label: const Text('Cheque'),
                        selected: method == 'Cheque',
                        onSelected: saving
                            ? null
                            : (_) => setState(() => method = 'Cheque'),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Payment date',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(shortDate(paymentDate.toIso8601String())),
                    trailing: const Icon(Icons.event_outlined, color: C.blue),
                    onTap: saving ? null : _pickPaymentDate,
                  ),
                  TextField(
                    controller: amountCtrl,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Amount collected (all outstanding bills)',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      helperText:
                          'Total outstanding is ${money(stmt.totalPayable)}. You can type the collected amount.',
                    ),
                  ),
                  if (!widget.ownerMode && method == 'Cheque') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: chequeNoCtrl,
                      enabled: !saving,
                      decoration: const InputDecoration(
                          labelText: 'Cheque number *',
                          prefixIcon: Icon(Icons.numbers)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: remarksCtrl,
                    enabled: !saving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Remarks (optional)',
                        prefixIcon: Icon(Icons.notes_outlined)),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: const TextStyle(
                          color: C.error, fontWeight: FontWeight.w600)),
                ],
                if (stmt != null && stmt.lines.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: C.blue,
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: saving ? null : submit,
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white))
                          : Text(
                              widget.ownerMode
                                  ? 'Pay Outstanding Bills'
                                  : (method == 'Cheque'
                                      ? 'Record Cheque · Pay Outstanding'
                                      : 'Collect Cash · Pay Outstanding'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
