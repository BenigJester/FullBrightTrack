import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_and_wellbeing/services/display_name_service.dart';

void main() {
  test('display names are capped to six characters', () {
    expect(DisplayNameService.cleanForDisplay('Benjamin'), 'Benjam');
  });

  test('display name validation requires three to six characters', () {
    expect(DisplayNameService.validationError('Bo'), isNotNull);
    expect(DisplayNameService.validationError('Benign'), isNull);
    expect(DisplayNameService.validationError('Benigno'), isNotNull);
  });
}
