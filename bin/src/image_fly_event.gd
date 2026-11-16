extends Node3D

## 歌词触发的曲面飞入素材事件。
##
## 每次歌词切换时，从背景素材目录随机取一张图片，生成一个贴合圆柱曲率的
## 弧形面板。面板从摄像机上方或下方、随机水平位置和角度缓入到平视高度，
## 停留一段时间后继续沿相同方向飞出。卡片带有噪声撕裂描边。

@export_group("Images")
## 随机背景素材目录。
@export_dir var image_directory: String = "res://bin/asset/image/bg"
## 面板整体宽度，最终尺寸还会乘以 [member card_scale]。
@export var panel_width: float = 40.0
## 面板整体缩放倍率。
@export_range(0.1, 5.0, 0.01) var card_scale: float = 1.0

@export_group("Auto Trigger")
## 是否使用独立计时器自动触发；默认由歌词事件触发，避免一次歌词飞出两张。
@export var auto_trigger_enabled: bool = false
## 自动触发的最短间隔。
@export_range(0.5, 30.0, 0.1) var auto_trigger_min_interval: float = 3.0
## 自动触发的最长间隔。
@export_range(0.5, 30.0, 0.1) var auto_trigger_max_interval: float = 6.0

@export_group("Curved Panel")
## 弧形面板的圆柱半径；略小于背景圆柱，贴在内侧表面。
@export var panel_radius: float = 49.0
## 横向弧面分段数，越高越圆滑。
@export_range(4, 64, 1) var arc_segments: int = 24
## 纵向分段数。
@export_range(2, 32, 1) var height_segments: int = 10

@export_group("Motion")
## 从屏幕上方/下方开始移动的偏移量。
@export var spawn_offset: float = 30.0
## 飞出时额外增加的离场距离。
@export var exit_extra_offset: float = 40.0
## 缓入到摄像机平视位置的时间。
@export_range(0.05, 5.0, 0.05) var fly_in_duration: float = 1.1
## 在平视位置停留的时间。
@export_range(0.0, 8.0, 0.05) var hold_duration: float = 1.6
## 继续飞走的时间。
@export_range(0.05, 5.0, 0.05) var fly_out_duration: float = 1.1
## 在圆柱可见面上随机选择角度的范围，单位为度。
## 180 度表示覆盖面对摄像机的整个半圆。
@export_range(0.0, 180.0, 0.5) var visible_angle_spread_degrees: float = 180.0
## 贴合圆柱后再允许的轻微偏航倾斜。
@export_range(0.0, 20.0, 0.5) var yaw_tilt_degrees: float = 5.0
## 轻微俯仰倾斜。
@export_range(0.0, 20.0, 0.5) var pitch_tilt_degrees: float = 4.0
## 轻微滚转倾斜。
@export_range(0.0, 20.0, 0.5) var roll_tilt_degrees: float = 4.0
## 同时存在的最大面板数量；超出时移除最早的一张。
@export_range(1, 8, 1) var max_active_cards: int = 4

@export_group("Silhouette")
## 剪影事件中飞入素材变成的颜色。
@export var silhouette_color: Color = Color.BLACK

@export_group("Outline")
## 描边颜色。
@export var outline_color: Color = Color(0.025, 0.02, 0.03, 1.0)
## 描边宽度，使用 UV 距离。
@export_range(0.0, 0.08, 0.001) var outline_width: float = 0.014
## 边缘撕裂扭曲强度。
@export_range(0.0, 0.08, 0.001) var edge_distortion: float = 0.022
## 噪声频率，越大边缘越碎。
@export_range(1.0, 60.0, 0.5) var noise_scale: float = 20.0

## 已加载的背景素材。
var _textures: Array[Texture2D] = []
## 当前存活的弧形面板。
var _active_cards: Array[MeshInstance3D] = []
## 素材抽取袋，保证每张素材单独使用一次后再重新洗牌。
var _texture_bag: Array[int] = []
## 当前剪影目标，0 为原色，1 为纯剪影色。
var _silhouette_target: float = 0.0
## 自动触发的计时器。
var _auto_timer: Timer


## 载入素材目录并启动独立于歌词的自动触发。
func _ready() -> void:
	_load_images()
	if auto_trigger_enabled:
		_start_auto_trigger()


