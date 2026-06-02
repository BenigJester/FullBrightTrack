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

## Local Run

```powershell
dart pub get
$env:GROQ_API_KEY="YOUR_GROQ_API_KEY"
dart run bin/server.dart
```

This backend uses Groq, not Google Gemini. Do not run it with `genkit start`
or a Google/Gemini provider command. If you see a message about a missing
Google API key, you are running a different tool or old backend command. For
this server, only `GROQ_API_KEY` is used for AI calls. If `GROQ_API_KEY` is not
set, the server still starts and uses local fallback scoring.

Windows PowerShell quick start:

```powershell
cd genkit_backend
dart pub get
$env:GROQ_API_KEY="YOUR_GROQ_API_KEY"
dart run bin/server.dart
```

Health check:

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/health"
```

For Android emulator testing, Flutter can call the local backend through:

```powershell
flutter run --dart-define=GENKIT_STRESS_FLOW_URL=http://10.0.2.2:8080/stress
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
```

Optional environment:

```text
GROQ_MODEL=llama-3.3-70b-versatile
```

Then run Flutter with:

```powershell
flutter run --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```

For release:

```powershell
flutter build apk --release --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```

## Data Handling Notes

- The Flutter app controls whether this backend is called by checking `users/{uid}.rawAiDataConsent`.
- Raw data is sent for scoring only after consent is recorded.
- The backend prompt tells the model not to diagnose or claim medical certainty.
- The app stores only derived stress score, rank, confidence, rationale, AI mood status, and summarized warning metadata in `admin_monitoring`.
- Raw journal text and task titles are not copied into `admin_monitoring` by the Flutter client.
