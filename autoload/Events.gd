extends Node
## Global signal bus. Systems communicate through here instead of hard references,
## which keeps rooms, factions, UI and AI fully decoupled (and multiplayer-friendly later).

# --- Units / combat ---
signal unit_died(unit: Node)
signal player_spawned(player: Node)
signal player_died
signal player_health_changed(health: float, max_health: float)
signal player_damaged
signal hit_confirmed(killed: bool)

# --- Weapons ---
signal ammo_changed(ammo: int, magazine: int)
signal weapon_changed(display_name: String)

# --- Squad ---
signal squad_changed(members: Array)
signal squad_mode_changed(mode_name: String)

# --- Missions / world ---
signal objectives_changed
signal mission_completed(title: String)
signal mission_failed(reason: String)
signal parts_changed(amount: int)
signal collectible_found(toy_name: String, found: int, total: int)
signal notify(text: String)

# --- Vehicles ---
signal vehicle_entered(vehicle: Node)
signal vehicle_exited

# --- Economy / powerups ---
signal coins_changed(amount: int)
signal powerup_started(id: String, duration: float)
signal fuel_changed(fuel: float, max_fuel: float)
