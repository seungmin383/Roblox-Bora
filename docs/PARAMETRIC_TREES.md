# v0.4 가지 레시피 생성기

현재 작업 프로젝트는 최상위 `Ro.rbxlx` 하나입니다. 아래에 기록된 이전 비교·테스트 Place 파일은 프로젝트 통합 시 삭제했습니다. 같은 파일에만 적용하며 새 프로젝트는 생성하지 않습니다. 현재 사용법과 빌드는 최상위 README.md를 따릅니다.

## 사용 범위

Studio에서 큰 가지 수 4~14개, 퍼짐 65~140%, 목재 굵기 65~150%, 잎 밀도 0~150%와 정수 시드(0~2147483646)를 입력하고 적용합니다. 큰 가지마다 잔가지 2개가 따라갑니다. 잔가지 개별 추가·삭제, 각 가지를 직접 잡아 이동하는 편집기는 이번 범위가 아닙니다.

v0.4.1에서는 모든 설정을 슬라이더로 조절합니다. 드래그 중에는 정수 수치와 손잡이만 바꾸고, 놓을 때 구조를 한 번 생성해 Undo 한 단계로 기록합니다. 성장 슬라이더는 기존처럼 드래그 중 실시간 반영합니다. 시드 슬라이더는 0~999 범위이며 전체 정수 시드는 숫자 필드로 입력할 수 있습니다. 숫자 입력은 기존 적용 버튼을 사용합니다. Esc는 진행 중인 설정 드래그를 취소합니다.

원하는 전체 형상을 만드는 골격 레시피를 보관하고 설정이 달라질 때 목재 표면을 다시 계산합니다. 성장률 변경은 목재 전체와 잎 부착점을 같은 축 비율로 축소합니다. 가지가 시간에 따라 새로 돋는 생물학적 성장 시뮬레이션은 아닙니다.

## 소스 역할

| 파일 | 역할 |
| --- | --- |
| TreeParameters | 입력 범위·기본값·레시피 버전·저장 Attributes 읽기 |
| TreeSkeleton | 줄기와 가지 중심선, 반지름, 부모 관계, 수관 부착점 생성 |
| TreeMesher | 부드러운 거리장 합집합, marching tetrahedra, 경계 정점 공유, 접합부 평활화 |
| TreeMeshBackend | 실제 EditableMesh 생성, UV·공유 법선, 세션 정적 Content 생성, API 한도별 MeshPart 분할 |
| ProceduralTreeFactory | 나무 생성·구조 변경·성장·잎 카드·지면 기준과 ID 유지 |
| ParametricTreePlugin.server | 인스펙터·설치·성장 드래그·Undo·편집 세션 복원 |
| ProceduralRuntime.server | 저장된 생성 레시피를 Play 세션에서 한 번 복원 |
| tools/build_tree_v4 | 플러그인·빈 작업 맵·가지 6/9/12개 비교 맵 생성 |

## 목재 연결

중심선 구간마다 반지름이 변하는 캡슐의 signed distance를 샘플링합니다. smooth-min으로 만나는 표면을 둥글게 합칩니다. 한 거리장에서 외부 표면을 추출하므로 접합부 안의 겹친 껍질이나 별도 가지의 잘린 끝이 남지 않습니다.

v0.4.2는 같은 가지 내부 구간에는 최솟값 합집합을 쓰고, 서로 다른 가지 사이에만 부드러운 합집합을 사용합니다. 같은 가지의 매 구간마다 부풀어 오르던 현상을 제거했습니다. 중심선은 Hermite 곡선으로 연결합니다.

기본 격자 간격은 0.22 studs이며 굵기에 따라 0.18~0.25로 조절합니다. 추출·평활화 후 정점을 원래 곡면에 투영하고, 곡면을 0.008 studs 이상 파고드는 삼각형 모서리는 공유 중점을 추가해 보정합니다. 가는 가지를 위해 전체 격자를 과도하게 늘리지 않고 필요한 둘레만 더 나눕니다. 법선은 곡면의 미분으로 계산합니다. 공간별 가까운 구간만 검사해 투영 비용을 줄입니다.

격자보다 가는 잔가지가 끊어지지 않도록 반지름 하한은 유지합니다. 끝부분의 극소 파편은 제거하되 큰 가지가 분리되면 생성에 실패합니다. 정점 공유·닫힘·삼각형 방향과 연결성은 자동 테스트로 검사합니다.

삼각형 수는 기본값에서 큰 가지 6개 33,880개, 9개 43,558개, 12개 53,670개입니다. 표면 개선으로 이전 버전보다 메시가 커졌습니다. 실제 API에는 최대 18,000개씩 나누어 전달합니다. 분할 경계에서도 같은 위치와 전체 표면의 법선을 사용합니다. 개별 조각은 열린 부분 표면일 수 있으므로 장식 목재 자체는 충돌에 쓰지 않으며, 줄기 아래쪽에 별도 단순 충돌 상자를 사용합니다.

## 변경과 실패 처리

새 골격·메시·잎을 나무에 붙이기 전에 완성합니다. 입력이 잘못됐거나 메시 API가 실패하면 새 형상을 버리고 기존 Geometry를 유지합니다. 성공 시 같은 Model·Root·ObjectId에 새 Geometry를 붙이고 현재 Growth를 다시 적용합니다.

Studio의 Undo가 이전 형상을 다시 붙일 수 있도록 이전 Geometry를 Parent=nil 상태로 편집 세션에 보관합니다. 삭제된 형상은 Workspace에서 렌더되지 않습니다. 세션 중 편집을 많이 할수록 Undo용 형상 메모리가 늘 수 있습니다. 로컬 제작 검토 버전의 제약이며 대량 반복 편집용 메모리 정책은 별도입니다.

