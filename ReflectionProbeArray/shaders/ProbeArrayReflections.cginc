#ifndef UNITY_IMAGE_BASED_LIGHTING_INCLUDED

#include "UnityImageBasedLighting.cginc" // needed for the perceptualRoughnessToMipmapLevel function

#endif

/* An example of how to define the constants for the reflection probY_DECLARE_TEXCUBEARRAY(_ReflProbeArray);
float4 _ReflProbeArray_HDR;
UNITY_DECLARE_TEX2DARRAY(_ProbeParams);
*/


/* Utility function for unpacking the four unsigned short integers from two floats
   Use this to extract the reflextion probe indicies from the first two floats of uv2 */
uint4 unpack4ShortsFrom2Floats(float packedFloat1, float packedFloat2)
{
	uint packedInt1 = asuint(packedFloat1);
	uint packedInt2 = asuint(packedFloat2);
	uint4 num;
	num.x = packedInt1 & 0x0000FFFF;
	num.y = packedInt1 >> 16;
	num.z = packedInt2 & 0x0000FFFF;
	num.w = packedInt2 >> 16;
	return num;
}

/* Utility function for unpacking the four half-precision floats from two full floats 
   Not used anymore, was using it to extract half-precision probe weights from the uvs*/
float4 unpack4HalfsFrom2Floats(float packedFloat1, float packedFloat2)
{
	uint packedInt1 = asuint(packedFloat1);
	uint packedInt2 = asuint(packedFloat2);
	float4 num;
	num.x = asfloat(f16tof32(packedInt1 & 0x0000FFFF));
	num.y = asfloat(f16tof32(packedInt1 >> 16));
	num.z = asfloat(f16tof32(packedInt2 & 0x0000FFFF));
	num.w = asfloat(f16tof32(packedInt2 >> 16));
	return num;
}



struct ProbeArray_GlossyEnvironmentData
{
	uint4	probeIndicies;
	float4	probeWeights;
	float3	meshBoundsMin;
	float3	meshBoundsMax;
    half    perceptualRoughness;
    float3  UVW0;
	float3  UVW1;
	float3  UVW2;
	float3  UVW3;
};

/** isPointInBox
 * 
 *  Determine if a given worldspace position is inside an axis aligned bounding box defined by its minimum
 *  and maximum corners.
 *
 */
bool isPointInBox(float3 pos, float3 boxMin, float3 boxMax)
{
	return (pos.x > boxMin.x) && (pos.x < boxMax.x) &&
		(pos.y > boxMin.y) && (pos.y < boxMax.y) &&
		(pos.z > boxMin.z) && (pos.z < boxMax.z);
}


/** SdBox
 *
 *  Signed Distance function of a box. Adapted from https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm 
 *
 */

