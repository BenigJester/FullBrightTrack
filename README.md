# FullBrightTrack

FullBrightTrack is a Flutter productivity and wellbeing app for students. It combines step tracking, mood check-ins, journaling, task management, streak tracking, and Firestore leaderboards in one mobile experience.

Current app version: `1.0.4`

## Features

- Native Android step tracking with a foreground pedometer service.
- Background step persistence using local storage and Firestore sync.
- Step goal progress, calories, distance, streaks, and health insights.
- Mood check-in with intensity tracking and daily popup reminder.
- Professional AI mood status view based on the latest consented wellness signal output.
- Journal entries with prompts, history, filters, and Firestore storage.
- AI-assisted journal warning detection for normal stress, elevated concern, critical danger phrases, harm toward others, threats, harassment/coercion, explicit unsafe wording, and Philippine language signals.
- Task management with deadlines, overdue state, completion, and collapsible sections.
- Streak dashboard for step and mood consistency.
- Firestore leaderboard using combined step and mood streak points with short cache on reopen and pull-to-refresh reload.
- Admin Monitoring for wellbeing summaries, stress ranking, rank filters, confidence sorting, paged review, Week/Month charts, warning signals, contact calling, and alert-target highlighting.
- Admin warning resolution workflow and daily stress history charting.
- Admin warning verification supports support-provided and false-positive outcomes.
- Groq-backed AI stress estimate endpoint with consent-gated raw wellness payloads.
- Account flows for email/password and Google sign-in, with backend-sent registration confirmation links, provider-link confirmation, and account contact information.
- Login consent gate for processing raw wellness data such as mood, journal, task, and step records for AI insights and safety alerts.
- App Check support for Firebase protection with debug-token support for development builds.
- App-wide internet checker with retry/exit dialog for airplane mode, no Wi-Fi/mobile data, Wi-Fi without internet, unreachable backend, and very slow internet.
- Backend worker support for sending admin FCM safety alerts from `admin_alerts` to registered `admin_fcm_tokens`; tapping alerts refreshes Admin Monitoring and opens the matching user.
- Daily motivation popup.

## Tech Stack

- Flutter / Dart
- Firebase Auth
- Cloud Firestore
- Google Sign-In
- Provider state management
- SharedPreferences local persistence
- Flutter Local Notifications
- Native Android Kotlin foreground service
- Firebase App Check
- Groq AI backend on Render or another Docker host
- Brevo HTTPS email API for Render-friendly registration confirmation delivery
- Developer console access is controlled with `users/{uid}.role == "developer"`.

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
    journal_service.dart
    journal_warning_service.dart
    leaderboard_service.dart
    local_stress_model_service.dart
    moodscreen_service.dart
    notification_service.dart
    quote_service.dart
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
- App Check is enabled by default. Debug builds use the debug provider and print the token that must be registered in Firebase Console. Release builds use Play Integrity.
- Optional explicit debug App Check run command:
  `flutter run --dart-define=USE_APP_CHECK_DEBUG=true`
- When using debug App Check, check the Flutter console for `Firebase App Check debug token to register: ...`, then add that exact token in Firebase Console under App Check > your Android app > Manage debug tokens.

3. Configure the backend:

- Deploy `genkit_backend` to Render or another Docker host.
- Set `GROQ_API_KEY` as a server environment variable.
- Set `FIREBASE_SERVICE_ACCOUNT_JSON`, `FIREBASE_WEB_API_KEY`, `PUBLIC_BASE_URL`, `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, and `BREVO_SENDER_NAME` on the backend if registration confirmation emails are enabled.
- Use both the deployed backend base URL and `/stress` endpoint when running or building Flutter.
- Debug builds default to `http://10.0.2.2:8080/stress` if `GENKIT_STRESS_FLOW_URL` is not provided, which is useful for Android emulator testing against a local backend.
- Users must agree to the raw wellness data processing consent on login before raw mood, journal, task, and step records are sent to the AI backend. AI-dependent online reviews require internet access and a reachable backend.

4. Configure admin FCM alerts, optional but recommended for admin safety review:

The same backend service watches/polls admin alert records through `/admin-alert-worker`. Set this environment variable on Render or locally if you want automatic polling:

```powershell
$env:ADMIN_ALERT_WORKER_INTERVAL_SECONDS="60"
```

For manual testing, call the worker:

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/admin-alert-worker" -Method Post
```

To test registered admin/developer FCM tokens directly:

```powershell
$body = @{
  title = "FullBrightTrack test alert"
  body  = "Admin FCM token delivery is working."
} | ConvertTo-Json

Invoke-RestMethod `
  -Uri "http://localhost:8080/test-admin-notification" `
  -Method Post `
  -ContentType "application/json" `
  -Body $body |
ConvertTo-Json -Depth 5
```

5. Run the app:

```bash
flutter run --flavor user --dart-define=FULLBRIGHT_BACKEND_URL=https://YOUR_RENDER_SERVICE.onrender.com --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```

