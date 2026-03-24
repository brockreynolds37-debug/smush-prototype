extends CanvasLayer

## Screen Effects — chromatic aberration on low HP, hitstop on big hits, screen flash.
## Makes combat feel crunchy and impactful.

var _aberration_rect: ColorRect = null
var _flash_rect: ColorRect = null
var _aberration_strength: float = 0.0
var _target_aberration: float = 0.0
var _hitstop_active: bool = false

const ABERRATION_SHADER := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 0.02) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 uv = SCREEN_UV;
	float r = texture(screen_texture, uv + vec2(strength, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(strength, 0.0)).b;
	COLOR = vec4(r, g, b, 1.0);
}
"""

func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Chromatic aberration fullscreen shader
	_aberration_rect = ColorRect.new()
	_aberration_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aberration_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = ABERRATION_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("strength", 0.0)
	_aberration_rect.material = mat
	_aberration_rect.visible = false
	add_child(_aberration_rect)

	# Flash overlay (white/red flash on crits and big hits)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	add_child(_flash_rect)

	GameManager.hitstop_requested.connect(_on_hitstop)

func _process(delta: float) -> void:
	_update_low_hp_effects()
	_aberration_strength = lerp(_aberration_strength, _target_aberration, 5.0 * delta)
	if _aberration_strength > 0.001:
		_aberration_rect.visible = true
		(_aberration_rect.material as ShaderMaterial).set_shader_parameter("strength", _aberration_strength)
	else:
		_aberration_rect.visible = false

func _update_low_hp_effects() -> void:
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		_target_aberration = 0.0
		return
	var hp_ratio: float = float(hero.current_health) / float(hero.max_health)
	if hp_ratio < 0.3:
		# Scale aberration from 0 at 30% HP to max at 0% HP
		_target_aberration = (0.3 - hp_ratio) / 0.3 * 0.012
	else:
		_target_aberration = 0.0

func _on_hitstop(duration: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false

func screen_flash(color: Color, duration: float = 0.15) -> void:
	var flash_scale: float = AccessibilitySettings.screen_flash_scale if AccessibilitySettings else 1.0
	if flash_scale <= 0.01:
		return
	color.a *= flash_scale
	_flash_rect.color = color
	var tween = create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.tween_property(_flash_rect, "color:a", 0.0, duration)
