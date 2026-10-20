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

String _shortIso(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day}/${d.month}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// App-bar bell for OWNER/TENANT (and optionally ADMIN) using live API.
class LiveNotificationBellButton extends StatefulWidget {
  const LiveNotificationBellButton({super.key});

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
        return IconButton(
          tooltip: 'Notifications',
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
            label: Text('$count'),
            child: const Icon(Icons.notifications_outlined),
          ),
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

  Future<void> _markAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final result =
          await ensureLiveRepositories(session.api).notifications.markAllRead();
      if (mounted) {
        _toast(context, 'Marked ${result.updated} read');
        reload();
      }
    } catch (e) {
      if (mounted) _toast(context, notificationErrorMessage(e));
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
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _markAll,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: FutureBuilder<Paged<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading notifications…');
          }
          if (snapshot.hasError) {
            return LoadFailure(error: snapshot.error!, onRetry: reload);
          }
          final items = snapshot.data!.items;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: isReadFilter == null,
                      onSelected: (_) {
                        setState(() {
                          isReadFilter = null;
                          _future = _load(force: true);
                        });
                      },
                    ),
                    FilterChip(
                      label: const Text('Unread'),
                      selected: isReadFilter == false,
                      onSelected: (_) {
                        setState(() {
                          isReadFilter = false;
                          _future = _load(force: true);
                        });
                      },
                    ),
                    FilterChip(
                      label: const Text('Read'),
                      selected: isReadFilter == true,
                      onSelected: (_) {
                        setState(() {
                          isReadFilter = true;
                          _future = _load(force: true);
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const EmptyState('No notifications yet')
                else
                  ...items.map(
                    (n) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        onTap: () => _open(n),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    n.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: C.navy,
                                      fontSize: n.isRead ? 14 : 15,
                                    ),
                                  ),
                                ),
                                if (!n.isRead) const StatusBadge('new'),
                              ],
                            ),
                            Text(
                              n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: C.muted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                StatusBadge(notificationTypeLabel(n.type)),
                                Text(
                                  _shortIso(n.createdAt),
                                  style: const TextStyle(
                                    color: C.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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

  Future<void> _navigate(AppNotification n) async {
    final session = authSession;
    final role = session?.appRole;
    final entityId = n.relatedEntityId;
    final type = n.type;

    Widget? page;
    final isResident = role == AppRole.owner || role == AppRole.tenant;
    if (type == 'ANNOUNCEMENT' && entityId != null && isResident) {
      page = LiveResidentAnnouncementDetailPage(announcementId: entityId);
    } else if (type == 'VISITOR_REQUEST' ||
        type == 'VISITOR_APPROVED' ||
        type == 'VISITOR_REJECTED') {
      if (isResident) page = const LiveResidentVisitorsPage();
    } else if (type == 'COMPLAINT_ASSIGNED' ||
        type == 'COMPLAINT_STATUS_CHANGED') {
      if (entityId != null && isResident) {
        page = LiveResidentComplaintDetailPage(complaintId: entityId);
      }
    } else if (type == 'FACILITY_BOOKING_APPROVED' ||
        type == 'FACILITY_BOOKING_REJECTED' ||
        type == 'FACILITY_BOOKING_CANCELLED') {
      if (entityId != null && isResident) {
        page = LiveResidentBookingDetailPage(bookingId: entityId);
      }
    }
    // BILL_*, STAFF_SHIFT_ASSIGNED, SYSTEM, unknown → generic detail only.

    if (page == null) {
      if (mounted) {
        _toast(
          context,
          'No linked screen for this notification type.',
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
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
            return const LoadingView(label: 'Loading…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final n = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                n.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusBadge(notificationTypeLabel(n.type)),
                  StatusBadge(n.isRead ? 'Read' : 'Unread'),
                  if (!n.isKnownType) const StatusBadge('Unknown type'),
                ],
              ),
              const SizedBox(height: 12),
              Text(n.body, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 12),
              Text(
                'Received ${_shortIso(n.createdAt)}',
                style: const TextStyle(color: C.muted, fontSize: 13),
              ),
              if (n.relatedEntityType != null)
                Text(
                  'Related: ${n.relatedEntityType}'
                  '${n.relatedEntityId != null ? ' · ${n.relatedEntityId}' : ''}',
                  style: const TextStyle(color: C.muted, fontSize: 13),
                ),
              const SizedBox(height: 20),
              if (n.isKnownType)
                FilledButton(
                  onPressed: () => _navigate(n),
                  child: const Text('Open related'),
                )
              else
                const InfoNote(
                  'This notification type is not mapped. Showing safe detail only.',
                ),
            ],
          );
        },
      ),
    );
  }
}
