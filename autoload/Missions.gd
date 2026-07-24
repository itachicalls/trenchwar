extends Node
## Mission/objective tracker. Levels push objectives; gameplay code reports progress
## through complete()/progress(). The HUD listens to Events.objectives_changed.

class Objective:
	var id: String
	var text: String
	var count_needed: int = 1
	var count_done: int = 0
	var done: bool = false
	func label() -> String:
		if count_needed > 1:
			return "%s  (%d/%d)" % [text, count_done, count_needed]
		return text

var mission_title: String = ""
var objectives: Array[Objective] = []
var _on_all_complete: Callable = Callable()

## Set by the active room: Callable(objective_id) -> Vector3 world position of the
## nearest target for that objective, or Vector3.INF for "no marker".
var marker_provider: Callable = Callable()

func start_mission(title: String, on_all_complete: Callable = Callable()) -> void:
	mission_title = title
	objectives.clear()
	_on_all_complete = on_all_complete
	marker_provider = Callable()
	Events.objectives_changed.emit()

## World position of the current objective's marker, or Vector3.INF.
func active_marker() -> Vector3:
	var o := active_objective()
	if o == null or not marker_provider.is_valid():
		return Vector3.INF
	return marker_provider.call(o.id)

func add_objective(id: String, text: String, count: int = 1) -> void:
	var o := Objective.new()
	o.id = id
	o.text = text
	o.count_needed = count
	objectives.append(o)
	Events.objectives_changed.emit()

func progress(id: String, amount: int = 1) -> void:
	var o := _find(id)
	if o == null or o.done:
		return
	o.count_done = mini(o.count_done + amount, o.count_needed)
	if o.count_done >= o.count_needed:
		_finish(o)
	Events.objectives_changed.emit()

func complete(id: String) -> void:
	var o := _find(id)
	if o == null or o.done:
		return
	o.count_done = o.count_needed
	_finish(o)
	Events.objectives_changed.emit()

## Drop the remaining quota when a rescue target is lost so the mission
## cannot soft-lock (prefer keeping captives alive — this is a safety net).
func forgive(id: String, amount: int = 1) -> void:
	var o := _find(id)
	if o == null or o.done or amount <= 0:
		return
	o.count_needed = maxi(o.count_done, o.count_needed - amount)
	if o.count_needed <= 0:
		o.count_needed = 1
		o.count_done = 1
	if o.count_done >= o.count_needed:
		_finish(o)
	Events.objectives_changed.emit()

## Kill-quota safety net: if fewer matching enemies remain than the objective
## still needs (or none), shrink/complete so the mission cannot soft-lock when
## a spawn fails, a body falls out of the world, or squadmates finish the rest.
func sync_living(id: String, living: int) -> void:
	var o := _find(id)
	if o == null or o.done:
		return
	var need := o.count_needed - o.count_done
	if need <= 0:
		return
	if living <= 0:
		complete(id)
		return
	if living < need:
		o.count_needed = o.count_done + living
		if o.count_done >= o.count_needed:
			_finish(o)
		Events.objectives_changed.emit()

func is_done(id: String) -> bool:
	var o := _find(id)
	return o != null and o.done

func active_objective() -> Objective:
	for o in objectives:
		if not o.done:
			return o
	return null

func _finish(o: Objective) -> void:
	o.done = true
	Sfx.play("objective")
	Events.notify.emit("OBJECTIVE COMPLETE: " + o.text)
	for other in objectives:
		if not other.done:
			return
	Events.mission_completed.emit(mission_title)
	if _on_all_complete.is_valid():
		_on_all_complete.call()

func _find(id: String) -> Objective:
	for o in objectives:
		if o.id == id:
			return o
	return null
