# THE FIRST DIVERGENCE — Phase 0 설계 문서

- 날짜: 2026-08-29
- 근거 문서: [THE_FIRST_DIVERGENCE_GDD.md](../../THE_FIRST_DIVERGENCE_GDD.md) (v0.1)
- 상태: 사용자 승인 완료 (접근안 + 범위), 스펙 리뷰 대기
- 선행 프로젝트: DREADPULSE (폐기). 브랜치 `phase0-combat-sim`에 히스토리 보존.

---

## 1. 목적과 범위

기획서 §61의 프로토타입 검증 목표를 **숫자와 이벤트 로그로** 검증하는 전투 시뮬레이터를 만든다.
아직 게임이 아니다. "이 엔진이 재밌는 구조인가"를 판정하는 계측 장비다.

### 목표 (Goals)

- 쿨타임 기반 파츠의 실시간 자동전투 루프 구현 (양측 대칭)
- **ACTIVE / AUGMENT 이중용도** 파츠를 데이터 병합으로 표현 (§3.2, §16)
- 트리거 연쇄작동 엔진 — A→B→C 체인이 이벤트 스트림으로 관측 가능 (§3.1, §56)
- 공용 자원 2종: 자재 / 공명 (§22~24)
- 구조 파괴 시스템: 파괴선 75/50/25%, 파손 상태, 보강, 복구 (§18~20, §32~33)
- 3팩션 파츠 18종(팩션당 6) + First Relic 3종 + 적 6종 (§62 권장 하한)
- 결정론적 시뮬레이션 (고정 틱 + 주입 시드 RNG) → 배치 통계 검증 가능
- 검증 지표 5종 자동 리포트
- 디버그 시각화: 슬롯 보드 + 쿨타임 바 + **Trigger Chain 로그 스트림**

### 비목표 (Non-Goals) — Phase 1 이후로 명시적 연기

| 항목 | GDD 절 | 연기 사유 |
|---|---|---|
| 동조 / ATTUNEMENT | §29 | 엔진이 먼저 작동해야 측정 가능 |
| 전투 추가 목표 / OBSERVATION CONDITION | §30~31 | 위와 동일 |
| Experimental Condition, Archive, 과거 함선 전투 | §34~38 | 메타 계층. 전투가 확정된 뒤 |
| 맵 노드, Salvage 드래프트, Workshop | §12 | 런 구조 |
| Elite / Boss | §62 | 일반전 밸런스가 먼저 |
| 조립 UI, 플레이어 조작 | §17 | Phase 0은 빌드를 JSON으로 준다 |
| 팩션 Frame 3종 | §15 | 기본 Frame 1종으로 충분히 검증됨 |
| 확장 팩션 (Null Choir / The Maw / Eidola) | §55 | 기획서가 명시적으로 제외 |

---

## 2. 아키텍처 — 3층 분리

```
res://
├── sim/          순수 로직. Node/씬/Engine 싱글톤 참조 금지. 결정론 보장.
├── tests/        헤드리스 러너. sim이 방출한 이벤트 스트림만 집계.
└── debug/        시각화 씬. 이벤트 스트림만 소비. sim 내부 상태 직접 접근 금지.
```

**의존 방향은 한 방향뿐이다.** `sim/`은 자신을 누가 쓰는지 모른다. 매 틱 **이벤트 배열**을
방출하고, 배치 러너는 그걸 집계만, 디버그 씬은 그걸 그리기만 한다.
이 코어가 그대로 Phase 1+의 실전 전투 엔진이 된다.

### 2.1 파일 배치

```
sim/
  combat_sim.gd      전투 1판: 틱 루프, 양측 갱신, 파괴선 검사, 승패 판정
  ship_state.gd      함선: Frame 슬롯 + Active 파츠 + Relic + HP/보호막/자재/공명
  part.gd            파츠 런타임: 쿨타임, 가속·둔화 잔여시간, 남은 발동 횟수, 보강, 파괴 불가, 파손
  trigger_engine.gd  이벤트 큐 → 트리거 매칭 → 조건 평가 → 액션 실행 → 새 이벤트
  actions.gd         원자 액션 op 테이블
  conditions.gd      where 조건 평가기
  targeting.gd       target 셀렉터 해석
  catalog.gd         파츠/Frame/빌드 JSON 로더 + 스키마 검증
  data/
    parts/reclaimer.json  viridia.json  aeonic.json  relics.json
    frames/standard_frame.json
    builds/*.json         테스트용 플레이어 빌드
    enemies/*.json        적 고정 빌드 6종
tests/
  run_unit.gd        단위 검증 (exit code 0 = 통과)
  run_batch.gd       배치 러너 + 검증 지표 5종 리포트
  out/               리포트/CSV (gitignore)
debug/
  battle_view.tscn   디버그 씬
  battle_view.gd     이벤트 스트림 구독 → 그리기
```

`sim/`의 모든 클래스는 `RefCounted` 기반. `class_name` 대신 `preload` const로 참조한다
(전역 클래스 이름 오염 방지 — 이전 프로젝트에서 검증된 규약).

---

## 3. 핵심 설계 결정 — 효과를 데이터로 표현한다

이 게임의 전부는 §3.1 "A가 B를 작동시키고, B가 C를 작동시키고, C가 다시 A를 강화하는 구조"다.
따라서 **효과 표현 방식이 아키텍처의 전부**다.

### 3.1 채택안: 선언적 트리거 규칙 + 원자 액션

파츠는 `{on: 이벤트, where: 조건, do: [액션…]}` 형태의 규칙 배열을 갖는다.
액션 실행이 다시 이벤트를 낳고, 그 이벤트가 다른 트리거를 깨워 체인이 형성된다.

**기각한 대안:**

- *파츠별 GDScript 콜백* — AUGMENT는 부모 파츠의 동작을 **합성**해야 하는데 콜백은 합성이 안 된다.
  또한 파츠 추가가 코드 변경이 되어 데이터 확장성을 잃는다.
- *하이브리드 (일반=데이터, First Relic=코드 훅)* — §54 유물 4종을 전부 선언적으로 표현할 수
  있음을 확인했으므로 지금은 불필요. 정말 막히는 유물이 나오면 그때 훅을 추가한다.

