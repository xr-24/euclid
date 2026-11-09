shader_type spatial;
render_mode cull_disabled;
uniform vec4 water_color : source_color = vec4(0.06,0.28,0.30,1.0);
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    VERTEX.y += sin(world_position.x * 3.0 + TIME * 0.8) * 0.008 + sin(world_position.z * 4.0 - TIME) * 0.005;
}
void fragment() {
    float wave = sin(world_position.x * 16.0 + TIME) * cos(world_position.z * 11.0 - TIME * 0.7);
    ALBEDO = water_color.rgb + wave * 0.015;
    ROUGHNESS = 0.12;
    METALLIC = 0.35;
    NORMAL_MAP = vec3(0.5 + wave * 0.05,0.5 + sin(world_position.z * 17.0 + TIME) * 0.035,1.0);
}
