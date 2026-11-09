shader_type spatial;
uniform vec4 tint : source_color = vec4(0.79,0.76,0.67,1.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p = world_position.xz;
    float grain = sin(p.x * 1.6 + sin(p.y * 2.0) * 1.6 + sin(p.x * 3.7 + p.y) * 0.3);
    float vein = pow(abs(grain), 24.0);
    float fine_grain = sin(p.x * 150.0) * sin(p.y * 120.0) * 0.008;
    ALBEDO = tint.rgb * (0.94 - vein * 0.12 + fine_grain);
    ROUGHNESS = 0.33 + vein * 0.06;
}
