/**
 * Trenchwar live gateway (no CC hosting):
 *  - Proxies WebSocket upgrades → Godot dedicated server (:9080)
 *  - REST /api/wager/* for Solana stake escrow (Phantom deposits → winner payout)
 *
 * Env:
 *   GODOT_WS=http://127.0.0.1:9080
 *   PORT=9081
 *   SOLANA_CLUSTER=devnet|mainnet-beta
 *   WAGER_SETTLE_SECRET=shared-with-godot-server (optional harden)
 */
import express from "express";
import cors from "cors";
import http from "http";
import httpProxy from "http-proxy";
import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  LAMPORTS_PER_SOL,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import bs58 from "bs58";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 9081);
const GODOT_WS = process.env.GODOT_WS || "http://127.0.0.1:9080";
const CLUSTER = process.env.SOLANA_CLUSTER || "devnet";
const RPC =
  process.env.SOLANA_RPC ||
  (CLUSTER === "mainnet-beta"
    ? "https://api.mainnet-beta.solana.com"
    : "https://api.devnet.solana.com");
const SETTLE_SECRET = process.env.WAGER_SETTLE_SECRET || "trenchwar-dev-settle";

const connection = new Connection(RPC, "confirmed");
const DATA_DIR = path.join(__dirname, ".data");
const MATCHES_FILE = path.join(DATA_DIR, "matches.json");

if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

function loadMatches() {
  try {
    return JSON.parse(fs.readFileSync(MATCHES_FILE, "utf8"));
  } catch {
    return {};
  }
}
function saveMatches(m) {
  fs.writeFileSync(MATCHES_FILE, JSON.stringify(m, null, 2));
}

let matches = loadMatches();

function clusterLabel() {
  return CLUSTER;
}

function recreateKeypair(secretB58) {
  return Keypair.fromSecretKey(bs58.decode(secretB58));
}

const app = express();
app.use(cors({ origin: true }));
app.use(express.json({ limit: "64kb" }));
// Allow browser clients on Vercel (or elsewhere) to call this API cross-origin.
app.use((_req, res, next) => {
  res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
  next();
});

app.get("/health", (_req, res) => {
  res.json({ ok: true, cluster: clusterLabel(), godot: GODOT_WS });
});

app.get("/api/wager/config", (_req, res) => {
  res.json({
    cluster: clusterLabel(),
    rpc: RPC,
    minStakeSol: 0.001,
    maxStakeSol: 5,
    stakesSol: [0, 0.01, 0.05, 0.1, 0.25],
  });
});

/** Create / fetch escrow for a room. Both players deposit equal lamports. */
app.post("/api/wager/create", async (req, res) => {
  try {
    const room = String(req.body.room || "").toUpperCase();
    const stakeSol = Number(req.body.stakeSol || 0);
    const wallet = String(req.body.wallet || "");
    if (!room || room.length < 3) {
      return res.status(400).json({ error: "Invalid room code" });
    }
    if (!(stakeSol > 0)) {
      return res.status(400).json({ error: "stakeSol must be > 0" });
    }
    if (!wallet) {
      return res.status(400).json({ error: "wallet required" });
    }
    let m = matches[room];
    if (!m || m.status === "paid" || m.status === "refunded") {
      const kp = Keypair.generate();
      m = {
        room,
        stakeLamports: Math.round(stakeSol * LAMPORTS_PER_SOL),
        stakeSol,
        escrow: kp.publicKey.toBase58(),
        escrowSecret: bs58.encode(kp.secretKey),
        players: {},
        status: "open", // open → funded → paid
        createdAt: Date.now(),
        cluster: clusterLabel(),
      };
      matches[room] = m;
      saveMatches(matches);
    }
    if (m.stakeSol !== stakeSol && Object.keys(m.players).length === 0) {
      m.stakeSol = stakeSol;
      m.stakeLamports = Math.round(stakeSol * LAMPORTS_PER_SOL);
    }
    if (!m.players[wallet]) {
      if (Object.keys(m.players).length >= 2) {
        return res.status(400).json({ error: "Match already has two wallets" });
      }
      m.players[wallet] = { deposited: false, pubkey: wallet };
      saveMatches(matches);
    }
    res.json({
      room,
      escrow: m.escrow,
      stakeSol: m.stakeSol,
      stakeLamports: m.stakeLamports,
      cluster: m.cluster,
      status: m.status,
      players: Object.keys(m.players),
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e.message || e) });
  }
});

