#if (SHADERPASS != SHADERPASS_DBUFFER_PROJECTOR) && (SHADERPASS != SHADERPASS_DBUFFER_MESH)
#error SHADERPASS_is_not_correctly_define
#endif

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/VertMesh.hlsl"


void MeshDecalsPositionZBias(inout VaryingsToPS input)
{
#if defined(UNITY_REVERSED_Z)
	input.vmesh.positionCS.z -= _DecalMeshDepthBias * input.vmesh.positionCS.w;
#else
	input.vmesh.positionCS.z += _DecalMeshDepthBias * input.vmesh.positionCS.w;
#endif
}

PackedVaryingsType Vert(AttributesMesh inputMesh)
{
    UNITY_SETUP_INSTANCE_ID(inputMesh);
    VaryingsType varyingsType;
    varyingsType.vmesh = VertMesh(inputMesh);
#if (SHADERPASS == SHADERPASS_DBUFFER_MESH)
	MeshDecalsPositionZBias(varyingsType);
#endif
    PackedVaryingsType o = PackVaryingsType(varyingsType);
    UNITY_TRANSFER_INSTANCE_ID(inputMesh, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    return o;
}

void Frag(  PackedVaryingsToPS packedInput,
            OUTPUT_DBUFFER(outDBuffer)
            )
{
    UNITY_SETUP_INSTANCE_ID(packedInput);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(packedInput);
    FragInputs input = UnpackVaryingsMeshToFragInputs(packedInput.vmesh);
	DecalSurfaceData surfaceData;

#if (SHADERPASS == SHADERPASS_DBUFFER_PROJECTOR)
	float depth = LOAD_TEXTURE(_CameraDepthTexture, input.positionSS.xy).x;
	PositionInputs posInput = GetPositionInput_Stereo(input.positionSS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V, unity_StereoEyeIndex);
    // Transform from relative world space to decal space (DS) to clip the decal
    float3 positionDS = TransformWorldToObject(posInput.positionWS);
    positionDS = positionDS * float3(1.0, -1.0, 1.0) + float3(0.5, 0.5f, 0.5);
    clip(positionDS);       // clip negative value
    clip(1.0 - positionDS); // Clip value above one

    float4x4 normalToWorld = UNITY_ACCESS_INSTANCED_PROP(matrix, _NormalToWorld);
    GetSurfaceData(positionDS.xz, normalToWorld, surfaceData);
	// have to do explicit test since compiler behavior is not defined for RW resources and discard instructions
	if ((all(positionDS.xyz > 0.0f) && all(1.0f - positionDS.xyz > 0.0f)))
	{
#elif (SHADERPASS == SHADERPASS_DBUFFER_MESH)
	GetSurfaceData(input, surfaceData);
#endif
        uint oldVal = UnpackByte(_DecalHTile[input.positionSS.xy / 8]);
        oldVal |= surfaceData.HTileMask;
        _DecalHTile[input.positionSS.xy / 8] = PackByte(oldVal);

#if (SHADERPASS == SHADERPASS_DBUFFER_PROJECTOR)
    }
#endif

    ENCODE_INTO_DBUFFER(surfaceData, outDBuffer);
}
