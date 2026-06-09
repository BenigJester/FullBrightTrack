# FullBrightTrack Groq Backend

This is the server-side AI endpoint for Admin Monitoring stress scoring and the Mood tab AI status.

Backend version: `0.2.0`

It accepts a consent-gated raw wellness payload from the Flutter app plus a local numeric baseline for calibration and fallback. The raw payload can include recent steps, mood check-ins, journal text, journal warning labels, and task records. If the user has not agreed to raw data processing in the app, the Flutter client uses local fallback scoring instead of calling this endpoint.

The backend still returns compact structured scoring output only:

```json
{
  "score": 0,
  "rank": "Low",
  "confidence": 0.5,
  "modelVersion": "groq-llama-stress-v1",
  "rationale": ["balanced recent signals"]
}
```

The same `/stress` route also supports focused modes from the Flutter app:

- `mode: "journal-warning"` reviews raw journal text for safety warning severity.
- `mode: "journal-mood"` estimates mood index and intensity from raw journal text.
- `mode: "task-content"` checks whether a task title is safe and appropriate to save.

Journal warning review understands English and Philippine languages such as Tagalog, Cebuano, Ilocano, Hiligaynon, Waray, Kapampangan, Pangasinan, Bicolano, and mixed local-English writing. It can detect self-harm, harm toward others, threats, harassment/coercion, and explicit unsafe wording. The prompt also tells the model to ignore clearly safe slang, jokes, quoted media, academic discussion, or non-risk context.

The backend can also run thesis-demo account and admin alert workflows:

- `/start-registration` creates a pending email confirmation record.
- `/confirm-registration` shows a confirmation page; the Firebase Auth account is created only after the user presses the confirmation button.
- `/complete-registration` lets the Flutter app verify an already confirmed registration request.
- `/request-password-reset` creates a one-time reset token for an existing Firebase Auth user.
- `/confirm-password-reset` validates a reset token and shows the reset form.
- `/complete-password-reset` updates the Firebase Auth password after the new password and confirmation match.
- `/admin-alert-worker` polls Firestore `admin_alerts`, reads admin FCM tokens, and sends push notifications through FCM HTTP v1.
- `/test-admin-notification` sends a direct test notification to registered admin/developer FCM tokens.
- `/developer-delete-user` lets the developer app delete Firebase Auth login credentials for a target UID or email after verifying the signed-in caller has `users/{uid}.role == "developer"`.

## Local Run

Run these commands from the backend folder:

```powershell
cd C:\Users\benig\OneDrive\Documents\THESIS\Application\App\productivity_and_wellbeing\genkit_backend
dart pub get
$env:GROQ_API_KEY="YOUR_GROQ_API_KEY"
$env:FIREBASE_SERVICE_ACCOUNT_JSON=(Get-Content ".\service-account.json" -Raw)
$env:FIREBASE_WEB_API_KEY="YOUR_FIREBASE_WEB_API_KEY"
$env:PUBLIC_BASE_URL="http://localhost:8080"
$env:BREVO_API_KEY="YOUR_BREVO_API_KEY"
$env:BREVO_SENDER_EMAIL="your_verified_sender@example.com"
$env:BREVO_SENDER_NAME="FullBrightTrack"
dart run bin/server.dart
```

Expected startup lines:

```text
FullBrightTrack Groq backend listening on 8080
Groq API key: configured
Firebase backend: configured
```

## Environment Variables

Use these on both local PowerShell and Render:

| Variable | Required | How to use |
| --- | --- | --- |
| `GROQ_API_KEY` | Optional for startup, required for Groq AI | Groq console API key. If empty, backend uses local fallback scoring. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Required for account, password, FCM, developer delete | Paste the full service account JSON as one environment variable. Locally, load it with `Get-Content ".\service-account.json" -Raw`. |
| `FIREBASE_WEB_API_KEY` | Required for automatic Firebase Auth account creation | Firebase Web API key from Google Cloud or Firebase project settings. Keep it on the backend, not inside Flutter. |
| `PUBLIC_BASE_URL` | Required for online email links | Local: `http://localhost:8080`. Render: `https://YOUR_RENDER_SERVICE.onrender.com`. |
| `BREVO_API_KEY` | Required for Brevo email delivery | Brevo SMTP & API > API keys. Use normal API key, not MCP key. |
| `BREVO_SENDER_EMAIL` | Required for Brevo email delivery | A sender email verified in Brevo. |
| `BREVO_SENDER_NAME` | Optional | Example: `FullBrightTrack`. |
| `ADMIN_ALERT_WORKER_INTERVAL_SECONDS` | Optional | Set to `60` to poll and send pending admin alerts automatically. |
| `ADMIN_NOTIFICATION_TEST_SECRET` | Optional | If set, `/test-admin-notification` requires header `x-admin-test-secret`. |
| `EMAIL_DEBUG_RETURN_LINK` | Optional local testing only | Set to `true` to include confirmation/reset links in API responses. |

