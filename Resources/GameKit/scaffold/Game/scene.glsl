// The game's shader: sokol-shdc turns it into HLSL for the Xbox and Metal for the preview on the Mac, with
// build/shaders/scene.glsl.h describing it to the game (scene_shader_desc, ATTR_scene_…, UB_vs_params, vs_params_t…).
@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
};
in vec4 position;
in vec4 normal;
in vec2 texcoord;
in vec4 color0;
out vec3 wpos;
out vec3 nrm;
out vec2 uv;
out vec4 color;
void main() {
    gl_Position = mvp * position;
    wpos = (model * position).xyz;
    nrm = normalize(mat3(model) * normal.xyz);
    uv = texcoord;
    color = color0;
}
@end

@fs fs
layout(binding=1) uniform fs_params {
    vec4 light_dir;
    vec4 eye_pos;
    vec4 tint;
};
in vec3 wpos;
in vec3 nrm;
in vec2 uv;
in vec4 color;
out vec4 frag_color;
void main() {
    vec3 n = normalize(nrm);
    vec3 l = normalize(light_dir.xyz);
    vec3 v = normalize(eye_pos.xyz - wpos);
    vec3 h = normalize(l + v);
    float diffuse = clamp(dot(n, l), 0.0, 1.0);
    float spec = pow(clamp(dot(n, h), 0.0, 1.0), 48.0) * 0.4;
    float checker = (tint.w > 1.5) ? (mod(floor(uv.x * 40.0) + floor(uv.y * 40.0), 2.0) * 0.25 + 0.75) : 1.0;
    vec3 base = color.rgb * tint.rgb * checker;
    frag_color = vec4(base * (0.18 + 0.82 * diffuse) + spec, 1.0);
}
@end

@program scene vs fs
