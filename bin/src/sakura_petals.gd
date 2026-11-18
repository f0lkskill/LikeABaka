extends GPUParticles3D

## 舞台与外围遮罩圆柱之间的樱花飘落粒子。
##
## 花瓣由程序化 shader 绘制，不依赖贴图；粒子沿环形区域生成后缓慢下落。
## 外部通过 set_enabled / set_density 控制开关与密度，开关带透明度渐变。

@export_group("Particles")
## 最大粒子数量。
@export_range(20, 2000, 10) var max_particles: int = 620
## 花瓣初始密度，0 到 1。
@export_range(0.0, 1.0, 0.01) var initial_density: float = 0.72
## 花瓣生命周期。
@export_range(2.0, 60.0, 0.5) var particle_lifetime: float = 18.0
## 发射区域横向半宽，覆盖整个背幕。
@export var spawn_half_width: float = 58.0
## 发射区域纵深半深。
@export var spawn_half_depth: float = 48.0
## 发射平面厚度。
@export_range(0.0, 20.0, 0.1) var spawn_thickness: float = 0.5
## 每秒固定粒子模拟帧率。
@export_range(10, 60, 1) var particle_fps: int = 30
## 粒子整体速度倍率，用于快速下落。
@export_range(0.1, 5.0, 0.1) var simulation_speed: float = 1.6

@export_group("Look")
## 花瓣深色。
@export var petal_color: Color = Color(1.0, 0.52, 0.68, 1.0)
## 花瓣浅色。
@export var petal_light_color: Color = Color(1.0, 0.86, 0.91, 1.0)
## 五瓣花使用的红色。
@export var flower_petal_color: Color = Color(0.86, 0.08, 0.16, 1.0)
## 五瓣花浅色。
@export var flower_petal_light_color: Color = Color(1.0, 0.45, 0.48, 1.0)
## 五瓣花生命周期。
@export_range(2.0, 60.0, 0.5) var flower_lifetime: float = 35.0
## 五瓣花整体速度倍率。
@export_range(0.1, 5.0, 0.1) var flower_simulation_speed: float = 2.2
## 五瓣花初始下落速度上限与下限。
@export var flower_initial_speed_min: float = 14.0
@export var flower_initial_speed_max: float = 22.0
## 五瓣花重力。
@export var flower_gravity: float = -7.0
## 五瓣花旋转速度，刻意比单瓣慢。
@export var flower_angular_speed: float = 45.0
## BadApple 剪影模式下花瓣变成的颜色。
@export var silhouette_color: Color = Color.BLACK
## 花瓣单边尺寸。
@export var petal_size: float = 1.35
## 花瓣形状：0 单瓣，1 五瓣花。
@export_range(0, 1, 1) var petal_style: int = 0:
	set(value):
		petal_style = clampi(value, 0, 1)
		_apply_style_profile()

## 粒子材质。
var _material: ShaderMaterial
## 内置花瓣 shader 列表。
var _style_shaders: Array[Shader] = []
## 开关渐变 Tween。
var _fade_tween: Tween
## 密度渐变 Tween。
var _density_tween: Tween
## 当前全局透明度。
var _fade: float = 0.0
## 是否处于开启状态。
var _enabled: bool = false
## 剪影颜色混合 Tween。
var _silhouette_tween: Tween
## 当前剪影颜色混合值。
var _silhouette_mix: float = 0.0


## 构建粒子系统和花瓣 shader。
func _ready() -> void:
	amount = max_particles
	fixed_fps = particle_fps
	emitting = false
	visibility_aabb = AABB(
		Vector3(-80.0, -160.0, -80.0),
		Vector3(160.0, 320.0, 160.0)
	)
	process_material = _create_process_material()
	_build_petal_shaders()
	draw_pass_1 = _create_petal_mesh()
	_apply_style_profile()
	amount_ratio = initial_density
	_set_fade(0.0)
	set_enabled(false, 0.0)


