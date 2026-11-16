extends Sprite3D

## 角色立绘集合切换时发出，参数为新的角色索引。
signal character_set_changed(index: int)

## 角色立绘随机切换控制器。
##
## 每次新歌词出现后，从导出的立绘目录中随机选择一张不同的 png。
## 同一角色内的表情切换使用残留淡入；整套角色切换则先淡出再换图，
## 避免两个不同角色同时出现在舞台上。
## 外部选项系统也可以直接调用 [method switch_random_texture]。
## 若与摄像机共用 [code]BGM_Analyzer[/code] 总线，不会影响音频播放。

## 歌词环节点路径，用于监听新歌词出现事件。
@export var lyric_ring_path: NodePath = ^"../../LyricRing"
## 角色立绘目录集合；切换角色时按顺序循环，当前目录下的 png 作为随机候选。
@export var character_directories: PackedStringArray = PackedStringArray([
	"res://bin/asset/image/cha_1",
	"res://bin/asset/image/cha_2",
])
## 新歌词出现后到开始切换立绘的最短随机延迟。
@export_range(0.0, 1.0, 0.01) var min_switch_delay: float = 0.05
## 新歌词出现后到开始切换立绘的最长随机延迟。
@export_range(0.0, 2.0, 0.01) var max_switch_delay: float = 0.2
## 普通随机立绘在旧立绘上淡入的时长。
@export_range(0.05, 1.0, 0.01) var transition_duration: float = 0.4
## 角色 1/2 整体切换时的过渡时长，通常比普通随机切换更长。
@export_range(0.05, 2.0, 0.01) var character_set_transition_duration: float = 0.7
## 各角色立绘相对默认位置的局部偏移，索引与 character_directories 对齐。
@export var character_offsets: PackedVector3Array = PackedVector3Array([
	Vector3.ZERO,
	Vector3.ZERO,
])
## 各角色立绘的额外缩放倍率，索引与 character_directories 对齐。
## cha_2 原图有效高度约为 cha_1 的 81%，默认放大以保持脚底和头顶对齐。
@export var character_scales: PackedFloat32Array = PackedFloat32Array([1.0, 1.235])
## 立绘始终朝向摄像机，避免舞台旋转时看到纸片侧面。
@export var face_camera: bool = true

var _textures: Array[Texture2D] = []
var _overlay: Sprite3D
var _current_texture: Texture2D
var _transition_tween: Tween
var _switching: bool = false
var _switch_token: int = 0
var _character_index: int = 0
var _texture_directory: String = ""
var _base_position: Vector3
var _base_scale: Vector3
var _offset_tween: Tween


## 初始化候选贴图、残留上层节点，并连接歌词信号。
func _ready() -> void:
	_current_texture = texture
	_base_position = position
	_base_scale = scale
	if face_camera:
		billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	if not character_directories.is_empty():
		_texture_directory = character_directories[0]
	_load_textures()
	_create_overlay()
	_apply_character_offset(0, 0.0)
	var lyric_ring := get_node_or_null(lyric_ring_path)
	if lyric_ring != null and lyric_ring.has_signal("line_spawned"):
		lyric_ring.line_spawned.connect(_on_line_spawned)


## 返回当前角色立绘集合索引。
func get_character_index() -> int:
	return _character_index


## 切换到下一套角色立绘，并优先选择同名贴图保持表情连续。
## 切换后所有随机立绘都只从当前角色目录中选择。
func switch_character_set() -> void:
	if character_directories.size() <= 1:
		return
	var previous_name := ""
	if _current_texture != null:
		previous_name = _current_texture.resource_path.get_file()
	_character_index = (_character_index + 1) % character_directories.size()
	_texture_directory = character_directories[_character_index]
	_load_textures()
	if _textures.is_empty():
		return
	var next_texture: Texture2D
	for candidate in _textures:
		if candidate.resource_path.get_file() == previous_name:
			next_texture = candidate
			break
	if next_texture == null:
		for candidate in _textures:
			if candidate.resource_path.get_file() == "normal.png":
				next_texture = candidate
				break
	if next_texture == null:
		next_texture = _textures[0]
	_start_character_set_transition(next_texture, character_set_transition_duration)
	character_set_changed.emit(_character_index)


## 由外部选项系统调用，经过随机短延迟后触发一次随机切换。
func switch_random_texture() -> void:
	_switch_token += 1
	var token := _switch_token
	await get_tree().create_timer(randf_range(min_switch_delay, max_switch_delay)).timeout
	if token != _switch_token:
		return
	_perform_random_switch()


## 收到新歌词后，经过随机短延迟触发一次立绘切换。
## [param _index] 歌词在时间轴中的索引，本脚本不使用。
## [param _time] 歌词时间戳，单位为秒，本脚本不使用。
## [param _text] 歌词文本，本脚本不使用。
func _on_line_spawned(_index: int, _time: float, _text: String) -> void:
	_switch_token += 1
	var token := _switch_token
	await get_tree().create_timer(randf_range(min_switch_delay, max_switch_delay)).timeout
	if token != _switch_token:
		return
	_perform_random_switch()


