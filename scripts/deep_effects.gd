extends CanvasLayer

## The Deep — Floor 4+ visual effects.
## Reality distortion shader, camera flickers, eerie ambience.
## Instantiated by dungeon scene when on floor 4+.

var _distortion_rect: ColorRect = null
var _flicker_timer: float = 0.0
var _next_flicker: float = 3.0
var _distortion_time: float = 0.0
var _active: bool = false

const DISTORTION_SHADER := """
shader_type canvas_item;
uniform float time;
uniform float intensity : hint_range(0.0, 1.0) = 0.3;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 uv = SCREEN_UV;
	// Wavy distortion
	float wave = sin(uv.y * 20.0 + time * 2.0) * 0.003 * intensity;
	float wave2 = cos(uv.x * 15.0 + time * 1.5) * 0.002 * intensity;
	uv.x += wave;
	uv.y += wave2;
	// Chromatic split
	float split = 0.002 * intensity;
	float r = texture(screen_texture, uv + vec2(split, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(split, 0.0)).b;
	// Scanlines
	float scanline = 1.0 - 0.1 * intensity * step(0.5, fract(SCREEN_UV.y * 400.0));
	// Vignette darkening
	vec2 vc = (SCREEN_UV - 0.5) * 2.0;
	float vignette = 1.0 - dot(vc, vc) * 0.3 * intensity;
	COLOR = vec4(r * scanline * vignette, g * scanline * vignette, b * scanline * vignette, 1.0);
}
"""

func _ready() -> void:
	layer = 98
	process_mode = Node.PROCESS_MODE_ALWAYS

	_distortion_rect = ColorRect.new()
	_distortion_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_distortion_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader = Shader.new()
	shader.code = DISTORTION_SHADER
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensity", 0.3)
	mat.set_shader_parameter("time", 0.0)
	_distortion_rect.material = mat
	add_child(_distortion_rect)

func activate() -> void:
	_active = true
	_distortion_rect.visible = true

func deactivate() -> void:
	_active = false
	_distortion_rect.visible = false

func _process(delta: float) -> void:
	if not _active:
		return

	_distortion_time += delta
	var mat = _distortion_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("time", _distortion_time)

	# Random camera flickers
	_flicker_timer += delta
	if _flicker_timer >= _next_flicker:
		_flicker_timer = 0.0
		_next_flicker = randf_range(2.0, 8.0)
		_do_flicker()

func _do_flicker() -> void:
	# Brief screen flash/glitch
	var mat = _distortion_rect.material as ShaderMaterial
	if not mat:
		return
	# Spike distortion intensity briefly
	mat.set_shader_parameter("intensity", 0.8)
	await get_tree().create_timer(0.05).timeout
	mat.set_shader_parameter("intensity", 1.0)
	await get_tree().create_timer(0.03).timeout
	mat.set_shader_parameter("intensity", 0.0)
	await get_tree().create_timer(0.05).timeout
	mat.set_shader_parameter("intensity", 0.3)
