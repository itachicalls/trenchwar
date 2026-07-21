extends Node3D
## Diagnostic: every landmark model in a bright grid, screenshotted.
## Run: godot --path . -- --landlab

const NAMES := [
	"bed_double", "coffee_table", "dining_table", "desk", "chair", "tv",
	"bookshelf", "toilet", "bathtub", "sink", "fridge", "car",
	"washing_machine", "stove", "sofa",
]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.28)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	floor_mesh.mesh = pm
	add_child(floor_mesh)

	for i in NAMES.size():
		var rig := ModelLib.build_landmark(NAMES[i], 20.0)
		var x := float(i % 5) * 45.0 - 90.0
		var z := float(i / 5) * 50.0 - 50.0
		if rig == null:
			print("LANDLAB MISSING: ", NAMES[i])
			continue
		rig.position = Vector3(x, 0, z)
		add_child(rig)
		var label := Label3D.new()
		label.text = NAMES[i]
		label.font_size = 220
		label.position = Vector3(x, 26, z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)

	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.position = Vector3(0, 130, 130)
	cam.look_at(Vector3(0, 0, -10))

	get_tree().create_timer(2.0).timeout.connect(func():
		if DisplayServer.get_name() != "headless":
			var img := get_viewport().get_texture().get_image()
			img.save_png("res://screenshots/landlab.png")
		print("LANDLAB OK")
		get_tree().quit())
