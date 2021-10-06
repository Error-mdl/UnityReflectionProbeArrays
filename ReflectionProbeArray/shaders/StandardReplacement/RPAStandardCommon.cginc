
#include "UnityCG.cginc"
#include "Lighting.cginc"
#include "AutoLight.cginc"
#include "UnityPBSLighting.cginc"
#include "../ProbeArrayReflections.cginc"

#ifdef UNITY_PASS_FORWARDBASE
UNITY_DECLARE_TEXCUBEARRAY(_ReflProbeArray);
float4 _ReflProbeArray_HDR;
UNITY_DECLARE_TEX2DARRAY(_ProbeParams);
#endif

struct vertexIn {
	float4 vertex : POSITION;
	float4 tangent : TANGENT;
	float3 normal : NORMAL;
	float4 uv0 : TEXCOORD0;
#ifdef LIGHTMAP_ON
	float2 uv1 : TEXCOORD1;
#endif
#ifdef UNITY_PASS_FORWARDBASE
	float4 uv2 : TEXCOORD2;
	float4 uv3 : TEXCOORD3;
#endif
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
	float4 pos : SV_POSITION;
	float3 normal : NORMAL;
	float4 tangent : TANGENT;
	float2 uv : TEXCOORD0;
	float3 wPos : TEXCOORD1;
	float3 bitangent : TEXCOORD2;
	SHADOW_COORDS(3)
#ifdef LIGHTMAP_ON
		float2 lightmapUV : LIGHTMAPUV;
#endif
	#ifdef UNITY_PASS_FORWARDBASE
	
	nointerpolation int4 probeIndex : PROBEID;
	nointerpolation float3 boundsMin : BMIN;
	nointerpolation float3 boundsMax : BMAX;
	#endif
	UNITY_VERTEX_OUTPUT_STEREO
};


float3 vertex_lighting(float3 vertexPos, float3 normal)
{
	float3 light = float3(0.0, 0.0, 0.0);
	for (int index = 0; index < 4; index++)
	{
		float4 lightPosition = float4(unity_4LightPosX0[index],
			unity_4LightPosY0[index],
			unity_4LightPosZ0[index], 1.0);

		float3 originToLightSource =
			lightPosition.xyz - vertexPos;
		float3 lightDirection = normalize(originToLightSource);
		float squaredDistance =
			dot(originToLightSource, originToLightSource);
		float attenuation = 1.0 / (1.0 +
			unity_4LightAtten0[index] * squaredDistance);
		float3 diffuseReflection = attenuation
			* unity_LightColor[index].rgb;
		diffuseReflection *= max(0.0, dot(normal, lightDirection));
		light += diffuseReflection;
	}
	return light;
}

void StdCommonVert(in vertexIn v, inout v2f o)
{
	o.wPos = mul(unity_ObjectToWorld, v.vertex);
	o.pos = UnityWorldToClipPos(o.wPos);
	o.normal = UnityObjectToWorldNormal(v.normal);
	o.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
	o.bitangent = cross(o.normal, o.tangent.xyz) * o.tangent.w;
	TRANSFER_SHADOW(o);
	o.uv = TRANSFORM_TEX(v.uv0.xy, _MainTex);
	#ifdef UNITY_PASS_FORWARDBASE
	#ifdef LIGHTMAP_ON
	o.lightmapUV = v.uv1 * unity_LightmapST.xy + unity_LightmapST.zw;
	#endif
	o.probeIndex = unpack4ShortsFrom2Floats(v.uv2.x, v.uv2.y);
	o.boundsMin = float3(v.uv2.z, v.uv2.w, v.uv3.x);
	o.boundsMax = v.uv3.yzw;
	#endif
}

float3 tanToWrldNormal(float3 tNormal, v2f i)
{
	float3x3 TangentToWorld = float3x3(i.tangent.x, i.bitangent.x, i.normal.x,
		i.tangent.y, i.bitangent.y, i.normal.y,
		i.tangent.z, i.bitangent.z, i.normal.z);

	float3 normal = normalize(mul(TangentToWorld, tNormal));
	return normal;
}

float4 StdCommonFrag(v2f i, float4 albedoCol, float3 normal, float smoothness, float metallic)
{
	UNITY_LIGHT_ATTENUATION(attenuation, i, i.wPos.xyz);

	float3 specularTint;
	float oneMinusReflectivity;

	float3 albedo = DiffuseAndSpecularFromMetallic(
		albedoCol, metallic, specularTint, oneMinusReflectivity
	);

	float3 viewDir = normalize(_WorldSpaceCameraPos - i.wPos);
	UnityLight light;
	
	light.color = attenuation * _LightColor0.rgb;
	light.dir = normalize(UnityWorldSpaceLightDir(i.wPos));
	UnityIndirect indirectLight;
	#ifdef UNITY_PASS_FORWARDADD
	indirectLight.diffuse = indirectLight.specular = 0;
	#else

	#ifdef LIGHTMAP_ON	
	indirectLight.diffuse = float3(0, 0, 0);
	#else
	indirectLight.diffuse = max(0, ShadeSH9(float4(normal, 1)));
	#endif

	float3 reflectionDir = reflect(-viewDir, normal);
	
	ProbeArray_GlossyEnvironmentData gloss;
	gloss.probeIndicies = i.probeIndex;
	gloss.meshBoundsMin = i.boundsMin;
	gloss.meshBoundsMax = i.boundsMax;
	gloss.perceptualRoughness = 1.0 - smoothness;
	GetProbeUVWsAndWeights(UNITY_PASS_TEX2DARRAY(_ProbeParams), gloss, float4(i.wPos,1), reflectionDir, 1.0);

	indirectLight.specular = ProbeArray_GlossyEnvironment(UNITY_PASS_TEXCUBEARRAY(_ReflProbeArray), _ReflProbeArray_HDR, gloss);
	#endif

	float3 col = UNITY_BRDF_PBS(
		albedo, specularTint,
		oneMinusReflectivity, smoothness,
		normal, viewDir,
		light, indirectLight
	);


#ifdef UNITY_PASS_FORWARDBASE
#ifdef LIGHTMAP_ON
	float3 lm = DecodeLightmap(UNITY_SAMPLE_TEX2D(unity_Lightmap, i.lightmapUV.xy));
	col.rgb += (1 - metallic) * albedoCol.rgb * lm;
#endif
	col.rgb += (1 - metallic) * albedoCol.rgb * vertex_lighting(i.wPos, normal);
#endif

#ifdef _ALPHAPREMULTIPLY_ON
	col.rgb *= albedoCol.a;
	//albedoCol.a = 1 - oneMinusReflectivity + albedoCol.a * oneMinusReflectivity;
#endif

	#ifdef UNITY_PASS_FORWARDADD
	return float4(col, 0);
	#else
	return float4(col, albedoCol.a);
	#endif
}

