import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/auth/app_role.dart';
import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/common.dart';
import '../../api/models/notification_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import '../announcements/live_announcements_module.dart';
import '../billing/live_billing_module.dart';
import '../complaints/live_complaints_module.dart';
import '../facilities/live_facilities_module.dart';
import '../visitors/live_visitors_module.dart';

String notificationErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'NOTIFICATION_ACCESS_DENIED':
        return 'You cannot view this notification.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this action.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'ANNOUNCEMENT':
      return Icons.campaign_outlined;
    case 'BILL_GENERATED':
      return Icons.receipt_long_outlined;
    case 'PAYMENT_SUCCESS':
      return Icons.check_circle_outline_rounded;
    case 'PAYMENT_FAILED':
      return Icons.error_outline_rounded;
    case 'VISITOR_REQUEST':
    case 'VISITOR_APPROVED':
    case 'VISITOR_REJECTED':
      return Icons.badge_outlined;
    case 'COMPLAINT_ASSIGNED':
    case 'COMPLAINT_STATUS_CHANGED':
      return Icons.report_problem_outlined;
    case 'FACILITY_BOOKING_APPROVED':
    case 'FACILITY_BOOKING_REJECTED':
    case 'FACILITY_BOOKING_CANCELLED':
      return Icons.event_available_outlined;
    case 'STAFF_SHIFT_ASSIGNED':
      return Icons.schedule_rounded;
    default:
      return Icons.notifications_outlined;
  }
}

Color _typeColor(String type) {
  switch (type) {
    case 'PAYMENT_SUCCESS':
    case 'VISITOR_APPROVED':
    case 'FACILITY_BOOKING_APPROVED':
      return C.green;
    case 'PAYMENT_FAILED':
    case 'VISITOR_REJECTED':
    case 'FACILITY_BOOKING_REJECTED':
      return C.error;
    case 'FACILITY_BOOKING_CANCELLED':
    case 'VISITOR_REQUEST':
      return C.amber;
    default:
      return C.blue;
  }
}

/// Human-friendly relative time for inbox rows (falls back to a date).
String _relative(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return fmtDate(d);
}

/// Resolves the screen a notification should open, or null when there is no
/// safe destination for the current role.
Widget? _linkedPage(AppNotification n) {
  final role = authSession?.appRole;
  final entityId = n.relatedEntityId;
  final isResident = role == AppRole.owner || role == AppRole.tenant;
  if (!isResident) return null;
  switch (n.type) {
    case 'ANNOUNCEMENT':
      return entityId == null
          ? null
          : LiveResidentAnnouncementDetailPage(announcementId: entityId);
    case 'VISITOR_REQUEST':
    case 'VISITOR_APPROVED':
    case 'VISITOR_REJECTED':
      return const LiveResidentVisitorsPage();
    case 'COMPLAINT_ASSIGNED':
    case 'COMPLAINT_STATUS_CHANGED':
      return entityId == null
          ? null
          : LiveResidentComplaintDetailPage(complaintId: entityId);
    case 'FACILITY_BOOKING_APPROVED':
    case 'FACILITY_BOOKING_REJECTED':
    case 'FACILITY_BOOKING_CANCELLED':
      return entityId == null
          ? null
          : LiveResidentBookingDetailPage(bookingId: entityId);
    case 'BILL_GENERATED':
      // Financial detail is owner-only in the UI; the backend remains
      // authoritative for access.
      if (role != AppRole.owner || entityId == null) return null;
      return LiveOwnerBillDetailPage(billId: entityId);
    default:
      // PAYMENT_*, STAFF_SHIFT_ASSIGNED, SYSTEM, unknown → detail only.
      return null;
  }
}

String _linkLabel(String type) {
  switch (type) {
    case 'ANNOUNCEMENT':
      return 'Open announcement';
    case 'VISITOR_REQUEST':
    case 'VISITOR_APPROVED':
    case 'VISITOR_REJECTED':
      return 'Open visitors';
    case 'COMPLAINT_ASSIGNED':
    case 'COMPLAINT_STATUS_CHANGED':
      return 'Open complaint';
    case 'FACILITY_BOOKING_APPROVED':
    case 'FACILITY_BOOKING_REJECTED':
    case 'FACILITY_BOOKING_CANCELLED':
      return 'Open booking';
    case 'BILL_GENERATED':
      return 'Open bill';
    default:
      return 'Open';
  }
}

/// App-bar bell for OWNER/TENANT (and optionally ADMIN) using live API.
class LiveNotificationBellButton extends StatefulWidget {
  const LiveNotificationBellButton({super.key, this.onPine = false});

  /// White icon + well for use on a [PineHeader].
  final bool onPine;

  @override
  State<LiveNotificationBellButton> createState() =>
      _LiveNotificationBellButtonState();
}

class _LiveNotificationBellButtonState
    extends State<LiveNotificationBellButton> {
  late Future<int> _unread = _load();
  StreamSubscription<NotificationEventPayload>? _sub;

  Future<int> _load() async {
    final session = authSession;
    if (session == null) return 0;
    final role = session.appRole;
    if (role != AppRole.owner && role != AppRole.tenant) return 0;
    try {
      final c = await ensureLiveRepositories(session.api)
          .notifications
          .unreadCount(force: true);
      return c.unreadCount;
    } catch (_) {
      return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.notificationEvents.listen((_) {
      if (mounted) setState(() => _unread = _load());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _unread,
      builder: (context, snap) {
        final count = snap.data ?? 0;
        final icon = Icon(
          count > 0
              ? Icons.notifications_active_outlined
              : Icons.notifications_outlined,
          color: widget.onPine ? Colors.white : C.navy,
        );
        final button = IconButton(
          tooltip: count > 0 ? '$count unread notifications' : 'Notifications',
          onPressed: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const LiveNotificationsInboxPage(),
              ),
            );
            if (mounted) setState(() => _unread = _load());
          },
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: icon,
          ),
        );
        if (!widget.onPine) return button;
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(Rd.lg),
          ),
          child: button,
        );
      },
    );
  }
}

