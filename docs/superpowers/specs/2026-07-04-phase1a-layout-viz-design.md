# DREADPULSE Phase 1a — 함선 레이아웃 + 시각화 v2 설계 문서

- 날짜: 2026-07-04
- 근거: [DREADPULSE_GDD.md](../../DREADPULSE_GDD.md) §5 (레이아웃), §8 (비주얼 방향성)
- 선행: [Phase 0 설계](2026-07-04-dreadpulse-phase0-design.md) — 전투 코어·이벤트 스트림 완성 상태
- 상태: 사용자 승인 대기

## 1. 목적과 범위

빌드가 "부품 목록 + 배선"에서 **"함선 위 어느 슬롯에 무엇이 붙었는가"** 로 승격된다.
디자인 필라 #2("빌드가 곧 화면이다")의 최소 구현: 실루엣 + 슬롯 배치 + 배선 흐름이
텍스트를 읽지 않아도 보이게 한다.

### 목표
- 선체 정의 데이터(`sim/hulls/standard_hull.json`): 실루엣 폴리곤, 흘수선, 슬롯 13개
- 빌드 스키마 v2: 부품별 `slot` 필드 + 마운트 규칙 검증
- battle_view v2: 실루엣·슬롯·부품·배선 렌더링, 펄스가 배선을 타고 흐르는 플래시
- 이벤트 자기서술화(Phase 0 이월): `pulse_arrived`에 `from`, `stack_gained`에 `name`
- **전투 수치 불변**: 기존 82개 단위 테스트 무수정 통과 + 배치 지표 결과 동일

### 비목표
- 펄스 거리 지연/감쇠, 슬롯 성장·침수 복구 (Phase 2)
- 존 태그 기반 시너지 효과 (1b에서 데이터만 활용 시작)
- 도트 아트, 노멀맵, 셰이더 (Phase 3 — 지금은 폴리곤+박스)
- 복수 선체 종류 (표준 선체 1종만; 스키마는 복수 지원 형태로)

## 2. 선체 데이터 모델

`sim/hulls/standard_hull.json` — 로컬 좌표계(캔버스 400×240 기준, 흘수선 y=150):

```json
{
  "name": "standard_hull",
  "canvas": [400, 240],
  "waterline_y": 150,
  "silhouette": [[정점 배열 — 함수(좌)→함미(우) 측면 폴리곤, 함교 상부구조 포함]],
  "slots": [
    {"id": "D1", "zone": "deck", "section": "bow", "pos": [70, 78], "hardpoint": true},
    {"id": "D2", "zone": "deck", "section": "bridge", "pos": [150, 58], "hardpoint": true},
    {"id": "D3", "zone": "deck", "section": "engine", "pos": [230, 78], "hardpoint": true},
    {"id": "D4", "zone": "deck", "section": "stern", "pos": [310, 78], "hardpoint": true},
    {"id": "I1", "zone": "internal", "section": "bow", "pos": [70, 120], "hardpoint": false},
    {"id": "I2", "zone": "internal", "section": "bridge", "pos": [140, 120], "hardpoint": false},
    {"id": "H",  "zone": "internal", "section": "engine", "pos": [210, 120], "hardpoint": false},
    {"id": "I3", "zone": "internal", "section": "engine", "pos": [260, 120], "hardpoint": false},
    {"id": "I4", "zone": "internal", "section": "stern", "pos": [310, 120], "hardpoint": false},
    {"id": "I5", "zone": "internal", "section": "stern", "pos": [350, 130], "hardpoint": false},
    {"id": "B1", "zone": "below", "section": "bow", "pos": [90, 185], "hardpoint": true},
    {"id": "B2", "zone": "below", "section": "engine", "pos": [210, 185], "hardpoint": true},
    {"id": "B3", "zone": "below", "section": "stern", "pos": [300, 185], "hardpoint": true}
  ]
}
```

```
            D1   D2   D3   D4        ← 갑판 하드포인트 (실루엣 밖 돌출)
        ┌────┬────┬────┬────┐
 함수 ◁ │ I1 │ I2 │ [H] I3 │ I4  I5 │ ▷ 함미
        └────┴────┴────┴────┘        [H] = 심장 전용 슬롯 (기관부)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  ← 흘수선 y=150
              B1   B2   B3           ← 선저 하드포인트 (촉수 등)
```

- 심장은 `H` 슬롯 고정 (GDD §5.1 "심장은 기관부에 고정").
- 실루엣 폴리곤의 정확한 정점 좌표는 구현 계획에서 확정 (플레이스홀더 — "군함으로 읽히는" 측면 실루엣이면 됨. 함수 상향 경사, 함교 상부구조, 함미 순).
- 로더: `build_loader.gd`에 `load_hull(name := "standard") -> Dictionary` 추가 (기존 load_build와 같은 에러 정책).

## 3. 카탈로그 확장 — `mount` 필드

각 부품 정의에 `mount` 추가. 융합은 기본 부품의 mount를 유지한다(get_def가 name/effects만 치환하므로 자동).

