import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/announcement_models.dart';
import '../../api/models/common.dart';
import '../../api/models/notification_models.dart' show UnreadCount;
import '../../api/models/society_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import 'announcement_flat_picker.dart';

String announcementErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'ANNOUNCEMENT_NOT_EDITABLE':
        return 'Only draft announcements can be edited.';
      case 'INVALID_STATUS':
        return 'This status change is not allowed.';
      case 'INVALID_SCHEDULE':
        return 'Schedule time must be in the future.';
      case 'INVALID_EXPIRY':
        return 'Expiry must be after the scheduled time.';
      case 'ANNOUNCEMENT_EXPIRED':
        return 'Cannot publish an already expired announcement.';
      case 'ATTACHMENT_LIMIT':
        return 'Attachment limit reached (max $kAnnouncementAttachmentMaxCount).';
      case 'ATTACHMENT_TOO_LARGE':
        return 'File exceeds the 5 MB size limit.';
      case 'INVALID_ATTACHMENT_TYPE':
        return 'Only JPEG, PNG, WebP, GIF, or PDF files are allowed.';
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

bool _attachmentOk({
  required String mimeType,
  required int sizeBytes,
  required int existingCount,
}) {
  if (!kAnnouncementAttachmentMimeTypes.contains(mimeType)) return false;
  if (sizeBytes <= 0 || sizeBytes > kAnnouncementAttachmentMaxBytes) {
    return false;
  }
  if (existingCount >= kAnnouncementAttachmentMaxCount) return false;
  return true;
}

// ─── Resident feed ───────────────────────────────────────────────────────────

class LiveResidentAnnouncementsPage extends StatefulWidget {
  const LiveResidentAnnouncementsPage({super.key});

  @override
  State<LiveResidentAnnouncementsPage> createState() =>
      _LiveResidentAnnouncementsPageState();
}

