shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 body_green : source_color = vec4(0.055, 0.38, 0.17, 1.0);
uniform vec4 body_green_dark : source_color = vec4(0.02, 0.18, 0.075, 1.0);
uniform vec4 stripe_yellow : source_color = vec4(0.91, 0.72, 0.08, 1.0);
uniform vec4 roof_gray : source_color = vec4(0.56, 0.59, 0.57, 1.0);
uniform vec4 window_blue : source_color = vec4(0.075, 0.25, 0.26, 1.0);
uniform vec4 running_gear : source_color = vec4(0.035, 0.045, 0.043, 1.0);

varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	vec3 p = model_position;
	float side = smoothstep(0.42, 0.51, abs(p.x));
	vec3 color = mix(body_green_dark.rgb, body_green.rgb, 0.35 + 0.65 * max(NORMAL.y, 0.0));
	float roughness = 0.68;
	float metallic = 0.08;

	// Dark chassis, bogies and equipment below the body sill.
	if (p.y < 0.55) {
		color = running_gear.rgb;
		roughness = 0.82;
		metallic = 0.34;
	}

	// Rounded roof and roof fittings remain weathered light gray.
	if (p.y > 1.50) {
		color = roof_gray.rgb * (0.82 + 0.18 * max(NORMAL.y, 0.0));
		roughness = 0.78;
		metallic = 0.18;
	}

	// Repeating side windows. End bays are reserved for vestibule doors.
	float window_zone = step(0.82, p.y) * (1.0 - step(1.36, p.y));
	float passenger_zone = 1.0 - step(3.34, abs(p.z));
	float bay_phase = fract((p.z + 3.18) / 0.49);
	float window_bay = step(0.14, bay_phase) * (1.0 - step(0.82, bay_phase));
	float window_mask = side * window_zone * passenger_zone * window_bay;
	color = mix(color, window_blue.rgb, window_mask * 0.96);
	if (window_mask > 0.1) {
		roughness = 0.24;
		metallic = 0.12;
	}

	// Vestibule-door glazing near both ends.
	float door_zone = step(3.36, abs(p.z)) * (1.0 - step(3.82, abs(p.z)));
	float door_window = side * door_zone * step(0.88, p.y) * (1.0 - step(1.31, p.y));
	color = mix(color, window_blue.rgb * 0.82, door_window);

	// Classic passenger-car yellow waist bands, visible only on the side sheets.
	float lower_stripe = step(0.675, p.y) * (1.0 - step(0.735, p.y));
	float upper_stripe = step(1.405, p.y) * (1.0 - step(1.445, p.y));
	float stripe_mask = side * max(lower_stripe, upper_stripe);
	color = mix(color, stripe_yellow.rgb, stripe_mask);

	// Flexible gangway face and bellows at the extreme ends.
	float gangway = step(3.91, abs(p.z)) * (1.0 - side) * step(0.58, p.y);
	color = mix(color, running_gear.rgb * 0.72, gangway);

	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.38;
}