### 3.2 AUGMENT = 데이터 병합

기획서 §16이 요구하는 AUGMENT의 세 가지 작용이 그대로 세 가지 병합 연산이 된다:

| GDD 요구 | 구현 |
|---|---|
| 새 Trigger 추가 | `augment.triggers`를 숙주의 트리거 목록에 append |
| 새 Keyword 추가 | `augment.add_keywords`를 숙주의 키워드 집합에 union |
| 기존 효과 변경 | `augment.modify`가 숙주의 쿨타임/피해 등에 배율·가산 적용 |

파츠 JSON은 `active` 블록과 `augment` 블록을 **나란히** 갖는다. 이것이 §3.2 dual-use의
데이터적 실체다. 하나의 파츠 정의를 어느 블록으로 읽느냐만 다르다.

**강화에 사용한 파츠는 동시에 Active로 사용할 수 없다** (§16) — 빌드 검증에서 강제한다.

---

## 4. 시뮬레이션 모델

### 4.1 시간

- 고정 틱 `TICK_DT = 0.05초`.
- 쿨타임은 배율 누산: `cooldown_progress += TICK_DT * speed_mult`. `가속`/`둔화`가 `speed_mult`를 바꾼다.
- 전투 시간 상한 `MAX_COMBAT_TIME = 120초`. 초과 시 잔여 HP 비율로 판정승, 동률이면 무승부.
  (§30의 "20초 이내 승리" 같은 조건을 고려하면 일반전은 20~60초 스케일이어야 한다.)

### 4.2 발동 상한 — 초당 5회

**모든 파츠는 마지막 발동으로부터 `MIN_FIRE_INTERVAL = 0.2초`가 지나기 전에는 발동할 수 없다.**

- 가속이 아무리 누적되어도 실효 쿨타임은 0.2초 아래로 내려가지 않는다.
- 체인이 `fire_part`로 강제 발동시킨 경우에도 동일하게 적용된다.
- `다중 발동` 키워드는 "한 번의 발동 안에서 효과를 여러 번 실행"이므로 상한에 걸리지 않는다.
- 틱 0.05초와 정확히 맞아떨어진다 (0.0 / 0.2 / 0.4 / 0.6 / 0.8초 = 초당 5회).

이 상한은 밸런스 장치이자 **무한 체인 방지 장치**를 겸한다. 상한에 막힌 발동은
`part_fire_blocked{reason: "rate_cap"}` 이벤트를 남기므로, 배치 리포트에서 상시 상한에
걸려 있는 파츠(= 밸런스 이상)를 탐지할 수 있다.

### 4.3 결정론

- 모든 확률은 시뮬레이션 외부에서 주입한 시드의 `RandomNumberGenerator`만 사용한다.
  전역 `randf()` / `randi()` 호출 금지.
- **같은 빌드 + 같은 시드 = 완전히 같은 이벤트 스트림.** 배치 검증의 전제다.
- 순회 순서가 결과에 영향을 주는 모든 지점(슬롯 발동 순서, 무작위 대상 선택 풀)은
  Dictionary가 아닌 정렬된 Array로 다룬다.

### 4.4 틱 순서

각 틱마다 아래 순서를 **양측에 대해 동시에** 수행한다 (선공 편향 방지: 3단계에서 양측
발동 후보를 모두 모은 뒤 슬롯 인덱스 순으로 해소).

1. **쿨타임 진행** — 모든 살아있는 파츠의 `cooldown_progress` 증가
2. **지속 효과 만료** — 가속/둔화/재생 지속시간 감소, 만료분 제거
3. **발동** — 준비된 파츠를 슬롯 순서로 발동. 비용(자재)이 부족하거나 남은 발동 횟수가
   0이면 발동하지 않고 `part_fire_blocked`. 이 발동으로 남은 횟수가 0이 된 파츠는
   효과를 정상 실행한 뒤 파손된다.
4. **체인 소진** — 3단계가 낳은 이벤트를 트리거 큐에 넣고 비워질 때까지 처리
5. **지속 피해/회복** — 과열 tick, 재생 tick
6. **파괴선 검사** — HP가 임계를 처음 통과했으면 파츠 파괴
7. **승패 판정** — HP 0 이하 또는 시간 초과

### 4.5 발동 제한

기획서 §21의 `발동 제한` 키워드다. 파츠의 **수명**을 나타내는, 파츠 단위의 유일한 카운터다.

- 파츠 런타임은 `fires_remaining` (int)을 갖는다. `-1`이면 무제한.
- 카탈로그에 `active.fire_limit`이 있으면 그 값이 초기값, 없으면 `-1`.
- 발동할 때마다 유한이면 1 감소. `0`이면 발동하지 못한다
  (`part_fire_blocked{reason: "fire_limit"}`).
- 남은 횟수가 `0` 이하가 되면 즉시 파손된다
  (`part_destroyed{cause: "fires_exhausted"}`).
  **발동으로 0이 된 경우 그 발동의 효과는 정상 실행된 뒤 파손된다** — 마지막 한 발은 나간다.
- `restore_part`는 파손을 풀면서 `fires_remaining`을 초기값으로 되돌린다.
- 보강 스택이 있으면 소모하고 파손을 막는다. 단 남은 횟수는 0인 채이므로 여전히 발동하지
  못한다 — 다시 쓰려면 `restore_fires`로 횟수를 회복시켜야 한다.

**적용 범위: 기본은 무제한이다.** `fire_limit`을 명시한 파츠(주로 Reclaimer)와,
`drain_fires`를 맞아 제한이 걸린 파츠만 유한해진다. 모든 파츠에 제한을 걸지 않는 이유는
두 가지다 — 장기전에서 양측 보드가 전부 멈춰 무승부가 폭증하는 것을 피하고,
`drain_fires`가 "이 파츠는 이제 수명이 정해졌다"는 **명확한 상태 변화**로 읽히게 하기 위함이다.

무제한 파츠가 `drain_fires`를 맞으면 그 순간 `fires_remaining`이
`DEFAULT_FIRE_LIMIT = 5`로 확정된 뒤 깎인다.

