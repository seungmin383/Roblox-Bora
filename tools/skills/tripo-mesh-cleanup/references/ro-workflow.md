# 기존 Ro 신호등 작업을 이어갈 때

이 문서는 이 스킬이 만들어진 Ro 작업의 재사용 예시다. 다른 모델에 신호등 치수나 프로젝트 보존 규칙을 복사하지 않는다.

## 경로와 보존

프로젝트 위치는 `C:/Users/jinug/Desktop/SEUNGMIN_BAEK/Ro`다. 현재 프로젝트인지 확인하고 루트 `AGENTS.md`를 먼저 따른다.

- 유일한 Place는 루트 `Ro.rbxlx`다. 추가 `.rbxl`/`.rbxlx`, 테스트 맵, Place 백업을 만들지 않는다.
- 맵 배치와 사용자 편집을 보존한다. Place를 바꿔야 한다면 저장 상태를 먼저 맞추고 기존 빌드 진입점 `tools/build_tree_v4.luau`를 사용한다.
- 사용자는 가상 데스크톱 전환을 원하지 않는다. Studio를 자동 실행하거나 활성화하지 않는다.
- 메시 수정본 제작은 Place 반영과 별개다. 신호등 수정본을 만들었다고 실제 게임에 적용됐다고 보고하지 않는다.

기존 자산 구조:

| 경로 | 역할 |
| --- | --- |
| `assets/traffic/source/` | Tripo 생성 원본 |
| `assets/traffic/local/` | 기존 게임용 자산. 별도 적용 요청 전에는 보존 |
| `assets/traffic/retopology/TrafficSignal_Clean.*` | 차량 신호등 수정본 |
| `assets/traffic/retopology/PedestrianSignal_Clean.*` | 보행자 신호등 수정본 |
| `assets/traffic/retopology/cleanup-report.json` | 두 자산의 형상·삼각형·거리 검사 결과 |
| `dist/preview/` | 솔리드·와이어프레임 검토 이미지 |

## 기존 코드

- `tools/clean_signal_topology.py`: 수정본 생성, 보호 태그, UV/도장 베이크, 원본 비교, native 메시 내보내기와 렌더.
- `tools/signal_housing.py`: 승인된 본체 형상, 부품 결합.
- `tools/signal_hoods.py`: 차량용 원형 두께 차양과 뿌리 플랜지.
- `tools/signal_optics.py`: 별도 측정한 렌즈 중심, 규칙적인 원형 테두리, 볼록 렌즈.
- `tools/signal_details.py`: 단순한 닫힌 클립·받침·곧은 리브.
- `tools/pedestrian_displays.py`: 보행자용 사각 차양, 평평한 표시 면, 테두리와 볼트.

모델을 다룰 때 좌표는 이미 Roblox 기준 Y-up, 앞은 음의 Z다. Blender에서 임의 축 변환을 다시 적용하지 않는다. 모든 다른 Tripo 모델이 같은 좌표계를 갖는다는 뜻은 아니다.

실행 파일은 환경에서 찾고, 기존 Python/Blender를 백그라운드로 이용한다. 파일 생성 전 측정 검사만 할 수 있다.

```powershell
& $blenderExe --background --python-exit-code 1 --python tools/clean_signal_topology.py -- --traffic --validate-only
& $blenderExe --background --python-exit-code 1 --python tools/clean_signal_topology.py -- --pedestrian --validate-only
```

검사 후 해당 자산만 갱신하려면 `--validate-only`를 뺀다. 이 명령은 `*_Clean.blend/.mesh/.png`와 보고서를 갱신하며 Place를 만들지 않는다. 기본 두 자산 동시 실행 대신 수정 대상만 선택한다.

저장된 수정본 검증 도구:

- `tests/signal_topology_candidates.py`: native 파일, UV/노멀, 예산, 원본 해시와 단일 Place 보존.
- `tools/validate_saved_signal_hoods.py`, `tools/validate_saved_signal_optics.py`, `tools/validate_saved_signal_details.py`: 차량 신호등의 단계별 승인 형상과 새 부품 검사.
- `tools/validate_saved_pedestrian_displays.py`: 보행자 차양·표시 면·고정 부품의 닫힘, 직선 벽, 노멀, 승인된 본체와 차량 자산 보존.

검증 스크립트의 기준 서명은 승인 당시 형상이다. 서명 불일치가 나면 원인을 확인하며, 검사를 통과시키려고 기준 파일을 새 결과로 덮어쓰지 않는다. 사용자가 그 형상 변경을 요청한 경우에만 해당 기준과 검사를 의도적으로 갱신한다.
