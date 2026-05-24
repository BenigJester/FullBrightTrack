import 'dart:convert';
import 'dart:math';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StepLocalState {
  StepLocalState({
    required this.steps,
    required this.baseline,
    required this.initialSteps,
    required this.lastRawSteps,
    required this.anchorSteps,
    required this.baselineSet,
    required this.day,
    required this.debugText,
  });

  int steps;
  int baseline;
  int initialSteps;
  int lastRawSteps;
  int anchorSteps;
  bool baselineSet;
  String day;
  String debugText;

  Map<String, dynamic> toTaskData() {
    return {
      'steps': steps,
      'baseline': baseline,
      'initialSteps': initialSteps,
      'lastRawSteps': lastRawSteps,
      'anchorSteps': anchorSteps,
      'baselineSet': baselineSet,
      'day': day,
      'debugText': debugText,
    };
  }
}

class StepLocalStore {
  static const int maxStepSpike = 3000;

  static String todayKey() {
    final now = DateTime.now();

    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  static double caloriesFor(int steps) => steps * 0.04;

  static double distanceFor(int steps) => steps * 0.0008;

  static Future<StepLocalState> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final today = todayKey();
    final savedDay = prefs.getString('bg_day') ?? '';

    if (savedDay != today) {
      return StepLocalState(
        steps: 0,
        baseline: 0,
        initialSteps: 0,
        lastRawSteps: 0,
        anchorSteps: 0,
        baselineSet: false,
        day: today,
        debugText: 'Waiting for today steps...',
      );
    }

    final baseline = prefs.getInt('bg_baseline') ?? 0;

    return StepLocalState(
      steps: prefs.getInt('bg_steps') ?? 0,
      baseline: baseline,
      initialSteps: prefs.getInt('bg_initial_steps') ?? 0,
      lastRawSteps: prefs.getInt('bg_last_raw') ?? 0,
      anchorSteps: prefs.getInt('bg_anchor') ?? 0,
      baselineSet: baseline > 0,
      day: savedDay,
      debugText: prefs.getString('bg_debug') ?? 'Loaded local steps',
    );
  }

  static Future<StepLocalState> processStep(
    StepLocalState state,
    StepCount event,
  ) async {
    final raw = event.steps;
    final today = todayKey();

    if (state.day.isNotEmpty && state.day != today && state.steps > 0) {
      await enqueueSave(state, dayOverride: state.day);
    }

    if (state.day != today) {
      state
        ..day = today
        ..baseline = raw
        ..anchorSteps = 0
        ..initialSteps = 0
        ..steps = 0
        ..lastRawSteps = raw
        ..baselineSet = true
        ..debugText = 'New day reset\nRAW: $raw\nBASELINE RESET';

      await persist(state);
      await enqueueSave(state);
      return state;
    }

    if (!state.baselineSet) {
      state
        ..baseline = raw
        ..anchorSteps = 0
        ..lastRawSteps = raw
        ..baselineSet = true
        ..debugText = 'Baseline set\nRAW: $raw';

      await persist(state);
      return state;
    }

    if (raw < state.lastRawSteps) {
      state
        ..initialSteps = state.steps
        ..anchorSteps = state.steps
        ..baseline = raw
        ..lastRawSteps = raw
        ..debugText =
            'Sensor reset\nRAW: $raw\nSHIFT BASELINE\nINIT: ${state.initialSteps}';

      await persist(state);
      await enqueueSave(state);
      return state;
    }

    final diffRaw = raw - state.lastRawSteps;

    if (diffRaw > maxStepSpike) {
      state.debugText =
          'Spike ignored\nRAW: $raw\nLAST: ${state.lastRawSteps}\nDIFF: $diffRaw';

      await persist(state);
      return state;
    }

    final delta = max(0, raw - state.baseline);
    final computed = max(0, state.anchorSteps + delta);

    state
      ..steps = computed
      ..lastRawSteps = raw
      ..debugText =
          'RAW: $raw\nBASE: ${state.baseline}\nLAST: ${state.lastRawSteps}\nDELTA: $delta\nTOTAL: ${state.steps}';

    await persist(state);
    return state;
  }

  static Future<void> persist(StepLocalState state) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('bg_steps', state.steps);
    await prefs.setInt('bg_baseline', state.baseline);
    await prefs.setInt('bg_initial_steps', state.initialSteps);
    await prefs.setInt('bg_last_raw', state.lastRawSteps);
    await prefs.setString('bg_day', state.day);
    await prefs.setInt('bg_anchor', state.anchorSteps);
    await prefs.setString('bg_debug', state.debugText);
  }

  static Future<void> enqueueSave(
    StepLocalState state, {
    String? dayOverride,
  }) async {
    final day = dayOverride ?? state.day;
    if (day.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final raw = prefs.getString('steps_queue');
    final queue = <Map<String, dynamic>>[];

    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        queue.addAll(decoded.cast<Map<String, dynamic>>());
      }
    }

    queue.removeWhere((entry) => entry['day'] == day);
    queue.add({
      'day': day,
      'steps': state.steps,
      'baseline': state.baseline,
      'lastRawSteps': state.lastRawSteps,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (queue.length > 60) {
      queue.removeRange(0, queue.length - 60);
    }

    await prefs.setString('steps_queue', jsonEncode(queue));
  }
}