float SdBox(float3 pos, float3 boxMin, float3 boxMax)
{
	float3 boxCenter = (boxMin + boxMax) * 0.5;
	float3 boxRadii = boxMax - boxCenter;
	pos = pos - boxCenter;
	float3 q = abs(pos) - boxRadii;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

/** ProbeWeightFromBounds
 *
 * Determines the weight of a probe at a given position using the distance to its bounding box.
 * Points inside the box have a weight of 1, and linearly fall off to 0 at a distance from the
 * box determined by the falloff parameter.
 *
 */
float ProbeWeightFromBounds(float3 pos, float3 boundsMin, float3 boundsMax, float falloff)
{
	float dist = SdBox(pos, boundsMin, boundsMax);
	float weight = saturate((falloff - dist) / falloff);
	weight *= weight;
	weight = max(1E-4, weight);
	return weight;
}

/** BoxProjection
 *
 *  For a given reflection vector and reflection probe, if the probe is marked as using box projection
 *  (4th component of the probe's position > 0) find the intersection of the reflected ray with the probe's
 *  bounding box and then return the vector connecting the intersection point with the probe origin.
 *  Otherwise return the original direction.
 *
 *  Copied from the sacred texts https://catlikecoding.com/unity/tutorials/rendering/part-8/
 *
 */

float3 BoxProjection (float3 direction, float3 position,
	float4 cubemapPosition, float3 boxMin, float3 boxMax) 
{
	if (cubemapPosition.w > 0) {
		float3 factors = ((direction > 0 ? boxMax : boxMin) - position) / direction;
		float scalar = min(min(factors.x, factors.y), factors.z);
		direction = direction * scalar + (position - cubemapPosition);
	}
	
	return direction;
}



void GetWeightUVW(UNITY_ARGS_TEX2DARRAY(probeParams), inout float probeWeight, inout float3 probeUVW, float4 pixelWorldPos, float3 reflectionDir,
	float falloff, float3 meshBoundsMin, float3 meshBoundsMax, int probeIndex)
{
	float4 position = UNITY_SAMPLE_TEX2DARRAY_LOD(probeParams, float3(0.125, 0.5, probeIndex), 0);
	float3 boxMin = UNITY_SAMPLE_TEX2DARRAY_LOD(probeParams, float3(0.375, 0.5, probeIndex), 0).xyz;
	float3 boxMax = UNITY_SAMPLE_TEX2DARRAY_LOD(probeParams, float3(0.625, 0.5, probeIndex), 0).xyz;

	probeWeight = ProbeWeightFromBounds(pixelWorldPos, boxMin, boxMax, falloff); // determine the falloff before expanding the bounding box to cover the mesh

	boxMin = min(boxMin, meshBoundsMin);
	boxMax = max(boxMax, meshBoundsMax);

	probeUVW = BoxProjection(reflectionDir, pixelWorldPos, position, boxMin, boxMax);

	// blend out the probe if the ray travels less than a cm, which usually happens where a probe just encapsulates a wall which makes the reflection look painted on.
	probeWeight *= smoothstep(0, 0.1, length(probeUVW + position.xyz - pixelWorldPos));
}

/** GetProbeUVWsAndWeights
 *  
 *  Given a glossy environment data with the probe weights initialized, the worldspace position of the pixel, and the reflection vector, calculate
 *  the box projection reflection vectors and set the probe weights by its distance to the probe bounds.
 *
 */


void GetProbeUVWsAndWeights(UNITY_ARGS_TEX2DARRAY(probeParams), inout ProbeArray_GlossyEnvironmentData glossIn, float4 pixelWorldPos, float3 reflectionDir, float falloff)
{	
	/* Initialize the reflection directions */
	glossIn.UVW0 = glossIn.UVW1 = glossIn.UVW2 = glossIn.UVW3 = reflectionDir;

	/* Read each probe's parameters from the probe parameter texture array, and determine if the pixel is within the probe's
	 * bounding box. If it is, compute the box projection of the reflection direction. Otherwise decimate the weight if it is
	 * the first probe, or set it to 0 for the other probes. Always determine the reflection direction of the first probe,
	 * only do so for the others if the probe's base weight is greater than the minimum weight as we won't be sampling them
	 * if they have below the min weight */

	GetWeightUVW(UNITY_PASS_TEX2DARRAY(probeParams), glossIn.probeWeights.x, glossIn.UVW0, pixelWorldPos, reflectionDir,
		falloff, glossIn.meshBoundsMin, glossIn.meshBoundsMax, glossIn.probeIndicies.x);


	GetWeightUVW(UNITY_PASS_TEX2DARRAY(probeParams), glossIn.probeWeights.y, glossIn.UVW1, pixelWorldPos, reflectionDir,
		falloff, glossIn.meshBoundsMin, glossIn.meshBoundsMax, glossIn.probeIndicies.y);

	GetWeightUVW(UNITY_PASS_TEX2DARRAY(probeParams), glossIn.probeWeights.z, glossIn.UVW2, pixelWorldPos, reflectionDir,
		falloff, glossIn.meshBoundsMin, glossIn.meshBoundsMax, glossIn.probeIndicies.z);

	GetWeightUVW(UNITY_PASS_TEX2DARRAY(probeParams), glossIn.probeWeights.w, glossIn.UVW3, pixelWorldPos, reflectionDir, 
		falloff, glossIn.meshBoundsMin, glossIn.meshBoundsMax, glossIn.probeIndicies.w);
	 
}


/* Modified from Unity_GlossyEnvironment in UnityImageBasedLighting.cginc, with normal cubemap functions replaced with their cubemap array counterparts */
half3 ProbeArray_GlossyEnvironment (UNITY_ARGS_TEXCUBEARRAY(tex), half4 hdr, ProbeArray_GlossyEnvironmentData glossIn)
{
    half perceptualRoughness = glossIn.perceptualRoughness;

/* Disabled perceptual roughness calculations from the original function, maybe it might be better than the approximation? */
// TODO: CAUTION: remap from Morten may work only with offline convolution, see impact with runtime convolution!
// For now disabled
#if 0
    float m = PerceptualRoughnessToRoughness(perceptualRoughness); // m is the real roughness parameter
    const float fEps = 1.192092896e-07F;        // smallest such that 1.0+FLT_EPSILON != 1.0  (+1e-4h is NOT good here. is visibly very wrong)
    float n =  (2.0/max(fEps, m*m))-2.0;        // remap to spec power. See eq. 21 in --> https://dl.dropboxusercontent.com/u/55891920/papers/mm_brdf.pdf

    n /= 4;                                     // remap from n_dot_h formulatino to n_dot_r. See section "Pre-convolved Cube Maps vs Path Tracers" --> https://s3.amazonaws.com/docs.knaldtech.com/knald/1.0.0/lys_power_drops.html

    perceptualRoughness = pow( 2/(n+2), 0.25);      // remap back to square root of real roughness (0.25 include both the sqrt root of the conversion and sqrt for going from roughness to perceptualRoughness)
#else
    // MM: came up with a surprisingly close approximation to what the #if 0'ed out code above does.
    perceptualRoughness = perceptualRoughness*(1.7 - 0.7*perceptualRoughness);
#endif


    half mip = perceptualRoughnessToMipmapLevel(perceptualRoughness);
	
	half3 probe0 = float3(0,0,0);
	half3 probe1 = float3(0,0,0);
	half3 probe2 = float3(0,0,0);
	half3 probe3 = float3(0,0,0);
	
	/* Sample the first reflection probe */
    
    half4 rgbm0 = UNITY_SAMPLE_TEXCUBEARRAY_LOD(tex, float4(glossIn.UVW0, glossIn.probeIndicies.x), mip);
	probe0 = DecodeHDR(rgbm0, hdr);

	/* Sample the other reflection probes if their weights are greater than the min weight*/
	UNITY_BRANCH if (glossIn.probeWeights.y > 0)
	{
		half4 rgbm1 = UNITY_SAMPLE_TEXCUBEARRAY_LOD(tex, float4(glossIn.UVW1, glossIn.probeIndicies.y), mip);
		probe1 = DecodeHDR(rgbm1, hdr);
	}
	UNITY_BRANCH if (glossIn.probeWeights.z > 0)
	{
		half4 rgbm2 = UNITY_SAMPLE_TEXCUBEARRAY_LOD(tex, float4(glossIn.UVW2, glossIn.probeIndicies.z), mip);
		probe2 = DecodeHDR(rgbm2, hdr);
	}
	UNITY_BRANCH if (glossIn.probeWeights.w > 0)
	{
		half4 rgbm3 = UNITY_SAMPLE_TEXCUBEARRAY_LOD(tex, float4(glossIn.UVW3, glossIn.probeIndicies.w), mip);
		probe3 = DecodeHDR(rgbm3, hdr);
	}
	
	half3 probeMix = (probe0 * glossIn.probeWeights.x + probe1 * glossIn.probeWeights.y +
		probe2 * glossIn.probeWeights.z + probe3 * glossIn.probeWeights.w) /
		(glossIn.probeWeights.x + glossIn.probeWeights.y + glossIn.probeWeights.z + glossIn.probeWeights.w + 1E-6);
	
    return probeMix;
}
