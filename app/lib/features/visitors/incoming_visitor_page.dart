import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/auth/auth_session.dart';
import '../../api/models/visitor_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import '../parcels/live_parcels_module.dart';
import 'visitor_messages.dart';

/// Call-style resident screen for walk-in visitors waiting at the gate.
class IncomingVisitorPage extends StatefulWidget {
  const IncomingVisitorPage({super.key, required this.visitorId});

  final String visitorId;

  @override
  State<IncomingVisitorPage> createState() => _IncomingVisitorPageState();
}

class _IncomingVisitorPageState extends State<IncomingVisitorPage> {
  late Future<Visitor> _future = _load();
  bool _busy = false;
  Timer? _tick;

  Future<Visitor> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .residentVisitor(widget.visitorId, force: force);
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _future = _load(force: true));

  String _expiryLabel(Visitor v) {
    final raw = v.pendingExpiresAt;
    if (raw == null || raw.isEmpty) return 'Waiting for your response';
    final expires = DateTime.tryParse(raw)?.toLocal();
    if (expires == null) return 'Waiting for your response';
    final remaining = expires.difference(DateTime.now());
    if (remaining.isNegative || v.approvalStatus == 'EXPIRED') {
      return 'This request has expired. Keep the visitor outside.';
    }
    final seconds = remaining.inSeconds;
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return 'Respond within $mm:$ss';
  }

  bool _canAct(Visitor v) =>
      v.approvalStatus == 'PENDING' && v.entryStatus == 'NOT_ENTERED';

  Future<void> _approve(Visitor v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final updated =
          await ensureLiveRepositories(session.api).visitors.approve(v.id);
      if (!mounted) return;
      showSuccessSnack(
        context,
        v.isWalkIn
            ? '${updated.visitorName} approved. The guard must confirm actual entry.'
            : '${updated.visitorName} approved. Entry OTP sent by email.',
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deny(Visitor v) async {
    if (_busy) return;
    final reason = await promptTextDialog(
      context,
      title: 'Deny ${v.visitorName}?',
      message: 'The guard will be notified. The visitor stays outside.',
      label: 'Reason (optional)',
      confirmLabel: 'Deny',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.reject(
            v.id,
            reason: reason.isEmpty ? null : reason,
          );
      if (!mounted) return;
      showAppSnack(context, 'Visitor denied', tone: SnackTone.warning);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveParcel(Visitor v) async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'Leave a parcel?',
      message:
          'This authorizes parcel handover only. It does not allow ${v.visitorName} to enter.',
      confirmLabel: 'Authorize parcel',
      icon: Icons.inventory_2_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final result =
          await ensureLiveRepositories(session.api).visitors.leaveParcel(v.id);
      if (!mounted) return;
      showSuccessSnack(
        context,
        'Parcel handover authorized. The guard will accept the parcel at the gate.',
      );
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              LiveResidentParcelDetailPage(parcelId: result.parcel.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Visitor>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            backgroundColor: C.blueDark,
            appBar: AppBar(
              backgroundColor: C.blueDark,
              foregroundColor: Colors.white,
              title: const Text('Incoming visitor'),
            ),
            body: const LoadingView(label: 'Loading visitor…'),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Incoming visitor')),
            body: LoadFailure(error: snapshot.error!, onRetry: _reload),
          );
        }
        final v = snapshot.data!;
        final canAct = _canAct(v);
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.blueDark,
            foregroundColor: Colors.white,
            title: const Text('Incoming visitor'),
          ),
          body: Column(children: [
            Container(
              width: double.infinity,
              color: C.blueDark,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(children: [
                const AppAvatar(
                  icon: Icons.person_outline_rounded,
                  color: Colors.white,
                  size: 72,
                ),
                const SizedBox(height: 12),
                Text(
                  v.visitorName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${v.flatLabel} · ${visitorTypeLabel(v.visitorType)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Text(
                  _expiryLabel(v),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: canAct ? const Color(0xFFFFD56A) : Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: Sp.pagePadding,
                children: [
                  DetailCard(title: 'Visitor', children: [
                    DetailRow('Name', v.visitorName),
                    if (v.visitorPhone.trim().isNotEmpty)
                      DetailRow('Mobile', v.visitorPhone),
                    DetailRow('Type', visitorTypeLabel(v.visitorType)),
                    DetailRow('Purpose', v.purpose),
                    DetailRow('Flat', v.flatLabel),
                    DetailRow('Requested', fmtIsoDateTime(v.createdAt)),
                    if (v.pendingExpiresAt != null)
                      DetailRow(
                          'Expires', fmtIsoDateTime(v.pendingExpiresAt)),
                    if (v.requestState != null)
                      DetailRow(
                          'Status', requestStateLabel(v.requestState!)),
                  ]),
                  if (!canAct)
                    InfoNote(
                      v.approvalStatus == 'EXPIRED'
                          ? 'This request expired. The visitor must remain outside.'
                          : v.resolution == 'PARCEL'
                              ? 'Parcel handover was authorized. Visitor entry is not allowed.'
                              : 'This request is no longer waiting for a decision.',
                      tone: v.approvalStatus == 'APPROVED'
                          ? NoteTone.success
                          : NoteTone.warning,
                    ),
                ],
              ),
            ),
            if (canAct)
              BottomActionBar(children: [
                PrimaryButton(
                  label: 'Approve entry',
                  icon: Icons.check_rounded,
                  color: C.green,
                  busy: _busy,
                  onPressed: () => _approve(v),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  label: 'Deny',
                  icon: Icons.close_rounded,
                  destructive: true,
                  onPressed: _busy ? null : () => _deny(v),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  label: 'Leave parcel',
                  icon: Icons.inventory_2_outlined,
                  onPressed: _busy ? null : () => _leaveParcel(v),
                ),
              ]),
          ]),
        );
      },
    );
  }
}

String requestStateLabel(String state) {
  switch (state) {
    case 'PENDING':
      return 'Pending';
    case 'APPROVED':
      return 'Approved';
    case 'DENIED':
      return 'Denied';
    case 'EXPIRED':
      return 'Expired';
    case 'ENTRY_COMPLETED':
      return 'Entry completed';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return state;
  }
}
