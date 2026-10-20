import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../app_core.dart';
import '../../services/visitor_speech_parser.dart';
import '../../ui/components.dart';

/// Shared with [AddGateVisitorPage] — kept local to avoid circular imports.
const _kVisitorCategories = [
  'Guest',
  'Delivery',
  'Cab',
  'Domestic Help',
  'Technician',
  'Other',
];
const _kSocietyWings = ['A', 'B', 'C', 'D', 'E'];

/// Max listen window; longer silence gap so Hinglish pauses do not cut speech.
const _kListenFor = Duration(seconds: 60);
const _kPauseFor = Duration(seconds: 6);

const _kExamples = [
  'Rahul Sharma, mobile 9876543210, flat A 302, personal visit.',
  'Ek delivery person aaya hai flat B 204 ke liye, naam Amit hai, mobile 9876543210.',
  'Visitor Priya Shah, flat C 501, coming for domestic help, vehicle MH 05 AB 1234.',
];

/// Voice-assisted gate visitor registration → same owner-approval workflow.
class VoiceVisitorRegistrationPage extends StatefulWidget {
  const VoiceVisitorRegistrationPage({
    super.key,
    required this.guardId,
    required this.guardName,
    this.onManualFallback,
  });

  final int guardId;
  final String guardName;

  /// Opens the existing manual Add Visitor form (caller provides navigation).
  final VoidCallback? onManualFallback;

  @override
  State<VoiceVisitorRegistrationPage> createState() =>
      _VoiceVisitorRegistrationPageState();
}

enum _VoicePhase { capture, review }

enum _RecState { idle, starting, listening, processing }

