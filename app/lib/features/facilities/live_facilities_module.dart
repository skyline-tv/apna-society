import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/common.dart';
import '../../api/models/facility_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

String facilityErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'DUPLICATE_FACILITY':
        return 'A facility with this name already exists.';
      case 'FACILITY_DAY_UNAVAILABLE':
        return 'Facility is not available on this day.';
      case 'BOOKING_DURATION_EXCEEDED':
        return 'Booking exceeds the maximum duration.';
      case 'OUTSIDE_OPENING_HOURS':
        return 'Booking is outside facility opening hours.';
      case 'FACILITY_CAPACITY_FULL':
      case 'CAPACITY_EXCEEDED':
        return 'No remaining confirmed capacity for this slot.';
      case 'BOOKING_CONFLICT':
        return 'Booking conflicts with capacity or schedule.';
      case 'RESIDENTIAL_ACCESS_DENIED':
        return 'Residential facility access is not available for this flat.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this action.';
      case 'INVALID_STATUS_TRANSITION':
        return 'This booking action is not allowed in the current status.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

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

String _feeLine(FacilityBooking b) {
  final fee = moneyPaise(b.feePaiseSnapshot);
  if (b.feePaiseSnapshot <= 0) return 'Fee: free';
  if (b.feePaid) return 'Fee: $fee · paid';
  return 'Fee: $fee · unpaid';
}

// ─── Resident ────────────────────────────────────────────────────────────────

class LiveResidentFacilitiesPage extends StatefulWidget {
  const LiveResidentFacilitiesPage({super.key});

  @override
  State<LiveResidentFacilitiesPage> createState() =>
      _LiveResidentFacilitiesPageState();
}

