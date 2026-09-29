# FrameMind backend

ASP.NET Core 9, Clean Architecture + CQRS (MediatR), PostgreSQL, Redis,
RabbitMQ, S3-compatible storage.

```
src/
  FrameMind.Domain          Entities (User, Project, Chat, GenerationJob, GeneratedVideo),
                            value objects (VideoAnalysis, Script), plan rules
  FrameMind.Application     Commands/queries per feature, validators, ports (interfaces),
                            generation pipeline (ProcessGenerationJobCommand)
  FrameMind.Infrastructure  EF Core + migrations, Redis cache, RabbitMQ, S3/R2/MinIO,
                            Claude (analysis/scripts/prompts), yt-dlp + FFmpeg,
                            Veo, ElevenLabs, FCM
  FrameMind.Api             Minimal API endpoints, Firebase JWT, rate limiting, ProblemDetails
  FrameMind.Worker          Queue consumer + stale-job sweeper
tests/FrameMind.UnitTests
```

## Request flow

1. `POST /api/video/analyze` — yt-dlp reads public metadata and a low-res copy,
   FFmpeg samples 8 keyframes, Claude returns abstract attributes only
   (category, theme, mood, style, pace, archetypes). Cached in Redis for 7 days.
2. `POST /api/script/generate` — Claude writes an original script from those
   attributes (never from the source's content). Narration/dialogue are in the
   chosen language; visual directions stay in English for the video model.
3. `PUT /api/script/{chatId}` / `POST /api/script/regenerate` — edits and rewrites.
4. `POST /api/video/generate` — plan + daily quota check, job row, RabbitMQ
   message (premium = higher priority). Returns `202` with the job.
5. Worker: scene prompts (Claude) → voiceover per scene (ElevenLabs) → scene
   clips (Veo, 2 in parallel) → FFmpeg (normalize to 720p/1080p @ 30 fps,
   cross-fades, voice mix, burned-in subtitles, `+faststart` MP4) → S3 → FCM push.
6. `GET /api/video/{id}/download` — 15-minute signed URL with an attachment filename.

## Run locally

```bash
# from the repo root: infra + api + worker
docker compose up -d --build
```

Or run infra in Docker and the .NET projects on the host (needs `ffmpeg`,
`ffprobe` and `yt-dlp` on PATH):

```bash
docker compose up -d postgres redis rabbitmq minio
cd backend
dotnet user-secrets --project src/FrameMind.Api set Anthropic:ApiKey "sk-ant-..."
dotnet run --project src/FrameMind.Api      # http://localhost:5172
dotnet run --project src/FrameMind.Worker
```

In `Development`, `Auth:DevBypass` lets you call the API without Firebase:

```bash
curl -X POST http://localhost:8080/api/video/analyze \
  -H "X-Dev-User: alice" -H "Content-Type: application/json" \
  -d '{"videoUrl":"https://www.youtube.com/watch?v=..."}'
```

The OpenAPI document is served at `/openapi/v1.json` in Development.

## Configuration

| Key | Default | Notes |
|---|---|---|
| `ConnectionStrings:Postgres/Redis/RabbitMq` | localhost | |
| `Anthropic:ApiKey`, `Anthropic:Model` | –, `claude-opus-5-5` | Analysis, scripts, scene prompts |
| `Firebase:ProjectId` | – | Required in production for token validation |
| `Firebase:PushEnabled`, `Firebase:CredentialsPath` | `false` | FCM service account |
| `Storage:*` | MinIO on :9000 | Set `ServiceUrl` to your R2 endpoint, or leave empty for AWS S3; `ServerSideEncryption=true` on S3 |
| `VideoGeneration:Provider` | `Placeholder` | `Veo` + `VideoGeneration:Veo:ApiKey` / `Model` |
| `Voice:Provider` | `Placeholder` | `ElevenLabs` + `Voice:ElevenLabs:ApiKey`; voice ids per voice type and model per language are configurable |
| `Database:MigrateOnStartup` | `true` | Apply EF migrations when the API starts |

Adding another video engine (Runway, Luma, Kling) means implementing
`ISceneVideoGenerator` and registering it in `Infrastructure/DependencyInjection.cs`.

## Tests & migrations

```bash
dotnet test
dotnet tool restore
dotnet ef migrations add <Name> -p src/FrameMind.Infrastructure -s src/FrameMind.Infrastructure -o Persistence/Migrations
```
