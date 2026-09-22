shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 body_green : source_color = vec4(0.026, 0.245, 0.095, 1.0);
uniform vec4 body_green_dark : source_color = vec4(0.010, 0.105, 0.038, 1.0);
uniform float saturation : hint_range(0.0, 2.0) = 1.30;
uniform float contrast : hint_range(0.5, 2.0) = 1.14;
uniform float brightness : hint_range(0.0, 1.5) = 0.84;
uniform float roughness : hint_range(0.0, 1.0) = 0.80;
uniform float metallic : hint_range(0.0, 1.0) = 0.02;

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	float luminance = dot(base, vec3(0.2126, 0.7152, 0.0722));
	float high_channel = max(base.r, max(base.g, base.b));
	float low_channel = min(base.r, min(base.g, base.b));
	float chroma = high_channel - low_channel;
	float neutral_surface = 1.0 - smoothstep(0.055, 0.20, chroma);
	float green_surface = smoothstep(-0.015, 0.075, base.g - max(base.r, base.b));
	float light_body = smoothstep(0.16, 0.62, luminance);
	float recolor_mask = max(green_surface, neutral_surface * light_body);
	vec3 reference_green = mix(body_green_dark.rgb, body_green.rgb,
		smoothstep(0.08, 0.86, luminance));
	// The source front-livery texture contains pale neutral body panels.
	// Recolour those panels instead of merely darkening them, matching the
	// passenger-car green while preserving coloured stripes and dark glazing.
	vec3 recolored = mix(base, reference_green, recolor_mask * 0.92);
	float recolored_luminance = dot(recolored, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(recolored_luminance), recolored, saturation);
	graded = (graded - vec3(0.5)) * contrast + vec3(0.5);
	ALBEDO = clamp(graded * brightness, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.25;
}
