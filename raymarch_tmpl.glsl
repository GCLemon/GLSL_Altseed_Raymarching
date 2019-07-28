//////////////////////////////////////////////////
//
//    raymarch_tmpl.glsl
//    レイマーチングのテンプレート
//

uniform float time;
uniform vec2 resolution;

in vec4 inPosition;
in vec2 inUV;
in vec4 inColor;

out vec4 outOutput;

#define delta 0.001
#define pi 3.1415926535897932
#define max_step 128
#define sqrt3 1.73205080757
#define ax_x vec3(1.0, 0.0, 0.0)
#define ax_y vec3(0.0, 1.0, 0.0)
#define ax_z vec3(0.0, 0.0, 1.0)

vec3 light_env = normalize(vec3(4.0, 5.0, -3.0));

float bpm = 120.0;

// 光線の情報
struct ray
{
    vec3 pos;
    vec3 dir;
};

// hsv から rgb に変換する
vec3 hsv2rgb(float h, float s, float v)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(h + K.xyz) * 6.0 - K.www);
    return v * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), s);
}

// ロドリゲスの回転公式
mat3 rodrigues(vec3 axis, float angle)
{
    vec3 a = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float r = 1.0 - c;
    return mat3(
        a.x * a.x * r + c,
        a.y * a.x * r + a.z * s,
        a.z * a.x * r - a.y * s,
        a.x * a.y * r - a.z * s,
        a.y * a.y * r + c,
        a.z * a.y * r + a.x * s,
        a.x * a.z * r + a.y * s,
        a.y * a.z * r - a.x * s,
        a.z * a.z * r + c
    );
}

// 六角柱の距離関数
float sdHex(vec2 p, float h)
{
    vec3 k = vec3(-0.8660254, 0.57735, 0.5);
    p = abs(p);
    p -= 2.0 * min(dot(k.xz, p), 0.0) * k.xz;
    return length(p - vec2(clamp(p.x, -k.y * h, k.y * h), h)) * sign(p.y - h);
}

// 六角柱のタイリングをするときの距離関数
float deHexTiling(vec2 p, float radius, float scale)
{
    vec2 rep = vec2(2.0 * sqrt3, 2.0) * radius;
    vec2 p1 = mod(p, rep) - rep * 0.5;
    vec2 p2 = mod(p + 0.5 * rep, rep) - rep * 0.5;
    return min(
        sdHex(p1.xy, scale * radius),
        sdHex(p2.xy, scale * radius)
    );
}

// 正八面体の距離函数
float sdOctahedron( in vec3 p, in float s)
{
    p = abs(p);
    return (p.x+p.y+p.z-s)*0.57735027;
}

// オブジェクト全体の距離関数
float distance(vec3 pos, int select)
{
    switch(select)
    {
        case 1:
            return max(deHexTiling(pos.zx, 2.0, 0.9), pos.y);
        case 2:
            pos -= vec3(0.0, 3.0, 0.0);
            pos *= rodrigues(ax_x, pi * time / 12.0);
            pos *= rodrigues(ax_y, pi * time / 13.0);
            pos *= rodrigues(ax_z, pi * time / 14.0);
            pos = abs(pos);
            float v = 1.0 - mod(time * bpm * 0.5, 30.0) / 30.0;
            float d = 2.0 + 0.5 * v, s = 0.4 + 0.1 * v;
            float dist = sdOctahedron(pos, 1.6 + 0.4 * v);
            dist = min(dist, sdOctahedron(pos - ax_x * d, s));
            dist = min(dist, sdOctahedron(pos - ax_y * d, s));
            dist = min(dist, sdOctahedron(pos - ax_z * d, s));
            return dist;
    }
}

// 法線ベクトル
vec3 normal(vec3 pos, int select)
{
    return normalize(vec3(
        distance(pos + vec3(delta, 0.0, 0.0), select) - distance(pos - vec3(delta, 0.0, 0.0), select),
        distance(pos + vec3(0.0, delta, 0.0), select) - distance(pos - vec3(0.0, delta, 0.0), select),
        distance(pos + vec3(0.0, 0.0, delta), select) - distance(pos - vec3(0.0, 0.0, delta), select)
    ));
}

// レイマーチング
int try_raymarch(inout ray march_ray, out float trace_dist)
{
    trace_dist = 0.0;

    for(int i = 0; i < max_step; ++i)
    {
        float dist1 = distance(march_ray.pos, 1);
        if(dist1 < delta * 2.0) return 1;
        float dist2 = distance(march_ray.pos, 2);
        if(dist2 < delta * 2.0) return 2;
        march_ray.pos += march_ray.dir * min(dist1, dist2);
        trace_dist += min(dist1, dist2);
    }

    return 0;
}

// カメラの情報からレイを生成する
ray make_ray(vec3 pos, vec3 dir, vec3 up)
{
    vec2 uv = inUV * 2.0 - 1.0;
    uv.y *= resolution.y / resolution.x;

    vec3 side = cross(up, dir);
    ray march_ray;
    march_ray.pos = pos;
    march_ray.dir = normalize(uv.x * side + uv.y * up + dir);
    return march_ray;
}

// 背景に映し出す色
vec3 background()
{
    return vec3(0.0);
}

// メイン関数
void main(void)
{
    float a = pi / 12.0;

    // カメラの姿勢を決定する
    vec3 camera_pos = vec3(0.0, 5.0, -10.0);
    vec3 camera_dir = vec3(0.0, -sin(a), cos(a));
    vec3 camera_up = vec3(0.0, cos(a), sin(a));
    mat3 rotate = rodrigues(vec3(0.0, 1.0, 0.0), pi * time / 36.0);
    camera_pos *= rotate;
    camera_dir *= rotate;
    camera_up *= rotate;

    // レイを生成する
    ray march_ray = make_ray(
        camera_pos,
        camera_dir,
        camera_up
    );

    // レイマーチング
    float dist = 0.0;
    int collide = try_raymarch(march_ray, dist);

    vec3 pos = march_ray.pos;
    vec3 norm = normal(pos, collide);

    // 描画
    switch(collide)
    {
        case 1:
            {
                vec2 rep = vec2(2.0, 2.0 * sqrt3) * 2.0;
                vec2 a = mod(pos.xz, rep) - rep * 0.5;
                vec2 b = mod(pos.xz - rep * 0.5, rep) - rep * 0.5;
                vec2 id = pos.xz - (length(a) < length(b) ? a : b);

                float v = 1.0 - mod(length(id)- time * bpm * 0.5, 30.0) / 30.0;
                v = clamp(1.0 / (v * 3.0), 0.0, 1.0);
                vec3 texture = hsv2rgb(length(id) * 0.001 + time * 0.01, 1.0, v);

                v = clamp(v * 2.0 - 1.0, 0.0, 1.0);
                vec3 value = mix(vec3(dot(norm, light_env) - 0.7), texture, v);
                vec3 color = mix(value, background(), clamp(dist / 80.0, 0.0, 1.0));
                outOutput = vec4(color, 1.0);
                break;
            }
        case 2:
            {
                vec3 color = hsv2rgb(time * 0.01, 1.0, 1.0);
                vec3 value = vec3(dot(norm, light_env)) * color;
                outOutput = vec4(value, 1.0);
                break;
            }
        default:
            {
                outOutput = vec4(background(), 1.0);
                break;
            }
    }
}
