@tool
## 场景全局管理器。
##
## 挂载在场景根节点，统一提供场景级接口。
## 歌词环的具体实现由 [LyricRing] 模板负责，本脚本只负责绑定、
## 转发信号与提供稳定的全局调用入口。
class_name GlobalManager
extends Node3D

## 一条歌词开始显示时发出。
signal lyric_line_started(index: int, time: float, text: String)
## 一条歌词转到不可见半圈并被销毁时发出。
signal lyric_line_destroyed(index: int, text: String)
## 全部歌词播放完毕时发出。
signal lyrics_finished

## 歌词环模板节点路径。
@export var lyric_ring_path: NodePath = ^"LyricRing":
	set(value):
		lyric_ring_path = value
		_bind_lyric_ring()
## BGM 播放器路径；播放结束时自动退出进程。
@export var bgm_path: NodePath = ^"BGM":
	set(value):
		bgm_path = value
		_bind_bgm()
@export var event_path: NodePath = ^"Event":
	set(value):
		event_path = value
		_bind_event()
## 舞台根节点路径；旋转时摄像机会作为它的子节点同步移动。
@export var stage_path: NodePath = ^"stage":
	set(value):
		stage_path = value
		_bind_performance()
## 角色 Sprite3D 路径，用于切换角色立绘集合。
@export var character_path: NodePath = ^"charactor/C1":
	set(value):
		character_path = value
		_bind_performance()
## 摄像机支架路径；旋转舞台时会对该节点施加反向滞后旋转。
@export var camera_rig_path: NodePath = ^"stage/Node3D":
	set(value):
		camera_rig_path = value
		_bind_performance()
## 摄像机追随舞台旋转的速度；越小滞后越明显。
@export_range(0.5, 20.0, 0.1) var camera_follow_speed: float = 1.8
## 歌词只负责显示；旋转由 Event 节点或 AnimationPlayer 手动调用。
## 舞台旋转 180 度所需时间。
@export_range(0.1, 5.0, 0.05) var rotate_duration: float = 1.2
## 舞台律动条节点路径；角色切换时会同步主题色。
@export var rhythm_bars_path: NodePath = ^"stage/CollisionShape3D/StageRhythmBars":
	set(value):
		rhythm_bars_path = value
		_bind_performance()
## 舞台背景圆柱路径；角色切换时同步主题色与对半过渡。
@export var backdrop_path: NodePath = ^"stage/StageBackdrop":
	set(value):
		backdrop_path = value
		_bind_performance()
## 各角色对应的律动条与背景主题色，索引与 character_directories 对齐。
@export var character_theme_colors: PackedColorArray = PackedColorArray([
	Color(1.0, 0.4, 0.68, 1.0),
	Color(0.62, 0.04, 0.10, 1.0),
])
## 律动条主题色过渡时长。
@export_range(0.0, 2.0, 0.05) var theme_transition_duration: float = 0.45
## 背景圆柱对半分裂再合并的过渡时长。
@export_range(0.0, 3.0, 0.05) var backdrop_transition_duration: float = 0.9
## 是否启用剪影事件。
@export var silhouette_enabled: bool = true
## 是否按时间区间自动开关剪影；用 Event/动画手动控制时请关闭。
@export var auto_silhouette_events: bool = true
## 剪影时间区间，x 为开始秒数，y 为结束秒数。
@export var silhouette_ranges: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 10.0),
	Vector2(51.00, 71.04),
])
## 剪影中人物使用的颜色。
@export var silhouette_character_color: Color = Color.WHITE
## 剪影中舞台使用的颜色。
@export var silhouette_stage_color: Color = Color.BLACK
## 剪影中背景黑白块使用的颜色。
@export var silhouette_backdrop_color: Color = Color.BLACK
## 剪影中律动条使用的颜色。
@export var silhouette_bar_color: Color = Color.WHITE
## 进入和退出剪影时所有元素的渐变时长。
@export_range(0.0, 2.0, 0.05) var silhouette_transition_duration: float = 0.45
## 飞入素材事件节点路径。
@export var image_event_path: NodePath = ^"stage/ImageFlyEvent":
	set(value):
		image_event_path = value
		_bind_performance()
## 每隔多少句歌词触发一次背景素材飞入，1 表示每句都触发。
@export_range(1, 16, 1) var image_event_every_lines: int = 1

