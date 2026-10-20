import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/admin_user_models.dart';
import '../../api/models/common.dart';
import '../../api/models/complaint_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

String complaintErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'RESIDENTIAL_ACCESS_DENIED':
        return 'Residential complaint access is not available for this flat.';
      case 'COMPLAINT_ACCESS_DENIED':
        return 'You cannot view this complaint.';
      case 'COMPLAINT_CANCEL_FORBIDDEN':
        return 'Only the raiser can cancel this complaint.';
      case 'INVALID_STATUS_TRANSITION':
        return 'This status change is not allowed.';
      case 'INVALID_ASSIGNEE':
        return 'Selected assignee is not valid for this society.';
      case 'RESOLUTION_NOTES_REQUIRED':
        return 'Resolution notes are required.';
      case 'CANCELLATION_REASON_REQUIRED':
        return 'A cancellation reason is required.';
      case 'ATTACHMENT_FORBIDDEN':
        return 'You cannot attach files to this complaint.';
      case 'ATTACHMENT_LIMIT':
        return 'Attachment limit reached (max $kComplaintAttachmentMaxCount).';
      case 'ATTACHMENT_TOO_LARGE':
        return 'File exceeds the 5 MB size limit.';
      case 'INVALID_ATTACHMENT_TYPE':
        return 'Only JPEG, PNG, WebP, or GIF images are allowed.';
      case 'FILE_REQUIRED':
        return 'Please select an image file.';
      case 'ATTACHMENT_FILE_MISSING':
        return 'Attachment is no longer available.';
      case 'RATE_LIMITED':
        return 'Too many requests. Please wait and try again.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this action.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

bool _clientAttachmentOk({
  required String mimeType,
  required int sizeBytes,
  required int existingCount,
}) {
  if (!kComplaintAttachmentMimeTypes.contains(mimeType)) return false;
  if (sizeBytes <= 0 || sizeBytes > kComplaintAttachmentMaxBytes) return false;
  if (existingCount >= kComplaintAttachmentMaxCount) return false;
  return true;
}

String _guessMime(String name, String? reported) {
  if (reported != null && kComplaintAttachmentMimeTypes.contains(reported)) {
    return reported;
  }
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

String _fileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

BadgeTone _priorityTone(String priority) {
  switch (priority.toUpperCase()) {
    case 'URGENT':
      return BadgeTone.danger;
    case 'HIGH':
      return BadgeTone.warning;
    case 'LOW':
      return BadgeTone.neutral;
    default:
      return BadgeTone.info;
  }
}

BadgeTone _statusTone(String status) {
  switch (status.toUpperCase()) {
    case 'OPEN':
      return BadgeTone.warning;
    case 'ASSIGNED':
    case 'IN_PROGRESS':
      return BadgeTone.info;
    case 'RESOLVED':
    case 'CLOSED':
      return BadgeTone.success;
    case 'CANCELLED':
      return BadgeTone.neutral;
    default:
      return BadgeTone.neutral;
  }
}

IconData _categoryIcon(String category) {
  switch (category.toUpperCase()) {
    case 'PLUMBING':
      return Icons.plumbing_outlined;
    case 'ELECTRICAL':
      return Icons.electrical_services_outlined;
    case 'CLEANING':
    case 'HOUSEKEEPING':
      return Icons.cleaning_services_outlined;
    case 'SECURITY':
      return Icons.shield_outlined;
    case 'PARKING':
      return Icons.local_parking_outlined;
    case 'LIFT':
    case 'ELEVATOR':
      return Icons.elevator_outlined;
    case 'NOISE':
      return Icons.volume_up_outlined;
    case 'WATER':
      return Icons.water_drop_outlined;
    case 'MAINTENANCE':
      return Icons.build_outlined;
    default:
      return Icons.report_problem_outlined;
  }
}

IconData _historyIcon(String action) {
  switch (action.toUpperCase()) {
    case 'CREATED':
      return Icons.add_circle_outline_rounded;
    case 'PRIORITY_CHANGED':
      return Icons.flag_outlined;
    case 'ASSIGNED':
    case 'REASSIGNED':
      return Icons.person_add_alt_1_outlined;
    case 'UNASSIGNED':
      return Icons.person_remove_alt_1_outlined;
    case 'STARTED':
      return Icons.play_circle_outline_rounded;
    case 'RESOLVED':
      return Icons.task_alt_rounded;
    case 'CLOSED':
      return Icons.lock_outline_rounded;
    case 'CANCELLED':
      return Icons.cancel_outlined;
    case 'ATTACHMENT_ADDED':
      return Icons.attach_file_rounded;
    default:
      return Icons.circle_outlined;
  }
}

String _historyLabel(ComplaintHistoryItem h) {
  final base = humanizeStatus(h.action);
  if (h.action == 'PRIORITY_CHANGED' && h.newPriority != null) {
    return 'Priority set to ${complaintPriorityLabel(h.newPriority!)}';
  }
  if ((h.action == 'ASSIGNED' || h.action == 'REASSIGNED') &&
      h.assignmentSnapshot != null) {
    final name = h.assignmentSnapshot!['assignedToNameSnapshot'] ??
        (h.assignmentSnapshot!['externalAssignee'] is Map
            ? (h.assignmentSnapshot!['externalAssignee'] as Map)['name']
            : null);
    if (name is String && name.isNotEmpty) return '$base to $name';
  }
  return base;
}

class _ComplaintRow extends StatelessWidget {
  const _ComplaintRow({required this.complaint, required this.onTap});
  final Complaint complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        icon: _categoryIcon(c.category),
        square: true,
        color: badgeColors(_statusTone(c.status)).fg,
      ),
      title: c.title,
      subtitle: '${c.complaintNumber} · ${complaintCategoryLabel(c.category)}\n'
          '${fmtIsoDateTime(c.createdAt)}',
      badges: [
        StatusBadge(complaintStatusLabel(c.status),
            tone: _statusTone(c.status)),
        if (c.priority != 'MEDIUM')
          StatusBadge(complaintPriorityLabel(c.priority),
              tone: _priorityTone(c.priority), icon: Icons.flag_rounded),
      ],
    );
  }
}

