// = INCLUDES ========
#include "Common.hlsl"
//====================

Texture2D sourceTexture 		: register(t0);
Texture2D sourceTexture2 		: register(t1);
SamplerState pointSampler 		: register(s0);
SamplerState bilinearSampler 	: register(s1);

cbuffer DefaultBuffer
{
    matrix mTransform;
    float2 resolution;
    float2 padding;
};

struct VS_Output
{
    float4 position : SV_POSITION;
    float2 uv 		: TEXCOORD;
};

// Vertex Shader
VS_Output DirectusVertexShader(Vertex_PosUv input)
{
    VS_Output output;
	
    input.position.w = 1.0f;
    output.position = mul(input.position, mTransform);
    output.uv = input.uv;
	
    return output;
}

/*------------------------------------------------------------------------------
								[Pixel Shader]
------------------------------------------------------------------------------*/
float4 DirectusPixelShader(VS_Output input) : SV_TARGET
{
    float2 texCoord 	= input.uv;
    float4 color 		= float4(0.0f, 0.0f, 0.0f, 1.0f);
    float2 texelSize 	= float2(1.0f / resolution.x, 1.0f / resolution.y);
	
#if PASS_FXAA
	color.rgb = FXAA(texCoord, texelSize, sourceTexture, bilinearSampler);
#endif

#if PASS_CHROMATIC_ABERRATION
	color.rgb = ChromaticAberrationPass(texCoord, texelSize, sourceTexture, bilinearSampler);
#endif

#if PASS_SHARPENING
	color.rgb 	= LumaSharpen(texCoord, sourceTexture, bilinearSampler, resolution);
	color.a 	= 1.0f;
#endif
	
#if PASS_BLUR_BOX
	color = Pass_BlurBox(texCoord, texelSize, 4, sourceTexture, pointSampler);
#endif

#if PASS_BLUR_GAUSSIAN_H
	color = Pass_BlurGaussian(texCoord, sourceTexture, pointSampler, resolution, float2(1.0f, 0.0f), 3.0f);
#endif

#if PASS_BLUR_GAUSSIAN_V
	color = Pass_BlurGaussian(texCoord, sourceTexture, pointSampler, resolution, float2(0.0f, 1.0f), 3.0f);
#endif

#if PASS_BRIGHT
	color 				= sourceTexture.Sample(pointSampler, input.uv);
    float luminance 	= dot(color.rgb, float3(0.2126f, 0.7152f, 0.0722f));	
	color 				= luminance > 1.0f ? color : float4(0.0f, 0.0f, 0.0f, color.a); // maintain alpha as it holds FXAA luma
#endif

#if PASS_BLEND_ADDITIVE
	float4 sourceColor 	= sourceTexture.Sample(pointSampler, input.uv);
	float4 sourceColor2 = sourceTexture2.Sample(pointSampler, input.uv);
	color 				= sourceColor + sourceColor2;
#endif

#if PASS_CORRECTION
	color 		= sourceTexture.Sample(pointSampler, texCoord);
	color.rgb 	= ACESFitted(color);
	color 		= ToGamma(color);
#endif

    return color;
}