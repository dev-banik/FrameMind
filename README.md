# FrameMind

An AI video creation platform that turns inspiration into original content.

Paste a public video URL (YouTube, Facebook, Instagram, TikTok, …). FrameMind
analyzes its **category, theme, mood, pacing and storytelling style** — never
its specific content — and generates a brand-new original script, a
scene-by-scene storyboard, a voiced AI video, and an HD MP4 you can download
to your gallery.

## Repository layout

```
backend/            ASP.NET Core 9 Web API + worker (Clean Architecture, CQRS)
  src/FrameMind.Domain          Entities, enums, domain rules
  src/FrameMind.Application     CQRS commands/queries (MediatR), validation, ports
  src/FrameMind.Infrastructure  EF Core/PostgreSQL, Redis, RabbitMQ, S3/R2,
                                Claude, Veo, ElevenLabs, FFmpeg, FCM adapters
  src/FrameMind.Api             REST API (Firebase JWT auth, rate limiting)
  src/FrameMind.Worker          Queue consumer: voice → video → render → notify
mobile/             Flutter app (Android + iOS), Riverpod, Hive
docs/API.md         REST contract shared by backend and mobile
docker-compose.yml  PostgreSQL, Redis, RabbitMQ, MinIO, API, Worker
```

## Architecture

```
Flutter app ──HTTPS + Firebase ID token──▶ API ──▶ PostgreSQL
                                            │ ├──▶ Redis (analysis cache)
                                            │ └──▶ Claude (analysis + scripts)
                                            ▼
                                        RabbitMQ (priority queue)
                                            ▼
                                         Worker ──▶ ElevenLabs (voice)
                                            │   ──▶ Veo / Runway / Luma / Kling (scenes)
                                            │   ──▶ FFmpeg (subtitles, transitions, MP4)
                                            │   ──▶ S3 / R2 (signed URLs)
                                            └──▶ Firebase Cloud Messaging
```

**Originality guardrail.** The analysis step extracts only abstract,
non-identifying attributes (genre, mood, pacing, story pattern). The script
generator never receives the source transcript, character names or
dialogue, and is instructed to invent new characters, settings and plot.

## Running locally

Prerequisites: Docker, .NET 9 SDK, Flutter 3.24+, a Firebase project.

```bash
cp .env.example .env         # fill in API keys (see below)
docker compose up -d --build # infra + api (http://localhost:8080) + worker
```

Without video/voice API keys the worker uses the built-in `Placeholder`
providers (FFmpeg-rendered title cards and silent audio) so the full pipeline
can be exercised end-to-end.

| Variable | Purpose |
|---|---|
| `ANTHROPIC_API_KEY` | Video analysis and script generation (Claude) |
| `GOOGLE_API_KEY` | Google Veo scene generation (`VideoGeneration__Provider=Veo`) |
| `ELEVENLABS_API_KEY` | Narration (`Voice__Provider=ElevenLabs`) |
| `FIREBASE_PROJECT_ID` | Validates Firebase ID tokens |
| `GOOGLE_APPLICATION_CREDENTIALS` | Service account for FCM push |

Mobile app: see [mobile/README.md](mobile/README.md).

## Plans

| | Free | Premium |
|---|---|---|
| Videos / day | 3 | Unlimited |
| Max resolution | 720p | 1080p |
| Queue priority | Normal | High |

## License

See [LICENSE](LICENSE).
