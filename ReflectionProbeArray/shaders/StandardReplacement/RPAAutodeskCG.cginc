
uniform float4 _Color;
UNITY_DECLARE_TEX2D(_MainTex);
//uniform sampler2D _MainTex;
uniform float4 _MainTex_ST;
UNITY_DECLARE_TEX2D_NOSAMPLER(_MetallicGlossMap);
//uniform sampler2D _MetallicGlossMap;
uniform float4 _MetallicGlossMap_ST;
//uniform sampler2D _SpecGlossMap;
//uniform float4 _SpecGlossMap_ST;
UNITY_DECLARE_TEX2D_NOSAMPLER(_BumpMap);
uniform float4 _BumpMap_ST;
uniform float _Cutoff;
uniform float _Smoothness;
uniform float _Metallic;

#include "RPAStandardCommon.cginc"


v2f vert(vertexIn v)
{
	v2f o;

	UNITY_SETUP_INSTANCE_ID(v);
	UNITY_INITIALIZE_OUTPUT(v2f, o);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	StdCommonVert(v, o);

	return o;
}


float4 frag(v2f i) : SV_TARGET
{
	float4 albedoCol = UNITY_SAMPLE_TEX2D(_MainTex, i.uv) * _Color;
	float4 metallicGlossMap = UNITY_SAMPLE_TEX2D_SAMPLER(_MetallicGlossMap, _MainTex, i.uv);
	//float4 specGlossMap = tex2D(_SpecGlossMap, i.uv);
	float3 tNormal = UnpackNormal(UNITY_SAMPLE_TEX2D_SAMPLER(_BumpMap, _MainTex, i.uv));

	float3x3 TangentToWorld = float3x3(i.tangent.x, i.bitangent.x, i.normal.x,
									   i.tangent.y, i.bitangent.y, i.normal.y,
									   i.tangent.z, i.bitangent.z, i.normal.z);
	
	float3 normal = normalize(mul(TangentToWorld, tNormal));

	float smoothness = (1.0 - metallicGlossMap.g) * _Smoothness;
	
	float metallic = metallicGlossMap.r * _Metallic;

	float4 color = StdCommonFrag(i, albedoCol, normal, smoothness, metallic);
	return color;
}

