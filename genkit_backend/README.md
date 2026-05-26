# FullBrightTrack Groq Backend

This is the server-side AI endpoint for Admin Monitoring stress scoring.

It accepts minimized numeric data from the Flutter app and optional short warning snippets. It does not require raw journal text or task titles.

## Local Run

```bash
dart pub get
$env:GROQ_API_KEY="YOUR_GROQ_API_KEY"
dart run bin/server.dart
```

Health check:

```bash
curl http://localhost:8080/health
```

Stress endpoint:

```bash
curl -X POST http://localhost:8080/stress ^
  -H "Content-Type: application/json" ^
  -d "{\"avgMoodIndex\":1.8,\"avgMoodIntensity\":0.7,\"avgDailySteps\":3500,\"moodLogCoverage\":0.6,\"journalEntryCount\":8,\"activeTaskCount\":4,\"completedTaskCount\":6,\"overdueTaskCount\":2,\"warningSnippets\":[\"short warning line only\"]}"
```

Optional model override:

```bash
$env:GROQ_MODEL="llama-3.3-70b-versatile"
```

## Deploy To Cloud Run

```bash
gcloud run deploy fullbright-stress-ai ^
  --source genkit_backend ^
  --region asia-southeast1 ^
  --allow-unauthenticated ^
  --set-env-vars GROQ_API_KEY=YOUR_GROQ_API_KEY
```

Then run Flutter with:

```bash
flutter run --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_CLOUD_RUN_URL/stress
```

For release:

```bash
flutter build apk --release --dart-define=GENKIT_STRESS_FLOW_URL=https://YOUR_CLOUD_RUN_URL/stress
```