| mount | 부품 | 배치 가능 슬롯 |
|---|---|---|
| `"heart"` | heart | `H` 전용 |
| `"hardpoint"` | main_turret, tentacle, eye | hardpoint: true 슬롯 (D*, B*) |
| `"internal"` | boiler, magazine, autoloader, steam_turbine, armor_bulkhead, ganglion, gills, cyst, ancillary_heart | hardpoint: false 슬롯 (I*, H 제외) |

## 4. 빌드 스키마 v2 + 검증

```json
{"id": "t1", "type": "main_turret", "graft": "nerve", "slot": "D2"}
```

- `Ship.load_build(build, hull_def := {})` — 두 번째 인자 추가(기본 빈 Dict).
  - `hull_def`가 비어 있으면 슬롯 검증 전체 생략 → **기존 인라인 테스트 빌드 무수정 호환**.
  - `hull_def` 제공 시 검증(전부 `load_errors` 누적):
    슬롯 필드 누락 / 존재하지 않는 슬롯 ID / 슬롯 중복 점유 / 마운트 규칙 위반
    (hardpoint 부품이 내부 슬롯에, internal 부품이 하드포인트에, heart가 H 외 슬롯에/타 부품이 H에).
- `Part`에 `slot`, `zone`, `section` 필드 추가 (로드 시 복사. 1a에서는 전투 수치에 영향 없음 — 1b 존 시너지의 데이터 기반).
- 기존 빌드 5종(`sim/builds/*.json`)에 슬롯 지정 마이그레이션. 배치 러너·디버그 뷰는 hull_def를 전달하도록 변경.

## 5. 이벤트 확장 (자기서술화 — Phase 0 최종 리뷰 이월 해소)

- `pulse_arrived` 페이로드에 `"from": <직전 부품 id>` 추가 (BFS가 엣지를 이미 앎 — pulse_network.gd 한 줄).
- `stack_gained` 페이로드에 `"name": <표시명>` 추가 → battle_view의 `sim.ships` 런타임 참조 제거.
- 스펙 §6 이벤트 계약(Phase 0 문서)의 페이로드 목록 갱신.

## 6. battle_view v2

- **배치**: 좌 = 플레이어 함(함수가 오른쪽을 향하게), 우 = 적함(좌우 반전 — scale 반전이 아니라 **좌표 미러링**으로 계산해 텍스트가 뒤집히지 않게). 중앙 상태 패널(hull/자원/interval)과 하단 로그, 상단 컨트롤 바는 Phase 0 그대로.
- **렌더링(부품별 노드)**: 실루엣 = `Polygon2D`(선체 채움) + `Line2D`(윤곽), 흘수선 = 반투명 수평선. 빈 슬롯 = 얇은 외곽선 박스. 부품 = 슬롯 좌표의 ColorRect(강철 청회 / 생체 자주 / 심장 적색) + charge 게이지. 배선 = 슬롯 중심 간 `Line2D`.
- **애니메이션(이벤트 구동)**: `pulse_emitted`(origin=heart) → 심장 박스 펄스 플래시. `pulse_arrived` → `from→part` 배선 Line2D 플래시 + 부품 게이지 갱신. `part_fired`/`misfire`/`part_destroyed` → Phase 0과 동일한 박스 플래시/회색화.
- 창 크기: 함선 캔버스 2개(각 400×240 스케일)가 들어가도록 뷰포트 1280×720 권장 (프로젝트 세팅, MCP로 변경).

## 7. 에러 처리 / 테스트

- 헐 JSON 로드 실패·스키마 이상(slots 누락 등) → push_error + 빈 Dict (load_build와 동일 정책).
- 단위 테스트 추가: 헐 로드, 정상 슬롯 빌드 통과, [슬롯 누락 / 미존재 슬롯 / 중복 점유 / 마운트 위반 / 심장 위치 위반] 각 거부, 기존 인라인 빌드(헐 미제공) 호환.
- 회귀: 기존 82개 무수정 통과, 배치 러너 지표 결과 동일(전투 수치 불변 증명).
- 시각 검증: MCP `play_scene` + 스크린샷 — 실루엣이 군함으로 읽히는가, 하드포인트 돌출이 보이는가, 펄스가 배선을 타고 흐르는가.

## 8. 결정 기록

| 결정 | 이유 |
|---|---|
| 슬롯 13개 (D4/I5+H/B3) | 현 빌드 최대 7부품 + 1b 확장 여유. Phase 2 슬롯 성장의 기저값 |
| hull_def 미제공 시 검증 생략 | 기존 인라인 테스트 무수정 호환. 실전 경로(배치·뷰)만 헐 강제 |
| 미러링은 좌표 계산으로 | scale.x=-1은 텍스트/게이지가 뒤집힘 |
| 존/구획 태그는 1a에서 비활성 데이터 | 전투 수치 불변 원칙. 1b 존 시너지에서 활성화 |
| gills는 internal | 흘수선 아래가 로어에 맞지만 마운트 3종 규칙 단순성 우선. 1b에서 zone 선호로 재검토 |