This backend uses Groq, not Google Gemini. Do not run it with `genkit start`
or a Google/Gemini provider command. If you see a message about a missing
Google API key, you are running a different tool or old backend command. For
this server, only `GROQ_API_KEY` is used for AI calls. If `GROQ_API_KEY` is not
set, the server still starts and uses local fallback scoring.

Firebase account and FCM endpoints require `FIREBASE_SERVICE_ACCOUNT_JSON`. Automatic account creation from the confirmation link uses the service account plus `FIREBASE_WEB_API_KEY` to identify the Firebase project. Email confirmation on Render free services should use the Brevo HTTPS API because Render blocks outbound SMTP ports on free web services. Keep service account JSON and email API keys on the backend only. Never put them in Flutter.

Windows PowerShell quick start:

```powershell
cd genkit_backend
dart pub get
$env:GROQ_API_KEY="YOUR_GROQ_API_KEY"
$env:FIREBASE_SERVICE_ACCOUNT_JSON=(Get-Content ".\service-account.json" -Raw)
$env:FIREBASE_WEB_API_KEY="YOUR_FIREBASE_WEB_API_KEY"
$env:PUBLIC_BASE_URL="http://localhost:8080"
$env:BREVO_API_KEY="YOUR_BREVO_API_KEY"
$env:BREVO_SENDER_EMAIL="your_verified_sender@example.com"
$env:BREVO_SENDER_NAME="FullBrightTrack"
dart run bin/server.dart
```

Optional local SMTP fallback, useful only outside Render free services:

```powershell
$env:SMTP_HOST="smtp.gmail.com"
$env:SMTP_PORT="465"
$env:SMTP_STARTTLS="false"
$env:SMTP_USERNAME="your_sender_email@gmail.com"
$env:SMTP_PASSWORD="YOUR_EMAIL_APP_PASSWORD"
$env:SMTP_FROM_EMAIL="your_sender_email@gmail.com"
$env:SMTP_FROM_NAME="FullBrightTrack"
```

Health check:

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/health"
```

Use this URL from an Android emulator:

```text
http://10.0.2.2:8080
```

For Android emulator testing, Flutter can call the local backend through:

```powershell
flutter run --flavor user --dart-define=FULLBRIGHT_BACKEND_URL=http://10.0.2.2:8080 --dart-define=GENKIT_STRESS_FLOW_URL=http://10.0.2.2:8080/stress
```

Debug Flutter builds also default to `http://10.0.2.2:8080/stress` when `GENKIT_STRESS_FLOW_URL` is omitted.

Stress endpoint:

```powershell
$body = @{
  rawData = @{
    period = @{
      days = 30
      startDate = "2026-05-04"
      endDate = "2026-06-02"
    }
    steps = @(
      @{ date = "2026-06-02"; steps = 3500 }
    )
    moods = @(
      @{ date = "2026-06-02"; moodIndex = 1; intensity = 0.7 }
    )
    journals = @(
      @{
        id = "sample"
        text = "I feel tired but I finished my task."
        tag = "Tired"
        prompt = "What challenged you today?"
        createdAt = "2026-06-02T10:00:00.000"
      }
    )
    tasks = @(
      @{
        id = "task-1"
        title = "Submit report"
        isCompleted = $false
        deadline = "2026-06-03T09:00:00.000"
      }
    )
  }
  localBaseline = @{
    avgMoodIndex = 1.8
    avgMoodIntensity = 0.7
    avgDailySteps = 3500
    moodLogCoverage = 0.6
    journalEntryCount = 8
    activeTaskCount = 4
    completedTaskCount = 6
    overdueTaskCount = 2
  }
  warningSnippets = @("want to die")
  journalWarningWeight = 0.3
  journalWarningSeverity = "stress"
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "http://localhost:8080/stress" -Method Post -ContentType "application/json" -Body $body
```

## How To Test Registration Confirmation

```powershell
$env:EMAIL_DEBUG_RETURN_LINK="true"

$body = @{
  email = "student@example.com"
  password = "studentPassword123"
} | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "http://localhost:8080/start-registration" -Method Post -ContentType "application/json" -Body $body
```

The backend sends the confirmation link to the user's email. If `EMAIL_DEBUG_RETURN_LINK=true`, the response also includes `confirmationUrl` for local testing.

Open the link in a browser. The account is not created yet. The page asks the user to press `Confirm and create account`. Only that button creates the Firebase Auth email/password account.

The backend stores records under:

```text
pending_registrations/{requestId}
```

`/complete-registration` is kept only as a verification endpoint for the Flutter app:

