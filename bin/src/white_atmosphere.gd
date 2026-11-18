extends CanvasLayer

## 全屏白色氛围层。
##
## 画面边缘为白色，向屏幕中心逐渐透明；颜色会混合当前角色主题色。
## 强度跟随 Camera3D 的自动 FOV 变化，并支持开关渐变和 BadApple 白色模式。

@export var camera_path: NodePath = ^"stage/Node3D/Camera3D"
## 氛围强度系数，最终透明度会乘以它。
@export_range(0.0, 2.0, 0.01) var intensity_coefficient: float = 0.45
## 主题色混合到白色底色的比例。
@export_range(0.0, 1.0, 0.01) var theme_tint_strength: float = 0.28
## 是否跟随 FOV 自动变化强度。
@export var follow_fov: bool = true
## FOV 映射下限。
@export var fov_min: float = 30.0
## FOV 映射上限。
@export var fov_max: float = 100.0
## FOV 变化对强度的影响比例。
@export_range(0.0, 1.0, 0.01) var fov_influence: float = 0.6
## 渐变开始位置，0 为屏幕中心，1 为边缘。
@export_range(0.0, 1.0, 0.01) var edge_start: float = 0.35
## 渐变结束位置。
@export_range(0.0, 1.5, 0.01) var edge_end: float = 1.0
## 渐变曲线幂次，越大越集中到边缘。
@export_range(0.2, 5.0, 0.1) var gradient_power: float = 1.5

## 全屏色块。
var _rect: ColorRect
## 氛围材质。
var _material: ShaderMaterial
## 当前主题色。
var _theme_color: Color = Color.WHITE
## 是否处于 BadApple 白色模式。
var _badapple_mode: bool = false
## 开关渐变值。
var _enabled_fade: float = 0.0
## 开关渐变 Tween。
var _fade_tween: Tween
## 当前 FOV 强度因子。
var _fov_factor: float = 1.0
## 当前实际透明度。
var _opacity: float = 0.0


## 创建全屏色块和 shader。
func _ready() -> void:
	layer = 10
	_rect = ColorRect.new()
	_rect.name = "AtmosphereRect"
	_rect.color = Color.WHITE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = _create_shader()
	_rect.material = _material
	add_child(_rect)
	visible = false
	_refresh_tint()
	_apply_opacity()


## 设置角色主题色；BadApple 模式下仍保持白色。
## [param color] 当前角色主题色。
func set_theme_color(color: Color) -> void:
	_theme_color = color
	_refresh_tint()


## 设置氛围强度系数。
## [param value] 强度倍率。
func set_intensity(value: float) -> void:
	intensity_coefficient = maxf(value, 0.0)


## 开启或关闭氛围层，并渐变透明度。
## [param enabled] true 开启，false 关闭。
## [param duration] 渐变时长。
func set_enabled(enabled: bool, duration: float = 1.0) -> void:
	visible = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var target := 1.0 if enabled else 0.0
	if duration <= 0.0:
		_enabled_fade = target
		if not enabled:
			visible = false
		return
	_fade_tween = create_tween()
	_fade_tween.tween_method(
		_set_enabled_fade,
		_enabled_fade,
		target,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not enabled:
		_fade_tween.tween_callback(_hide_if_disabled)


## 切换 BadApple 的白色氛围配色。
## [param active] true 时忽略主题色，使用纯白。
func set_badapple_mode(active: bool) -> void:
	_badapple_mode = active
	_refresh_tint()


## 每帧根据 FOV 更新氛围强度。
## [param delta] 本帧时间，单位为秒。
func _process(delta: float) -> void:
	if follow_fov:
		var camera := get_node_or_null(camera_path) as Camera3D
		if camera != null:
			var fov_ratio := clampf(
				inverse_lerp(fov_min, maxf(fov_max, fov_min + 1.0), camera.fov),
				0.0,
				1.0
			)
			_fov_factor = lerpf(1.0 - fov_influence, 1.0, fov_ratio)
	var target := intensity_coefficient * _fov_factor * _enabled_fade
	_opacity = lerpf(_opacity, target, clampf(delta * 8.0, 0.0, 1.0))
	_apply_opacity()


## 创建边缘白色、中心透明的 CanvasItem shader。
func _create_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint_color : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
uniform float edge_start = 0.35;
uniform float edge_end = 1.0;
uniform float gradient_power = 1.5;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float distance_from_center = length(p);
	float gradient = smoothstep(edge_start, edge_end, distance_from_center);
	gradient = pow(gradient, gradient_power);
	COLOR = vec4(tint_color.rgb, tint_color.a * gradient * opacity);
}
"""
	return shader


## 刷新主题色与 BadApple 白色配色。
func _refresh_tint() -> void:
	if _material == null:
		return
	var color := Color.WHITE.lerp(_theme_color, theme_tint_strength)
	if _badapple_mode:
		color = Color.WHITE
	_material.set_shader_parameter("tint_color", color)


## 设置开关渐变值。
func _set_enabled_fade(value: float) -> void:
	_enabled_fade = clampf(value, 0.0, 1.0)


## 关闭渐变结束后隐藏整个层。
func _hide_if_disabled() -> void:
	if is_zero_approx(_enabled_fade):
		visible = false


## 写入 shader 的透明度和渐变参数。
func _apply_opacity() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("opacity", _opacity)
	_material.set_shader_parameter("edge_start", edge_start)
	_material.set_shader_parameter("edge_end", edge_end)
	_material.set_shader_parameter("gradient_power", gradient_power)
