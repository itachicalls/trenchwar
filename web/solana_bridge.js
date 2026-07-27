/**
 * Phantom / Solana wallet bridge for Trenchwar (web + mobile browsers).
 * Loaded before the Godot engine; Godot calls window.trenchwarSol.*
 */
(function () {
  const TW = {
    pubkey: "",
    onWallet: null,
    onDeposit: null,

    provider() {
      const s = window.solana;
      if (s && s.isPhantom) return s;
      // Solflare / wallet-standard fallback
      if (window.solflare && window.solflare.isSolflare) return window.solflare;
      return s || null;
    },

    async connect() {
      try {
        const p = this.provider();
        if (!p) {
          // Mobile: deep-link to Phantom browse
          const ret = encodeURIComponent(window.location.href);
          const ref = encodeURIComponent(window.location.origin);
          window.location.href =
            "https://phantom.app/ul/browse/" +
            encodeURIComponent(window.location.href) +
            "?ref=" +
            ref;
          this._emitWallet("");
          return;
        }
        const res = await p.connect();
        this.pubkey = (res && res.publicKey ? res.publicKey : p.publicKey).toString();
        this._emitWallet(this.pubkey);
      } catch (e) {
        console.error("tw connect", e);
        this._emitWallet("");
        if (this.onDeposit) this.onDeposit(false, "", String(e.message || e));
      }
    },

    async disconnect() {
      try {
        const p = this.provider();
        if (p && p.disconnect) await p.disconnect();
      } catch (_) {}
      this.pubkey = "";
      this._emitWallet("");
    },

    async deposit(escrowBase58, lamports, cluster) {
      try {
        const p = this.provider();
        if (!p || !this.pubkey) {
          if (this.onDeposit) this.onDeposit(false, "", "Connect Phantom first");
          return;
        }
        // Prefer web3 from CDN if present; otherwise use raw Transaction via Phantom's request
        if (!window.solanaWeb3) {
          await this._loadWeb3();
        }
        const {
          Connection,
          PublicKey,
          SystemProgram,
          Transaction,
        } = window.solanaWeb3;
        const rpc =
          cluster === "mainnet-beta"
            ? "https://api.mainnet-beta.solana.com"
            : "https://api.devnet.solana.com";
        const connection = new Connection(rpc, "confirmed");
        const from = new PublicKey(this.pubkey);
        const to = new PublicKey(escrowBase58);
        const tx = new Transaction().add(
          SystemProgram.transfer({
            fromPubkey: from,
            toPubkey: to,
            lamports: Number(lamports),
          })
        );
        tx.feePayer = from;
        const { blockhash } = await connection.getLatestBlockhash();
        tx.recentBlockhash = blockhash;
        const signed = await p.signAndSendTransaction(tx);
        const sig = signed.signature || signed;
        if (this.onDeposit) this.onDeposit(true, String(sig), "ok");
      } catch (e) {
        console.error("tw deposit", e);
        if (this.onDeposit) this.onDeposit(false, "", String(e.message || e));
      }
    },

    _loadWeb3() {
      return new Promise((resolve, reject) => {
        if (window.solanaWeb3) return resolve();
        const s = document.createElement("script");
        s.src = "https://unpkg.com/@solana/web3.js@1.98.0/lib/index.iife.min.js";
        s.onload = () => {
          // iife may expose solanaWeb3
          if (!window.solanaWeb3 && window.solanaWeb3Bundle) {
            window.solanaWeb3 = window.solanaWeb3Bundle;
          }
          // unpkg iife typically sets solanaWeb3
          resolve();
        };
        s.onerror = reject;
        document.head.appendChild(s);
      });
    },

    _emitWallet(pk) {
      this.pubkey = pk || "";
      if (typeof window._twWalletCb === "function") {
        try {
          window._twWalletCb(this.pubkey);
        } catch (e) {
          console.warn(e);
        }
      }
      if (this.onWallet) this.onWallet(this.pubkey);
    },

    _bindGodot() {
      // no-op hook for Godot
    },
  };

  window.trenchwarSol = TW;

  // Auto-reconnect if Phantom already approved this origin
  window.addEventListener("load", async () => {
    try {
      const p = TW.provider();
      if (p && p.isConnected && p.publicKey) {
        TW.pubkey = p.publicKey.toString();
        TW._emitWallet(TW.pubkey);
      }
    } catch (_) {}
  });
})();
