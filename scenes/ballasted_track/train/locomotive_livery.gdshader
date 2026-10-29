shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_texture = true;
uniform mat4 mesh_to_body;
uniform vec4 body_red : source_color = vec4(0.60, 0.018, 0.042, 1.0);
uniform vec4 cab_charcoal : source_color = vec4(0.055, 0.065, 0.085, 1.0);
uniform vec4 skirt_blue_gray : source_color = vec4(0.14, 0.22, 0.25, 1.0);
varying vec3 body_position;

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec3 q = cell + f;
	return 0.5 + 0.25 * sin(q.x * 1.7 + sin(q.z * 0.91)) + 0.25 * sin(q.y * 2.9 + q.z * 0.73);
}

void vertex() {
	body_position = (mesh_to_body * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	float luminance = dot(base, vec3(0.2126, 0.7152, 0.0722));
	float high_channel = max(base.r, max(base.g, base.b));
	float low_channel = min(base.r, min(base.g, base.b));
	float chroma = high_channel - low_channel;
	float neutral_surface = 1.0 - smoothstep(0.055, 0.20, chroma);
	float green_surface = smoothstep(-0.015, 0.075, base.g - max(base.r, base.b));
	float light_body = smoothstep(0.16, 0.62, luminance);
	float recolor_mask = use_texture ? max(green_surface, neutral_surface * light_body * (1.0 - smoothstep(0.78, 0.94, luminance))) : 1.0;
	vec3 paint = body_red.rgb;
	// Vehicle-relative coordinates keep the diagonal cab band aligned on curves.
	float cab = smoothstep(6.0, 7.0, abs(body_position.z));
	float band_height = 1.70 + max(9.9 - abs(body_position.z), 0.0) * 0.18;
	float band = cab * smoothstep(band_height - 0.025, band_height + 0.025, body_position.y);
	paint = mix(paint, cab_charcoal.rgb, band);
	paint = mix(skirt_blue_gray.rgb, paint, smoothstep(-0.03, 0.015, body_position.y));
	paint = mix(paint, vec3(0.12, 0.135, 0.145), smoothstep(2.76, 2.83, body_position.y));
	float shading = use_texture ? mix(0.58, 1.0, smoothstep(0.05, 0.8, luminance)) : 1.0;
	// Restrained paint variation and road dust, expressed in metres.
	float variation = noise3(body_position * vec3(1.6, 5.0, 2.2));
	float grime = (1.0 - smoothstep(-0.15, 0.85, body_position.y)) * (0.12 + 0.08 * variation);
	vec3 enamel = paint * shading * (0.99 + 0.015 * variation);
	enamel = mix(enamel, vec3(0.085, 0.073, 0.06), grime);
	vec3 finish = mix(base, enamel, recolor_mask);
	// Keep the photographed wipers/reflections but suppress the baked white glare.
	float glazing_y = step(0.15, UV.y) * (1.0 - step(0.315, UV.y));
	float glazing_x = max(step(0.08, UV.x) * (1.0 - step(0.435, UV.x)), step(0.52, UV.x) * (1.0 - step(0.90, UV.x)));
	float glazing = use_texture ? glazing_y * glazing_x : 0.0;
	finish = mix(finish, mix(vec3(0.018, 0.037, 0.044), base * vec3(0.22, 0.29, 0.31), 0.55), glazing);
	ALBEDO = finish;
	ROUGHNESS = mix(0.66 + variation * 0.025 + grime * 0.25, 0.32, glazing);
	METALLIC = 0.0;
	SPECULAR = 0.22;
}