```powershell
$body = @{
  requestId = "REQUEST_ID"
  email = "student@example.com"
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "http://localhost:8080/complete-registration" -Method Post -ContentType "application/json" -Body $body
```

If confirmed, the endpoint reports that the email is already ready for sign-in.

## How To Test Password Reset

```powershell
$body = @{ email = "student@example.com" } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "http://localhost:8080/request-password-reset" -Method Post -ContentType "application/json" -Body $body
```

Open the returned `resetUrl`. The browser page asks for `New password` and `Confirm new password`.

You can also complete it manually:

```powershell
$body = @{
  id = "REQUEST_ID"
  token = "TOKEN_FROM_RESET_URL"
  newPassword = "newPassword123"
  confirmPassword = "newPassword123"
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "http://localhost:8080/complete-password-reset" -Method Post -ContentType "application/json" -Body $body
```

## How To Test Admin FCM Notifications

First sign in to the Flutter user app with an account whose Firestore profile has:

```text
users/{uid}.role = "admin"
```

or:

```text
users/{uid}.role = "developer"
```

Allow notifications and open the Home screen. The app writes a token under:

```text
admin_fcm_tokens/{uid}/tokens/{token}
```

Then test token delivery directly:

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

Expected:

```json
{
  "ok": true,
  "tokenCount": 1,
  "successCount": 1,
  "failureCount": 0
}
```

If `tokenCount` is `0`, the app has not registered the admin/developer token yet.

To send pending journal warning alerts:

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/admin-alert-worker" -Method Post
```

For automatic polling:

```powershell
$env:ADMIN_ALERT_WORKER_INTERVAL_SECONDS="60"
```

## How To Test Developer User Delete

```powershell
$body = @{
  email = "student@example.com"
  uid = ""
} | ConvertTo-Json -Compress

Invoke-RestMethod `
  -Uri "http://localhost:8080/developer-delete-user" `
  -Method Post `
  -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer ADMIN_FIREBASE_ID_TOKEN" } `
  -Body $body
```

The backend verifies the developer token against Firebase Auth and checks `users/{developerUid}.role == "developer"` before deleting the target Firebase Auth user. This deletes sign-in credentials only; Firestore profile/data documents are kept unless deleted separately.

Journal warning mode example:

```powershell
$body = @{
  mode = "journal-warning"
  rawJournalText = "I feel angry and might hurt someone, but I am trying to calm down."
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "http://localhost:8080/stress" -Method Post -ContentType "application/json" -Body $body
```

Optional model override:

```powershell
$env:GROQ_MODEL="llama-3.3-70b-versatile"
```

The backend also has a deterministic local fallback if Groq is unavailable, returns an invalid response, or if only the local baseline is usable. The local fallback never calls Groq.

To protect Groq free-tier token limits, repeated `/stress` scoring calls use a short cooldown. If the same payload repeats during cooldown, the backend can reuse the latest Groq result. If no cached Groq result is available, it returns a `server-local-fallback` response with a `fallbackReason`. The Flutter app preserves the last real AI result when available so temporary cooldown fallback does not overwrite Admin Monitoring or AI Analysis with local scoring.

## Deploy To Render

Create a Render Web Service with these settings:

```text
Runtime: Docker
Root Directory: genkit_backend
Health Check Path: /health
Environment: GROQ_API_KEY=YOUR_GROQ_API_KEY
Environment: FIREBASE_SERVICE_ACCOUNT_JSON={...service account json...}
Environment: FIREBASE_WEB_API_KEY=YOUR_FIREBASE_WEB_API_KEY
Environment: PUBLIC_BASE_URL=https://YOUR_RENDER_SERVICE.onrender.com
Environment: BREVO_API_KEY=YOUR_BREVO_API_KEY
Environment: BREVO_SENDER_EMAIL=your_verified_sender@example.com
Environment: BREVO_SENDER_NAME=FullBrightTrack
```

Optional environment:

```text
GROQ_MODEL=llama-3.3-70b-versatile
ADMIN_ALERT_WORKER_INTERVAL_SECONDS=60
```

Then run Flutter with:

```powershell
flutter run --dart-define=FULLBRIGHT_BACKEND_URL=https://YOUR_RENDER_SERVICE.onrender.com --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```

For release:

```powershell
flutter build apk --release --dart-define=FULLBRIGHT_BACKEND_URL=https://YOUR_RENDER_SERVICE.onrender.com --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```

## Data Handling Notes

- The Flutter app controls whether this backend is called by checking `users/{uid}.rawAiDataConsent`.
- Raw data is sent for scoring only after consent is recorded.
- The backend prompt tells the model not to diagnose or claim medical certainty.
- The app stores only derived stress score, rank, confidence, rationale, AI mood status, and summarized warning metadata in `admin_monitoring`.
- Raw journal text and task titles are not copied into `admin_monitoring` by the Flutter client.
