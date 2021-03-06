﻿Shader "NoteCAD/DraftLines" {

	Properties {
		_MainTex ("Texture", 2D) = "white" {}
		_Width("Width", Float) = 1.0
		_StippleWidth("StippleWidth", Float) = 1.0
		[HideInInspector]
		_PatternLength("PatternLength", Float) = 1.0
		[HideInInspector]
		_Pixel("Pixel", Float) = 1.0
		[HideInInspector]
		_CamDir("CamDir", Vector) = (1,1,1,0)
		_CamRight("CamRight", Vector) = (1,0,1,0)
		_Color("Color", Color) = (1,1,1,1)
		_ZTest ("_ZTest", Float) = 4.0
	}
	
	SubShader {
		Tags { "RenderType" = "Transparent" }
		LOD 100
		//AlphaToMask On
		ZWrite Off
		ZTest [_ZTest]
		Blend SrcAlpha OneMinusSrcAlpha

		Pass {
			//Offset -1, -1
			Cull Off
			//ZTest Always
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_instancing
			#pragma multi_compile __ CLIP_BOX CLIP_CORNER
			#pragma multi_compile __ USE_WST_CROSSSECTION
			#pragma multi_compile __ USE_SILHOUETTE_NORMALS

			#include "UnityCG.cginc"

			struct appdata {
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				#if defined(USE_SILHOUETTE_NORMALS)
					float3 nl : TEXCOORD1;
					float3 nr : TEXCOORD2;
				#endif
				float4 tangent: NORMAL;
				float4 params: TANGENT;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct v2f
			{
				noperspective float2 uv : TEXCOORD0;
				noperspective float3 cap: TEXCOORD1;

				float4 vertex : SV_POSITION;
				#if defined(USE_WST_CROSSSECTION)
					float4 pos : TEXCOORD2;
				#endif
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;
			float _Width;
			float _StippleWidth;
			float _PatternLength;
			float _Pixel;
			float _DpiScale;
			float4 _CamDir;
			float4 _CamRight;
			float _Feather;
			fixed4 _Color;

			#if defined(USE_WST_CROSSSECTION)
				#include "Packages/com.h3.clipbox/Shaders/StencilShaders/section_clipping_CS.hlsl"
			#endif

			v2f vert (appdata v) {
				v2f o;
				UNITY_SETUP_INSTANCE_ID(v);
				float4 projected = UnityObjectToClipPos(float4(v.vertex.xyz, 1.0));

				#if defined(USE_SILHOUETTE_NORMALS)
					if(any(v.nl != float3(0.0, 0.0, 0.0)))
					{
						float3 viewDir = unity_OrthoParams.w == 1.0 
							? normalize(mul((float3x3)unity_CameraToWorld, float3(0,0,1)))
							: WorldSpaceViewDir(v.vertex);
						float3 nl = mul((float3x3)unity_WorldToObject, v.nl);
						float3 nr = mul((float3x3)unity_WorldToObject, v.nr); 

						float ldot = dot(nl, viewDir);
						float rdot = dot(nr, viewDir);

						bool isOutline = (ldot > -1e-6) == (rdot < 1e-6) ||
										 (rdot > -1e-6) == (ldot < 1e-6);
						if(!isOutline)
						{
							o.vertex = float4(0.0, 0.0, 0.0, 0.0);
							return o;
						}
					}
				#endif

				float4 projectedTang = UnityObjectToClipPos(float4(v.vertex.xyz + normalize(v.tangent.xyz), 1.0));
				float3 tang = projectedTang.xyz / projectedTang.w - projected.xyz / projected.w;
				if((projected.w >= 0) != (projectedTang.w >= 0)) tang = -tang;
				float tangLen = length(tang.xy);
				tang = tang / tangLen;
				float scale = length(float3(unity_ObjectToWorld[0].x, unity_ObjectToWorld[1].x, unity_ObjectToWorld[2].x));
				float pixel = _DpiScale * projected.w / _ScreenParams.x;
				// dir does not get used
				//float3 dir = mul((float3x3)unity_WorldToObject, (float3)_CamDir);
				if (all(v.tangent.xyz == float3(0, 0, 0))) {
					tang = normalize(mul((float3x3)unity_WorldToObject, (float3)_CamRight));
				}
				float cap = _Width * pixel + _Feather * 2.0 * pixel;
				float3 x = tang * cap / 1.5;
				float3 y = cross(tang, float3(0.0, 0.0, 1.0)) * cap;
				float ratio = _ScreenParams.x / _ScreenParams.y;
				x.y *= ratio;
				y.y *= ratio;

				o.vertex = projected + float4(v.params.x * x + v.params.y * y, 0.0);
				#if defined(USE_WST_CROSSSECTION)
					o.pos = mul(unity_ObjectToWorld, v.vertex);
				#endif
				
				// some depth offset depending on width of line
				o.vertex.z += _DpiScale * _Width / 4.0 / _ScreenParams.x;
				float2 uv = v.uv;
				uv.x += v.params.x * cap;
				float len = length(v.tangent.xyz);
				if(v.params.x == -1.0) {
					o.cap = float3(-1.0, len / cap, pixel);
				} else {
					o.cap = float3(len / cap + 1.0, len / cap, pixel);
				}
				o.uv = TRANSFORM_TEX(uv, _MainTex);
				return o;
			}

			fixed4 frag (v2f i) : SV_Target {
				#if defined(USE_WST_CROSSSECTION)
					PLANE_CLIP(i.pos)
				#endif
				float pix = i.cap.z / 2.0;
				float patternScale = _PatternLength * _StippleWidth * pix;
				fixed4 v = tex2D(_MainTex, float2(i.uv.x / patternScale, 0.0));
				float val = dot(v, float4(1.0, 1.0 / 255.0, 1.0 / 65025.0, 1.0 / 160581375.0));
				float pat = val * patternScale / (_Width * pix) * 8.0;
				float c = (_Width / 2.0 + _Feather) / (_Width / 2.0);
				float cap = (max(i.cap.x - i.cap.y, 0.0) - min(i.cap.x, 0.0)) * c;
				float dist = length(float2(max(cap, pat), i.uv.y * c));

				float f = 2.0 * _Feather / (_Width / 2.0 + _Feather);
				float k = smoothstep(1.0 - f, 1.0+ f, dist);
				if (k == 1.0) discard;
				return float4(_Color.rgb, _Color.a * (1.0 - k));
			}
			ENDCG

		}
	}
}
