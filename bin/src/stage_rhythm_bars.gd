extends Node3D

## 沿圆台舞台边缘生成一组分隔的 2D 竖条律动条。
##
## 竖条围绕一整圈舞台边缘排布，正面中心朝向摄像机，条面朝向圆心。
## 高度由 BGM 频谱排名驱动：峰值条更高，普通条更低。
## 颜色、数量、宽度、间隔和响应速度都可以通过导出属性调整。

## 用于频谱分析的音频总线名称；与摄像机共用同一条总线。
const ANALYZER_BUS := "BGM_Analyzer"

@export_group("Layout")
## 舞台圆柱网格路径。
@export var stage_mesh_path: NodePath = ^"../stage/CollisionShape3D/MeshInstance3D"
## BGM 播放器路径。
@export var bgm_path: NodePath = ^"../BGM"
## 正中心角度；0 度朝向摄像机。
@export var center_angle_deg: float = 0.0
## 展开角度；360 度表示绕舞台一整圈。
@export_range(1.0, 360.0, 1.0) var arc_degrees: float = 360.0
## 竖条数量。
@export_range(1, 128, 1) var bar_count: int = 64
## 单根竖条宽度。
@export var bar_width: float = 1.3
## 相对舞台半径的外扩距离。
@export var radius_offset: float = 0.25
## 竖条底部相对舞台顶面的高度。
@export var base_height_offset: float = 0.4
## 最短高度。
@export var min_height: float = 2.0
## 最长高度。
@export var max_height: float = 10.0

@export_group("Appearance")
## 竖条颜色。
@export var bar_color: Color = Color(1.0, 0.4, 0.68, 1.0):
	set(value):
		bar_color = value
		_apply_color()
## 竖条顶部的透明度；用于形成向上透明的渐变。
@export_range(0.0, 1.0, 0.01) var top_alpha: float = 0.05:
	set(value):
		top_alpha = value
		_apply_color()

@export_group("Reaction")
## 峰值锐度；越大越只有少数峰值条接近最高高度。
@export_range(1.0, 5.0, 0.1) var peak_sharpness: float = 2.8
## 频谱最大值的活跃度倍率。
@export var activity_gain: float = 40.0
## 总线峰值对整体高度的提升权重。
@export_range(0.0, 1.0, 0.05) var peak_weight: float = 0.4
## 高度响应速度。
@export_range(0.5, 30.0, 0.1) var response_speed: float = 10.0
## 频谱最低频率。
@export var min_frequency: float = 60.0
## 频谱最高频率。
@export var max_frequency: float = 8000.0

var _bars: Array[MeshInstance3D] = []
var _heights: PackedFloat32Array = []
var _base_positions: Array[Vector3] = []
var _angles: PackedFloat32Array = []
var _material: ShaderMaterial
var _stage_mesh: MeshInstance3D
var _up_axis := Vector3.UP
var _bgm: AudioStreamPlayer
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _bus_index: int = -1


## 初始化舞台尺寸、音频分析总线和全部竖条节点。
func _ready() -> void:
	_resolve_stage()
	_setup_analyzer_bus()
	_build_bars()


## 每帧采样 BGM 频谱，按排名计算每根竖条的目标高度并平滑过渡。
## [param delta] 距上一帧的时间，单位为秒。
func _process(delta: float) -> void:
	if _bars.is_empty():
		return
	var peak := 0.0
	if _bus_index >= 0:
		peak = clampf(
			db_to_linear(AudioServer.get_bus_peak_volume_left_db(_bus_index, 0)),
			0.0,
			1.0
		)
	var center_index := float(bar_count - 1) * 0.5
	var energies := PackedFloat32Array()
	energies.resize(_bars.size())
	var max_energy := 0.000001
	for i in _bars.size():
		var energy := 0.0
		if _analyzer != null:
			var distance := 0.0
			if center_index > 0.0:
				distance = absf(float(i) - center_index) / center_index
			var ratio := max_frequency / maxf(min_frequency, 1.0)
			var center_frequency := min_frequency * pow(ratio, distance)
			var magnitude := _analyzer.get_magnitude_for_frequency_range(
				center_frequency / 1.25,
				center_frequency * 1.25
			)
			energy = maxf(magnitude.x, magnitude.y)
		energies[i] = energy
		max_energy = maxf(max_energy, energy)
	var count := energies.size()
	var order: Array[int] = []
	for i in count:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return energies[a] < energies[b])
	var ranks := PackedFloat32Array()
	ranks.resize(count)
	for rank in count:
		ranks[order[rank]] = float(rank) / float(maxi(count - 1, 1))
	var activity := clampf(max_energy * activity_gain + peak * peak_weight, 0.0, 1.0)
	for i in _bars.size():
		var level := 0.0
		if _analyzer != null:
			level = pow(ranks[i], peak_sharpness) * activity
		else:
			level = peak * 0.5
		var height := lerpf(min_height, max_height, clampf(level, 0.0, 1.0))
		_heights[i] = lerpf(
			_heights[i],
			height,
			clampf(delta * response_speed, 0.0, 1.0)
		)
		var bar := _bars[i]
		bar.scale = Vector3(1.0, _heights[i], 1.0)
		bar.position = _base_positions[i] + _up_axis * (_heights[i] * 0.5)


