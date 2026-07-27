extends Node
## Web/mobile bridge to Phantom (and wallet-standard) via JavaScript.
## Desktop builds: wallet features unavailable (use the web build for SOL stakes).

signal wallet_changed(pubkey: String)
signal bridge_ready
signal bridge_error(message: String)
signal deposit_result(ok: bool, signature: String, message: String)

var pubkey: String = ""
var _cb_wallet = null
var _cb_deposit = null
var _bridge_ok := false

func is_web() -> bool:
	return OS.has_feature("web")

func available() -> bool:
	return is_web() and _bridge_ok

func _ready() -> void:
	if not is_web():
		return
	_cb_wallet = JavaScriptBridge.create_callback(_on_js_wallet)
	_cb_deposit = JavaScriptBridge.create_callback(_on_js_deposit)
	JavaScriptBridge.eval("""
		window._twSol = window._twSol || {};
		if (window.trenchwarSol) { window.trenchwarSol._bindGodot(); }
	""", true)
	_bind_callbacks()
	_bridge_ok = true
	bridge_ready.emit()

func _bind_callbacks() -> void:
	var tw: Variant = JavaScriptBridge.eval("window.trenchwarSol", true)
	if tw == null:
		get_tree().create_timer(0.5).timeout.connect(func():
			_bind_callbacks()
			_bridge_ok = true
			bridge_ready.emit())
		return
	JavaScriptBridge.eval("""
		(function(){
			if (!window.trenchwarSol) return;
			window.trenchwarSol.onWallet = function(pk){
				if (window._twWalletCb) window._twWalletCb(pk);
			};
			window.trenchwarSol.onDeposit = function(ok, sig, msg){
				if (window._twDepositCb) window._twDepositCb(ok, sig, msg);
			};
		})();
	""", true)
	var w := JavaScriptBridge.get_interface("window")
	if w:
		w._twWalletCb = _cb_wallet
		w._twDepositCb = _cb_deposit

func connect_wallet() -> void:
	if not is_web():
		bridge_error.emit("Connect Phantom in the web/mobile build.")
		return
	JavaScriptBridge.eval("window.trenchwarSol && window.trenchwarSol.connect();", true)

func disconnect_wallet() -> void:
	pubkey = ""
	JavaScriptBridge.eval("window.trenchwarSol && window.trenchwarSol.disconnect();", true)
	wallet_changed.emit("")

func deposit(escrow: String, lamports: int, cluster: String) -> void:
	if not is_web():
		bridge_error.emit("Deposits require web/mobile + Phantom.")
		return
	var js := "window.trenchwarSol && window.trenchwarSol.deposit('%s', %d, '%s');" % [
		escrow, lamports, cluster]
	JavaScriptBridge.eval(js, true)

func short_key() -> String:
	if pubkey.length() < 8:
		return pubkey
	return pubkey.substr(0, 4) + "…" + pubkey.substr(pubkey.length() - 4, 4)

func _on_js_wallet(args: Array) -> void:
	pubkey = str(args[0]) if args.size() > 0 else ""
	wallet_changed.emit(pubkey)

func _on_js_deposit(args: Array) -> void:
	var ok := bool(args[0]) if args.size() > 0 else false
	var sig := str(args[1]) if args.size() > 1 else ""
	var msg := str(args[2]) if args.size() > 2 else ""
	deposit_result.emit(ok, sig, msg)