class _ComplaintHeader extends StatelessWidget {
  const _ComplaintHeader({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    return DetailHero(
      title: c.title,
      subtitle: c.complaintNumber,
      leading: AppAvatar(
        icon: _categoryIcon(c.category),
        size: Sz.avatarLg,
        square: true,
        color: badgeColors(_statusTone(c.status)).fg,
      ),
      badges: [
        StatusBadge(complaintStatusLabel(c.status),
            tone: _statusTone(c.status)),
        StatusBadge(complaintPriorityLabel(c.priority),
            tone: _priorityTone(c.priority), icon: Icons.flag_rounded),
        StatusBadge(complaintCategoryLabel(c.category),
            tone: BadgeTone.neutral, icon: _categoryIcon(c.category)),
      ],
    );
  }
}

class _HistoryTimeline extends StatelessWidget {
  const _HistoryTimeline({required this.items, this.showInternal = false});
  final List<ComplaintHistoryItem> items;
  final bool showInternal;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState('No history yet', compact: true);
    }
    final ordered = items.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return AppCard(
      child: Column(children: [
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0) const Divider(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppAvatar(
              icon: _historyIcon(ordered[i].action),
              size: 34,
              square: true,
              color: C.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_historyLabel(ordered[i]), style: T.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      '${fmtIsoDateTime(ordered[i].createdAt)} · ${humanizeStatus(ordered[i].actorRole)}',
                      style: T.caption,
                    ),
                    if (ordered[i].publicNotes != null &&
                        ordered[i].publicNotes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(ordered[i].publicNotes!, style: T.body),
                    ],
                    // Resident screens never show h.notes (internal).
                    if (showInternal &&
                        ordered[i].notes != null &&
                        ordered[i].notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: C.surfaceAlt,
                          borderRadius: BorderRadius.circular(Rd.sm),
                        ),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.lock_outline_rounded,
                                  size: 14, color: C.muted),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(ordered[i].notes!,
                                      style: T.secondary)),
                            ]),
                      ),
                    ],
                  ]),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({required this.attachments, required this.onOpen});
  final List<ComplaintAttachment> attachments;
  final ValueChanged<ComplaintAttachment> onOpen;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const EmptyState('No photos attached',
          icon: Icons.photo_library_outlined, compact: true);
    }
    return Column(children: [
      for (final a in attachments)
        ListRow(
          dense: true,
          leading: const AppAvatar(
              icon: Icons.image_outlined, square: true, size: 36),
          title: a.originalFilename,
          subtitle: '${_fileSize(a.sizeBytes)} · ${fmtIsoDate(a.createdAt)}',
          trailing:
              const Icon(Icons.open_in_full_rounded, size: 18, color: C.muted),
          showChevron: false,
          onTap: () => onOpen(a),
        ),
    ]);
  }
}

