// {{NAME}}: the game. A lit floor and a ball the left stick rolls, with a camera behind it that the right stick
// turns, and its name in the corner. Everything is drawn with sokol_gfx through the one shader in scene.glsl.
#include "lamp_game.h"
#include "sokol_debugtext.h"
#include "sokol_shape.h"
#include "HandmadeMath.h"
#include "scene.glsl.h"
#include <cmath>
#include <cstring>

struct Mesh { sg_buffer vertices, indices; sshape_element_range_t range; };

static struct {
    sg_pipeline pipeline;
    Mesh floor, ball;
    HMM_Vec3 ball_at, eye;
    float yaw, pitch;
    int width, height;
} g;

// One shape from sokol_shape into a pair of buffers. `layout` keeps the last shape's vertex layout for the pipeline
// (every shape's is the same).
static sshape_state_t layout;
template <typename Build> static Mesh make(Build build) {
    static uint8_t vertices[64 * 1024 * 24];
    static uint16_t indices[96 * 1024];
    sshape_state_t state = {};
    state.vertices.buffer = SSHAPE_RANGE(vertices);
    state.indices.buffer = SSHAPE_RANGE(indices);
    build(&state);
    Mesh mesh;
    mesh.vertices = sg_make_buffer(sshape_vertex_buffer_desc(&state));
    mesh.indices = sg_make_buffer(sshape_index_buffer_desc(&state));
    mesh.range = sshape_element_range(&state);
    layout = state;
    return mesh;
}

void game_init(const LampSetup* setup) {
    g.width = setup->width;
    g.height = setup->height;
    g.ball_at = HMM_V3(0, 0.5f, 0);
    g.pitch = 0.45f;

    sdtx_desc_t text = {};
    text.fonts[0] = sdtx_font_oric();
    text.context.color_format = setup->color_format;
    text.context.depth_format = setup->depth_format;
    text.context.sample_count = setup->sample_count;
    sdtx_setup(&text);

    g.floor = make([](sshape_state_t* state) {
        sshape_plane_t plane = {};
        plane.width = 40; plane.depth = 40; plane.tiles = 10;
        plane.color = sshape_color_3f(0.55f, 0.6f, 0.65f);
        sshape_build_plane(state, &plane);
    });
    g.ball = make([](sshape_state_t* state) {
        sshape_sphere_t sphere = {};
        sphere.radius = 0.5f; sphere.slices = 36; sphere.stacks = 20;
        sphere.color = sshape_color_3f(1.0f, 0.55f, 0.15f);
        sshape_build_sphere(state, &sphere);
    });

    sg_pipeline_desc pipeline = {};
    pipeline.shader = sg_make_shader(scene_shader_desc(sg_query_backend()));
    pipeline.layout.buffers[0] = sshape_vertex_buffer_layout_state(&layout);
    pipeline.layout.attrs[ATTR_scene_position] = sshape_position_vertex_attr_state(&layout);
    pipeline.layout.attrs[ATTR_scene_normal] = sshape_normal_vertex_attr_state(&layout);
    pipeline.layout.attrs[ATTR_scene_texcoord] = sshape_texcoord_vertex_attr_state(&layout);
    pipeline.layout.attrs[ATTR_scene_color0] = sshape_color_vertex_attr_state(&layout);
    pipeline.index_type = SG_INDEXTYPE_UINT16;
    pipeline.cull_mode = SG_CULLMODE_BACK;
    pipeline.depth.compare = SG_COMPAREFUNC_LESS_EQUAL;
    pipeline.depth.write_enabled = true;
    pipeline.depth.pixel_format = setup->depth_format;
    pipeline.colors[0].pixel_format = setup->color_format;
    g.pipeline = sg_make_pipeline(&pipeline);
    lamp_log("{{NAME}} is ready.");
}