**이 축이 세 팩션이 갈라지는 지점이다** (§7.3). Reclaimer는 소진시켜 자재로 바꾸고,
Viridia는 회복시키고, Aeonic은 미리 당겨 쓴다. 같은 카운터에 서로 다른 문법을 얹는
것이 기획서 §60이 요구한 "팩션 전용 키워드 최소화"다.

> **용어 주의**: `과부하`는 이 메커니즘의 **Reclaimer 팩션 표현**일 뿐이다
> (Viridia는 `고갈`, Aeonic은 `위상 붕괴`). 코드 식별자와 키워드는 `fire_limit` 하나다.
> 스펙 어디에서도 `과부하`는 메커니즘 이름으로 쓰이지 않는다 — 팩션 표현임을 설명하는
> 자리에만 등장한다.

### 4.6 연쇄 안전장치

- **체인 깊이 상한** `MAX_CHAIN_DEPTH = 12`. 초과 시 `chain_capped` 이벤트를 남기고 중단.
- **틱당 파츠 재진입 상한** — 한 파츠는 한 틱에 최대 1회 발동 (4.2의 0.2초 상한이 이를 포함).
- 배치 리포트에서 `chain_capped` 발생률이 0이 아니면 **무한루프 설계 결함 신호**다 (§60 대책).

---

## 5. 데이터 스키마

### 5.1 파츠

```json
{
  "id": "supercharged_turbine",
  "name": "과급 터빈",
  "faction": "reclaimer",
  "roles": ["utility", "flexible"],
  "keywords": ["accelerate", "fire_limit"],

  "active": {
    "cooldown": 5.0,
    "fire_limit": 6,
    "cost": { "material": 0 },
    "on_fire": [
      { "op": "accelerate", "target": "self", "duration": 3.0 }
    ],
    "triggers": []
  },

  "augment": {
    "add_keywords": ["accelerate", "fire_limit"],
    "modify": { "cooldown_mult": 1.0 },
    "triggers": [
      { "on": "part_fired", "where": { "is_host": true },
        "do": [
          { "op": "accelerate",  "target": "host", "duration": 2.0 },
          { "op": "drain_fires", "target": "host", "amount": 1 }
        ] }
    ]
  }
}
```

`roles`에 나열된 역할의 슬롯 또는 `flexible` 슬롯에만 들어간다.

**Core 파츠도 다른 파츠와 똑같이 쿨타임을 갖고 발동한다.** "10초마다 공명 +1" 같은 주기
효과는 `cooldown: 10`으로 표현하고, "전투 시작 시" 효과는 `combat_start` 트리거로 표현한다.
Core만의 특별한 실행 경로는 없다 — Core가 다른 점은 파괴선 면제(§8)와 Augment 금지뿐이다.

Core 역할 파츠는 Phase 0에서 **ACTIVE 전용**이다 (`augment` 블록 없음) — Core는 빌드 방향을
결정하는 중심 파츠이므로(§14) 강화 재료로 소모되면 의미가 사라진다.

`on_fire`의 각 항목도 `triggers`와 동일하게 **선택적 `where`를 가질 수 있다.**
"공명 3 이상이면 보강 +1", "30초 이전이면 피해 +50%" 같은 조건부 효과가 이것으로 표현된다.

### 5.2 Frame

```json
{
  "id": "standard_frame",
  "name": "표준 Frame",
  "hull": 200,
  "slots": [
    { "id": "core",      "role": "core"     },
    { "id": "weapon_1",  "role": "weapon"   },
    { "id": "weapon_2",  "role": "weapon"   },
    { "id": "defense_1", "role": "defense"  },
    { "id": "utility_1", "role": "utility"  },
    { "id": "utility_2", "role": "utility"  },
    { "id": "flex_1",    "role": "flexible" }
  ],
  "relic_slots": 1,
  "thresholds": [0.75, 0.50, 0.25]
}
```

§13의 예시 Frame 그대로 (Core 1 / Weapon 2 / Defense 1 / Utility 2 / Flexible 1 = 7슬롯).
Relic은 역할 슬롯을 차지하지 않는 별도 1칸이다.

**Augment 슬롯은 Active 파츠당 1개**로 고정한다. 기획서에 개수 명시가 없고, 여러 개를
허용하면 조합 폭발이 Phase 0의 검증 신호를 흐린다. Phase 1에서 재검토한다.

### 5.3 빌드

```json
{
  "id": "reclaimer_pure",
  "frame": "standard_frame",
  "relic": null,
  "slots": {
    "core":      { "part": "scrap_reactor" },
    "weapon_1":  { "part": "rivet_railgun", "augment": "supercharged_turbine" },
    "weapon_2":  { "part": "rivet_railgun" },
    "defense_1": { "part": "weld_plating" },
    "utility_1": { "part": "breaker" },
    "utility_2": { "part": "venting_manifold" },
    "flex_1":    { "part": "breaker" }
  },
  "links": []
}
```

`links`는 §21 `link` 키워드의 데이터 표현이다 — 슬롯 id 쌍의 배열
(`[["utility_1","weapon_1"], ["utility_1","weapon_2"]]`)이며 방향이 없다.
Phase 0에서는 빌드에 명시적으로 적는다. 위 예시 빌드에는 `link` 키워드를 가진 파츠가
없으므로 비어 있다.

**빌드 검증** (로드 시 실패):
역할 불일치 / 존재하지 않는 파츠 id / 존재하지 않는 Frame·Relic id / Core 슬롯 비어 있음 /
Core 파츠를 Augment로 사용 / `augment` 블록이 없는 파츠를 Augment로 사용 /
존재하지 않는 슬롯을 `links`에 지정 / Relic을 `relic_slots`보다 많이 지정.

같은 파츠 **id**를 여러 슬롯에 쓰는 것은 허용한다 (위 예시의 `rivet_railgun` × 2, `breaker` × 2).
§16의 "강화에 사용한 파츠는 동시에 Active로 사용할 수 없다"는 **같은 물리적 인스턴스**에
대한 제약이고, 빌드 JSON의 각 항목은 서로 다른 인스턴스이기 때문이다. Salvage로 파츠
인벤토리가 생기는 Phase 1에서 인스턴스 단위 제약으로 승격한다.

---

## 6. 이벤트 · 트리거 · 액션 계약

이 절이 `sim/`과 `tests/`·`debug/` 사이의 **유일한 계약**이다.

