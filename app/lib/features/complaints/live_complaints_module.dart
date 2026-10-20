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

String _shortIso(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day}/${d.month}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Complaint>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading complaints…');
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
                      'My complaints',
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
                          builder: (_) => const LiveCreateComplaintPage(),
                        ),
                      );
                      if (ok == true) reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: statusFilter == null,
                    onSelected: (_) {
                      setState(() {
                        statusFilter = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  for (final s in ['OPEN', 'ASSIGNED', 'IN_PROGRESS', 'RESOLVED', 'CLOSED', 'CANCELLED'])
                    FilterChip(
                      label: Text(complaintStatusLabel(s)),
                      selected: statusFilter == s,
                      onSelected: (_) {
                        setState(() {
                          statusFilter = s;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No complaints yet')
              else
                ...items.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveResidentComplaintDetailPage(
                              complaintId: c.id,
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
                            c.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${c.complaintNumber} · '
                            '${complaintCategoryLabel(c.category)} · '
                            '${_shortIso(c.createdAt)}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(complaintStatusLabel(c.status)),
                              StatusBadge(complaintPriorityLabel(c.priority)),
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

class LiveCreateComplaintPage extends StatefulWidget {
  const LiveCreateComplaintPage({super.key});

  @override
  State<LiveCreateComplaintPage> createState() =>
      _LiveCreateComplaintPageState();
}

class _LiveCreateComplaintPageState extends State<LiveCreateComplaintPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'OTHER';
  String? _flatId;
  bool _submitting = false;
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

  Future<void> _pickImage() async {
    if (_pendingFiles.length >= kComplaintAttachmentMaxCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum $kComplaintAttachmentMaxCount images',
          ),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid image. Use JPEG/PNG/WebP/GIF under 5 MB.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _pendingFiles.add((bytes: bytes, name: file.name, mime: mime));
    });
  }

  String _guessMime(String name, String? reported) {
    if (reported != null &&
        kComplaintAttachmentMimeTypes.contains(reported)) {
      return reported;
    }
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final flatId = _flatId;
    final title = _title.text.trim();
    final description = _description.text.trim();
    if (flatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active flat')),
      );
      return;
    }
    if (title.length < 3 || description.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a title (3+) and description (5+)'),
        ),
      );
      return;
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created ${created.complaintNumber}'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(complaintErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flats = authSession?.residentFlats ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('New complaint')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (flats.length > 1) ...[
            DropdownButtonFormField<String>(
              value: _flatId,
              decoration: const InputDecoration(
                labelText: 'Flat',
                border: OutlineInputBorder(),
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
              onChanged: (v) {
                setState(() => _flatId = v);
                if (v != null) authSession?.selectResidentFlat(v);
              },
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: kComplaintCategories
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(complaintCategoryLabel(c)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? 'OTHER'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const InfoNote(
            'Priority defaults to Medium on the server. '
            'You can attach up to 5 images (JPEG/PNG/WebP/GIF, 5 MB each).',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_outlined),
            label: Text('Add photo (${_pendingFiles.length}/$kComplaintAttachmentMaxCount)'),
          ),
          ..._pendingFiles.map(
            (f) => ListTile(
              dense: true,
              title: Text(f.name),
              subtitle: Text('${(f.bytes.length / 1024).toStringAsFixed(0)} KB'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _pendingFiles.remove(f)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Submitting…' : 'Submit complaint'),
          ),
        ],
      ),
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
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel complaint'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel complaint'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final reason = reasonCtrl.text.trim();
      await ensureLiveRepositories(session.api).complaints.cancelResident(
            c.id,
            reason: reason.isEmpty ? null : reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complaint cancelled')),
      );
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(complaintErrorMessage(e))),
      );
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(Complaint c) async {
    if (_busy) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? 'image/jpeg';
    if (!_clientAttachmentOk(
      mimeType: mime,
      sizeBytes: bytes.length,
      existingCount: c.attachments.length,
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid attachment')),
      );
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
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(complaintErrorMessage(e))),
      );
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
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(a.originalFilename),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Image.memory(Uint8List.fromList(bytes)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(complaintErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint detail')),
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
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final c = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                c.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              Text(
                c.complaintNumber,
                style: const TextStyle(color: C.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusBadge(complaintStatusLabel(c.status)),
                  StatusBadge(complaintPriorityLabel(c.priority)),
                  StatusBadge(complaintCategoryLabel(c.category)),
                ],
              ),
              const SizedBox(height: 16),
              Text(c.description),
              if (c.resolutionNotes != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Resolution',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(c.resolutionNotes!),
              ],
              // Never show internalNotes on resident screens.
              const SizedBox(height: 16),
              const Text(
                'Attachments',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              if (c.attachments.isEmpty)
                const Text('None', style: TextStyle(color: C.muted))
              else
                ...c.attachments.map(
                  (a) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.originalFilename),
                    subtitle: Text(a.mimeType),
                    trailing: const Icon(Icons.image_outlined),
                    onTap: () => _openAttachment(c, a),
                  ),
                ),
              if (c.status == 'OPEN') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _attach(c),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Add photo'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _cancel(c),
                  child: const Text('Cancel complaint'),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'History',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...c.history.map(
                (h) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.action,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _shortIso(h.createdAt),
                          style: const TextStyle(
                            color: C.muted,
                            fontSize: 12,
                          ),
                        ),
                        if (h.publicNotes != null) Text(h.publicNotes!),
                        // Resident never shows h.notes (internal).
                      ],
                    ),
                  ),
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminComplaintsBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading complaints…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final bundle = snapshot.data!;
        final s = bundle.summary;
        final items = bundle.list.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              const Text(
                'Complaints',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _mini('Open', '${s.open}'),
                  _mini('Assigned', '${s.assigned}'),
                  _mini('In progress', '${s.inProgress}'),
                  _mini('High/Urgent', '${s.highAndUrgentOpen}'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All status'),
                    selected: statusFilter == null,
                    onSelected: (_) {
                      setState(() {
                        statusFilter = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  for (final st in kComplaintStatuses)
                    FilterChip(
                      label: Text(complaintStatusLabel(st)),
                      selected: statusFilter == st,
                      onSelected: (_) {
                        setState(() {
                          statusFilter = st;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in [null, ...kComplaintPriorities])
                    FilterChip(
                      label: Text(
                        p == null ? 'All priority' : complaintPriorityLabel(p),
                      ),
                      selected: priorityFilter == p,
                      onSelected: (_) {
                        setState(() {
                          priorityFilter = p;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No complaints')
              else
                ...items.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveAdminComplaintDetailPage(
                              complaintId: c.id,
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
                            c.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${c.complaintNumber} · '
                            '${complaintCategoryLabel(c.category)}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(complaintStatusLabel(c.status)),
                              StatusBadge(complaintPriorityLabel(c.priority)),
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

  Widget _mini(String label, String value) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: C.navy,
            ),
          ),
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
        ],
      ),
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

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(complaintErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(Complaint c) async {
    final session = authSession;
    if (session == null) return;
    final users = await ensureLiveRepositories(session.api).users.listUsers(
          force: true,
          query: const ListUsersQuery(limit: 100),
        );
    if (!mounted) return;
    AdminUser? selected;
    var type = 'INTERNAL';
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Assign complaint'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'INTERNAL', child: Text('Internal')),
                    DropdownMenuItem(value: 'EXTERNAL', child: Text('External')),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? 'INTERNAL'),
                ),
                if (type == 'INTERNAL')
                  DropdownButtonFormField<AdminUser>(
                    value: selected,
                    decoration: const InputDecoration(labelText: 'Assignee'),
                    items: users.items
                        .where(
                          (u) =>
                              u.roles.contains('ADMIN') ||
                              u.roles.contains('OWNER'),
                        )
                        .map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(u.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => selected = v),
                  )
                else
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'External name',
                    ),
                  ),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
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
    });
    nameCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _resolve(Complaint c) async {
    final notesCtrl = TextEditingController();
    final internalCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve complaint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Resolution notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: internalCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Internal notes (admin only)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final session = authSession!;
      final internal = internalCtrl.text.trim();
      await ensureLiveRepositories(session.api).complaints.resolve(
            c.id,
            resolutionNotes: notesCtrl.text.trim(),
            internalNotes: internal.isEmpty ? null : internal,
          );
    });
    notesCtrl.dispose();
    internalCtrl.dispose();
  }

  Future<void> _cancel(Complaint c) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel complaint'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ensureLiveRepositories(authSession!.api).complaints.cancelAdmin(
            c.id,
            reason: reasonCtrl.text.trim(),
          );
    });
    reasonCtrl.dispose();
  }

  Future<void> _setPriority(Complaint c) async {
    String priority = c.priority;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Update priority'),
          content: DropdownButtonFormField<String>(
            value: priority,
            items: kComplaintPriorities
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(complaintPriorityLabel(p)),
                  ),
                )
                .toList(),
            onChanged: (v) => setLocal(() => priority = v ?? priority),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ensureLiveRepositories(authSession!.api)
          .complaints
          .updatePriority(c.id, priority: priority);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint detail')),
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
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final c = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                c.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              Text(c.complaintNumber, style: const TextStyle(color: C.muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusBadge(complaintStatusLabel(c.status)),
                  StatusBadge(complaintPriorityLabel(c.priority)),
                ],
              ),
              const SizedBox(height: 12),
              Text(c.description),
              if (c.assignedToNameSnapshot != null)
                Text('Assignee: ${c.assignedToNameSnapshot}'),
              if (c.internalNotes != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Internal notes',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(c.internalNotes!),
              ],
              if (c.resolutionNotes != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Resolution',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(c.resolutionNotes!),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.status == 'OPEN' ||
                      c.status == 'ASSIGNED' ||
                      c.status == 'IN_PROGRESS')
                    FilledButton(
                      onPressed: _busy ? null : () => _assign(c),
                      child: Text(
                        c.status == 'OPEN' ? 'Assign' : 'Reassign',
                      ),
                    ),
                  if (c.status == 'ASSIGNED')
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await ensureLiveRepositories(authSession!.api)
                                    .complaints
                                    .unassign(c.id);
                              }),
                      child: const Text('Unassign'),
                    ),
                  if (c.status == 'ASSIGNED')
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await ensureLiveRepositories(authSession!.api)
                                    .complaints
                                    .start(c.id);
                              }),
                      child: const Text('Start work'),
                    ),
                  if (c.status == 'IN_PROGRESS')
                    FilledButton(
                      onPressed: _busy ? null : () => _resolve(c),
                      child: const Text('Resolve'),
                    ),
                  if (c.status == 'RESOLVED')
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await ensureLiveRepositories(authSession!.api)
                                    .complaints
                                    .close(c.id);
                              }),
                      child: const Text('Close'),
                    ),
                  if (c.status == 'OPEN' ||
                      c.status == 'ASSIGNED' ||
                      c.status == 'IN_PROGRESS')
                    OutlinedButton(
                      onPressed: _busy ? null : () => _cancel(c),
                      child: const Text('Cancel'),
                    ),
                  if (c.status != 'CLOSED' && c.status != 'CANCELLED')
                    OutlinedButton(
                      onPressed: _busy ? null : () => _setPriority(c),
                      child: const Text('Priority'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Attachments',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              ...c.attachments.map(
                (a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.originalFilename),
                  subtitle: Text('${a.sizeBytes} bytes'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'History',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              ...c.history.map(
                (h) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.action,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _shortIso(h.createdAt),
                          style: const TextStyle(
                            color: C.muted,
                            fontSize: 12,
                          ),
                        ),
                        if (h.publicNotes != null) Text(h.publicNotes!),
                        if (h.notes != null)
                          Text(
                            'Internal: ${h.notes}',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
