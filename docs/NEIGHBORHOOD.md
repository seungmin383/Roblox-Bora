# 첫 동네 구역

유일한 `Ro.rbxlx`의 기존 `XJunction_5` 주변에 `Workspace.BoraNeighborhood_01`을 추가합니다. 중심은 약 **X=245.8, Z=80.7 studs**입니다. Studio Explorer에서 해당 모델을 선택하고 F로 위치를 볼 수 있습니다. 자동으로 Studio나 카메라를 활성화하지 않습니다.

기존 네 방향 차선·정지선·횡단보도·차로 방향·차량/보행 신호 설정은 보존합니다. 건물 앞 포장은 기존 보도 높이에 맞추고, 건물·집기·가로등은 차도 밖에 배치합니다. 새 점자 경고 타일 8곳은 횡단보도 양쪽의 기존 보도에 배치합니다. 기존 보도 턱 형상을 절개하거나 차로 폭을 변경하지 않습니다.

- 느린 커피: 2층, 연한 벽체·녹색 차양·실외 테이블.
- 보라 약국: 3층, 녹색 간판과 돌출 약국 표시.
- 보라 마트: 2층, 벽돌 외벽·남색 차양·입구 상품 상자.
- 보라빌라 101: 3층, 발코니·우편함·주거용 입면.

상가의 정면·측면 유리는 실제 투명 부품입니다. 지상층은 열린 출입문과 간단한 카운터·선반을 두며, 상층부는 외관용 벽체·창틀·창유리로 구성합니다. 뒷면에도 창과 관리용 출입문을 둡니다. 옥상에는 난간·출입실·실외기 형상을 포함합니다. 가로등 8개, 벤치 4개, 낮은 화단 4개를 배치합니다. 점포 상호작용이나 NPC는 이번 모델에 들어 있지 않습니다.

모두 일반 Roblox Part/SurfaceGui/PointLight이므로 별도 텍스처 설치나 업로드가 필요 없습니다. 원본 제작 소스는 `src/NeighborhoodFactory.luau`, 배치 도구는 `tools/build_neighborhood.luau`입니다. 1,294개 고정 부품을 추가하며 기존 나무·자동차 모델은 복제하거나 수정하지 않습니다.

## 재현과 검증

빌드 진입점은 계속 `tools/build_tree_v4.luau`입니다.

```powershell
lune run tools/build_tree_v4.luau --neighborhood-stage
python tests/neighborhood.py
blender --background --disable-autoexec --python-exit-code 1 --python tools/render_neighborhood.py
lune run tools/build_tree_v4.luau --neighborhood
```

Stage는 `.rbxmx` 모델과 JSON만 생성합니다. 적용 시에는 Stage 시점의 Place·제작 소스·모델 해시를 대조하여 이후 저장된 편집을 덮어쓰지 않습니다. 기존 동네 모델이 있으면 다시 생성하거나 사용자 수정사항을 초기화하지 않습니다. 기존 도로를 편집했을 때 건물까지 자동 이동시키지는 않습니다.

`tests/neighborhood.py`는 실제 저장 도로의 충돌 면과 새 부품의 차도 침범, 고정·크기·간판·조명 수, 반복 적용 및 사용자 편집 보존을 확인합니다. `dist/neighborhood-project-validation.json`은 기존 Workspace와 모든 서비스 보존 결과입니다. `dist/preview/neighborhood-*.png`는 실제 생성된 Roblox 부품을 Blender로 렌더한 미리보기이며 Studio 캡처가 아닙니다. Studio Play 확인은 별도입니다.
