#include <metal_stdlib>
#include "../Types/Types.h"

#define iv2 int2
#define iv3 int3
#define iv4 int4

#define v2 float2
#define v3 float3
#define v4 float4

#define h16 half
#define h2 half2
#define h3 half3
#define h4 half4

#define m2 float2x2
#define m3 float3x3
#define m4 float4x4

#define MIN_DISTANCE 0.0
#define MAX_DISTANCE 100.0
#define MAX_STEPS 255
#define EPSILON   0.001
#define PI			3.1415926

using namespace metal;

struct uniforms {
	u16 Width;
	u16 Height;
   u32 Frame;
};

struct VertexInput {
   v3 Position [[attribute(0)]];
};

typedef struct {
   v4 Position [[position]];
	v2 Resolution;
   f32 Frame;
} vertex_out;

vertex vertex_out vert(VertexInput In [[stage_in]], 
								constant uniforms& Uniforms [[buffer(1)]]) {
   vertex_out Out;

	Out.Position   = v4(In.Position, 1.0);
	Out.Resolution = v2(Uniforms.Width, Uniforms.Height);
   Out.Frame = f32(Uniforms.Frame);

	return Out;
}

// 
// Globals
//

constant v3 L0Position = v3(-4.0, -2.0, -4.0);
constant v3 ColorTable[] = {v3(0.5, 0.5, 1.0),
                            v3(0.8, 0.8, 0.0),    
                            v3(0.0, 0.8, 0.0)};

// 
// Signed Distance Functions
//

f32 SphereSDF(v3 Point, f32 Size) {
	return length(Point) - Size;
}

f32 CubeSDF(v3 Point, f32 Size) {
	v3 Range = abs(Point) - v3(Size);       

	f32 Inside = min(max(Range.x, max(Range.y, Range.z)), 0.0); 

	f32 Outside = length(max(Range, 0.0));  

	return Inside + Outside; 
}

f32 PlaneSDF(v3 Point, v3 Normal, f32 Height) {
	
	return dot(Point, Normal) + Height;
}

v2 Union(v2 A, v2 B) {
    return A.x < B.x ? A : B;
}

v2 SDF(v3 Point) {
    f32 _Light, _Cube, _Plane;
    v3 LightOffset, CubeOffset;
    v2 Light, Cube, Plane; 

    LightOffset = Point + L0Position + v3(0.0, -1.0, 0.0);
    CubeOffset = Point + v3(0.0, -1.0, 0.0);

	 _Light = SphereSDF(LightOffset, 0.5);
	 _Cube = SphereSDF(CubeOffset, 1.0);
	 _Plane = PlaneSDF(Point, v3(0.0, 1.0, 0.0), 0.0);

    Light = v2(_Light, 1.0);
    Cube  = v2(_Cube,  2.0);
    Plane = v2(_Plane, 3.0);

    return Union(Light, Union(Cube, Plane));
}

// 
// Utility Functions
//

f32 Radians(f32 Degree) {
    return Degree * PI / 180.0;
}

m3 RotateY(f32 Rad) {
   return m3(
        v3(sin(Rad), 0.0, cos(Rad)),
        v3(0.0,      1.0, 0.0),
        v3(cos(Rad), 0.0, -sin(Rad))
    );
}

m3 RotateX(f32 Rad) {
   return m3(
        v3(1.0, 0.0,      0.0),
        v3(0.0, cos(Rad), -sin(Rad)),
        v3(0.0, sin(Rad), cos(Rad))
    );
}

v3 RayDirection(f32 FieldOfView, v2 Size, v2 FragCoord) {
	v2 xy = FragCoord - Size / 2.0;
	f32 z = Size.y / tan(Radians(FieldOfView) / 2.0);     
	return normalize(v3(xy, -z));   
}

// 
// Main RayMarching 
//

v2 DistanceToSurface(v3 Eye, v3 Direction, f32 Start, f32 Stop) { 
	s32 i;
	f32 Depth;
   v2 Result;
	
	Depth = Start;

	for(i = 0; i < MAX_STEPS; ++i) {
		Result = SDF(Eye + Depth * Direction);
		Depth += Result.x;
			
		if(Result.x < EPSILON || Depth >= Stop) {
			return v2(Depth, Result.y);
		}
	}

	return v2(Stop, 0.0);
}

// 
// Lighting 
//
	
struct Light {
	v3 Position;
	v3 IAmbient;
	v3 IDiffuse;
	v3 ISpecular;
	f32 Alpha;	
};

