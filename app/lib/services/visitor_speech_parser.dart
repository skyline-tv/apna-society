/// Lightweight on-device extraction of visitor fields from speech transcripts.
/// Supports English, Hindi cues, and Hinglish without calling an external AI API.
library;

class ParsedVisitorSpeech {
  const ParsedVisitorSpeech({
    required this.rawText,
    this.name,
    this.mobile,
    this.category,
    this.purpose,
    this.wing,
    this.flatNumber,
    this.vehicleNumber,
    this.missingFields = const {},
    this.uncertainFields = const {},
  });

  final String rawText;
  final String? name;
  final String? mobile;
  final String? category;
  final String? purpose;
  final String? wing;
  final String? flatNumber;
  final String? vehicleNumber;
  final Set<String> missingFields;
  final Set<String> uncertainFields;

  bool get hasUsableExtract =>
      (name?.isNotEmpty ?? false) ||
      (mobile?.isNotEmpty ?? false) ||
      (flatNumber?.isNotEmpty ?? false) ||
      (vehicleNumber?.isNotEmpty ?? false);
}

/// Parses recognized speech into visitor fields. Does not invent missing details.
///
/// [knownFlatNumbers] should be active society flats (e.g. `A-302`). If a spoken
/// flat is not in this set, it is left empty and marked uncertain.
ParsedVisitorSpeech parseVisitorSpeech(
  String raw, {
  Set<String> knownFlatNumbers = const {},
}) {
  final original = raw.trim();
  if (original.isEmpty) {
    return ParsedVisitorSpeech(
      rawText: original,
      missingFields: const {'name', 'mobile', 'flatNumber', 'purpose'},
    );
  }

  var work = _normalizeTranscript(original);
  final mobile = _extractMobile(work);
  if (mobile != null) {
    work = work.replaceAll(RegExp(r'[6-9](?:[\s\-]?\d){9}'), ' ');
  }

  final vehicle = _extractVehicle(work);
  if (vehicle != null) {
    work = work.replaceAll(
      RegExp(
        r'(?:vehicle(?:\s+number)?|gaadi(?:\s+number)?|car(?:\s+number)?)\s*[:\-]?\s*',
        caseSensitive: false,
      ),
      ' ',
    );
    work = work.replaceAll(
      RegExp(r'[A-Za-z]{2}\s*\d{1,2}\s*[A-Za-z]{1,3}\s*\d{3,4}',
          caseSensitive: false),
      ' ',
    );
  }

  final category = _extractCategory(original);
  final flatHit = _extractFlat(work);
  String? wing = flatHit?.wing;
  String? flatNumber = flatHit?.flatNumber;
  if (flatHit != null) {
    work = work.replaceAll(flatHit.match, ' ');
  } else {
    wing = _extractWingOnly(work) ?? wing;
  }

  if (flatNumber != null &&
      knownFlatNumbers.isNotEmpty &&
      !knownFlatNumbers.contains(flatNumber)) {
    // Spoken flat is not in the 140-flat inventory — do not invent a substitute.
    flatNumber = null;
    wing = wing; // keep wing hint if present for the dropdown
  }

  final name = _extractName(work, original);
  if (name != null) {
    for (final token in name.toLowerCase().split(RegExp(r'\s+'))) {
      if (token.length >= 2) {
        work = work.replaceAll(
            RegExp('\\b${RegExp.escape(token)}\\b', caseSensitive: false), ' ');
      }
    }
  }

  final purpose = _extractPurpose(original, category: category);

  final missing = <String>{};
  final uncertain = <String>{};
  if (name == null || name.isEmpty) missing.add('name');
  if (mobile == null || mobile.isEmpty) missing.add('mobile');
  if (flatNumber == null || flatNumber.isEmpty) {
    missing.add('flatNumber');
    if (flatHit != null && knownFlatNumbers.isNotEmpty) {
      uncertain.add('flatNumber');
    }
  }
  if (purpose == null || purpose.isEmpty) missing.add('purpose');
  if (vehicle == null &&
      RegExp(r'vehicle|gaadi|car number', caseSensitive: false)
          .hasMatch(original)) {
    uncertain.add('vehicleNumber');
  }
  if (name != null &&
      name.split(' ').length == 1 &&
      !RegExp(r'naam|name is|visitor\s+\w+', caseSensitive: false)
          .hasMatch(original)) {
    uncertain.add('name');
  }

  return ParsedVisitorSpeech(
    rawText: original,
    name: name,
    mobile: mobile,
    category: category ?? 'Guest',
    purpose: purpose,
    wing: wing,
    flatNumber: flatNumber,
    vehicleNumber: vehicle,
    missingFields: missing,
    uncertainFields: uncertain,
  );
}

