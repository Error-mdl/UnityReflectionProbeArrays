// Based on d4rkpl4y3r's BRDF PBS Macro
Shader "Reflection Probe Array/RPA Opaque"
{
	Properties
	{
		[Enum(Off, 0, Front, 1, Back, 2)] _Culling ("Culling Mode", Int) = 2
		[KeywordEnum(Smoothness, Roughness)] _surface ("Smoothness Mode", Float) = 0
		_MainTex("Albedo Texture", 2D) = "white" {}
		_Color("Albedo Color", color) = (1,1,1,1)
		_MetallicGlossMap ("Metallic Gloss Map", 2D) = "white" {}
		_BumpMap("Normal Map", 2D) = "bump" {}
		[hdr] _Color("Albedo", Color) = (1,1,1,1)
		[Gamma] _Metallic("Metallic", Range(0, 1)) = 0
		_Smoothness("Smoothness/Roughness", Range(0, 1)) = 1
		_ReflProbeArray("Reflection Probe Array", CUBEArray) = "black" {}
		_ProbeParams("Reflection Probe Params", 2DArray) = "black" {}
		_FacingWallMin("Box Projection Wall Fade Min Distance", float) = 0
		_FacingWallMax("Box Projection Wall Fade Max Distance", float) = 0.1
	}
	SubShader
	{
		Tags
		{
			"RenderType"="Opaque"
			"Queue"="Geometry"
		}

		Cull [_Culling]

		Pass
		{
			Tags { "LightMode" = "ForwardBase" }
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase_fullshadows
			#pragma multi_compile UNITY_PASS_FORWARDBASE
			#pragma multi_compile _ LIGHTMAP_ON
			#pragma multi_compile_instancing
			#pragma multi_compile_local _ _SURFACE_SMOOTHNESS _SURFACE_ROUGHNESS; 
			#pragma target 5.0
			#include "RPAStandardCG.cginc"
			ENDCG
		}

		Pass
		{
			Tags { "LightMode" = "ForwardAdd" }
			Blend One One
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdadd_fullshadows
			#pragma multi_compile_instancing
			#pragma multi_compile UNITY_PASS_FORWARDADD
			#pragma multi_compile_local _ _SURFACE_SMOOTHNESS _SURFACE_ROUGHNESS; 
			#pragma target 5.0
			#include "RPAStandardCG.cginc"
			ENDCG
		}

		Pass
		{
			Tags { "LightMode" = "ShadowCaster" }
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_shadowcaster
			#pragma multi_compile UNITY_PASS_SHADOWCASTER
			#pragma target 5.0

			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"
			#include "UnityPBSLighting.cginc"

			uniform float4 _Color;
			uniform float _Metallic;
			uniform float _Smoothness;
			uniform sampler2D _MainTex;
			uniform float4 _MainTex_ST;
			uniform float _Cutoff;

			struct v2f
			{
				V2F_SHADOW_CASTER;
			};

			v2f vert(appdata_base v)
			{
				v2f o;
				
				TRANSFER_SHADOW_CASTER_NOPOS(o, o.pos);
		
				return o;
			}

			float4 frag(v2f i) : SV_Target
			{
				SHADOW_CASTER_FRAGMENT(i)
			}
			
		ENDCG
		}

		Pass
		{
			Name "META_BAKERY"
			Tags {"LightMode" = "Meta"}
			Cull Off
			CGPROGRAM
			// Must use vert_bakerymt vertex shader
			#pragma vertex vert_bakerymt
			#pragma fragment frag_customMeta
			#pragma shader_feature EDITOR_VISUALIZATION
			#include "RPAStandardMeta.cginc"
			ENDCG
		}
	}
}
