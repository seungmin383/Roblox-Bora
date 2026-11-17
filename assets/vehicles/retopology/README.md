# BORA S2 차량 정리본

> 2026-10-18 사용자 평가: 마지막 `BoraS2_FitFix`는 실패한 결과이며 승인된 제작 기반이 아닙니다. 아래의 자동 검사 통과 이력은 외형 품질 승인을 의미하지 않습니다. 다음 자동차 작업은 `docs/vehicle-reference.md`의 사용자 제공 예시 분석을 먼저 확인합니다.

이 폴더의 `BoraS2_Clean.blend`가 최종 편집 파일입니다. `BoraS2_Clean.glb`에는 차량과 재질만 들어 있으며, 사진용 바닥·조명·카메라는 내보내지 않았습니다. 현재 `Ro.rbxlx`의 차량은 교체하지 않았습니다.

## 확인할 파일

- `BoraS2_Overview.jpg`: 전면·후면·문 열림·1인칭 확인용 이미지
- `BoraS2_Clean.blend`: 텍스처를 내장한 편집 파일. Body / DoorFL·FR·RL·RR / WheelFL·FR·RL·RR / Steering 컬렉션으로 구분했습니다.
- `BoraS2_Clean.glb`: 일반 가져오기용 자산
- `native/manifest.json` 및 `.mesh`: 기존 프로젝트 방식의 피벗 상대좌표 메시. 49개 파트이며 개별 파트는 8,000삼각형 이하입니다.

## 정리한 부분

Tripo에서 차 전체를 두 후보로 생성하고 P2.0 후보를 선택했습니다. 이 후보의 차체 표면을 기준으로 문을 분리했습니다. 차체·후드·범퍼의 큰 곡면은 해당 원본의 표면 표본으로 맞추고, 유리·지붕·창 하단 연결·실내·바퀴·핸들은 이 차의 치수에 맞춰 정리했습니다. 그릴은 얕은 패널과 텍스처 무늬입니다. 계기판과 내비 화면도 텍스처이며, 실제 브랜드 엠블럼과 바퀴 로고는 제거했습니다.

실내는 1인칭 기본 시야용으로 단순화했습니다. 외장·문·유리의 같은 곡면을 기준으로 맞췄으며, 이전 S1의 문이나 지붕을 가져다 붙이지 않았습니다. 저장된 블렌드의 사진용 실내 보조 조명은 게임 자산에 포함하지 않습니다.

## 검사와 현재 범위

- 저장본 재로드 기준 차량 전체 **37,942삼각형**
- 모든 메시의 열린 경계·비다양체 모서리·퇴화 삼각형·잘못된 좌표/UV/노멀: 검사 통과
- 네 타이어의 외경 반지름 0.338m, 같은 원형 단면·정렬·공용 그룹 피벗 확인
- GLB와 native 파일의 인덱스·노멀·UV·삼각형 수·텍스처 경로 확인
- 보호한 기존 파일 변경 없음. Place는 최상위 `Ro.rbxlx` 하나입니다.

이는 모델 정리 및 파일 검사 결과입니다. Roblox Studio 실행, 기존 차량 교체, 주행·탑승·문 충돌 시험은 이번 작업에 포함하지 않았습니다. 새 외장으로 교체할 때 기존 섀시와 조작 스크립트에 그룹·치수를 맞춰야 합니다.

## 원본 기록

선정 작업: https://studio.tripo3d.ai/ko/workspace/generate/b1e76032-3d84-48ca-98b7-dbf272ea6cab

생성 두 번과 텍스처 한 번에 총 175크레딧을 사용했습니다. 원본은 `../source/BoraS2_*`에 유지합니다. 세부 이력은 `BoraS2_Provenance.json`, 검사 결과는 `BoraS2_Audit.json`, `BoraS2_SkinInspection.json`, `BoraS2_ExportValidation.json`입니다.

## 다시 생성하는 순서

`make_s2_textures.py` → `prepare_s2_scene.py` → `clean_s2_sedan.py` → `finalize_s2_sedan.py` → `qa_s2_sedan.py` → `validate_s2_exports.py` → `package_s2_delivery.py`

모든 도구는 자산 폴더에서만 작업하며, Place를 만들거나 Studio를 실행하지 않습니다.