## 当前绑定的歌词环模板。
var _lyric_ring: LyricRing
## 当前绑定的 BGM 播放器。
var _bgm: AudioStreamPlayer
## Event 节点的动画播放器。
var _event: AnimationPlayer
## 当前舞台根节点。
var _stage: Node3D
## 当前角色节点。
var _character: Node
## 当前摄像机支架节点。
var _camera_rig: Node3D
## 当前律动条节点。
var _rhythm_bars: Node
## 当前背景圆柱节点。
var _backdrop: Node
## 当前已应用的主题索引。
var _active_theme_index: int = 0
## 律动条主题色过渡 Tween。
var _theme_tween: Tween
## 旋转开始前的舞台全局变换。
var _stage_start_transform: Transform3D
## 旋转开始前的摄像机支架全局变换。
var _camera_rig_start_transform: Transform3D
## 角色所在的旋转轴心，使用世界坐标的 X/Z。
var _rotation_pivot: Vector3
## 是否正在执行旋转，避免重叠旋转。
var _rotating: bool = false
## 摄像机当前追随角度。
var _camera_follow_angle: float = 0.0
## 摄像机追随目标角度。
var _camera_target_angle: float = 0.0
## 摄像机是否仍在追平舞台。
var _camera_following: bool = false
## 飞入素材事件节点；剪影事件会同步它的颜色状态。
var _image_event: Node
## 飞入素材事件的歌词计数。
var _image_event_line_count: int = 0
## 当前舞台地面网格。
var _stage_mesh: MeshInstance3D
## 角色残留上层节点。
var _character_overlay: Node
## 是否处于剪影事件中。
var _silhouette_active: bool = false
## 剪影材质是否已经覆盖到场景节点上。
var _silhouette_visuals_applied: bool = false
## 剪影混合程度，0 为正常，1 为纯剪影。
var _silhouette_mix: float = 0.0
## 剪影进入/退出 Tween。
var _silhouette_tween: Tween
## 舞台原本的颜色。
var _silhouette_stage_base_color: Color = Color.WHITE
## 剪影人物材质。
var _silhouette_character_material: ShaderMaterial
## 剪影角色残留上层材质。
var _silhouette_overlay_material: ShaderMaterial
## 剪影舞台材质。
var _silhouette_stage_material: StandardMaterial3D
## 剪影前的节点材质，用于退出时恢复。
var _character_material_backup: Material
var _overlay_material_backup: Material
var _stage_material_backup: Material


## 初始化并绑定歌词环模板。
func _ready() -> void:
	_bind_lyric_ring()
	_bind_bgm()
	_bind_performance()
	_bind_event()
	# 先启动 BGM，再让 Event 的 main 与 BGM 从同一时间开始。
	if _bgm != null and not _bgm.playing:
		_bgm.play()
	if _event != null and not _event.is_playing():
		_event.play("main")
		# 如果 BGM 已经提前开始，动画直接对齐 BGM 当前播放位置。
		if _bgm != null and _bgm.playing:
			_event.seek(_bgm.get_playback_position(), true)


## 从指定时间开始播放歌词。
## [param from_time] 起始秒数；小于 0 时使用模板的 start_time。
func play_lyrics(from_time: float = -1.0) -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.play(from_time)


## 暂停歌词播放。
func pause_lyrics() -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.pause()


## 停止歌词播放并清空当前歌词。
func stop_lyrics() -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.stop()


## 跳转到指定歌词时间。
## [param time] 目标秒数。
func seek_lyrics(time: float) -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.seek(time)


## 载入 LRC 歌词文件。
## [param path] 可选的新路径；留空时使用模板当前路径。
## 返回是否成功解析出歌词。
func load_lyrics(path: String = "") -> bool:
	_ensure_lyric_ring()
	if _lyric_ring == null:
		return false
	return _lyric_ring.load_lyrics(path)


## 直接传入歌词时间轴。
## [param entries] 每一项为包含 time 和 text 的字典。
func set_lyrics(entries: Array) -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.set_lyrics(entries)


## 让舞台旋转 180 度，并同步切换角色立绘集合。
## 摄像机作为舞台子节点会一起旋转，但会通过 [member camera_follow_speed]
## 延迟追随舞台角度，并在舞台停下后继续追平，角色立绘保持原位。
## 旋转使用 Inverted Check 曲线，结束后复位旋转状态。
func rotate_stage_and_switch_character(texture_file_name: String = "") -> void:
	_start_stage_rotation(true, texture_file_name)