class LiveNotificationsInboxPage extends StatefulWidget {
  const LiveNotificationsInboxPage({super.key});

  @override
  State<LiveNotificationsInboxPage> createState() =>
      _LiveNotificationsInboxPageState();
}

class _LiveNotificationsInboxPageState
    extends State<LiveNotificationsInboxPage> {
  bool? isReadFilter;
  late Future<Paged<AppNotification>> _future = _load();
  StreamSubscription<NotificationEventPayload>? _sub;
  bool _busy = false;

  Future<Paged<AppNotification>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).notifications.list(
          force: force,
          query: ListNotificationsQuery(isRead: isReadFilter, limit: 50),
        );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.notificationEvents.listen((_) {
      if (mounted) setState(() => _future = _load(force: true));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  Future<void> _markAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final result =
          await ensureLiveRepositories(session.api).notifications.markAllRead();
      if (mounted) {
        showSuccessSnack(
            context,
            result.updated == 0
                ? 'Everything is already read.'
                : 'Marked ${result.updated} notification${result.updated == 1 ? '' : 's'} as read.');
        reload();
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, notificationErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    try {
      final session = authSession!;
      if (!n.isRead) {
        await ensureLiveRepositories(session.api).notifications.markRead(n.id);
      }
    } catch (_) {}
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveNotificationDetailPage(notificationId: n.id),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _markAll,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('Mark all read'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<Paged<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 6);
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load notifications',
                onRetry: reload);
          }
          final items = snapshot.data!.items;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: Sp.pagePadding,
              children: [
                FilterBar(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final f in const [
                      (null, 'All'),
                      (false, 'Unread'),
                      (true, 'Read'),
                    ])
                      AppFilterChip(
                        label: f.$2,
                        selected: isReadFilter == f.$1,
                        onSelected: () => setState(() {
                          isReadFilter = f.$1;
                          _future = _load(force: true);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_busy) const LinearProgressIndicator(minHeight: 3),
                if (items.isEmpty)
                  EmptyState(
                    isReadFilter == false
                        ? 'You are all caught up'
                        : isReadFilter == true
                            ? 'No read notifications'
                            : 'No notifications yet',
                    icon: isReadFilter == false
                        ? Icons.task_alt_rounded
                        : Icons.notifications_none_rounded,
                    actionLabel: isReadFilter == null ? null : 'Show all',
                    onAction: () => setState(() {
                      isReadFilter = null;
                      _future = _load(force: true);
                    }),
                  )
                else
                  for (final n in items)
                    ListRow(
                      onTap: () => _open(n),
                      leading: AppAvatar(
                        icon: _typeIcon(n.type),
                        square: true,
                        color: n.isRead ? C.muted : _typeColor(n.type),
                      ),
                      title: n.title,
                      subtitle: n.body,
                      badges: [
                        if (!n.isRead)
                          const StatusBadge('New', tone: BadgeTone.info),
                        StatusBadge(notificationTypeLabel(n.type),
                            tone: BadgeTone.neutral),
                      ],
                      trailing: Text(_relative(n.createdAt), style: T.caption),
                      showChevron: false,
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LiveNotificationDetailPage extends StatefulWidget {
  const LiveNotificationDetailPage({super.key, required this.notificationId});
  final String notificationId;

  @override
  State<LiveNotificationDetailPage> createState() =>
      _LiveNotificationDetailPageState();
}

class _LiveNotificationDetailPageState
    extends State<LiveNotificationDetailPage> {
  late Future<AppNotification> _future = _load();

  Future<AppNotification> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .notifications
        .get(widget.notificationId, force: force);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification')),
      body: FutureBuilder<AppNotification>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading notification…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load notification',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final n = snapshot.data!;
          final linked = _linkedPage(n);
          return Column(children: [
            Expanded(
              child: ListView(
                padding: Sp.pagePadding,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AppAvatar(
                      icon: _typeIcon(n.type),
                      square: true,
                      size: Sz.avatarLg,
                      color: _typeColor(n.type),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title, style: T.h1),
                            const SizedBox(height: 3),
                            Text(
                              '${notificationTypeLabel(n.type)} · ${fmtIsoDateTime(n.createdAt)}',
                              style: T.secondary,
                            ),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    StatusBadge(n.isRead ? 'Read' : 'Unread',
                        tone: n.isRead ? BadgeTone.neutral : BadgeTone.info),
                    if (!n.isKnownType)
                      const StatusBadge('Unrecognised type',
                          tone: BadgeTone.warning),
                  ]),
                  const SizedBox(height: 18),
                  AppCard(
                    child: SelectableText(n.body,
                        style: T.body.copyWith(height: 1.55)),
                  ),
                  DetailCard(title: 'Details', children: [
                    DetailRow('Received', fmtIsoDateTime(n.createdAt)),
                    if (n.readAt != null)
                      DetailRow('Read', fmtIsoDateTime(n.readAt)),
                    if (n.relatedEntityType != null)
                      DetailRow('About', humanizeStatus(n.relatedEntityType!)),
                  ]),
                  if (!n.isKnownType)
                    const InfoNote(
                      'This notification type is not recognised by this version of the app, so only its text is shown.',
                      tone: NoteTone.warning,
                    ),
                ],
              ),
            ),
            if (linked != null)
              BottomActionBar(children: [
                PrimaryButton(
                  label: _linkLabel(n.type),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => linked),
                  ),
                ),
              ]),
          ]);
        },
      ),
    );
  }
}
