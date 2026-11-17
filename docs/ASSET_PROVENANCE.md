# 나무 에셋 생성 출처

## 보행자 신호등 · 2026-10-16

Tripo Studio H3.1에서 세로형 보행자 신호등 본체를 새로 생성했습니다. 작업 ID `18113186-2d02-4423-8ea5-c805f7780b75`, 크레딧 사용 55입니다. 생성 페이지: https://studio.tripo3d.ai/ko/workspace/generate/18113186-2d02-4423-8ea5-c805f7780b75 . 원본은 `assets/traffic/source/BoraPedestrianSignal.glb`입니다.

원본에 불필요한 세 번째 표시 칸이 생성되어 `tools/prepare_traffic_asset.py`의 `--pedestrian` 옵션으로 아래 칸을 절개하고 하단을 막아 두 칸으로 정리했습니다. 원본 UV/albedo를 유지하며 위치 정점 용접·경량화·0.82m 높이 정규화와 native mesh 변환을 수행했습니다. 원본 1,998,256 triangles → 4,208 triangles입니다. 생성 albedo는 1024×1024 PNG이며 새 이미지 생성은 하지 않았습니다. 사람 표시와 지주·점멸 제어는 Luau로 추가했습니다. `assets/traffic/local/pedestrian-manifest.json`에 출처·크기·표시 위치를 기록합니다.

## 도로 신호등 · 2026-10-16

Tripo Studio H3.1의 텍스트 생성으로 가로형 3색 신호등 본체를 새로 만들었습니다. 작업 ID는 `ce30b66d-2fca-4301-81d8-824268179ce4`, 크레딧 사용은 55입니다. 생성 페이지: https://studio.tripo3d.ai/ko/workspace/generate/ce30b66d-2fca-4301-81d8-824268179ce4 . 원본 `assets/traffic/source/BoraTrafficSignal.glb`를 내려받아 보관했습니다.

`tools/prepare_traffic_asset.py`가 백그라운드 Blender에서 위치 정점 용접, UV 유지 경량화, 방향·2.1m 폭 정규화와 Roblox native mesh 변환을 수행합니다. 원본 1,954,664 triangles → 6,500 triangles, 텍스처는 생성 원본의 1024×1024 albedo입니다. `assets/traffic/local/manifest.json`에 메시 크기·렌즈 위치와 출처를 기록합니다. 지주와 실제 점등 부품은 Luau로 만듭니다. 별도의 Tripo 재생성·추가 크레딧 사용은 하지 않았습니다.

## 현재 v0.4 가지 생성기 · 2026-10-15

목재는 `src/TreeSkeleton.luau`와 `TreeMesher.luau`에서 설정에 따라 새로 생성합니다. 자연스러운 접합부를 위해 중심선 캡슐들의 부드러운 거리장 합집합에서 단일 연결 표면을 추출합니다. Tripo 추가 생성이나 크레딧 사용은 없었습니다.

`ProceduralBark.png`는 `tools/render_parametric_trees.py`가 Blender의 절차적 세로 결 재질을 구운 새 텍스처입니다. `Procedural6.mesh`, `Procedural9.mesh`, `Procedural12.mesh`는 동일한 Luau 생성기를 실행해 내보낸 기본 비교용 메시입니다. 실제 Studio 편집은 EditableMesh와 세션 정적 Content를 사용합니다.

잎 이미지는 아래 v0.3의 `GinkgoCluster.png`를 그대로 재사용합니다. 가지 수·밀도에 따라 카드 수와 배치가 달라집니다. 이전 v0.3 소스와 맵은 `archive/tree-v3-20261015`에 보존했습니다.

## 현재 v0.3 · 2026-10-15

