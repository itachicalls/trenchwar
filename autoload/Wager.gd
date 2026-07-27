extends Node
## Solana VS stakes: both players deposit equal SOL into a per-room escrow;
## winner receives the pot. Uses live-gateway /api/wager (Cloudflare tunnel).

signal config_loaded
signal wager_updated
signal wager_error(message: String)
signal funded
signal settled(signature: String)

var api_base: String = ""          # https://xxx.trycloudflare.com
var cluster: String = "devnet"
var stake_sol: float = 0.0
var room: String = ""
var escrow: String = ""
var stake_lamports: int = 0
var status: String = "idle"        # idle|open|funded|paid
var pot_ready: bool = false
var last_error: String = ""

const STAKE_OPTIONS := [0.0, 0.01, 0.05, 0.1, 0.25]

func _ready() -> void:
	SolBridge.deposit_result.connect(_on_deposit_result)

func configure(p_api: String, p_cluster: String) -> void:
	api_base = p_api.strip_edges().trim_suffix("/")
	cluster = p_cluster if p_cluster != "" else "devnet"
	config_loaded.emit()

func set_stake(sol: float) -> void:
	stake_sol = sol
	wager_updated.emit()

func active() -> bool:
	return stake_sol > 0.0 and api_base != ""

func _http() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = 25
	add_child(h)
	return h

func _headers(json_body: bool = true) -> PackedStringArray:
	var h: PackedStringArray = ["Accept: application/json"]
	if json_body:
		h.append("Content-Type: application/json")
	return h

func create_or_join(p_room: String) -> void:
	room = p_room.to_upper()
	if not active():
		status = "idle"
		wager_updated.emit()
		return
	if SolBridge.pubkey == "":
		last_error = "Connect Phantom first"
		wager_error.emit(last_error)
		return
	var body := JSON.stringify({
		"room": room,
		"stakeSol": stake_sol,
		"wallet": SolBridge.pubkey,
	})
	var h := _http()
	h.request_completed.connect(func(result, code, _headers, body_bytes):
		h.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
			last_error = "Wager create failed (%s)" % code
			wager_error.emit(last_error)
			return
		var data = JSON.parse_string(body_bytes.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			wager_error.emit("Bad wager response")
			return
		escrow = str(data.get("escrow", ""))
		stake_lamports = int(data.get("stakeLamports", 0))
		status = str(data.get("status", "open"))
		cluster = str(data.get("cluster", cluster))
		wager_updated.emit()
		Events.notify.emit("Escrow ready — deposit %s SOL" % str(stake_sol))
	, CONNECT_ONE_SHOT)
	var err := h.request(api_base + "/api/wager/create", _headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		h.queue_free()
		wager_error.emit("HTTP error")

func deposit_now() -> void:
	if escrow == "" or stake_lamports <= 0:
		wager_error.emit("No escrow yet")
		return
	if SolBridge.pubkey == "":
		wager_error.emit("Connect wallet")
		return
	SolBridge.deposit(escrow, stake_lamports, cluster)

func _on_deposit_result(ok: bool, signature: String, message: String) -> void:
	if not ok:
		wager_error.emit(message if message != "" else "Deposit failed")
		return
	_confirm_deposit(signature)

func _confirm_deposit(signature: String) -> void:
	# signature used for audit trail on the gateway
	var body := JSON.stringify({
		"room": room,
		"wallet": SolBridge.pubkey,
		"signature": signature,
	})
	var h := _http()
	h.request_completed.connect(func(result, code, _headers, body_bytes):
		h.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
			wager_error.emit("Confirm failed")
			return
		var data = JSON.parse_string(body_bytes.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			status = str(data.get("status", status))
			pot_ready = bool(data.get("ready", false))
			if pot_ready:
				funded.emit()
				Events.notify.emit("Both stakes locked — fight for the pot!")
		wager_updated.emit()
	, CONNECT_ONE_SHOT)
	h.request(api_base + "/api/wager/confirm-deposit", _headers(), HTTPClient.METHOD_POST, body)

func refresh_status() -> void:
	if room == "" or api_base == "":
		return
	var h := _http()
	h.request_completed.connect(func(result, code, _headers, body_bytes):
		h.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
			return
		var data = JSON.parse_string(body_bytes.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			return
		status = str(data.get("status", status))
		pot_ready = bool(data.get("ready", false))
		escrow = str(data.get("escrow", escrow))
		wager_updated.emit()
		if pot_ready:
			funded.emit()
	, CONNECT_ONE_SHOT)
	h.request(api_base + "/api/wager/status?room=" + room.uri_encode(), _headers(false))

## Called by match authority (dedicated server / host) after a win.
func settle_winner(winner_wallet: String) -> void:
	if not active() or room == "" or winner_wallet == "":
		return
	var body := JSON.stringify({"room": room, "winner": winner_wallet})
	var secret := OS.get_environment("WAGER_SETTLE_SECRET")
	if secret == "":
		secret = "trenchwar-dev-settle"
	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"x-settle-secret: %s" % secret,
	])
	var h := _http()
	h.request_completed.connect(func(result, code, _headers, body_bytes):
		h.queue_free()
		var text: String = body_bytes.get_string_from_utf8()
		if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
			push_warning("Wager settle failed: %s %s" % [code, text])
			return
		var data = JSON.parse_string(text)
		if typeof(data) == TYPE_DICTIONARY and data.get("signature", "") != "":
			status = "paid"
			settled.emit(str(data.signature))
			Events.notify.emit("SOL pot paid — sig %s…" % str(data.signature).substr(0, 8))
		wager_updated.emit()
	, CONNECT_ONE_SHOT)
	h.request(api_base + "/api/wager/settle", headers, HTTPClient.METHOD_POST, body)

func reset_match() -> void:
	room = ""
	escrow = ""
	stake_lamports = 0
	status = "idle"
	pot_ready = false
	wager_updated.emit()
