extends MeshInstance3D

## 包裹舞台的卷轴式黑白块背景圆柱。
## 黑块使用角色主题色；角色切换时圆柱在约一半处分开，
## 一侧保留旧主题，另一侧切换新主题，并在边界处柔和过渡。

@export_group("Pattern")
## 横向与纵向的黑白块数量。
@export var block_count: Vector2 = Vector2(64.0, 48.0)
## 横向卷轴滚动速度，单位为 UV/秒。
@export var scroll_speed: float = 0.025
## 纵向卷轴滚动速度，单位为 UV/秒。
@export var scroll_speed_y: float = 0.0
## 白块颜色。
@export var white_color: Color = Color.WHITE
## 初始黑块主题色。
@export var base_theme_color: Color = Color(1.0, 0.4, 0.68, 1.0)
## 背景整体亮度；过暗会失去黑白块氛围。
@export_range(0.0, 1.0, 0.01) var brightness: float = 0.85
## 背景底部相对顶部的额外变暗比例。
@export_range(0.0, 1.0, 0.01) var bottom_darkness: float = 0.15
## 律动条高度附近压暗带中心，沿圆柱高度 0 到 1。
@export_range(0.0, 1.0, 0.01) var bar_band_center: float = 0.45
## 律动条压暗带宽度。
@export_range(0.0, 0.5, 0.01) var bar_band_width: float = 0.22
## 律动条压暗带强度；只压暗条后方，避免整面背景过黑。
@export_range(0.0, 1.0, 0.01) var bar_band_darkness: float = 0.55

@export_group("Theme Split")
## 半圆分界线在圆周上的偏移，0 到 1。
@export_range(0.0, 1.0, 0.01) var split_angle: float = 0.0
## 分界线两侧颜色的柔化宽度。
@export_range(0.0, 0.25, 0.001) var split_softness: float = 0.18

var _material: ShaderMaterial
var _theme_tween: Tween
var _color_a: Color
var _color_b: Color
var _split_amount: float = 0.0


## 创建背景 ShaderMaterial 并应用初始主题色。
func _ready() -> void:
	_build_material()
	set_theme(base_theme_color)


## 立即设置统一主题色。
## [param color] 新的黑块颜色。
func set_theme(color: Color) -> void:
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	_color_a = color
	_color_b = color
	_split_amount = 0.0
	_apply_to_shader()


## 从旧主题过渡到新主题。
## 先让圆柱分成两半，再让旧的一半追上新颜色。
## [param old_color] 旧主题色。
## [param new_color] 新主题色。
## [param duration] 过渡总时长。
func transition_theme(old_color: Color, new_color: Color, duration: float) -> void:
	if duration <= 0.0:
		set_theme(new_color)
		return
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	_color_a = old_color
	_color_b = new_color
	_split_amount = 0.0
	_apply_to_shader()
	var split_time := duration * 0.35
	_theme_tween = create_tween()
	_theme_tween.tween_method(_set_split_amount, 0.0, 1.0, split_time) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_theme_tween.tween_method(
		_set_color_a,
		old_color,
		new_color,
		maxf(duration - split_time, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_theme_tween.tween_callback(_finish_theme_transition)


## 构建圆柱背景使用的着色器。
func _build_material() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 color_a : source_color = vec4(1.0, 0.4, 0.68, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.4, 0.68, 1.0);
uniform vec4 white_color : source_color = vec4(1.0);
uniform vec2 block_count = vec2(64.0, 48.0);
uniform float scroll_speed = 0.025;
uniform float scroll_speed_y = 0.0;
uniform float split_angle = 0.0;
uniform float split_softness = 0.18;
uniform float split_amount = 0.0;
uniform float brightness = 0.85;
uniform float bottom_darkness = 0.15;
uniform float bar_band_center = 0.45;
uniform float bar_band_width = 0.22;
uniform float bar_band_darkness = 0.55;

void fragment() {
	vec2 uv = UV;
	uv.x += TIME * scroll_speed;
	uv.y += TIME * scroll_speed_y;
	vec2 cell = floor(uv * block_count);
	float checker = mod(cell.x + cell.y, 2.0);
	float angle = fract(UV.x + split_angle);
	float half_mask = smoothstep(0.5 - split_softness, 0.5 + split_softness, angle);
	vec4 theme_color = mix(color_a, color_b, half_mask * split_amount);
	vec3 block_color = mix(white_color.rgb, theme_color.rgb, checker);
	float height_shade = mix(1.0 - bottom_darkness, 1.0, smoothstep(0.05, 0.9, UV.y));
	float band = 1.0 - smoothstep(0.0, bar_band_width, abs(UV.y - bar_band_center));
	height_shade *= mix(1.0, 1.0 - bar_band_darkness, band);
	ALBEDO = block_color * brightness * height_shade;
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	material_override = _material


## 设置分界线的过渡程度。
func _set_split_amount(value: float) -> void:
	_split_amount = value
	_apply_to_shader()


## 设置 A 侧主题色。
func _set_color_a(value: Color) -> void:
	_color_a = value
	_apply_to_shader()


## 过渡结束时让两侧统一为新颜色。
func _finish_theme_transition() -> void:
	_color_a = _color_b
	_split_amount = 0.0
	_apply_to_shader()


## 把当前参数写入着色器。
func _apply_to_shader() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("color_a", _color_a)
	_material.set_shader_parameter("color_b", _color_b)
	_material.set_shader_parameter("white_color", white_color)
	_material.set_shader_parameter("block_count", block_count)
	_material.set_shader_parameter("scroll_speed", scroll_speed)
	_material.set_shader_parameter("scroll_speed_y", scroll_speed_y)
	_material.set_shader_parameter("split_angle", split_angle)
	_material.set_shader_parameter("split_softness", split_softness)
	_material.set_shader_parameter("split_amount", _split_amount)
	_material.set_shader_parameter("brightness", brightness)
	_material.set_shader_parameter("bottom_darkness", bottom_darkness)
	_material.set_shader_parameter("bar_band_center", bar_band_center)
	_material.set_shader_parameter("bar_band_width", bar_band_width)
	_material.set_shader_parameter("bar_band_darkness", bar_band_darkness)
