﻿ Shader "Maxwell/CombinedProcedural" {
	SubShader {
		Tags { "RenderType"="Opaque" }
		LOD 200

		
	// ------------------------------------------------------------
	// Surface shader code generated out of a CGPROGRAM block:
CGINCLUDE
// Upgrade NOTE: excluded shader from OpenGL ES 2.0 because it uses non-square matrices
#pragma exclude_renderers gles
#pragma target 5.0
#include "HLSLSupport.cginc"
#include "UnityShaderVariables.cginc"
#include "UnityShaderUtilities.cginc"
#include "UnityCG.cginc"
#include "Lighting.cginc"
#include "UnityMetaPass.cginc"
#include "AutoLight.cginc"
#include "UnityPBSLighting.cginc"
#include "CGINC/Procedural.cginc"
struct Property{
    float _SpecularIntensity;
	float _MetallicIntensity;
    float4 _EmissionColor;
	float _EmissionMultiplier;
	float _Occlusion;
	float _Glossiness;
	float4 _Color;
};
	Texture2DArray<half4> _BumpMap; SamplerState sampler_BumpMap;
	Texture2DArray<half3> _SpecularMap; SamplerState sampler_SpecularMap;
	Texture2DArray<half> _OcclusionMap; SamplerState sampler_OcclusionMap;
	Texture2DArray<half4> _MainTex; SamplerState sampler_MainTex;
	StructuredBuffer<Property> _PropertiesBuffer;
	
	void surf (float2 uv, uint index, inout SurfaceOutputStandardSpecular o) {
		Property prop = _PropertiesBuffer[index];
		half4 c = _MainTex.Sample(sampler_MainTex, float3(uv, index)) * prop._Color;
		o.Albedo = c.rgb;
		o.Alpha = c.a;
		o.Occlusion = lerp(1, _OcclusionMap.Sample(sampler_OcclusionMap, float3(uv, index)).r, prop._Occlusion);
		half3 spec = _SpecularMap.Sample(sampler_SpecularMap, float3(uv, index));
		o.Specular = lerp(prop._SpecularIntensity * spec.r, o.Albedo * prop._SpecularIntensity * spec.r, prop._MetallicIntensity * spec.g); 
		o.Smoothness = prop._Glossiness * spec.b;
		o.Normal = UnpackNormal(_BumpMap.Sample(sampler_BumpMap, float3(uv, index)));
		o.Emission = prop._EmissionColor * prop._EmissionMultiplier;
	}


#define GetScreenPos(pos) ((float2(pos.x, pos.y) * 0.5) / pos.w + 0.5)


half4 ProceduralStandardSpecular_Deferred (SurfaceOutputStandardSpecular s, float3 viewDir, out half4 outGBuffer0, out half4 outGBuffer1, out half4 outGBuffer2)
{
    // energy conservation
    float oneMinusReflectivity;
    s.Albedo = EnergyConservationBetweenDiffuseAndSpecular (s.Albedo, s.Specular, /*out*/ oneMinusReflectivity);
    // RT0: diffuse color (rgb), occlusion (a) - sRGB rendertarget
    outGBuffer0 = half4(s.Albedo, s.Occlusion);
    // RT1: spec color (rgb), smoothness (a) - sRGB rendertarget
    outGBuffer1 = half4(s.Specular, s.Smoothness);
    // RT2: normal (rgb), --unused, very low precision-- (a)
    outGBuffer2 = half4(s.Normal * 0.5f + 0.5f, 0);
    half4 emission = half4(s.Emission, 1);
    return emission;
}
float4x4 _LastVp;
float4x4 _NonJitterVP;
inline half2 CalculateMotionVector(float4x4 lastvp, half3 worldPos, half2 screenUV)
{
	half4 lastScreenPos = mul(lastvp, half4(worldPos, 1));
	half2 lastScreenUV = GetScreenPos(lastScreenPos);
	return screenUV - lastScreenUV;
}

struct v2f_surf {
  UNITY_POSITION(pos);
  float2 pack0 : TEXCOORD0; 
  float4 worldTangent : TEXCOORD1;
  float4 worldBinormal : TEXCOORD2;
  float4 worldNormal : TEXCOORD3;
  float3 worldViewDir : TEXCOORD4;
  nointerpolation uint objectIndex : TEXCOORD5;
};
float4 _MainTex_ST;
v2f_surf vert_surf (uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) 
{
  	Point v = getVertex(vertexID, instanceID);
  	v2f_surf o;
  	o.pack0 = v.texcoord;
	o.objectIndex = v.objIndex;
  	o.pos = mul(UNITY_MATRIX_VP, float4(v.vertex, 1));
  	o.worldTangent = float4( v.tangent.xyz, v.vertex.x);
	o.worldNormal =float4(v.normal, v.vertex.z);
  	float tangentSign = v.tangent.w;
  	o.worldBinormal = float4(cross(v.normal, o.worldTangent.xyz) * tangentSign, v.vertex.y);
  	o.worldViewDir = UnityWorldSpaceViewDir(v.vertex);
  	return o;
}
float4 unity_Ambient;

// fragment shader
void frag_surf (v2f_surf IN,
    out half4 outGBuffer0 : SV_Target0,
    out half4 outGBuffer1 : SV_Target1,
    out half4 outGBuffer2 : SV_Target2,
    out half4 outEmission : SV_Target3,
	out half2 outMotionVector : SV_Target4,
	out float outDepth : SV_Target5
) {
  // prepare and unpack data
  float3 worldPos = float3(IN.worldTangent.w, IN.worldBinormal.w, IN.worldNormal.w);
  float3 worldViewDir = normalize(IN.worldViewDir);
  SurfaceOutputStandardSpecular o;
  half3x3 wdMatrix= half3x3(normalize(IN.worldTangent.xyz), normalize(IN.worldBinormal.xyz), normalize(IN.worldNormal.xyz));
  // call surface function
  surf (IN.pack0, IN.objectIndex, o);
  o.Normal = normalize(mul(o.Normal, wdMatrix));
  outEmission = ProceduralStandardSpecular_Deferred (o, worldViewDir, outGBuffer0, outGBuffer1, outGBuffer2); //GI neccessary here!
  outDepth = IN.pos.z;
  //Calculate Motion Vector
  half4 screenPos = mul(_NonJitterVP, float4(worldPos, 1));
  half2 screenUV = GetScreenPos(screenPos);
  outMotionVector = CalculateMotionVector(_LastVp, worldPos, screenUV);
}

ENDCG

//Pass 0 deferred
Pass {
stencil{
  Ref 1
  comp always
  pass replace
}
ZTest Less
CGPROGRAM

#pragma vertex vert_surf
#pragma fragment frag_surf
#pragma exclude_renderers nomrt
#define UNITY_PASS_DEFERRED
ENDCG
}
}
CustomEditor "SpecularShaderEditor"
}

