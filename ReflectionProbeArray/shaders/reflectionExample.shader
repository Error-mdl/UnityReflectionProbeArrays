Shader "Unlit/reflectionTest"
{
    Properties
    {
       _ReflProbeArray("Reflection Probe Array", CUBEArray) = "black" {}
       _ProbeParams("Reflection Probe Params", 2DArray) = "black" {}

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma target 5.0
            #include "UnityCG.cginc"
            #include "ProbeArrayReflections.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float4 uv2 : TEXCOORD2;
                float4 uv3 : TEXCOORD3;

            };

            struct v2f
            {
                nointerpolation int4 probeIndex : TEXCOORD2;
                nointerpolation float3 boundsMin : TEXCOORD3;
                nointerpolation float3 boundsMax : TEXCOORD4;

                float4 vertex : SV_POSITION;
                float4 worldPos : WORLDPOS;

                float3 normal : NORMAL;
            };

            UNITY_DECLARE_TEXCUBEARRAY(_ReflProbeArray);
            float4 _ReflProbeArray_HDR;
            UNITY_DECLARE_TEX2DARRAY(_ProbeParams);

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                //o.probeIndex = int4(asint(v.uv2.x), asint(v.uv2.y), asint(v.uv2.z), asint(v.uv2.w));
                o.probeIndex = unpack4ShortsFrom2Floats(v.uv2.x, v.uv2.y);
                //o.probeWeights = v.uv3;
                o.boundsMin = float3(v.uv2.z, v.uv2.w, v.uv3.x);
                o.boundsMax = v.uv3.yzw;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                ProbeArray_GlossyEnvironmentData gloss;
                gloss.probeIndicies = i.probeIndex;
                gloss.meshBoundsMin = i.boundsMin;
                gloss.meshBoundsMax = i.boundsMax;
                gloss.perceptualRoughness = 0;
                float3 cameraToPixel = normalize(i.worldPos - _WorldSpaceCameraPos);
                float3 reflection = reflect(cameraToPixel, normalize(i.normal));
                GetProbeUVWsAndWeights(UNITY_PASS_TEX2DARRAY(_ProbeParams), gloss, i.worldPos, reflection, 1.0);

                // sample the texture
                float3 col = ProbeArray_GlossyEnvironment(UNITY_PASS_TEXCUBEARRAY(_ReflProbeArray), _ReflProbeArray_HDR, gloss);
                //col = float3(
                //    frac(length(gloss.UVW0)),0,0);
                //return float4(i.probeIndex.x == 2, 0, 0, 1);
                return float4(col,1);
            }
            ENDCG
        }
    }
}
