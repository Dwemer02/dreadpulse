# 2차 프로토타입 — Mini Iteration 설계

- 날짜: 2026-09-02
- 상위 문서: [플레이 루프 및 런 진행 구조](2026-09-02-play-loop-and-run-structure.md)(전체 구조),
  [Phase 0 설계](2026-08-29-first-divergence-phase0-design.md)(전투 계층)
- 상태: **1~8단계 완료 — 사람이 직접 플레이 가능 (F5). 플레이테스트 대기**

---

## 1. 이 문서의 지위

상위 문서가 **완성형 런 구조**(Sector 4개 · 가지형 지도 · Faction Influence ·
Workshop · Attunement)를 그린 반면, 이 문서는 그중 **6전투 규모로 잘라낸 검증판**이다.
잘라낸 기준은 하나다 — *"조립과 Tune이 재미있는가"를 판정하는 데 필요한 최소한만 남긴다.*

검증 질문(기획서 원문):

> "같은 21개의 파츠만 가지고도, 어떤 적을 선택했고 무엇을 Salvage했느냐에 따라
> 매 런 서로 다른 엔진을 만들고 조정하는 재미가 발생하는가?"

이 질문에 YES가 나올 때까지 파츠 파괴·Upgrade·Attunement·맵·Faction Influence는
손대지 않는다.

### 상위 문서와의 대응

| 상위 문서 | 이 문서에서 |
|---|---|
| §2 Sector 4개 가지형 지도 | **선형 6노드**로 축소. 각 노드에서 적 2종 중 택1 |
| §4 적 정보 3단계 공개 | 2단계로 축소 — 선택 시 Threat Profile, 전투 직전 전체 공개 |
| §5 Build → Tune | 그대로 유지. 이 프로토타입의 핵심 검증 대상 |
| §7.1 Salvage 3택1 | 그대로 유지. 풀 결정 요인은 `적 팩션`·`적이 쓴 파츠`만 남김 |
| §11.1 Gatekeeper | Elite 1 + Boss 1로 축소. 경로 영향은 없음(선형이므로) |
| §8 Observation Condition | **미구현** |
| §9 Workshop / Merchant | **미구현** |
| §12 Upgrade / Attunement | **미구현** |
| §13 파츠 등급 | **미구현** — 전부 Normal |
| §3 Faction Influence | **미구현** |

---

## 2. 결정 기록 (재논의 방지)

### 결정 1. Aeonic Core도 `plating`을 유지한다 — 기존 계약을 지킨다

**결론: 바꾸지 않는다.** `HULL_MATERIALS`는 `plating`/`biomass` 두 종으로 유지하고,
Aeonic Core는 `plating` 재질 + 보호막 50 효과를 그대로 둔다.

그 대가를 알고 받는다: Reclaimer와 Aeonic이 같은 재질이므로 **상성이 사실상
2방향으로 남는다.** `thermal`은 Viridia에게만 유리하고 나머지 둘에게는 불리·중립이며,
`energy`는 Viridia에게만 불리하다. "적 선택 → 무기 타입 교체" Tune 동기가 그만큼 약하다.
Tune 지표(§10)가 0에 가깝게 나오면 **이 결정이 원인 후보 1번**이다.

아래는 왜 이런 선택지가 있었는지에 대한 기록이다.

---

기획서는 Core 3종의 재질을 이렇게 적었다:

| Core | 재질 |
|---|---|
| Reclaimer | `plating` |
| Viridia | `biomass` |
| **Aeonic** | **`energy_shield`** |

그런데 현재 계약은 `energy_shield`를 **재질로 인정하지 않는다**:

```gdscript
# sim/sim_const.gd
const DEFENSE_TYPES: Array[String] = ["plating", "biomass", "energy_shield"]
## 선체 재질은 이 둘 중 하나다. energy_shield는 재질이 아니다.
const HULL_MATERIALS: Array[String] = ["plating", "biomass"]
```

CLAUDE.md에도 "`energy_shield`는 선체 위에 얹히는 흡수층"으로 기록되어 있다.

**요청대로 바꾸면 무엇이 달라지는가.** 코드는 `HULL_MATERIALS`에 한 줄 추가하면 끝이다 —
`damage.gd`는 이미 `TYPE_MULT`에서 `energy_shield` 열을 읽고 있으므로 계산 경로는 그대로다.
바뀌는 것은 **의미**다: Aeonic 함선의 선체 자체가 에너지 실드 재질이 되고,
실드 배율과 선체 배율이 같은 열을 쓴다.