목재는 `tools/build_tree_quality.py`로 Blender에서 새로 제작한 연결 표면입니다. 이전 Tripo 메시를 단순히 합친 결과가 아니라, 줄기·큰 가지·잔가지·뿌리를 직접 구성하고 voxel union한 메시입니다. 새로운 Tripo 생성 요청이나 크레딧 사용은 없었습니다. 회갈색 나무껍질도 Blender의 절차적 재질을 구웠습니다. 목재 7,800 triangles, 닫힌 연결 요소 1개를 검사했습니다.

최종 목재: `assets/tree/local/ConnectedWood.blend`, `ConnectedWood.fbx`, `ConnectedWood.mesh`, `ConnectedBark.png`.

2026-10-15 로컬 설치 복구: 설치 당시 `version-9b554450a0fc4e65`가 Studio 업데이트로 제거되고, 실제 실행 경로는 `version-4f087c32742644ab`로 바뀌었습니다. 로그에서 세 에셋의 fetch 실패를 확인했습니다. 현재 버전에 재설치하고 SHA256을 비교한 뒤, 실제 Studio 화면의 잎·목재와 `2026-10-15T05:00:20.336Z`의 `[BoraTree] assets ready: 3`을 확인했습니다. 설치 도구는 모든 발견된 Studio 버전과 실행 경로를 확인하도록 수정했습니다.

잎은 OpenAI 내장 image_gen으로 새로 생성한 가지 없는 여름 은행잎 뭉치입니다. 요청은 작은 부채꼴 잎 60~90개가 겹친 불규칙한 수관 조각, 잎 사이 투명 공간, 가지·줄기·배경 없음입니다. 실제 요청 원문은 `docs/leaf-cluster-prompt.txt`에 보관했습니다. 내장 도구를 사용했으며 CLI/API fallback은 사용하지 않았습니다.

원본: `C:/Users/jinug/.codex/generated_images/01a13ddc-e1bc-7381-b896-393eebab23db/exec-d0992b42-b777-408e-b931-5ad85fde3ccc.png`.

프로젝트 복사본: `assets/tree/local/GinkgoCluster.png`, 1254×1254 RGBA, alpha 0~255. 복사 후 배경 제거·재채색 작업 없이 생성 alpha를 유지했습니다. 84개 고정 평면에 재사용하며 camera billboard는 사용하지 않습니다.

이전 소스·도구·성장 비교 맵·렌더·manifest는 `archive/tree-v2-20261015`에 보존했습니다. 아래 기록은 v0.2의 출처이며 현재 사용 수량과 구분해야 합니다.

## 이전 v0.2 · 2026-10-14

## TRIPO 목재 메시

Tripo Studio Smart Mesh P2.0에서 private 모델로 생성했습니다. 은행나무용 현실감 있는 스타일화를 지시했으며, 모듈형 줄기·큰 가지·잔가지 각각 하나, 잎과 배경 없이 목재만 요청했습니다. 아래는 생성 요청 내용의 요약이며 원문 프롬프트 기록은 아닙니다.

| 부품 | 생성 요청 요약 | 원본 프로젝트 |
| --- | --- | --- |
| 줄기 | 뿌리 밑동을 포함한 은행나무의 단독 줄기, 수직 형태, 사실적인 나무껍질, 잎·수관 없음, 낮은 폴리곤 | https://studio.tripo3d.ai/ko/workspace/generate/d61fad18-3d8d-451d-b6de-a7b1f0c8110d |
| 큰 가지 | 나무에 붙여 쓸 단독 큰 가지, 두꺼운 접합부에서 가늘어지는 형태, 나무껍질, 잎·주변 물체 없음 | https://studio.tripo3d.ai/ko/workspace/generate/6ed73cf9-8ca4-4954-92b3-efab0fccaafe |
| 잔가지 | 작은 잎 이미지 묶음을 붙일 가는 은행나무 잔가지, 목재만, 잎 없음, 낮은 폴리곤 | https://studio.tripo3d.ai/ko/workspace/generate/92ee10f4-ae13-48c4-bd40-8d8871b7e4af |