### 6.1 이벤트

모든 이벤트는 `{ type, t, ship, ... }` 형태의 Dictionary다. `ship`은 `"player"` 또는 `"enemy"`.

| 이벤트 | 주요 필드 |
|---|---|
| `combat_start` | `player_build`, `enemy_build`, `seed` |
| `part_fired` | `slot`, `part_id`, `part_name`, `faction`, `chain_depth`, `cause` |
| `part_fire_blocked` | `slot`, `part_id`, `reason` (`rate_cap`/`broken`/`no_material`/`fire_limit`) |
| `damage_dealt` | `target_ship`, `amount`, `absorbed`, `source_slot` |
| `hull_changed` | `from`, `to`, `ratio` |
| `shield_gained` / `shield_absorbed` | `amount` |
| `repaired` / `regen_applied` / `regen_ticked` | `amount`, `duration` |
| `overheat_applied` / `overheat_ticked` | `stacks`, `damage` |
| `speed_changed` | `slot`, `state` (`accelerated`/`slowed`/`normal`), `duration` |
| `fires_changed` | `slot`, `delta`, `remaining`, `cause` (`fired`/`drained`/`restored`) |
| `part_destroyed` | `slot`, `part_id`, `cause` (`threshold`/`fires_exhausted`/`effect`) |
| `part_restored` | `slot`, `part_id` |
| `reinforce_gained` / `reinforce_consumed` | `slot`, `stacks` |
| `indestructible_applied` | `slot`, `duration` (`-1` = 영구) |
| `break_prevented` | `slot`, `part_id`, `cause`, `by` (`indestructible`) — 파손이 유예됨 |
| `threshold_crossed` | `threshold`, `destroyed_slot` |
| `material_gained` / `material_spent` | `slot`, `amount`, `total`, `source`/`sink` |
| `resonance_gained` | `amount`, `total`, `source` |
| `chain_capped` | `slot`, `part_id`, `depth` |
| `combat_end` | `winner`, `elapsed`, `reason` |

**이벤트는 자기서술적이어야 한다** — 소비자가 sim 내부를 조회하지 않고도 사람이 읽을 수 있는
줄을 만들 수 있을 만큼의 필드를 담는다 (이전 프로젝트에서 확인된 요구사항).

### 6.2 트리거

```
{ "on": <이벤트 타입>, "where": <조건>, "max_fires": <int>, "do": [ <액션>... ] }
```

`where`와 `max_fires`는 생략 가능. 여러 조건을 함께 쓰면 AND로 평가한다.
`max_fires: n`이면 이 트리거는 **전투당 n회까지만** 발동한다
(예: "숙주가 파괴되면 즉시 복구 — 전투당 2회"는 `max_fires: 2`).

> **이름 구분**: 파츠의 발동 횟수 제한은 `active.fire_limit`(§4.5),
> 트리거의 발동 횟수 제한은 `max_fires`다. 서로 다른 계층의 카운터다.

조건 목록:

| 조건 | 의미 |
|---|---|
| `resonance_at_least` | 자함 공명 ≥ n |
| `material_at_least` | 자함 자재 ≥ n |
| `before_seconds` / `after_seconds` | 전투 경과 시간 조건 (§27 Aeonic) |
| `every_nth_fire` | 이 파츠의 n번째 발동마다 |
| `every_nth_accumulated` | `{field, n}` — 이벤트의 해당 필드를 누적해 n의 배수를 넘을 때마다 |
| `is_host` | (augment 문맥) 이벤트 주체가 숙주 파츠인가 |
| `event_field` | `{field, equals}` — 이벤트의 임의 필드를 값과 비교 (예: `part_destroyed`의 `cause`, `part_fire_blocked`의 `reason`) |
| `source_faction` | 이벤트를 일으킨 파츠의 팩션 |
| `source_keyword` | 이벤트를 일으킨 파츠가 해당 키워드 보유 |
| `hull_below_ratio` | 자함 HP 비율 < r |
| `fires_remaining_at_most` | 대상 파츠의 남은 발동 횟수 ≤ n (무제한 파츠는 거짓) |
| `has_broken_own` | 자함에 파손 파츠가 존재하는가 |
| `own_ship` / `enemy_ship` | 이벤트가 발생한 함선 |

`prime_oscillator` Relic은 `resonance_at_least`의 요구치를 1 낮춰 평가한다 (§9.4).

### 6.3 액션

| op | 파라미터 |
|---|---|
| `deal_damage` | `amount` |
| `gain_shield` | `amount` |
| `repair` | `amount` |
| `apply_regen` | `amount`, `duration` |
| `apply_overheat` | `stacks` |
| `accelerate` / `slow` | `target`, `duration` — 배율은 고정(§6.5) |
| `drain_fires` | `target`, `amount`, `material_per_part`(선택) — 남은 발동 횟수를 깎고, 실제로 깎인 파츠 수에 비례해 자재 획득 |
| `restore_fires` | `target`, `amount` — 남은 발동 횟수 회복 (초기값 초과 불가) |
| `make_indestructible` | `target`, `duration` (`-1` = 영구) |
| `reduce_cooldown` | `target`, `ratio` |
| `destroy_part` / `restore_part` | `target` |
| `reinforce` | `target`, `stacks` |
| `empower` | `target`, `damage_mult`, `stacks` — 대상의 **다음 발동** 피해를 증폭. 발동 시 1스택 소모 |
| `gain_material` / `spend_material` | `amount` |
| `gain_resonance` | `amount` |
| `fire_part` | `target` (발동 상한·체인 깊이 적용) |
| `multi_fire` | `times`, `do`(선택) — 감싼 액션들을 같은 발동 안에서 n회 실행. `do`를 생략하면 **숙주(augment 문맥) 또는 자신의 `on_fire` 블록 전체**를 n회 반복한다. 발동 상한·발동 횟수를 소모하지 않는다 |

**공통 규칙:**

- 모든 액션 항목은 선택적 `where`를 가질 수 있다. 거짓이면 그 항목만 건너뛴다.
- 모든 액션 항목은 선택적 `delay`(초)를 가질 수 있다. 지정하면 그만큼 뒤 틱에 예약 실행된다
  (예: "숙주가 파괴되면 8초 후 자동 복구"). 예약된 액션은 전투가 끝나면 폐기된다.