static void draw(const Mesh& mesh, const HMM_Mat4& view_projection, const HMM_Mat4& model, HMM_Vec4 tint) {
    vs_params_t vs;
    HMM_Mat4 mvp = HMM_MulM4(view_projection, model);
    memcpy(vs.mvp, &mvp, sizeof mvp);
    memcpy(vs.model, &model, sizeof model);
    fs_params_t fs = {};
    float light[4] = { 0.4f, 1.0f, 0.3f, 0 };
    float eye[4] = { g.eye.X, g.eye.Y, g.eye.Z, 1 };
    memcpy(fs.light_dir, light, sizeof light);
    memcpy(fs.eye_pos, eye, sizeof eye);
    memcpy(fs.tint, &tint, sizeof tint);
    sg_bindings bindings = {};
    bindings.vertex_buffers[0] = mesh.vertices;
    bindings.index_buffer = mesh.indices;
    sg_apply_bindings(&bindings);
    sg_apply_uniforms(UB_vs_params, SG_RANGE(vs));
    sg_apply_uniforms(UB_fs_params, SG_RANGE(fs));
    sg_draw(mesh.range.base_element, mesh.range.num_elements, 1);
}

void game_frame(const LampFrame* frame) {
    const LampPad& pad = frame->pads[0];
    float dt = (float)frame->dt;

    // The right stick turns the camera; the left stick rolls the ball the way the camera faces.
    g.yaw += pad.rx * 2.0f * dt;
    g.pitch = HMM_Clamp(0.15f, g.pitch - pad.ry * 1.5f * dt, 1.3f);
    HMM_Vec3 forward = HMM_V3(sinf(g.yaw), 0, cosf(g.yaw));
    HMM_Vec3 right = HMM_V3(-cosf(g.yaw), 0, sinf(g.yaw));
    float speed = 6.0f * dt;
    g.ball_at = HMM_AddV3(g.ball_at, HMM_AddV3(HMM_MulV3F(forward, pad.ly * speed), HMM_MulV3F(right, pad.lx * speed)));
    g.ball_at.X = HMM_Clamp(-19.5f, g.ball_at.X, 19.5f);
    g.ball_at.Z = HMM_Clamp(-19.5f, g.ball_at.Z, 19.5f);
    if (pad.pressed & LAMP_A) lamp_log("A pressed with the ball at %.1f, %.1f", g.ball_at.X, g.ball_at.Z);

    float distance = 9.0f;
    g.eye = HMM_V3(g.ball_at.X - forward.X * distance * cosf(g.pitch), g.ball_at.Y + distance * sinf(g.pitch),
                   g.ball_at.Z - forward.Z * distance * cosf(g.pitch));
    HMM_Mat4 projection = HMM_Perspective_RH_ZO(60.0f * HMM_DegToRad, (float)g.width / (float)g.height, 0.1f, 200.0f);
    HMM_Mat4 view = HMM_LookAt_RH(g.eye, g.ball_at, HMM_V3(0, 1, 0));
    HMM_Mat4 view_projection = HMM_MulM4(projection, view);

    sg_pass pass = {};
    pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
    pass.action.colors[0].clear_value = { 0.12f, 0.16f, 0.26f, 1.0f };
    pass.swapchain = frame->swapchain;
    sg_begin_pass(&pass);
    sg_apply_pipeline(g.pipeline);
    draw(g.floor, view_projection, HMM_M4D(1.0f), HMM_V4(1, 1, 1, 2));   // w = 2 asks the shader for the checks
    HMM_Mat4 roll = HMM_Rotate_RH((float)frame->time * 2.0f, HMM_V3(1, 0, 0));
    draw(g.ball, view_projection, HMM_MulM4(HMM_Translate(g.ball_at), roll), HMM_V4(1, 1, 1, 1));

    // Text on a canvas a third of the screen's size, so each letter is 24 pixels: big enough from the sofa.
    sdtx_canvas(g.width / 3.0f, g.height / 3.0f);
    sdtx_origin(2, 2);
    sdtx_color3f(1, 1, 1);
    sdtx_puts("{{NAME}}");
    sdtx_draw();
    sg_end_pass();
    sg_commit();
}
