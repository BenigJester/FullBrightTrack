import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'step_background_handler.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(StepBackgroundHandler());
}
