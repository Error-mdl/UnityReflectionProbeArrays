
uniform float4 _Color;
UNITY_DECLARE_TEX2D(_MainTex);
uniform float4 _MainTex_ST;
UNITY_DECLARE_TEX2D_NOSAMPLER(_MetallicGlossMap);
UNITY_DECLARE_TEX2D_NOSAMPLER(_BumpMap);
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
	//float4 metallicGlossMap = tex2D(_MetallicGlossMap, i.uv);
	float4 metallicGlossMap = UNITY_SAMPLE_TEX2D_SAMPLER(_MetallicGlossMap, _MainTex, i.uv);
	float3 tNormal = UnpackNormal(UNITY_SAMPLE_TEX2D_SAMPLER(_BumpMap, _MainTex, i.uv));

	float3x3 TangentToWorld = float3x3(i.tangent.x, i.bitangent.x, i.normal.x,
									   i.tangent.y, i.bitangent.y, i.normal.y,
									   i.tangent.z, i.bitangent.z, i.normal.z);
	
	float3 normal = normalize(mul(TangentToWorld, tNormal));

	//clip(texCol.a - _Cutoff);

	#ifdef _SURFACE_SMOOTHNESS
	float smoothness = metallicGlossMap.g * _Smoothness;
	#else
	float smoothness = (1.0 - metallicGlossMap.a) * _Smoothness;
	#endif
	float metallic = metallicGlossMap.r * _Metallic;
	
	float4 color = StdCommonFrag(i, albedoCol, normal, smoothness, metallic);
	return color;
}