- 지속시간을 받는 액션에서 `duration: -1`은 **전투 종료까지 영구**를 뜻한다.

### 6.4 대상 셀렉터

`self` / `host` / `linked` / `enemy_ship` / `own_ship` / `random_own_active` /
`slowest_own` (남은 쿨타임 최대) / `random_broken_own` / `all_own_active` /
`all_own_limited` (발동 제한이 걸린 아군 파츠 전부) / `random_own_limited`

무작위 셀렉터는 전부 주입된 시드 RNG를 쓴다.

**셀렉터는 `do` 블록 시작 시점에 한 번만 해석하고 결과를 블록 전체가 공유한다.**
액션마다 다시 평가하지 않는다. 이 규칙이 없으면
`[fire_part{slowest_own}, drain_fires{slowest_own}]`이 서로 다른 파츠를 건드리고,
`[restore_part{random_broken_own}, drain_fires{random_broken_own}]`은 첫 액션이 대상을
파손 상태에서 빼버려 두 번째가 빈손이 된다. 둘 다 실제 파츠(`future_debtor`, `phase_shifter`)의
동작이므로 계약으로 고정한다.

### 6.5 가속과 둔화 — 배율 고정, 시간만 다름

기획서 §21의 정의를 따른다. **증감폭은 항상 같고 효과마다 다른 것은 지속시간뿐이다.**

- `accelerate {target, duration}` — 지속시간 동안 쿨타임 진행 **×2**
- `slow {target, duration}` — 지속시간 동안 쿨타임 진행 **×0.5**
- 배율 파라미터는 없다. 파츠가 지정하는 것은 `duration` 하나다.
- **중첩**: 같은 종류가 겹치면 남은 지속시간을 **합산**한다.
- **상쇄**: 가속과 둔화가 동시에 걸리면 남은 시간끼리 상쇄한다 —
  짧은 쪽이 사라지고 긴 쪽에 차이만큼만 남는다.
- `speed_mult`는 저장하는 값이 아니라 파생값이다:
  가속만 `2.0` / 둔화만 `0.5` / 둘 다 없거나 상쇄되면 `1.0`.

이 결정의 부수 효과: 가속 상한이 ×2로 고정되므로 **쿨타임 0.4초 이상인 파츠는 자연 발동만으로
§4.2의 초당 5회 상한에 걸릴 수 없다.** Phase 0의 파츠는 전부 쿨타임 4초 이상이므로,
초당 5회 상한은 사실상 `fire_part` 강제 발동 전용 안전장치로 작동한다.

---

## 7. 자원 — 세 개의 축

전투 중 플레이어가 읽는 숫자는 세 종류뿐이고, 셋은 범위·방향·성격이 전부 다르다.

| 축 | 범위 | 방향 | 성격 |
|---|---|---|---|
| 자재 | 함선 | 벌고 쓴다 | 유동성 — 지금 무엇에 투자할까 |
| 공명 | 함선 | 오르기만 | 패턴 안정도 — 파츠들을 잇는 게이트 |
| 발동 횟수 | **파츠** | 소진되기만 | 수명 — 팩션별로 문법이 갈리는 축 |

