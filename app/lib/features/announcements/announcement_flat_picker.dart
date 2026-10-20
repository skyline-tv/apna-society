import '../../api/models/society_models.dart';

/// Display label for announcement audience flat chips/rows.
String announcementFlatLabel(FlatSummary flat) {
  final wing = (flat.wingName?.trim().isNotEmpty == true)
      ? flat.wingName!.trim()
      : (flat.wingCode?.trim().isNotEmpty == true)
          ? 'Wing ${flat.wingCode!.trim()}'
          : 'Wing';
  return '$wing · ${flat.number}';
}

/// Pure selection + client-side search/pagination for announcement flat picking.
///
/// Selected IDs are preserved when [search] or [page] changes. Selection uses a
/// [Set] so duplicates are impossible.
class AnnouncementFlatPickerModel {
  AnnouncementFlatPickerModel({
    Set<String>? initiallySelected,
    this.pageSize = 20,
  }) : selectedIds = {...?initiallySelected};

  final Set<String> selectedIds;
  final int pageSize;

  List<FlatSummary> allFlats = const [];
  String search = '';
  int page = 1;

  List<FlatSummary> get filtered {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return allFlats;
    return allFlats.where((f) {
      final label = announcementFlatLabel(f).toLowerCase();
      return label.contains(q) ||
          f.number.toLowerCase().contains(q) ||
          (f.wingCode?.toLowerCase().contains(q) ?? false) ||
          (f.wingName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  int get totalFiltered => filtered.length;

  int get totalPages {
    if (totalFiltered == 0) return 1;
    return ((totalFiltered - 1) ~/ pageSize) + 1;
  }

  List<FlatSummary> get pageItems {
    final items = filtered;
    if (items.isEmpty) return const [];
    final safePage = page.clamp(1, totalPages);
    final start = (safePage - 1) * pageSize;
    if (start >= items.length) return const [];
    final end = (start + pageSize).clamp(0, items.length);
    return items.sublist(start, end);
  }

  void replaceFlats(List<FlatSummary> flats) {
    allFlats = List.unmodifiable(flats);
    page = page.clamp(1, totalPages);
  }

  void setSearch(String value) {
    search = value;
    page = 1; // preserve selectedIds
  }

  void goToPage(int next) {
    page = next.clamp(1, totalPages);
  }

  /// Returns true if selection changed.
  bool setSelected(String flatId, bool selected) {
    if (selected) {
      return selectedIds.add(flatId);
    }
    return selectedIds.remove(flatId);
  }

  bool isSelected(String flatId) => selectedIds.contains(flatId);
}