그 대가로 상성표가 3방향으로 살아난다. 현재는 Reclaimer와 Aeonic이 둘 다 `plating`이라
공격 타입 3종 중 실질적으로 갈리는 것이 하나뿐이다:

| | vs plating | vs biomass | vs energy_shield |
|---|---|---|---|
| `physical` | ×1.0 | ×1.0 | ×1.0 |
| `thermal` | ×0.75 | ×1.5 | ×1.0 |
| `energy` | ×1.0 | ×0.75 | ×1.5 |

재질이 3종으로 갈리면 "적 선택 → 무기 타입 교체"라는 Tune 동기가 실제로 생긴다.
Core의 목적이 "공격 타입 상성이 전투별 파츠 선택에 실제 영향을 주는지 검증"이므로
이쪽이 기획 의도에 맞아 보인다.

부수 효과 하나: Aeonic 선체가 `energy` ×1.5를 받으므로 Aeonic 미러전이 매우 짧아진다.
`energy`를 쓰는 파츠는 현재 Aeonic 광자창뿐이다.

**기각 사유:** 기록된 계약을 뒤집을 만큼 급하지 않다. 상성을 더 갈라야 한다면
CLAUDE.md의 원래 의도("같은 팩션 안에도 재질이 다른 Core가 존재해야 한다")대로
**팩션당 Core를 늘리는 쪽**이 계약과도 맞고 빌드 단위 선택도 만든다.
이번 프로토타입 뒤에 다시 판단한다.

### 결정 2. 오토파일럿을 먼저, 그 위에 최소 조작 UI (안 A → 안 B)

이 프로토타입의 검증 질문은 **사람이 조작해야만** 답이 나온다.
"Tune이 재미있는가"는 배치 러너로 측정할 수 없다.
반면 지금 있는 디버그 뷰는 **읽기 전용 재생기**다 — 클릭으로 파츠를 옮길 수 없다.

**결론: 1~6단계로 오토파일럿 런을 먼저 완주시키고, 그 위에 드롭다운·버튼 기반
Tune·Salvage 화면을 얹는다.** 드래그 앤 드롭은 만들지 않는다.

근거는 §11의 표에 적었다 — 조립의 재미 대부분은 "무엇을 넣을지 고민하는 것"에서 오고
그 고민은 드롭다운으로도 발생한다. 그리고 오토파일럿이 먼저 돌면 시스템 정합성과
Salvage 풀 고갈을 사람 없이 검증할 수 있어 UI 작업이 훨씬 싸진다.

---

## 3. 아키텍처 — 새 계층 `res://run/`

상위 문서 §20의 결론을 그대로 따른다:

> `sim/`의 순수 로직 계약을 지키면서 하려면 **런 계층이 sim에 데이터를 주입하는 방향**이어야
> 하고, 그 반대가 되면 안 된다.

```
res://
├── sim/     전투 1판. 런이 존재하는지 모른다. (변경 최소)
├── run/     런 1회. 인벤토리·노드 진행·Salvage. sim을 호출한다. (신규)
├── tests/   헤드리스 러너. sim과 run을 둘 다 검증한다.
└── debug/   시각화. 이벤트 스트림과 런 상태를 소비한다.
```

`run/`도 `sim/`과 같은 규약을 지킨다 — `RefCounted`만, `class_name` 금지,
Node·씬·Engine 싱글톤 참조 금지, **주입된 RNG만** 사용.

### 3.1 파일 배치

```
run/
  run_content.gd    무엇이 런 콘텐츠인지 한 곳에 적는 레지스트리 (sim/content.gd와 같은 역할)
  run_state.gd      런 1회의 상태: 팩션 · 인벤토리 · 진행 위치 · 런 RNG
  inventory.gd      보유 파츠 인스턴스 목록과 슬롯 배치. 빌드 Dictionary를 만든다
  salvage.gd        전투 후 3택1 후보 생성 (런 RNG)
  mini_iteration.gd 6노드 진행 상태 기계. 적 선택 → Tune → 전투 → Salvage
  autopilot.gd      규칙 기반 자동 플레이어. UI 없이 런을 완주시킨다
  data/
    starters.json   팩션별 스타터 3종
    enemies.json    적 프리셋 6종 + Hybrid Elite + Boss
    nodes.json      6노드 구성 (각 노드의 적 후보)
```

