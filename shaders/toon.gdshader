shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Toon / cel-shading shader — WC3-inspired look
// Discrete light bands, warm palette, optional outline

group_uniforms albedo;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;

group_uniforms toon;
uniform float light_bands : hint_range(2.0, 6.0, 1.0) = 3.0;
uniform float band_smoothness : hint_range(0.0, 0.3) = 0.05;
uniform float shadow_brightness : hint_range(0.0, 0.8) = 0.35;
uniform vec4 shadow_tint : source_color = vec4(0.6, 0.5, 0.7, 1.0);

group_uniforms rim;
uniform bool rim_enabled = true;
uniform float rim_width : hint_range(0.0, 1.0) = 0.45;
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.6;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);

group_uniforms outline;
uniform bool outline_enabled = false;
uniform float outline_width : hint_range(0.0, 0.05) = 0.015;

void vertex() {
	if (outline_enabled) {
		// Push vertices along normals for outline pass (use with cull_front material)
		VERTEX += NORMAL * outline_width;
	}
}

void fragment() {
	vec3 base_color = albedo_color.rgb;
	if (use_texture) {
		base_color *= texture(albedo_texture, UV).rgb;
	}
	ALBEDO = base_color;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}

void light() {
	// Toon shading with discrete light bands
	float NdotL = dot(NORMAL, LIGHT);
	float raw_intensity = (NdotL + 1.0) * 0.5; // remap -1..1 to 0..1

	// Quantize into bands
	float bands = light_bands;
	float stepped = floor(raw_intensity * bands + 0.5) / bands;
	// Smooth the band edges slightly
	float blended = mix(raw_intensity, stepped, 1.0 - band_smoothness);

	// Apply shadow tint to dark areas
	vec3 shadow_col = mix(shadow_tint.rgb * ALBEDO, ALBEDO, shadow_brightness);
	vec3 lit_color = mix(shadow_col, ALBEDO * LIGHT_COLOR, blended);

	// Rim lighting
	if (rim_enabled) {
		float rim_factor = 1.0 - dot(NORMAL, VIEW);
		rim_factor = smoothstep(1.0 - rim_width, 1.0, rim_factor);
		float rim_light = rim_factor * max(NdotL, 0.2);
		lit_color += rim_color.rgb * rim_light * rim_intensity;
	}

	DIFFUSE_LIGHT += lit_color * ATTENUATION;
}