## 只旋转舞台和摄像机，不切换角色；供 Event 节点或 AnimationPlayer 编排。
func rotate_stage() -> void:
	_start_stage_rotation(false)


## 手动切换角色集合；不自动关联歌词。
## [param texture_file_name] 可选目标贴图文件名，例如 "sad.png"。
func switch_character_set(texture_file_name: String = "") -> void:
	_bind_performance()
	if _character != null and _character.has_method("switch_character_set"):
		_character.call("switch_character_set", texture_file_name)


## 在当前角色集合内切换到指定贴图文件名。
## [param texture_file_name] 文件名，例如 "sad.png"。
func set_character_texture(texture_file_name: String) -> void:
	_bind_performance()
	if _character != null and _character.has_method("set_character_texture"):
		_character.call("set_character_texture", texture_file_name)


## 手动触发当前角色的一次随机立绘切换。
func switch_random_texture() -> void:
	_bind_performance()
	if _character != null and _character.has_method("switch_random_texture"):
		_character.call("switch_random_texture")


## 手动设置 BadApple 剪影状态；供 Event/AnimationPlayer 调用。
## [param active] true 进入剪影，false 退出剪影。
func set_silhouette_effect(active: bool) -> void:
	_set_silhouette(active)


## 手动触发一次背景素材飞入；自动触发仍由 ImageFlyEvent 自己管理。
func trigger_image_fly() -> void:
	if _image_event != null and _image_event.has_method("trigger_event"):
		_image_event.call("trigger_event")


## 启动舞台旋转。
## [param switch_character] 是否在旋转开始时切换角色集合。
## [param texture_file_name] 可选的新角色贴图文件名。
func _start_stage_rotation(
	switch_character: bool,
	texture_file_name: String = ""
) -> void:
	if Engine.is_editor_hint() or _rotating:
		return
	_bind_performance()
	if _stage == null:
		return
	_rotating = true
	if switch_character \
			and _character != null \
			and _character.has_method("switch_character_set"):
		_character.call("switch_character_set", texture_file_name)
	_stage_start_transform = _stage.global_transform
	_camera_rig_start_transform = (
		_camera_rig.global_transform if _camera_rig != null else Transform3D()
	)
	_rotation_pivot = _get_rotation_pivot()
	_camera_follow_angle = 0.0
	_camera_target_angle = 0.0
	_camera_following = true
	var tween := create_tween()
	tween.tween_method(
		_set_stage_rotation.bind(PI),
		0.0,
		1.0,
		rotate_duration
	)
	tween.finished.connect(_on_stage_rotation_finished)


## 当前歌词时间轴时钟，单位为秒。
func get_lyric_time() -> float:
	_ensure_lyric_ring()
	return _lyric_ring.get_playback_time() if _lyric_ring != null else 0.0


## 是否正在播放歌词。
func is_lyrics_playing() -> bool:
	_ensure_lyric_ring()
	return _lyric_ring.is_playing() if _lyric_ring != null else false


## 当前最新活动歌词文本。
func get_lyric_text() -> String:
	_ensure_lyric_ring()
	return _lyric_ring.get_current_text() if _lyric_ring != null else ""


## 解析并绑定歌词环模板，同时转发其信号。
func _bind_lyric_ring() -> void:
	if not is_node_ready():
		return
	if _lyric_ring != null:
		if _lyric_ring.line_spawned.is_connected(_on_line_spawned):
			_lyric_ring.line_spawned.disconnect(_on_line_spawned)
		if _lyric_ring.line_destroyed.is_connected(_on_line_destroyed):
			_lyric_ring.line_destroyed.disconnect(_on_line_destroyed)
		if _lyric_ring.playback_finished.is_connected(_on_playback_finished):
			_lyric_ring.playback_finished.disconnect(_on_playback_finished)
	_lyric_ring = get_node_or_null(lyric_ring_path) as LyricRing
	if _lyric_ring == null:
		push_warning("GlobalManager: 找不到歌词环模板节点: %s" % lyric_ring_path)
		return
	if not _lyric_ring.line_spawned.is_connected(_on_line_spawned):
		_lyric_ring.line_spawned.connect(_on_line_spawned)
	if not _lyric_ring.line_destroyed.is_connected(_on_line_destroyed):
		_lyric_ring.line_destroyed.connect(_on_line_destroyed)
	if not _lyric_ring.playback_finished.is_connected(_on_playback_finished):
		_lyric_ring.playback_finished.connect(_on_playback_finished)


