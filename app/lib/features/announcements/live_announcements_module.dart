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

String _fileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

String _priorityLabel(String p) => humanizeStatus(p);

BadgeTone _priorityTone(String p) {
  switch (p.toUpperCase()) {
    case 'URGENT':
      return BadgeTone.danger;
    case 'IMPORTANT':
      return BadgeTone.warning;
    default:
      return BadgeTone.neutral;
  }
}

BadgeTone _statusTone(String s) {
  switch (s.toUpperCase()) {
    case 'PUBLISHED':
      return BadgeTone.success;
    case 'SCHEDULED':
      return BadgeTone.info;
    case 'DRAFT':
      return BadgeTone.warning;
    case 'ARCHIVED':
    case 'CANCELLED':
      return BadgeTone.neutral;
    default:
      return BadgeTone.neutral;
  }
}

IconData _categoryIcon(String category) {
  switch (category.toUpperCase()) {
    case 'MAINTENANCE':
      return Icons.build_outlined;
    case 'WATER_SUPPLY':
      return Icons.water_drop_outlined;
    case 'ELECTRICITY':
      return Icons.bolt_outlined;
    case 'SECURITY':
      return Icons.shield_outlined;
    case 'EVENT':
      return Icons.celebration_outlined;
    case 'EMERGENCY':
      return Icons.warning_amber_rounded;
    case 'MEETING':
      return Icons.groups_outlined;
    case 'PARKING':
      return Icons.local_parking_outlined;
    default:
      return Icons.campaign_outlined;
  }
}

IconData _mimeIcon(String mime) => mime == 'application/pdf'
    ? Icons.picture_as_pdf_outlined
    : Icons.image_outlined;

class _AnnouncementRow extends StatelessWidget {
  const _AnnouncementRow({
    required this.announcement,
    required this.onTap,
    this.admin = false,
  });
  final Announcement announcement;
  final VoidCallback onTap;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final unread = !admin && a.isRead == false;
    final urgent = a.priority.toUpperCase() == 'URGENT';
    return ListRow(
      onTap: onTap,
      unread: unread,
      leading: AppAvatar(
        icon: _categoryIcon(a.category),
        square: true,
        color: urgent ? C.error : (unread ? C.blue : C.muted),
      ),
      title: a.title,
      subtitle: admin
          ? '${audienceTypeLabel(a.audienceType)} · ${announcementCategoryLabel(a.category)}\n'
              '${a.publishedAt != null ? 'Published ${fmtIsoDateTime(a.publishedAt)}' : a.scheduledAt != null ? 'Scheduled ${fmtIsoDateTime(a.scheduledAt)}' : 'Updated ${fmtIsoDateTime(a.updatedAt)}'}'
          : '${announcementCategoryLabel(a.category)} · ${fmtIsoDateTime(a.publishedAt ?? a.createdAt)}',
      badges: [
        if (admin)
          StatusBadge(announcementStatusLabel(a.status),
              tone: _statusTone(a.status)),
        if (a.priority.toUpperCase() != 'NORMAL')
          StatusBadge(_priorityLabel(a.priority),
              tone: _priorityTone(a.priority),
              icon: Icons.priority_high_rounded),
        if (unread) const StatusBadge('New', tone: BadgeTone.info),
        if (a.attachments.isNotEmpty)
          StatusBadge(
              '${a.attachments.length} file${a.attachments.length == 1 ? '' : 's'}',
              tone: BadgeTone.neutral,
              icon: Icons.attach_file_rounded),
        if (admin && a.eligibleRecipientCount != null)
          StatusBadge('${a.eligibleRecipientCount} recipients',
              tone: BadgeTone.neutral, icon: Icons.people_outline_rounded),
      ],
    );
  }
}