/** Client confirms they sent a deposit; we verify on-chain balance. */
app.post("/api/wager/confirm-deposit", async (req, res) => {
  try {
    const room = String(req.body.room || "").toUpperCase();
    const wallet = String(req.body.wallet || "");
    const signature = String(req.body.signature || "");
    const m = matches[room];
    if (!m) return res.status(404).json({ error: "No wager for room" });
    if (!m.players[wallet]) {
      return res.status(400).json({ error: "Wallet not in this wager" });
    }
    const escrowPk = new PublicKey(m.escrow);
    const bal = await connection.getBalance(escrowPk);
    const needed = m.stakeLamports * Object.keys(m.players).length;
    // Mark this wallet deposited if escrow has grown enough for at least one stake
    // (and optional signature present).
    if (bal >= m.stakeLamports) {
      m.players[wallet].deposited = true;
      if (signature) m.players[wallet].signature = signature;
    }
    const allIn = Object.values(m.players).every((p) => p.deposited);
    const funded = bal >= m.stakeLamports * Math.max(2, Object.keys(m.players).length);
    if (funded || (allIn && Object.keys(m.players).length >= 2 && bal >= m.stakeLamports * 2)) {
      m.status = "funded";
    }
    saveMatches(matches);
    res.json({
      room,
      balanceLamports: bal,
      status: m.status,
      players: m.players,
      ready: m.status === "funded",
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.get("/api/wager/status", async (req, res) => {
  try {
    const room = String(req.query.room || "").toUpperCase();
    const m = matches[room];
    if (!m) return res.status(404).json({ error: "No wager" });
    const bal = await connection.getBalance(new PublicKey(m.escrow));
    res.json({
      room,
      escrow: m.escrow,
      stakeSol: m.stakeSol,
      status: m.status,
      balanceLamports: bal,
      players: Object.fromEntries(
        Object.entries(m.players).map(([k, v]) => [k, { deposited: v.deposited }])
      ),
      cluster: m.cluster,
      ready: m.status === "funded",
    });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

/** Authority settles: send entire escrow (minus rent-exempt dust) to winner. */
app.post("/api/wager/settle", async (req, res) => {
  try {
    const secret = String(req.headers["x-settle-secret"] || req.body.secret || "");
    if (secret !== SETTLE_SECRET) {
      return res.status(401).json({ error: "Unauthorized" });
    }
    const room = String(req.body.room || "").toUpperCase();
    const winner = String(req.body.winner || "");
    const m = matches[room];
    if (!m) return res.status(404).json({ error: "No wager" });
    if (m.status === "paid") {
      return res.json({ ok: true, already: true, signature: m.payoutSig });
    }
    if (!winner || !m.players[winner]) {
      return res.status(400).json({ error: "Winner must be a deposited player wallet" });
    }
    const kp = recreateKeypair(m.escrowSecret);
    const bal = await connection.getBalance(kp.publicKey);
    const rent = 5000; // fee buffer
    const sendLamports = bal - rent;
    if (sendLamports < m.stakeLamports) {
      return res.status(400).json({ error: "Escrow underfunded", balance: bal });
    }
    const tx = new Transaction().add(
      SystemProgram.transfer({
        fromPubkey: kp.publicKey,
        toPubkey: new PublicKey(winner),
        lamports: sendLamports,
      })
    );
    const sig = await sendAndConfirmTransaction(connection, tx, [kp], {
      commitment: "confirmed",
    });
    m.status = "paid";
    m.winner = winner;
    m.payoutSig = sig;
    m.payoutLamports = sendLamports;
    // Drop secret after payout
    delete m.escrowSecret;
    saveMatches(matches);
    res.json({ ok: true, signature: sig, lamports: sendLamports, winner });
  } catch (e) {
    console.error("settle", e);
    res.status(500).json({ error: String(e.message || e) });
  }
});

const server = http.createServer(app);
const proxy = httpProxy.createProxyServer({
  target: GODOT_WS,
  ws: true,
  changeOrigin: true,
  xfwd: true,
});

proxy.on("error", (err, _req, res) => {
  console.error("proxy error", err.message);
  if (res && !res.headersSent && typeof res.writeHead === "function") {
    res.writeHead(502);
    res.end("Godot server unreachable");
  }
});

// Non-API HTTP also proxied (rarely used); WS upgrades always → Godot.
server.on("upgrade", (req, socket, head) => {
  proxy.ws(req, socket, head);
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[gateway] http+ws :${PORT} → Godot ${GODOT_WS}`);
  console.log(`[gateway] Solana cluster=${CLUSTER}`);
  console.log(`[gateway] wager routes /api/wager/*`);
});
