# Trenchwar dedicated online server

Public WebSocket game host for worldwide PvP. The Vercel site stays a static CDN;
this process is the always-on match authority.

## Local (LAN / smoke)

```bash
# from repo root
godot --headless --path . res://server/ServerMain.tscn
# or Windows:
# tools/Godot_v4.3-stable_win64_console.exe --headless --path . res://server/ServerMain.tscn
```

Clients: `ws://127.0.0.1:9080` (Advanced join) or Quick Play if `DEFAULT_WSS_URL` points here.

## Worldwide (wss://)

Browsers on HTTPS (Vercel) **must** use `wss://`.

### Option A — Docker Compose + Caddy on a VPS

1. Edit [`Caddyfile`](Caddyfile): replace `play.example.com` with your hostname.
2. DNS A/AAAA → VPS.
3. `CADDY_EMAIL=you@domain.com docker compose -f server/docker-compose.yml up -d --build`
4. Set client URL: `wss://play.yourdomain.com` (see `Net.DEFAULT_WSS_URL` / env `TRENCHWAR_WS_URL`).

### Option B — Fly.io

```bash
fly launch --config server/fly.toml
fly deploy --config server/fly.toml
```

Clients use `wss://<app>.fly.dev`.

## Env

| Variable | Meaning |
|---|---|
| `TRENCHWAR_PORT` | Bind port (default 9080) |
| `TRENCHWAR_DEDICATED` | `1` = headless authority (no local soldier) |
| `TRENCHWAR_WS_URL` | Client default (bake at export or set in shell for desktop) |
