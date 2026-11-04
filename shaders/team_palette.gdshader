shader_type canvas_item;
// Team palette swap for character sprites.
//
// Character sheets (tools/make_sprites.py) draw the scarf in two marker
// colours instead of a real team colour:
//     (255,   0, 255) magenta        -> team_color
//     (180,   0, 180) dark magenta   -> team_color * 0.7  (scarf shadow)
// Anything else is left untouched, so one sprite sheet serves every team.
// If you repaint the sprites, keep those two marker colours on whatever you
// want recoloured and nothing else in your art should be that magenta.

uniform vec4 team_color : source_color = vec4(0.9, 0.35, 0.25, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d_main = distance(c.rgb, vec3(1.0, 0.0, 1.0));
	float d_shade = distance(c.rgb, vec3(0.706, 0.0, 0.706));
	if (c.a > 0.0) {
		if (d_main < 0.08) {
			c.rgb = team_color.rgb;
		} else if (d_shade < 0.08) {
			c.rgb = team_color.rgb * 0.7;
		}
	}
	COLOR = c;
}
