# Trenchwar live online (no credit card)

Public play uses a **free Cloudflare quick tunnel** — not Fly/AWS.

## Go live (Windows)

```powershell
# From repo root — keep the window open while people play
powershell -ExecutionPolicy Bypass -File scripts/go_live.ps1 -Push
```

This starts:

1. Godot dedicated server (`:9080`)
2. Solana wager gateway (`:9081`) — WebSocket proxy + `/api/wager/*`
3. `cloudflared` tunnel → public `https://….trycloudflare.com` / `wss://…`
4. Writes [`web/net_config.json`](../web/net_config.json) and (with `-Push`) updates Vercel

Players on the Vercel site: **GAME MODES → ONLINE PVP → QUICK PLAY**.

## SOL stakes (1v1)

1. Both players open the **web** build (Phantom / mobile Phantom browser).
2. Lobby leader picks a stake (e.g. `0.05 SOL`).
3. Each connects Phantom → **CREATE ESCROW** → **DEPOSIT**.
4. When status is `funded`, start the match. Winner receives the pot on-chain.

Default cluster: **devnet** (set `SOLANA_CLUSTER=mainnet-beta` before `go_live` for real SOL).

## LAN only

```text
godot --headless --path . res://server/ServerMain.tscn
```

Join `ws://127.0.0.1:9080` via Advanced in the lobby.