v3 ApproximateNormal(v3 p) {
	return normalize(v3(
		SDF(v3(p.x + EPSILON, p.y, p.z)).x  - SDF(v3(p.x - EPSILON, p.y, p.z)).x,  
		SDF(v3(p.x, p.y + EPSILON, p.z)).x  - SDF(v3(p.x, p.y - EPSILON, p.z)).x,     
		SDF(v3(p.x, p.y, p.z  + EPSILON)).x - SDF(v3(p.x, p.y, p.z - EPSILON)).x
	));
}

v3 BlinnLighting(v3 Eye, v3 Point, v3 KAmbient, v3 KDiffuse, v3 KSpecular,
					 struct Light Lights[1]) {

	v3 Normal = ApproximateNormal(Point);	
	v3 View   = normalize(Eye - Point);
	
	v3 Ip = v3(0.0);

	for(s32 i = 0; i < 1; ++i) {
		v3 LightVector = normalize(Lights[i].Position - Point);
		v3 Half 			= normalize(View + LightVector);

		f32 DotNL = max(0.0, dot(Normal, LightVector));
      f32 DotHN = max(0.0, dot(Half, Normal));

		Ip += KAmbient * Lights[i].IAmbient + KDiffuse * DotNL * Lights[i].IDiffuse +
				KSpecular * pow(DotHN, Lights[i].Alpha) * Lights[i].ISpecular;
	}	

	return Ip;	
}

// 
// Shadows 
//

f32 Shadows(v3 Point, v3 Direction, f32 Start, f32 Stop, f32 Falloff) {
	s32 i;
	f32 Depth, Distance, Min;
	
	Depth = Start;
   Min = 1.0;

	for(i = 0; i < MAX_STEPS; ++i) {
		Distance = SDF(Point + Depth * Direction).x;
		Depth += Distance;
      Min = min(Min, Distance / Depth * Falloff);
			
		if(Distance < EPSILON) { 

			return 0.0;

		} else if(Depth >= Stop) {

         return Min;
      }
	}

	return Min;
}

f32 Checker(v2 Point) {
    iv2 Checker;
    
    Checker = iv2(round(Point + 0.5));
    return f32((Checker.x ^ Checker.y) & 1);
}


fragment v4 frag(vertex_out In [[stage_in]]) {
   f32 HasHit, Shadow, Fog;
   v2 Result, FragCoord;
   v3 Direction, WorldDirection, Eye, HitPoint, Lighting, Color;
   v4 FragColor;
   m3 RotateMat;
	struct Light L0, Lights[1];

   // Correcting Input and Calculating Raydirection
   FragCoord = v2(In.Position.x, -In.Position.y);
   Direction = RayDirection(45.0, In.Resolution, FragCoord);

   // Animating Camera
	Eye = v3(-6.0, 12.0, 20.0); 
   RotateMat = RotateY(In.Frame / 60.0) * RotateX(Radians(-15.0));
   Eye = RotateMat * Eye;
   WorldDirection = RotateMat * Direction;

   // Cast Ray 
	Result = DistanceToSurface(Eye, WorldDirection, MIN_DISTANCE, MAX_DISTANCE); 
   
   HitPoint = Eye + WorldDirection * Result.x;	
	HasHit = f32(Result.x < MAX_DISTANCE);	
    
   // Deal with returned Materialindexes
   if(Result.y == 3.0) {

       Color = v3(Checker(HitPoint.xz));
       Color = clamp(Color, 0.4, 0.6);
       Color += v3(0.05, 0.1, 0.0);

   } else {

       Color = ColorTable[s32(Result.y)];
   }

   // Apply Fog
   Fog = HasHit * (1.0 - min(1.0, 2.0 * Result.x / MAX_DISTANCE));
	FragColor = v4(mix(ColorTable[0], Color, Fog), 1.0);

   // Do Lighting and Shadows
   L0.Position  = -L0Position;
	L0.IAmbient  = v3(1.8);
	L0.IDiffuse  = v3(2.5);
	L0.ISpecular = v3(1.0);
	L0.Alpha     = 10.0;

	Lights[0] = L0;
    
	Lighting = BlinnLighting(Eye, HitPoint, v3(0.2), v3(0.4), v3(1.0), Lights);
    
   Shadow = Shadows(HitPoint + ApproximateNormal(HitPoint) * 0.1,
                    normalize(L0.Position - HitPoint),
                    MIN_DISTANCE, MAX_DISTANCE, 3.0);

   Lighting = mix(Lighting * 0.4, Lighting, Shadow);

	return FragColor * v4(Lighting, 1.0);
}
