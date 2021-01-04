/*
Copyright(c) 2016-2020 Panos Karabelas

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions :

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

// = INCLUDES ======
#include "BRDF.hlsl"
#include "Fog.hlsl"
//==================

float4 mainPS(Pixel_PosUv input) : SV_TARGET
{
    float4 color            = float4(0.0f, 0.0f, 0.0f, 1.0f);
    const float2 uv         = input.uv;
    const int2 screen_pos   = uv * g_resolution;

    // Sample some textures
    const float4 normal             = tex_normal.Load(int3(screen_pos, 0));
    const float depth               = tex_depth.Load(int3(screen_pos, 0)).r;
    const float3 light_volumetric   = tex_light_volumetric.Load(int3(screen_pos, 0)).rgb;

    // Get view direction
    const float3 camera_to_pixel = get_view_direction(depth, uv);

    // Get material ID
    const int mat_id = round(normal.a * 65535);

    // Fog
    float3 position                 = get_position(uv);
    float camera_to_pixel_length    = length(position - g_camera_position.xyz);
    float3 fog                      = get_fog_factor(position.y, camera_to_pixel_length);
    
    [branch]
    if (mat_id == 0)
    {
        color.rgb   += tex_environment.Sample(sampler_bilinear_clamp, direction_sphere_uv(camera_to_pixel)).rgb;
        color.rgb   *= saturate(g_directional_light_intensity / 128000.0f);
        fog         *= luminance(color.rgb);
    }
    else
    {
        // Sample from textures
        float3 light_diffuse    = tex_light_diffuse.Load(int3(screen_pos, 0)).rgb;
        float3 light_specular   = tex_light_specular.Load(int3(screen_pos, 0)).rgb;
        float4 sample_material  = tex_material.Load(int3(screen_pos, 0));
        
        #if TRANSPARENT
        float2 sample_ssr       = 0.0f; // we don't do ssr for transparents
        float sample_hbao       = 1.0f; // we don't do ao for transparents
        #else
        float2 sample_ssr       = tex_ssr.Load(int3(screen_pos, 0)).xy;
        float sample_hbao       = tex_hbao.SampleLevel(sampler_point_clamp, uv, 0).r; // if hbao is disabled, the texture will be 1x1 white pixel, so we use a sampler
        #endif

        // Create material
        Material material;
        material.albedo     = tex_albedo.Load(int3(screen_pos, 0));
        material.roughness  = sample_material.r;
        material.metallic   = sample_material.g;
        material.emissive   = sample_material.b;
        material.F0         = lerp(0.04f, material.albedo.rgb, material.metallic);
        
        // Light - Ambient
        float3 light_ambient = saturate(g_directional_light_intensity / 128000.0f);

        // Modulate fog with ambient light
        fog *= light_ambient * 0.25f;

        // Apply ambient occlusion to ambient light
        #if SSGI
        light_ambient *= sample_hbao;
        #else
        light_ambient *= MultiBounceAO(sample_hbao, material.albedo.rgb);
        #endif

        // Light - IBL/SSR
        float3 light_ibl_ssr = 0.0f;
        {
            // IBL
            float3 diffuse_energy   = 1.0f;
            light_ibl_ssr           = Brdf_Specular_Ibl(material, normal.xyz, camera_to_pixel, diffuse_energy) * light_ambient;
            light_ibl_ssr           += Brdf_Diffuse_Ibl(material, normal.xyz) * light_ambient * diffuse_energy; // Tone down diffuse such as that only non metals have it

            // SSR
            if (g_ssr_enabled && any(sample_ssr))
            {
                float3 light_ssr = tex_frame.SampleLevel(sampler_bilinear_clamp, sample_ssr, 0).rgb;

                // Blend with IBL
                light_ibl_ssr = lerp(light_ibl_ssr, light_ssr, 1.0f - material.roughness);
            }
        }

        // Light - Transparenct/Refraction
        float3 light_refraction = 0.0f;
        #if TRANSPARENT
        {
            float ior               = 1.5; // glass
            float2 normal2D         = mul((float3x3)g_view, normal.xyz).xy;
            float2 refraction_uv    = uv + normal2D * ior * 0.03f;
        
            // Only refract what's behind the surface
            [branch]
            if (get_linear_depth(refraction_uv) > get_linear_depth(depth))
            {
                light_refraction = tex_frame.SampleLevel(sampler_bilinear_clamp, refraction_uv, 0).rgb;
            }
            else
            {
                light_refraction = tex_frame.SampleLevel(sampler_bilinear_clamp, uv, 0).rgb;
            }
        
            // Increase refraction/transparency as the material more transparent
            light_refraction *= 1.0f - material.albedo.a;
        }
        #endif

        // Accumulate diffuse and specular light
        color.rgb += material.albedo.rgb * material.albedo.a * (light_diffuse + light_specular);

        // Accumulate ssr and refraction/transparency
        color.rgb += light_ibl_ssr + light_refraction;
    }

    // Accumulate regular and volumetric fog
    color.rgb += light_volumetric;
    color.rgb += fog;

    return saturate_16(color);
}