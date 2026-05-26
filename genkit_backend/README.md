# FullBrightTrack Groq Backend

This is the server-side AI endpoint for Admin Monitoring stress scoring.

It accepts minimized numeric data from the Flutter app and optional short warning snippets. It does not require raw journal text or task titles.

## Local Run

```powershell
dart pub get
$env:GROQ_API_KEY="YOUR_GROQ_API_KEY"
dart run bin/server.dart
```

Health check:

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/health"
```

Stress endpoint:

```powershell
$body = @{
  avgMoodIndex = 1.8
  avgMoodIntensity = 0.7
  avgDailySteps = 3500
  moodLogCoverage = 0.6
  journalEntryCount = 8
  activeTaskCount = 4
  completedTaskCount = 6
  overdueTaskCount = 2
  warningSnippets = @("short warning line only")
  journalWarningWeight = 0.3
  journalWarningSeverity = "stress"
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "http://localhost:8080/stress" -Method Post -ContentType "application/json" -Body $body
```

Optional model override:

```powershell
$env:GROQ_MODEL="llama-3.3-70b-versatile"
```

## Deploy To Render

Create a Render Web Service with these settings:

```text
Runtime: Docker
Root Directory: genkit_backend
Health Check Path: /health
Environment: GROQ_API_KEY=YOUR_GROQ_API_KEY
```

Then run Flutter with:

```powershell
flutter run --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```

For release:

```powershell
flutter build apk --release --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_RENDER_SERVICE.onrender.com/stress
```
