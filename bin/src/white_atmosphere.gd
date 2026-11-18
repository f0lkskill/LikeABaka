extends CanvasLayer

## 全屏白色氛围层。
##
## 画面边缘为白色，向屏幕中心逐渐透明；颜色会混合当前角色主题色。
## 强度逐帧读取 BGM 频谱，并支持开关渐变和 BadApple 白色模式。

const ANALYZER_BUS := "BGM_Analyzer"

## 氛围强度系数，最终透明度会乘以它。
@export_range(0.0, 2.0, 0.01) var intensity_coefficient: float = 1.15
## 主题色混合到白色底色的比例。
@export_range(0.0, 1.0, 0.01) var theme_tint_strength: float = 0.28
## BGM 分析频段下限。
@export var bgm_min_hz: float = 60.0
## BGM 分析频段上限。
@export var bgm_max_hz: float = 4000.0
## BGM 频谱增益。
@export var bgm_gain: float = 2.0
## 静音时的最低强度比例。
@export_range(0.0, 1.0, 0.01) var bgm_floor: float = 0.2
## 强度跟随 BGM 的平滑速度。
@export_range(1.0, 40.0, 0.1) var bgm_smoothing: float = 12.0
## 渐变开始位置，0 为屏幕中心，1 为边缘。
@export_range(0.0, 1.0, 0.01) var edge_start: float = 0.18
## 渐变结束位置。
@export_range(0.0, 1.5, 0.01) var edge_end: float = 1.0
## 渐变曲线幂次，越大越集中到边缘。
@export_range(0.2, 5.0, 0.1) var gradient_power: float = 1.2

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
## 主题色渐变 Tween。
var _theme_tween: Tween
## 主题色到 BadApple 白色的渐变 Tween。
var _tint_tween: Tween
## BGM 频谱分析器。
var _analyzer: AudioEffectSpectrumAnalyzerInstance
## 当前 BGM 强度，范围 0 到 1。
var _bgm_energy: float = 0.0
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
	_setup_bgm_analyzer()
	visible = false
	_refresh_tint()
	_apply_opacity()


## 绑定 BGM 频谱分析器；如果总线已由摄像机创建则直接复用。
func _setup_bgm_analyzer() -> void:
	var bus_index := AudioServer.get_bus_index(ANALYZER_BUS)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, ANALYZER_BUS)
		AudioServer.set_bus_send(bus_index, "Master")
	if AudioServer.get_bus_effect_count(bus_index) == 0:
		var analyzer_effect := AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(bus_index, analyzer_effect)
	_analyzer = AudioServer.get_bus_effect_instance(
		bus_index,
		0
	) as AudioEffectSpectrumAnalyzerInstance


## 设置角色主题色；颜色变化可以渐变。
## [param color] 当前角色主题色。
## [param duration] 渐变时长；小于等于 0 时立即应用。
func set_theme_color(color: Color, duration: float = 0.0) -> void:
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	if duration <= 0.0:
		_set_theme_color_value(color)
		return
	_theme_tween = create_tween()
	_theme_tween.tween_method(
		_set_theme_color_value,
		_theme_color,
		color,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 更新主题色缓存并刷新着色器颜色。
## [param color] 过渡中的主题色。
func _set_theme_color_value(color: Color) -> void:
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
## [param duration] 主题色与白色之间的渐变时长。
func set_badapple_mode(active: bool, duration: float = 0.0) -> void:
	_badapple_mode = active
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	var target := _get_target_tint_color()
	if duration <= 0.0 or _material == null:
		_set_tint_color_value(target)
		return
	var current := _material.get_shader_parameter("tint_color") as Color
	if current == null:
		current = target
	_tint_tween = create_tween()
	_tint_tween.tween_method(
		_set_tint_color_value,
		current,
		target,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 每帧读取当前 BGM 频谱并更新氛围强度。
## [param delta] 本帧时间，单位为秒。
func _process(delta: float) -> void:
	var energy := 0.0
	if _analyzer != null:
		var magnitude := _analyzer.get_magnitude_for_frequency_range(
			bgm_min_hz,
			maxf(bgm_max_hz, bgm_min_hz + 1.0)
		)
		energy = clampf(maxf(magnitude.x, magnitude.y) * bgm_gain, 0.0, 1.0)
	_bgm_energy = lerpf(
		_bgm_energy,
		energy,
		clampf(delta * bgm_smoothing, 0.0, 1.0)
	)
	var music_strength := lerpf(bgm_floor, 1.0, _bgm_energy)
	var target := intensity_coefficient * music_strength * _enabled_fade
	_opacity = lerpf(_opacity, target, clampf(delta * 12.0, 0.0, 1.0))
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
	if _tint_tween != null and _tint_tween.is_running():
		return
	_set_tint_color_value(_get_target_tint_color())


## 计算当前主题色与 BadApple 模式下的目标颜色。
func _get_target_tint_color() -> Color:
	if _badapple_mode:
		return Color.WHITE
	return Color.WHITE.lerp(_theme_color, theme_tint_strength)


## 写入 shader 的 tint_color。
## [param color] 目标颜色。
func _set_tint_color_value(color: Color) -> void:
	if _material != null:
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