## 创建粒子发射与运动参数。
func _create_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(
		spawn_half_width,
		spawn_thickness,
		spawn_half_depth
	)
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 20.0
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 14.0
	material.gravity = Vector3(0.0, -4.2, 0.0)
	material.damping_min = 0.03
	material.damping_max = 0.12
	material.angular_velocity_min = -220.0
	material.angular_velocity_max = 220.0
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.particle_flag_rotate_y = true
	material.scale_min = 0.7
	material.scale_max = 1.6
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 1.5
	material.turbulence_noise_scale = 2.4
	return material


## 创建程序化花瓣的四边形网格与材质。
func _create_petal_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(petal_size, petal_size * 0.72)
	_material = ShaderMaterial.new()
	_apply_material_shader()
	_apply_material_parameters()
	mesh.material = _material
	return mesh


## 应用当前形状专属的运动与寿命参数。
## 单瓣保持柔和樱花参数，五瓣花使用独立的红色花朵参数。
func _apply_style_profile() -> void:
	var flower_style := petal_style == 1
	lifetime = flower_lifetime if flower_style else particle_lifetime
	speed_scale = flower_simulation_speed if flower_style else simulation_speed
	var process := process_material as ParticleProcessMaterial
	if process != null:
		if flower_style:
			process.initial_velocity_min = flower_initial_speed_min
			process.initial_velocity_max = flower_initial_speed_max
			process.gravity = Vector3(0.0, flower_gravity, 0.0)
			process.angular_velocity_min = -flower_angular_speed
			process.angular_velocity_max = flower_angular_speed
			process.particle_flag_rotate_y = false
		else:
			process.initial_velocity_min = 8.0
			process.initial_velocity_max = 14.0
			process.gravity = Vector3(0.0, -4.2, 0.0)
			process.angular_velocity_min = -220.0
			process.angular_velocity_max = 220.0
			process.particle_flag_rotate_y = true
	_apply_material_shader()


## 构建内置的单瓣与五瓣花 shader。
func _build_petal_shaders() -> void:
	_style_shaders.clear()
	_style_shaders.append(_create_single_petal_shader())
	_style_shaders.append(_create_flower_petal_shader())


## 单瓣花瓣 shader。
func _create_single_petal_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 petal_color : source_color = vec4(1.0, 0.52, 0.68, 1.0);
uniform vec4 petal_light_color : source_color = vec4(1.0, 0.86, 0.91, 1.0);
uniform vec4 silhouette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float silhouette_mix : hint_range(0.0, 1.0) = 0.0;
uniform float fade_alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(vec2(p.x * 1.25, p.y)) - 0.86;
	float notch = smoothstep(0.0, 0.25, -p.y) * smoothstep(0.0, 0.45, abs(p.x));
	d += notch * 0.14;
	float alpha = 1.0 - smoothstep(-0.06, 0.06, d);
	if (alpha < 0.02) {
		discard;
	}
	float gradient = smoothstep(-1.0, 1.0, p.y);
	vec3 color = mix(petal_color.rgb, petal_light_color.rgb, gradient * 0.65);
	color = mix(color, silhouette_color.rgb, silhouette_mix);
	ALBEDO = color;
	ALPHA = alpha * fade_alpha;
}
"""
	return shader


## 五瓣花朵 shader，使用极坐标生成类似樱花的轮廓。
func _create_flower_petal_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 petal_color : source_color = vec4(1.0, 0.52, 0.68, 1.0);
uniform vec4 petal_light_color : source_color = vec4(1.0, 0.86, 0.91, 1.0);
uniform vec4 silhouette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float silhouette_mix : hint_range(0.0, 1.0) = 0.0;
uniform float fade_alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// 四边形高度为宽度的 0.72 倍，横向补偿后花朵才是正圆。
	p.x *= 0.72;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float five_lobes = abs(cos(angle * 2.5));
	// 五个花瓣之间留出透明缝隙，并让中心保持空心。
	float angular_gap = smoothstep(0.10, 0.38, five_lobes);
	float outer_radius = 0.60 + 0.28 * five_lobes;
	float inner_radius = 0.14;
	float radial_mask = (
		1.0 - smoothstep(outer_radius - 0.035, outer_radius + 0.035, radius)
	) * smoothstep(inner_radius - 0.03, inner_radius + 0.03, radius);
	float alpha = radial_mask * angular_gap;
	if (alpha < 0.02) {
		discard;
	}
	float gradient = smoothstep(inner_radius, outer_radius, radius);
	vec3 color = mix(petal_color.rgb, petal_light_color.rgb, gradient * 0.75);
	color = mix(color, silhouette_color.rgb, silhouette_mix);
	ALBEDO = color;
	ALPHA = alpha * fade_alpha;
}
"""
	return shader


