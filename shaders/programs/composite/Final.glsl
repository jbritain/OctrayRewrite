/* config
const int colortex0Format = R32UI;
const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex1Format = RGBA32F;
const bool colortex1Clear = true;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex2Format = R32UI;
const bool colortex2Clear = false;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex3Format = R32UI;
const bool colortex3Clear = true;
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex5Format = RGBA8;
const bool colortex5Clear = true;
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex6Format = RGB32F;
const int colortex7Format = RGB32F;

const int colortex8Format = RGBA32F;
const int colortex9Format = RGBA32F;
const int colortex10Format = RGBA32F;
const int colortex11Format = RGBA32F;
const int colortex13Format = RGBA32F;
const int colortex14Format = RGBA32F;
const bool colortex8Clear = false;
const bool colortex9Clear = false;
const bool colortex10Clear = false;
const bool colortex13Clear = false;
*/

layout (r32ui) uniform uimage2D colorimg2;

uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex10;
uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;

uniform int hideGUI;

const bool colortex13MipmapEnabled = true;
const bool colortex14MipmapEnabled = true;

vec2 texcoord = gl_FragCoord.xy / viewSize * MC_RENDER_QUALITY;

#include "../../includes/debug.glsl"

#include "../../includes/aces.glsl"

float LogContrast(float x, const float eps, float logMidpoint, float contrast) {
	float logX = log2(x + eps);
	float adjX = (logX - logMidpoint) / contrast + logMidpoint;

	return max0(exp2(adjX) - eps);
}

vec3 Contrast(vec3 color) {
	const float contrastEpsilon = 1e-5;

	vec3 ret;
	     ret.x = LogContrast(color.x, contrastEpsilon, log2(0.5), 1.0 - (-0.1));
		 ret.y = LogContrast(color.y, contrastEpsilon, log2(0.5), 1.0 - (-0.1));
		 ret.z = LogContrast(color.z, contrastEpsilon, log2(0.5), 1.0 - (-0.1));

	return ret;
}


/***********************************************************************/
/* Bloom */
vec4 cubic(float x) {
	float x2 = x * x;
	float x3 = x2 * x;
	vec4 w;
	
	w.x =   -x3 + 3*x2 - 3*x + 1;
	w.y =  3*x3 - 6*x2       + 4;
	w.z = -3*x3 + 3*x2 + 3*x + 1;
	w.w =  x3;
	
	return w / 6.0;
}

vec3 BicubicTexture(sampler2D tex, vec2 coord) {
	coord *= viewSize;
	
	vec2 f = fract(coord);
	
	coord -= f;
	
	vec4 xcubic = cubic(f.x);
	vec4 ycubic = cubic(f.y);
	
	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xcubic.xz + xcubic.yw, ycubic.xz + ycubic.yw);
	
	vec4 offset  = c + vec4(xcubic.yw, ycubic.yw) / s;
	     offset /= viewSize.xxyy;
	
	vec3 sample0 = texture2D(tex, offset.xz).rgb;
	vec3 sample1 = texture2D(tex, offset.yz).rgb;
	vec3 sample2 = texture2D(tex, offset.xw).rgb;
	vec3 sample3 = texture2D(tex, offset.yw).rgb;
	
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	
	return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

vec3 GetBloomTile(sampler2D tex, const int scale, vec2 offset) {
	vec2 coord  = texcoord;
	     coord /= scale;
	     coord += offset + 0.75/viewSize;
	
	return BicubicTexture(tex, coord);
}

#define BLOOM
#define BLOOM_AMOUNT 0.1
#define BLOOM_CURVE 1.0

vec3 GetBloom(sampler2D tex, vec3 color) {
	#ifndef BLOOM
		return color;
	#endif
	vec3 bloom[8];
	
	// These arguments should be identical to those in composite2.fsh
	bloom[1] = GetBloomTile(tex,   4, vec2(0.0                         ,                          0.0));
	bloom[2] = GetBloomTile(tex,   8, vec2(0.0                         , 0.25     + 1/viewSize.y * 2.0));
	bloom[3] = GetBloomTile(tex,  16, vec2(0.125    + 1/viewSize.x * 2.0, 0.25     + 1/viewSize.y * 2.0));
	bloom[4] = GetBloomTile(tex,  32, vec2(0.1875   + 1/viewSize.x * 4.0, 0.25     + 1/viewSize.y * 2.0));
	bloom[5] = GetBloomTile(tex,  64, vec2(0.125    + 1/viewSize.x * 2.0, 0.3125   + 1/viewSize.y * 4.0));
	bloom[6] = GetBloomTile(tex, 128, vec2(0.140625 + 1/viewSize.x * 4.0, 0.3125   + 1/viewSize.y * 4.0));
	bloom[7] = GetBloomTile(tex, 256, vec2(0.125    + 1/viewSize.x * 2.0, 0.328125 + 1/viewSize.y * 6.0));
	
	bloom[0] = vec3(0.0);
	
	for (uint index = 1; index <= 7; index++)
		bloom[0] += bloom[index];
	
	bloom[0] /= 7.0;
	
	return mix(color, min(pow(bloom[0], vec3(BLOOM_CURVE)), bloom[0]), BLOOM_AMOUNT);
}
/***********************************************************************/


void main() {
    vec3 avgCol = textureLod(colortex13, vec2(0.5), 16).rgb;
    float expo = pow(1.0 / sqrt(dot(avgCol, vec3(1.0))), 1.5);
    
    vec3 diffuse = texture(colortex13, texcoord).rgb;
    
    vec3 gbufferEncode = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).rgb;
    vec3 albedo = unpackUnorm4x8(floatBitsToUint(gbufferEncode.r)).rgb * 256.0 / 255.0;
    
    albedo = pow(albedo, vec3(2.2));
    
    // vec3 color = diffuse * albedo;
    vec3 color = diffuse;
    color = GetBloom(colortex14, color);
    color *= min(expo, 1000.0);
    
    color = ACES_AP1_SRGB_RRT(color);
    // WhiteBalance(color);
    // color    = Vibrance(color);
    // color    = Saturation(color);
    // color    = Contrast(color);
    // color    = LiftGammaGain(color);
    
    color = LinearToSRGB(color);
    
    gl_FragColor.rgb = color;
    
    if (int(gl_FragCoord.x) == 0 && int(gl_FragCoord.y) == 0)
        imageStore(colorimg2, ivec2(4095), uvec4(1));
    
    #ifdef DEBUG
    if (hideGUI == 1)
        gl_FragColor.rgb = imageLoad(colorimg5, ivec2(texcoord * viewSize)).rgb;
    #endif
    
    // gl_FragColor.rgb = texture(colortex14, texcoord).rgb;
}
