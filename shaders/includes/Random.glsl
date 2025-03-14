#if !defined RANDOM_GLSL
#define RANDOM_GLSL

uint Triple32(uint x) {
    // https://nullprogram.com/blog/2018/07/31/
    x ^= x >> 17;
    x *= 0xed5ad4bbu;
    x ^= x >> 11;
    x *= 0xac4c1b51u;
    x ^= x >> 15;
    x *= 0x31848babu;
    x ^= x >> 14;
    return x;
}

float WangHash(uint seed) {
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return float(seed) / 4294967296.0;
}

vec2 WangHash(uvec2 seed) {
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return vec2(seed) / 4294967296.0;
}

#ifdef RAND_SEED
uint randState = Triple32(RAND_SEED);
uint RandNext() { return randState = Triple32(randState); }
uvec2 RandNext2() { return uvec2(RandNext(), RandNext()); }
uvec3 RandNext3() { return uvec3(RandNext2(), RandNext()); }
uvec4 RandNext4() { return uvec4(RandNext3(), RandNext()); }
float RandNextF() { return float(RandNext()) / float(0xffffffffu); }
vec2 RandNext2F() { return vec2(RandNext2()) / float(0xffffffffu); }
vec3 RandNext3F() { return vec3(RandNext3()) / float(0xffffffffu); }
vec4 RandNext4F() { return vec4(RandNext4()) / float(0xffffffffu); }
#endif

uint  Rand   (uint  seed) { return Triple32(seed); }
uvec2 Rand1x2(uint  seed) { return uvec2(Triple32(seed), Triple32(Triple32(seed))); }
float RandF  (uint  seed) { return float(Triple32(seed))                    / float(0xffffffffu); }
vec2  Rand2F (uvec2 seed) { return vec2(Triple32(seed.x), Triple32(seed.y)) / float(0xffffffffu); }

#define TAA

#ifdef TAA
#endif

vec2 TAAHash() {
    vec2 ret = vec2(0.0);
    
#ifdef TAA
    #ifdef REPROJECT
        ret = ((Rand2F(uvec2((frameCounter+2)*2, (frameCounter+2)*2 + 1)) - 0.5) / viewSize) * 2.0;
    #else
    if (accum)
        ret = ((Rand2F(uvec2((frameCounter+2)*2, (frameCounter+2)*2 + 1)) - 0.5) / viewSize) * 2.0;
    #endif
#endif
    
    return ret;
}

vec2 TAAPrevHash() {
    vec2 ret = vec2(0.0);
    
#ifdef TAA
    #ifdef REPROJECT
        ret = ((Rand2F(uvec2((frameCounter+1)*2, (frameCounter+1)*2 + 1)) - 0.5) / viewSize) * 2.0;
    #else
    if (accum)
        ret = ((Rand2F(uvec2((frameCounter+1)*2, (frameCounter+1)*2 + 1)) - 0.5) / viewSize) * 2.0;
    #endif
#endif
    
    return ret;
}

vec3 CalculateConeVector(const float i, const float angularRadius, const int steps) {
    float x = i * 2.0 - 1.0;
    float y = i * float(steps) * 1.618 * 256.0;
    
    float angle = acos(x) * angularRadius / 3.14159;
    float s = sin(angle);

    return vec3(cos(y) * s, sin(y) * s, cos(angle));
}

vec3 hemisphereSample_cos(vec2 uv) {
    float phi = uv.y * 2.0 * PI;
    float cosTheta = sqrt(1.0 - uv.x);
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    return vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}


float OrenNayarDiffuse(vec3 lightDirection, vec3 viewDirection, vec3 surfaceNormal, float roughness, float albedo) {
	float LdotV = dot(lightDirection, viewDirection);
	float NdotL = dot(lightDirection, surfaceNormal);
	float NdotV = dot(surfaceNormal, viewDirection);

	float s = LdotV - NdotL * NdotV;
	float t = mix(1.0, max(NdotL, NdotV), step(0.0, s));

	float sigma2 = roughness * roughness;
	float A = 1.0 + sigma2 * (albedo / (sigma2 + 0.13) + 0.5 / (sigma2 + 0.33));
	float B = 0.45 * sigma2 / (sigma2 + 0.09);

	return albedo * max(0.0, NdotL) * (A + B * s / t) / PI;
}

vec3 CosineSampleHemisphere(vec2 Xi, out float pdf) {
	float r = sqrt(Xi.x);
	float theta = Xi.y * PI * 2.0;

	float x = r * cos(theta);
	float y = r * sin(theta);

	pdf = sqrt(max(1.0 - Xi.x, 0));

	return vec3(x, y, pdf);
}

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a      = roughness*roughness;
    float a2     = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;
	
    float num   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
	
    return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = NdotV;
    float denom = NdotV * (1.0 - k) + k;
	
    return num / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = GeometrySchlickGGX(NdotV, roughness);
    float ggx1  = GeometrySchlickGGX(NdotL, roughness);
	
    return ggx1 * ggx2;
}

vec3 fresnelSchlick(float cosTheta, vec3 F0) {
	return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

vec3 GGXVNDFSample(vec3 Ve, float alpha, vec2 Xi) {
	// Section 3.2: transforming the view direction to the hemisphere configuration
	vec3 Vh = normalize(vec3(alpha * Ve.x, alpha * Ve.y, Ve.z));

	// Section 4.1: orthonormal basis (with special case if cross product is zero)
	float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
	vec3 T1 = lensq > 0.0 ? vec3(-Vh.y, Vh.x, 0.0) * inversesqrt(lensq) : vec3(1.0, 0.0, 0.0);
	vec3 T2 = cross(Vh, T1);

	// Section 4.2: parameterization of the projected area
	float r = sqrt(Xi.y);
	float phi = Xi.x * PI * 2.0;

	float s = 0.5 * (1.0 + Vh.z);

	float t1 = r * cos(phi);
	float t2 = r * sin(phi);
		  t2 = (1.0 - s) * sqrt(1.0 - t1 * t1) + s * t2;

	// Section 4.3: reprojection onto hemisphere
	vec3 Nh = t1 * T1 + t2 * T2 + sqrt(max(1.0 - t1 * t1 - t2 * t2, 0.0)) * Vh;

	// Section 3.4: transforming the normal back to the ellipsoid configuration
	return normalize(vec3(alpha * Nh.x, alpha * Nh.y, max(Nh.z, 0.0)));
}

#endif