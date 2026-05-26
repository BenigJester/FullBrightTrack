import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_and_wellbeing/services/wellness_signal_service.dart';

void main() {
  test('step average uses recorded positive step days only', () {
    final average = WellnessSignalService.averageRecordedDailySteps([
      6000,
      0,
      4000,
    ]);

    expect(average, 5000);
  });

  test('step average returns zero when no positive steps are recorded', () {
    final average = WellnessSignalService.averageRecordedDailySteps([0, 0]);

    expect(average, 0);
  });
}
