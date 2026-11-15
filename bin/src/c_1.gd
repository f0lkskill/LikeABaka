extends Sprite3D

## 每次新歌词出现后随机切换角色立绘。
## 旧立绘保持不透明作为残留底图，新立绘在上层淡入，舞台上不会出现空角色。
## 也可以由外部选项系统直接调用 switch_random_texture()。

@export var lyric_ring_path: NodePath = ^"../../LyricRing"
## 角色立绘目录；目录下的 png 会全部作为候选。
@export_dir var texture_directory: String = "res://bin/asset/image/cha_1"
@export_range(0.0, 1.0, 0.01) var min_switch_delay: float = 0.05
@export_range(0.0, 2.0, 0.01) var max_switch_delay: float = 0.2
@export_range(0.05, 1.0, 0.01) var transition_duration: float = 0.18

var _textures: Array[Texture2D] = []
var _overlay: Sprite3D
var _current_texture: Texture2D
var _transition_tween: Tween
var _switching: bool = false
var _switch_token: int = 0


func _ready() -> void:
	_current_texture = texture
	_load_textures()
	_create_overlay()
	var lyric_ring := get_node_or_null(lyric_ring_path)
	if lyric_ring != null and lyric_ring.has_signal("line_spawned"):
		lyric_ring.line_spawned.connect(_on_line_spawned)


## 由外部选项系统调用，立即排队一次随机切换。
func switch_random_texture() -> void:
	_switch_token += 1
	var token := _switch_token
	await get_tree().create_timer(randf_range(min_switch_delay, max_switch_delay)).timeout
	if token != _switch_token:
		return
	_perform_random_switch()


func _on_line_spawned(_index: int, _time: float, _text: String) -> void:
	_switch_token += 1
	var token := _switch_token
	await get_tree().create_timer(randf_range(min_switch_delay, max_switch_delay)).timeout
	if token != _switch_token:
		return
	_perform_random_switch()


func _load_textures() -> void:
	var directory := DirAccess.open(texture_directory)
	if directory == null:
		push_warning("C1: 无法打开角色立绘目录: %s" % texture_directory)
		if _current_texture != null:
			_textures.append(_current_texture)
		return
	var files := directory.get_files()
	files.sort()
	for file in files:
		if file.get_extension().to_lower() != "png":
			continue
		var loaded := load(texture_directory.path_join(file)) as Texture2D
		if loaded != null:
			_textures.append(loaded)
	if _textures.is_empty() and _current_texture != null:
		_textures.append(_current_texture)


func _create_overlay() -> void:
	_overlay = Sprite3D.new()
	_overlay.name = "C1ResidualOverlay"
	_overlay.texture = _current_texture
	_overlay.transform = Transform3D(Basis(), Vector3(0.0, 0.0, 0.01))
	_overlay.pixel_size = pixel_size
	_overlay.billboard = billboard
	_overlay.shaded = shaded
	_overlay.double_sided = double_sided
	_overlay.no_depth_test = no_depth_test
	_overlay.fixed_size = fixed_size
	_overlay.alpha_cut = alpha_cut
	_overlay.modulate = Color(1, 1, 1, 0)
	_overlay.visible = false
	add_child(_overlay)


func _perform_random_switch() -> void:
	if _switching or _textures.size() <= 1:
		return
	var candidates: Array[Texture2D] = []
	for candidate in _textures:
		if candidate != _current_texture:
			candidates.append(candidate)
	if candidates.is_empty():
		return
	var next_texture := candidates[randi() % candidates.size()]
	_start_residual_transition(next_texture)


func _start_residual_transition(next_texture: Texture2D) -> void:
	_switching = true
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	# 底图始终保留当前立绘，只让上层新立绘淡入。
	modulate = Color(1, 1, 1, 1)
	_overlay.texture = next_texture
	_overlay.modulate = Color(1, 1, 1, 0)
	_overlay.visible = true
	_transition_tween = create_tween()
	_transition_tween.tween_property(_overlay, "modulate:a", 1.0, transition_duration)
	_transition_tween.tween_callback(_finish_transition.bind(next_texture))


func _finish_transition(next_texture: Texture2D) -> void:
	texture = next_texture
	_current_texture = next_texture
	_overlay.visible = false
	_overlay.modulate = Color(1, 1, 1, 0)
	_switching = false
