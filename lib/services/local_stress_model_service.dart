import 'dart:math';

class StressModelInput {
  const StressModelInput({
    required this.avgMoodIndex,
    required this.avgMoodIntensity,
    required this.avgDailySteps,
    required this.moodLogCoverage,
    required this.journalEntryCount,
    required this.activeTaskCount,
    required this.completedTaskCount,
    required this.overdueTaskCount,
    this.journalWarningWeight = 0,
  });

  final double avgMoodIndex;
  final double avgMoodIntensity;
  final double avgDailySteps;
  final double moodLogCoverage;
  final int journalEntryCount;
  final int activeTaskCount;
  final int completedTaskCount;
  final int overdueTaskCount;
  final double journalWarningWeight;
}

class StressModelResult {
  const StressModelResult({
    required this.score,
    required this.rank,
    required this.confidence,
    required this.modelVersion,
    required this.rationale,
  });

  final double score;
  final String rank;
  final double confidence;
  final String modelVersion;
  final List<String> rationale;
}

class LocalStressModelService {
  const LocalStressModelService._();

  static const modelVersion = 'local-minimized-v1';

  static StressModelResult analyze(StressModelInput input) {
    final lowMoodSignal = ((3 - input.avgMoodIndex).clamp(0, 3) / 3);
    final moodIntensitySignal = input.avgMoodIntensity.clamp(0, 1);
    final lowActivitySignal =
        ((4000 - input.avgDailySteps).clamp(0, 4000) / 4000);
    final journalSignal = min(input.journalEntryCount, 12) / 12;
    final overdueTaskSignal = min(input.overdueTaskCount, 8) / 8;
    final activeTaskSignal = min(input.activeTaskCount, 12) / 12;
    final completionRelief = min(input.completedTaskCount, 12) / 12;
    final journalWarningSignal = input.journalWarningWeight.clamp(0, 1);

    final moodIntensityWeight = input.avgMoodIndex <= 1.5 ? 18 : -10;
    final weighted =
        lowMoodSignal * 38 +
        moodIntensitySignal * moodIntensityWeight +
        lowActivitySignal * 16 +
        journalSignal * 8 +
        overdueTaskSignal * 16 +
        activeTaskSignal * 6 +
        journalWarningSignal * 24 -
        completionRelief * 6;

    final score = weighted.clamp(0, 100).toDouble();
    final confidence = _confidence(input);

    return StressModelResult(
      score: score,
      rank: rankForScore(score),
      confidence: confidence,
      modelVersion: modelVersion,
      rationale: _rationale(
        input: input,
        lowMoodSignal: lowMoodSignal,
        lowActivitySignal: lowActivitySignal,
        overdueTaskSignal: overdueTaskSignal,
      ),
    );
  }

  static String rankForScore(double score) {
    if (score >= 70) return 'High';
    if (score >= 45) return 'Elevated';
    if (score >= 25) return 'Moderate';
    return 'Low';
  }

  static double _confidence(StressModelInput input) {
    final signals = [
      input.moodLogCoverage > 0,
      input.avgDailySteps > 0,
      input.journalEntryCount > 0,
      input.journalWarningWeight > 0,
      input.activeTaskCount +
              input.completedTaskCount +
              input.overdueTaskCount >
          0,
    ].where((ready) => ready).length;

    final coverageBoost = input.moodLogCoverage.clamp(0, 1) * 0.25;
    final signalBoost = signals / 5 * 0.65;

    return (0.1 + coverageBoost + signalBoost).clamp(0, 1).toDouble();
  }

  static List<String> _rationale({
    required StressModelInput input,
    required double lowMoodSignal,
    required double lowActivitySignal,
    required double overdueTaskSignal,
  }) {
    final reasons = <String>[];

    if (lowMoodSignal >= 0.5) {
      reasons.add('lower recent mood');
    }
    if (input.avgMoodIntensity >= 0.7 && input.avgMoodIndex <= 1.5) {
      reasons.add('high intensity on low mood');
    }
    if (lowActivitySignal >= 0.5) {
      reasons.add('low step activity');
    }
    if (overdueTaskSignal > 0) {
      reasons.add('overdue tasks');
    }
    if (input.journalWarningWeight >= 0.8) {
      reasons.add('critical journal warning');
    } else if (input.journalWarningWeight >= 0.5) {
      reasons.add('elevated journal warning');
    } else if (input.journalWarningWeight > 0) {
      reasons.add('normal stress journal signal');
    }
    if (input.journalEntryCount > 0) {
      reasons.add('journal activity present');
    }
    if (reasons.isEmpty) {
      reasons.add('balanced recent signals');
    }

    return reasons.take(3).toList();
  }
}
