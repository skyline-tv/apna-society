import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/models/visitor_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../services/incoming_visitor_call.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
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
  StreamSubscription<VisitorEventPayload>? _sub;
  bool _busy = false;
  Timer? _tick;

  Future<Visitor> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final visitor = await ensureLiveRepositories(session.api)
        .visitors
        .residentVisitor(widget.visitorId, force: force);
    if (visitor.approvalStatus != 'PENDING') {
      unawaited(
        IncomingVisitorCallCoordinator.instance.stopIncoming(visitor.id),
      );
    }
    return visitor;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _sub = VisitorSocket.instance.events.listen((event) {
      if (event.visitorId != widget.visitorId) return;
      if (!mounted) return;
      setState(() => _future = _load(force: true));
      if (event.approvalStatus == 'APPROVED' ||
          event.approvalStatus == 'REJECTED' ||
          event.approvalStatus == 'EXPIRED') {
        unawaited(
          IncomingVisitorCallCoordinator.instance.stopIncoming(widget.visitorId),
        );
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    IncomingVisitorCallCoordinator.instance.noteClosed(widget.visitorId);
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
      return 'No response. The request stays pending for later review.';
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
      await IncomingVisitorCallCoordinator.instance.stopIncoming(v.id);
      if (!mounted) return;
      showSuccessSnack(
        context,
        '${updated.visitorName} approved. The guard must confirm they entered.',
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

  Future<void> _reject(Visitor v) async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'Reject ${v.visitorName}?',
      message: 'The guard will be told immediately. The visitor stays outside.',
      confirmLabel: 'REJECT',
      destructive: true,
      icon: Icons.close_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.reject(v.id);
      await IncomingVisitorCallCoordinator.instance.stopIncoming(v.id);
      if (!mounted) return;
      showAppSnack(context, 'Visitor rejected', tone: SnackTone.warning);
      _reload();
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: FutureBuilder<Visitor>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Scaffold(
              backgroundColor: Color(0xFF102033),
              body: LoadingView(label: 'Visitor at the gate…'),
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
            backgroundColor: const Color(0xFF102033),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pad = constraints.maxWidth < 360 ? 16.0 : 24.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(pad, 20, pad, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 44).clamp(0, 4000),
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            const Text(
                              'VISITOR AT MAIN GATE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 28),
                            const CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.white24,
                              child: Icon(
                                Icons.person_rounded,
                                size: 56,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              v.visitorName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Flat ${v.flatLabel}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              v.purpose,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _expiryLabel(v),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: canAct
                                    ? const Color(0xFFFFD56A)
                                    : Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            if (!canAct) ...[
                              const SizedBox(height: 16),
                              Text(
                                v.approvalStatus == 'APPROVED'
                                    ? 'Approved. The guard must confirm they entered.'
                                    : v.approvalStatus == 'REJECTED'
                                        ? 'Rejected. The visitor stays outside.'
                                        : v.approvalStatus == 'EXPIRED'
                                            ? 'No one answered. Review this request from Visitors if needed.'
                                            : 'This request is no longer waiting.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (canAct) ...[
                              SizedBox(
                                width: double.infinity,
                                height: 64,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: C.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _busy ? null : () => _approve(v),
                                  child: Text(
                                    _busy ? 'Please wait…' : 'APPROVE',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 64,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                        color: Colors.white70, width: 2),
                                  ),
                                  onPressed: _busy ? null : () => _reject(v),
                                  child: const Text(
                                    'REJECT',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white54),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
