extends MeshInstance3D

## 包裹舞台的卷轴式黑白块背景圆柱。
## 黑块使用角色主题色；角色切换时圆柱在约一半处分开，
## 一侧保留旧主题，另一侧切换新主题，并在边界处柔和过渡。

@export_group("Pattern")
## 横向与纵向的黑白块数量。
@export var block_count: Vector2 = Vector2(64.0, 48.0):
	set(value):
		block_count = value
		_apply_to_shader()
## 横向卷轴滚动速度，单位为 UV/秒。
@export var scroll_speed: float = 0.025:
	set(value):
		scroll_speed = value
		_apply_to_shader()
## 纵向卷轴滚动速度，单位为 UV/秒。
@export var scroll_speed_y: float = 0.0:
	set(value):
		scroll_speed_y = value
		_apply_to_shader()
## 白块颜色。
@export var white_color: Color = Color.WHITE:
	set(value):
		white_color = value
		_apply_to_shader()
## 初始黑块主题色。
@export var base_theme_color: Color = Color(1.0, 0.4, 0.68, 1.0)
## 背景整体亮度；过暗会失去黑白块氛围。
@export_range(0.0, 1.0, 0.01) var brightness: float = 0.85:
	set(value):
		brightness = value
		_apply_to_shader()
## 背景底部相对顶部的额外变暗比例。
@export_range(0.0, 1.0, 0.01) var bottom_darkness: float = 0.15:
	set(value):
		bottom_darkness = value
		_apply_to_shader()
## 律动条高度附近压暗带中心，沿圆柱高度 0 到 1。
@export_range(0.0, 1.0, 0.01) var bar_band_center: float = 0.45:
	set(value):
		bar_band_center = value
		_apply_to_shader()
## 律动条压暗带宽度。
@export_range(0.0, 0.5, 0.01) var bar_band_width: float = 0.22:
	set(value):
		bar_band_width = value
		_apply_to_shader()
## 律动条压暗带强度；只压暗条后方，避免整面背景过黑。
@export_range(0.0, 1.0, 0.01) var bar_band_darkness: float = 0.55:
	set(value):
		bar_band_darkness = value
		_apply_to_shader()

@export_group("Background")
## 普通状态随机背景素材目录。
@export_dir var background_directory: String = "res://bin/asset/image/bg"
## 普通背景素材亮度。
@export_range(0.0, 1.0, 0.01) var texture_brightness: float = 0.9
## 背景素材交叉淡入的默认时长。
@export_range(0.05, 5.0, 0.05) var texture_switch_duration: float = 1.2

@export_group("Theme Split")
## 半圆分界线在圆周上的偏移，0 到 1。
@export_range(0.0, 1.0, 0.01) var split_angle: float = 0.0:
	set(value):
		split_angle = value
		_apply_to_shader()
## 分界线两侧颜色的柔化宽度。
@export_range(0.0, 0.25, 0.001) var split_softness: float = 0.18:
	set(value):
		split_softness = value
		_apply_to_shader()

## 圆柱背景材质。
var _material: ShaderMaterial
## 主题色过渡 Tween。
var _theme_tween: Tween
## 背景素材交叉淡入 Tween。
var _texture_tween: Tween
## 黑白块剪影切换 Tween。
var _checker_tween: Tween
## 当前显示的两侧主题色。
var _color_a: Color
var _color_b: Color
## 主题色对半分裂程度。
var _split_amount: float = 0.0
## 背景目录中加载的素材。
var _background_textures: Array[Texture2D] = []
## 交叉淡入的当前素材与下一张素材。
var _texture_a: Texture2D
var _texture_b: Texture2D
## 当前素材索引。
var _current_texture_index: int = -1
## 正在淡入的素材索引。
var _next_texture_index: int = -1
## 素材交叉淡入程度，0 为当前素材，1 为下一张素材。
var _texture_mix: float = 0.0
## 黑白块剪影程度，0 为普通素材，1 为剪影。
var _checker_mix: float = 0.0


## 创建背景 ShaderMaterial 并应用初始主题色。
func _ready() -> void:
	_build_material()
	# 黑白块与主题色作为舞台常驻背景保留；飞入素材是额外叠加的独立效果。
	set_theme(base_theme_color)
	_apply_to_shader()


## 扫描背景目录并选中第一张随机素材。
func _load_background_textures() -> void:
	_background_textures.clear()
	var directory := DirAccess.open(background_directory)
	if directory == null:
		push_warning("StageBackdrop: 无法打开背景目录: %s" % background_directory)
		return
	var files := directory.get_files()
	files.sort()
	for file in files:
		if file.get_extension().to_lower() != "png":
			continue
		var loaded := load(background_directory.path_join(file)) as Texture2D
		if loaded != null:
			_background_textures.append(loaded)
	if _background_textures.is_empty():
		return
	_current_texture_index = randi() % _background_textures.size()
	_texture_a = _background_textures[_current_texture_index]
	_texture_b = _texture_a