class _VoiceVisitorRegistrationPageState
    extends State<VoiceVisitorRegistrationPage> with TickerProviderStateMixin {
  final _speech = stt.SpeechToText();
  late final AnimationController _pulse;
  late final AnimationController _bars;

  final name = TextEditingController();
  final mobile = TextEditingController();
  final purpose = TextEditingController();
  final vehicle = TextEditingController();

  _VoicePhase phase = _VoicePhase.capture;
  _RecState recState = _RecState.idle;
  bool speechReady = false;
  bool speechAvailable = false;
  bool busy = false;
  bool initTried = false;
  String? error;

  /// Finalized chunks from the recognizer (Android often emits several finals).
  String _committed = '';

  /// Current partial hypothesis.
  String _partial = '';
  String get transcript => ('$_committed $_partial').trim();

  /// Hinglish works best with the India English recognizer.
  String localeId = 'en_IN';

  /// Mic level from speech engine (~0–10). Used for live bars.
  double soundLevel = 0;
  DateTime? listenStartedAt;
  Timer? _tickTimer;
  int secondsLeft = _kListenFor.inSeconds;
  int exampleIndex = 0;
  Timer? _exampleTimer;

  /// True while Stop is finishing — status callbacks must not fight it.
  bool _userStopped = false;

  String category = _kVisitorCategories.first;
  String wing = 'A';
  String? selectedFlat;
  List<String> flatOptions = [];
  Set<String> knownFlats = {};
  Set<String> missingFields = {};
  Set<String> uncertainFields = {};

  bool get listening => recState == _RecState.listening;
  bool get starting => recState == _RecState.starting;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _bars = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280))
      ..repeat(reverse: true);
    _exampleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || listening) return;
      setState(() => exampleIndex = (exampleIndex + 1) % _kExamples.length);
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadKnownFlats();
    await _initSpeech();
  }

  Future<void> _loadKnownFlats() async {
    final all = <String>{};
    for (final w in _kSocietyWings) {
      all.addAll(await db.flatNumbersForWing(w));
    }
    final flats = await db.flatNumbersForWing(wing);
    if (!mounted) return;
    setState(() {
      knownFlats = all;
      flatOptions = flats;
    });
  }

  Future<void> _initSpeech() async {
    setState(() {
      initTried = true;
      error = null;
    });
    try {
      final ok = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (e) {
          if (!mounted) return;
          final code = e.errorMsg;
          // Soft errors: keep any transcript already captured; do not wipe the session UI.
          final soft = code == 'error_speech_timeout' ||
              code == 'error_no_match' ||
              code == 'error_client';
          _stopTimers();
          setState(() {
            recState = _RecState.idle;
            _pulse.stop();
            soundLevel = 0;
            if (_partial.isNotEmpty) {
              _committed = ('$_committed $_partial').trim();
              _partial = '';
            }
            if (!soft || transcript.isEmpty) {
              error = _friendlySpeechError(code);
            }
          });
        },
      );
      if (ok) {
        localeId = _pickHinglishLocale(await _speech.locales());
      }
      if (!mounted) return;
      setState(() {
        speechAvailable = ok;
        speechReady = ok;
        if (!ok) {
          error =
              'Speech recognition is unavailable on this device. Use manual registration.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        speechAvailable = false;
        speechReady = false;
        error = 'Could not start speech recognition. Use manual registration.';
      });
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status != 'done' && status != 'notListening') return;

    // stopRecording() owns the Stop → review path. Status only cleans UI after silence/engine end.
    if (_userStopped) return;

    final wasActive = recState == _RecState.listening ||
        recState == _RecState.processing ||
        recState == _RecState.starting;
    if (!wasActive) return;

    _stopTimers();
    setState(() {
      recState = _RecState.idle;
      _pulse.stop();
      soundLevel = 0;
      if (_partial.isNotEmpty) {
        _committed = _mergeSpeech(_committed, _partial);
        _partial = '';
      }
      // Keep transcript; guard can Continue or Review. Do not auto-open review.
      error = null;
    });
  }

  String _pickHinglishLocale(List<stt.LocaleName> available) {
    final ids = {
      for (final l in available) l.localeId.toLowerCase(): l.localeId
    };
    for (final preferred in ['en_IN', 'en_US', 'en_GB', 'hi_IN']) {
      final hit = ids[preferred.toLowerCase()];
      if (hit != null) return hit;
    }
    for (final l in available) {
      if (l.localeId.toLowerCase().startsWith('en')) return l.localeId;
    }
    return available.isNotEmpty ? available.first.localeId : 'en_IN';
  }

  String _friendlySpeechError(String code) {
    switch (code) {
      case 'error_permission':
      case 'error_insufficient_permissions':
        return 'Microphone permission denied. Enable it in Settings, or use manual registration.';
      case 'error_network':
      case 'error_network_timeout':
        return 'Speech needs a network connection on this device. Try again or register manually.';
      case 'error_speech_timeout':
      case 'error_no_match':
        return 'No speech detected. Hold the phone closer and try again.';
      case 'error_busy':
        return 'Speech recognizer is busy. Wait a moment and try again.';
      case 'error_audio':
        return 'Microphone is in use by another app. Close it and try again.';
      default:
        return 'Speech recognition failed. You can retry or use manual entry.';
    }
  }

  Future<void> _loadFlatsForWing() async {
    final flats = await db.flatNumbersForWing(wing);
    if (!mounted) return;
    setState(() {
      flatOptions = flats;
      if (selectedFlat != null && !flats.contains(selectedFlat)) {
        selectedFlat = null;
      }
    });
  }

  void _startTimers() {
    _stopTimers();
    listenStartedAt = DateTime.now();
    secondsLeft = _kListenFor.inSeconds;
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !listening) return;
      final elapsed = DateTime.now().difference(listenStartedAt!).inSeconds;
      final left =
          (_kListenFor.inSeconds - elapsed).clamp(0, _kListenFor.inSeconds);
      setState(() => secondsLeft = left);
      if (left <= 0) {
        unawaited(stopRecording());
      }
    });
    _pulse.repeat(reverse: true);
  }

  void _stopTimers() {
    _tickTimer?.cancel();
    _tickTimer = null;
    listenStartedAt = null;
  }

  Future<void> startRecording({bool append = false}) async {
    if (starting || listening || busy) return;
    _userStopped = false;
    setState(() {
      error = null;
      if (!append) {
        _committed = '';
        _partial = '';
      } else if (_partial.isNotEmpty) {
        _committed = ('$_committed $_partial').trim();
        _partial = '';
      }
      phase = _VoicePhase.capture;
      recState = _RecState.starting;
      soundLevel = 0;
    });
    HapticFeedback.mediumImpact();

    if (!speechReady) {
      await _initSpeech();
      if (!speechReady) {
        if (mounted) setState(() => recState = _RecState.idle);
        return;
      }
    }

    // Brief settle after permission / prior session — improves Android start reliability.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    try {
      // Platform/cloud recognizer first — far more reliable for Hinglish names & numbers.
      // On-device is a fallback only (often truncates or misses digits).
      var started = await _tryListen(onDevice: false);
      if (!started && mounted) {
        started = await _tryListen(onDevice: true);
      }
      if (!mounted) return;
      if (!started) {
        setState(() {
          recState = _RecState.idle;
          error =
              'Could not start the microphone. Check permissions or use manual registration.';
        });
        return;
      }
      setState(() => recState = _RecState.listening);
      _startTimers();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        recState = _RecState.idle;
        error =
            'Microphone permission denied or speech unavailable. Use manual registration.';
      });
    }
  }

  Future<bool> _tryListen({required bool onDevice}) async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          setState(() {
            error = null;
            if (result.finalResult) {
              // Android may emit multiple finals per session — append unique chunks.
              _committed = _mergeSpeech(_committed, words);
              _partial = '';
            } else {
              // Partials are usually the full current hypothesis for this utterance.
              _partial = words;
            }
          });
        },
        onSoundLevelChange: (level) {
          if (!mounted) return;
          if (recState != _RecState.listening && recState != _RecState.starting)
            return;
          setState(() => soundLevel = level);
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          onDevice: onDevice,
          listenFor: _kListenFor,
          pauseFor: _kPauseFor,
          localeId: localeId,
          enableHapticFeedback: true,
          autoPunctuation: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Merges recognizer finals without duplicating overlapping prefixes/suffixes.
  String _mergeSpeech(String committed, String next) {
    final a = committed.trim();
    final b = next.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    if (a.contains(b)) return a;
    if (b.contains(a)) return b;
    // Overlap: end of a == start of b
    final aWords = a.split(RegExp(r'\s+'));
    final bWords = b.split(RegExp(r'\s+'));
    var overlap = 0;
    final max = math.min(aWords.length, bWords.length);
    for (var n = max; n >= 1; n--) {
      if (aWords.sublist(aWords.length - n).join(' ') ==
          bWords.sublist(0, n).join(' ')) {
        overlap = n;
        break;
      }
    }
    if (overlap > 0) {
      return ('$a ${bWords.sublist(overlap).join(' ')}').trim();
    }
    return '$a $b';
  }

  Future<void> stopRecording() async {
    if (!listening &&
        recState != _RecState.processing &&
        recState != _RecState.starting) {
      // Already idle with text — go review.
      if (transcript.isNotEmpty) {
        _goToReview();
      }
      return;
    }
    _userStopped = true;
    setState(() => recState = _RecState.processing);
    HapticFeedback.lightImpact();
    await _speech.stop();
    _stopTimers();
    if (!mounted) return;
    setState(() {
      if (_partial.isNotEmpty) {
        _committed = _mergeSpeech(_committed, _partial);
        _partial = '';
      }
      recState = _RecState.idle;
      _pulse.stop();
      soundLevel = 0;
    });
    // Give the engine a beat to deliver a last final result.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (transcript.isEmpty) {
      _userStopped = false;
      setState(() => error =
          'Nothing was recognized. Tap the mic, speak clearly, then tap Stop.');
      return;
    }
    _userStopped = false;
    _goToReview();
  }

  Future<void> cancelRecording() async {
    _userStopped = false;
    await _speech.cancel();
    _stopTimers();
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      recState = _RecState.idle;
      _pulse.stop();
      soundLevel = 0;
      _committed = '';
      _partial = '';
      error = null;
      phase = _VoicePhase.capture;
    });
  }

  void _goToReview() {
    final text = transcript;
    if (text.isEmpty) return;
    _applyTranscript(text);
    setState(() => phase = _VoicePhase.review);
  }

  void _applyTranscript(String text) {
    final parsed = parseVisitorSpeech(text, knownFlatNumbers: knownFlats);
    name.text = parsed.name ?? '';
    mobile.text = parsed.mobile ?? '';
    purpose.text = parsed.purpose ?? '';
    vehicle.text = parsed.vehicleNumber ?? '';
    category = parsed.category ?? _kVisitorCategories.first;
    if (parsed.wing != null && _kSocietyWings.contains(parsed.wing)) {
      wing = parsed.wing!;
    }
    selectedFlat = parsed.flatNumber;
    missingFields = {...parsed.missingFields};
    uncertainFields = {...parsed.uncertainFields};
    unawaited(_loadFlatsForWing());
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if ((selectedFlat ?? '').isEmpty)
        throw StateError('Select a destination flat number.');
      await db.createGuardVisitorRequest(
        guardId: widget.guardId,
        guardName: widget.guardName,
        wing: wing,
        flatNumber: selectedFlat!,
        visitorName: name.text,
        mobile: mobile.text.trim(),
        category: category,
        purpose: purpose.text,
        vehicleNumber: vehicle.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Visitor request sent for owner approval (same-device demo notification).'),
          backgroundColor: C.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error =
          e is StateError ? e.message : 'Could not create visitor request.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openManual() async {
    await cancelRecording();
    if (!mounted) return;
    if (widget.onManualFallback != null) {
      widget.onManualFallback!();
      return;
    }
    Navigator.pop(context);
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String fieldKey,
    IconData? icon,
    String? counterText,
  }) {
    final highlight =
        missingFields.contains(fieldKey) || uncertainFields.contains(fieldKey);
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      counterText: counterText,
      filled: true,
      fillColor: highlight ? const Color(0xFFFFF4E5) : null,
      enabledBorder: highlight
          ? OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: C.amber, width: 1.4),
            )
          : null,
      focusedBorder: highlight
          ? OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: C.amber, width: 1.6),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _exampleTimer?.cancel();
    _stopTimers();
    _pulse.dispose();
    _bars.dispose();
    unawaited(_speech.cancel());
    name.dispose();
    mobile.dispose();
    purpose.dispose();
    vehicle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final requestTime =
        '${now.toIso8601String().substring(0, 10)} · ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(phase == _VoicePhase.review
            ? 'Review visitor details'
            : 'Register by voice'),
        actions: [
          TextButton(
            onPressed: busy ? null : openManual,
            child: const Text('Manual'),
          ),
        ],
      ),
      body: phase == _VoicePhase.capture
          ? _buildCapture(requestTime)
          : _buildReview(requestTime),
    );
  }

  Widget _buildCapture(String requestTime) {
    final statusLine = switch (recState) {
      _RecState.starting => 'Starting microphone…',
      _RecState.listening => 'Listening — speak now ($secondsLeft s left)',
      _RecState.processing => 'Processing speech…',
      _RecState.idle => speechAvailable
          ? 'Tap the mic, speak naturally, then Stop — or pause and it finishes for you.'
          : initTried
              ? 'Speech unavailable — use manual registration below.'
              : 'Preparing speech recognition…',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const InfoNote(
          'Speak in Hinglish. Audio is not stored. Owner approval is still required after you review.',
        ),
        const SizedBox(height: 10),
        billDetailLine('Entry request time', requestTime),
        const SizedBox(height: 18),
        Center(
            child: _MicButton(
          pulse: _pulse,
          bars: _bars,
          soundLevel: soundLevel,
          recState: recState,
          secondsLeft: secondsLeft,
          enabled: !busy && speechAvailable,
          onTap: () {
            if (listening || recState == _RecState.processing) {
              stopRecording();
            } else if (!starting) {
              startRecording();
            }
          },
        )),
        const SizedBox(height: 14),
        const Text(
          'Register Visitor by Voice',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontWeight: FontWeight.w900, color: C.navy, fontSize: 18),
        ),
        const SizedBox(height: 6),
        Text(
          statusLine,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: listening ? C.error : C.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (listening) ...[
          const SizedBox(height: 6),
          const Text(
            'Say name, mobile, flat and purpose in one go. Tap Stop when finished.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: C.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
        if (!listening && !starting) ...[
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Container(
              key: ValueKey(exampleIndex),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.chip,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Try: “${_kExamples[exampleIndex]}”',
                style: const TextStyle(
                    color: C.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy || listening || starting || !speechAvailable
                    ? null
                    : () => startRecording(),
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Start'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed:
                    busy || (!listening && recState != _RecState.processing)
                        ? null
                        : stopRecording,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    busy || (recState == _RecState.idle && transcript.isEmpty)
                        ? null
                        : cancelRecording,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
            ),
          ],
        ),
        if (listening) ...[
          const SizedBox(height: 12),
          _LiveLevelBar(level: soundLevel, anim: _bars),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: 1 - (secondsLeft / _kListenFor.inSeconds),
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: C.line,
            color: C.blue,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.error.withValues(alpha: 0.35)),
            ),
            child: const Row(
              children: [
                Icon(Icons.graphic_eq, color: C.error),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mic is live — stops after silence or when you tap Stop. Not listening in the background.',
                    style: TextStyle(
                        color: C.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (transcript.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text('Live transcript',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, color: C.navy)),
              ),
              if (!listening && !starting) ...[
                TextButton(
                  onPressed: busy ? null : () => startRecording(append: true),
                  child: const Text('Continue'),
                ),
                TextButton(
                  onPressed: busy ? null : () => startRecording(append: false),
                  child: const Text('Re-record'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transcript,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: C.charcoal,
                      height: 1.35),
                ),
                if (listening) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: C.error
                                .withValues(alpha: 0.2 + 0.8 * _bars.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Listening… keep speaking',
                          style: TextStyle(
                              color: C.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!listening && !starting) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: transcript.isEmpty ? null : _goToReview,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review extracted details'),
            ),
            const SizedBox(height: 4),
            const Text(
              'If the mic stopped early, tap Continue and finish the remaining details.',
              style: TextStyle(
                  color: C.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!,
              style:
                  const TextStyle(color: C.error, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 18),
        TextButton.icon(
          onPressed: busy ? null : openManual,
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('Manual registration fallback'),
        ),
      ],
    );
  }

  Widget _buildReview(String requestTime) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const InfoNote(
          'Confirm or correct every field. Amber fields need attention. Owner approval is still required — voice never auto-submits.',
        ),
        const SizedBox(height: 10),
        billDetailLine('Entry request time', requestTime),
        if (transcript.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('From speech',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: C.navy, fontSize: 12)),
          const SizedBox(height: 4),
          Text(transcript,
              style: const TextStyle(color: C.muted, fontSize: 13)),
        ],
        if (missingFields.isNotEmpty || uncertainFields.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            [
              if (missingFields.isNotEmpty)
                'Missing: ${missingFields.join(', ')}',
              if (uncertainFields.isNotEmpty)
                'Check: ${uncertainFields.join(', ')}',
            ].join(' · '),
            style: const TextStyle(
                color: C.amber, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: _fieldDecoration(
              label: 'Visitor full name *',
              fieldKey: 'name',
              icon: Icons.badge_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: mobile,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _fieldDecoration(
            label: 'Mobile number *',
            fieldKey: 'mobile',
            icon: Icons.phone_android,
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _kVisitorCategories.contains(category)
              ? category
              : _kVisitorCategories.first,
          decoration:
              _fieldDecoration(label: 'Visitor category', fieldKey: 'category'),
          items: _kVisitorCategories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: busy ? null : (v) => setState(() => category = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: purpose,
          maxLines: 2,
          decoration: _fieldDecoration(
              label: 'Purpose of visit *', fieldKey: 'purpose'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: wing,
          decoration: _fieldDecoration(
              label: 'Destination wing *', fieldKey: 'flatNumber'),
          items: _kSocietyWings
              .map((w) => DropdownMenuItem(value: w, child: Text('Wing $w')))
              .toList(),
          onChanged: busy
              ? null
              : (v) async {
                  setState(() => wing = v!);
                  await _loadFlatsForWing();
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('voice-flat-$wing-${flatOptions.length}-$selectedFlat'),
          initialValue:
              selectedFlat != null && flatOptions.contains(selectedFlat)
                  ? selectedFlat
                  : null,
          decoration: _fieldDecoration(
            label: 'Destination flat number *',
            fieldKey: 'flatNumber',
            icon: Icons.apartment_outlined,
          ),
          items: flatOptions
              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
              .toList(),
          onChanged: busy || flatOptions.isEmpty
              ? null
              : (v) => setState(() => selectedFlat = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: vehicle,
          textCapitalization: TextCapitalization.characters,
          decoration: _fieldDecoration(
            label: 'Vehicle registration (optional)',
            fieldKey: 'vehicleNumber',
            icon: Icons.directions_car_outlined,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!,
              style:
                  const TextStyle(color: C.error, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : submit,
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : const Text('Submit Approval Request',
                  style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  await cancelRecording();
                  setState(() => phase = _VoicePhase.capture);
                },
          icon: const Icon(Icons.mic_none),
          label: const Text('Record again'),
        ),
        TextButton(
          onPressed: busy ? null : openManual,
          child: const Text('Switch to manual registration'),
        ),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.pulse,
    required this.bars,
    required this.soundLevel,
    required this.recState,
    required this.secondsLeft,
    required this.enabled,
    required this.onTap,
  });

  final AnimationController pulse;
  final AnimationController bars;
  final double soundLevel;
  final _RecState recState;
  final int secondsLeft;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final listening = recState == _RecState.listening;
    final starting = recState == _RecState.starting;
    final processing = recState == _RecState.processing;
    final levelNorm = (soundLevel / 10).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: Listenable.merge([pulse, bars]),
      builder: (context, child) {
        final ring =
            listening ? 1.0 + (pulse.value * 0.12) + (levelNorm * 0.1) : 1.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (listening) ...[
              Transform.scale(
                scale: ring + 0.15,
                child: Container(
                  width: 168,
                  height: 168,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: C.error.withValues(alpha: 0.08 + levelNorm * 0.1),
                  ),
                ),
              ),
              Transform.scale(
                scale: ring,
                child: Container(
                  width: 168,
                  height: 168,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            C.error.withValues(alpha: 0.35 + levelNorm * 0.4),
                        width: 3),
                  ),
                ),
              ),
            ],
            Material(
              color: listening || processing
                  ? C.error
                  : starting
                      ? C.softBlue
                      : enabled
                          ? C.blue
                          : C.muted,
              shape: const CircleBorder(),
              elevation: listening ? 8 : 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled || listening || processing ? onTap : null,
                child: SizedBox(
                  width: 148,
                  height: 148,
                  child: starting || processing
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.6))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              listening ? Icons.mic : Icons.mic_none_rounded,
                              color: Colors.white,
                              size: 52,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              listening ? '${secondsLeft}s' : 'Tap to speak',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LiveLevelBar extends StatelessWidget {
  const _LiveLevelBar({required this.level, required this.anim});
  final double level;
  final AnimationController anim;

  @override
  Widget build(BuildContext context) {
    final n = (level / 10).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(12, (i) {
            final target = math.sin((i / 12) * math.pi) * (0.25 + n * 0.75);
            final h = 8 + target * 28 * (0.7 + anim.value * 0.3);
            return Container(
              width: 6,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Color.lerp(C.blue, C.error, n)!,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        );
      },
    );
  }
}
