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
                                Ollama/Claude, Storyboard/Veo, edge-tts/ElevenLabs,
                                FFmpeg, FCM adapters
  src/FrameMind.Api             REST API (Firebase JWT auth, rate limiting)
  src/FrameMind.Worker          Queue consumer: voice → video → render → notify
mobile/             Flutter app (Android + iOS), Riverpod, Hive
docs/API.md         REST contract shared by backend and mobile
docker-compose.yml  PostgreSQL, Redis, RabbitMQ, MinIO, Ollama, API, Worker
```

## Architecture

```
Flutter app ──HTTPS + Firebase ID token──▶ API ──▶ PostgreSQL
                                            │ ├──▶ Redis (analysis cache)
                                            │ └──▶ Ollama (free) / Claude (analysis + scripts)
                                            ▼
                                        RabbitMQ (priority queue)
                                            ▼
                                         Worker ──▶ edge-tts (free) / ElevenLabs (voice)
                                            │   ──▶ Storyboard images (free) / Veo (scenes)
                                            │   ──▶ FFmpeg (subtitles, transitions, MP4)
                                            │   ──▶ S3 / R2 (signed URLs)
                                            └──▶ Firebase Cloud Messaging
```

**Originality guardrail.** The analysis step extracts only abstract,
non-identifying attributes (genre, mood, pacing, story pattern). The script
generator never receives the source transcript, character names or
dialogue, and is instructed to invent new characters, settings and plot.

## Running locally — free, no API keys

Everything runs on free resources by default:

| Stage | Free default (no key) | Paid upgrade (set in `.env`) |
|---|---|---|
| Analysis + scripts | **Ollama** + `gemma3:4b`, local on CPU (Bangla/Hindi/English, reads images) | `LLM_PROVIDER=Claude` + `ANTHROPIC_API_KEY` |
| Scene visuals | **Storyboard**: one AI image per scene (Pollinations.ai, keyless) animated with pan/zoom | `VIDEO_PROVIDER=Veo` + `GOOGLE_API_KEY` |
| Voice | **edge-tts** neural voices (falls back to offline eSpeak NG) | `VOICE_PROVIDER=ElevenLabs` + `ELEVENLABS_API_KEY` |
| Login + push | Firebase free (Spark) plan | – |
| DB, cache, queue, storage | PostgreSQL, Redis, RabbitMQ, MinIO in Docker | – |

Prerequisites: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
(free for personal use), ~12 GB free disk, 16 GB RAM recommended.

```bash
cp .env.example .env           # defaults are already the free setup
docker compose up -d --build   # first run also downloads the AI model (~3.3 GB)
curl http://localhost:8080/health
```

What to expect on a laptop CPU: analysis 1–4 min, script 2–6 min, and a
60-second video 5–15 min. Paid providers are much faster.

Free-tier caveats: Pollinations and edge-tts are public free services with no
SLA. They may rate-limit or change. The pipeline falls back to title cards or
eSpeak voice for a scene instead of failing the whole video.

Mobile app: see [mobile/README.md](mobile/README.md).

## Plans

| | Free | Premium |
|---|---|---|
| Videos / day | 3 | Unlimited |
| Max resolution | 720p | 1080p |
| Queue priority | Normal | High |

## License

See [LICENSE](LICENSE).