## 绑定舞台和角色节点。
func _bind_performance() -> void:
	if not is_node_ready():
		return
	_stage = get_node_or_null(stage_path) as Node3D
	_character = get_node_or_null(character_path)
	_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	_rhythm_bars = get_node_or_null(rhythm_bars_path)
	_backdrop = get_node_or_null(backdrop_path)
	_image_event = get_node_or_null(image_event_path)
	_stage_mesh = (
		_stage.get_node_or_null("CollisionShape3D/MeshInstance3D") as MeshInstance3D
		if _stage != null
		else null
	)
	_character_overlay = (
		_character.get_node_or_null("C1ResidualOverlay")
		if _character != null
		else null
	)
	if _character != null and _character.has_signal("character_set_changed"):
		if not _character.is_connected("character_set_changed", _on_character_set_changed):
			_character.connect("character_set_changed", _on_character_set_changed)
		if not Engine.is_editor_hint() and _character.has_method("get_character_index"):
			_apply_character_theme(_character.get_character_index(), 0.0)


## 设置当前舞台的旋转角度，供 Tween 逐帧调用。
## 舞台和摄像机都围绕角色所在的 X/Z 轴心旋转，保证角色占位不变。
## [param progress] 线性进度，范围 0 到 1。
## [param total_angle] 本次旋转总角度，单位为弧度。
func _set_stage_rotation(progress: float, total_angle: float) -> void:
	if _stage == null:
		return
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var angle := total_angle * eased
	_stage.global_transform = _rotate_transform_around(
		_stage_start_transform,
		angle,
		_rotation_pivot
	)
	_camera_target_angle = angle
	if _camera_rig != null and _camera_following:
		_camera_rig.global_transform = _rotate_transform_around(
			_camera_rig_start_transform,
			_camera_follow_angle,
			_rotation_pivot
		)


## 每帧让摄像机延迟追随舞台角度；舞台停止后仍会继续追平。
## [param delta] 本帧时间，用于计算平滑权重。
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_silhouette_event()
	if _silhouette_visuals_applied:
		_sync_silhouette_textures()
	if not _camera_following or _camera_rig == null:
		return
	var weight := 1.0 - exp(-camera_follow_speed * delta)
	_camera_follow_angle = lerpf(_camera_follow_angle, _camera_target_angle, weight)
	_camera_rig.global_transform = _rotate_transform_around(
		_camera_rig_start_transform,
		_camera_follow_angle,
		_rotation_pivot
	)
	if not _rotating and absf(_camera_follow_angle - _camera_target_angle) < 0.003:
		_camera_follow_angle = _camera_target_angle
		_camera_rig.global_transform = _rotate_transform_around(
			_camera_rig_start_transform,
			_camera_follow_angle,
			_rotation_pivot
		)
		_camera_following = false


## 根据播放时间切换黑白剪影事件。
func _update_silhouette_event() -> void:
	if not auto_silhouette_events:
		return
	if not silhouette_enabled:
		if _silhouette_active:
			_set_silhouette(false)
		return
	var time := _get_performance_time()
	var active := false
	for time_range in silhouette_ranges:
		if time >= time_range.x and time < time_range.y:
			active = true
			break
	if active != _silhouette_active:
		_set_silhouette(active)


## 返回当前表演时间，优先使用歌词环内部的稳定时钟。
func _get_performance_time() -> float:
	if _lyric_ring != null:
		return _lyric_ring.get_playback_time()
	if _bgm != null:
		return _bgm.get_playback_position()
	return 0.0


## 设置或退出剪影事件，所有元素都使用渐变过渡。
## [param active] 是否启用剪影。
func _set_silhouette(active: bool) -> void:
	if active == _silhouette_active:
		return
	_silhouette_active = active
	if active:
		_enter_silhouette()
	else:
		_exit_silhouette()


