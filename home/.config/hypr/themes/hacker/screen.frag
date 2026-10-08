#version 300 es
// Hacker screen effect (toggled by ~/.local/bin/screen-fx): faint CRT scanlines, a soft green
// bloom on bright pixels and a light vignette. Kept subtle so text stays readable.
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 color = texture(tex, v_texcoord);
    vec2 size = vec2(textureSize(tex, 0));

    // Scanlines: every third physical row a little darker.
    float row = mod(floor(v_texcoord.y * size.y), 3.0);
    color.rgb *= row < 1.0 ? 0.94 : 1.0;

    // Bloom: lift bright pixels towards phosphor green.
    float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb += vec3(0.0, 0.035, 0.012) * smoothstep(0.55, 1.0, luma);

    // Vignette.
    vec2 d = v_texcoord - 0.5;
    color.rgb *= 1.0 - 0.28 * dot(d, d) * 2.0;

    fragColor = color;
}