Future<void> _previewAttachment(
  BuildContext context,
  AnnouncementAttachment att,
  List<int> bytes,
) {
  final isImage = att.mimeType.startsWith('image/');
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(att.originalFilename,
                    style: T.title, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          if (isImage)
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(Uint8List.fromList(bytes),
                    fit: BoxFit.contain),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(children: [
                const Icon(Icons.picture_as_pdf_outlined,
                    size: 48, color: C.error),
                const SizedBox(height: 10),
                Text('PDF · ${_fileSize(bytes.length)}', style: T.bodyStrong),
                const SizedBox(height: 4),
                const Text(
                  'Downloaded successfully. In-app PDF preview is not available; the file is kept by the society office.',
                  textAlign: TextAlign.center,
                  style: T.secondary,
                ),
              ]),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
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

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Announcement>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snapshot.hasError) {
          return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load announcements',
              onRetry: reload);
        }
        final items = snapshot.data!.items;
        final unread = _unread?.unreadCount ?? 0;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: Sp.pagePadding,
            children: [
              PageHeader(
                'Announcements',
                subtitle: unread > 0
                    ? '$unread unread'
                    : 'Notices from the society office',
                trailing: unread > 0
                    ? StatusBadge('$unread new', tone: BadgeTone.info)
                    : null,
              ),
              FilterBar(
                padding: EdgeInsets.zero,
                children: [
                  AppFilterChip(
                    label: 'All',
                    selected: category == null,
                    onSelected: () => setState(() {
                      category = null;
                      _future = _load(force: true);
                    }),
                  ),
                  for (final c in kAnnouncementCategories)
                    AppFilterChip(
                      label: announcementCategoryLabel(c),
                      icon: _categoryIcon(c),
                      selected: category == c,
                      onSelected: () => setState(() {
                        category = c;
                        _future = _load(force: true);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                EmptyState(
                  category == null
                      ? 'No announcements for you yet'
                      : 'No ${announcementCategoryLabel(category!).toLowerCase()} announcements',
                  icon: Icons.campaign_outlined,
                  actionLabel: category == null ? null : 'Show all',
                  onAction: () => setState(() {
                    category = null;
                    _future = _load(force: true);
                  }),
                )
              else
                for (final a in items)
                  _AnnouncementRow(
                    announcement: a,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveResidentAnnouncementDetailPage(
                            announcementId: a.id,
                          ),
                        ),
                      );
                      if (mounted) reload();
                    },
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
  String? _busyAttachment;

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
    if (_busyAttachment != null) return;
    setState(() => _busyAttachment = att.id);
    try {
      final session = authSession!;
      final bytes = await ensureLiveRepositories(session.api)
          .announcements
          .downloadResidentAttachment(a.id, att.id);
      if (!mounted) return;
      await _previewAttachment(context, att, bytes);
    } catch (e) {
      if (mounted) showErrorSnack(context, announcementErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busyAttachment = null);
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
            return const LoadingView(label: 'Loading announcement…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load announcement',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final a = snapshot.data!;
          final urgent = a.priority.toUpperCase() == 'URGENT';
          return ListView(
            padding: Sp.pagePadding,
            children: [
              DetailHero(
                title: a.title,
                subtitle:
                    '${announcementCategoryLabel(a.category)} · ${fmtIsoDateTime(a.publishedAt ?? a.createdAt)}',
                leading: AppAvatar(
                  icon: _categoryIcon(a.category),
                  square: true,
                  size: Sz.avatarLg,
                  color: urgent ? C.error : C.blue,
                ),
                badges: [
                  if (a.priority.toUpperCase() != 'NORMAL')
                    StatusBadge(_priorityLabel(a.priority),
                        tone: _priorityTone(a.priority),
                        icon: Icons.priority_high_rounded),
                  if (a.expiresAt != null)
                    StatusBadge('Valid till ${fmtIsoDate(a.expiresAt)}',
                        tone: BadgeTone.neutral, icon: Icons.event_outlined),
                ],
              ),
              const SizedBox(height: 18),
              const SectionTitle('Message'),
              DetailCard(
                title: null,
                children: [
                  SelectableText(a.body,
                      style: T.body.copyWith(height: 1.55, color: C.navy)),
                ],
              ),
              if (a.attachments.isNotEmpty) ...[
                const SizedBox(height: 14),
                SectionTitle('Attachments',
                    subtitle:
                        '${a.attachments.length} file${a.attachments.length == 1 ? '' : 's'} · tap to open'),
                AppCard(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < a.attachments.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 56, endIndent: 12),
                      ListRow(
                        dense: true,
                        leading: AppAvatar(
                            icon: _mimeIcon(a.attachments[i].mimeType),
                            square: true,
                            size: 36,
                            color:
                                a.attachments[i].mimeType == 'application/pdf'
                                    ? C.error
                                    : C.blue),
                        title: a.attachments[i].originalFilename,
                        subtitle: _fileSize(a.attachments[i].sizeBytes),
                        showChevron: false,
                        trailing: _busyAttachment == a.attachments[i].id
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.2))
                            : const Icon(Icons.open_in_full_rounded,
                                size: 18, color: C.muted),
                        onTap: _busyAttachment != null
                            ? null
                            : () => _download(a, a.attachments[i]),
                      ),
                    ],
                  ]),
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

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  Future<void> _create() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveAnnouncementFormPage()),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Draft saved. Publish it when ready.');
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-announcement',
        onPressed: _create,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New draft'),
      ),
      body: FutureBuilder<Paged<Announcement>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 5, showHeader: true);
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load announcements',
                onRetry: reload);
          }
          final items = snapshot.data!.items;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              children: [
                const PageHeader('Announcements',
                    subtitle: 'Draft, schedule and publish notices'),
                FilterBar(
                  padding: EdgeInsets.zero,
                  children: [
                    AppFilterChip(
                      label: 'All',
                      selected: status == null,
                      onSelected: () => setState(() {
                        status = null;
                        _future = _load(force: true);
                      }),
                    ),
                    for (final s in kAnnouncementStatuses)
                      AppFilterChip(
                        label: announcementStatusLabel(s),
                        selected: status == s,
                        onSelected: () => setState(() {
                          status = s;
                          _future = _load(force: true);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  EmptyState(
                    status == null
                        ? 'No announcements yet'
                        : 'No ${announcementStatusLabel(status!).toLowerCase()} announcements',
                    icon: Icons.campaign_outlined,
                    actionLabel:
                        status == null ? 'Write the first one' : 'Show all',
                    onAction: status == null
                        ? _create
                        : () => setState(() {
                              status = null;
                              _future = _load(force: true);
                            }),
                  )
                else ...[
                  ResultCount(snapshot.data!.pagination.total, 'announcement'),
                  for (final a in items)
                    _AnnouncementRow(
                      announcement: a,
                      admin: true,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveAdminAnnouncementDetailPage(
                              announcementId: a.id,
                            ),
                          ),
                        );
                        if (mounted) reload();
                      },
                    ),
                ],
              ],
            ),
          );
        },
      ),
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
    final a =
        await repos.announcements.getAdmin(widget.announcementId, force: force);
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
        showSuccessSnack(context, okMsg);
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, announcementErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(Announcement a) async {
    if (a.attachments.length >= kAnnouncementAttachmentMaxCount) {
      showWarningSnack(context,
          'Attachment limit reached (max $kAnnouncementAttachmentMaxCount).');
      return;
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? 'image/jpeg';
    if (!_attachmentOk(
      mimeType: mime,
      sizeBytes: bytes.length,
      existingCount: a.attachments.length,
    )) {
      if (mounted) {
        showErrorSnack(context, 'Invalid attachment. Use an image under 5 MB.');
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
    }, 'Attachment added.');
  }

  Future<void> _removeAttachment(
      Announcement a, AnnouncementAttachment att) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove attachment?',
      message: att.originalFilename,
      confirmLabel: 'Remove',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .announcements
          .removeAttachment(a.id, att.id);
    }, 'Attachment removed.');
  }

  Future<void> _publish(Announcement a) async {
    final ok = await confirmDialog(
      context,
      title: 'Publish now?',
      message:
          'This sends "${a.title}" to ${audienceTypeLabel(a.audienceType).toLowerCase()}'
          '${a.eligibleRecipientCount != null ? ' (${a.eligibleRecipientCount} recipients)' : ''}. '
          'Published announcements cannot be edited.',
      confirmLabel: 'Publish',
      icon: Icons.send_rounded,
    );
    if (!ok) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).announcements.publish(a.id);
    }, 'Announcement published.');
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
    final local =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!local.isAfter(DateTime.now())) {
      showWarningSnack(context, 'Schedule time must be in the future.');
      return;
    }
    final scheduled = local.toUtc();
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).announcements.schedule(
            a.id,
            scheduledAt: scheduled.toIso8601String(),
          );
    }, 'Scheduled for ${fmtDateTime(local)}.');
  }

  Future<void> _cancelScheduled(Announcement a) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel scheduled announcement?',
      message: 'It will not be sent. The announcement is marked cancelled.',
      confirmLabel: 'Cancel it',
      cancelLabel: 'Keep schedule',
      destructive: true,
      icon: Icons.event_busy_outlined,
    );
    if (!ok) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).announcements.cancel(a.id);
    }, 'Scheduled announcement cancelled.');
  }

  Future<void> _archive(Announcement a) async {
    final ok = await confirmDialog(
      context,
      title: 'Archive announcement?',
      message: 'Residents will no longer see it in their feed.',
      confirmLabel: 'Archive',
      icon: Icons.archive_outlined,
    );
    if (!ok) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).announcements.archive(a.id);
    }, 'Announcement archived.');
  }

  Future<void> _edit(Announcement a) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LiveAnnouncementFormPage(existing: a)),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Draft updated.');
      setState(() => _future = _load(force: true));
    }
  }

  List<ToolLink> _secondaryActions(Announcement a) {
    final links = <ToolLink>[];
    final editable = a.status == 'DRAFT' || a.status == 'SCHEDULED';
    if (a.status == 'DRAFT') {
      links.add(ToolLink(
        icon: Icons.edit_outlined,
        label: 'Edit draft',
        subtitle: 'Title, body, audience and priority',
        onTap: () => _edit(a),
      ));
    }
    if (a.status == 'DRAFT' || a.status == 'SCHEDULED') {
      links.add(ToolLink(
        icon: Icons.schedule_send_outlined,
        label: a.status == 'SCHEDULED' ? 'Reschedule' : 'Schedule',
        subtitle: a.status == 'SCHEDULED'
            ? 'Currently ${fmtIsoDateTime(a.scheduledAt)}'
            : 'Pick a date and time to publish automatically',
        onTap: () => _schedule(a),
      ));
    }
    if (editable && a.attachments.length < kAnnouncementAttachmentMaxCount) {
      links.add(ToolLink(
        icon: Icons.add_photo_alternate_outlined,
        label: 'Add image',
        subtitle:
            '${a.attachments.length} of $kAnnouncementAttachmentMaxCount attached',
        onTap: () => _attach(a),
      ));
    }
    if (a.status == 'SCHEDULED') {
      links.add(ToolLink(
        icon: Icons.event_busy_outlined,
        label: 'Cancel schedule',
        subtitle: 'Do not send this announcement',
        onTap: () => _cancelScheduled(a),
      ));
    }
    if (a.status == 'PUBLISHED') {
      links.add(ToolLink(
        icon: Icons.archive_outlined,
        label: 'Archive',
        subtitle: 'Remove from resident feeds',
        onTap: () => _archive(a),
      ));
    }
    return links;
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
            return const LoadingView(label: 'Loading announcement…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load announcement',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final a = snapshot.data!;
          final r = _recipients;
          final secondary = _secondaryActions(a);
          final canPublish = a.status == 'DRAFT' || a.status == 'SCHEDULED';
          final editable = a.status == 'DRAFT' || a.status == 'SCHEDULED';
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                DetailHero(
                  title: a.title,
                  subtitle:
                      '${announcementCategoryLabel(a.category)} · ${audienceTypeLabel(a.audienceType)}',
                  leading: AppAvatar(
                    icon: _categoryIcon(a.category),
                    square: true,
                    size: Sz.avatarLg,
                    color: badgeColors(_statusTone(a.status)).fg,
                  ),
                  badges: [
                    StatusBadge(announcementStatusLabel(a.status),
                        tone: _statusTone(a.status)),
                    StatusBadge(_priorityLabel(a.priority),
                        tone: _priorityTone(a.priority),
                        icon: Icons.priority_high_rounded),
                  ],
                ),
                const SizedBox(height: 18),
                if (a.status == 'DRAFT')
                  const InfoNote(
                    'This is a draft. Residents cannot see it until you publish or schedule it.',
                    tone: NoteTone.warning,
                    icon: Icons.edit_note_rounded,
                  ),
                if (a.status == 'SCHEDULED')
                  InfoNote(
                    'Scheduled to publish on ${fmtIsoDateTime(a.scheduledAt)}.',
                    icon: Icons.schedule_rounded,
                  ),
                const SectionTitle('Message'),
                DetailCard(
                  children: [
                    SelectableText(a.body,
                        style: T.body.copyWith(height: 1.55, color: C.navy)),
                  ],
                ),
                if (a.adminNotes != null &&
                    a.adminNotes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InfoNote(
                    'Admin notes: ${a.adminNotes}',
                    icon: Icons.lock_outline_rounded,
                  ),
                ],
                DetailCard(title: 'Delivery', children: [
                  DetailRow('Audience', audienceTypeLabel(a.audienceType)),
                  DetailRow('Occupancy', audienceRoleLabel(a.audienceRole)),
                  if (a.audienceType == 'WING' && a.targetWingIds != null)
                    DetailRow('Wings', '${a.targetWingIds!.length} selected'),
                  if (a.audienceType == 'SELECTED_FLATS' &&
                      a.targetFlatIds != null)
                    DetailRow('Flats', '${a.targetFlatIds!.length} selected'),
                  DetailRow(
                      'State', humanizeStatus(a.deliveryState ?? 'pending')),
                  if (a.scheduledAt != null)
                    DetailRow('Scheduled', fmtIsoDateTime(a.scheduledAt)),
                  if (a.publishedAt != null)
                    DetailRow('Published', fmtIsoDateTime(a.publishedAt)),
                  if (a.expiresAt != null)
                    DetailRow('Expires', fmtIsoDateTime(a.expiresAt)),
                  DetailRow('Created', fmtIsoDateTime(a.createdAt)),
                ]),
                if (r != null) ...[
                  const SectionTitle('Reach'),
                  MetricBand(items: [
                    MetricItem('Eligible', '${r.eligibleRecipientCount}'),
                    MetricItem('Notified', '${r.notificationCreatedCount}'),
                    MetricItem(
                      'Read',
                      '${r.readCount}',
                      valueColor: r.readCount > 0 ? C.green : null,
                    ),
                  ]),
                  if (r.note != null && r.note!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(r.note!, style: T.caption),
                    ),
                  const SizedBox(height: 10),
                ],
                if (a.attachments.isNotEmpty) ...[
                  SectionTitle('Attachments',
                      subtitle:
                          '${a.attachments.length} of $kAnnouncementAttachmentMaxCount'),
                  AppCard(
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < a.attachments.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 56, endIndent: 12),
                        ListRow(
                          dense: true,
                          leading: AppAvatar(
                              icon: _mimeIcon(a.attachments[i].mimeType),
                              square: true,
                              size: 36,
                              color:
                                  a.attachments[i].mimeType == 'application/pdf'
                                      ? C.error
                                      : C.blue),
                          title: a.attachments[i].originalFilename,
                          subtitle: _fileSize(a.attachments[i].sizeBytes),
                          showChevron: false,
                          trailing: editable
                              ? IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: C.error),
                                  onPressed: _busy
                                      ? null
                                      : () => _removeAttachment(
                                          a, a.attachments[i]),
                                )
                              : null,
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
                if (canPublish || secondary.isNotEmpty) ...[
                  const SectionTitle('Actions'),
                  ActionRail(
                    busy: _busy,
                    primary: canPublish
                        ? ToolLink(
                            icon: Icons.send_rounded,
                            label: 'Publish now',
                            subtitle: a.status == 'DRAFT'
                                ? 'Send to the selected audience immediately'
                                : 'Publish ahead of the scheduled time',
                            onTap: () => _publish(a),
                          )
                        : null,
                    secondary: secondary,
                  ),
                ],
              ],
            ),
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
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _body = TextEditingController(text: widget.existing?.body);
  late final _notes = TextEditingController(text: widget.existing?.adminNotes);
  late final _flatSearch = TextEditingController();
  late String _category = widget.existing?.category ?? 'GENERAL';
  late String _priority = widget.existing?.priority ?? 'NORMAL';
  late String _audience = widget.existing?.audienceType ?? 'ALL_RESIDENTS';
  late String _audienceRole = widget.existing?.audienceRole ?? 'ALL';
  final _selectedWings = <String>{};
  late final _flatPicker = AnnouncementFlatPickerModel(
    initiallySelected: {...?widget.existing?.targetFlatIds},
  );
  List<WingSummary> _wings = const [];
  bool _submitting = false;
  bool _reviewing = false;
  bool _loadingWings = true;
  bool _loadingFlats = false;
  Object? _wingsError;
  Object? _flatsError;
  String? _error;

  Set<String> get _selectedFlats => _flatPicker.selectedIds;

  String get _audienceCountLabel {
    switch (_audience) {
      case 'WING':
        return '${_selectedWings.length} wing${_selectedWings.length == 1 ? '' : 's'}';
      case 'SELECTED_FLATS':
        return '${_selectedFlats.length} flat${_selectedFlats.length == 1 ? '' : 's'}';
      default:
        return 'All residents';
    }
  }

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
      final flats =
          await ensureLiveRepositories(session.api).society.listAllFlats(
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

  bool _validateForReview() {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return false;
    if (_audience == 'WING' && _selectedWings.isEmpty) {
      setState(() => _error = 'Select at least one wing.');
      return false;
    }
    if (_audience == 'SELECTED_FLATS' && _selectedFlats.isEmpty) {
      setState(() => _error = 'Select at least one flat.');
      return false;
    }
    return true;
  }

  void _openReview() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_validateForReview()) return;
    setState(() => _reviewing = true);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_validateForReview()) {
      setState(() => _reviewing = false);
      return;
    }
    final title = _title.text.trim();
    final body = _body.text.trim();
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
            audienceRole: _audienceRole,
            targetWingIds: _audience == 'WING' ? _selectedWings.toList() : null,
            targetFlatIds:
                _audience == 'SELECTED_FLATS' ? _selectedFlats.toList() : null,
            adminNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
            audienceRole: _audienceRole,
            targetWingIds:
                _audience == 'WING' ? _selectedWings.toList() : const [],
            targetFlatIds: _audience == 'SELECTED_FLATS'
                ? _selectedFlats.toList()
                : const [],
            adminNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = announcementErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _audienceSection() {
    if (_audience == 'WING') {
      if (_loadingWings) return const SkeletonBox(height: 40);
      if (_wingsError != null) {
        return LoadFailure(
            error: _wingsError!, compact: true, onRetry: _loadWings);
      }
      if (_wings.isEmpty) {
        return const EmptyState('No wings found for this society',
            compact: true);
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final w in _wings)
            AppFilterChip(
              label: '${w.name} · ${w.flatCount} flats',
              selected: _selectedWings.contains(w.id),
              onSelected: _submitting
                  ? () {}
                  : () => setState(() {
                        if (_selectedWings.contains(w.id)) {
                          _selectedWings.remove(w.id);
                        } else {
                          _selectedWings.add(w.id);
                        }
                      }),
            ),
        ],
      );
    }
    if (_audience == 'SELECTED_FLATS') {
      if (_loadingFlats) return const SkeletonList(items: 3);
      if (_flatsError != null) {
        return LoadFailure(
          error: _flatsError!,
          compact: true,
          onRetry: () => _loadAllFlats(force: true),
        );
      }
      if (_flatPicker.allFlats.isEmpty) {
        return const EmptyState('No flats found for this society',
            compact: true);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SearchField(
          controller: _flatSearch,
          hint: 'Search by wing or flat number',
          onChanged: (v) => setState(() => _flatPicker.setSearch(v)),
        ),
        const SizedBox(height: 8),
        if (_flatPicker.pageItems.isEmpty)
          const EmptyState('No flats match this search', compact: true)
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < _flatPicker.pageItems.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _flatPicker.isSelected(_flatPicker.pageItems[i].id),
                  title: Text(announcementFlatLabel(_flatPicker.pageItems[i]),
                      style: T.bodyStrong),
                  subtitle: Text('Floor ${_flatPicker.pageItems[i].floor}',
                      style: T.caption),
                  onChanged: _submitting
                      ? null
                      : (sel) => setState(() {
                            _flatPicker.setSelected(
                                _flatPicker.pageItems[i].id, sel ?? false);
                          }),
                ),
              ],
            ]),
          ),
        Row(children: [
          Expanded(
            child: Text('${_flatPicker.totalFiltered} shown', style: T.caption),
          ),
          PaginationBar(
            page: _flatPicker.page,
            totalPages: _flatPicker.totalPages,
            onPrevious: () =>
                setState(() => _flatPicker.goToPage(_flatPicker.page - 1)),
            onNext: () =>
                setState(() => _flatPicker.goToPage(_flatPicker.page + 1)),
          ),
        ]),
      ]);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return FormScaffold(
      title: _reviewing
          ? 'Review draft'
          : (editing ? 'Edit draft' : 'New announcement'),
      formKey: _formKey,
      actions: _reviewing
          ? [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _reviewing = false;
                          _error = null;
                        }),
                child: const Text('Edit'),
              ),
            ]
          : null,
      bottom: PrimaryButton(
        label: _reviewing
            ? (editing ? 'Save draft' : 'Save as draft')
            : 'Review & save',
        icon: _reviewing ? Icons.save_outlined : Icons.preview_outlined,
        busy: _submitting,
        onPressed: _reviewing ? _submit : _openReview,
      ),
      children: _reviewing
          ? [
              ReviewSummary(
                title: 'Draft summary',
                rows: [
                  ('Title', _title.text.trim()),
                  ('Category', announcementCategoryLabel(_category)),
                  ('Priority', _priorityLabel(_priority)),
                  ('Audience', audienceTypeLabel(_audience)),
                  ('Occupancy', audienceRoleLabel(_audienceRole)),
                  ('Audience count', _audienceCountLabel),
                ],
                note:
                    'Drafts are not visible to residents. Publish or schedule from the announcement page.',
              ),
              InlineError(_error),
            ]
          : [
              const FormSectionLabel('Message'),
              TextFormField(
                controller: _title,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  counterText: '',
                ),
                validator: (v) => (v ?? '').trim().length < 3
                    ? 'Title must be at least 3 characters.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _body,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Body *',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v ?? '').trim().length < 3
                    ? 'Body must be at least 3 characters.'
                    : null,
              ),
              const SizedBox(height: 20),
              const FormSectionLabel('Category'),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(_categoryIcon(_category)),
                ),
                items: [
                  for (final c in kAnnouncementCategories)
                    DropdownMenuItem(
                      value: c,
                      child: Text(announcementCategoryLabel(c)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              ScaleToWidth(
                child: SegmentedButton<String>(
                  showSelectedIcon: MediaQuery.sizeOf(context).width >= 400,
                  segments: [
                    for (final p in kAnnouncementPriorities)
                      ButtonSegment(value: p, label: Text(_priorityLabel(p))),
                  ],
                  selected: {_priority},
                  onSelectionChanged: _submitting
                      ? null
                      : (s) => setState(() => _priority = s.first),
                ),
              ),
              const SizedBox(height: 20),
              const FormSectionLabel('Audience'),
              ScaleToWidth(
                child: SegmentedButton<String>(
                  showSelectedIcon: MediaQuery.sizeOf(context).width >= 400,
                  segments: [
                    for (final a in kAudienceTypes)
                      ButtonSegment(
                          value: a, label: Text(audienceTypeLabel(a))),
                  ],
                  selected: {_audience},
                  onSelectionChanged: _submitting
                      ? null
                      : (s) {
                          final next = s.first;
                          setState(() => _audience = next);
                          if (next == 'SELECTED_FLATS' &&
                              _flatPicker.allFlats.isEmpty &&
                              !_loadingFlats) {
                            _loadAllFlats();
                          }
                        },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in kAudienceRoles)
                    AppFilterChip(
                      label: audienceRoleLabel(role),
                      selected: _audienceRole == role,
                      onSelected: _submitting
                          ? () {}
                          : () => setState(() => _audienceRole = role),
                    ),
                ],
              ),
              if (_audience != 'ALL_RESIDENTS') ...[
                const SizedBox(height: 12),
                Text(
                  _audience == 'WING'
                      ? 'Wings (${_selectedWings.length} selected)'
                      : 'Flats (${_selectedFlats.length} selected'
                          '${_flatPicker.allFlats.isEmpty ? '' : ' of ${_flatPicker.allFlats.length}'})',
                  style: T.label,
                ),
                const SizedBox(height: 8),
                _audienceSection(),
              ],
              const SizedBox(height: 20),
              const FormSectionLabel('Admin notes'),
              TextFormField(
                controller: _notes,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Admin notes',
                  helperText: 'Not shown to residents.',
                  alignLabelWithHint: true,
                ),
              ),
              InlineError(_error),
            ],
    );
  }
}