## 进入剪影：先应用材质，再把人物、舞台、背景和律动条渐变到黑白。
func _enter_silhouette() -> void:
	_ensure_silhouette_visuals()
	_tween_silhouette_mix(1.0, _silhouette_stage_base_color, silhouette_stage_color)
	_fade_bars_to(silhouette_bar_color, silhouette_transition_duration)
	if _backdrop != null and _backdrop.has_method("fade_theme"):
		_backdrop.call(
			"fade_theme",
			silhouette_backdrop_color,
			silhouette_transition_duration
		)
	if _backdrop != null and _backdrop.has_method("set_checker_mode"):
		_backdrop.call("set_checker_mode", true, silhouette_transition_duration)
	# 飞入素材也进入剪影色，使用自己的材质做渐变。
	if _image_event != null and _image_event.has_method("set_silhouette_mode"):
		_image_event.call(
			"set_silhouette_mode",
			true,
			silhouette_transition_duration
		)


## 退出剪影：所有颜色渐变回角色主题色，结束后撤销材质覆盖。
func _exit_silhouette() -> void:
	if not _silhouette_visuals_applied:
		_apply_character_theme(_active_theme_index, 0.0)
		return
	var theme_color := silhouette_backdrop_color
	if not character_theme_colors.is_empty():
		theme_color = character_theme_colors[
			_active_theme_index % character_theme_colors.size()
		]
	_tween_silhouette_mix(0.0, silhouette_stage_color, _silhouette_stage_base_color)
	_fade_bars_to(theme_color, silhouette_transition_duration)
	if _backdrop != null and _backdrop.has_method("fade_theme"):
		_backdrop.call("fade_theme", theme_color, silhouette_transition_duration)
	if _backdrop != null and _backdrop.has_method("set_checker_mode"):
		_backdrop.call("set_checker_mode", false, silhouette_transition_duration)
	# 飞入素材随剪影一起渐变回原色。
	if _image_event != null and _image_event.has_method("set_silhouette_mode"):
		_image_event.call(
			"set_silhouette_mode",
			false,
			silhouette_transition_duration
		)
	if silhouette_transition_duration <= 0.0:
		_finish_exit_silhouette()
	elif _silhouette_tween != null and _silhouette_tween.is_valid():
		_silhouette_tween.chain().tween_callback(_finish_exit_silhouette)


## 应用材质覆盖并记录原始材质。
func _ensure_silhouette_visuals() -> void:
	# 飞入素材由自己的材质单独渐变到剪影色，这里只处理人物和舞台。
	if _silhouette_visuals_applied:
		return
	if _silhouette_character_material == null:
		_build_silhouette_materials()
	if _character is GeometryInstance3D:
		var character_node := _character as GeometryInstance3D
		_character_material_backup = character_node.material_override
		character_node.material_override = _silhouette_character_material
	if _character_overlay is GeometryInstance3D:
		var overlay_node := _character_overlay as GeometryInstance3D
		_overlay_material_backup = overlay_node.material_override
		overlay_node.material_override = _silhouette_overlay_material
	if _stage_mesh != null:
		_stage_material_backup = _stage_mesh.material_override
		var base_material := _stage_mesh.get_active_material(0) as StandardMaterial3D
		if base_material != null:
			_silhouette_stage_base_color = base_material.albedo_color
		_stage_mesh.material_override = _silhouette_stage_material
		_silhouette_stage_material.albedo_color = _silhouette_stage_base_color
	_silhouette_mix = 0.0
	_set_silhouette_mix(0.0)
	_silhouette_visuals_applied = true
	_sync_silhouette_textures()