For local Android emulator testing against a local backend, use:

```bash
flutter run --flavor user --dart-define=FULLBRIGHT_BACKEND_URL=http://10.0.2.2:8080 --dart-define=GENKIT_STRESS_FLOW_URL=http://10.0.2.2:8080/stress
```

For debug builds only, the app also falls back to this local emulator URL when `GENKIT_STRESS_FLOW_URL` is omitted.

6. Run the developer app:

```bash
flutter run --flavor developer -t lib/developer/developer_app.dart --dart-define=FULLBRIGHT_BACKEND_URL=http://10.0.2.2:8080
```

For a release/demo APK with App Check debug token support:

```bash
flutter build apk --release --flavor developer -t lib/developer/developer_app.dart --dart-define=USE_APP_CHECK_DEBUG=true --dart-define=APP_CHECK_DEBUG_TOKEN=YOUR_VERSION_4_UUID
```

The developer app uses package `com.productivity.and.wellbeing.developer`, so it must have its own Firebase Android app, OAuth clients, App Check registration, and matching SHA-1/SHA-256 fingerprints.

## Account And Backend How-To

### Registration Confirmation

1. User enters email/password in the register screen.
2. Flutter calls `/start-registration`.
3. Backend stores `pending_registrations/{requestId}` and sends a Brevo email.
4. User opens the email link.
5. The browser shows a confirmation page.
6. The Firebase Auth account is created only after the user presses `Confirm and create account`.
7. User returns to the login screen and signs in.

For local testing, start the backend with:

```powershell
$env:EMAIL_DEBUG_RETURN_LINK="true"
```

Then call:

```powershell
$body = @{
  email = "student@example.com"
  password = "studentPassword123"
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "http://localhost:8080/start-registration" -Method Post -ContentType "application/json" -Body $body
```

### Password Reset

1. User chooses reset password in Login or Account Information.
2. Flutter calls `/request-password-reset`.
3. Backend checks that the email exists in Firebase Auth before sending anything.
4. Backend emails a one-time reset link that expires in 5 minutes.
5. User opens the link, enters the new password, then presses `Update password`.
6. Backend updates the Firebase Auth password only after the reset token is valid and unused.

### Account Information Actions

Account Information switches its action button based on linked Firebase providers:

- Google-only account: `Add Password`
- Email/password-only account: `Verify with Google Sign-In` and `Reset Password`
- Account with both providers: `Reset Password`

Users can also maintain a Philippine mobile contact number and relationship label. This contact is mirrored to Admin Monitoring so admins can call a saved support contact when review requires it.

The developer app uses the same account action logic and adds hide/show controls to password fields.

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

These summaries contain numeric wellbeing signals, weighted journal warning severity, AI/local stress score, rank, confidence, AI mood status, daily stress history, and privacy-safe critical warning labels. Raw journal text and task titles are not copied into admin monitoring.

When a user gives raw AI processing consent at login, recent raw mood, journal, task, and step records may be sent to the configured AI backend for scoring. That raw payload is used by the backend request and is not copied into `admin_monitoring`.

If online AI is unavailable, AI-dependent actions fail visibly instead of silently replacing the result with fallback scoring. Native step tracking remains offline-capable and syncs when Firestore is reachable.

Privacy-safe admin alert records are stored under:

```text
admin_alerts/{alertId}
admin_fcm_tokens/{adminUid}/tokens/{token}
```

`admin_alerts` stores only review metadata, the affected user id, display name, stress rank, score, status, warning signature, and push delivery status. It does not store raw journal text. `admin_fcm_tokens` stores verified admin/developer device tokens so the backend worker can send FCM push notifications for active alerts.

When an admin taps an active safety alert or its notification history item, the app refreshes Admin Monitoring from the server first, then highlights the matching user.

## Suggested Firestore Rules

