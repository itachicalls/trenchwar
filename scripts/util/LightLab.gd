class_name LightLab
extends Node3D
## Diagnostic scene for lighting bisection. Run with:
##   godot --path . -- --lightlab=<variant>
## Variants toggle environment features one at a time; each run screenshots to
## screenshots/lab_<variant>.png so we can see exactly what kills the light.

var variant: String = "full"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lightlab="):
			variant = arg.split("=")[1]

	var env: Environment
	match variant:
		"plain":
			# Absolute baseline: gray bg, strong flat ambient, nothing else.
			env = Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.25, 0.25, 0.3)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.5, 0.5, 0.6)
			env.ambient_light_energy = 1.5
		"nosky":
			env = RoomBase.make_night_environment(Color(0.12, 0.14, 0.24), Color(0.42, 0.47, 0.62), 1.6)
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.03, 0.04, 0.1)
		"nossao":
			env = RoomBase.make_night_environment(Color(0.12, 0.14, 0.24), Color(0.42, 0.47, 0.62), 1.6)
			env.ssao_enabled = false
		"notonemap":
			env = RoomBase.make_night_environment(Color(0.12, 0.14, 0.24), Color(0.42, 0.47, 0.62), 1.6)
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.tonemap_exposure = 1.0
		"nofog":
			env = RoomBase.make_night_environment(Color(0.12, 0.14, 0.24), Color(0.42, 0.47, 0.62), 1.6)
			env.fog_enabled = false
		_:
			env = RoomBase.make_night_environment(Color(0.12, 0.14, 0.24), Color(0.42, 0.47, 0.62), 1.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	if variant != "nolights":
		RoomBase.add_light_rig(self, Vector3(-38, 145, 0), Color(0.68, 0.76, 1.0), 1.5)

	# Floor.
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(40, 1, 40)
	floor_mesh.mesh = fm
	floor_mesh.material_override = ToyMaterials.soft(Color(0.36, 0.3, 0.42))
	floor_mesh.position.y = -0.5
	add_child(floor_mesh)

	# Material bisection row. Same green, features added one at a time:
	# 0 bare albedo · 1 +clearcoat · 2 +rim · 3 full plastic() · 4 soft (control)
	var green_c := Color(0.35, 0.55, 0.25)
	var bare := StandardMaterial3D.new()
	bare.albedo_color = green_c
	bare.roughness = 0.32
	var cc := StandardMaterial3D.new()
	cc.albedo_color = green_c
	cc.roughness = 0.32
	cc.clearcoat_enabled = true
	cc.clearcoat = 0.55
	cc.clearcoat_roughness = 0.25
	var rim := StandardMaterial3D.new()
	rim.albedo_color = green_c
	rim.roughness = 0.32
	rim.rim_enabled = true
	rim.rim = 0.4
	rim.rim_tint = 0.6
	var mats: Array = [
		bare,
		cc,
		rim,
		ToyMaterials.plastic(green_c),
		ToyMaterials.soft(green_c),
	]
	for i in mats.size():
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, 1.5, 1.5)
		box.mesh = bm
		box.material_override = mats[i]
		box.position = Vector3(-6.0 + i * 3.0, 0.75, 0)
		add_child(box)

	# Two soldiers + a tall wall behind them (tests shadowing).
	var green: FactionData = load("res://data/factions/green_army.tres")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var s1 := ModelLib.build_character(green)
	s1.position = Vector3(-2, 0, 3)
	add_child(s1)
	var s2 := ModelLib.build_character(chrome, true)
	s2.position = Vector3(2, 0, 3)
	s2.rotation_degrees.y = 180
	add_child(s2)
	if variant == "models":
		var tank := ModelLib.build_tank(3.4)
		if tank != null:
			tank.position = Vector3(5.5, 0, 2.0)
			add_child(tank)
	if variant == "anims3":
		# Gameplay view: soldiers face AWAY from camera playing Idle_Shoot,
		# with candidate yaw compensations. Pick the one whose back is square
		# to the camera and rifle points dead ahead.
		for i in 3:
			var offset := -22.0 + i * 22.0   # -22 0 +22
			var rig := ModelLib.build_character(green)
			rig.position = Vector3(-6.0 + i * 6.0, 0, 1.0)
			add_child(rig)
			var model := rig.get_child(0) as Node3D
			model.rotation_degrees.y = 180.0 + offset
			if rig.has_meta("anim"):
				var ap: AnimationPlayer = rig.get_meta("anim")
				ap.play("Idle_Shoot")
				ap.advance(0.5)
			var tag := Label3D.new()
			tag.text = str(offset)
			tag.font_size = 48
			tag.position = rig.position + Vector3(0, 2.4, 0)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(tag)
	if variant == "anims2":
		# Idle_Shoot with different model yaw offsets: find the compensation
		# that points the rifle straight at the camera (rig faces +Z here).
		for i in 5:
			var offset := -60.0 + i * 30.0   # -60 -30 0 +30 +60
			var rig := ModelLib.build_character(green)
			rig.position = Vector3(-8.0 + i * 4.0, 0, 6.0)
			rig.rotation_degrees.y = 180.0
			add_child(rig)
			var model := rig.get_child(0) as Node3D
			model.rotation_degrees.y = 180.0 + offset
			if rig.has_meta("anim"):
				var ap: AnimationPlayer = rig.get_meta("anim")
				ap.play("Idle_Shoot")
				ap.advance(0.5)
			var tag := Label3D.new()
			tag.text = str(offset)
			tag.font_size = 48
			tag.position = rig.position + Vector3(0, 2.2, 0)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(tag)
	if variant == "anims":
		# Four soldiers, one per animation, all built facing the camera (+Z).
		# Compares body orientation between poses to catch bladed shoot anims.
		var anims := ["Idle", "Idle_Shoot", "Run_Gun", "Run_Shoot"]
		for i in anims.size():
			var rig := ModelLib.build_character(green)
			rig.position = Vector3(-6.0 + i * 4.0, 0, 6.0)
			rig.rotation_degrees.y = 180.0
			add_child(rig)
			if rig.has_meta("anim"):
				var ap: AnimationPlayer = rig.get_meta("anim")
				ap.play(anims[i])
				ap.advance(0.5)
			var tag := Label3D.new()
			tag.text = anims[i]
			tag.font_size = 48
			tag.position = rig.position + Vector3(0, 2.2, 0)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(tag)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(20, 12, 1)
	wall.mesh = wm
	wall.material_override = ToyMaterials.soft(Color(0.55, 0.6, 0.7))
	wall.position = Vector3(0, 6, -6)
	add_child(wall)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 11)
	cam.rotation_degrees.x = -16
	cam.fov = 55
	add_child(cam)
	cam.make_current()

	get_tree().create_timer(1.0).timeout.connect(func():
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://screenshots/lab_%s.png" % variant)
		print("LAB OK ", variant)
		get_tree().quit())