## 渐入/渐出人物与舞台剪影强度。
func _tween_silhouette_mix(target: float, stage_from: Color, stage_to: Color) -> void:
	if _silhouette_tween != null and _silhouette_tween.is_valid():
		_silhouette_tween.kill()
	if silhouette_transition_duration <= 0.0:
		_set_silhouette_mix(target)
		_silhouette_stage_material.albedo_color = stage_to
		return
	_silhouette_stage_material.albedo_color = stage_from
	_silhouette_tween = create_tween().set_parallel(true)
	_silhouette_tween.tween_method(
		_set_silhouette_mix,
		_silhouette_mix,
		target,
		silhouette_transition_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_silhouette_tween.tween_property(
		_silhouette_stage_material,
		"albedo_color",
		stage_to,
		silhouette_transition_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 设置人物剪影的混合程度。
func _set_silhouette_mix(value: float) -> void:
	_silhouette_mix = value
	if _silhouette_character_material != null:
		_silhouette_character_material.set_shader_parameter(
			"silhouette_mix",
			value
		)
	if _silhouette_overlay_material != null:
		_silhouette_overlay_material.set_shader_parameter(
			"silhouette_mix",
			value
		)


## 同步基础立绘和残留上层使用的贴图，以及角色切换时的透明度。
func _sync_silhouette_textures() -> void:
	if _character is Sprite3D and _silhouette_character_material != null:
		var character_sprite := _character as Sprite3D
		_silhouette_character_material.set_shader_parameter(
			"silhouette_texture",
			character_sprite.texture
		)
		_silhouette_character_material.set_shader_parameter(
			"character_fade",
			character_sprite.modulate.a
		)
	if _character_overlay is Sprite3D and _silhouette_overlay_material != null:
		var overlay_sprite := _character_overlay as Sprite3D
		_silhouette_overlay_material.set_shader_parameter(
			"silhouette_texture",
			overlay_sprite.texture
		)
		_silhouette_overlay_material.set_shader_parameter(
			"character_fade",
			overlay_sprite.modulate.a
		)


## 退出渐变结束后撤销剪影材质并恢复主题。
func _finish_exit_silhouette() -> void:
	if _character is GeometryInstance3D:
		(_character as GeometryInstance3D).material_override = _character_material_backup
	if _character_overlay is GeometryInstance3D:
		(_character_overlay as GeometryInstance3D).material_override = (
			_overlay_material_backup
		)
	if _stage_mesh != null:
		_stage_mesh.material_override = _stage_material_backup
	_silhouette_mix = 0.0
	_silhouette_visuals_applied = false
	_apply_character_theme(_active_theme_index, 0.0)


## 渐变律动条颜色。
func _fade_bars_to(color: Color, duration: float) -> void:
	if _rhythm_bars == null:
		return
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	if duration <= 0.0:
		_rhythm_bars.set("bar_color", color)
		return
	_theme_tween = create_tween()
	_theme_tween.tween_property(_rhythm_bars, "bar_color", color, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)


## 只刷新剪影状态下的律动条与背景颜色。
func _apply_silhouette_colors() -> void:
	_fade_bars_to(silhouette_bar_color, 0.0)
	if _backdrop != null and _backdrop.has_method("fade_theme"):
		_backdrop.call("fade_theme", silhouette_backdrop_color, 0.0)


## 创建剪影人物与舞台材质。
func _build_silhouette_materials() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform sampler2D silhouette_texture : source_color, filter_linear;
uniform vec4 silhouette_color : source_color = vec4(1.0);
uniform float silhouette_mix : hint_range(0.0, 1.0) = 1.0;
uniform float character_fade : hint_range(0.0, 1.0) = 1.0;

// 自定义材质会绕过 Sprite3D 的 billboard，因此在剪影里手动朝向摄像机。
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 camera_world = INV_VIEW_MATRIX[3].xyz;
	vec3 forward = normalize(vec3(
		camera_world.x - origin.x,
		0.0,
		camera_world.z - origin.z
	));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
	vec3 up = normalize(cross(forward, right));
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right * scale.x, 0.0),
		vec4(up * scale.y, 0.0),
		vec4(forward * scale.z, 0.0),
		vec4(origin, 1.0)
	);
}

