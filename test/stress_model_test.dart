import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_and_wellbeing/services/local_stress_model_service.dart';

void main() {
  test('higher steps lower the local stress estimate', () {
    const lowSteps = StressModelInput(
      avgMoodIndex: 2,
      avgMoodIntensity: 0.5,
      avgDailySteps: 500,
      moodLogCoverage: 0.6,
      journalEntryCount: 1,
      activeTaskCount: 2,
      completedTaskCount: 1,
      overdueTaskCount: 0,
    );
    const highSteps = StressModelInput(
      avgMoodIndex: 2,
      avgMoodIntensity: 0.5,
      avgDailySteps: 9000,
      moodLogCoverage: 0.6,
      journalEntryCount: 1,
      activeTaskCount: 2,
      completedTaskCount: 1,
      overdueTaskCount: 0,
    );

    final lowStepResult = LocalStressModelService.analyze(lowSteps);
    final highStepResult = LocalStressModelService.analyze(highSteps);

    expect(highStepResult.score, lessThan(lowStepResult.score));
  });
}
