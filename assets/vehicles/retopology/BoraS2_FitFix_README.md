# BORA S2 — 앞코 접합·앞유리 간섭 수정본

현재 확인할 Blender 파일은 **BoraS2_FitFix.blend**입니다.
기존에 열어둔 `BoraS2_Clean.blend`를 덮어쓰지 않고 별도 차량 자산으로 저장했습니다.
새 Roblox Place를 만들지 않았으며 `Ro.rbxlx`의 차량은 아직 교체하지 않았습니다.

## 이번 수정

- Tripo에서 생성된 앞코의 겹친 조각·찢어진 테두리를 제거하고, 기존 후드·펜더 단면에서 이어지는 6 mm 두께의 닫힌 곡면으로 연결했습니다.
- 앞바퀴에 반지름 390 mm의 아치 여유를 마련했습니다. 바퀴 크기와 회전 피벗은 유지했습니다.
- 그릴과 헤드램프 패널을 실제 수정된 범퍼 표면에 맞췄습니다. 헤드램프 그래픽은 선택한 Tripo 원본에서 색상을 베이크해 사용합니다. 광학 세부는 텍스처입니다.
- 대시보드 앞단을 앞유리 하단 곡선에 따라 좁히고 낮췄습니다. 하단 대시보드도 그 경계에 맞췄고, 계기판 덮개·표시면을 뒤로 이동했습니다.
- 저장 시 보이는 차체 메시가 활성화되어 바로 Edit 모드에 진입할 수 있습니다.

## 검증

- 저장한 파일을 다시 읽어 **42,908삼각형**, 메시 168개를 검사했습니다. 열린 경계·비다양체 모서리·퇴화 삼각형·잘못된 노멀/좌표/UV는 0입니다.
- 지정 실내 부품의 표면을 앞유리에 투영해 간섭을 확인했습니다. 대시보드 상단은 유리 하단보다 낮으며, 유리 영역과 겹치는 계기판 덮개 표본은 유리에서 최소 약 72 mm 안쪽입니다.
- 전면 3,321개 광선의 범퍼 표면 검사에 누락이 없으며 후드·펜더 접합도 별도로 검사했습니다. 이는 차량 전체의 충돌·운전·애니메이션 검증을 의미하지 않습니다.
- 기존 자산 151개의 좌표·면·변환 서명과 절단 경계 뒤쪽 원래 차체 면 3,674개를 보존했습니다.
- GLB와 Roblox용 50개 native mesh의 삼각형 수·노멀·UV·축·피벗·바이너리 구조 검사를 통과했습니다.
- 원본 Blender 파일과 보호 대상 파일의 해시는 유지되었습니다.

세부 기록: `BoraS2_FitFix_Audit.json`, `BoraS2_FitFix_Clearance.json`, `BoraS2_FitFix_SkinInspection.json`, `BoraS2_FitFix_ExportValidation.json`, `BoraS2_FitRepairProcess.json`.

## 결과물

- 편집 파일: `BoraS2_FitFix.blend`
- 교환 파일: `BoraS2_FitFix.glb`
- Roblox용 메시: `native-fit/manifest.json`
- 근접 이미지: `s2-fit-nose.png`, `s2-fit-glass.png`
- 추가 검토 이미지: `s2-fit-nose-high.png`, `s2-fit-nose-wire.png`, `s2-fit-front.png`

기존 문·바퀴·핸들 그룹은 유지합니다. 전체 차량의 완성도 개선과 게임 적용은 후속 작업입니다.

## 재현 도구

Blender를 백그라운드로 실행합니다. `bake_s2_lamp_graphic.py` → `repair_s2_fit.py` → `qa_s2_sedan.py -- --fit-fix --export-only` → `check_s2_fit_clearance.py` 순서로 사용합니다. 바이너리 검사는 Python의 `validate_s2_exports.py --fit-fix`, 이미지 검토는 Blender의 `render_s2_fit.py -- --fast --wire`를 사용합니다.
