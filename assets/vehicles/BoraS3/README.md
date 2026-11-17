# BORA S3 — 승인된 프로젝트 모델

사용자 제공 예시의 패널 접합과 실내 공간 구성을 참고해 새로 만든 세단입니다. 2026-10-18 핸들 방향 교정 후 사용자가 현재 모델을 승인하고 프로젝트 반영을 요청했습니다. `BoraS2_FitFix`를 열거나 기반 메시로 사용하지 않았습니다.

## 열 파일

- `BoraS3.blend`: 편집용 원본. 차량과 별도 Presentation 컬렉션에 촬영용 조명·바닥·카메라가 있습니다.
- `BoraS3.glb`: 차량 메시·재질과 내장된 계기판/내비/번호판 그래픽. 촬영용 조명·바닥·카메라는 제외했습니다.
- `S3_Front.png`, `S3_Rear.png`, `S3_Cockpit.png`: 실제 재질 렌더.
- `S3_SteeringMount.png`: 사용자가 표시한 대시보드 아래에서 기둥이 나오도록 수정한 최신 핸들 근접 화면. 기존 전체 렌더는 이 국소 수정 전 이미지입니다.
- `S3_SolidFront.png`, `S3_SolidRear.png`, `S3_Side.png`, `S3_CabinCutaway.png`, `S3_WireFront.png`: 중성 구조/편집 모서리 확인.
- `audit.json`, `glb-validation.json`, `skin-inspection.json`: 저장본과 내보낸 파일 검사.
- `provenance.json`: 참고 및 생성 근거, 원본·Place 보존 해시와 피벗.

## 구조

앞뒤 범퍼와 보닛·트렁크·옆면이 공유하는 표면 함수로 경계를 맞췄습니다. 범퍼에는 실제 램프·그릴 개구부와 안쪽 받침이 있고, 유리는 얇은 곡면 셸입니다. 문 4개, 바퀴 4개, 핸들은 독립 그룹과 피벗으로 분리했습니다. 문 안쪽 패널, 앞좌석 2개, 뒤 벤치, 대시보드, 콘솔, 페달, 룸미러와 화면을 포함합니다.

Blender 단위는 미터입니다. 앞 방향은 -Y, 위는 +Z, 운전석/차량 왼쪽은 +X입니다. GLB는 내보내기 도구의 Y-up 변환을 사용합니다. 프로젝트 native 내보내기는 Roblox 좌표 `(-X, Z, Y)`와 1 stud = 0.28m를 사용하며 문·바퀴·핸들의 피벗을 연결합니다.

기존 Tripo S2 생성 원본의 세단 비율을 참고했으며, 메시와 세부 구조는 새로 작성했습니다. 내려받은 예시 모델의 메시·UV·텍스처는 복사하지 않았습니다. 추가 Tripo 생성과 크레딧 사용은 없습니다.

## 검증 범위와 남은 단계

저장된 `.blend`를 다시 읽어 메시 경계, 비다양체 연결, 퇴화 삼각형, UV와 노멀을 검사했습니다. 실내·핸들·문 안쪽 패널과 여섯 유리 메시의 삼각형 교차도 별도로 확인합니다. 최신 수치는 JSON 검사 결과를 기준으로 합니다.

현재 저장본은 **176,384삼각형 / 343개 메시**입니다. 열린 경계, 과도 연결 모서리, 퇴화 삼각형, 잘못된 UV/노멀 및 검사 대상 실내-유리 교차는 0개입니다. GLB 삼각형 수 일치와 버퍼·인덱스·노멀·UV·3개 내장 이미지도 검사했습니다. 디자인 승인은 이 자동 검사와 별도로 사용자가 전달했습니다.

2026-10-18 핸들 국소 수정: 핸들 뒤에서 계기판 쪽으로 올라가던 기둥을 제거하고, 사용자 표시 위치인 대시보드 하단에서 핸들 허브로 연결했습니다. 핸들 림·허브의 위치와 나머지 메시/UV/배치를 보존했습니다. `steering-mount-change.json`에 보존 서명을 기록했습니다.

이후 방향 교정: 핸들 중심과 하단 연결 위치를 유지하면서 핸들 면이 운전자 머리 방향을 향하도록 기울기를 고쳤습니다. 림 위쪽은 앞유리 쪽, 아래쪽은 운전자 쪽이며, 패드와 버튼도 운전자 면에 배치했습니다. `steering-orientation.json`에 방향 및 나머지 메시 보존 결과가 있습니다. `S3_Cockpit.png`와 `S3_SteeringMount.png`가 이 수정 후 운전석 화면입니다.

`tools/export_s3_project_assets.py`가 승인된 원본을 읽어 삼각형을 유지한 채 재질·동작 그룹별 **84개 렌더 부품**으로 합칩니다. `assets/vehicles/local/manifest.json`이 현재 프로젝트 모델 목록입니다. 유일한 `Ro.rbxlx`의 기존 차량에 외형·실내·화면을 반영하며 기존 주행·탑승·문·바퀴·핸들 동작에 연결합니다. 사용자 주차 위치와 인스턴스 참조를 보존합니다. 자동 검사는 `tests/s3_project_assets.py`, `tests/vehicle_project.py`, `tests/vehicle_installation.py` 및 `dist/model-application-validation.json`을 확인합니다. Studio Play에서 실제 주행·문 개폐 간섭·아바타 동작·성능은 아직 확인하지 않았으며 최종 LOD 예산을 확정하지 않습니다.

## 재현

프로젝트 최상위에서 Pillow를 사용할 수 있는 Python으로 `tools/make_s3_graphics.py`를 실행합니다. 이후 환경에서 찾은 Blender 실행 파일을 사용합니다.

```powershell
& $s3Blender --background --disable-autoexec --python-exit-code 1 --python tools/build_bora_s3.py
& $s3Blender --background --disable-autoexec --python-exit-code 1 --python tools/review_bora_s3.py
& $s3Blender --background --disable-autoexec --python-exit-code 1 --python tools/review_bora_s3.py -- --beauty
python tools/validate_s3_glb.py
```

위 제작 명령은 이 폴더의 제작 파일을 갱신합니다. 프로젝트 반영은 `tools/build_tree_v4.luau`에서 별도로 진행합니다. 예시 원본과 기존 S2 파일을 보존하며 Studio를 실행하지 않습니다.
