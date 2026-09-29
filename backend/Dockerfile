# syntax=docker/dockerfile:1
# Build targets: `api` and `worker`. Both need FFmpeg + yt-dlp (the API samples
# keyframes during analysis; the worker renders videos).

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY global.json Directory.Build.props FrameMind.sln ./
COPY src/FrameMind.Domain/FrameMind.Domain.csproj src/FrameMind.Domain/
COPY src/FrameMind.Application/FrameMind.Application.csproj src/FrameMind.Application/
COPY src/FrameMind.Infrastructure/FrameMind.Infrastructure.csproj src/FrameMind.Infrastructure/
COPY src/FrameMind.Api/FrameMind.Api.csproj src/FrameMind.Api/
COPY src/FrameMind.Worker/FrameMind.Worker.csproj src/FrameMind.Worker/
RUN dotnet restore src/FrameMind.Api/FrameMind.Api.csproj \
 && dotnet restore src/FrameMind.Worker/FrameMind.Worker.csproj
COPY src/ src/
RUN dotnet publish src/FrameMind.Api -c Release --no-restore -o /out/api \
 && dotnet publish src/FrameMind.Worker -c Release --no-restore -o /out/worker

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS media-runtime
# Set by BuildKit: amd64 on laptops, arm64 on Oracle Cloud Ampere (Always Free).
ARG TARGETARCH
# Noto fonts cover Latin, Bengali and Devanagari for burned-in subtitles.
# edge-tts (free neural voices) runs from a venv; espeak-ng is the offline fallback.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg fonts-noto-core ca-certificates curl \
      espeak-ng python3 python3-venv \
 && python3 -m venv /opt/edge-tts && /opt/edge-tts/bin/pip install --no-cache-dir edge-tts \
 && ln -s /opt/edge-tts/bin/edge-tts /usr/local/bin/edge-tts \
 && curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux$( [ "$TARGETARCH" = "arm64" ] && echo _aarch64 ) -o /usr/local/bin/yt-dlp \
 && chmod +x /usr/local/bin/yt-dlp \
 && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 10001 app
USER app
WORKDIR /app

FROM media-runtime AS api
COPY --from=build /out/api .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "FrameMind.Api.dll"]

FROM media-runtime AS worker
COPY --from=build /out/worker .
ENTRYPOINT ["dotnet", "FrameMind.Worker.dll"]