## 创建自动触发计时器。
func _start_auto_trigger() -> void:
	_auto_timer = Timer.new()
	_auto_timer.one_shot = true
	_auto_timer.timeout.connect(_on_auto_trigger_timeout)
	add_child(_auto_timer)
	_schedule_next_auto_trigger()


## 安排下一次自动触发，并保证最短/最长间隔合法。
func _schedule_next_auto_trigger() -> void:
	if _auto_timer == null:
		return
	var min_interval := minf(auto_trigger_min_interval, auto_trigger_max_interval)
	var max_interval := maxf(auto_trigger_min_interval, auto_trigger_max_interval)
	_auto_timer.wait_time = randf_range(min_interval, max_interval)
	_auto_timer.start()


## 自动触发一次素材飞入，然后继续安排下一次。
func _on_auto_trigger_timeout() -> void:
	if auto_trigger_enabled:
		trigger_event()
		_schedule_next_auto_trigger()


## 触发一次飞入事件，生成一张随机素材的独立弧形面板。
func trigger_event() -> void:
	if _textures.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	while _active_cards.size() >= max_active_cards:
		var expired: MeshInstance3D = _active_cards.pop_front()
		if is_instance_valid(expired):
			expired.queue_free()
	var texture := _pick_texture()
	if texture == null:
		return
	# 摄像机位置转换到圆弧本地坐标，用来选择可见的圆柱表面。
	var local_camera := to_local(camera.global_position)
	var target_y := local_camera.y
	var far_angle := atan2(-local_camera.x, -local_camera.z)
	var angle_offset := deg_to_rad(
		randf_range(
			-visible_angle_spread_degrees * 0.5,
			visible_angle_spread_degrees * 0.5
		)
	)
	var placement_angle := far_angle + angle_offset
	var direction := 1.0 if randf() < 0.5 else -1.0
	var start_y := target_y + direction * spawn_offset
	# 每张面板都有独立材质，便于各自设置贴图和描边参数。
	var card := MeshInstance3D.new()
	card.name = "FlyingCurvedCard"
	card.mesh = _create_curved_mesh()
	card.material_override = _create_outline_material(texture)
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	card.position = Vector3(0.0, start_y, 0.0)
	# 先贴合圆柱法线，再叠加很小的随机倾斜，避免和字幕穿模。
	card.rotation_degrees = Vector3(
		randf_range(-pitch_tilt_degrees, pitch_tilt_degrees),
		rad_to_deg(placement_angle - PI) \
			+ randf_range(-yaw_tilt_degrees, yaw_tilt_degrees),
		randf_range(-roll_tilt_degrees, roll_tilt_degrees)
	)
	add_child(card)
	_active_cards.append(card)
	_animate_card(card, start_y, target_y, direction)