생성 3회에 각각 100크레딧, 줄기와 큰 가지 텍스처 생성에 각각 20크레딧으로 총 340크레딧을 사용했습니다. 작업 전 2,890, 작업 후 2,550크레딧이었습니다. 잔가지는 텍스처 없이 갈색으로 사용합니다.

원본은 `assets/tripo/source`에 보관합니다. 잔가지 원본은 사용자가 직접 다운로드한 FBX zip입니다. 줄기와 큰 가지는 TRIPO에서 제공한 GLB를 사용합니다. 만료되는 서명 다운로드 URL이나 계정 인증 정보는 저장하지 않았습니다.

TRIPO 출력에 불필요한 옆가지와 그루터기가 포함되어 Blender로 정리했습니다. 큰 가지 밑동 일부를 잘라 막고, 돌출부를 가늘어지는 가지 형태로 줄였습니다. 줄기의 긴 돌출부도 줄이고 방향·원점·길이를 정규화했습니다. 원본의 UV를 유지합니다. PNG 텍스처는 1024×1024로 저장합니다.

정리한 메시의 삼각형 수는 줄기 2,184, 큰 가지 1,123, 잔가지 492입니다. 한 나무는 줄기 1개·큰 가지 4개·잔가지 8개로 목재 10,612개 삼각형입니다. Blender 파일, FBX, Studio 로컬 native mesh를 `assets/tree/local`에 보관합니다.

## 잎 이미지

OpenAI image_gen으로 투명 배경의 은행잎 묶음 이미지 1개를 생성했습니다. 생성 의도는 현실감 있는 스타일화, 여름 은행나무의 부채꼴 잎 7~10개와 가는 잔가지, 뚜렷한 실루엣, 겹쳐 쓰는 foliage sprite, 주변 장면·배경 없음입니다. 이 설명은 요청 요약입니다.

원본 파일: `C:/Users/jinug/.codex/generated_images/01a134dc-90dc-7693-a10b-ec4577802d24/exec-1d5be13f-2df2-45f8-82f6-9a58a9b67ccf.png`

프로젝트 복사본: `assets/tree/local/GinkgoLeaves.png` (1254×1254 RGBA, alpha 0~255).

현재 나무는 투명 Part에 양면 SurfaceGui·ImageLabel을 붙인 카드 16장을 사용합니다. 잎을 TRIPO의 입체 메시로 만들지 않았습니다. 카드 두 개를 교차해 여러 방향에서 볼 수 있게 했습니다. 300 studs 밖에서는 잎 SurfaceGui를 그리지 않습니다. 아직 거리별 목재 LOD와 모바일 성능 측정은 없습니다.

`LeafCard.mesh`는 Blender 비교 렌더용 평면입니다. 실제 Studio 나무는 이 파일을 사용하지 않습니다. 비교 이미지에는 카드의 PNG와 위치·크기를 같은 방식으로 렌더했습니다. Studio의 조명과 SurfaceGui 출력은 Blender 렌더와 다를 수 있습니다.

## 설치 및 검증

`BoraTreeKit.rbxmx`와 필요한 local mesh·PNG 6개를 Studio 설치 폴더에 복사하고 SHA256을 확인했습니다. 기존 `BoraWorldKit.rbxmx`는 `archive/legacy-20261014/installed`에 백업 후 제거했습니다. 기존 제작 파일은 삭제하지 않고 보존했습니다.

현재는 같은 PC에서 사용할 수 있는 로컬 Studio 에셋입니다. Roblox 업로드는 하지 않았습니다. 온라인·모바일 배포 전에 FBX 및 이미지를 업로드하고 로컬 경로를 Roblox 에셋 ID로 바꿔야 합니다.

로딩 API 참고: https://create.roblox.com/docs/reference/engine/classes/ContentProvider
SurfaceGui 참고: https://create.roblox.com/docs/reference/engine/classes/SurfaceGui
