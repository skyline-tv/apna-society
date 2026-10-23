import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/auth/app_role.dart';
import '../../api/auth/auth_session.dart';
import '../../api/models/common.dart';
import '../../api/models/parcel_models.dart';
import '../../api/models/visitor_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import '../visitors/visitor_messages.dart';

String parcelErrorMessage(Object error) => visitorErrorMessage(error);

class LiveGuardParcelsPage extends StatefulWidget {
  const LiveGuardParcelsPage({super.key});

  @override
  State<LiveGuardParcelsPage> createState() => _LiveGuardParcelsPageState();
}

class _LiveGuardParcelsPageState extends State<LiveGuardParcelsPage> {
  String? _status;
  late Future<Paged<ParcelHandover>> _future = _load();
  StreamSubscription<VisitorEventPayload>? _sub;

  Future<Paged<ParcelHandover>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).visitors.listGuardParcels(
          status: _status,
          force: force,
        );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.events.listen((_) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Parcels')),
      body: FutureBuilder<Paged<ParcelHandover>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 4);
          }
          if (snapshot.hasError) {
            return LoadFailure(error: snapshot.error!, onRetry: reload);
          }
          final items = snapshot.data!.items;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: Sp.pagePadding,
              children: [
                FilterBar(
                  padding: EdgeInsets.zero,
                  children: [
                    AppFilterChip(
                      label: 'All',
                      selected: _status == null,
                      onSelected: () => setState(() {
                        _status = null;
                        _future = _load(force: true);
                      }),
                    ),
                    for (final status in kParcelStatuses)
                      AppFilterChip(
                        label: parcelStatusLabel(status),
                        selected: _status == status,
                        onSelected: () => setState(() {
                          _status = status;
                          _future = _load(force: true);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const EmptyState('No parcels at the gate',
                      icon: Icons.inventory_2_outlined)
                else
                  for (final parcel in items)
                    _ParcelRow(
                      parcel: parcel,
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveGuardParcelDetailPage(parcelId: parcel.id),
                          ),
                        );
                        reload();
                      },
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LiveResidentParcelsPage extends StatefulWidget {
  const LiveResidentParcelsPage({super.key});

  @override
  State<LiveResidentParcelsPage> createState() => _LiveResidentParcelsPageState();
}

class _LiveResidentParcelsPageState extends State<LiveResidentParcelsPage> {
  late Future<Paged<ParcelHandover>> _future = _load();

  Future<Paged<ParcelHandover>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .listResidentParcels(force: force);
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcels')),
      body: FutureBuilder<Paged<ParcelHandover>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 4);
          }
          if (snapshot.hasError) {
            return LoadFailure(error: snapshot.error!, onRetry: reload);
          }
          final items = snapshot.data!.items;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: Sp.pagePadding,
              children: [
                if (items.isEmpty)
                  const EmptyState('No parcels for this flat',
                      icon: Icons.inventory_2_outlined)
                else
                  for (final parcel in items)
                    _ParcelRow(
                      parcel: parcel,
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveResidentParcelDetailPage(
                                parcelId: parcel.id),
                          ),
                        );
                        reload();
                      },
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LiveGuardParcelDetailPage extends StatefulWidget {
  const LiveGuardParcelDetailPage({super.key, required this.parcelId});
  final String parcelId;

  @override
  State<LiveGuardParcelDetailPage> createState() =>
      _LiveGuardParcelDetailPageState();
}

class _LiveGuardParcelDetailPageState extends State<LiveGuardParcelDetailPage> {
  late Future<ParcelHandover> _future = _load();
  bool _busy = false;

  Future<ParcelHandover> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .guardParcel(widget.parcelId, force: force);
  }

  void _reload() => setState(() => _future = _load(force: true));

  Future<void> _receive(ParcelHandover parcel) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api)
          .visitors
          .receiveParcel(parcel.id);
      if (!mounted) return;
      showSuccessSnack(context, 'Parcel received at the gate.');
      _reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, parcelErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcel')),
      body: FutureBuilder<ParcelHandover>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading parcel…');
          }
          if (snapshot.hasError) {
            return LoadFailure(error: snapshot.error!, onRetry: _reload);
          }
          final parcel = snapshot.data!;
          final awaiting = parcel.status == 'AWAITING_HANDOVER';
          return Column(children: [
            Expanded(child: _ParcelDetailBody(parcel: parcel, onRefresh: () async {
              _reload();
              await _future;
            })),
            if (awaiting)
              BottomActionBar(children: [
                PrimaryButton(
                  label: 'Record parcel received',
                  icon: Icons.inventory_2_outlined,
                  busy: _busy,
                  onPressed: () => _receive(parcel),
                ),
              ]),
          ]);
        },
      ),
    );
  }
}