class _LiveResidentFacilitiesPageState extends State<LiveResidentFacilitiesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<Paged<Facility>> _facilities = _loadFacilities();
  late Future<Paged<FacilityBooking>> _bookings = _loadBookings();
  StreamSubscription<FacilityBookingEventPayload>? _sub;

  Future<Paged<Facility>> _loadFacilities({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).facilities.listResident(
          force: force,
          query: const ListFacilitiesQuery(isActive: true, limit: 50),
        );
  }

  Future<Paged<FacilityBooking>> _loadBookings({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).facilities.listResidentBookings(
          force: force,
          query: const ListFacilityBookingsQuery(limit: 50),
        );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.facilityBookingEvents.listen((_) {
      if (mounted) {
        setState(() {
          _bookings = _loadBookings(force: true);
          _facilities = _loadFacilities(force: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void reload() {
    setState(() {
      _facilities = _loadFacilities(force: true);
      _bookings = _loadBookings(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: C.navy,
          tabs: const [
            Tab(text: 'Facilities'),
            Tab(text: 'My bookings'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _FacilitiesList(
                future: _facilities,
                onReload: reload,
                onOpen: (f) async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          LiveResidentFacilityDetailPage(facilityId: f.id),
                    ),
                  );
                  reload();
                },
              ),
              _BookingsList(
                future: _bookings,
                onReload: reload,
                onOpen: (b) async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveResidentBookingDetailPage(
                        bookingId: b.id,
                      ),
                    ),
                  );
                  reload();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FacilitiesList extends StatelessWidget {
  const _FacilitiesList({
    required this.future,
    required this.onReload,
    required this.onOpen,
  });

  final Future<Paged<Facility>> future;
  final VoidCallback onReload;
  final ValueChanged<Facility> onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Facility>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading facilities…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: onReload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => onReload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              if (items.isEmpty)
                const EmptyState('No active facilities')
              else
                ...items.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => onOpen(f),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${facilityCategoryLabel(f.category)} · '
                            'Capacity ${f.capacity} · '
                            '${f.openingTime}–${f.closingTime}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(
                                f.bookingFeePaise > 0
                                    ? moneyPaise(f.bookingFeePaise)
                                    : 'Free',
                              ),
                              if (f.requiresApproval)
                                const StatusBadge('Needs approval'),
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

class _BookingsList extends StatelessWidget {
  const _BookingsList({
    required this.future,
    required this.onReload,
    required this.onOpen,
  });

  final Future<Paged<FacilityBooking>> future;
  final VoidCallback onReload;
  final ValueChanged<FacilityBooking> onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<FacilityBooking>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading bookings…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: onReload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => onReload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              if (items.isEmpty)
                const EmptyState('No bookings yet')
              else
                ...items.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => onOpen(b),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${b.bookingDate} · ${b.startTime}–${b.endTime}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            _feeLine(b),
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(
                                facilityBookingStatusLabel(b.status),
                              ),
                              if (b.status == 'PENDING' && b.expiresAt != null)
                                StatusBadge(
                                  b.isPendingExpired
                                      ? 'Expiry passed'
                                      : 'Expires ${_shortIso(b.expiresAt)}',
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

class LiveResidentFacilityDetailPage extends StatefulWidget {
  const LiveResidentFacilityDetailPage({super.key, required this.facilityId});
  final String facilityId;

  @override
  State<LiveResidentFacilityDetailPage> createState() =>
      _LiveResidentFacilityDetailPageState();
}

class _LiveResidentFacilityDetailPageState
    extends State<LiveResidentFacilityDetailPage> {
  late Future<Facility> _future = _load();
  FacilityAvailability? _availability;
  String _date = _ymd(DateTime.now());
  bool _loadingAvailability = false;

  Future<Facility> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .facilities
        .getResident(widget.facilityId, force: force);
  }

  Future<void> _loadAvailability() async {
    setState(() => _loadingAvailability = true);
    try {
      final session = authSession!;
      final a = await ensureLiveRepositories(session.api)
          .facilities
          .availability(widget.facilityId, date: _date, force: true);
      if (mounted) setState(() => _availability = a);
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Facility')),
      body: FutureBuilder<Facility>(
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
          final f = snapshot.data!;
          final avail = _availability;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                f.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              Text(
                facilityCategoryLabel(f.category),
                style: const TextStyle(color: C.muted),
              ),
              if (f.description != null) ...[
                const SizedBox(height: 8),
                Text(f.description!),
              ],
              const SizedBox(height: 12),
              Text('Capacity: ${f.capacity}'),
              Text('Hours: ${f.openingTime}–${f.closingTime}'),
              Text(
                'Days: ${f.availableDays.map(weekdayLabel).join(', ')}',
              ),
              Text(
                'Fee: ${f.bookingFeePaise > 0 ? moneyPaise(f.bookingFeePaise) : 'Free'}',
              ),
              Text('Max duration: ${f.maxBookingDurationMinutes} min'),
              if (f.requiresApproval)
                const Text('Bookings require admin approval'),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Availability date: $_date'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) {
                    setState(() => _date = _ymd(picked));
                    await _loadAvailability();
                  }
                },
              ),
              if (_loadingAvailability)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (avail != null) ...[
                Text(
                  'Confirmed ${avail.confirmedCount} / ${avail.capacity} · '
                  'Remaining hint ${avail.remainingCapacityHint}',
                ),
                Text(
                  'Only CONFIRMED bookings consume capacity'
                  '${avail.pendingPolicy.pendingDoesNotConsumeCapacity ? ' (pending does not).' : '.'}',
                  style: const TextStyle(color: C.muted, fontSize: 13),
                ),
                if (avail.confirmedSlots.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Confirmed slots',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ...avail.confirmedSlots.map(
                    (s) => Text('${s.startTime}–${s.endTime}'),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveCreateBookingPage(
                        facility: f,
                        initialDate: _date,
                      ),
                    ),
                  );
                  if (ok == true && mounted) {
                    await _loadAvailability();
                  }
                },
                child: const Text('Book'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LiveCreateBookingPage extends StatefulWidget {
  const LiveCreateBookingPage({
    super.key,
    required this.facility,
    this.initialDate,
  });

  final Facility facility;
  final String? initialDate;

  @override
  State<LiveCreateBookingPage> createState() => _LiveCreateBookingPageState();
}

class _LiveCreateBookingPageState extends State<LiveCreateBookingPage> {
  late String _date = widget.initialDate ?? _ymd(DateTime.now());
  late final _start =
      TextEditingController(text: widget.facility.openingTime);
  late final _end = TextEditingController(
    text: widget.facility.closingTime == widget.facility.openingTime
        ? widget.facility.openingTime
        : widget.facility.closingTime,
  );
  String? _flatId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _flatId = authSession?.selectedResidentFlatId;
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final flatId = _flatId;
    if (flatId == null) {
      _toast(context, 'No active flat');
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).facilities.createBooking(
            widget.facility.id,
            CreateFacilityBookingRequest(
              flatId: flatId,
              bookingDate: _date,
              startTime: _start.text.trim(),
              endTime: _end.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flats = authSession?.residentFlats ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text('Book ${widget.facility.name}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (flats.length > 1)
            DropdownButtonFormField<String>(
              value: _flatId,
              decoration: const InputDecoration(labelText: 'Flat'),
              items: [
                for (final f in flats)
                  DropdownMenuItem(
                    value: f.flat.id,
                    child: Text(f.flat.number),
                  ),
              ],
              onChanged: (v) {
                setState(() => _flatId = v);
                if (v != null) authSession?.selectResidentFlat(v);
              },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date: $_date'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 90)),
              );
              if (picked != null) setState(() => _date = _ymd(picked));
            },
          ),
          TextField(
            controller: _start,
            decoration: InputDecoration(
              labelText: 'Start (HH:mm)',
              helperText:
                  'Facility hours ${widget.facility.openingTime}–${widget.facility.closingTime}',
            ),
          ),
          TextField(
            controller: _end,
            decoration: const InputDecoration(labelText: 'End (HH:mm)'),
          ),
          Text(
            'Fee snapshot will be '
            '${widget.facility.bookingFeePaise > 0 ? moneyPaise(widget.facility.bookingFeePaise) : 'free'} '
            '(unpaid until a payment flow exists).',
            style: const TextStyle(color: C.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Booking…' : 'Submit booking'),
          ),
        ],
      ),
    );
  }
}

class LiveResidentBookingDetailPage extends StatefulWidget {
  const LiveResidentBookingDetailPage({super.key, required this.bookingId});
  final String bookingId;

  @override
  State<LiveResidentBookingDetailPage> createState() =>
      _LiveResidentBookingDetailPageState();
}

class _LiveResidentBookingDetailPageState
    extends State<LiveResidentBookingDetailPage> {
  late Future<FacilityBooking> _future = _load();
  bool _busy = false;

  Future<FacilityBooking> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .facilities
        .getResidentBooking(widget.bookingId, force: force);
  }

  Future<void> _cancel(FacilityBooking b) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel booking'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api).facilities.cancelResidentBooking(
            b.id,
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
          );
      if (mounted) {
        _toast(context, 'Cancelled');
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking')),
      body: FutureBuilder<FacilityBooking>(
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
          final b = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${b.bookingDate} · ${b.startTime}–${b.endTime}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              StatusBadge(facilityBookingStatusLabel(b.status)),
              const SizedBox(height: 12),
              Text(_feeLine(b)),
              if (b.feePaymentRequired)
                const Text(
                  'Payment gateway is not integrated in this phase.',
                  style: TextStyle(color: C.muted, fontSize: 13),
                ),
              if (b.expiresAt != null)
                Text(
                  b.isPendingExpired
                      ? 'Pending expiry has passed (server may mark cancelled)'
                      : 'Pending expires: ${_shortIso(b.expiresAt)}',
                ),
              if (b.rejectionReason != null)
                Text('Rejection: ${b.rejectionReason}'),
              if (b.cancellationReason != null)
                Text('Cancellation: ${b.cancellationReason}'),
              const SizedBox(height: 20),
              if (b.status == 'PENDING' || b.status == 'CONFIRMED')
                OutlinedButton(
                  onPressed: _busy ? null : () => _cancel(b),
                  child: const Text('Cancel booking'),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Admin facilities ────────────────────────────────────────────────────────

class LiveAdminFacilitiesPage extends StatefulWidget {
  const LiveAdminFacilitiesPage({super.key});

  @override
  State<LiveAdminFacilitiesPage> createState() =>
      _LiveAdminFacilitiesPageState();
}

class _LiveAdminFacilitiesPageState extends State<LiveAdminFacilitiesPage> {
  bool? activeFilter;
  late Future<Paged<Facility>> _future = _load();

  Future<Paged<Facility>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).facilities.listAdmin(
          force: force,
          query: ListFacilitiesQuery(isActive: activeFilter, limit: 50),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Facility>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading facilities…');
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
                      'Facilities',
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
                          builder: (_) => const LiveFacilityFormPage(),
                        ),
                      );
                      if (ok == true) reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: activeFilter == null,
                    onSelected: (_) {
                      setState(() {
                        activeFilter = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Active'),
                    selected: activeFilter == true,
                    onSelected: (_) {
                      setState(() {
                        activeFilter = true;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Inactive'),
                    selected: activeFilter == false,
                    onSelected: (_) {
                      setState(() {
                        activeFilter = false;
                        _future = _load(force: true);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No facilities')
              else
                ...items.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveAdminFacilityDetailPage(facilityId: f.id),
                          ),
                        );
                        reload();
                      },
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${facilityCategoryLabel(f.category)} · '
                            'cap ${f.capacity} · '
                            '${moneyPaise(f.bookingFeePaise)}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StatusBadge(f.isActive ? 'Active' : 'Inactive'),
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

class LiveAdminFacilityDetailPage extends StatefulWidget {
  const LiveAdminFacilityDetailPage({super.key, required this.facilityId});
  final String facilityId;

  @override
  State<LiveAdminFacilityDetailPage> createState() =>
      _LiveAdminFacilityDetailPageState();
}

class _LiveAdminFacilityDetailPageState
    extends State<LiveAdminFacilityDetailPage> {
  late Future<Facility> _future = _load();
  bool _busy = false;

  Future<Facility> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .facilities
        .getAdmin(widget.facilityId, force: force);
  }

  Future<void> _toggle(Facility f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .facilities
          .setActive(f.id, isActive: !f.isActive);
      if (mounted) {
        _toast(context, f.isActive ? 'Deactivated' : 'Activated');
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Facility')),
      body: FutureBuilder<Facility>(
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
          final f = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                f.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              StatusBadge(f.isActive ? 'Active' : 'Inactive'),
              const SizedBox(height: 12),
              Text('Category: ${facilityCategoryLabel(f.category)}'),
              Text('Capacity: ${f.capacity}'),
              Text('Fee: ${moneyPaise(f.bookingFeePaise)}'),
              Text('Hours: ${f.openingTime}–${f.closingTime}'),
              Text('Max duration: ${f.maxBookingDurationMinutes} min'),
              Text(
                'Approval required: ${f.requiresApproval ? 'Yes' : 'No'}',
              ),
              Text('Days: ${f.availableDays.map(weekdayLabel).join(', ')}'),
              if (f.location != null) Text('Location: ${f.location}'),
              if (f.description != null) Text(f.description!),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveFacilityFormPage(existing: f),
                          ),
                        );
                        if (ok == true && mounted) {
                          setState(() => _future = _load(force: true));
                        }
                      },
                child: const Text('Edit'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _toggle(f),
                child: Text(f.isActive ? 'Deactivate' : 'Activate'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LiveFacilityFormPage extends StatefulWidget {
  const LiveFacilityFormPage({super.key, this.existing});
  final Facility? existing;

  @override
  State<LiveFacilityFormPage> createState() => _LiveFacilityFormPageState();
}

class _LiveFacilityFormPageState extends State<LiveFacilityFormPage> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description =
      TextEditingController(text: widget.existing?.description);
  late final _location =
      TextEditingController(text: widget.existing?.location);
  late final _capacity = TextEditingController(
    text: '${widget.existing?.capacity ?? 10}',
  );
  late final _fee = TextEditingController(
    text: '${widget.existing?.bookingFeePaise ?? 0}',
  );
  late final _maxDuration = TextEditingController(
    text: '${widget.existing?.maxBookingDurationMinutes ?? 120}',
  );
  late final _open =
      TextEditingController(text: widget.existing?.openingTime ?? '06:00');
  late final _close =
      TextEditingController(text: widget.existing?.closingTime ?? '22:00');
  late String _category = widget.existing?.category ?? 'OTHER';
  late bool _bookingRequired = widget.existing?.bookingRequired ?? true;
  late bool _requiresApproval = widget.existing?.requiresApproval ?? true;
  late Set<String> _days =
      {...(widget.existing?.availableDays ?? kWeekdays)};
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _location.dispose();
    _capacity.dispose();
    _fee.dispose();
    _maxDuration.dispose();
    _open.dispose();
    _close.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _name.text.trim();
    final capacity = int.tryParse(_capacity.text.trim());
    final fee = int.tryParse(_fee.text.trim());
    final maxDur = int.tryParse(_maxDuration.text.trim());
    if (name.isEmpty || capacity == null || fee == null || maxDur == null) {
      _toast(context, 'Enter name, capacity, fee (paise), and max duration');
      return;
    }
    if (_days.isEmpty) {
      _toast(context, 'Select at least one available day');
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repo = ensureLiveRepositories(session.api).facilities;
      if (widget.existing == null) {
        await repo.createFacility(
          CreateFacilityRequest(
            name: name,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            category: _category,
            location:
                _location.text.trim().isEmpty ? null : _location.text.trim(),
            capacity: capacity,
            bookingRequired: _bookingRequired,
            requiresApproval: _requiresApproval,
            maxBookingDurationMinutes: maxDur,
            openingTime: _open.text.trim(),
            closingTime: _close.text.trim(),
            availableDays: _days.toList(),
            bookingFeePaise: fee,
          ),
        );
      } else {
        await repo.updateFacility(
          widget.existing!.id,
          UpdateFacilityRequest(
            name: name,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            category: _category,
            location:
                _location.text.trim().isEmpty ? null : _location.text.trim(),
            capacity: capacity,
            bookingRequired: _bookingRequired,
            requiresApproval: _requiresApproval,
            maxBookingDurationMinutes: maxDur,
            openingTime: _open.text.trim(),
            closingTime: _close.text.trim(),
            availableDays: _days.toList(),
            bookingFeePaise: fee,
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit facility' : 'Create facility'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLines: 2,
          ),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in kFacilityCategories)
                DropdownMenuItem(
                  value: c,
                  child: Text(facilityCategoryLabel(c)),
                ),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          TextField(
            controller: _capacity,
            decoration: const InputDecoration(labelText: 'Capacity'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _fee,
            decoration: const InputDecoration(
              labelText: 'Booking fee (paise)',
              helperText: 'Integer paise from backend; 0 = free',
            ),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _maxDuration,
            decoration: const InputDecoration(
              labelText: 'Max booking duration (minutes)',
            ),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _open,
            decoration: const InputDecoration(labelText: 'Opening (HH:mm)'),
          ),
          TextField(
            controller: _close,
            decoration: const InputDecoration(labelText: 'Closing (HH:mm)'),
          ),
          SwitchListTile(
            title: const Text('Booking required'),
            value: _bookingRequired,
            onChanged: (v) => setState(() => _bookingRequired = v),
          ),
          SwitchListTile(
            title: const Text('Requires approval'),
            value: _requiresApproval,
            onChanged: (v) => setState(() => _requiresApproval = v),
          ),
          const SizedBox(height: 8),
          const Text('Available days', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 8,
            children: [
              for (final d in kWeekdays)
                FilterChip(
                  label: Text(weekdayLabel(d)),
                  selected: _days.contains(d),
                  onSelected: (sel) {
                    setState(() {
                      if (sel) {
                        _days.add(d);
                      } else {
                        _days.remove(d);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

// ─── Admin bookings ──────────────────────────────────────────────────────────

class LiveAdminFacilityBookingsPage extends StatefulWidget {
  const LiveAdminFacilityBookingsPage({super.key});

  @override
  State<LiveAdminFacilityBookingsPage> createState() =>
      _LiveAdminFacilityBookingsPageState();
}

class _LiveAdminFacilityBookingsPageState
    extends State<LiveAdminFacilityBookingsPage> {
  String? status;
  late Future<Paged<FacilityBooking>> _future = _load();

  Future<Paged<FacilityBooking>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).facilities.listAdminBookings(
          force: force,
          query: ListFacilityBookingsQuery(status: status, limit: 50),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<FacilityBooking>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading bookings…');
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
              const Text(
                'Facility bookings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
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
                  for (final s in kFacilityBookingStatuses)
                    FilterChip(
                      label: Text(facilityBookingStatusLabel(s)),
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
                const EmptyState('No bookings')
              else
                ...items.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveAdminBookingDetailPage(
                              bookingId: b.id,
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
                            '${b.bookingDate} · ${b.startTime}–${b.endTime}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${_feeLine(b)} · Flat ${b.flatId}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(
                                facilityBookingStatusLabel(b.status),
                              ),
                              if (b.status == 'PENDING' && b.expiresAt != null)
                                StatusBadge(
                                  'Expires ${_shortIso(b.expiresAt)}',
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

class LiveAdminBookingDetailPage extends StatefulWidget {
  const LiveAdminBookingDetailPage({super.key, required this.bookingId});
  final String bookingId;

  @override
  State<LiveAdminBookingDetailPage> createState() =>
      _LiveAdminBookingDetailPageState();
}

class _LiveAdminBookingDetailPageState
    extends State<LiveAdminBookingDetailPage> {
  late Future<FacilityBooking> _future = _load();
  bool _busy = false;

  Future<FacilityBooking> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .facilities
        .getAdminBooking(widget.bookingId, force: force);
  }

  Future<void> _approve(FacilityBooking b) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .facilities
          .approveBooking(b.id);
      if (mounted) {
        _toast(context, 'Approved');
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(FacilityBooking b) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject booking'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason (required)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    final reason = reasonCtrl.text.trim();
    if (reason.length < 3) {
      _toast(context, 'Reason must be at least 3 characters');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .facilities
          .rejectBooking(b.id, reason: reason);
      if (mounted) {
        _toast(context, 'Rejected');
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(FacilityBooking b) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel booking'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
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
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api).facilities.cancelAdminBooking(
            b.id,
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
          );
      if (mounted) {
        _toast(context, 'Cancelled');
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) _toast(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking admin')),
      body: FutureBuilder<FacilityBooking>(
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
          final b = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${b.bookingDate} · ${b.startTime}–${b.endTime}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              StatusBadge(facilityBookingStatusLabel(b.status)),
              const SizedBox(height: 12),
              Text('Facility: ${b.facilityId}'),
              Text('Flat: ${b.flatId}'),
              Text('Booked by: ${b.bookedByUserId}'),
              Text(_feeLine(b)),
              if (b.adminNotes != null) Text('Admin notes: ${b.adminNotes}'),
              if (b.expiresAt != null)
                Text('Pending expires: ${_shortIso(b.expiresAt)}'),
              if (b.rejectionReason != null)
                Text('Rejection: ${b.rejectionReason}'),
              if (b.cancellationReason != null)
                Text('Cancellation: ${b.cancellationReason}'),
              const SizedBox(height: 20),
              if (b.status == 'PENDING') ...[
                FilledButton(
                  onPressed: _busy ? null : () => _approve(b),
                  child: const Text('Approve'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _reject(b),
                  child: const Text('Reject'),
                ),
                const SizedBox(height: 8),
              ],
              if (b.status == 'PENDING' || b.status == 'CONFIRMED')
                OutlinedButton(
                  onPressed: _busy ? null : () => _cancel(b),
                  child: const Text('Cancel'),
                ),
            ],
          );
        },
      ),
    );
  }
}
