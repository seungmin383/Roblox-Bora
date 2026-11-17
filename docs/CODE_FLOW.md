# 나무 v0.3 제작과 성장 흐름

## 정적인 골격을 먼저 완성

`tools/build_tree_quality.py`가 Blender에서 굵기가 점차 줄어드는 줄기·큰 가지 9개·잔가지 18개·뿌리를 만듭니다. 겹친 튜브를 voxel remesh로 합치고 가지 목 부분을 부드럽게 다듬은 뒤 7,800 triangles로 줄입니다. 매우 작은 voxel 파편만 제거하며, 큰 가지가 분리된 경우 생성이 실패합니다. 최종 메시의 연결 요소 1개와 모든 모서리의 manifold 여부를 검사합니다.

회갈색 나무껍질의 세로 결을 1024×1024 PNG로 구워 FBX와 native mesh에서 같은 텍스처를 사용합니다. 바운드의 실제 밑면을 지면 기준으로 정규화합니다. `manifest.json`에는 목재 치수·높이·수관 부착점 28개와 검증 결과가 저장됩니다.

## 맵과 플러그인 빌드

`tools/build_tree_v2.luau`는 manifest로 `src/TreeAssetCatalog.luau`를 생성하고 GrowthMath·GrowthTreeFactory·TreePlugin을 하나의 설치 모델에 넣습니다. 빈 작업 맵, 성장 3단계 맵, 성목·목재 비교 맵을 함께 출력합니다. 파일명은 기존 호출과 호환되도록 유지했습니다.

`tools/install_tree_v2.ps1`은 Studio content/BoraTreeKitV3에 현재 에셋 3개를, Plugins에 BoraTreeKit.rbxmx를 복사하고 SHA256을 비교합니다. 기존 설치 플러그인은 프로젝트 archive 안에 별도 파일로 백업합니다. Studio 버전이 바뀌면 다시 설치해야 합니다.

## 성장 편집

`GrowthMath.dimensions`가 성장률 0~1을 목재 높이 3~18 studs, 줄기 지름 0.22~2.2 studs, 잎 카드 기준 크기 0.38~4.3 studs로 바꿉니다.

`GrowthTreeFactory.layout`은 목재 전체에 하나의 비균일 스케일을 적용합니다. 줄기와 가지는 같은 표면과 같은 변환을 공유하므로 성장 중에도 연결됩니다. 수관 부착점에도 같은 스케일을 적용하고, 결정적인 Seed로 잎 카드를 그 주변에 분산합니다. 이 방식은 어린 나무에 성목의 가지 구조가 축소되어 남는 한계가 있습니다.

`setGrowth`는 기존 목재 1개와 카드 84개의 위치·크기를 바꿉니다. Root는 지면 기준으로 고정하고 ObjectId와 Instance를 유지합니다. 충돌은 아래쪽 줄기 높이의 42%에 해당하는 단순 상자입니다. 장식 가지와 잎에는 충돌이 없습니다.

## 잎 뭉치

작은 은행잎 다수가 모인 투명 PNG 한 종류를 카드 84장에 재사용합니다. 두 장은 기울어진 수직 방향, 한 장은 위쪽에서 보이는 경사 방향으로 놓으며 각 카드의 위치와 깊이를 다르게 합니다. 안쪽 경사 카드는 수관 중심부의 빈 공간을 메웁니다. 카메라 방향을 읽거나 따라 회전시키는 코드는 없습니다.

카드는 투명 Part 양면의 SurfaceGui·ImageLabel입니다. PNG alpha를 유지하고 AlwaysOnTop은 끕니다. LightInfluence=1, 최대 거리=300 studs이며 그림자는 만들지 않습니다. 현재 168개의 SurfaceGui/그루이므로 대량 배치에 적합한 최적화가 끝난 상태는 아닙니다.

## 이전 나무와 검토용 골격

v0.2 나무는 SchemaVersion=2이므로 v0.3 성장 코드가 수정하지 않습니다. 인스펙터는 새 나무를 배치하라는 안내를 표시합니다. 오른쪽 검토용 맨목재는 AssetKind가 다르므로 성장 인스펙터에서 제외됩니다.

## 검증 경계

`tests/tree_growth.luau`는 101단계 성장, 밑면·ObjectId·개체 유지, 저장·복원, 역성장, 이동, alpha 카드, 위쪽 방향 카드, v2 보호를 확인합니다. Blender의 `render_tree_growth.py`는 실제 내보낸 메시·XML 배치를 읽어 성목·변형·골격·위쪽 시점과 성장 비교 PNG를 출력합니다.

렌더는 Studio 캡처가 아닙니다. Blender에서는 alpha 잎이 그림자를 만들지만 Studio SurfaceGui는 같은 방식으로 그림자를 만들지 않습니다. 실제 클릭·드래그·Undo와 모바일 프레임률은 별도의 Studio/실기기 확인이 필요합니다. 나무별 런타임 Script나 성장 루프는 넣지 않았습니다.