class LiveResidentParcelDetailPage extends StatefulWidget {
  const LiveResidentParcelDetailPage({super.key, required this.parcelId});
  final String parcelId;

  @override
  State<LiveResidentParcelDetailPage> createState() =>
      _LiveResidentParcelDetailPageState();
}

class _LiveResidentParcelDetailPageState
    extends State<LiveResidentParcelDetailPage> {
  late Future<ParcelHandover> _future = _load();

  Future<ParcelHandover> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final role = session.appRole;
    final repos = ensureLiveRepositories(session.api);
    if (role == AppRole.guard) {
      return repos.visitors.guardParcel(widget.parcelId, force: force);
    }
    return repos.visitors.residentParcel(widget.parcelId, force: force);
  }

  void _reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcel')),
      body: FutureBuilder<ParcelHandover>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading parcel…');
          }
          if (snapshot.hasError) {
            return LoadFailure(error: snapshot.error!, onRetry: _reload);
          }
          return _ParcelDetailBody(
            parcel: snapshot.data!,
            onRefresh: () async {
              _reload();
              await _future;
            },
          );
        },
      ),
    );
  }
}

class _ParcelRow extends StatelessWidget {
  const _ParcelRow({required this.parcel, this.onTap});
  final ParcelHandover parcel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        icon: Icons.inventory_2_outlined,
        color: parcel.status == 'AWAITING_HANDOVER' ? C.amber : C.green,
      ),
      title: parcel.courierName,
      subtitle: '${parcel.flatLabel} · ${parcelStatusLabel(parcel.status)}',
      trailing: Text(fmtIsoDateTime(parcel.requestedAt), style: T.caption),
    );
  }
}

class _ParcelDetailBody extends StatelessWidget {
  const _ParcelDetailBody({required this.parcel, this.onRefresh});
  final ParcelHandover parcel;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: Sp.pagePadding,
      children: [
        DetailHero(
          title: parcel.courierName,
          subtitle: parcel.flatLabel,
          leading: const AppAvatar(
            icon: Icons.inventory_2_outlined,
            color: C.amber,
            size: Sz.avatarLg,
          ),
          badges: [
            StatusBadge(parcelStatusLabel(parcel.status)),
          ],
        ),
        DetailCard(title: 'Handover', children: [
          if (parcel.courierPhone != null && parcel.courierPhone!.isNotEmpty)
            DetailRow('Mobile', parcel.courierPhone!),
          if (parcel.visitorType != null)
            DetailRow('Visitor type', visitorTypeLabel(parcel.visitorType!)),
          if (parcel.purpose != null && parcel.purpose!.isNotEmpty)
            DetailRow('Purpose', parcel.purpose!),
          DetailRow('Requested', fmtIsoDateTime(parcel.requestedAt)),
          DetailRow('Authorized', fmtIsoDateTime(parcel.authorizedAt)),
          if (parcel.receivedAt != null)
            DetailRow('Received by guard', fmtIsoDateTime(parcel.receivedAt)),
          if (parcel.notes != null && parcel.notes!.trim().isNotEmpty)
            DetailRow('Notes', parcel.notes!),
        ]),
        const InfoNote(
          'Leave Parcel authorizes handover only. It does not record visitor entry.',
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(color: C.blue, onRefresh: onRefresh!, child: list);
  }
}
