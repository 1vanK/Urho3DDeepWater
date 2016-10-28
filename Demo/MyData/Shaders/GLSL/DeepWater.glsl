// DEEP_WATER: Based on Water.glsl

#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"
#include "Lighting.glsl"
#include "Fog.glsl"

#ifndef GL_ES
varying vec4 vScreenPos;
varying vec2 vReflectUV;
varying vec2 vWaterUV;
varying vec3 vEyeVec;
varying vec4 vWorldPos;
#else
varying highp vec4 vScreenPos;
varying highp vec2 vReflectUV;
varying highp vec2 vWaterUV;
varying highp vec3 vEyeVec;
varying highp vec4 vWorldPos;
#endif
varying vec3 vNormal;

#ifdef COMPILEVS
uniform vec2 cNoiseSpeed;
uniform float cNoiseTiling;
#endif

#ifdef COMPILEPS
uniform float cNoiseStrength;
uniform float cFresnelPower;
uniform vec3 cShallowColor;
uniform vec3 cDeepColor;
uniform float cDepthScale;
#endif

#ifdef PERPIXEL
    #ifdef SPOTLIGHT
        varying vec4 vSpotPos;
    #endif
    #ifdef POINTLIGHT
        varying vec3 vCubeMaskVec;
    #endif

    varying vec4 vTangent;
    varying vec4 vTexCoord;
    varying vec4 vTexCoord2;
#endif

void VS()
{
    mat4 modelMatrix = iModelMatrix;
    vec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    vNormal = GetWorldNormal(modelMatrix);
    vScreenPos = GetScreenPos(gl_Position);

    vReflectUV = GetQuadTexCoord(gl_Position);
    vReflectUV.y = 1.0 - vReflectUV.y;
    vReflectUV *= gl_Position.w;
    vWaterUV = iTexCoord * cNoiseTiling + cElapsedTime * cNoiseSpeed;
    vEyeVec = cCameraPos - worldPos;
     
    #ifdef PERPIXEL
        // Per-pixel forward lighting
        vec4 projWorldPos = vec4(worldPos, 1.0);
            
        vec3 tangent = GetWorldTangent(modelMatrix);
        vec3 bitangent = cross(tangent, vNormal) * iTangent.w;
        vTexCoord = vec4(GetTexCoord(iTexCoord * cNoiseTiling + cElapsedTime * cNoiseSpeed), bitangent.xy);
        vTexCoord2 = vec4(GetTexCoord(iTexCoord.yx * cNoiseTiling - cElapsedTime * cNoiseSpeed), bitangent.xy);
        vTangent = vec4(tangent, bitangent.z);

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            vSpotPos = projWorldPos * cLightMatrices[0];
        #endif
    
        #ifdef POINTLIGHT
            vCubeMaskVec = (worldPos - cLightPos.xyz) * mat3(cLightMatrices[0][0].xyz, cLightMatrices[0][1].xyz, cLightMatrices[0][2].xyz);
        #endif
    #endif
}

void PS()
{
    #ifdef PERPIXEL

        #if defined(SPOTLIGHT)
            vec3 lightColor = vSpotPos.w > 0.0 ? texture2DProj(sLightSpotMap, vSpotPos).rgb * cLightColor.rgb : vec3(0.0, 0.0, 0.0);
        #elif defined(CUBEMASK)
            vec3 lightColor = textureCube(sLightCubeMap, vCubeMaskVec).rgb * cLightColor.rgb;
        #else
            vec3 lightColor = cLightColor.rgb;
        #endif

        #ifdef DIRLIGHT
            vec3 lightDir = cLightDirPS;
        #else
            vec3 lightVec = (cLightPosPS.xyz - vWorldPos.xyz) * cLightPosPS.w;
            vec3 lightDir = normalize(lightVec);
        #endif

        mat3 tbn = mat3(vTangent.xyz, vec3(vTexCoord.zw, vTangent.w), vNormal);
        vec3 normal = normalize(tbn * DecodeNormal(texture2D(sNormalMap, vTexCoord.xy)));
        vec3 normal2 = normalize(tbn * DecodeNormal(texture2D(sNormalMap, vTexCoord2.xy)));
        normal = normalize(normal + normal2);

        #ifdef HEIGHTFOG
            float fogFactor = GetHeightFogFactor(vWorldPos.w, vWorldPos.y);
        #else
            float fogFactor = GetFogFactor(vWorldPos.w);
        #endif
    
        vec3 spec = GetSpecular(normal, cCameraPosPS - vWorldPos.xyz, lightDir, 200.0) * lightColor * cLightColor.a;
        
        gl_FragColor = vec4(GetLitFog(spec, fogFactor), 1.0);

    #else
    
        vec2 refractUV = vScreenPos.xy / vScreenPos.w;
        vec2 reflectUV = vReflectUV.xy / vScreenPos.w;

        vec2 noise = (texture2D(sNormalMap, vWaterUV).rg - 0.5) * cNoiseStrength;
        refractUV += noise;
        // Do not shift reflect UV coordinate upward, because it will reveal the clipping of geometry below water
        if (noise.y < 0.0)
            noise.y = 0.0;
        reflectUV += noise;

        float fresnel = pow(1.0 - clamp(dot(normalize(vEyeVec), vNormal), 0.0, 1.0), cFresnelPower);
        vec3 refractColor = texture2D(sEnvMap, refractUV).rgb;
        vec3 reflectColor = texture2D(sDiffMap, reflectUV).rgb;
    
        vec4 depthInput = texture2D(sDepthBuffer, refractUV);
        float depth = ReconstructDepth(depthInput.r); // HWDEPTH
        float waterDepth = (depth - vWorldPos.w) * (cFarClipPS - cNearClipPS);
        
        // Object above water. Recalc without UV noise (avoid artefacts).
        if (waterDepth <= 0.0)
        {
            refractColor = texture2D(sEnvMap, vScreenPos.xy / vScreenPos.w).rgb;
            reflectColor = texture2D(sDiffMap, vReflectUV.xy / vScreenPos.w).rgb;
            
            depthInput = texture2D(sDepthBuffer, vScreenPos.xy / vScreenPos.w);
            depth = ReconstructDepth(depthInput.r);
            waterDepth = (depth - vWorldPos.w) * (cFarClipPS - cNearClipPS);
        }

        vec3 waterColor = mix(cShallowColor, cDeepColor, clamp(waterDepth * cDepthScale, 0.0, 1.0));
        refractColor *= waterColor;
        vec3 finalColor = mix(refractColor, reflectColor, fresnel);
        gl_FragColor = vec4(GetFog(finalColor, GetFogFactor(vWorldPos.w)), 1.0);
    
    #endif
}