class _LiveResidentAnnouncementsPageState
    extends State<LiveResidentAnnouncementsPage> {
  String? category;
  late Future<Paged<Announcement>> _future = _load();
  UnreadCount? _unread;
  StreamSubscription<AnnouncementEventPayload>? _sub;

  Future<Paged<Announcement>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    _unread = await repos.announcements.unreadCount(force: force);
    return repos.announcements.listResident(
      force: force,
      query: ListResidentAnnouncementsQuery(category: category, limit: 50),
    );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.announcementEvents.listen((_) {
      if (mounted) setState(() => _future = _load(force: true));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Announcement>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading announcements…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        final unread = _unread?.unreadCount ?? 0;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Announcements',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  if (unread > 0) StatusBadge('$unread unread'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: category == null,
                    onSelected: (_) {
                      setState(() {
                        category = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  for (final c in kAnnouncementCategories.take(6))
                    FilterChip(
                      label: Text(announcementCategoryLabel(c)),
                      selected: category == c,
                      onSelected: (_) {
                        setState(() {
                          category = c;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No announcements for you yet')
              else
                ...items.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveResidentAnnouncementDetailPage(
                              announcementId: a.id,
                            ),
                          ),
                        );
                        reload();
                      },
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  a.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: C.navy,
                                    fontSize: a.isRead == false ? 15 : 14,
                                  ),
                                ),
                              ),
                              if (a.isRead == false)
                                const StatusBadge('Unread'),
                            ],
                          ),
                          Text(
                            '${announcementCategoryLabel(a.category)} · '
                            '${_shortIso(a.publishedAt ?? a.createdAt)}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          StatusBadge(a.priority),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class LiveResidentAnnouncementDetailPage extends StatefulWidget {
  const LiveResidentAnnouncementDetailPage({
    super.key,
    required this.announcementId,
  });
  final String announcementId;

  @override
  State<LiveResidentAnnouncementDetailPage> createState() =>
      _LiveResidentAnnouncementDetailPageState();
}

class _LiveResidentAnnouncementDetailPageState
    extends State<LiveResidentAnnouncementDetailPage> {
  late Future<Announcement> _future = _load();
  bool _busy = false;

  Future<Announcement> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final a = await ensureLiveRepositories(session.api)
        .announcements
        .getResident(widget.announcementId, force: force);
    if (a.isRead != true) {
      try {
        await ensureLiveRepositories(session.api)
            .announcements
            .markRead(widget.announcementId);
      } catch (_) {}
      return ensureLiveRepositories(session.api)
          .announcements
          .getResident(widget.announcementId, force: true);
    }
    return a;
  }

  Future<void> _download(Announcement a, AnnouncementAttachment att) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final bytes = await ensureLiveRepositories(session.api)
          .announcements
          .downloadResidentAttachment(a.id, att.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(att.originalFilename),
          content: att.mimeType.startsWith('image/')
              ? Image.memory(Uint8List.fromList(bytes))
              : Text(
                  'Downloaded ${bytes.length} bytes (${att.mimeType}). '
                  'PDF preview is not embedded; open via share if needed.',
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _toast(context, announcementErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
      body: FutureBuilder<Announcement>(
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
          final a = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                a.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusBadge(announcementCategoryLabel(a.category)),
                  StatusBadge(a.priority),
                  if (a.isRead == true) const StatusBadge('Read'),
                ],
              ),
              const SizedBox(height: 12),
              Text(a.body, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 8),
              Text(
                'Published ${_shortIso(a.publishedAt)}',
                style: const TextStyle(color: C.muted, fontSize: 13),
              ),
              if (a.attachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionTitle('Attachments'),
                ...a.attachments.map(
                  (att) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.attach_file),
                    title: Text(att.originalFilename),
                    subtitle: Text('${att.mimeType} · ${att.sizeBytes} B'),
                    trailing: IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: _busy ? null : () => _download(a, att),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Admin ───────────────────────────────────────────────────────────────────

class LiveAdminAnnouncementsPage extends StatefulWidget {
  const LiveAdminAnnouncementsPage({super.key});

  @override
  State<LiveAdminAnnouncementsPage> createState() =>
      _LiveAdminAnnouncementsPageState();
}

class _LiveAdminAnnouncementsPageState
    extends State<LiveAdminAnnouncementsPage> {
  String? status;
  late Future<Paged<Announcement>> _future = _load();

  Future<Paged<Announcement>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).announcements.listAdmin(
          force: force,
          query: ListAdminAnnouncementsQuery(status: status, limit: 50),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Announcement>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading announcements…');
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Announcements',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveAnnouncementFormPage(),
                        ),
                      );
                      if (ok == true) reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Draft'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: status == null,
                    onSelected: (_) {
                      setState(() {
                        status = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  for (final s in kAnnouncementStatuses)
                    FilterChip(
                      label: Text(announcementStatusLabel(s)),
                      selected: status == s,
                      onSelected: (_) {
                        setState(() {
                          status = s;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No announcements')
              else
                ...items.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveAdminAnnouncementDetailPage(
                              announcementId: a.id,
                            ),
                          ),
                        );
                        reload();
                      },
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${audienceTypeLabel(a.audienceType)} · '
                            '${announcementCategoryLabel(a.category)}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(announcementStatusLabel(a.status)),
                              StatusBadge(a.priority),
                              if (a.eligibleRecipientCount != null)
                                StatusBadge(
                                  '${a.eligibleRecipientCount} recipients',
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
    );
  }
}

class LiveAdminAnnouncementDetailPage extends StatefulWidget {
  const LiveAdminAnnouncementDetailPage({
    super.key,
    required this.announcementId,
  });
  final String announcementId;

  @override
  State<LiveAdminAnnouncementDetailPage> createState() =>
      _LiveAdminAnnouncementDetailPageState();
}

class _LiveAdminAnnouncementDetailPageState
    extends State<LiveAdminAnnouncementDetailPage> {
  late Future<Announcement> _future = _load();
  AnnouncementRecipientSummary? _recipients;
  bool _busy = false;

  Future<Announcement> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final a = await repos.announcements
        .getAdmin(widget.announcementId, force: force);
    try {
      _recipients = await repos.announcements
          .recipients(widget.announcementId, force: force);
    } catch (_) {
      _recipients = null;
    }
    return a;
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        _toast(context, okMsg);
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) _toast(context, announcementErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(Announcement a) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? 'image/jpeg';
    if (!_attachmentOk(
      mimeType: mime,
      sizeBytes: bytes.length,
      existingCount: a.attachments.length,
    )) {
      if (mounted) {
        _toast(context, 'Invalid attachment (images under 5 MB)');
      }
      return;
    }
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).announcements.uploadAttachment(
            a.id,
            bytes: bytes,
            filename: file.name,
            mimeType: mime,
          );
    }, 'Attachment added');
  }

  Future<void> _schedule(Announcement a) async {
    final now = DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).announcements.schedule(
            a.id,
            scheduledAt: scheduled.toIso8601String(),
          );
    }, 'Scheduled');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
      body: FutureBuilder<Announcement>(
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
          final a = snapshot.data!;
          final r = _recipients;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                a.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusBadge(announcementStatusLabel(a.status)),
                  StatusBadge(audienceTypeLabel(a.audienceType)),
                  StatusBadge(a.priority),
                ],
              ),
              const SizedBox(height: 12),
              Text(a.body),
              if (a.adminNotes != null && a.adminNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Admin notes: ${a.adminNotes}',
                  style: const TextStyle(color: C.muted),
                ),
              ],
              const SizedBox(height: 8),
              Text('Delivery: ${a.deliveryState ?? '—'}'),
              if (a.scheduledAt != null)
                Text('Scheduled: ${_shortIso(a.scheduledAt)}'),
              if (a.publishedAt != null)
                Text('Published: ${_shortIso(a.publishedAt)}'),
              if (r != null) ...[
                const SizedBox(height: 12),
                const SectionTitle('Recipients / reads'),
                Text('Eligible: ${r.eligibleRecipientCount}'),
                Text('Notifications created: ${r.notificationCreatedCount}'),
                Text('Read count: ${r.readCount}'),
                if (r.note != null)
                  Text(
                    r.note!,
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
              ],
              if (a.attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                const SectionTitle('Attachments'),
                ...a.attachments.map(
                  (att) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(att.originalFilename),
                    subtitle: Text(att.mimeType),
                    trailing: a.status == 'DRAFT' || a.status == 'SCHEDULED'
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      final session = authSession!;
                                      await ensureLiveRepositories(session.api)
                                          .announcements
                                          .removeAttachment(a.id, att.id);
                                    }, 'Removed'),
                          )
                        : null,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (a.status == 'DRAFT') ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LiveAnnouncementFormPage(existing: a),
                            ),
                          );
                          if (ok == true && mounted) {
                            setState(() => _future = _load(force: true));
                          }
                        },
                  child: const Text('Edit draft'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _attach(a),
                  child: const Text('Add image attachment'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final session = authSession!;
                            await ensureLiveRepositories(session.api)
                                .announcements
                                .publish(a.id);
                          }, 'Published'),
                  child: const Text('Publish now'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _schedule(a),
                  child: const Text('Schedule'),
                ),
              ],
              if (a.status == 'SCHEDULED') ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final session = authSession!;
                            await ensureLiveRepositories(session.api)
                                .announcements
                                .publish(a.id);
                          }, 'Published'),
                  child: const Text('Publish now'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _schedule(a),
                  child: const Text('Reschedule'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _attach(a),
                  child: const Text('Add image attachment'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final session = authSession!;
                            await ensureLiveRepositories(session.api)
                                .announcements
                                .cancel(a.id);
                          }, 'Cancelled'),
                  child: const Text('Cancel scheduled'),
                ),
              ],
              if (a.status == 'PUBLISHED') ...[
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final session = authSession!;
                            await ensureLiveRepositories(session.api)
                                .announcements
                                .archive(a.id);
                          }, 'Archived'),
                  child: const Text('Archive'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class LiveAnnouncementFormPage extends StatefulWidget {
  const LiveAnnouncementFormPage({super.key, this.existing});
  final Announcement? existing;

  @override
  State<LiveAnnouncementFormPage> createState() =>
      _LiveAnnouncementFormPageState();
}

class _LiveAnnouncementFormPageState extends State<LiveAnnouncementFormPage> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _body = TextEditingController(text: widget.existing?.body);
  late final _notes = TextEditingController(text: widget.existing?.adminNotes);
  late final _flatSearch = TextEditingController();
  late String _category = widget.existing?.category ?? 'GENERAL';
  late String _priority = widget.existing?.priority ?? 'NORMAL';
  late String _audience = widget.existing?.audienceType ?? 'ALL_RESIDENTS';
  final _selectedWings = <String>{};
  late final _flatPicker = AnnouncementFlatPickerModel(
    initiallySelected: {...?widget.existing?.targetFlatIds},
  );
  List<WingSummary> _wings = const [];
  bool _submitting = false;
  bool _loadingWings = true;
  bool _loadingFlats = false;
  Object? _wingsError;
  Object? _flatsError;

  Set<String> get _selectedFlats => _flatPicker.selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedWings.addAll(widget.existing?.targetWingIds ?? const []);
    _loadWings();
    if (_audience == 'SELECTED_FLATS') {
      _loadAllFlats();
    }
  }

  Future<void> _loadWings() async {
    setState(() {
      _loadingWings = true;
      _wingsError = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final wings = await ensureLiveRepositories(session.api).society.wings();
      if (mounted) {
        setState(() {
          _wings = wings;
          _loadingWings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wingsError = e;
          _loadingWings = false;
        });
      }
    }
  }

  Future<void> _loadAllFlats({bool force = false}) async {
    setState(() {
      _loadingFlats = true;
      _flatsError = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final flats = await ensureLiveRepositories(session.api).society.listAllFlats(
            force: force,
          );
      if (mounted) {
        setState(() {
          _flatPicker.replaceFlats(flats);
          _loadingFlats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _flatsError = e;
          _loadingFlats = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _notes.dispose();
    _flatSearch.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.length < 3 || body.length < 3) {
      _toast(context, 'Title and body must be at least 3 characters');
      return;
    }
    if (_audience == 'WING' && _selectedWings.isEmpty) {
      _toast(context, 'Select at least one wing');
      return;
    }
    if (_audience == 'SELECTED_FLATS' && _selectedFlats.isEmpty) {
      _toast(context, 'Select at least one flat');
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repo = ensureLiveRepositories(session.api).announcements;
      if (widget.existing == null) {
        await repo.create(
          CreateAnnouncementRequest(
            title: title,
            body: body,
            category: _category,
            priority: _priority,
            audienceType: _audience,
            targetWingIds:
                _audience == 'WING' ? _selectedWings.toList() : null,
            targetFlatIds: _audience == 'SELECTED_FLATS'
                ? _selectedFlats.toList()
                : null,
            adminNotes:
                _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ),
        );
      } else {
        await repo.update(
          widget.existing!.id,
          UpdateAnnouncementRequest(
            title: title,
            body: body,
            category: _category,
            priority: _priority,
            audienceType: _audience,
            targetWingIds:
                _audience == 'WING' ? _selectedWings.toList() : const [],
            targetFlatIds: _audience == 'SELECTED_FLATS'
                ? _selectedFlats.toList()
                : const [],
            adminNotes:
                _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _toast(context, announcementErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit draft' : 'New draft'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _body,
            decoration: const InputDecoration(labelText: 'Body'),
            maxLines: 6,
          ),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in kAnnouncementCategories)
                DropdownMenuItem(
                  value: c,
                  child: Text(announcementCategoryLabel(c)),
                ),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          DropdownButtonFormField<String>(
            value: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: [
              for (final p in kAnnouncementPriorities)
                DropdownMenuItem(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => _priority = v ?? _priority),
          ),
          DropdownButtonFormField<String>(
            value: _audience,
            decoration: const InputDecoration(labelText: 'Audience'),
            items: [
              for (final a in kAudienceTypes)
                DropdownMenuItem(
                  value: a,
                  child: Text(audienceTypeLabel(a)),
                ),
            ],
            onChanged: (v) {
              final next = v ?? _audience;
              setState(() => _audience = next);
              if (next == 'SELECTED_FLATS' &&
                  _flatPicker.allFlats.isEmpty &&
                  !_loadingFlats) {
                _loadAllFlats();
              }
            },
          ),
          if (_audience == 'WING') ...[
            const SizedBox(height: 8),
            const Text('Wings', style: TextStyle(fontWeight: FontWeight.w700)),
            if (_loadingWings)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_wingsError != null)
              LoadFailure(error: _wingsError!, onRetry: _loadWings)
            else if (_wings.isEmpty)
              const EmptyState('No wings found for this society')
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final w in _wings)
                    FilterChip(
                      label: Text(w.name),
                      selected: _selectedWings.contains(w.id),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _selectedWings.add(w.id);
                          } else {
                            _selectedWings.remove(w.id);
                          }
                        });
                      },
                    ),
                ],
              ),
          ] else if (_audience == 'SELECTED_FLATS') ...[
            const SizedBox(height: 8),
            Text(
              'Flats (${_selectedFlats.length} selected'
              '${_flatPicker.allFlats.isEmpty ? '' : ' · ${_flatPicker.allFlats.length} in society'})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_loadingFlats)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_flatsError != null)
              LoadFailure(
                error: _flatsError!,
                onRetry: () => _loadAllFlats(force: true),
              )
            else if (_flatPicker.allFlats.isEmpty)
              const EmptyState('No flats found for this society')
            else ...[
              TextField(
                controller: _flatSearch,
                decoration: const InputDecoration(
                  labelText: 'Search flats',
                  hintText: 'Wing or flat number',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) {
                  setState(() => _flatPicker.setSearch(v));
                },
              ),
              const SizedBox(height: 8),
              if (_flatPicker.pageItems.isEmpty)
                const EmptyState('No flats match this search')
              else
                ..._flatPicker.pageItems.map(
                  (f) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _flatPicker.isSelected(f.id),
                    title: Text(announcementFlatLabel(f)),
                    subtitle: Text('Floor ${f.floor}'),
                    onChanged: (sel) {
                      setState(() {
                        _flatPicker.setSelected(f.id, sel ?? false);
                      });
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Page ${_flatPicker.page} of ${_flatPicker.totalPages}'
                    ' · ${_flatPicker.totalFiltered} shown',
                    style: const TextStyle(color: C.muted, fontSize: 13),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _flatPicker.page <= 1
                        ? null
                        : () => setState(
                              () => _flatPicker.goToPage(_flatPicker.page - 1),
                            ),
                    child: const Text('Prev'),
                  ),
                  TextButton(
                    onPressed: _flatPicker.page >= _flatPicker.totalPages
                        ? null
                        : () => setState(
                              () => _flatPicker.goToPage(_flatPicker.page + 1),
                            ),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ],
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Admin notes (not shown to residents)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Save draft'),
          ),
        ],
      ),
    );
  }
}
