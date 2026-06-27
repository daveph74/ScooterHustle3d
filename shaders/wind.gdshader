shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// Solid colour fallback when the original material has no texture.
uniform vec4 albedo_color : source_color = vec4(0.35, 0.55, 0.25, 1.0);
// Original mesh texture (copied from the StandardMaterial3D we replace).
uniform sampler2D albedo_tex : source_color, hint_default_white;
// How far tops sway relative to local vertex height. 0.12 = ~12% of mesh local-y.
uniform float wind_strength : hint_range(0.0, 0.3) = 0.12;

void vertex() {
    float h = max(VERTEX.y, 0.0);
    // Vary phase by world z so adjacent trees don't sway in perfect lockstep.
    float world_z = MODEL_MATRIX[3].z;
    float sway = sin(TIME * 1.5 + world_z * 0.12 + VERTEX.x * 1.8 + VERTEX.z * 2.1)
                 * h * wind_strength;
    VERTEX.x += sway;
}

void fragment() {
    vec4 tex_col = texture(albedo_tex, UV);
    ALBEDO = tex_col.rgb * albedo_color.rgb;
    ALPHA = tex_col.a * albedo_color.a;
    ROUGHNESS = 0.9;
    METALLIC = 0.0;
}