String _normalizeTranscript(String input) {
  var t = input.toLowerCase();
  // Spoken digit words → digits (common STT for Hinglish mobiles / flats).
  const words = {
    'zero': '0',
    'oh': '0',
    'o': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    'double': '', // handled below
  };
  // "double eight" → 88
  t = t.replaceAllMapped(
    RegExp(
        r'\bdouble\s+(zero|oh|one|two|three|four|five|six|seven|eight|nine)\b'),
    (m) => '${words[m.group(1)]}${words[m.group(1)]}',
  );
  for (final e in words.entries) {
    if (e.key == 'double' || e.key == 'o') continue;
    t = t.replaceAll(RegExp('\\b${e.key}\\b'), e.value);
  }
  t = t
      .replaceAll('mobile number', 'mobile')
      .replaceAll('phone number', 'mobile')
      .replaceAll('contact number', 'mobile')
      .replaceAll('vehicle number', 'vehicle')
      .replaceAll('gaadi number', 'vehicle')
      .replaceAll('car number', 'vehicle')
      .replaceAll('flat number', 'flat')
      .replaceAll('apartment', 'flat')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t;
}

String? _extractMobile(String text) {
  // Prefer contiguous / lightly spaced 10-digit Indian mobiles.
  final spaced = RegExp(r'\b([6-9](?:[\s\-]?\d){9})\b').firstMatch(text);
  if (spaced != null) {
    final digits = spaced.group(1)!.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) return digits;
  }

  // Fallback: scan all digits in order and take the first valid mobile window.
  final all = text.replaceAll(RegExp(r'\D'), '');
  for (var i = 0; i + 10 <= all.length; i++) {
    final slice = all.substring(i, i + 10);
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(slice)) return slice;
  }
  return null;
}

String? _extractVehicle(String text) {
  final m = RegExp(
    r'\b([A-Za-z]{2})\s*[-]?\s*(\d{1,2})\s*[-]?\s*([A-Za-z]{1,3})\s*[-]?\s*(\d{3,4})\b',
  ).firstMatch(text);
  if (m == null) return null;
  final plate =
      '${m.group(1)}${m.group(2)}${m.group(3)}${m.group(4)}'.toUpperCase();
  if (plate.length < 8 || plate.length > 11) return null;
  return plate;
}

class _FlatHit {
  const _FlatHit(
      {required this.wing, required this.flatNumber, required this.match});
  final String wing;
  final String flatNumber;
  final String match;
}

_FlatHit? _extractFlat(String text) {
  // flat A 302 / A-302 / A 3 0 2 (STT often spaces digits)
  final patterns = <RegExp>[
    RegExp(
      r'\b(?:flat|wing)?\s*([a-e])\s*[-\s]\s*(\d(?:\s*\d){2,3})\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b([a-e])\s*(?:wing)?\s*(?:flat)?\s*(\d(?:\s*\d){2,3})\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bflat\s*([a-e])\s*(\d(?:\s*\d){2,3})\b',
      caseSensitive: false,
    ),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(text);
    if (m == null) continue;
    final wing = m.group(1)!.toUpperCase();
    final num = m.group(2)!.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^[A-E]$').hasMatch(wing)) continue;
    if (num.length < 3 || num.length > 4) continue;
    final flatNumber = '$wing-$num';
    return _FlatHit(wing: wing, flatNumber: flatNumber, match: m.group(0)!);
  }
  return null;
}

String? _extractWingOnly(String text) {
  final m = RegExp(r'\b(?:wing|building)\s*([a-e])\b', caseSensitive: false)
      .firstMatch(text);
  if (m == null) return null;
  return m.group(1)!.toUpperCase();
}