## 立即设置统一主题色。
## [param color] 新的黑块颜色。
func set_theme(color: Color) -> void:
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	_color_a = color
	_color_b = color
	_split_amount = 0.0
	_apply_to_shader()


## 所有区域一起渐变到目标主题色，不执行对半分裂。
## [param color] 目标黑块颜色。
## [param duration] 过渡时长；小于等于 0 时立即应用。
func fade_theme(color: Color, duration: float) -> void:
	if duration <= 0.0:
		set_theme(color)
		return
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	_theme_tween = create_tween().set_parallel(true)
	_theme_tween.tween_method(_set_color_a, _color_a, color, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_theme_tween.tween_method(_set_color_b, _color_b, color, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_theme_tween.tween_method(_set_split_amount, _split_amount, 0.0, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)


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


## 随机切换到另一张背景素材并交叉淡入。
## [param duration] 过渡时长；小于 0 时使用默认值。
func switch_random_background(duration: float = -1.0) -> void:
	if _background_textures.size() <= 1:
		return
	var fade_duration := texture_switch_duration if duration < 0.0 else duration
	var candidates: Array[int] = []
	for i in _background_textures.size():
		if i != _current_texture_index:
			candidates.append(i)
	if candidates.is_empty():
		return
	if _texture_tween != null and _texture_tween.is_valid():
		_texture_tween.kill()
	_next_texture_index = candidates[randi() % candidates.size()]
	_texture_a = _background_textures[_current_texture_index]
	_texture_b = _background_textures[_next_texture_index]
	_texture_mix = 0.0
	_apply_to_shader()
	if fade_duration <= 0.0:
		_finish_texture_switch()
		return
	_texture_tween = create_tween()
	_texture_tween.tween_method(_set_texture_mix, 0.0, 1.0, fade_duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_texture_tween.tween_callback(_finish_texture_switch)


## 在普通素材与黑白块剪影之间渐变。
## [param active] true 显示黑白块，false 显示背景素材。
## [param duration] 过渡时长；小于等于 0 时立即应用。
func set_checker_mode(active: bool, duration: float) -> void:
	if _checker_tween != null and _checker_tween.is_valid():
		_checker_tween.kill()
	var target := 1.0 if active else 0.0
	if duration <= 0.0:
		_checker_mix = target
		_apply_to_shader()
		return
	_checker_tween = create_tween()
	_checker_tween.tween_method(_set_checker_mix, _checker_mix, target, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)


## 构建圆柱背景使用的着色器。
func _build_material() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D bg_texture_a : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bg_texture_b : source_color, filter_linear_mipmap, repeat_enable;
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
uniform float texture_mix = 0.0;
uniform float checker_mix = 0.0;
uniform float texture_brightness = 0.9;

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
	// 只在剪影事件中显示黑白块，平时由 ALPHA 淡出为透明。
	ALBEDO = block_color * brightness * height_shade;
	ALPHA = 1.0;
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	# 背景是透明材质，必须比律动条和角色更早绘制，避免盖住前景。
	_material.render_priority = -10
	material_override = _material


## 完成背景素材切换。
func _finish_texture_switch() -> void:
	if _next_texture_index >= 0:
		_current_texture_index = _next_texture_index
	_texture_a = _texture_b
	_texture_mix = 0.0
	_next_texture_index = -1
	_apply_to_shader()


## 设置素材交叉淡入程度。
func _set_texture_mix(value: float) -> void:
	_texture_mix = value
	_apply_to_shader()


## 设置黑白块剪影程度。
func _set_checker_mix(value: float) -> void:
	_checker_mix = value
	_apply_to_shader()


## 设置分界线的过渡程度。
func _set_split_amount(value: float) -> void:
	_split_amount = value
	_apply_to_shader()


## 设置 A 侧主题色。
func _set_color_a(value: Color) -> void:
	_color_a = value
	_apply_to_shader()


## 设置 B 侧主题色。
func _set_color_b(value: Color) -> void:
	_color_b = value
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
	_material.set_shader_parameter("bg_texture_a", _texture_a)
	_material.set_shader_parameter("bg_texture_b", _texture_b)
	_material.set_shader_parameter("texture_mix", _texture_mix)
	_material.set_shader_parameter("checker_mix", _checker_mix)
	_material.set_shader_parameter("texture_brightness", texture_brightness)
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
