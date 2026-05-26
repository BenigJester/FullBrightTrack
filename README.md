# FullBrightTrack

FullBrightTrack is a Flutter productivity and wellbeing app for students. It combines step tracking, mood check-ins, journaling, task management, streak tracking, and Firestore leaderboards in one mobile experience.

Current app version: `0.3.0-alpha`

## Features

- Native Android step tracking with a foreground pedometer service.
- Background step persistence using local storage and Firestore sync.
- Step goal progress, calories, distance, streaks, and health insights.
- Mood check-in with intensity tracking and daily popup reminder.
- Journal entries with prompts, history, filters, and Firestore storage.
- Task management with deadlines, overdue state, completion, and collapsible sections.
- Streak dashboard for step and mood consistency.
- Firestore leaderboard using combined step and mood streak points.
- Account flows for email/password and Google sign-in.
- Hourly step reminder notification support.
- Daily motivation popup.

## Tech Stack

- Flutter / Dart
- Firebase Auth
- Cloud Firestore
- Google Sign-In
- Provider state management
- SharedPreferences local persistence
- Workmanager background jobs
- Flutter Local Notifications
- Native Android Kotlin foreground service

## Project Structure

```text
lib/
  main.dart
  models/
    app_data.dart
  screens/
    appbar.dart
    home_screen.dart
    home_tab.dart
    steps_tab.dart
    mood_screen.dart
    journal_screen.dart
    journal_history.dart
    tasks_tab.dart
    streaks_tab.dart
    leaderboards_screen.dart
    other_screen.dart
    login_screen.dart
    register_screen.dart
  services/
    auth_service.dart
    hometab_service.dart
    hourly_worker.dart
    journal_service.dart
    leaderboard_service.dart
    moodscreen_service.dart
    notification_service.dart
    quote_service.dart
    step_foreground_service.dart
    step_local_store.dart
    steps_service.dart
    streak_service.dart

android/app/src/main/kotlin/com/productivity/and/wellbeing/
  MainActivity.kt
  StepBootReceiver.kt
  StepCounterService.kt

test/
  refresh_controllers_test.dart
  startup_optimization_test.dart
  tasks_tab_logic_test.dart
```

## Requirements

- Flutter SDK compatible with Dart `^3.10.8`
- Android Studio or VS Code with Flutter tooling
- Firebase project configured for Android
- Android device or emulator with step sensor support for pedometer testing

## Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Configure Firebase:

- Add your Firebase Android app.
- Place `google-services.json` in `android/app/`.
- Enable Firebase Auth providers used by the app:
  - Email/password
  - Google
- Enable Cloud Firestore.

3. Run the app:

```bash
flutter run
```

## Firestore Data

Private user data is stored under:

```text
users/{uid}
users/{uid}/steps/{yyyy-MM-dd}
users/{uid}/mood/{yyyy-MM-dd}
users/{uid}/journal/{journalId}
users/{uid}/tasks/{taskId}
```

Public leaderboard summaries are stored under:

```text
leaderboard/{uid}
```

The leaderboard summary contains public ranking fields such as first name, photo URL, monthly steps, step streak, mood streak, and streak points.

## Suggested Firestore Rules

This app expects users to access their own private data and read public leaderboard summaries. Adjust as needed for your deployment.

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null
                          && request.auth.uid == userId;
    }

    match /leaderboard/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
                   && request.auth.uid == userId;
    }
  }
}
```

## Android Step Tracking

Step tracking is handled by a native Kotlin foreground service:

```text
StepCounterService.kt
```

The service uses Android step sensors and stores the current step state in SharedPreferences so Flutter can restore and sync it later.

Important Android permissions:

- `ACTIVITY_RECOGNITION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_HEALTH`
- `POST_NOTIFICATIONS`
- `RECEIVE_BOOT_COMPLETED`
- `WAKE_LOCK`

The app also includes `StepBootReceiver.kt` so the service can restart after boot/package update when Android allows it.

## Testing

Run analyzer:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

Current test coverage includes:

- Refresh controller presence
- Startup/loading behavior
- Task parsing and deadline logic

## Development Notes

- Step counts are saved locally first and synced to Firestore when possible.
- The leaderboard is Firestore-only and uses public summary documents.
- Step streaks preserve the current streak during the unfinished current day and reset the next day if no goal is reached.
- Midnight step rollover saves the previous day under its correct date before starting the new day.
- Native step counter and detector events are reconciled to avoid double counting while keeping closed-app step updates live.

## License

This project is for academic/thesis development. Add a license if you plan to distribute it publicly.