Future<void> _showImageDialog(
    BuildContext context, String title, List<int> bytes) {
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
                child: Text(title,
                    style: T.title, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          Flexible(
            child: InteractiveViewer(
              child:
                  Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ─── Resident ────────────────────────────────────────────────────────────────

class LiveResidentComplaintsPage extends StatefulWidget {
  const LiveResidentComplaintsPage({super.key});

  @override
  State<LiveResidentComplaintsPage> createState() =>
      _LiveResidentComplaintsPageState();
}

class _LiveResidentComplaintsPageState
    extends State<LiveResidentComplaintsPage> {
  String? statusFilter;
  late Future<Paged<Complaint>> _future = _load();
  StreamSubscription<ComplaintEventPayload>? _sub;

  Future<Paged<Complaint>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).complaints.listResident(
          force: force,
          query: ListComplaintsQuery(status: statusFilter, limit: 50),
        );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.complaintEvents.listen((_) {
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

  Future<void> _create() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveCreateComplaintPage()),
    );
    if (ok == true && mounted) reload();
  }

  Widget _filters() => FilterBar(
        padding: EdgeInsets.zero,
        children: [
          AppFilterChip(
            label: 'All',
            selected: statusFilter == null,
            onSelected: () => setState(() {
              statusFilter = null;
              _future = _load(force: true);
            }),
          ),
          for (final s in kComplaintStatuses)
            AppFilterChip(
              label: complaintStatusLabel(s),
              selected: statusFilter == s,
              onSelected: () => setState(() {
                statusFilter = s;
                _future = _load(force: true);
              }),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-complaint',
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New complaint'),
      ),
      body: FutureBuilder<Paged<Complaint>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 5, showHeader: true);
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load complaints',
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
                const PageHeader('My complaints',
                    subtitle: 'Track issues raised for your flat'),
                _filters(),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  EmptyState(
                    statusFilter == null
                        ? 'When something needs attention in your flat, raise it here and track progress with the society office.'
                        : 'Nothing matches ${complaintStatusLabel(statusFilter!).toLowerCase()}. Try another status or clear the filter.',
                    icon: statusFilter == null
                        ? Icons.report_problem_outlined
                        : Icons.filter_list_off_rounded,
                    title: statusFilter == null
                        ? 'No complaints yet'
                        : 'No matches',
                    actionLabel:
                        statusFilter == null ? 'Raise a complaint' : 'Show all',
                    onAction: statusFilter == null
                        ? _create
                        : () => setState(() {
                              statusFilter = null;
                              _future = _load(force: true);
                            }),
                  )
                else ...[
                  ResultCount(items.length, 'complaint'),
                  for (final c in items)
                    _ComplaintRow(
                      complaint: c,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveResidentComplaintDetailPage(
                                complaintId: c.id),
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

class LiveCreateComplaintPage extends StatefulWidget {
  const LiveCreateComplaintPage({super.key});

  @override
  State<LiveCreateComplaintPage> createState() =>
      _LiveCreateComplaintPageState();
}

class _LiveCreateComplaintPageState extends State<LiveCreateComplaintPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'OTHER';
  String? _flatId;
  bool _submitting = false;
  bool reviewing = false;
  String? _error;
  final _pendingFiles = <({List<int> bytes, String name, String mime})>[];

  @override
  void initState() {
    super.initState();
    // Multi-flat accounts must use the shared selection (or pick in the UI).
    _flatId = authSession?.selectedResidentFlatId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String _flatLabel() {
    final flats = authSession?.residentFlats ?? const [];
    final id = _flatId;
    if (id == null) return 'Not selected';
    for (final f in flats) {
      if (f.flat.id == id) {
        return '${f.flat.wingCode ?? '?'}-${f.flat.number}';
      }
    }
    return id;
  }

  Future<void> _pickImage() async {
    if (_pendingFiles.length >= kComplaintAttachmentMaxCount) {
      showWarningSnack(context,
          'You can attach up to $kComplaintAttachmentMaxCount images.');
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
    final mime = _guessMime(file.name, file.mimeType);
    if (!_clientAttachmentOk(
      mimeType: mime,
      sizeBytes: bytes.length,
      existingCount: _pendingFiles.length,
    )) {
      if (!mounted) return;
      showErrorSnack(
          context, 'Invalid image. Use JPEG, PNG, WebP or GIF under 5 MB.');
      return;
    }
    setState(() {
      _pendingFiles.add((bytes: bytes, name: file.name, mime: mime));
    });
  }

  void _openReview() {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    if (_flatId == null) {
      setState(() => _error = 'Select the flat this complaint is about.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => reviewing = true);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    final flatId = _flatId;
    if (flatId == null) {
      setState(() {
        reviewing = false;
        _error = 'Select the flat this complaint is about.';
      });
      return;
    }
    final title = _title.text.trim();
    final description = _description.text.trim();
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repos = ensureLiveRepositories(session.api);
      final created = await repos.complaints.create(
        CreateComplaintRequest(
          flatId: flatId,
          category: _category,
          title: title,
          description: description,
        ),
      );
      for (final file in _pendingFiles) {
        await repos.complaints.uploadResidentAttachment(
          created.id,
          bytes: file.bytes,
          filename: file.name,
          mimeType: file.mime,
        );
      }
      if (!mounted) return;
      showSuccessSnack(context, 'Complaint ${created.complaintNumber} raised.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = complaintErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flats = authSession?.residentFlats ?? const [];
    return FormScaffold(
      title: reviewing ? 'Review complaint' : 'New complaint',
      formKey: reviewing ? null : _formKey,
      actions: reviewing
          ? [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          reviewing = false;
                          _error = null;
                        }),
                child: const Text('Edit'),
              ),
            ]
          : null,
      bottom: PrimaryButton(
        label: reviewing ? 'Submit complaint' : 'Review & continue',
        icon: reviewing ? Icons.send_rounded : Icons.rate_review_outlined,
        busy: _submitting,
        onPressed: reviewing ? _submit : _openReview,
      ),
      children: reviewing
          ? [
              ReviewSummary(
                title: 'Complaint summary',
                rows: [
                  ('Flat', _flatLabel()),
                  ('Category', complaintCategoryLabel(_category)),
                  ('Subject', _title.text.trim()),
                  if (_pendingFiles.isNotEmpty)
                    (
                      'Photos',
                      '${_pendingFiles.length} attached',
                    ),
                ],
                note:
                    'Priority defaults to Medium. The society office can adjust it after you submit.',
              ),
              if (_description.text.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                DetailCard(title: 'Description', children: [
                  Text(_description.text.trim(), style: T.body),
                ]),
              ],
              if (_pendingFiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionTitle('Photos'),
                for (final f in _pendingFiles)
                  ListRow(
                    dense: true,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(Rd.sm),
                      child: Image.memory(
                        Uint8List.fromList(f.bytes),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: f.name,
                    subtitle: _fileSize(f.bytes.length),
                    showChevron: false,
                  ),
              ],
              InlineError(_error),
            ]
          : [
              if (flats.length > 1) ...[
                const FormSectionLabel('Flat'),
                DropdownButtonFormField<String>(
                  initialValue: _flatId,
                  decoration: const InputDecoration(
                    labelText: 'Flat',
                    prefixIcon: Icon(Icons.apartment_outlined),
                  ),
                  items: flats
                      .map(
                        (f) => DropdownMenuItem(
                          value: f.flat.id,
                          child: Text(
                            '${f.flat.wingCode ?? '?'}-${f.flat.number}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (v) {
                          setState(() => _flatId = v);
                          if (v != null) authSession?.selectResidentFlat(v);
                        },
                ),
                const SizedBox(height: 8),
              ] else if (flats.length == 1) ...[
                const FormSectionLabel('Flat'),
                DetailCard(children: [
                  DetailRow('Flat', _flatLabel()),
                ]),
                const SizedBox(height: 8),
              ],
              const FormSectionLabel('Issue'),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(_categoryIcon(_category)),
                ),
                items: kComplaintCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(complaintCategoryLabel(c)),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _category = v ?? 'OTHER'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'Short summary, e.g. "Water leakage in bathroom"',
                  counterText: '',
                ),
                validator: (v) => (v ?? '').trim().length < 3
                    ? 'Title must be at least 3 characters.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                enabled: !_submitting,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Describe the problem, when it started and where.',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v ?? '').trim().length < 5
                    ? 'Description must be at least 5 characters.'
                    : null,
              ),
              const SizedBox(height: 8),
              FormSectionLabel(
                  'Photos (${_pendingFiles.length}/$kComplaintAttachmentMaxCount)'),
              for (final f in _pendingFiles)
                ListRow(
                  dense: true,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(Rd.sm),
                    child: Image.memory(
                      Uint8List.fromList(f.bytes),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: f.name,
                  subtitle: _fileSize(f.bytes.length),
                  showChevron: false,
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _pendingFiles.remove(f)),
                  ),
                ),
              if (_pendingFiles.length < kComplaintAttachmentMaxCount)
                SecondaryButton(
                  label:
                      _pendingFiles.isEmpty ? 'Add photo' : 'Add another photo',
                  icon: Icons.add_photo_alternate_outlined,
                  onPressed: _submitting ? null : _pickImage,
                ),
              const SizedBox(height: 8),
              const InfoNote(
                'Priority is set to Medium by default and can be adjusted by the society office. JPEG, PNG, WebP or GIF up to 5 MB each.',
              ),
              InlineError(_error),
            ],
    );
  }
}

class LiveResidentComplaintDetailPage extends StatefulWidget {
  const LiveResidentComplaintDetailPage({super.key, required this.complaintId});
  final String complaintId;

  @override
  State<LiveResidentComplaintDetailPage> createState() =>
      _LiveResidentComplaintDetailPageState();
}

class _LiveResidentComplaintDetailPageState
    extends State<LiveResidentComplaintDetailPage> {
  late Future<Complaint> _future = _load();
  bool _busy = false;
  StreamSubscription<ComplaintEventPayload>? _sub;

  Future<Complaint> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .complaints
        .getResident(widget.complaintId, force: force);
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.complaintEvents.listen((e) {
      if (e.complaintId == widget.complaintId && mounted) {
        setState(() => _future = _load(force: true));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cancel(Complaint c) async {
    if (_busy) return;
    final reason = await promptTextDialog(
      context,
      title: 'Cancel this complaint?',
      message:
          'The society office will stop working on ${c.complaintNumber}. This cannot be undone.',
      label: 'Reason (optional)',
      confirmLabel: 'Cancel complaint',
      cancelLabel: 'Keep it',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final trimmed = reason.trim();
      await ensureLiveRepositories(session.api).complaints.cancelResident(
            c.id,
            reason: trimmed.isEmpty ? null : trimmed,
          );
      if (!mounted) return;
      showAppSnack(context, 'Complaint cancelled.', tone: SnackTone.warning);
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, complaintErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(Complaint c) async {
    if (_busy) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = _guessMime(file.name, file.mimeType);
    if (!_clientAttachmentOk(
      mimeType: mime,
      sizeBytes: bytes.length,
      existingCount: c.attachments.length,
    )) {
      if (!mounted) return;
      showErrorSnack(
          context, 'Invalid image. Use JPEG, PNG, WebP or GIF under 5 MB.');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api)
          .complaints
          .uploadResidentAttachment(
            c.id,
            bytes: bytes,
            filename: file.name,
            mimeType: mime,
          );
      if (!mounted) return;
      showSuccessSnack(context, 'Photo attached.');
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, complaintErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttachment(Complaint c, ComplaintAttachment a) async {
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final bytes = await ensureLiveRepositories(session.api)
          .complaints
          .downloadResidentAttachment(c.id, a.id);
      if (!mounted) return;
      await _showImageDialog(context, a.originalFilename, bytes);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, complaintErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint')),
      body: FutureBuilder<Complaint>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading complaint…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load complaint',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final c = snapshot.data!;
          final canEdit = c.status == 'OPEN';
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                _ComplaintHeader(complaint: c),
                const SizedBox(height: 18),
                DetailCard(title: 'Details', children: [
                  Text(c.description, style: T.body),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  DetailRow('Raised on', fmtIsoDateTime(c.createdAt)),
                  if (c.assignedToNameSnapshot != null)
                    DetailRow('Assigned to', c.assignedToNameSnapshot!),
                  if (c.resolvedAt != null)
                    DetailRow('Resolved on', fmtIsoDateTime(c.resolvedAt)),
                  if (c.closedAt != null)
                    DetailRow('Closed on', fmtIsoDateTime(c.closedAt)),
                  if (c.cancelledAt != null)
                    DetailRow('Cancelled on', fmtIsoDateTime(c.cancelledAt)),
                ]),
                if (c.resolutionNotes != null &&
                    c.resolutionNotes!.trim().isNotEmpty)
                  InfoNote(
                    'Resolution: ${c.resolutionNotes}',
                    tone: NoteTone.success,
                    icon: Icons.task_alt_rounded,
                  ),
                if (c.cancellationReason != null &&
                    c.cancellationReason!.trim().isNotEmpty)
                  InfoNote(
                    'Cancellation reason: ${c.cancellationReason}',
                    tone: NoteTone.info,
                    icon: Icons.cancel_outlined,
                  ),
                // Never show internalNotes on resident screens.
                const SizedBox(height: 10),
                SectionTitle(
                  'Photos',
                  subtitle:
                      '${c.attachments.length} of $kComplaintAttachmentMaxCount',
                  action: canEdit &&
                          c.attachments.length < kComplaintAttachmentMaxCount
                      ? TextButton.icon(
                          onPressed: _busy ? null : () => _attach(c),
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18),
                          label: const Text('Add'),
                        )
                      : null,
                ),
                _AttachmentList(
                  attachments: c.attachments,
                  onOpen: (a) => _openAttachment(c, a),
                ),
                const SizedBox(height: 14),
                const SectionTitle('Timeline'),
                _HistoryTimeline(items: c.history),
                if (canEdit) ...[
                  const SizedBox(height: 20),
                  SecondaryButton(
                    label: 'Cancel complaint',
                    icon: Icons.cancel_outlined,
                    destructive: true,
                    busy: _busy,
                    onPressed: () => _cancel(c),
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

// ─── Admin ───────────────────────────────────────────────────────────────────

class LiveAdminComplaintsPage extends StatefulWidget {
  const LiveAdminComplaintsPage({super.key});

  @override
  State<LiveAdminComplaintsPage> createState() =>
      _LiveAdminComplaintsPageState();
}

class _LiveAdminComplaintsPageState extends State<LiveAdminComplaintsPage> {
  String? statusFilter;
  String? categoryFilter;
  String? priorityFilter;
  late Future<_AdminComplaintsBundle> _future = _load();
  StreamSubscription<ComplaintEventPayload>? _sub;

  Future<_AdminComplaintsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final list = await repos.complaints.listAdmin(
      force: force,
      query: ListComplaintsQuery(
        status: statusFilter,
        category: categoryFilter,
        priority: priorityFilter,
        limit: 50,
      ),
    );
    final summary = await repos.complaints.summary(force: force);
    return _AdminComplaintsBundle(list: list, summary: summary);
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.complaintEvents.listen((_) {
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

  bool get _filtered =>
      statusFilter != null || categoryFilter != null || priorityFilter != null;

  void _clearFilters() => setState(() {
        statusFilter = null;
        categoryFilter = null;
        priorityFilter = null;
        _future = _load(force: true);
      });

  Future<void> _pickCategory() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Filter by category',
      builder: (ctx) => Column(children: [
        ListRow(
          dense: true,
          title: 'All categories',
          leading: const AppAvatar(
              icon: Icons.all_inclusive_rounded, square: true, size: 36),
          trailing: categoryFilter == null
              ? const Icon(Icons.check_rounded, color: C.blue)
              : null,
          showChevron: false,
          onTap: () => Navigator.pop(ctx, ''),
        ),
        for (final cat in kComplaintCategories)
          ListRow(
            dense: true,
            title: complaintCategoryLabel(cat),
            leading:
                AppAvatar(icon: _categoryIcon(cat), square: true, size: 36),
            trailing: categoryFilter == cat
                ? const Icon(Icons.check_rounded, color: C.blue)
                : null,
            showChevron: false,
            onTap: () => Navigator.pop(ctx, cat),
          ),
      ]),
    );
    if (picked == null) return;
    setState(() {
      categoryFilter = picked.isEmpty ? null : picked;
      _future = _load(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminComplaintsBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snapshot.hasError) {
          return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load complaints',
              onRetry: reload);
        }
        final bundle = snapshot.data!;
        final s = bundle.summary;
        final items = bundle.list.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: Sp.pagePadding,
            children: [
              const PageHeader('Complaints',
                  subtitle: 'Resident issues across the society'),
              MetricBand(items: [
                MetricItem(
                  'Open',
                  '${s.open}',
                  valueColor: s.open > 0 ? C.amber : C.navy,
                  onTap: () => setState(() {
                    statusFilter = statusFilter == 'OPEN' ? null : 'OPEN';
                    _future = _load(force: true);
                  }),
                ),
                MetricItem(
                  'Assigned',
                  '${s.assigned}',
                  valueColor: C.blue,
                  onTap: () => setState(() {
                    statusFilter =
                        statusFilter == 'ASSIGNED' ? null : 'ASSIGNED';
                    _future = _load(force: true);
                  }),
                ),
                MetricItem(
                  'In progress',
                  '${s.inProgress}',
                  valueColor: C.blue,
                  onTap: () => setState(() {
                    statusFilter =
                        statusFilter == 'IN_PROGRESS' ? null : 'IN_PROGRESS';
                    _future = _load(force: true);
                  }),
                ),
                MetricItem(
                  'High / urgent',
                  '${s.highAndUrgentOpen}',
                  valueColor: s.highAndUrgentOpen > 0 ? C.error : C.navy,
                ),
              ]),
              const SizedBox(height: 12),
              FilterBar(
                padding: EdgeInsets.zero,
                children: [
                  for (final st in const [
                    'RESOLVED',
                    'CLOSED',
                    'CANCELLED',
                  ])
                    AppFilterChip(
                      label: complaintStatusLabel(st),
                      selected: statusFilter == st,
                      onSelected: () => setState(() {
                        statusFilter = statusFilter == st ? null : st;
                        _future = _load(force: true);
                      }),
                    ),
                  AppFilterChip(
                    label: categoryFilter == null
                        ? 'Category'
                        : complaintCategoryLabel(categoryFilter!),
                    icon: Icons.category_outlined,
                    selected: categoryFilter != null,
                    onSelected: _pickCategory,
                  ),
                  for (final p in [null, ...kComplaintPriorities])
                    AppFilterChip(
                      label: p == null
                          ? 'All priority'
                          : complaintPriorityLabel(p),
                      selected: priorityFilter == p,
                      onSelected: () => setState(() {
                        priorityFilter = p;
                        _future = _load(force: true);
                      }),
                    ),
                ],
              ),
              if (statusFilter != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      statusFilter = null;
                      _future = _load(force: true);
                    }),
                    icon: const Icon(Icons.filter_list_off_rounded, size: 18),
                    label: Text(
                        'Showing ${complaintStatusLabel(statusFilter!)} · Clear'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (items.isEmpty)
                EmptyState(
                  _filtered
                      ? 'Try clearing status, category, or priority filters to see more.'
                      : 'Complaints raised by residents will appear here for triage.',
                  icon: _filtered
                      ? Icons.filter_list_off_rounded
                      : Icons.task_alt_rounded,
                  title: _filtered ? 'No matches' : 'Inbox clear',
                  actionLabel: _filtered ? 'Clear filters' : null,
                  onAction: _filtered ? _clearFilters : null,
                )
              else ...[
                Row(children: [
                  Expanded(
                      child: ResultCount(
                          bundle.list.pagination.total, 'complaint')),
                  if (_filtered)
                    TextButton(
                        onPressed: _clearFilters, child: const Text('Clear')),
                ]),
                for (final c in items)
                  _ComplaintRow(
                    complaint: c,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LiveAdminComplaintDetailPage(complaintId: c.id),
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
    );
  }
}

class _AdminComplaintsBundle {
  const _AdminComplaintsBundle({required this.list, required this.summary});
  final Paged<Complaint> list;
  final ComplaintSummary summary;
}

class LiveAdminComplaintDetailPage extends StatefulWidget {
  const LiveAdminComplaintDetailPage({super.key, required this.complaintId});
  final String complaintId;

  @override
  State<LiveAdminComplaintDetailPage> createState() =>
      _LiveAdminComplaintDetailPageState();
}

class _LiveAdminComplaintDetailPageState
    extends State<LiveAdminComplaintDetailPage> {
  late Future<Complaint> _future = _load();
  bool _busy = false;
  StreamSubscription<ComplaintEventPayload>? _sub;

  Future<Complaint> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .complaints
        .getAdmin(widget.complaintId, force: force);
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.complaintEvents.listen((e) {
      if (e.complaintId == widget.complaintId && mounted) {
        setState(() => _future = _load(force: true));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (success != null) showSuccessSnack(context, success);
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, complaintErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(Complaint c) async {
    final session = authSession;
    if (session == null) return;
    setState(() => _busy = true);
    Paged<AdminUser> users;
    try {
      users = await ensureLiveRepositories(session.api).users.listUsers(
            force: true,
            query: const ListUsersQuery(limit: 100),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, complaintErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final candidates = users.items
        .where((u) => u.roles.contains('ADMIN') || u.roles.contains('OWNER'))
        .toList();
    AdminUser? selected;
    var type = 'INTERNAL';
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? localError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
              c.status == 'OPEN' ? 'Assign complaint' : 'Reassign complaint'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'INTERNAL',
                        label: Text('Internal'),
                        icon: Icon(Icons.badge_outlined, size: 18)),
                    ButtonSegment(
                        value: 'EXTERNAL',
                        label: Text('External'),
                        icon: Icon(Icons.handyman_outlined, size: 18)),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setLocal(() {
                    type = s.first;
                    localError = null;
                  }),
                ),
                const SizedBox(height: 14),
                if (type == 'INTERNAL')
                  DropdownButtonFormField<AdminUser>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Assignee',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: candidates
                        .map((u) => DropdownMenuItem(
                              value: u,
                              child:
                                  Text(u.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setLocal(() {
                      selected = v;
                      localError = null;
                    }),
                  )
                else
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Vendor / contractor name',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    onChanged: (_) => setLocal(() => localError = null),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes (optional)',
                    helperText: 'Visible to admins only.',
                  ),
                ),
                InlineError(localError),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (type == 'INTERNAL' && selected == null) {
                  setLocal(() => localError = 'Choose an assignee.');
                  return;
                }
                if (type == 'EXTERNAL' && nameCtrl.text.trim().isEmpty) {
                  setLocal(() => localError = 'Enter the vendor name.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() async {
        final notes = notesCtrl.text.trim();
        await ensureLiveRepositories(session.api).complaints.assign(
              c.id,
              assignmentType: type,
              assignedToUserId: type == 'INTERNAL' ? selected?.id : null,
              externalAssignee: type == 'EXTERNAL'
                  ? ExternalAssignee(name: nameCtrl.text.trim())
                  : null,
              notes: notes.isEmpty ? null : notes,
            );
      }, success: 'Complaint assigned.');
    }
    nameCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _resolve(Complaint c) async {
    final notesCtrl = TextEditingController();
    final internalCtrl = TextEditingController();
    String? localError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Resolve complaint'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Resolution notes *',
                    helperText: 'Shared with the resident.',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setLocal(() => localError = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: internalCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes',
                    helperText: 'Admins only.',
                    alignLabelWithHint: true,
                  ),
                ),
                InlineError(localError),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (notesCtrl.text.trim().isEmpty) {
                  setLocal(() => localError = 'Resolution notes are required.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Mark resolved'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() async {
        final session = authSession!;
        final internal = internalCtrl.text.trim();
        await ensureLiveRepositories(session.api).complaints.resolve(
              c.id,
              resolutionNotes: notesCtrl.text.trim(),
              internalNotes: internal.isEmpty ? null : internal,
            );
      }, success: 'Complaint marked resolved.');
    }
    notesCtrl.dispose();
    internalCtrl.dispose();
  }

  Future<void> _cancel(Complaint c) async {
    final reason = await promptTextDialog(
      context,
      title: 'Cancel complaint?',
      message:
          'This closes ${c.complaintNumber} without resolution. The resident will see the reason.',
      label: 'Reason *',
      confirmLabel: 'Cancel complaint',
      cancelLabel: 'Back',
      destructive: true,
      required: true,
      maxLines: 2,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(() async {
      await ensureLiveRepositories(authSession!.api).complaints.cancelAdmin(
            c.id,
            reason: reason.trim(),
          );
    }, success: 'Complaint cancelled.');
  }

  Future<void> _unassign(Complaint c) async {
    final ok = await confirmDialog(
      context,
      title: 'Unassign complaint?',
      message:
          '${c.assignedToNameSnapshot ?? 'The current assignee'} will be removed and the complaint returns to Open.',
      confirmLabel: 'Unassign',
      icon: Icons.person_remove_alt_1_outlined,
    );
    if (!ok) return;
    await _run(() async {
      await ensureLiveRepositories(authSession!.api).complaints.unassign(c.id);
    }, success: 'Assignee removed.');
  }

  Future<void> _close(Complaint c) async {
    final ok = await confirmDialog(
      context,
      title: 'Close complaint?',
      message:
          'Closing confirms the resolution. No further changes can be made.',
      confirmLabel: 'Close complaint',
      icon: Icons.lock_outline_rounded,
    );
    if (!ok) return;
    await _run(() async {
      await ensureLiveRepositories(authSession!.api).complaints.close(c.id);
    }, success: 'Complaint closed.');
  }

  Future<void> _setPriority(Complaint c) async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Set priority',
      builder: (ctx) => Column(children: [
        for (final p in kComplaintPriorities)
          ListRow(
            dense: true,
            title: complaintPriorityLabel(p),
            leading: AppAvatar(
              icon: Icons.flag_rounded,
              square: true,
              size: 36,
              color: badgeColors(_priorityTone(p)).fg,
            ),
            trailing: c.priority == p
                ? const Icon(Icons.check_rounded, color: C.blue)
                : null,
            showChevron: false,
            onTap: () => Navigator.pop(ctx, p),
          ),
      ]),
    );
    if (picked == null || picked == c.priority) return;
    await _run(() async {
      await ensureLiveRepositories(authSession!.api)
          .complaints
          .updatePriority(c.id, priority: picked);
    }, success: 'Priority updated to ${complaintPriorityLabel(picked)}.');
  }

  Future<void> _openAttachment(Complaint c, ComplaintAttachment a) async {
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final bytes = await ensureLiveRepositories(session.api)
          .complaints
          .downloadAdminAttachment(c.id, a.id);
      if (!mounted) return;
      await _showImageDialog(context, a.originalFilename, bytes);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, complaintErrorMessage(e));
    }
  }

  ToolLink? _primaryAction(Complaint c) {
    switch (c.status) {
      case 'ASSIGNED':
        return ToolLink(
          icon: Icons.play_circle_outline_rounded,
          label: 'Start work',
          subtitle: 'Move to In progress',
          onTap: () => _run(() async {
            await ensureLiveRepositories(authSession!.api)
                .complaints
                .start(c.id);
          }, success: 'Work started.'),
        );
      case 'IN_PROGRESS':
        return ToolLink(
          icon: Icons.task_alt_rounded,
          label: 'Resolve',
          subtitle: 'Add resolution notes for the resident',
          onTap: () => _resolve(c),
        );
      case 'RESOLVED':
        return ToolLink(
          icon: Icons.lock_outline_rounded,
          label: 'Close complaint',
          subtitle: 'Confirm the resolution and archive',
          onTap: () => _close(c),
        );
      default:
        return null;
    }
  }

  List<ToolLink> _secondaryActions(Complaint c) {
    final active = c.status == 'OPEN' ||
        c.status == 'ASSIGNED' ||
        c.status == 'IN_PROGRESS';
    final links = <ToolLink>[];
    if (active) {
      links.add(ToolLink(
        icon: Icons.person_add_alt_1_outlined,
        label: c.status == 'OPEN' ? 'Assign' : 'Reassign',
        subtitle: c.assignedToNameSnapshot == null
            ? 'Choose a staff member or vendor'
            : 'Currently ${c.assignedToNameSnapshot}',
        onTap: () => _assign(c),
      ));
    }
    if (c.status != 'CLOSED' && c.status != 'CANCELLED') {
      links.add(ToolLink(
        icon: Icons.flag_outlined,
        label: 'Change priority',
        subtitle: 'Currently ${complaintPriorityLabel(c.priority)}',
        onTap: () => _setPriority(c),
      ));
    }
    if (active) {
      links.add(ToolLink(
        icon: Icons.cancel_outlined,
        label: 'Cancel complaint',
        subtitle: 'Requires a reason',
        onTap: () => _cancel(c),
      ));
    }
    if (c.status == 'ASSIGNED') {
      links.add(ToolLink(
        icon: Icons.person_remove_alt_1_outlined,
        label: 'Unassign',
        subtitle: 'Return to Open',
        onTap: () => _unassign(c),
      ));
    }
    return links;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint')),
      body: FutureBuilder<Complaint>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading complaint…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load complaint',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final c = snapshot.data!;
          final primary = _primaryAction(c);
          final secondary = _secondaryActions(c);
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                _ComplaintHeader(complaint: c),
                const SizedBox(height: 18),
                DetailCard(title: 'Details', children: [
                  Text(c.description, style: T.body),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  DetailRow('Raised on', fmtIsoDateTime(c.createdAt)),
                  DetailRow('Raised by', humanizeStatus(c.raisedByRole)),
                  DetailRow(
                    'Assignee',
                    c.assignedToNameSnapshot ?? 'Unassigned',
                    valueWidget: c.assignedToNameSnapshot == null
                        ? const Text('Unassigned', style: T.secondary)
                        : Text(
                            '${c.assignedToNameSnapshot}'
                            '${c.assignmentType == 'EXTERNAL' ? ' (external)' : ''}',
                            style: T.bodyStrong),
                  ),
                  if (c.externalAssignee?.phone != null)
                    DetailRow('Vendor phone', c.externalAssignee!.phone!),
                  if (c.externalAssignee?.company != null)
                    DetailRow('Vendor company', c.externalAssignee!.company!),
                  if (c.resolvedAt != null)
                    DetailRow('Resolved on', fmtIsoDateTime(c.resolvedAt)),
                  if (c.closedAt != null)
                    DetailRow('Closed on', fmtIsoDateTime(c.closedAt)),
                  if (c.cancelledAt != null)
                    DetailRow('Cancelled on', fmtIsoDateTime(c.cancelledAt)),
                ]),
                if (c.resolutionNotes != null &&
                    c.resolutionNotes!.trim().isNotEmpty)
                  InfoNote(
                    'Resolution: ${c.resolutionNotes}',
                    tone: NoteTone.success,
                    icon: Icons.task_alt_rounded,
                  ),
                if (c.internalNotes != null &&
                    c.internalNotes!.trim().isNotEmpty)
                  InfoNote(
                    'Internal notes: ${c.internalNotes}',
                    tone: NoteTone.info,
                    icon: Icons.lock_outline_rounded,
                  ),
                if (c.cancellationReason != null &&
                    c.cancellationReason!.trim().isNotEmpty)
                  InfoNote(
                    'Cancellation reason: ${c.cancellationReason}',
                    tone: NoteTone.warning,
                    icon: Icons.cancel_outlined,
                  ),
                if (primary != null || secondary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const SectionTitle('Actions'),
                  ActionRail(
                    busy: _busy,
                    primary: primary,
                    secondary: secondary,
                  ),
                ],
                const SizedBox(height: 14),
                SectionTitle('Photos',
                    subtitle: '${c.attachments.length} attached'),
                _AttachmentList(
                  attachments: c.attachments,
                  onOpen: (a) => _openAttachment(c, a),
                ),
                const SizedBox(height: 14),
                const SectionTitle('Timeline'),
                _HistoryTimeline(items: c.history, showInternal: true),
              ],
            ),
          );
        },
      ),
    );
  }
}