void fragment() {
	vec4 tex = texture(silhouette_texture, UV);
	ALBEDO = mix(tex.rgb, silhouette_color.rgb, silhouette_mix);
	ALPHA = tex.a * mix(1.0, silhouette_color.a, silhouette_mix) * character_fade;
}
"""
	_silhouette_character_material = ShaderMaterial.new()
	_silhouette_character_material.shader = shader
	_silhouette_character_material.set_shader_parameter(
		"silhouette_color",
		silhouette_character_color
	)
	_silhouette_overlay_material = ShaderMaterial.new()
	_silhouette_overlay_material.shader = shader
	_silhouette_overlay_material.set_shader_parameter(
		"silhouette_color",
		silhouette_character_color
	)
	_silhouette_stage_material = StandardMaterial3D.new()
	_silhouette_stage_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_silhouette_stage_material.albedo_color = silhouette_stage_color


## 角色集合变化时，平滑更新律动条主题色。
## [param index] 当前角色集合索引。
func _on_character_set_changed(index: int) -> void:
	_apply_character_theme(index, theme_transition_duration)


## 将指定角色索引对应的主题色应用到律动条。
## [param index] 当前角色集合索引。
## [param duration] 颜色过渡时长；小于等于 0 时立即应用。
func _apply_character_theme(index: int, duration: float) -> void:
	if Engine.is_editor_hint():
		return
	if character_theme_colors.is_empty():
		_active_theme_index = index
		return
	if _silhouette_visuals_applied:
		_active_theme_index = index
		if _silhouette_active:
			_apply_silhouette_colors()
		return
	var color := character_theme_colors[index % character_theme_colors.size()]
	var old_color := character_theme_colors[
		_active_theme_index % character_theme_colors.size()
	]
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	if _rhythm_bars != null:
		if duration <= 0.0:
			_rhythm_bars.set("bar_color", color)
		else:
			_theme_tween = create_tween()
			_theme_tween.tween_property(_rhythm_bars, "bar_color", color, duration) \
				.set_trans(Tween.TRANS_SINE) \
				.set_ease(Tween.EASE_IN_OUT)
	if _backdrop != null and _backdrop.has_method("transition_theme"):
		if duration <= 0.0:
			_backdrop.call("set_theme", color)
		else:
			_backdrop.call(
				"transition_theme",
				old_color,
				color,
				backdrop_transition_duration
			)
	_active_theme_index = index


## 返回角色当前世界坐标的 X/Z，作为舞台和摄像机的共同旋转轴心。
func _get_rotation_pivot() -> Vector3:
	var anchor := _character.get_parent() if _character != null else null
	if anchor is Node3D:
		var anchor_position := (anchor as Node3D).global_position
		var pivot_y := _stage.global_position.y if _stage != null else 0.0
		return Vector3(anchor_position.x, pivot_y, anchor_position.z)
	if _stage != null:
		return _stage.global_position
	return Vector3.ZERO


## 将变换围绕指定轴心绕 Y 轴旋转。
## [param source] 旋转前的世界变换。
## [param angle] 旋转角度，单位为弧度。
## [param pivot] 旋转轴心，使用世界坐标。
func _rotate_transform_around(source: Transform3D, angle: float, pivot: Vector3) -> Transform3D:
	var rotation := Basis(Vector3.UP, angle)
	return Transform3D(
		rotation * source.basis,
		pivot + rotation * (source.origin - pivot)
	)


## 旋转完成时清除旋转锁。
func _on_stage_rotation_finished() -> void:
	_rotating = false


## 绑定 BGM，并在播放结束后退出进程。
func _bind_bgm() -> void:
	if Engine.is_editor_hint() or not is_node_ready():
		return
	if _bgm != null and _bgm.finished.is_connected(_on_bgm_finished):
		_bgm.finished.disconnect(_on_bgm_finished)
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	if _bgm == null:
		push_warning("GlobalManager: 找不到 BGM 节点: %s" % bgm_path)
		return
	if not _bgm.finished.is_connected(_on_bgm_finished):
		_bgm.finished.connect(_on_bgm_finished)

## 绑定 Event 节点的 AnimationPlayer。
func _bind_event() -> void:
	if Engine.is_editor_hint() or not is_node_ready():
		return
	_event = get_node_or_null(event_path) as AnimationPlayer
	if _event == null:
		push_warning("GlobalManager: 找不到 Event 节点: %s" % event_path)

## 确保歌词环已绑定。
func _ensure_lyric_ring() -> void:
	if _lyric_ring == null:
		_bind_lyric_ring()


## BGM 播放结束，退出进程。
func _on_bgm_finished() -> void:
	get_tree().quit()


## 转发歌词开始信号，只保留背景素材飞入这一项自动事件。
## 舞台旋转、角色切换和立绘随机变化仍由 Event 节点或 AnimationPlayer 编排。
func _on_line_spawned(index: int, time: float, text: String) -> void:
	lyric_line_started.emit(index, time, text)
	_image_event_line_count += 1
	if image_event_every_lines > 0:
		if _image_event_line_count % image_event_every_lines == 0:
			trigger_image_fly()


## 转发歌词销毁信号。
func _on_line_destroyed(index: int, text: String) -> void:
	lyric_line_destroyed.emit(index, text)


## 转发播放完成信号。
func _on_playback_finished() -> void:
	lyrics_finished.emit()
