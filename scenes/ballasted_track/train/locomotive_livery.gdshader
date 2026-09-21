shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float saturation : hint_range(0.0, 2.0) = 1.35;
uniform float contrast : hint_range(0.5, 2.0) = 1.18;
uniform float brightness : hint_range(0.0, 1.5) = 0.76;
uniform float roughness : hint_range(0.0, 1.0) = 0.34;
uniform float metallic : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	float luminance = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(luminance), base, saturation);
	graded = (graded - vec3(0.5)) * contrast + vec3(0.5);
	ALBEDO = clamp(graded * brightness, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness;
	METALLIC = metallic;
}