## 把当前形状对应的 shader 应用到共享材质，所有粒子会立即一起更新。
func _apply_material_shader() -> void:
	if _material == null or _style_shaders.is_empty():
		return
	_material.shader = _style_shaders[clampi(
		petal_style,
		0,
		_style_shaders.size() - 1
	)]
	_apply_material_parameters()


## 重新写入花瓣 shader 的统一参数。
func _apply_material_parameters() -> void:
	if _material == null:
		return
	var flower_style := petal_style == 1
	var dark_color := flower_petal_color if flower_style else petal_color
	var light_color := flower_petal_light_color if flower_style else petal_light_color
	_material.set_shader_parameter("petal_color", dark_color)
	_material.set_shader_parameter("petal_light_color", light_color)
	_material.set_shader_parameter("silhouette_color", silhouette_color)
	_material.set_shader_parameter("silhouette_mix", _silhouette_mix)
	_material.set_shader_parameter("fade_alpha", _fade)


## 一键切换内置花瓣形状。
## [param style_index] 0 为单瓣，1 为五瓣花。
func set_petal_style(style_index: int) -> void:
	petal_style = style_index


## 使用外部 shader 替换花瓣渲染；所有现存粒子会刷新。
## [param shader] 需要保持与内置 shader 相同的 uniform 名称。
func set_petal_shader(shader: Shader) -> void:
	if shader == null or _material == null:
		return
	_material.shader = shader
	_apply_material_parameters()


## 开启或关闭樱花，并渐变透明度。
## [param enabled] true 开启，false 关闭。
## [param duration] 渐变时长；小于等于 0 时立即切换。
func set_enabled(enabled: bool, duration: float = 1.0) -> void:
	_enabled = enabled
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	if enabled:
		emitting = true
		restart()
		if duration <= 0.0:
			_set_fade(1.0)
			return
		_fade_tween = create_tween()
		_fade_tween.tween_method(_set_fade, _fade, 1.0, duration) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
		return

	if duration <= 0.0:
		_set_fade(0.0)
		emitting = false
		return
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, _fade, 0.0, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_callback(_stop_emitting)


## 切换花瓣的 BadApple 剪影颜色。
## [param active] true 变成剪影色，false 恢复粉色。
## [param duration] 颜色渐变时长。
func set_silhouette_mode(active: bool, duration: float) -> void:
	var target := 1.0 if active else 0.0
	if _silhouette_tween != null and _silhouette_tween.is_valid():
		_silhouette_tween.kill()
	if duration <= 0.0:
		_set_silhouette_mix(target)
		return
	_silhouette_tween = create_tween()
	_silhouette_tween.tween_method(
		_set_silhouette_mix,
		_silhouette_mix,
		target,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 设置花瓣剪影混合值。
## [param value] 0 为粉色，1 为纯剪影色。
func _set_silhouette_mix(value: float) -> void:
	_silhouette_mix = clampf(value, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("silhouette_mix", _silhouette_mix)


## 设置花瓣密度。
## [param density] 0 到 1 的密度比例。
## [param duration] 渐变时长；小于等于 0 时立即应用。
func set_density(density: float, duration: float = 1.0) -> void:
	var target := clampf(density, 0.0, 1.0)
	if _density_tween != null and _density_tween.is_valid():
		_density_tween.kill()
	if duration <= 0.0:
		_set_density_value(target)
		return
	_density_tween = create_tween()
	_density_tween.tween_method(_set_density_value, amount_ratio, target, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)


## 设置 shader 透明度。
func _set_fade(value: float) -> void:
	_fade = clampf(value, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("fade_alpha", _fade)


## 设置粒子密度。
func _set_density_value(value: float) -> void:
	amount_ratio = clampf(value, 0.0, 1.0)


## 淡出完成后停止发射。
func _stop_emitting() -> void:
	emitting = false