## 扫描当前角色目录下的所有 png，并缓存为候选贴图。
## 若目录不可用，则退回到当前 Sprite3D 的 texture。
func _load_textures() -> void:
	_textures.clear()
	var directory := DirAccess.open(_texture_directory)
	if directory == null:
		push_warning("C1: 无法打开角色立绘目录: %s" % _texture_directory)
		if _current_texture != null:
			_textures.append(_current_texture)
		return
	var files := directory.get_files()
	files.sort()
	for file in files:
		if file.get_extension().to_lower() != "png":
			continue
		var loaded := load(_texture_directory.path_join(file)) as Texture2D
		if loaded != null:
			_textures.append(loaded)
	if _textures.is_empty() and _current_texture != null:
		_textures.append(_current_texture)


## 创建用于淡入新贴图的上层 Sprite3D，并复制当前 Sprite3D 的显示参数。
func _create_overlay() -> void:
	_overlay = Sprite3D.new()
	_overlay.name = "C1ResidualOverlay"
	_overlay.texture = _current_texture
	_overlay.transform = Transform3D(Basis(), Vector3(0.0, 0.0, 0.02))
	_overlay.pixel_size = pixel_size
	_overlay.billboard = billboard
	_overlay.shaded = shaded
	_overlay.double_sided = double_sided
	# 上层贴图必须稳定盖在底图上，避免深度冲突导致淡入不可见。
	_overlay.no_depth_test = true
	_overlay.fixed_size = fixed_size
	_overlay.alpha_cut = alpha_cut
	_overlay.modulate = Color(1, 1, 1, 0)
	_overlay.visible = false
	add_child(_overlay)


## 从候选贴图中随机选择一张与当前不同的贴图并开始过渡。
## 正在过渡或候选不足时直接跳过。
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


## 开始一次角色集合切换：先淡出旧立绘，在完全透明时替换贴图和偏移，再淡入。
## 这样不会同时显示两个不同角色。
## [param next_texture] 新角色集合中的目标贴图。
## [param duration] 整个过渡时长。
func _start_character_set_transition(next_texture: Texture2D, duration: float) -> void:
	_switch_token += 1
	_switching = true
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if _offset_tween != null and _offset_tween.is_valid():
		_offset_tween.kill()
	_overlay.visible = false
	_overlay.modulate = Color(1, 1, 1, 0)
	modulate = Color(1, 1, 1, 1)
	if duration <= 0.0:
		_apply_character_set_change(next_texture, _character_index)
		modulate = Color(1, 1, 1, 1)
		_switching = false
		return
	var fade_out := duration * 0.4
	var fade_in := duration - fade_out
	_transition_tween = create_tween()
	_transition_tween.tween_property(self, "modulate:a", 0.0, fade_out) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_callback(
		_apply_character_set_change.bind(next_texture, _character_index)
	)
	_transition_tween.tween_property(self, "modulate:a", 1.0, fade_in) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_callback(_finish_character_set_transition)


## 在立绘完全透明时替换贴图、位置和缩放。
## [param next_texture] 新贴图。
## [param index] 新角色集合索引。
func _apply_character_set_change(next_texture: Texture2D, index: int) -> void:
	texture = next_texture
	_current_texture = next_texture
	_overlay.visible = false
	_apply_character_offset(index, 0.0)


## 完成角色集合切换，恢复不透明并解除切换锁。
func _finish_character_set_transition() -> void:
	modulate = Color(1, 1, 1, 1)
	_switching = false


## 开始一次残留式过渡：旧贴图留在底层，新贴图在上层淡入。
## [param next_texture] 即将切换到的目标贴图。
## [param duration] 可选的自定义过渡时长；小于 0 时使用普通随机切换时长。
func _start_residual_transition(next_texture: Texture2D, duration: float = -1.0) -> void:
	_switching = true
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	var fade_duration := transition_duration if duration < 0.0 else duration
	# 底图始终保留当前立绘，只让上层新立绘淡入。
	modulate = Color(1, 1, 1, 1)
	_overlay.texture = next_texture
	_overlay.modulate = Color(1, 1, 1, 0)
	_overlay.visible = true
	_transition_tween = create_tween()
	_transition_tween.tween_property(_overlay, "modulate:a", 1.0, fade_duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_callback(_finish_transition.bind(next_texture))


## 按角色索引应用各自的相对位置和缩放偏移。
## [param index] 角色集合索引。
## [param duration] 偏移过渡时长；小于等于 0 时立即应用。
func _apply_character_offset(index: int, duration: float) -> void:
	var offset := Vector3.ZERO
	if not character_offsets.is_empty():
		offset = character_offsets[index % character_offsets.size()]
	var scale_multiplier := 1.0
	if not character_scales.is_empty():
		scale_multiplier = character_scales[index % character_scales.size()]
	var target_position := _base_position + offset
	var target_scale := _base_scale * scale_multiplier
	if _offset_tween != null and _offset_tween.is_valid():
		_offset_tween.kill()
	if duration <= 0.0:
		position = target_position
		scale = target_scale
		return
	_offset_tween = create_tween().set_parallel(true)
	_offset_tween.tween_property(self, "position", target_position, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_offset_tween.tween_property(self, "scale", target_scale, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)


## 过渡完成后把新贴图设为底层正式贴图，并隐藏上层。
## [param next_texture] 已经完成淡入的目标贴图。
func _finish_transition(next_texture: Texture2D) -> void:
	texture = next_texture
	_current_texture = next_texture
	_overlay.visible = false
	_overlay.modulate = Color(1, 1, 1, 0)
	_switching = false