## 切换飞入素材的剪影状态。
## [param active] 是否变成剪影颜色。
## [param duration] 颜色渐变时长；小于等于 0 时立即切换。
func set_silhouette_mode(active: bool, duration: float) -> void:
	_silhouette_target = 1.0 if active else 0.0
	for card in _active_cards:
		if not is_instance_valid(card):
			continue
		var material := card.material_override as ShaderMaterial
		if material == null:
			continue
		if duration <= 0.0:
			material.set_shader_parameter("silhouette_mix", _silhouette_target)
		else:
			var current := float(material.get_shader_parameter("silhouette_mix"))
			create_tween().tween_method(
				_set_material_silhouette_mix.bind(material),
				current,
				_silhouette_target,
				duration
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 设置单个卡片材质的剪影混合程度。
## [param value] 0 为原色，1 为纯剪影色。
## [param material] 目标卡片材质。
func _set_material_silhouette_mix(value: float, material: ShaderMaterial) -> void:
	if is_instance_valid(material):
		material.set_shader_parameter("silhouette_mix", value)


## 载入目录中的全部 png 背景素材。
func _load_images() -> void:
	_textures.clear()
	var directory := DirAccess.open(image_directory)
	if directory == null:
		push_warning("ImageFlyEvent: 无法打开素材目录: %s" % image_directory)
		return
	var files := directory.get_files()
	files.sort()
	for file in files:
		if file.get_extension().to_lower() != "png":
			continue
		var loaded := load(image_directory.path_join(file)) as Texture2D
		if loaded != null:
			_textures.append(loaded)
	_refill_texture_bag()


## 重新洗牌素材索引，保证每张素材独立出现。
func _refill_texture_bag() -> void:
	_texture_bag.clear()
	for i in _textures.size():
		_texture_bag.append(i)
	_texture_bag.shuffle()


## 从素材袋中取下一张素材。
func _pick_texture() -> Texture2D:
	if _textures.is_empty():
		return null
	if _texture_bag.is_empty():
		_refill_texture_bag()
	var index: int = _texture_bag.pop_back()
	return _textures[index]


## 创建贴合圆柱的弧形面板网格。
## 面板宽度为 [member panel_width] * [member card_scale]，高度按 2:1 比例。
func _create_curved_mesh() -> ArrayMesh:
	var width := panel_width * card_scale
	var height := width * 0.5
	var arc := 2.0 * asin(clampf(width / (2.0 * panel_radius), -1.0, 1.0))
	var columns := maxi(arc_segments, 2)
	var rows := maxi(height_segments, 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in rows + 1:
		var v := float(row) / float(rows)
		var y := (v - 0.5) * height
		for column in columns + 1:
			var u := float(column) / float(columns)
			var angle := (u - 0.5) * arc
			var x := panel_radius * sin(angle)
			var z := -panel_radius * cos(angle)
			vertices.append(Vector3(x, y, z))
			normals.append(Vector3(-sin(angle), 0.0, cos(angle)))
			uvs.append(Vector2(u, 1.0 - v))
	for row in rows:
		for column in columns:
			var i := row * (columns + 1) + column
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + columns + 1)
			indices.append(i + 1)
			indices.append(i + columns + 2)
			indices.append(i + columns + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 创建带噪声撕裂描边的卡片材质。
## [param texture] 卡片使用的背景贴图。
func _create_outline_material(texture: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D card_texture : source_color, filter_linear_mipmap;
uniform vec4 outline_color : source_color = vec4(0.025, 0.02, 0.03, 1.0);
uniform vec4 silhouette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float silhouette_mix = 0.0;
uniform float outline_width = 0.014;
uniform float edge_distortion = 0.022;
uniform float noise_scale = 20.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec4 tex = texture(card_texture, UV);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float rough = (value_noise(UV * noise_scale) - 0.5) * edge_distortion;
	float torn_edge = edge + rough;
	// 超出粗糙边缘的部分直接丢弃，形成撕裂轮廓。
	if (torn_edge < 0.0) {
		discard;
	}
	float outline = 1.0 - smoothstep(outline_width * 0.55, outline_width, torn_edge);
	vec3 card_color = mix(tex.rgb, silhouette_color.rgb, silhouette_mix);
	vec3 line_color = mix(outline_color.rgb, silhouette_color.rgb, silhouette_mix);
	ALBEDO = mix(card_color, line_color, outline);
	ALPHA = tex.a;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("card_texture", texture)
	material.set_shader_parameter("outline_color", outline_color)
	material.set_shader_parameter("silhouette_color", silhouette_color)
	material.set_shader_parameter("silhouette_mix", _silhouette_target)
	material.set_shader_parameter("outline_width", outline_width)
	material.set_shader_parameter("edge_distortion", edge_distortion)
	material.set_shader_parameter("noise_scale", noise_scale)
	return material


## 让面板从起始位置缓入、停留，再沿相同方向飞出。
## [param card] 正在运动的面板。
## [param start_y] 面板起始的本地 Y 坐标。
## [param target_y] 摄像机平视高度的本地 Y 坐标。
## [param direction] 1 表示从上方进入，-1 表示从下方进入。
func _animate_card(
	card: MeshInstance3D,
	start_y: float,
	target_y: float,
	direction: float
) -> void:
	var exit_y := target_y - direction * (spawn_offset + exit_extra_offset)
	var tween := create_tween()
	tween.tween_property(card, "position:y", target_y, fly_in_duration) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_duration)
	tween.tween_property(card, "position:y", exit_y, fly_out_duration) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN)
	tween.tween_callback(_remove_card.bind(card))


## 移除已经飞出的面板。
## [param card] 需要移除的面板。
func _remove_card(card: MeshInstance3D) -> void:
	_active_cards.erase(card)
	if is_instance_valid(card):
		card.queue_free()