## 저장·다시 열기·Play

저장 원본은 BranchCount, Spread, Thickness, LeafDensity, Seed, Growth, RecipeVersion, ObjectId와 Root입니다. API에서 구운 Content는 세션 수명을 가지므로 이 Content만을 영구 저장 원본으로 취급하지 않습니다.

플러그인은 Studio에서 LiveMesh=true인 v4 나무의 레시피를 다시 생성합니다. 첫 편집·설치 때 ServerScriptService에 공용 `BoraProceduralRuntime`과 필요한 모듈을 넣고, Play 시작 시 서버에서도 한 번 생성해 세션 정적 Content를 사용합니다. 매 프레임 생성하거나 나무별 Heartbeat를 추가하지 않습니다.

기본 비교 맵의 6/9/12 모델은 native mesh 파일 참조를 사용해 처음 열 때도 표시됩니다. 사용자가 설정을 적용한 나무부터 LiveMesh 레시피 복원 경로를 사용합니다.

공개 게임에서 EditableMesh API를 쓰려면 Roblox의 관련 경험 설정·권한 조건도 충족해야 합니다. 이 작업에서는 계정 보안 설정을 변경하거나 Roblox에 새 에셋을 업로드하지 않았습니다. 잎·나무껍질의 rbxasset 로컬 경로도 온라인 배포 전에 정식 에셋으로 전환해야 합니다.

## 검사

`tests/parametric_geometry.luau`: 6/9/12개와 범위 경계·여러 시드의 닫힌 연결 표면, 공유 모서리 방향, 지면, 가지 그래프, 입력 거부. 동일한 결과로 native mesh와 Blender 검토 JSON을 출력합니다.

`tests/parametric_factory.luau`: API별 18,000 triangle 분할, EditableMesh 자원 정리, 성장 101단계에서 개체 유지, 가지 수 변경, 잎 밀도 0, 잘못된 입력과 API 실패 시 기존 형상 유지, 저장된 레시피 복원, 소스 컴파일.

`tests/tree_surface.luau`: 비스듬한 가는 원통을 1구간/16구간으로 나눠도 같은 표면을 만드는지 검사하고 반지름 오차를 측정합니다. `tools/render_surface_comparison.py`는 이전/현재 목재를 잎·텍스처 없이 비교 렌더합니다. 실제 Studio 캡처가 아닌 Blender 렌더입니다. 새 확인용 맵은 `dist/BoraTreeSmoothEditor.rbxlx`이며 왼쪽은 목재만, 오른쪽은 잎 포함입니다. 기존 저장 맵의 공용 Play 복원 모듈도 편집기와 같은 버전으로 갱신합니다.

실제 Studio 검증 · 2026-10-15:

- v0.4.2: 새 목재/잎 비교 맵을 열어 목재만 있는 나무를 확대 확인. 퍼짐 100→110% 드래그 후 새 EditableMesh 생성 성공, 화면상 소요 약 0.8초. 세 자동 테스트(`parametric_geometry`, `parametric_factory`, `tree_surface`) 통과. 저장 맵은 `dist/BoraTreeSmoothEditor.rbxlx`.
- v0.4.1: 다섯 슬라이더를 직접 드래그해 가지 9→12, 퍼짐 100→120%, 굵기 100→120%, 잎 밀도 100→75%, 시드 42→503 자동 적용 확인. 각 생성 약 0.4~0.5초. 시드 변경 Ctrl+Z/ Ctrl+Y 시 숫자·손잡이·형상 복원 확인. 예제는 `dist/BoraTreeSliderEditor.rbxlx`.
- 큰 가지 9→6 적용 성공: 14,360 triangles, ObjectId `parametric-preview-9` 유지.
- 큰 가지 9→12 적용 성공: 21,868 triangles, MeshPart 2개로 표시, ObjectId 유지.
- Ctrl+Z로 9개 가지의 이전 형상 복원, Ctrl+Y로 12개 가지 형상 복원.
- 성장 슬라이더를 100→50%로 드래그해 표시와 형상 변경 확인.
- 로컬 `ParametricTreeEditTest.rbxlx` 저장 성공 후, 복사본을 별도 Studio 프로세스에서 열어 `restored recipe: parametric-preview-9`와 나무 표시 확인.
- Play의 서버 시작 스크립트에서 `runtime restored parametric-preview-9` 확인 및 클라이언트 나무 표시 확인.

Play 중 편집 플러그인까지 실행되는 초기 경고를 확인하고, 플러그인은 편집 모드에서만 초기화하도록 막았습니다. 온라인 경험이나 모바일 실기기는 테스트하지 않았습니다. 검증 파일은 `dist/ParametricTreeEditTest.rbxlx`, `dist/ParametricTreeReloadTest.rbxlx`이며, 사용자는 편집 시작용 맵 `dist/BoraTreeEditor.rbxlx`를 열면 됩니다. `ParametricTreePreview.rbxlx`는 같은 기본 비교 장면입니다.

Blender PNG는 실제 Studio 캡처가 아니며, 잎 SurfaceGui의 그림자 표현도 Blender와 다릅니다.

## API 참고

- https://create.roblox.com/docs/reference/engine/classes/EditableMesh
- https://create.roblox.com/docs/reference/engine/classes/AssetService
- https://devforum.roblox.com/t/full-release-introducing-createdatamodelcontent-convert-editable-mesh-and-image-data-into-static-content/4541898/1