> 설계안의 `encounter.gd`와 `run_metrics.gd`는 따로 두지 않았다. 노드 데이터는
> `nodes.json`이고, 지표는 `mini_iteration`이 남기는 `history` 배열을 소비자가
> 집계하면 된다 — 별도 계층을 두면 같은 숫자가 두 곳에 생긴다.

### 3.2 두 개의 RNG — 섞이면 결정론이 깨진다

| RNG | 소유 | 쓰는 곳 |
|---|---|---|
| 런 RNG | `RunState` | Salvage 후보 생성, 적 후보 선정 |
| 전투 RNG | `CombatSim` | 파괴선 대상 선정, 무작위 셀렉터 |

전투 RNG는 지금처럼 `Content.prepare(..., combat_seed)`로 주입한다.
전투 시드는 `run_seed`와 노드 번호에서 **결정론적으로 파생**한다
(`combat_seed = hash(run_seed, node_index)`) — 그러면 같은 런 시드로 전체 런이 재현된다.

### 3.3 sim/에 필요한 변경 — 두 가지뿐

**(1) 파일이 아니라 Dictionary로 전투를 조립할 수 있어야 한다.**
현재 `Content.prepare()`는 빌드 id로 JSON 경로를 찾는다. 런의 플레이어 보드는
파일이 아니라 인벤토리에서 매 전투 새로 만들어지므로 경유지가 필요하다.

`build_loader.assemble()`이 이미 Dictionary를 받으므로 얇은 함수 하나면 된다:

```gdscript
# sim/content.gd
static func prepare_builds(catalog: RefCounted, player_build: Dictionary,
		enemy_build: Dictionary, combat_seed: int) -> Dictionary
```

기존 `prepare()`는 이것을 호출하는 래퍼가 된다. **엔진 로직 변경 없음.**

**(2) 전투 요약을 이벤트 스트림에서 뽑는 함수.**
§10의 전투 지표(Damage·Repair·Material·Overheat·Multi-fire·Accelerate·Charge)는
전부 이벤트에 있다. `sim/event_analysis.gd`에 집계 함수를 추가한다 —
sim 내부를 조회하지 않으므로 계약 위반이 아니다.

```gdscript
static func combat_summary(log: Array, side: String) -> Dictionary
```

---

## 4. 런 상태와 인벤토리

### 4.1 인벤토리는 인스턴스의 목록이다

보유 파츠는 **파츠 id의 집합이 아니라 인스턴스 목록**이다. 같은 파츠를 두 번
Salvage할 수 있고(고철 기관포 2정은 유효한 빌드다), 하나의 인스턴스는 한 슬롯에만
들어간다 — Active로 쓰면 그 인스턴스는 Augment로 못 쓴다.

```gdscript
# run/inventory.gd
## 보유 인스턴스: [{ "uid": int, "part_id": String }]
var owned: Array = []
## 슬롯 배치: slot_id -> { "active": uid, "augment": uid(선택) }
var board: Dictionary = {}
```

배치되지 않은 인스턴스는 창고에 남는다. Tune은 `board`만 고치는 연산이다.

### 4.2 빌드 Dictionary 생성

`Inventory.to_build(frame_id)`가 `build_loader`가 먹는 형태를 만든다:

```gdscript
{ "id": "run_player", "frame": "pool_frame", "relic": null,
  "slots": { "core": {"part": "foundry_core"},
             "weapon_1": {"part": "rotary_incinerator", "augment": "scrap_autocannon"} } }
```

빈 슬롯은 그냥 넣지 않는다 — `assemble()`이 이미 허용한다(Core만 필수).
**스타터가 4파츠인데 프레임이 6슬롯인 것은 의도된 것이다.** 남은 2칸이 Salvage로
채워지는 성장 공간이다.

### 4.3 전투 사이의 선체 — 매 전투 완전 회복

전투마다 양측이 **최대 선체로 시작한다.** 노드 간 HP 이월이 없다.

이 프로토타입이 판정하려는 것은 빌드와 Tune의 품질이므로, HP 소모가 누적되면
"3전투에서 잘못 골라 6전투에서 죽었다"는 잡음이 지표를 덮는다. 패배는 즉시 런 종료다 —
6전투가 서로 독립된 빌드 시험이 된다.

> HP 이월은 완성형 런의 관심사다(상위 문서 §9 Workshop이 회복 노드를 다룬다).
> 여기서 넣으면 검증 질문이 흐려진다.

### 4.4 배치 유효성