**결정 기록 — 공명을 파츠별로 내리지 않는다.** 검토했으나 기각했다. 개별화하면 팩션 색깔과
파츠 단위 서사를 얻지만, 읽을 숫자가 슬롯 수만큼 늘고(§60 "지나친 툴팁 복잡성"),
무엇보다 **파츠 사이를 잇는 게이트가 사라져** §3.1("파츠 하나의 성능보다 파츠 사이의
연쇄작동")과 §28("별도의 혼종 전용 자원이 필요 없다")이 무너진다. 로어(§5·§24)와
최종 보스 기믹(§47 Synchronization)도 함선 단일 공명을 전제한다.
팩션별 차이는 세 번째 축(발동 횟수)에서 낸다.

### 7.1 자재 / MATERIAL (§23)

정수. 소비형. 전투 종료 시 리셋. 상한 없음. 팩션마다 생산 문법이 다르되 자원 자체는 공용이다.

### 7.2 공명 / RESONANCE (§24)

정수. **누적만 하고 감소하지 않는다.** 전투 종료 시 리셋.

기획서 §60은 "공명이 또 공명을 너무 빠르게 생성하면 사실상의 무한루프"를 경고하며
`행동 누적 → 공명`을 기본형으로 요구한다. Phase 0 기본 규칙:

> 자함 파츠 발동이 누적 **8회**마다 공명 +1.

파츠가 직접 공명을 생성하는 효과는 희귀하게 유지한다 (18종 중 2종 + Relic 1종).

### 7.3 발동 횟수 — 팩션이 갈라지는 축

파츠 단위 카운터다. 정의와 규칙은 §4.5에 있다. 세 팩션은 **같은 카운터를 서로 다른
문법으로** 다룬다 (§60 "팩션 전용 키워드를 최소화하고 같은 것을 다른 문법으로 사용한다"):

| 팩션 | 문법 | 표현 |
|---|---|---|
| Reclaimer | 소진시켜 자재로 바꾼다 (`drain_fires` + `material_per_part`) | 과부하 |
| Viridia | 회복시킨다 (`restore_fires`) | 고갈 |
| Aeonic | 미래분을 당겨 쓴다 (`fire_part` + `drain_fires`) | 위상 붕괴 |

§45 Divergent Resonance의 "한 시스템의 결함이 다른 시스템의 자원이 된다"가 이 축 위에서
실제로 돌아간다 — Aeonic이 당겨 쓴 횟수를 Reclaimer가 파손으로 회수해 자재로 만들고,
Viridia가 복구해 카운터를 되돌린다.

---

## 8. 구조 파괴 시스템 (§18~20, §32~33)

파손에 이르는 경로는 세 가지다: **파괴선 통과**, **발동 횟수 소진**(§4.5),
**`destroy_part` 액션**. 방어 수단은 두 가지고 성격이 다르다.

- **파괴선**: 최대 HP의 75% / 50% / 25%. **처음** 그 아래로 내려갈 때만 작동.
  한 번의 피해가 두 선을 통과하면 파츠 2개가 파괴된다. 수리해도 재활성화되지 않는다.
- **대상**: 파괴 가능한 Active 파츠 중 시드 RNG로 1개.
  이미 파손된 파츠와 `indestructible` 파츠는 후보에서 제외.
  후보가 없으면 아무 일도 일어나지 않는다.
- **보강** — 횟수제 방어. 대상 파츠에 보강 스택이 있으면 1 소모하고 파손을 막는다.
- **파괴 불가**(`indestructible`) — 기간제 면제. 파괴선 대상 선정 / 발동 횟수 소진 /
  `destroy_part` **전부**에서 면제된다. **보강보다 먼저 적용되며 보강 스택을 소모하지 않는다.**
  `make_indestructible {duration: -1}`이면 영구.
  **Core는 영구 `indestructible`을 기본 보유한다**(§14) — 별도의 예외 코드 경로가 아니다.
  남은 발동 횟수가 0인 채로 파괴 불가인 파츠는 파손이 **유예**되지만 발동하지 못하고,
  파괴 불가가 끝나는 순간 파손된다.
- **파손 상태**(§19): 효과 정지, 쿨타임 정지, **슬롯 유지**. 지속 효과도 정지.
  붙어 있던 Augment 효과도 함께 정지한다.
- **복구**(§21): 파손 파츠를 다시 활성화. 쿨타임은 0에서 재시작하고
  `fires_remaining`은 초기값으로 되돌아간다.

---

## 9. 콘텐츠 — 파츠 18종 + Relic 3종 + 적 6종

수치는 전부 플레이스홀더다. 배치 리포트가 §10의 지표를 통과하는 한 자유롭게 조정한다.

**아래 모든 효과는 §6의 이벤트·조건·액션 어휘만으로 표현 가능해야 한다.** 표현할 수 없는
파츠를 넣고 싶어지면, 파츠를 위해 코드를 고치기 전에 §6에 원자 연산을 추가할지부터 판단한다.
어휘를 늘리는 쪽이 옳은 경우는 그 연산이 최소 2종 이상의 파츠에서 재사용될 때뿐이다.

표기: `쿨 5초` = `active.cooldown`, `제한 6회` = `active.fire_limit`(없으면 무제한),
`가속 3초` = `accelerate {duration: 3.0}`(배율은 항상 ×2).

### 9.1 Reclaimer — Break & Rebuild (§25)

발동 횟수를 **소진시켜 자재로 바꾸는** 팩션. 제한이 걸린 파츠가 가장 많다.

| id | 이름 | 역할 | ACTIVE | AUGMENT |
|---|---|---|---|---|
| `supercharged_turbine` | 과급 터빈 | utility | 쿨 5초, 제한 6회: 자신 가속 3초 | 숙주 가속 2초, 숙주 횟수 −1 |
| `breaker` | 분해기 | utility | 쿨 8초: 자재 +2, 자함에 파손 파츠가 있으면 자재 +4 추가 | 아군 파츠가 파손될 때 자재 +4 |
| `rivet_railgun` | 리벳 레일건 | weapon | 쿨 6초, 제한 8회: 피해 18 | 숙주 발동 시 피해 6 추가, 숙주 횟수 −1 |
| `weld_plating` | 용접 장갑 | defense | 쿨 7초: 무작위 아군 파츠에 보강 +1, 선체 수리 8 | 숙주가 파손되면 즉시 복구 (`max_fires: 2`) |
| `venting_manifold` | 방출 다기관 | utility | 쿨 10초: 제한이 걸린 아군 파츠 전부의 남은 횟수 −1, 깎인 파츠 수 × 4 자재 | 숙주가 횟수 소진으로 파손될 때 자재 +6 |
| `scrap_reactor` | 폐선 재활용로 | **core** | 쿨 6초: 자재 +2. 시작 시 자재 +5. 자재를 누적 10 획득할 때마다 무작위 아군 파츠 가속 4초 | — |

### 9.2 Viridia — Grow & Connect (§26)

발동 횟수를 **회복시키는** 팩션. 자기 파츠에는 제한을 걸지 않는다.

| id | 이름 | 역할 | ACTIVE | AUGMENT |
|---|---|---|---|---|
| `regen_sac` | 재생낭 | defense | 쿨 4초: 자재 3 소비 → 선체 수리 10 | 숙주가 자재를 소비할 때 재생 2(5초) |
| `bio_nerve_cord` | 생체 신경삭 | utility | 쿨 7초: 연결된 파츠를 가속 4초 | 숙주에 `link` 부여. 공명 3 이상에서 숙주가 발동하면 연결된 파츠도 발동 |
| `proliferation_organ` | 증식 기관 | utility | 쿨 6초: 자재 +3 (공명 4 이상이면 +6) | 숙주가 3회 발동할 때마다 공명 +1 |
| `coral_spore` | 산호 포자탄 | weapon | 쿨 5초: 피해 12 + 적 과열 3 | 숙주 발동 시 적 과열 2 |
| `symbiotic_carapace` | 공생 갑각 | defense | 쿨 8초: 보호막 20 (공명 3 이상이면 보강 +1) | 공명이 오를 때마다 보호막 4 |
| `colony_heartcore` | 군체 심핵 | **core** | 쿨 10초: 재생 3, 제한이 걸린 아군 파츠 1개의 남은 횟수 +1, 공명 5 이상이면 모든 아군 파츠 가속 3초. 시작 시 보호막 30 | — |

### 9.3 Aeonic Covenant — Borrow & Foretell (§27)

발동 횟수를 **미리 당겨 쓰는** 팩션. 강제 발동과 짝지어 대가로 횟수를 깎는다.

| id | 이름 | 역할 | ACTIVE | AUGMENT |
|---|---|---|---|---|
| `future_debtor` | 미래 차입기 | utility | 쿨 6초: 남은 쿨타임이 가장 긴 아군 파츠를 즉시 발동시키고 그 파츠의 남은 횟수 −1 | 숙주 발동 시 숙주 쿨타임 40% 즉시 감소, 숙주 횟수 −1 |
| `foresight_lens` | 예견 렌즈 | weapon | 쿨 4초: 피해 10. 세 번째 발동마다 다중 발동 3 | 숙주의 세 번째 발동마다 숙주 효과를 2회 더 실행 (`multi_fire{times:2}`, `do` 생략) |
| `temporal_anchor` | 시간 고정장 | defense | 쿨 9초: 보강 +2, 보호막 15 | 전투 시작 시 숙주에 파괴 불가 15초 |
| `phase_shifter` | 위상 전환기 | utility | 쿨 7초: 파손 아군 파츠 1개 복구, 그 파츠의 남은 횟수 −2 | 숙주가 파손되면 8초 후 자동 복구 |
| `precognitive_sight` | 선행 조준기 | weapon | 쿨 5초: 피해 14 (30초 이전이면 +50%) | 공명이 오를 때마다 숙주의 다음 발동 피해 +30% |
| `convergence_core` | 수렴 코어 | **core** | 쿨 10초: 공명 +1. 시작 시 모든 아군 파츠 가속 10초 | — |

### 9.4 First Relic 3종 (§54)

| id | 이름 | 효과 |
|---|---|---|
| `resonance_relay` | Resonance Relay | 공명이 증가할 때 모든 아군 파츠를 가속 2초 |
| `prime_oscillator` | Prime Oscillator | 공명 조건이 있는 모든 효과의 요구 공명을 1 낮게 취급 |
| `convergence_engine` | Convergence Engine | 서로 다른 팩션의 파츠가 연속으로 발동하면 공명 +1 (최소 2초 간격) |

Relic은 룰브레이커다. `prime_oscillator`는 조건 평가기에, `convergence_engine`은 공명
규칙에 개입한다 — 즉 Relic은 **파츠가 아니라 함선 수준 modifier**로 구현한다.

### 9.5 적 6종 (§3.4 — Hard Counter가 아니라 성능 시험대)

적은 플레이어와 **같은 `ShipState`**에 고정 빌드를 얹은 것뿐이다.
이 대칭성 덕에 §38의 "과거 함선을 적으로 재현"이 Phase 1에서 공짜가 된다.

| id | 팩션 | 시험하는 성능 |
|---|---|---|
| `scrap_raider` | reclaimer | Burst — 저HP 고DPS, 초반에 못 끝내면 진다 |
| `hulk_breaker` | reclaimer | Destruction resistance — 파괴기를 들고 온다 |
| `spore_drifter` | viridia | Sustain — 과열 도트로 장기전을 건다 |
| `coral_bulwark` | viridia | Stability — 보호막·재생 탱크 |
| `chrono_lance` | aeonic | Scaling — 30초 이전에 폭발적, 이후 약화 |
| `phase_weaver` | aeonic | Recovery — 복구·보강으로 계속 되살아난다 |

---

## 10. 검증 지표 — 기획서 §61을 숫자로

배치 러너가 자동 리포트한다. 각 지표는 **통과 조건**을 갖는다.

배치 구성: 팩션 순수 빌드 3종 + 혼종 빌드 6종 + 무작위 생성 빌드 40종을, 적 6종 ×
시드 20개에 대해 돌린다 (49 × 6 × 20 = 5,880 전투). 무작위 빌드는 고정 시드로 생성해
리포트 간 비교가 가능하게 한다.

### A. Dual-use가 실제로 고민인가 (§61.A)

무작위 생성 빌드 집단에서 파츠별로 측정한다:

- **채택 균형**: 파츠 P가 등장한 빌드 중 Active로 쓰인 비율. 20~80% 밖이면
  "사실상 한쪽 전용" 실패 사례로 이름과 함께 열거.
- **승률 차**: P를 Active로 쓴 빌드의 승률 − Augment로 쓴 빌드의 승률.
  절댓값 15%p 이내면 통과(선택이 유의미). 초과 파츠를 열거한다.

### B. Trigger Engine이 읽히는가 (§61.B)

- 전투당 평균 체인 길이 **2~6**, 최장 체인 **≤ 12**
- `chain_capped` 발생률 **0%** (하나라도 나오면 설계 결함)
- `rate_cap`에 막힌 발동 비율 — 특정 파츠가 상시 상한에 걸려 있으면 밸런스 이상으로 열거

### C. 파괴선이 재밌는가 (§61.C)

- 전투당 평균 파손 파츠 수(양측 합) **1.5~3.5**.
  원인별로 나눠 집계한다: `threshold` / `fires_exhausted` / `effect`
- **"파손 직후 5초 내 패배" 비율 ≤ 20%** — 파괴가 즉사여서는 안 된다 (§60 파괴 RNG 스트레스)
- 복구/보강으로 되돌린 비율이 30% 이상인 빌드가 최소 1종 존재 — 대응책이 실제로 작동함을 증명
- **발동 제한 소진율** — 제한이 걸린 파츠가 죽을 때까지 초기 횟수의 **50% 이상**을
  실제로 소진해야 한다. 너무 낮으면 제한이 아니라 사고사(다른 원인으로 먼저 죽음)이고,
  100%에 붙어 있으면 제한이 밸런스에 관여하지 않는다는 뜻이다.
- **파괴 불가 유예 발생률** — `indestructible` 때문에 파손이 유예된 사례 수.
  0이면 그 키워드가 실제로 작동하는지 검증되지 않은 것이다.

### D. 세 팩션의 사고방식이 다른가 (§61.D)

팩션 순수 빌드 3종의 프로파일 4축 — (자재 총생산, 최고 공명, 평균 전투 길이, 총 파괴 수) —
을 비교한다. 통과 조건: **각 팩션이 최소 한 축에서 다른 두 팩션의 2배 이상 또는 절반 이하**.

### E. 혼종이 자연스럽게 발생하는가 (§61.E, §57)

- 혼종 빌드 평균 승률 ≤ 순수 빌드 평균 승률 **+5%p** (혼종이 상위호환이면 실패)
- 혼종 빌드 승률 **분산 > 순수 빌드 승률 분산** (고점과 저점이 둘 다 커야 §57의 차별화가 성립)

§61.F(전투 추가 목표)는 해당 시스템이 Phase 0 비목표이므로 측정하지 않는다.

---

## 11. 디버그 뷰

기획서 §56은 Trigger Chain 표시를 "단순 QoL가 아니라 **내가 만든 엔진을 이해하고 감상하는
핵심 쾌감**"이라고 못박았다. 따라서 이 뷰의 주인공은 함선 그림이 아니라 **체인 로그**다.

```
┌──────────────────────────────┬────────────────────────────┐
│  PLAYER                      │  TRIGGER CHAIN             │
│  HP ████████░░ 152/200       │  12.35  Railgun            │
│      ▲75  ▲50  ▲25 (마커)    │    └→ Overload             │
│  MATERIAL 14   RESONANCE 3   │      └→ Destroyed          │
│                              │        └→ Material +4      │
│  [core ] [wpn1] [wpn2]       │          └→ Repair Rig     │
│  [def1 ] [utl1] [utl2]       │            └→ Accelerated  │
│  [flex1]                     │                            │
│   각 칸: 이름 / 쿨타임 바 /   │  13.10  Regen Sac          │
│   남은횟수·보강 뱃지 / 파손 X │    └→ Repair 10            │
│   Augment는 하단 작은 칩      │                            │
├──────────────────────────────┤                            │
│  ENEMY (동일 레이아웃)        │                            │
└──────────────────────────────┴────────────────────────────┘
```

- 재생 속도 조절(0.25x / 1x / 4x)과 일시정지. 시드 고정 재생.
- 전투 후 §56의 요약: `MAIN CHAIN: Reactor → Cannon → Overload → Salvage · Repeated 12 times`
- ColorRect / Label / Panel 수준. 셰이더·아트 없음.

---

## 12. 검증 방법

```powershell
# 단위 (exit 0 = 통과)
& $godot --headless --path . --script res://tests/run_unit.gd
# 배치 지표 5종 리포트
& $godot --headless --path . --script res://tests/run_batch.gd
```

- **단위 테스트**가 검증하는 것: 파츠 개별 효과, 트리거 매칭, 조건 평가, 대상 셀렉터,
  발동 상한 0.2초, 발동 횟수 소진 파손, 파괴 불가 유예, 가속·둔화 상쇄,
  파괴선 통과(1선/2선 동시), 보강 소모, 파손·복구,
  자재 부족 시 불발, 공명 누적 규칙, 빌드 검증 실패 케이스, **결정론**(같은 시드 2회 → 동일 스트림).
- **배치 러너**: §10의 배치 구성을 돌려 지표 5종을 리포트하고,
  통과하지 못한 지표를 실패 사례 목록과 함께 출력한다.

---

## 13. 네이밍 규약

기획서 §41의 UI 용어를 코드 식별자로 강제한다.

| 개념 | 코드 식별자 | UI 표시 |
|---|---|---|
| Run | `iteration` | ITERATION |
| 빌드 | `build` (저장된 것은 `pattern`) | PATTERN |
| 함선 바디 | `frame` | FRAME |
| 파츠 | `part` | COMPONENT |
| 사용 / 강화 | `active` / `augment` | ACTIVE / AUGMENT |
| 전투 자원 | `material` | MATERIAL |
| 누적 전투 상태 | `resonance` | RESONANCE |

**결정 기록**: 파츠는 코드에서 `part`를 쓴다. `component`는 UI 표시 문자열 전용이다.
슬롯 역할(`weapon`/`defense`/`utility`)과 어울리고, Godot의 노드/컴포넌트 개념과 혼동되지 않는다.

전투 키워드(§21) 식별자 — JSON의 `keywords` / `add_keywords`에는 이 영문 식별자를 쓴다:
`damage` `shield` `repair` `regen` `accelerate` `slow` `overheat` `fire_limit`
`destroy` `indestructible` `reinforce` `restore` `link` `multi_fire` `crit`

**결정 기록 — `과부하`는 코드 식별자가 아니다.** 초안에는 `overload` 키워드가 있었으나
삭제했다. 과부하는 같은 메커니즘의 **Reclaimer 팩션 표현**일 뿐이고(Viridia는 `고갈`,
Aeonic은 `위상 붕괴`), 실제 메커니즘은 발동 횟수 제한 하나다. GDD §33이 `보강`을
"팩션별 표현은 다르되 키워드는 동일하게 보강"으로 처리한 것과 같은 구조다.
GDD §21도 `발동 제한`으로 개정했다. 코드·키워드 목록·액션명·이벤트명 어디에도
`overload`를 쓰지 않는다.

팩션 식별자: `reclaimer` `viridia` `aeonic` `first`

새 용어가 필요하면 GDD §41 또는 §21에 먼저 추가한 뒤 사용한다.

---

## 14. 열린 질문 (Phase 1에서 결정)

- Augment 슬롯을 파츠당 2개 이상으로 늘릴 것인가 (§16에 개수 명시 없음)
- Core 파츠도 Augment로 쓸 수 있게 할 것인가 (현재는 금지)
- `연결`을 플레이어가 전투 전에 직접 배선하게 할 것인가, 인접 슬롯 자동으로 할 것인가
- 전투 시간 상한 120초가 §30의 "20초 이내 승리" 목표와 맞는 스케일인가
- `DEFAULT_FIRE_LIMIT = 5`가 적절한가 — 배치 지표 C의 소진율이 판정한다
- GDD §19의 "Reclaimer가 파손 파츠를 **완전히 분해**해 자재로 바꾼다"(슬롯에서 영구 제거)를
  넣을 것인가. Phase 0은 `breaker`를 "파손 파츠가 있으면 자재를 더 얻는다"로 축약했다 —
  영구 제거는 복구 계열 파츠(`phase_shifter`, `weld_plating`, `temporal_anchor`)와 정면으로
  충돌하고 슬롯 생애주기 관리를 새로 만들어야 하는데, Phase 0의 검증 지표 어느 것도
  그것을 요구하지 않는다.

## 결정 기록 (재논의 방지)

| 결정 | 근거 |
|---|---|
| 공명은 함선 공용. 파츠별로 쪼개지 않는다 | §7 도입부 |
| `과부하`는 코드 식별자가 아니라 Reclaimer 팩션 표현 | §13 |
| 가속/둔화는 배율 고정, 지속시간만 다름 | §6.5 |
| 발동 횟수 제한은 기본 무제한 | §4.5 |
| 효과는 파츠별 콜백이 아니라 선언적 데이터 | §3.1 |
| Core는 ACTIVE 전용, 영구 `indestructible` | §5.1, §8 |
