import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/common.dart';
import '../../api/models/facility_models.dart';
import '../../api/models/society_models.dart';
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

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _feeLabel(int paise) => paise > 0 ? moneyPaise(paise) : 'Free';

String _slotLabel(FacilityBooking b) =>
    '${fmtYmd(b.bookingDate)} · ${b.startTime}–${b.endTime}';

IconData _categoryIcon(String category) {
  switch (category.toUpperCase()) {
    case 'GYM':
      return Icons.fitness_center_rounded;
    case 'SWIMMING_POOL':
    case 'POOL':
      return Icons.pool_rounded;
    case 'CLUBHOUSE':
    case 'CLUB_HOUSE':
      return Icons.celebration_outlined;
    case 'HALL':
    case 'BANQUET_HALL':
    case 'COMMUNITY_HALL':
      return Icons.meeting_room_outlined;
    case 'SPORTS':
    case 'COURT':
    case 'TENNIS_COURT':
    case 'BADMINTON_COURT':
      return Icons.sports_tennis_rounded;
    case 'GARDEN':
    case 'PARK':
      return Icons.park_outlined;
    case 'PLAY_AREA':
    case 'KIDS_PLAY_AREA':
      return Icons.child_care_rounded;
    case 'GUEST_ROOM':
      return Icons.hotel_outlined;
    case 'PARKING':
      return Icons.local_parking_outlined;
    default:
      return Icons.apartment_outlined;
  }
}

BadgeTone _bookingTone(String status) {
  switch (status.toUpperCase()) {
    case 'CONFIRMED':
      return BadgeTone.success;
    case 'PENDING':
      return BadgeTone.warning;
    case 'REJECTED':
    case 'EXPIRED':
      return BadgeTone.danger;
    case 'CANCELLED':
    case 'COMPLETED':
      return BadgeTone.neutral;
    default:
      return toneForStatus(status);
  }
}

Widget _emptyScrollable(Widget child, Future<void> Function() onRefresh) =>
    RefreshIndicator(
      color: C.blue,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [const SizedBox(height: 60), child],
      ),
    );

class _FacilityRow extends StatelessWidget {
  const _FacilityRow({
    required this.facility,
    required this.onTap,
    this.showActive = false,
  });
  final Facility facility;
  final VoidCallback onTap;
  final bool showActive;

  @override
  Widget build(BuildContext context) {
    final f = facility;
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        icon: _categoryIcon(f.category),
        square: true,
        color: f.isActive ? C.blue : C.muted,
      ),
      title: f.name,
      subtitle: '${facilityCategoryLabel(f.category)} · '
          'Capacity ${f.capacity} · ${f.openingTime}–${f.closingTime}',
      badges: [
        StatusBadge(_feeLabel(f.bookingFeePaise),
            tone: f.bookingFeePaise > 0 ? BadgeTone.info : BadgeTone.success,
            icon: f.bookingFeePaise > 0 ? Icons.currency_rupee_rounded : null),
        if (f.requiresApproval)
          const StatusBadge('Needs approval',
              tone: BadgeTone.neutral, icon: Icons.how_to_reg_outlined),
        if (showActive && !f.isActive) const StatusBadge('Inactive'),
      ],
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({
    required this.booking,
    required this.onTap,
    this.facilityName,
    this.flatLabel,
  });
  final FacilityBooking booking;
  final VoidCallback onTap;
  final String? facilityName;
  final String? flatLabel;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final parts = <String>[
      if (facilityName != null) facilityName!,
      if (flatLabel != null) 'Flat $flatLabel',
      if (b.feePaiseSnapshot > 0)
        '${moneyPaise(b.feePaiseSnapshot)} · ${b.feePaid ? 'paid' : 'unpaid'}'
      else
        'Free',
    ];
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        icon: Icons.event_available_outlined,
        square: true,
        color: badgeColors(_bookingTone(b.status)).fg,
      ),
      title: _slotLabel(b),
      subtitle: parts.join(' · '),
      badges: [
        StatusBadge(facilityBookingStatusLabel(b.status),
            tone: _bookingTone(b.status)),
        if (b.status == 'PENDING' && b.expiresAt != null)
          StatusBadge(
            b.isPendingExpired
                ? 'Expiry passed'
                : 'Expires ${fmtIsoDateTime(b.expiresAt)}',
            tone: b.isPendingExpired ? BadgeTone.danger : BadgeTone.neutral,
            icon: Icons.timer_outlined,
          ),
      ],
    );
  }
}