This app expects users to access their own private data, read public leaderboard summaries, and write only their own minimized admin monitoring summary. Admin and developer access is controlled by `users/{uid}.role`, using `user`, `admin`, or `developer`.
Email verification is not required by the current app flow, so these rules intentionally do not check `request.auth.token.email_verified`.

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

    function role() {
      return signedIn()
        ? get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role
        : null;
    }

    function hasAdminAccess() {
      return signedIn()
        && (role() == 'admin' || role() == 'developer');
    }

    function hasDeveloperRole() {
      return signedIn()
        && role() == 'developer';
    }

    match /users/{userId} {
      allow read: if isOwner(userId) || hasAdminAccess();
      allow create: if isOwner(userId)
        && (!request.resource.data.keys().hasAny(['role'])
          || request.resource.data.role == 'user');
      allow update: if isOwner(userId)
        && !request.resource.data.diff(resource.data).changedKeys()
          .hasAny(['role']);
      allow delete: if false;
    }

    match /users/{userId}/{document=**} {
      allow read: if isOwner(userId) || hasAdminAccess();
      allow create, update, delete: if isOwner(userId);
    }

    match /leaderboard/{userId} {
      allow read: if signedIn();
      allow write: if isOwner(userId);
    }

    match /admin_monitoring/{userId} {
      allow read: if isOwner(userId) || hasAdminAccess();
      allow create, update: if isOwner(userId);
      allow update: if hasAdminAccess()
        && request.resource.data.diff(resource.data).changedKeys()
          .hasOnly([
            'resolvedWarningSignature',
            'resolvedWarningSignatures',
            'resolvedWarningAt',
            'warningJournals',
            'warningSnippets',
            'warningFindings',
            'warningSignature',
            'warningJournalId',
            'warningJournalText',
            'warningJournalCreatedAt',
            'journalWarningWeight',
            'journalWarningSeverity',
            'hasDangerWarning',
            'stressScore',
            'stressRank',
            'confidence',
            'aiMoodIndex',
            'aiMoodIntensity',
            'aiMoodStatus',
            'aiMoodStatusUpdatedAt',
            'rationale',
            'supportResolutionStatus',
            'supportResolutionNote',
            'supportResolutionType',
            'supportResolutionUpdatedAt',
            'resolvedWarningJournals',
            'stressHistory',
            'updatedAt'
          ]);
      allow delete: if false;
    }

    match /admin_alerts/{alertId} {
      allow read: if hasAdminAccess();
      allow create: if signedIn()
        && request.resource.data.userId == request.auth.uid;
      allow update: if signedIn()
        && resource.data.userId == request.auth.uid
        && request.resource.data.userId == resource.data.userId
        && request.resource.data.diff(resource.data).changedKeys()
          .hasOnly(['pushStatus', 'pushUpdatedAt', 'updatedAt']);
      allow update: if hasAdminAccess()
        && request.resource.data.diff(resource.data).changedKeys()
          .hasOnly(['status', 'resolvedAt', 'updatedAt']);
      allow delete: if false;
    }

    match /admin_fcm_tokens/{adminUid}/tokens/{tokenId} {
      allow read: if false;
      allow create, update, delete: if isOwner(adminUid) && hasAdminAccess();
    }

    match /{document=**} {
      allow read, write: if hasDeveloperRole();
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
- `ACCESS_NETWORK_STATE`

The app also includes `StepBootReceiver.kt` so the service can restart after boot/package update when Android allows it.

After login, the app checks notification, physical activity, and battery optimization status. If any access is denied or restricted, it shows a user-friendly dialog explaining which features are limited. The `Allow` buttons request the matching Android permission without automatically redirecting to App Info. Explicit management links remain available in More > Permissions through `Manage / disable` and `Choose battery mode`.

When both physical activity and notification access are granted, the app starts the step foreground service so Android can show the persistent step-tracking notification. Battery unrestricted access uses Android's direct allow dialog and refreshes the access prompt when the app resumes.

The app also watches internet status while the user is inside the app. If online services become unavailable, it shows a professional dialog with `Retry connection` and `Exit app`. Android reports airplane mode, missing Wi-Fi/mobile data, Wi-Fi without internet, and weak/slow connection hints through a native connectivity channel. Native step tracking remains offline-capable; AI, account, Firestore, and admin alert services require working internet.

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
- Mood screen pull-to-refresh behavior for the AI status page

## Development Notes

- Step counts are saved locally first and synced to Firestore when possible.
- The leaderboard is Firestore-only and uses public summary documents.
- Raw AI scoring is consent-gated and requires the backend when AI output is needed.
- Admin Monitoring lists are filtered locally by rank, sorted by confidence, displayed in pages of 100 students, charted by Week or Month, and can store contact numbers after Philippine mobile validation.
- Admin FCM alerts require the backend worker route or `ADMIN_ALERT_WORKER_INTERVAL_SECONDS`; client-side token registration alone does not send push notifications. The Flutter app also registers a background FCM handler so admin alert/test payloads remain usable when the app is backgrounded or opened from a closed state.
- Admin FCM backend messages are sent as high-priority data payloads so the Flutter background handler can create the local Admin Safety Alert notification consistently.
- The app-wide internet guard uses the root navigator context before showing retry/exit dialogs, preventing startup crashes when the guard is mounted above the Navigator.
- Leaderboard results use a short in-memory cache when reopening the screen; pull-to-refresh bypasses the cache.
- Journal warning review uses the AI backend and fails visibly if the online service is unavailable. The AI prompt can ignore safe slang, jokes, quotes, or non-risk context.
- Step streaks preserve the current streak during the unfinished current day and reset the next day if no goal is reached.
- Midnight step rollover saves the previous day under its correct date before starting the new day.
- Native step counter and detector events are reconciled to avoid double counting while keeping closed-app step updates live.

## License

This project is for academic/thesis development. Add a license if you plan to distribute it publicly.