`assemble()`이 이미 검증한다 — 역할 불일치, 존재하지 않는 파츠, Core 슬롯 비어 있음,
Core를 Augment로 사용, augment 블록 없음. 런 계층은 **검증을 다시 구현하지 않고**
`assemble()`의 실패를 UI 에러로 옮긴다. 규칙이 두 곳에 있으면 반드시 어긋난다.

---

## 5. 6노드 구성

```
[1] 일반  → [2] 일반  → [3] 일반  → [4] 일반  → [5] Elite → [6] Boss
```

노드 1~4에서는 **성격이 다른 적 2종 중 택1**. 노드 5·6은 고정.

적 후보 2종은 "쉬운 쪽/어려운 쪽"이 아니라 **다른 종류의 위험**이어야 한다 —
그래야 선택이 난이도 조절이 아니라 Tune 방향의 선택이 된다.
노드마다 후보 팩션이 겹치지 않게 짜서 6전투 안에 3팩션을 모두 만나게 한다.

| 노드 | 후보 A | 후보 B |
|---|---|---|
| 1 | Reclaimer Gunline (Physical·빠름) | Viridia Needle Swarm (Multi-fire·고빈도) |
| 2 | Aeonic Phase Fortress (실드·방어) | Reclaimer Furnace (Thermal·지속) |
| 3 | Viridia Regenerator (Repair·성장) | Aeonic Solar Lance (Charge·Burst) |
| 4 | Reclaimer Furnace | Viridia Regenerator |
| 5 | **Hybrid Elite** (Reclaimer × Aeonic) | — |
| 6 | **Boss** | — |

노드 4가 1~3의 재출현인 것은 의도적이다 — 같은 적을 다시 만났을 때
"이번엔 준비가 됐다"는 감각이 Build → Tune이 작동한다는 증거다.

---

## 6. 적 프리셋 6종

**플레이어와 완전히 같은 파츠·같은 규칙**을 쓴다. 적 전용 메커니즘은 없다.
프레임도 `pool_frame`을 공유한다(Boss만 예외 — §8).

| id | 이름 | Core | 성격 | 구성 요지 |
|---|---|---|---|---|
| `reclaimer_gunline` | Reclaimer Gunline | 용광로 노심 | Physical · 빠른 공격 | 고철 기관포 ×2(하나는 자기 Augment) · 폐철 압축기 · 송풍 터빈 |
| `reclaimer_furnace` | Reclaimer Furnace | 용광로 노심 | Thermal · Overheat 지속 | 회전식 소각포 · 백열 파쇄포 · 폐열 회수기 · 송풍 터빈 |
| `viridia_needle_swarm` | Viridia Needle Swarm | 공생 심핵 | Multi-fire · 고빈도 | 골침 발사기관 ×2 · 재생낭 · 신경 다발 · 신경 촉진기관 |
| `viridia_regenerator` | Viridia Regenerator | 공생 심핵 | Repair · 성장 | 증식 심장 · 중층 재생막 · 성장 포대 · 신경 다발 |
| `aeonic_solar_lance` | Aeonic Solar Lance | 위상 노심 | Charge · Thermal Burst | 헬리오스 창 · 태양 반사경 · 인과 점화기 · 일식 축전기 |
| `aeonic_phase_fortress` | Aeonic Phase Fortress | 위상 노심 | Energy Shield · 방어 | 위상 방벽 ×2 · 광자창 · 시간 가속기 |

정확한 슬롯·Augment 배치는 구현 시 JSON에 적는다. 기존 3종 거울 빌드
(`reclaimer_mirror` 등)는 **이 6종으로 교체**한다 — 거울전은 파츠 검증용이었고
런 검증에는 성격이 갈리는 적이 필요하다.

---

## 7. Threat Profile — 선택 시점의 정보

노드에서 보이는 것은 **위험의 종류**뿐이다. 파츠 목록은 보이지 않는다.

```
VIRIDIA REGENERATOR
BIOMASS
SUSTAIN / GROWTH
```

Threat Profile은 적 JSON에 **손으로 적는다.** 파츠에서 자동 생성하지 않는다 —
자동 생성하면 "적이 실제로 무엇을 하는가"가 아니라 "어떤 키워드를 갖는가"가 나오고,
그 둘은 다르다(패시브 변환기는 키워드가 있어도 단독으로는 아무것도 안 한다).

```json
{ "id": "viridia_regenerator", "name": "Viridia Regenerator",
  "threat": { "material": "BIOMASS", "tags": ["SUSTAIN", "GROWTH"] },
  "slots": { ... } }
```