class _BookingDetails extends StatelessWidget {
  const _BookingDetails({
    required this.booking,
    this.facilityName,
    this.flatLabel,
    this.bookedBy,
    this.showAdminNotes = false,
  });
  final FacilityBooking booking;
  final String? facilityName;
  final String? flatLabel;
  final String? bookedBy;
  final bool showAdminNotes;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppAvatar(
          icon: Icons.event_available_outlined,
          square: true,
          size: Sz.avatarLg,
          color: badgeColors(_bookingTone(b.status)).fg,
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (facilityName != null) Text(facilityName!, style: T.h2),
            Text(fmtYmd(b.bookingDate),
                style: facilityName == null ? T.h2 : T.body),
            const SizedBox(height: 2),
            Text('${b.startTime} – ${b.endTime}', style: T.secondary),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        StatusBadge(facilityBookingStatusLabel(b.status),
            tone: _bookingTone(b.status)),
        StatusBadge(
          b.feePaiseSnapshot <= 0
              ? 'Free'
              : (b.feePaid ? 'Fee paid' : 'Fee unpaid'),
          tone: b.feePaiseSnapshot <= 0 || b.feePaid
              ? BadgeTone.success
              : BadgeTone.warning,
        ),
      ]),
      const SizedBox(height: 18),
      if (b.status == 'PENDING' && b.expiresAt != null)
        InfoNote(
          b.isPendingExpired
              ? 'The pending window has passed. The server may mark this booking cancelled.'
              : 'Awaiting approval. This request expires on ${fmtIsoDateTime(b.expiresAt)} if not approved.',
          tone: b.isPendingExpired ? NoteTone.warning : NoteTone.info,
          icon: Icons.timer_outlined,
        ),
      if (b.rejectionReason != null && b.rejectionReason!.trim().isNotEmpty)
        InfoNote('Rejected: ${b.rejectionReason}',
            tone: NoteTone.danger, icon: Icons.block_outlined),
      if (b.cancellationReason != null &&
          b.cancellationReason!.trim().isNotEmpty)
        InfoNote('Cancelled: ${b.cancellationReason}',
            tone: NoteTone.warning, icon: Icons.cancel_outlined),
      DetailCard(title: 'Booking', children: [
        if (flatLabel != null) DetailRow('Flat', flatLabel!),
        if (bookedBy != null) DetailRow('Booked by', bookedBy!),
        DetailRow('Date', fmtYmd(b.bookingDate)),
        DetailRow('Time', '${b.startTime} – ${b.endTime}'),
        DetailRow('Requested on', fmtIsoDateTime(b.createdAt)),
      ]),
      DetailCard(title: 'Fee', children: [
        DetailRow('Booking fee', _feeLabel(b.feePaiseSnapshot),
            emphasize: true),
        if (b.feePaiseSnapshot > 0)
          DetailRow('Payment', b.feePaid ? 'Paid' : 'Not paid'),
        if (b.paymentReference != null && b.paymentReference!.isNotEmpty)
          DetailRow('Reference', b.paymentReference!),
      ]),
      if (showAdminNotes &&
          b.adminNotes != null &&
          b.adminNotes!.trim().isNotEmpty)
        DetailCard(title: 'Admin notes', children: [
          Text(b.adminNotes!, style: T.body),
        ]),
    ]);
  }
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

  Future<void> _refresh() async {
    reload();
    await Future.wait([_facilities, _bookings]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: C.surface,
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Facilities'),
              Tab(text: 'My bookings'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _FacilitiesList(
                future: _facilities,
                onRefresh: _refresh,
                onOpen: (f) async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          LiveResidentFacilityDetailPage(facilityId: f.id),
                    ),
                  );
                  if (mounted) reload();
                },
              ),
              _BookingsList(
                future: _bookings,
                facilities: _facilities,
                onRefresh: _refresh,
                onBrowse: () => _tabs.animateTo(0),
                onOpen: (b) async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveResidentBookingDetailPage(
                        bookingId: b.id,
                      ),
                    ),
                  );
                  if (mounted) reload();
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
    required this.onRefresh,
    required this.onOpen,
  });

  final Future<Paged<Facility>> future;
  final Future<void> Function() onRefresh;
  final ValueChanged<Facility> onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Facility>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 5);
        }
        if (snapshot.hasError) {
          return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load facilities',
              onRetry: onRefresh);
        }
        final items = snapshot.data!.items;
        if (items.isEmpty) {
          return _emptyScrollable(
            const EmptyState('No facilities available for booking right now',
                icon: Icons.apartment_outlined),
            onRefresh,
          );
        }
        return RefreshIndicator(
          color: C.blue,
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: Sp.pagePadding,
            children: [
              ResultCount(items.length, 'facility'),
              for (final f in items)
                _FacilityRow(facility: f, onTap: () => onOpen(f)),
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
    required this.facilities,
    required this.onRefresh,
    required this.onOpen,
    required this.onBrowse,
  });

  final Future<Paged<FacilityBooking>> future;
  final Future<Paged<Facility>> facilities;
  final Future<void> Function() onRefresh;
  final ValueChanged<FacilityBooking> onOpen;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<FacilityBooking>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 5);
        }
        if (snapshot.hasError) {
          return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load bookings',
              onRetry: onRefresh);
        }
        final items = snapshot.data!.items;
        if (items.isEmpty) {
          return _emptyScrollable(
            EmptyState(
              'No bookings yet',
              icon: Icons.event_available_outlined,
              actionLabel: 'Browse facilities',
              onAction: onBrowse,
            ),
            onRefresh,
          );
        }
        return FutureBuilder<Paged<Facility>>(
          future: facilities,
          builder: (context, facSnap) {
            final names = <String, String>{
              for (final f in facSnap.data?.items ?? const <Facility>[])
                f.id: f.name,
            };
            final upcoming = items
                .where((b) => b.status == 'PENDING' || b.status == 'CONFIRMED')
                .toList();
            final past = items
                .where((b) => b.status != 'PENDING' && b.status != 'CONFIRMED')
                .toList();
            return RefreshIndicator(
              color: C.blue,
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: Sp.pagePadding,
                children: [
                  if (upcoming.isNotEmpty) ...[
                    const SectionTitle('Upcoming'),
                    for (final b in upcoming)
                      _BookingRow(
                        booking: b,
                        facilityName: names[b.facilityId],
                        onTap: () => onOpen(b),
                      ),
                  ],
                  if (past.isNotEmpty) ...[
                    if (upcoming.isNotEmpty) const SizedBox(height: 10),
                    const SectionTitle('Past & closed'),
                    for (final b in past)
                      _BookingRow(
                        booking: b,
                        facilityName: names[b.facilityId],
                        onTap: () => onOpen(b),
                      ),
                  ],
                ],
              ),
            );
          },
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
  String? _availabilityError;

  Future<Facility> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .facilities
        .getResident(widget.facilityId, force: force);
  }

  Future<void> _loadAvailability() async {
    setState(() {
      _loadingAvailability = true;
      _availabilityError = null;
    });
    try {
      final session = authSession!;
      final a = await ensureLiveRepositories(session.api)
          .facilities
          .availability(widget.facilityId, date: _date, force: true);
      if (mounted) setState(() => _availability = a);
    } catch (e) {
      if (mounted) setState(() => _availabilityError = facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _pickDate() async {
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
  }

  Future<void> _book(Facility f) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveCreateBookingPage(facility: f, initialDate: _date),
      ),
    );
    if (ok == true && mounted) {
      showSuccessSnack(
          context,
          f.requiresApproval
              ? 'Booking requested. You will be notified once approved.'
              : 'Booking confirmed.');
      await _loadAvailability();
    }
  }

  Widget _availabilityCard(Facility f) {
    final avail = _availability;
    final selectedDay = DateTime.tryParse(_date);
    final weekdayKey =
        selectedDay == null ? null : kWeekdays[selectedDay.weekday - 1];
    final dayUnavailable =
        weekdayKey != null && !f.availableDays.contains(weekdayKey);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Availability', subtitle: 'Capacity for ${fmtYmd(_date)}'),
      PickerField(
        label: 'Date',
        value: fmtYmd(_date),
        onTap: _pickDate,
      ),
      const SizedBox(height: 12),
      if (_loadingAvailability)
        const LinearProgressIndicator(minHeight: 3)
      else if (_availabilityError != null)
        Row(children: [
          Expanded(
              child: Text(_availabilityError!,
                  style: T.secondary.copyWith(color: C.error))),
          TextButton(onPressed: _loadAvailability, child: const Text('Retry')),
        ])
      else if (avail != null) ...[
        MetricBand(items: [
          MetricItem(
            'Confirmed',
            '${avail.confirmedCount}/${avail.capacity}',
            valueColor: avail.remainingCapacityHint > 0 ? C.green : C.error,
          ),
          MetricItem(
            'Slots left',
            '${avail.remainingCapacityHint}',
            valueColor: avail.remainingCapacityHint > 0 ? C.green : C.error,
          ),
          MetricItem('Hours', '${f.openingTime}–${f.closingTime}'),
          MetricItem('Max duration', '${f.maxBookingDurationMinutes} min'),
        ]),
        const SizedBox(height: 8),
        Text(
          'Only confirmed bookings count towards capacity'
          '${avail.pendingPolicy.pendingDoesNotConsumeCapacity ? '; pending requests do not.' : '.'}',
          style: T.caption,
        ),
        if (avail.confirmedSlots.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Booked slots on this day', style: T.label),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in avail.confirmedSlots)
              StatusBadge('${s.startTime}–${s.endTime}',
                  tone: BadgeTone.neutral, icon: Icons.schedule_rounded),
          ]),
        ],
      ],
      if (dayUnavailable) ...[
        const SizedBox(height: 10),
        const InfoNote('This facility is closed on the selected day.',
            tone: NoteTone.warning),
      ],
    ]);
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
            return const LoadingView(label: 'Loading facility…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load facility',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final f = snapshot.data!;
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                color: C.blue,
                onRefresh: () async {
                  setState(() => _future = _load(force: true));
                  await Future.wait([_future, _loadAvailability()]);
                },
                child: ListView(
                  padding: Sp.pagePadding,
                  children: [
                    DetailHero(
                      title: f.name,
                      subtitle: [
                        facilityCategoryLabel(f.category),
                        if (f.location != null &&
                            f.location!.trim().isNotEmpty)
                          f.location!,
                      ].join(' · '),
                      leading: AppAvatar(
                        icon: _categoryIcon(f.category),
                        square: true,
                        size: Sz.avatarLg,
                      ),
                      badges: [
                        StatusBadge(_feeLabel(f.bookingFeePaise),
                            tone: f.bookingFeePaise > 0
                                ? BadgeTone.info
                                : BadgeTone.success),
                        if (f.requiresApproval)
                          const StatusBadge('Needs approval',
                              tone: BadgeTone.neutral,
                              icon: Icons.how_to_reg_outlined),
                      ],
                    ),
                    if (f.description != null &&
                        f.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(f.description!, style: T.body),
                    ],
                    const SizedBox(height: 18),
                    _availabilityCard(f),
                    const SizedBox(height: 18),
                    DetailCard(title: 'Details', children: [
                      DetailRow('Hours', '${f.openingTime} – ${f.closingTime}'),
                      DetailRow('Open on',
                          f.availableDays.map(weekdayLabel).join(', ')),
                      DetailRow('Capacity', '${f.capacity}'),
                      DetailRow('Max duration',
                          '${f.maxBookingDurationMinutes} minutes'),
                      DetailRow('Booking fee', _feeLabel(f.bookingFeePaise),
                          emphasize: f.bookingFeePaise > 0),
                      DetailRow('Approval',
                          f.requiresApproval ? 'Required' : 'Not required'),
                    ]),
                  ],
                ),
              ),
            ),
            BottomActionBar(children: [
              PrimaryButton(
                label: f.requiresApproval ? 'Request booking' : 'Book now',
                icon: Icons.event_available_outlined,
                onPressed: () => _book(f),
              ),
            ]),
          ]);
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
  late final _start = TextEditingController(text: widget.facility.openingTime);
  late final _end = TextEditingController(
    text: widget.facility.closingTime == widget.facility.openingTime
        ? widget.facility.openingTime
        : widget.facility.closingTime,
  );
  String? _flatId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _flatId = authSession?.selectedResidentFlatId;
    _start.addListener(_onTimesChanged);
    _end.addListener(_onTimesChanged);
  }

  void _onTimesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _start.removeListener(_onTimesChanged);
    _end.removeListener(_onTimesChanged);
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  int? _minutes(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  String? _durationLabel() {
    final s = _minutes(_start.text);
    final e = _minutes(_end.text);
    if (s == null || e == null || e <= s) return null;
    final d = e - s;
    final h = d ~/ 60;
    final m = d % 60;
    return [if (h > 0) '$h h', if (m > 0) '$m min'].join(' ');
  }

  String? _flatLabel() {
    final flatId = _flatId;
    if (flatId == null) return null;
    final flats = authSession?.residentFlats ?? const [];
    for (final fl in flats) {
      if (fl.flat.id == flatId) {
        return fl.flat.label;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    final flatId = _flatId;
    if (flatId == null) {
      setState(() => _error = 'Select the flat this booking is for.');
      return;
    }
    final s = _minutes(_start.text);
    final e = _minutes(_end.text);
    if (s == null || e == null) {
      setState(() => _error = 'Enter start and end time as HH:mm.');
      return;
    }
    if (e <= s) {
      setState(() => _error = 'End time must be after the start time.');
      return;
    }
    final f = widget.facility;
    final duration = _durationLabel();
    final ok = await confirmDialog(
      context,
      title: f.requiresApproval ? 'Request this booking?' : 'Confirm booking?',
      message:
          '${f.name} on ${fmtYmd(_date)}, ${_start.text.trim()}–${_end.text.trim()}'
          '${duration != null ? ' ($duration)' : ''}'
          '${_flatLabel() != null ? ' for flat ${_flatLabel()}' : ''}. '
          '${f.requiresApproval ? 'An admin must approve before the slot is confirmed.' : 'The slot will be confirmed immediately.'}',
      confirmLabel: f.requiresApproval ? 'Request booking' : 'Confirm booking',
      icon: Icons.event_available_outlined,
    );
    if (!ok || !mounted) return;
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
      if (mounted) setState(() => _error = facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.facility;
    final flats = authSession?.residentFlats ?? const [];
    final duration = _durationLabel();
    return FormScaffold(
      title: 'Book ${f.name}',
      bottom: PrimaryButton(
        label: f.requiresApproval ? 'Request booking' : 'Confirm booking',
        icon: Icons.check_rounded,
        busy: _submitting,
        onPressed: _submit,
      ),
      children: [
        if (flats.length > 1) ...[
          const FormSectionLabel('Flat'),
          DropdownButtonFormField<String>(
            initialValue: _flatId,
            decoration: const InputDecoration(
              labelText: 'Flat',
              prefixIcon: Icon(Icons.apartment_outlined),
            ),
            items: [
              for (final fl in flats)
                DropdownMenuItem(
                  value: fl.flat.id,
                  child:
                      Text(fl.flat.label),
                ),
            ],
            onChanged: _submitting
                ? null
                : (v) {
                    setState(() => _flatId = v);
                    if (v != null) authSession?.selectResidentFlat(v);
                  },
          ),
          const SizedBox(height: 20),
        ],
        const FormSectionLabel('When'),
        PickerField(
          label: 'Date',
          value: fmtYmd(_date),
          enabled: !_submitting,
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
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TimeField(
              controller: _start,
              label: 'Start',
              enabled: !_submitting,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TimeField(
              controller: _end,
              label: 'End',
              enabled: !_submitting,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Open ${f.openingTime}–${f.closingTime} · max ${f.maxBookingDurationMinutes} min'
          '${duration != null ? ' · selected $duration' : ''}',
          style: T.caption,
        ),
        const SizedBox(height: 18),
        ReviewSummary(
          title: 'Booking summary',
          rows: [
            ('Facility', f.name),
            ('Date', fmtYmd(_date)),
            ('Time', '${_start.text.trim()}–${_end.text.trim()}'),
            if (duration != null) ('Duration', duration),
            if (_flatLabel() != null) ('Flat', _flatLabel()!),
            ('Booking fee', _feeLabel(f.bookingFeePaise)),
            ('Approval', f.requiresApproval ? 'Required' : 'Instant'),
          ],
          note: f.bookingFeePaise > 0
              ? 'The booking fee is recorded with your request. Online payment for facility fees is not available in the app; settle it with the society office.'
              : null,
        ),
        InlineError(_error),
      ],
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
  final Map<String, String> _facilityNames = {};
  bool _busy = false;

  Future<FacilityBooking> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repo = ensureLiveRepositories(session.api).facilities;
    final booking =
        await repo.getResidentBooking(widget.bookingId, force: force);
    if (!_facilityNames.containsKey(booking.facilityId)) {
      try {
        final f = await repo.getResident(booking.facilityId);
        _facilityNames[booking.facilityId] = f.name;
      } catch (_) {
        // Name is decorative; the booking still renders without it.
      }
    }
    return booking;
  }

  Future<void> _cancel(FacilityBooking b) async {
    if (_busy) return;
    final reason = await promptTextDialog(
      context,
      title: 'Cancel this booking?',
      message: 'Your slot on ${fmtYmd(b.bookingDate)} will be released.',
      label: 'Reason (optional)',
      confirmLabel: 'Cancel booking',
      cancelLabel: 'Keep it',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final trimmed = reason.trim();
      await ensureLiveRepositories(session.api)
          .facilities
          .cancelResidentBooking(
            b.id,
            reason: trimmed.isEmpty ? null : trimmed,
          );
      if (mounted) {
        showAppSnack(context, 'Booking cancelled.', tone: SnackTone.warning);
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, facilityErrorMessage(e));
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
            return const LoadingView(label: 'Loading booking…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load booking',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final b = snapshot.data!;
          final canCancel = b.status == 'PENDING' || b.status == 'CONFIRMED';
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                _BookingDetails(
                  booking: b,
                  facilityName: _facilityNames[b.facilityId],
                ),
                if (canCancel) ...[
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label: 'Cancel booking',
                    icon: Icons.cancel_outlined,
                    destructive: true,
                    busy: _busy,
                    onPressed: () => _cancel(b),
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

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  Future<void> _create() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveFacilityFormPage()),
    );
    if (ok == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-facility',
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add facility'),
      ),
      body: FutureBuilder<Paged<Facility>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 5, showHeader: true);
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load facilities',
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
                const PageHeader('Facilities',
                    subtitle: 'Amenities residents can book'),
                FilterBar(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final f in const [
                      (null, 'All'),
                      (true, 'Active'),
                      (false, 'Inactive'),
                    ])
                      AppFilterChip(
                        label: f.$2,
                        selected: activeFilter == f.$1,
                        onSelected: () => setState(() {
                          activeFilter = f.$1;
                          _future = _load(force: true);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  EmptyState(
                    activeFilter == null
                        ? 'No facilities yet'
                        : 'No ${activeFilter! ? 'active' : 'inactive'} facilities',
                    icon: Icons.apartment_outlined,
                    actionLabel: activeFilter == null ? 'Add a facility' : null,
                    onAction: _create,
                  )
                else ...[
                  ResultCount(items.length, 'facility'),
                  for (final f in items)
                    _FacilityRow(
                      facility: f,
                      showActive: true,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveAdminFacilityDetailPage(facilityId: f.id),
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
    final ok = await confirmDialog(
      context,
      title: f.isActive ? 'Deactivate ${f.name}?' : 'Activate ${f.name}?',
      message: f.isActive
          ? 'Residents will no longer see this facility or be able to book it. Existing bookings are not changed.'
          : 'Residents will be able to view and book this facility again.',
      confirmLabel: f.isActive ? 'Deactivate' : 'Activate',
      destructive: f.isActive,
      icon: f.isActive
          ? Icons.visibility_off_outlined
          : Icons.visibility_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .facilities
          .setActive(f.id, isActive: !f.isActive);
      if (mounted) {
        showSuccessSnack(context,
            f.isActive ? 'Facility deactivated.' : 'Facility activated.');
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Facility f) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LiveFacilityFormPage(existing: f)),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Facility updated.');
      setState(() => _future = _load(force: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facility'),
        actions: [
          FutureBuilder<Facility>(
            future: _future,
            builder: (context, snap) => snap.hasData
                ? IconButton(
                    tooltip: 'Edit',
                    onPressed: _busy ? null : () => _edit(snap.data!),
                    icon: const Icon(Icons.edit_outlined),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: FutureBuilder<Facility>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading facility…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load facility',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final f = snapshot.data!;
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
                  title: f.name,
                  subtitle: [
                    facilityCategoryLabel(f.category),
                    if (f.location != null && f.location!.trim().isNotEmpty)
                      f.location!,
                  ].join(' · '),
                  leading: AppAvatar(
                    icon: _categoryIcon(f.category),
                    square: true,
                    size: Sz.avatarLg,
                    color: f.isActive ? C.blue : C.muted,
                  ),
                  badges: [
                    StatusBadge(f.isActive ? 'Active' : 'Inactive'),
                    StatusBadge(_feeLabel(f.bookingFeePaise),
                        tone: f.bookingFeePaise > 0
                            ? BadgeTone.info
                            : BadgeTone.success),
                    if (f.requiresApproval)
                      const StatusBadge('Needs approval',
                          tone: BadgeTone.neutral,
                          icon: Icons.how_to_reg_outlined),
                  ],
                ),
                if (f.description != null &&
                    f.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(f.description!, style: T.body),
                ],
                const SizedBox(height: 16),
                const SectionTitle('Availability'),
                MetricBand(items: [
                  MetricItem('Hours', '${f.openingTime}–${f.closingTime}'),
                  MetricItem('Capacity', '${f.capacity}'),
                  MetricItem(
                      'Max duration', '${f.maxBookingDurationMinutes} min'),
                  MetricItem('Open days', '${f.availableDays.length}'),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Open on ${f.availableDays.map(weekdayLabel).join(', ')}',
                  style: T.caption,
                ),
                const SizedBox(height: 18),
                DetailCard(title: 'Booking rules', children: [
                  DetailRow('Hours', '${f.openingTime} – ${f.closingTime}'),
                  DetailRow(
                      'Open on', f.availableDays.map(weekdayLabel).join(', ')),
                  DetailRow('Capacity', '${f.capacity}'),
                  DetailRow(
                      'Max duration', '${f.maxBookingDurationMinutes} minutes'),
                  DetailRow(
                      'Booking required', f.bookingRequired ? 'Yes' : 'No'),
                  DetailRow('Approval',
                      f.requiresApproval ? 'Required' : 'Not required'),
                ]),
                DetailCard(title: 'Fee & location', children: [
                  DetailRow('Booking fee', _feeLabel(f.bookingFeePaise),
                      emphasize: f.bookingFeePaise > 0),
                  DetailRow('Fee payment',
                      f.feePaymentRequired ? 'Required' : 'Not required'),
                  if (f.location != null && f.location!.trim().isNotEmpty)
                    DetailRow('Location', f.location!),
                  DetailRow('Created', fmtIsoDate(f.createdAt)),
                  if (f.deactivatedAt != null)
                    DetailRow('Deactivated', fmtIsoDate(f.deactivatedAt)),
                ]),
                const SizedBox(height: 6),
                const SectionTitle('Actions'),
                ActionRail(
                  busy: _busy,
                  secondary: [
                    ToolLink(
                      icon: Icons.edit_outlined,
                      label: 'Edit facility',
                      subtitle: 'Name, hours, capacity, fee and days',
                      onTap: () => _edit(f),
                    ),
                    ToolLink(
                      icon: f.isActive
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      label: f.isActive ? 'Deactivate' : 'Activate',
                      subtitle: f.isActive
                          ? 'Hide from residents and stop new bookings'
                          : 'Make available for booking again',
                      onTap: () => _toggle(f),
                    ),
                  ],
                ),
              ],
            ),
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
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description =
      TextEditingController(text: widget.existing?.description);
  late final _location = TextEditingController(text: widget.existing?.location);
  late final _capacity = TextEditingController(
    text: '${widget.existing?.capacity ?? 10}',
  );
  // Admin types rupees; the API receives integer paise.
  late final _fee = TextEditingController(
    text: paiseToRupeeInput(widget.existing?.bookingFeePaise ?? 0),
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
  late final Set<String> _days = {
    ...(widget.existing?.availableDays ?? kWeekdays)
  };
  bool _submitting = false;
  String? _error;

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
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final capacity = int.tryParse(_capacity.text.trim());
    final fee = parseRupeesToPaise(_fee.text);
    final maxDur = int.tryParse(_maxDuration.text.trim());
    if (name.isEmpty || capacity == null || fee == null || maxDur == null) {
      setState(
          () => _error = 'Check the name, capacity, fee and max duration.');
      return;
    }
    if (_days.isEmpty) {
      setState(() => _error = 'Select at least one available day.');
      return;
    }
    if (_open.text.trim().isEmpty || _close.text.trim().isEmpty) {
      setState(() => _error = 'Set opening and closing times.');
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
      if (mounted) setState(() => _error = facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _positiveInt(String? v, String label) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return '$label must be a whole number above 0.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final feePaise = parseRupeesToPaise(_fee.text);
    return FormScaffold(
      title: editing ? 'Edit facility' : 'New facility',
      formKey: _formKey,
      bottom: PrimaryButton(
        label: editing ? 'Save changes' : 'Create facility',
        icon: Icons.check_rounded,
        busy: _submitting,
        onPressed: _submit,
      ),
      children: [
        const FormSectionLabel('Basics'),
        TextFormField(
          controller: _name,
          enabled: !_submitting,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Name *',
            prefixIcon: Icon(Icons.apartment_outlined),
          ),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Name is required.' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(_categoryIcon(_category)),
          ),
          items: [
            for (final c in kFacilityCategories)
              DropdownMenuItem(
                value: c,
                child: Text(facilityCategoryLabel(c)),
              ),
          ],
          onChanged: _submitting
              ? null
              : (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _location,
          enabled: !_submitting,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Location',
            hintText: 'e.g. Clubhouse, ground floor',
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          enabled: !_submitting,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        const FormSectionLabel('Hours & days'),
        Row(children: [
          Expanded(
            child: TimeField(
                controller: _open, label: 'Opens', enabled: !_submitting),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TimeField(
                controller: _close, label: 'Closes', enabled: !_submitting),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in kWeekdays)
              AppFilterChip(
                label: weekdayLabel(d),
                selected: _days.contains(d),
                onSelected: _submitting
                    ? () {}
                    : () => setState(() {
                          if (_days.contains(d)) {
                            _days.remove(d);
                          } else {
                            _days.add(d);
                          }
                        }),
              ),
          ],
        ),
        if (_days.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Select at least one day.',
                style: TextStyle(color: C.error, fontSize: 12)),
          ),
        const SizedBox(height: 20),
        const FormSectionLabel('Capacity & fee'),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _capacity,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Capacity *',
                prefixIcon: Icon(Icons.groups_outlined),
              ),
              validator: (v) => _positiveInt(v, 'Capacity'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _maxDuration,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Max minutes *',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              validator: (v) => _positiveInt(v, 'Max duration'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _fee,
          enabled: !_submitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Booking fee (₹)',
            prefixIcon: const Icon(Icons.currency_rupee_rounded),
            helperText: feePaise == null
                ? 'Enter 0 for a free facility.'
                : feePaise == 0
                    ? 'Free to book'
                    : 'Residents see ${moneyPaise(feePaise)} per booking',
          ),
          validator: (v) => parseRupeesToPaise(v ?? '') == null
              ? 'Enter a valid amount in rupees.'
              : null,
        ),
        const SizedBox(height: 20),
        const FormSectionLabel('Rules'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              title: const Text('Booking required'),
              subtitle:
                  const Text('Residents must reserve a slot to use it'),
              value: _bookingRequired,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _bookingRequired = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Requires approval'),
              subtitle: const Text(
                  'Bookings stay pending until an admin approves'),
              value: _requiresApproval,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _requiresApproval = v),
            ),
          ]),
        ),
        InlineError(_error),
      ],
    );
  }
}

// ─── Admin bookings ──────────────────────────────────────────────────────────

class _AdminBookingsBundle {
  const _AdminBookingsBundle({
    required this.bookings,
    required this.facilityNames,
    required this.flatLabels,
  });
  final Paged<FacilityBooking> bookings;
  final Map<String, String> facilityNames;
  final Map<String, String> flatLabels;
}

String _flatSummaryLabel(FlatSummary f) => f.label;

class LiveAdminFacilityBookingsPage extends StatefulWidget {
  const LiveAdminFacilityBookingsPage({super.key});

  @override
  State<LiveAdminFacilityBookingsPage> createState() =>
      _LiveAdminFacilityBookingsPageState();
}

class _LiveAdminFacilityBookingsPageState
    extends State<LiveAdminFacilityBookingsPage> {
  String? status;
  late Future<_AdminBookingsBundle> _future = _load();
  StreamSubscription<FacilityBookingEventPayload>? _sub;

  Future<_AdminBookingsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final bookings = await repos.facilities.listAdminBookings(
      force: force,
      query: ListFacilityBookingsQuery(status: status, limit: 50),
    );
    // Names are decorative; never fail the list because lookups failed.
    var facilityNames = <String, String>{};
    var flatLabels = <String, String>{};
    try {
      final facilities = await repos.facilities.listAdmin(
        query: const ListFacilitiesQuery(limit: 50),
      );
      facilityNames = {for (final f in facilities.items) f.id: f.name};
    } catch (_) {}
    try {
      final flats = await repos.society.listAllFlats();
      flatLabels = {for (final f in flats) f.id: _flatSummaryLabel(f)};
    } catch (_) {}
    return _AdminBookingsBundle(
      bookings: bookings,
      facilityNames: facilityNames,
      flatLabels: flatLabels,
    );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.facilityBookingEvents.listen((_) {
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
    return FutureBuilder<_AdminBookingsBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snapshot.hasError) {
          return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load bookings',
              onRetry: reload);
        }
        final bundle = snapshot.data!;
        final items = bundle.bookings.items;
        final pending = items.where((b) => b.status == 'PENDING').length;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: Sp.pagePadding,
            children: [
              PageHeader('Facility bookings',
                  subtitle: status == null && pending > 0
                      ? '$pending awaiting approval'
                      : 'Requests from residents'),
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
                  for (final s in kFacilityBookingStatuses)
                    AppFilterChip(
                      label: facilityBookingStatusLabel(s),
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
                      ? 'No bookings yet'
                      : 'No ${facilityBookingStatusLabel(status!).toLowerCase()} bookings',
                  icon: Icons.event_available_outlined,
                  actionLabel: status == null ? null : 'Show all',
                  onAction: () => setState(() {
                    status = null;
                    _future = _load(force: true);
                  }),
                )
              else ...[
                ResultCount(bundle.bookings.pagination.total, 'booking'),
                for (final b in items)
                  _BookingRow(
                    booking: b,
                    facilityName: bundle.facilityNames[b.facilityId],
                    flatLabel: bundle.flatLabels[b.flatId],
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LiveAdminBookingDetailPage(bookingId: b.id),
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

class _AdminBookingView {
  const _AdminBookingView({
    required this.booking,
    this.facilityName,
    this.flatLabel,
    this.bookedBy,
  });
  final FacilityBooking booking;
  final String? facilityName;
  final String? flatLabel;
  final String? bookedBy;
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
  late Future<_AdminBookingView> _future = _load();
  bool _busy = false;

  Future<_AdminBookingView> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final b =
        await repos.facilities.getAdminBooking(widget.bookingId, force: force);
    String? facilityName;
    String? flatLabel;
    String? bookedBy;
    // Lookups are decorative; a failure must not hide the booking.
    try {
      facilityName = (await repos.facilities.getAdmin(b.facilityId)).name;
    } catch (_) {}
    try {
      flatLabel = _flatSummaryLabel(await repos.society.flat(b.flatId));
    } catch (_) {}
    try {
      bookedBy = (await repos.users.getUser(b.bookedByUserId)).name;
    } catch (_) {}
    return _AdminBookingView(
      booking: b,
      facilityName: facilityName,
      flatLabel: flatLabel,
      bookedBy: bookedBy,
    );
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        if (success != null) showSuccessSnack(context, success);
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, facilityErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(FacilityBooking b) async {
    final ok = await confirmDialog(
      context,
      title: 'Approve booking?',
      message:
          'The slot on ${fmtYmd(b.bookingDate)} (${b.startTime}–${b.endTime}) will be confirmed and count towards capacity.',
      confirmLabel: 'Approve',
      icon: Icons.check_circle_outline_rounded,
    );
    if (!ok) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).facilities.approveBooking(b.id);
    }, success: 'Booking approved.');
  }

  Future<void> _reject(FacilityBooking b) async {
    final reason = await promptTextDialog(
      context,
      title: 'Reject booking?',
      message: 'The resident will see this reason.',
      label: 'Reason *',
      confirmLabel: 'Reject',
      cancelLabel: 'Back',
      destructive: true,
      required: true,
      minLength: 3,
      maxLines: 2,
    );
    if (reason == null) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .facilities
          .rejectBooking(b.id, reason: reason.trim());
    }, success: 'Booking rejected.');
  }

  Future<void> _cancel(FacilityBooking b) async {
    final reason = await promptTextDialog(
      context,
      title: 'Cancel booking?',
      message: 'This releases the slot. The resident will be notified.',
      label: 'Reason (optional)',
      confirmLabel: 'Cancel booking',
      cancelLabel: 'Back',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null) return;
    await _run(() async {
      final session = authSession!;
      final trimmed = reason.trim();
      await ensureLiveRepositories(session.api).facilities.cancelAdminBooking(
            b.id,
            reason: trimmed.isEmpty ? null : trimmed,
          );
    }, success: 'Booking cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking')),
      body: FutureBuilder<_AdminBookingView>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading booking…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load booking',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final view = snapshot.data!;
          final b = view.booking;
          final pending = b.status == 'PENDING';
          final open = pending || b.status == 'CONFIRMED';
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                color: C.blue,
                onRefresh: () async {
                  setState(() => _future = _load(force: true));
                  await _future;
                },
                child: ListView(
                  padding: Sp.pagePadding,
                  children: [
                    _BookingDetails(
                      booking: b,
                      facilityName: view.facilityName,
                      flatLabel: view.flatLabel,
                      bookedBy: view.bookedBy,
                      showAdminNotes: true,
                    ),
                    if (open) ...[
                      const SizedBox(height: 12),
                      const SectionTitle('Manage'),
                      ActionRail(
                        busy: _busy,
                        secondary: [
                          if (pending)
                            ToolLink(
                              icon: Icons.block_outlined,
                              label: 'Reject',
                              subtitle: 'Decline with a reason',
                              onTap: () => _reject(b),
                            ),
                          ToolLink(
                            icon: Icons.cancel_outlined,
                            label: 'Cancel booking',
                            subtitle: 'Release the slot',
                            onTap: () => _cancel(b),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (pending)
              BottomActionBar(children: [
                PrimaryButton(
                  label: 'Approve booking',
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: () => _approve(b),
                ),
              ]),
          ]);
        },
      ),
    );
  }
}
