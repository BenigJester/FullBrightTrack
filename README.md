# FullBrightTrack

FullBrightTrack is a Flutter productivity and wellbeing app for students. It combines step tracking, mood check-ins, journaling, task management, streak tracking, and Firestore leaderboards in one mobile experience.

Current app version: `0.4.0-alpha+5`

## Features

- Native Android step tracking with a foreground pedometer service.
- Background step persistence using local storage and Firestore sync.
- Step goal progress, calories, distance, streaks, and health insights.
- Mood check-in with intensity tracking and daily popup reminder.
- Journal entries with prompts, history, filters, and Firestore storage.
- Weighted journal warning detection for normal stress, elevated concern, and critical danger phrases.
- Task management with deadlines, overdue state, completion, and collapsible sections.
- Streak dashboard for step and mood consistency.
- Firestore leaderboard using combined step and mood streak points.
- Admin Monitoring for minimized wellbeing summaries, stress ranking, charts, and warning signals.
- Admin warning resolution workflow and daily stress history charting.
- Groq-backed AI stress estimate endpoint with local fallback scoring.
- Account flows for email/password and Google sign-in.
- App Check support for Firebase protection with debug-token support for development builds.
- Step reminder notification support with 1, 2, or 3 hour intervals.
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
- Firebase App Check
- Groq AI backend on Render or another Docker host

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
    admin_monitoring_screen.dart
    tasks_tab.dart
    streaks_tab.dart
    leaderboards_screen.dart
    other_screen.dart
    login_screen.dart
    register_screen.dart
  services/
    auth_service.dart
    app_check_service.dart
    display_name_service.dart
    genkit_stress_ai_service.dart
    hometab_service.dart
    hourly_worker.dart
    journal_service.dart
    journal_warning_service.dart
    leaderboard_service.dart
    local_stress_model_service.dart
    moodscreen_service.dart
    notification_service.dart
    quote_service.dart
    reminder_scheduler_service.dart
    step_foreground_service.dart
    step_local_store.dart
    steps_service.dart
    streak_service.dart
    wellness_signal_service.dart

genkit_backend/
  bin/server.dart
  Dockerfile
  README.md

android/app/src/main/kotlin/com/productivity/and/wellbeing/
  MainActivity.kt
  StepBootReceiver.kt
  StepReminderReceiver.kt
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
- Configure Firebase App Check for Android. Use debug provider only for debug builds and Play Integrity for release.
- When running a debug build, check the Flutter console for `Firebase App Check debug token to register: ...`, then add that token in Firebase Console under App Check > your Android app > Manage debug tokens.

3. Configure the AI backend:

- Deploy `genkit_backend` to Render or another Docker host.
- Set `GROQ_API_KEY` as a server environment variable.
- Use the deployed `/stress` endpoint when running or building Flutter.

4. Run the app:

```bash
flutter run --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```

For local Android emulator testing against a local backend, use:

```bash
flutter run --dart-define=GENKIT_STRESS_FLOW_URL=http://10.0.2.2:8080/stress
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

Minimized admin monitoring summaries are stored under:

```text
admin_monitoring/{uid}
```

These summaries contain numeric wellbeing signals, weighted journal warning severity, AI/local stress score, rank, confidence, daily stress history, and privacy-safe critical warning labels. Raw journal text and task titles are not copied into admin monitoring.

Privacy-safe admin alert records are stored under:

```text
admin_alerts/{alertId}
admin_fcm_tokens/{adminUid}/tokens/{token}
```

`admin_alerts` stores only review metadata, the affected user id, display name, stress rank, score, status, and warning signature. It does not store raw journal text. `admin_fcm_tokens` stores verified admin device tokens so a trusted backend or Cloud Function can send FCM push notifications for active alerts.

## Suggested Firestore Rules

This app expects users to access their own private data, read public leaderboard summaries, and write only their own minimized admin monitoring summary. Admin access is controlled by `users/{uid}.isAdmin == true`.

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return signedIn() && request.auth.uid == userId;
    }

    function isAdmin() {
      return signedIn()
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
    }

    match /users/{userId}/{document=**} {
      allow read: if isOwner(userId) || isAdmin();
      allow write: if isOwner(userId);
    }

    match /leaderboard/{userId} {
      allow read: if signedIn();
      allow write: if isOwner(userId);
    }

    match /admin_monitoring/{userId} {
      allow read: if isAdmin();
      allow create, update: if isOwner(userId);
      allow update: if isAdmin()
        && request.resource.data.diff(resource.data).changedKeys()
          .hasOnly(['resolvedWarningSignature', 'resolvedWarningAt']);
      allow delete: if false;
    }

    match /admin_alerts/{alertId} {
      allow read: if isAdmin();
      allow create: if signedIn()
        && request.resource.data.userId == request.auth.uid;
      allow update: if signedIn()
        && resource.data.userId == request.auth.uid
        && request.resource.data.userId == resource.data.userId;
      allow update: if isAdmin()
        && request.resource.data.diff(resource.data).changedKeys()
          .hasOnly(['status', 'resolvedAt', 'updatedAt']);
      allow delete: if false;
    }

    match /admin_fcm_tokens/{adminUid}/tokens/{tokenId} {
      allow read: if false;
      allow create, update, delete: if isOwner(adminUid) && isAdmin();
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
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`

The app also includes `StepBootReceiver.kt` so the service can restart after boot/package update when Android allows it.

After login, the app checks notification, physical activity, and battery optimization status. If any access is denied or restricted, it shows a user-friendly dialog explaining which features are limited. The `Allow` buttons request the matching Android permission without automatically redirecting to App Info. Explicit management links remain available in More > Permissions through `Manage / disable` and `Choose battery mode`.

When both physical activity and notification access are granted, the app starts the step foreground service so Android can show the persistent step-tracking notification. Battery unrestricted access uses Android's direct allow dialog and refreshes the access prompt when the app resumes.

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
- Display name validation
- Stress scoring direction for step activity
- Wellness signal step averaging
- Multilingual journal warning detection with privacy-safe labels

## Development Notes

- Step counts are saved locally first and synced to Firestore when possible.
- The leaderboard is Firestore-only and uses public summary documents.
- Step streaks preserve the current streak during the unfinished current day and reset the next day if no goal is reached.
- Midnight step rollover saves the previous day under its correct date before starting the new day.
- Native step counter and detector events are reconciled to avoid double counting while keeping closed-app step updates live.

## License

This project is for academic/thesis development. Add a license if you plan to distribute it publicly.