## 从圆台网格读取半径、高度和朝向，并计算每根竖条的底部位置。
func _resolve_stage() -> void:
	_stage_mesh = get_node_or_null(stage_mesh_path) as MeshInstance3D
	if _stage_mesh == null or not (_stage_mesh.mesh is CylinderMesh):
		push_warning("StageRhythmBars: 找不到圆台网格: %s" % stage_mesh_path)
		return
	var cylinder := _stage_mesh.mesh as CylinderMesh
	var transform := _stage_mesh.global_transform
	_up_axis = transform.basis.y.normalized()
	var x_axis := transform.basis.x.normalized()
	var z_axis := transform.basis.z.normalized()
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius) + radius_offset
	var top := transform * Vector3(0.0, cylinder.height * 0.5, 0.0)
	var closed_ring := arc_degrees >= 359.9
	for i in bar_count:
		var t := 0.0
		if bar_count > 1:
			t = float(i) / float(bar_count if closed_ring else bar_count - 1)
		var angle := deg_to_rad(center_angle_deg - arc_degrees * 0.5 + arc_degrees * t)
		var base_position := top \
			+ x_axis * (radius * sin(angle)) \
			+ z_axis * (radius * cos(angle)) \
			+ _up_axis * base_height_offset
		_base_positions.append(base_position)
		_angles.append(angle)


## 为每根计算好的底部位置创建独立的 QuadMesh 竖条。
## 竖条绕 Y 轴旋转到面向圆心，并共用同一份颜色材质。
func _build_bars() -> void:
	if _stage_mesh == null:
		return
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform vec4 bar_color : source_color = vec4(1.0);
uniform float top_alpha : hint_range(0.0, 1.0) = 0.05;

void fragment() {
	float fade = mix(top_alpha, 1.0, smoothstep(0.0, 1.0, UV.y));
	float edge = smoothstep(0.38, 0.5, abs(UV.x - 0.5));
	vec3 core = mix(bar_color.rgb, vec3(1.0), 0.2);
	ALBEDO = mix(core, vec3(0.015), edge);
	EMISSION = mix(bar_color.rgb * 2.2, vec3(0.0), edge);
	ALPHA = bar_color.a * fade;
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	# 律动条先于歌词绘制，避免透明排序把条盖在文字上。
	_material.render_priority = -1
	_apply_color()
	for i in _base_positions.size():
		var quad := QuadMesh.new()
		quad.size = Vector2(bar_width, 1.0)
		var bar := MeshInstance3D.new()
		bar.name = "RhythmBar_%02d" % i
		bar.mesh = quad
		bar.material_override = _material
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		bar.position = _base_positions[i] + _up_axis * (min_height * 0.5)
		bar.rotation.y = _angles[i] + PI
		bar.scale = Vector3(1.0, min_height, 1.0)
		add_child(bar)
		_bars.append(bar)
		_heights.append(min_height)


## 把当前 [member bar_color] 同步到共享材质和自发光颜色。
func _apply_color() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("bar_color", bar_color)
	_material.set_shader_parameter("top_alpha", top_alpha)


## 创建或复用 [constant ANALYZER_BUS]，并把 BGM 绑定到该总线。
func _setup_analyzer_bus() -> void:
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	var bus_index := AudioServer.get_bus_index(ANALYZER_BUS)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, ANALYZER_BUS)
		AudioServer.set_bus_send(bus_index, "Master")
	if AudioServer.get_bus_effect_count(bus_index) == 0:
		var analyzer_effect := AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(bus_index, analyzer_effect)
	_bus_index = bus_index
	_analyzer = AudioServer.get_bus_effect_instance(bus_index, 0) as AudioEffectSpectrumAnalyzerInstance
	if _bgm != null:
		_bgm.bus = ANALYZER_BUS
