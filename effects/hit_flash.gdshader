shader_type canvas_item;

// Mixes the drawn colour toward flash_color. Alpha is left alone.
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, amount);
}