전투 직전에는 전체 공개 — 슬롯별 Active/Augment 전부. 이 시점이 Tune 창이다.

---

## 8. Elite와 Boss

### Hybrid Elite — 혼종의 가능성을 보여주는 적

기획서가 지정한 루프를 그대로 쓴다:

```
Reclaimer Material → Weapon Accelerate → Aeonic Thermal Multi-fire → Overheat → Material 회수
```

현재 파츠로 정확히 표현된다:

| 슬롯 | 파츠 | 역할 |
|---|---|---|
| core | 용광로 노심 (plating) | — |
| weapon_1 | 태양 반사경 + **회전식 소각포**(Augment) | 가속 중이면 Multi-fire, 발동마다 Thermal+Overheat |
| flex_1 | 송풍 터빈 | 자재 2 소비 → 모든 무기 가속 3초 |
| flex_2 | 폐철 압축기 | 자재 생산 |
| flex_3 | 폐열 회수기 | Overheat 3회당 자재 회수 |
| defense_1 | 야전 용접기 | — |

이 조합은 **플레이어가 아직 만들어보지 않았을 혼종**이다. Elite의 역할은
난이도가 아니라 시연이므로, 보상 Salvage도 두 팩션이 섞인 후보로 구성한다.

### Boss — 하드 카운터가 아닌 종합 시험

특정 타입 면역·특정 빌드 봉쇄는 쓰지 않는다(GDD §3.4).
5개 축을 **동시에 적당히** 시험한다:

| 축 | 담당 |
|---|---|
| Burst 대응 | 헬리오스 창 (Thermal 7 + Overheat 3, 성장) |
| 지속 화력 | 공생 심핵 초당 회복 + 골침 발사기관 Multi-fire |
| 방어 | 중층 재생막 + 위상 방벽(Augment) |
| 성장 속도 | 성장 포대 + 증식 심장(Augment) |
| 엔진 안정성 | 신경 촉진기관 (템포) |

Boss만 `boss_frame`을 쓴다 — 선체 320, 파괴선 동일. **슬롯 수는 6칸 그대로다**
(더 주면 플레이어가 이길 수 없다). 강함은 선체와 조합 밀도로만 만든다.

> Boss Core는 **공생 심핵(biomass)** 으로 둔다. Boss가 세 팩션 조합인 만큼
> 재질 하나로 상성이 결정되면 안 되지만, 재질은 반드시 하나여야 한다.
> biomass는 Thermal에 약하고 Energy에 강해 어느 쪽도 무력화되지 않는다.

---

## 9. Salvage

전투 승리 후 후보 3개 중 1개. 기획서의 구성을 그대로 따른다.

| 후보 | 규칙 |
|---|---|
| 1 | **방금 싸운 적이 실제로 장착했던 파츠** 중 하나 |
| 2 | 그 적 팩션의 **다른** 파츠 중 하나 |
| 3 | **다른 팩션** 파츠 중 하나 |

- 후보는 런 RNG로 뽑는다. 같은 런을 재현할 수 있어야 한다.
- 이미 보유한 파츠도 후보에 나올 수 있다(중복 보유 허용, §4.1).
  단 **한 후보 안에 같은 파츠가 두 번 나오지 않게** 뽑는다.
- 후보가 부족한 경우(팩션 파츠를 다 가진 경우 등)는 다른 팩션에서 채운다.
- Elite 보상은 후보 3개를 **Reclaimer 1 / Aeonic 1 / 나머지 1**로 고정한다.

**상점·재화는 구현하지 않는다.** 파츠 획득 경로는 Salvage 하나뿐이다.

---

## 10. 검증 지표 — 무엇을 기록할 것인가

배치 지표 A~E(전투 밸런스)는 이번 단계에서 **보지 않는다**. 대신 기획서 §10의
세 묶음만 기록한다. 전부 이벤트 스트림 + 런 이벤트에서 나온다.

### 빌드 변화 — 핵심 지표

| 항목 | 통과 기준 |
|---|---|
| 전투 직전 교체한 Active 수 | **전투당 1~2개** |
| 변경한 Augment 수 | 위와 합산해 판단 |
| 슬롯 재배치 횟수 | 참고값 |

> 보드가 계속 통째로 바뀐다면 Tune이 아니라 Rebuild다 — 그 자체가 실패 신호다.
> 반대로 0개면 Tune 동기가 없다는 뜻이다.

### 파츠 가치

파츠별 Salvage 선택률 · Active 사용률 · Augment 사용률 ·
**한 번도 선택되지 않은 파츠 목록**.

