/*
 * Grass shader based on tutorial by Roystan: https://roystan.net/articles/grass-shader.html
 * Added to simulate interaction with objects in the scene
*/
Shader "Grass"
{
    Properties
    {
        [Header(Shading)]
        _TopColor("Top Color", Color) = (1, 1, 1, 1)
        _BottomColor("Bottom Color", Color) = (1, 1, 1, 1)

        [Header(Blade Properties)]
        _BladeWidth("Blade Width", Float) = 0.05
        _BladeWidthRandom("Blade Width Random", Float) = 0.02
        _BladeHeight("Blade Height", Float) = 0.5
        _BladeHeightRandom("Blade Height Random", Float) = 0.3
        _BladeForward("Blade Forward Amount", Float) = 0.38
        _BladeCurve("Blade Curvature Amount", Range(1, 4)) = 2
        _BendRotationRandom("Bend Rotation Random", Range(0, 1)) = 0.2

        [Header(Tessellation)]
        _TessellationUniform("Tessellation Uniform", Range(1, 64)) = 1

        [Header(Wind)]
        _WindDistortionMap("Wind Distortion Map", 2D) = "white" {}
        _WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
        _WindStrength("Wind Strength", Float) = 1

        [Header(Trample)]
        _Trample("Trample", Vector) = (0, 0, 0, 0)
        _TrampleStrength("Trample Strength", Range(0, 10)) = 0.2
    }

    CGINCLUDE
    #include "UnityCG.cginc"
    #include "CustomTessellation.cginc"

    #define BLADE_SEGMENTS 5

    // Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
    // Extended discussion on this function can be found at the following link:
    // https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
    // Returns a number in the 0...1 range.
    float rand(float3 co)
    {
        return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
    }

    // Construct a rotation matrix that rotates around the provided axis, sourced from:
    // https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
    float3x3 AngleAxis3x3(float angle, float3 axis)
    {
        float c, s;
        sincos(angle, s, c);

        float t = 1 - c;
        float x = axis.x;
        float y = axis.y;
        float z = axis.z;

        return float3x3(
            t * x * x + c, t * x * y - s * z, t * x * z + s * y,
            t * x * y + s * z, t * y * y + c, t * y * z - s * x,
            t * x * z - s * y, t * y * z + s * x, t * z * z + c
        );
    }

    float2 UV : TEXCOORD0;
    float _BendRotationRandom;
    float _BladeWidth;
    float _BladeWidthRandom;
    float _BladeHeight;
    float _BladeHeightRandom;
    float _BladeForward;
    float _BladeCurve;

    sampler2D _WindDistortionMap;
    float4 _WindDistortionMap_ST;
    float2 _WindFrequency;
    float _WindStrength;

    float4 _Trample;
    float _TrampleStrength;

    struct geometryOutput
    {
        float4 pos : SV_POSITION;
        float2 uv : TEXCOORD0;
    };

    geometryOutput VertexOutput(float3 pos, float2 uv)
    {
        geometryOutput o;
        o.pos = UnityObjectToClipPos(pos);
        o.uv = uv;
        return o;
    }

    geometryOutput GenerateGrassVertex(float3 vertexPosition, float width, float height, float forward, float2 uv,
                                       float3x3 transformationMatrix)
    {
        float3 tangentPoint = float3(width, forward, height);
        float3 localPosition = vertexPosition + mul(transformationMatrix, tangentPoint);

        return VertexOutput(localPosition, uv);
    }

    float4 GetTrampleVector(float3 pos, float4 objectOrigin)
    {
        float3 trampleDiff = pos - (_Trample.xyz - objectOrigin);
        return float4(
            float3(normalize(trampleDiff).x,
                   0,
                   normalize(trampleDiff).z) * (1.0 - saturate(length(trampleDiff) / _Trample.w)),
            0);
    }

    [maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
    void geo(triangle vertexOutput IN[3] : SV_POSITION, inout TriangleStream<geometryOutput> triStream)
    {
        float3 pos = IN[0].vertex;
        float3 normal = IN[0].normal;
        float4 tangent = IN[0].tangent;
        float3 binormal = cross(normal, tangent) * tangent.w;

        float3x3 tangentToLocal = float3x3(
            tangent.x, binormal.x, normal.x,
            tangent.y, binormal.y, normal.y,
            tangent.z, binormal.z, normal.z
        );

        float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));
        float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_TWO_PI * 0.5,
                                                   float3(-1, 0, 0));

        float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
        float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
        float3 wind = normalize(float3(windSample.x, windSample.y, 0));
        float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);

        float3x3 transformationMatrix = mul(mul(mul(tangentToLocal, windRotation), facingRotationMatrix),
                                            bendRotationMatrix);
        float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);

        float width = (rand(pos.xyz) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
        float height = (rand(pos.xyz) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
        float forward = rand(pos.yyz) * _BladeForward;
        float4 objectOrigin = mul(unity_ObjectToWorld, float4(0.0, 0.0, 0.0, 1.0));

        for (int i = 0; i < BLADE_SEGMENTS; i++)
        {
            float t = i / (float)BLADE_SEGMENTS;
            float segmentHeight = height * t;
            float segmentWidth = width * (1 - t);
            float segmentForward = pow(t, _BladeCurve) * forward;

            float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;

            if (i > 0)
            {
                float4 trample = GetTrampleVector(pos, objectOrigin);
                pos += trample * _TrampleStrength;
            }

            triStream.Append(
                GenerateGrassVertex(pos, segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
            triStream.Append(
                GenerateGrassVertex(pos, -segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
        }

        float4 trample = GetTrampleVector(pos, objectOrigin);
        pos += trample * _TrampleStrength;
        triStream.Append(GenerateGrassVertex(pos, 0, height, forward, float2(0.5, 1), transformationMatrix));
    }
    ENDCG

    SubShader
    {
        Cull Off

        Pass
        {
            Tags
            {
                "RenderType" = "Opaque"
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.6
            #pragma geometry geo
            #pragma hull hull
            #pragma domain domain

            float4 _TopColor;
            float4 _BottomColor;
            float _TranslucentGain;

            float4 frag(geometryOutput i, fixed facing : VFACE) : SV_Target
            {
                return lerp(_BottomColor, _TopColor, i.uv.y);
            }
            ENDCG
        }
    }
}