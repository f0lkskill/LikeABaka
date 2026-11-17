extends GPUParticles3D

## 舞台与外围遮罩圆柱之间的樱花飘落粒子。
##
## 花瓣由程序化 shader 绘制，不依赖贴图；粒子沿环形区域生成后缓慢下落。
## 外部通过 set_enabled / set_density 控制开关与密度，开关带透明度渐变。

@export_group("Particles")
## 最大粒子数量。
@export_range(20, 2000, 10) var max_particles: int = 420
## 花瓣初始密度，0 到 1。
@export_range(0.0, 1.0, 0.01) var initial_density: float = 0.55
## 花瓣生命周期。
@export_range(2.0, 30.0, 0.5) var particle_lifetime: float = 11.0
## 发射环内半径，避免落到舞台中心。
@export var ring_inner_radius: float = 33.0
## 发射环外半径，保持在外围遮罩内。
@export var ring_outer_radius: float = 47.0
## 发射环垂直厚度。
@export_range(0.0, 20.0, 0.1) var ring_height: float = 6.0
## 每秒固定粒子模拟帧率。
@export_range(10, 60, 1) var particle_fps: int = 30

@export_group("Look")
## 花瓣深色。
@export var petal_color: Color = Color(1.0, 0.52, 0.68, 1.0)
## 花瓣浅色。
@export var petal_light_color: Color = Color(1.0, 0.86, 0.91, 1.0)
## 花瓣单边尺寸。
@export var petal_size: float = 0.9

## 粒子材质。
var _material: ShaderMaterial
## 开关渐变 Tween。
var _fade_tween: Tween
## 密度渐变 Tween。
var _density_tween: Tween
## 当前全局透明度。
var _fade: float = 0.0
## 是否处于开启状态。
var _enabled: bool = false


## 构建粒子系统和花瓣 shader。
func _ready() -> void:
	amount = max_particles
	lifetime = particle_lifetime
	fixed_fps = particle_fps
	emitting = false
	visibility_aabb = AABB(
		Vector3(-80.0, -80.0, -80.0),
		Vector3(160.0, 160.0, 160.0)
	)
	process_material = _create_process_material()
	draw_pass_1 = _create_petal_mesh()
	amount_ratio = initial_density
	_set_fade(0.0)
	set_enabled(false, 0.0)


## 创建粒子发射与运动参数。
func _create_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_axis = Vector3(0.0, 1.0, 0.0)
	material.emission_ring_radius = ring_outer_radius
	material.emission_ring_inner_radius = ring_inner_radius
	material.emission_ring_height = ring_height
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 24.0
	material.initial_velocity_min = 1.2
	material.initial_velocity_max = 3.8
	material.gravity = Vector3(0.0, -1.4, 0.0)
	material.angular_velocity_min = -110.0
	material.angular_velocity_max = 110.0
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.scale_min = 0.55
	material.scale_max = 1.25
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 0.7
	material.turbulence_noise_scale = 2.0
	return material


## 创建程序化花瓣的四边形网格与材质。
func _create_petal_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(petal_size, petal_size * 0.72)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 petal_color : source_color = vec4(1.0, 0.52, 0.68, 1.0);
uniform vec4 petal_light_color : source_color = vec4(1.0, 0.86, 0.91, 1.0);
uniform float fade_alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// 用椭圆和顶部凹口构成简单花瓣轮廓。
	float d = length(vec2(p.x * 1.25, p.y)) - 0.86;
	float notch = smoothstep(0.0, 0.25, -p.y) * smoothstep(0.0, 0.45, abs(p.x));
	d += notch * 0.14;
	float alpha = 1.0 - smoothstep(-0.06, 0.06, d);
	if (alpha < 0.02) {
		discard;
	}
	float gradient = smoothstep(-1.0, 1.0, p.y);
	vec3 color = mix(petal_color.rgb, petal_light_color.rgb, gradient * 0.65);
	ALBEDO = color;
	ALPHA = alpha * fade_alpha;
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("petal_color", petal_color)
	_material.set_shader_parameter("petal_light_color", petal_light_color)
	mesh.material = _material
	return mesh


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
