# Trenchwar dedicated game server (Godot 4.3 headless WebSocket :9080).
# Put Caddy (or Fly TLS) in front for public wss://.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip libfontconfig1 libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

ARG GODOT_VERSION=4.3
ARG GODOT_TAG=4.3-stable
WORKDIR /opt/godot
RUN curl -fsSL -o godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip godot.zip \
    && mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -f godot.zip

WORKDIR /game
COPY . /game

# Import project once so .godot cache exists in the image.
RUN godot --headless --path /game --import || true

ENV TRENCHWAR_PORT=9080
EXPOSE 9080

CMD ["godot", "--headless", "--path", "/game", "res://server/ServerMain.tscn"]
