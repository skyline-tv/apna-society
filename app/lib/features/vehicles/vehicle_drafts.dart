import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/http/api_exception.dart';
import '../../api/models/vehicle_models.dart';
import '../../ui/components.dart';

String vehicleErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'DUPLICATE_VEHICLE':
        return 'This registration number is already registered in the society.';
      case 'INVALID_REGISTRATION_NUMBER':
        return 'Invalid Indian registration number format.';
      case 'VEHICLE_INACTIVE':
        return 'This vehicle is inactive.';
      case 'VEHICLE_FLAT_MISMATCH':
        return 'Vehicle does not belong to the selected flat.';
      case 'SLOT_INACTIVE':
        return 'This parking slot is inactive.';
      case 'INCOMPATIBLE_SLOT_TYPE':
        return 'Slot type does not match the vehicle type.';
      case 'DUPLICATE_SLOT':
        return 'A parking slot with this number already exists.';
      case 'DUPLICATE_ALLOCATION':
        return 'Vehicle or slot already has an active allocation.';
      case 'VEHICLE_HAS_ALLOCATION':
        return 'This vehicle still has a parking allocation. Refresh and try again.';
      case 'SLOT_OCCUPIED':
        return 'Release the allocation before deactivating this slot.';
      case 'ALLOCATION_CONFLICT':
        return 'Allocation conflict. Refresh and try again.';
      case 'DUPLICATE_ACTIVE_ENTRY':
        return 'This plate is already marked inside.';
      case 'EXIT_CONFLICT':
        return 'Exit conflict. Refresh and try again.';
      case 'VEHICLE_TYPE_REQUIRED':
        return 'Vehicle type is required for unregistered plates.';
      case 'REGISTRATION_MISMATCH':
        return 'Registration number does not match the selected vehicle.';
      case 'RESIDENTIAL_ACCESS_DENIED':
        return 'Residential vehicle access is not available for this flat.';
      case 'RESIDENT_VEHICLE_READ_ONLY':
        return 'Vehicles are managed by the society admin. You can view your registered vehicles here.';
      case 'NOT_FLAT_OCCUPANT':
        return 'This resident is not the active owner or tenant of that flat.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this action.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

class VehicleDraftControllers {
  VehicleDraftControllers({
    this.vehicleType = 'FOUR_WHEELER',
    String registration = '',
    String make = '',
    String model = '',
    String parkingNumber = '',
  })  : registration = TextEditingController(text: registration),
        make = TextEditingController(text: make),
        model = TextEditingController(text: model),
        parkingNumber = TextEditingController(text: parkingNumber);

  String vehicleType;
  final TextEditingController registration;
  final TextEditingController make;
  final TextEditingController model;
  final TextEditingController parkingNumber;

  void dispose() {
    registration.dispose();
    make.dispose();
    model.dispose();
    parkingNumber.dispose();
  }

  VehicleDraftPayload? toPayloadOrNull() {
    final plate = normalizeRegistrationNumber(registration.text);
    final makeText = make.text.trim();
    final modelText = model.text.trim();
    final parking = parkingNumber.text.trim();
    if (plate.isEmpty && makeText.isEmpty && modelText.isEmpty && parking.isEmpty) {
      return null;
    }
    return VehicleDraftPayload(
      vehicleType: vehicleType,
      registrationNumber: plate,
      make: makeText.isEmpty ? null : makeText,
      model: modelText.isEmpty ? null : modelText,
      parkingNumber: parking.isEmpty ? null : parking,
    );
  }
}

String? validateVehicleDrafts(List<VehicleDraftControllers> drafts) {
  final seen = <String>{};
  for (var i = 0; i < drafts.length; i++) {
    final payload = drafts[i].toPayloadOrNull();
    if (payload == null) continue;
    if (!isValidIndianRegistrationNumber(payload.registrationNumber)) {
      return 'Enter a valid Indian registration number for vehicle ${i + 1}.';
    }
    if (!seen.add(payload.registrationNumber)) {
      return '${payload.registrationNumber} is listed more than once.';
    }
  }
  return null;
}

List<VehicleDraftPayload> vehicleDraftPayloads(
  List<VehicleDraftControllers> drafts,
) {
  return [
    for (final draft in drafts)
      if (draft.toPayloadOrNull() != null) draft.toPayloadOrNull()!,
  ];
}

class VehicleDraftsEditor extends StatelessWidget {
  const VehicleDraftsEditor({
    super.key,
    required this.drafts,
    required this.onChanged,
    this.enabled = true,
  });

  final List<VehicleDraftControllers> drafts;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSectionLabel('Vehicle details'),
        const Text(
          'Optional. Add vehicles only if this resident has them. '
          'Each vehicle is linked to the resident, assigned flat, and society.',
          style: T.caption,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < drafts.length; i++) ...[
          _VehicleDraftCard(
            index: i,
            draft: drafts[i],
            enabled: enabled,
            canRemove: drafts.isNotEmpty,
            onRemove: () {
              drafts[i].dispose();
              drafts.removeAt(i);
              onChanged();
            },
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: !enabled
                ? null
                : () {
                    drafts.add(VehicleDraftControllers());
                    onChanged();
                  },
            icon: const Icon(Icons.add_circle_outline),
            label: Text(drafts.isEmpty ? 'Add a vehicle' : 'Add another vehicle'),
          ),
        ),
      ],
    );
  }
}

class _VehicleDraftCard extends StatelessWidget {
  const _VehicleDraftCard({
    required this.index,
    required this.draft,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final VehicleDraftControllers draft;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Vehicle ${index + 1}', style: T.bodyStrong),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Remove vehicle',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            value: draft.vehicleType,
            decoration: const InputDecoration(
              labelText: 'Vehicle type *',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final type in kAdminSelectableVehicleTypes)
                DropdownMenuItem(
                  value: type,
                  child: Text(vehicleTypeLabel(type)),
                ),
            ],
            onChanged: !enabled
                ? null
                : (value) {
                    draft.vehicleType = value ?? 'FOUR_WHEELER';
                    onChanged();
                  },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.registration,
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Registration number *',
              helperText: 'Example: MH12AB1234',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.make,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Make',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.model,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.parkingNumber,
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Parking number',
              helperText: 'Bay or slot label, for example B-12',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