### 전투 데이터 (`Analysis.combat_summary()`)

전투시간 · Damage(타입별) · Repair · Material 생성/소비 · Overheat 발생량 ·
Multi-fire 횟수 · Accelerate 횟수 · Charge 횟수.

기록 위치는 `tests/out/run_log.jsonl` — 런 1회가 한 줄. 사람이 읽는 요약은
런 종료 화면에도 띄운다.

---

## 11. 구현 순서

기획서 §13의 우선순위를 그대로 따른다. 각 단계가 끝나면 돌려볼 수 있어야 한다.

| # | 단계 | 산출물 | 돌려보는 방법 |
|---|---|---|---|
| ~~1~~ | ~~선체 재질 3종 확정~~ | **불필요 — 결정 1이 현행 유지** | — |
| 2 | 적 프리셋 6종 | `run/data/enemies.json` · Threat Profile | 디버그 뷰에서 6종 관전 |
| 3 | `sim/` 얇은 확장 2건 | `prepare_builds()` · `combat_summary()` | 단위 테스트 |
| 4 | 런 계층 코어 | `run_state` · `inventory` · `salvage` | 헤드리스 오토파일럿 런 |
| 5 | 스타터 3종 + 6노드 진행 | `starters.json` · `nodes.json` · `mini_iteration` | 헤드리스 6전투 완주 |
| 6 | Elite + Boss | 프리셋 2종 · `boss_frame` | 위와 같음 |
| 7 | **최소 조작 UI** (결정 2 = 안 B) | Tune 화면 · 적 선택 · Salvage 3택1 | 사람이 플레이 |
| 8 | 지표 기록 | `run_metrics` · `run_log.jsonl` | 런 리포트 |

4~6단계까지 하면 **오토파일럿 런**이 돌아간다 — 시스템이 맞물리는지, 6전투가
완주되는지, Salvage 풀이 고갈되지 않는지를 사람 없이 검증할 수 있다.
검증 질문 자체는 7단계 없이는 답이 안 나오지만, 7단계를 4~6 위에 얹는 것이
7단계를 먼저 만드는 것보다 훨씬 싸다.

### UI 선택지 — 안 B 채택 (결정 2)

| 안 | 내용 | 공수 | 얻는 것 |
|---|---|---|---|
| **A. 오토파일럿만** | 1~6 + 8. UI 없음. AI가 Tune·Salvage를 규칙으로 결정 | 작다 | 시스템 정합성. **재미는 판정 불가** |
| **B. 최소 조작 UI** | A + 드롭다운/버튼 기반 Tune·선택 화면. 기존 디버그 뷰 옆에 붙인다 | 중간 | 사람이 플레이 가능. 드래그 없음 |
| **C. 드래그 조립 UI** | 슬롯 드래그 앤 드롭, 파츠 카드, 툴팁 | 크다 | 실제 조립 감각 |

C는 "조립이 재미있는가"에 가장 가깝지만, 그 재미의 대부분은 **무엇을 넣을지 고민하는
것**에서 오고 그 고민은 B로도 발생한다. 드래그가 없어서 재미가 없다면 그건 UI 문제이지
설계 문제가 아니다 — 그리고 이 프로토타입은 설계를 검증하려는 것이다.

---

## 12. 구현하지 않는 것 (기획서 §11 그대로)

전체 가지형 지도 · Faction Influence · Workshop · Merchant · Upgrade ·
Attunement · Observation Condition · Meta Progression · Previous Pattern ·
The First 파츠 · 추가 팩션 · 추가 아키타입 · 파츠 등급.

**Relic도 이번에는 쓰지 않는다** — 3종이 구현되어 있지만 런 계층의 획득 경로가
없고, 순수 빌드에서는 두 종이 아무 일도 하지 않는다(§공명 조건을 쓰는 파츠가 없다).

---

## 13. 다음 단계 (이 프로토타입 이후)

기획서 §12가 지정한 다음 우선순위는 **파츠 파괴 / Restore / Reinforce**다.
이것으로 Damage · Sustain · Growth · Tempo에 **Engine Stability**라는 축이 추가된다.

현재 엔진에는 이미 재료가 다 있다 — `destroy_part` · `restore_part` · `reinforce` ·
파괴선 3단계 · `fire_limit`. 쓰는 파츠가 없을 뿐이다.
**현재 파츠 24종 중 `fire_limit`을 쓰는 것이 하나도 없다**는 점을 여기서 다시 짚어둔다.
