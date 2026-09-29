# FrameMind REST API (v1)

Base URL: `https://<host>/api`. All endpoints except `/health` require
`Authorization: Bearer <Firebase ID token>`. JSON uses camelCase; enums are
serialized as strings. Errors use RFC 7807 `application/problem+json`
(`{ "title", "status", "detail", "errors"? }`).

Status codes: `400` validation, `401` unauthenticated, `403` plan limit
(e.g. 1080p on Free), `404` not found / not owned, `409` invalid state,
`429` rate limited or daily quota exhausted.

## Enums

| Enum | Values |
|---|---|
| `Language` | `English`, `Bangla`, `Hindi` |
| `VideoStyle` | `Animation`, `Realistic`, `Cartoon`, `Cinematic`, `Anime` |
| `VoiceType` | `Male`, `Female`, `Child`, `Narrator` |
| `Resolution` | `P720`, `P1080` |
| `ChatStatus` | `Analyzed`, `ScriptReady`, `Queued`, `Generating`, `Completed`, `Failed` |
| `GenerationStage` | `Queued`, `Analyzing`, `GeneratingScript`, `GeneratingVoice`, `GeneratingVideo`, `Rendering`, `Complete`, `Failed` |
| `Plan` | `Free`, `Premium` |
| `SourcePlatform` | `YouTube`, `Facebook`, `Instagram`, `TikTok`, `Other` |

## Shared shapes

```jsonc
// VideoAnalysis
{
  "sourceTitle": "string",
  "sourcePlatform": "YouTube",
  "thumbnailUrl": "https://...",
  "sourceDurationSeconds": 62,
  "category": "Family Animation",
  "theme": "Family Bonding",
  "mood": "Heartwarming",
  "style": "3D Animation",
  "characters": ["Father", "Mother", "Daughter"],
  "pace": "Medium",
  "storyPattern": "Problem → shared effort → warm resolution",
  "summary": "Short, non-identifying description of the video's format"
}

// Script
{
  "title": "string",
  "summary": "string",
  "characters": [{ "name": "Mira", "description": "8-year-old, curious" }],
  "scenes": [
    {
      "number": 1,
      "visual": "A young boy helps his grandmother cross the road.",
      "narration": "Kindness often begins with small actions.",
      "dialogues": [{ "character": "Grandmother", "line": "Thank you, dear." }],
      "cameraDirection": "Wide shot, slow push-in",
      "durationSeconds": 5
    }
  ]
}

// ChatSummary (history list item)
{
  "id": "uuid", "projectId": "uuid|null", "title": "string",
  "thumbnailUrl": "string|null", "language": "English",
  "durationSeconds": 60, "status": "Completed",
  "latestVideoId": "uuid|null", "createdAt": "2026-09-29T10:00:00Z"
}

// Chat (full)
{
  "id": "uuid", "projectId": "uuid|null", "title": "string",
  "userPrompt": "string|null", "videoUrl": "string",
  "language": "English|null", "durationSeconds": 60, "style": "Animation|null",
  "voiceType": "Narrator|null", "status": "ScriptReady",
  "analysis": VideoAnalysis, "script": Script|null,
  "videos": [GeneratedVideo], "activeJob": GenerationJob|null,
  "createdAt": "...", "updatedAt": "..."
}

// GeneratedVideo
{
  "id": "uuid", "chatId": "uuid", "resolution": "P720",
  "durationSeconds": 60, "thumbnailUrl": "signed url",
  "streamUrl": "signed url (expires)", "createdAt": "..."
}

// GenerationJob
{
  "id": "uuid", "chatId": "uuid", "stage": "GeneratingVideo",
  "progress": 42, "error": null, "videoId": "uuid|null",
  "createdAt": "...", "completedAt": null
}
```

## Endpoints

### Users
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/users/me` | – | `{ id, name, email, photoUrl, plan, videosGeneratedToday, dailyVideoLimit (null = unlimited), maxResolution }` |
| POST | `/users/me/device-token` | `{ "token": "fcm-token", "platform": "android" \| "ios" }` | `204` |

The user row is created on first authenticated request from the Firebase token claims.

### Projects
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/project` | – | `[{ id, name, chatCount, createdAt }]` |
| GET | `/project/{id}` | – | `{ id, name, createdAt, chats: [ChatSummary] }` |
| POST | `/project` | `{ "name": "Family Stories" }` | `201` project |
| PUT | `/project/{id}` | `{ "name": "..." }` | project |
| DELETE | `/project/{id}` | – | `204` (chats are kept, moved to "no project") |

### Analysis
`POST /video/analyze`
```json
{ "videoUrl": "https://youtu.be/...", "projectId": null, "userPrompt": "optional extra direction" }
```
→ `200 { "chatId": "uuid", "analysis": VideoAnalysis }`. Creates a chat in
status `Analyzed`. Results are cached per URL. May take up to ~60 s.

### Script
| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/script/generate` | `{ chatId, language, durationSeconds (15–300), style, voiceType, userPrompt? }` | `Chat` |
| POST | `/script/regenerate` | `{ chatId, sceneNumber? , instructions? }` — omit `sceneNumber` to regenerate the whole script | `Chat` |
| PUT | `/script/{chatId}` | `{ "script": Script }` — save draft/edits (scenes are renumbered server-side) | `Chat` |

### Video generation
| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/video/generate` | `{ chatId, resolution }` | `202 GenerationJob` |
| GET | `/video/jobs/{jobId}` | – | `GenerationJob` |
| GET | `/video/{videoId}/download` | – | `{ "url": "signed url", "fileName": "title.mp4", "expiresAt": "..." }` |

Clients poll the job every 3–5 s while on the progress screen; an FCM push
(`data.type = "video_ready" | "video_failed"`, `data.chatId`, `data.jobId`) is also sent.

### Chats / history
| Method | Path | Query/Body | Response |
|---|---|---|---|
| GET | `/history` | `?search=&projectId=&language=&status=&page=1&pageSize=20` | `{ items: [ChatSummary], page, pageSize, total }` (newest first) |
| GET | `/chat/{id}` | – | `Chat` |
| PUT | `/chat/{id}/project` | `{ "projectId": "uuid\|null" }` | `204` |
| POST | `/chat/{id}/duplicate` | – | `201 Chat` (copies analysis + script, no videos) |
| DELETE | `/chat/{id}` | – | `204` |

### Health
`GET /health` → `200 "Healthy"` (unauthenticated).