String? _extractCategory(String original) {
  final t = original.toLowerCase();
  if (RegExp(r'\b(delivery|parcel|courier|amazon|flipkart|swiggy|zomato|dunzo)\b')
          .hasMatch(t) ||
      t.contains('delivery person') ||
      t.contains('delivery wala')) {
    return 'Delivery';
  }
  if (RegExp(r'\b(cab|taxi|uber|ola|rapido|driver)\b').hasMatch(t)) {
    return 'Cab';
  }
  if (RegExp(r'\b(domestic help|maid|cook|housemaid|house help|naukrani|kaamwali)\b')
          .hasMatch(t) ||
      t.contains('domestic')) {
    return 'Domestic Help';
  }
  if (RegExp(
          r'\b(technician|plumber|electrician|carpenter|ac\b|repair|mechanic)\b')
      .hasMatch(t)) {
    return 'Technician';
  }
  if (RegExp(r'\b(personal visit|guest|visitor|milne|relative|family)\b')
      .hasMatch(t)) {
    return 'Guest';
  }
  return null;
}

String? _extractPurpose(String original, {String? category}) {
  final t = original.toLowerCase();
  if (t.contains('personal visit')) return 'Personal visit';
  if (t.contains('coming for domestic help') || t.contains('domestic help'))
    return 'Domestic help';
  if (category == 'Delivery' || t.contains('delivery')) return 'Delivery';
  if (category == 'Cab') return 'Cab pickup / drop';
  if (category == 'Technician') return 'Service / repair';
  if (category == 'Guest') return 'Personal visit';

  final forMatch = RegExp(r'\b(?:for|coming for|ke liye)\s+([a-zA-Z ]{3,40})')
      .firstMatch(original);
  if (forMatch != null) {
    final p = forMatch.group(1)!.trim();
    if (!_isNoisePurpose(p)) return _titleCase(p);
  }
  return category;
}

bool _isNoisePurpose(String p) {
  final lower = p.toLowerCase();
  return lower.startsWith('flat') ||
      lower.startsWith('mobile') ||
      lower.startsWith('vehicle') ||
      RegExp(r'^\d').hasMatch(lower);
}

String? _extractName(String work, String original) {
  // "naam Amit hai" / "name is Amit Kumar"
  final naam = RegExp(
    r'\b(?:naam|name(?:\s+is)?)\s+([A-Za-z][A-Za-z.]+(?:\s+[A-Za-z][A-Za-z.]+){0,2})\s*(?:hai|hain)?\b',
    caseSensitive: false,
  ).firstMatch(original);
  if (naam != null) {
    final n = _cleanName(naam.group(1)!);
    if (n != null) return n;
  }

  // "Visitor Priya Shah"
  final visitor = RegExp(
    r'\bvisitor\s+([A-Za-z][A-Za-z.]+(?:\s+[A-Za-z][A-Za-z.]+){0,2})\b',
    caseSensitive: false,
  ).firstMatch(original);
  if (visitor != null) {
    final n = _cleanName(visitor.group(1)!);
    if (n != null) return n;
  }

  // Leading "Rahul Sharma, mobile…"
  final leading = RegExp(
    r'^([A-Za-z][A-Za-z.]+(?:\s+[A-Za-z][A-Za-z.]+){0,2})\s*[,]',
  ).firstMatch(original.trim());
  if (leading != null) {
    final n = _cleanName(leading.group(1)!);
    if (n != null) return n;
  }

  // Fallback: first 1–3 capitalized-looking words before flat/mobile cues (English-ish).
  final beforeCue = RegExp(
    r'^([A-Za-z][A-Za-z.]+(?:\s+[A-Za-z][A-Za-z.]+){0,2})\b(?=.*\b(?:mobile|flat|vehicle|personal|delivery)\b)',
    caseSensitive: false,
  ).firstMatch(original.trim());
  if (beforeCue != null) {
    final n = _cleanName(beforeCue.group(1)!);
    if (n != null) return n;
  }

  return null;
}

String? _cleanName(String raw) {
  final stop = {
    'visitor',
    'mobile',
    'number',
    'flat',
    'wing',
    'vehicle',
    'delivery',
    'person',
    'personal',
    'visit',
    'coming',
    'for',
    'domestic',
    'help',
    'ek',
    'aaya',
    'hai',
    'hain',
    'ke',
    'liye',
    'naam',
    'name',
    'is',
    'the',
    'a',
    'an',
  };
  final parts = raw
      .split(RegExp(r'\s+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty && !stop.contains(p.toLowerCase()))
      .where((p) => RegExp(r'^[A-Za-z][A-Za-z.]*$').hasMatch(p))
      .toList();
  if (parts.isEmpty) return null;
  if (parts.length > 3) return _titleCase(parts.take(3).join(' '));
  return _titleCase(parts.join(' '));
}

String _titleCase(String s) {
  return s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}
