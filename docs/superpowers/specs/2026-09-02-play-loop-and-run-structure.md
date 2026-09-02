# 플레이 루프 및 런 진행 구조

작성일: 2026-09-02
상태: **개략 기획. 최종 스펙 아님.** 구현 미착수 — 테스트용 구현 범위는 별도 지시로 정한다
관련: GDD §12 · §29–31 · §34–37 · §53 · §59 · §62
선행: [팩션별 빌드 아키타입](2026-09-01-faction-archetypes.md)

---

## 0. 이 문서의 지위

지금까지의 스펙은 전부 **전투 안**을 다뤘다 — 키워드 · 슬롯 · 상태이상 · 타입 · 아키타입.
이 문서는 **전투 밖**의 플레이 루프와 런 진행 구조를 정의한다.

큰 흐름의 기록이며 수치와 세부 규칙은 확정되지 않았다.

---

## 1. 목적

- 전투 비중이 높은 PvE 로그라이트 구조를 유지한다
- 매 전투마다 전체 빌드를 갈아엎지 않고 **핵심 엔진을 유지한 채 조정**하게 한다
- **경로 선택 자체가 빌드 방향성**과 파츠 획득 전략에 영향을 주게 한다
- 팩션별 지역 특성과 적 구성으로 자연스럽게 드래프팅 방향을 제시한다
- 전투 · Salvage · Augment · Upgrade · Attunement가 하나의 성장 루프로 연결되게 한다
- 후반으로 갈수록 **순수 팩션 빌드에서 혼종 빌드로** 자연히 이동하게 한다
- 전체 진행이 The First의 "Iteration / Experiment" 세계관과 연결되게 한다

---

## 2. 전체 진행 구조

Slay the Spire식 가지형 지도를 기반으로 하되, 노드 타입 중심이 아니라
**팩션 영향권이 깔린 지역 지도**에 가깝게 구성한다.

```
Iteration 시작 → 초기 함선 구성
→ Sector 1 → Sector 2 → Sector 3 → The Cradle
→ 최종 Validation / Ending
```

각 Sector는 여러 경로로 나뉘며, 플레이어는 다음 노드뿐 아니라
**어떤 팩션의 영향권을 통과할 것인지**를 함께 선택한다.

---

## 3. Faction Influence — 핵심 맵 시스템

각 Sector에 세 팩션의 세력 영향도가 공간적으로 배치된다.
딱 잘린 영토가 아니라 **서로 겹치는 그라데이션**이 적합하다.

영향도가 결정하는 것:

- 해당 팩션 적 출현 확률 증가
- 해당 팩션 파츠 Salvage 확률 증가
- 해당 팩션 공격/방어 타입 출현 증가
- 해당 팩션 관련 이벤트 출현 증가
- 특정 Threat Profile 등장 확률 증가

| 영향권 | 키워드 |
|---|---|
| **Reclaimer** | Thermal · Overheat · Material · Destroy · Plating |
| **Viridia** | Caustic · Corrosion · Repair · Regen · Biomass |
| **Aeonic** | Energy · Fracture · Charge · Stasis · Energy Shield |

따라서 경로 선택은 난이도 선택이 아니라
**어떤 파츠 풀과 어떤 적 환경에 자신을 노출시킬 것인가**를 정하는 드래프팅 행위다.

### 3.1 경로 선택의 핵심 질문

> "현재 Thermal 엔진이 거의 완성됐으니 Reclaimer 지역을 더 지나갈까?"
> "Caustic 브리지가 필요하니 Viridia 영향권으로 들어갈까?"
> "Charge 파츠 하나만 얻으면 성장 엔진이 완성되니 Aeonic 경로를 노릴까?"

맵 이동과 빌드 제작은 별개 시스템이 아니다. **맵 자체가 빌드 제작의 일부다.**

---

## 4. 적 정보 3단계 공개

정확한 적을 완전히 선택하게 하면 가장 쉬운 적만 고른다.
아무 정보도 없으면 보드 튜닝의 근거가 없다. 그래서 단계적으로 공개한다.

| 단계 | 시점 | 공개 정보 | 예 |
|---|---|---|---|
| **1** | 경로 선택 | 팩션 영향권 · Encounter 종류 · Threat Tag | `Reclaimer Territory / COMBAT / THERMAL · FAST` |
| **2** | Encounter 진입 | 구체적 적 성향 | `Reclaimer Assault Fleet` — Thermal, 빠른 Weapon, Plating |
| **3** | 전투 직전 | 적의 실제 함선 구성과 장착 파츠 | 전체 공개. 보드 재배치·파츠 교체 자유 |

> 경로에서는 **위험의 종류**를 선택하고, 전투 직전에는 그 위험에 맞게 **Tune**한다.

---

## 5. Build → Tune 원칙

전투마다 새 보드를 요구하지 않는다. 런 동안 하나의 핵심 엔진을 발전시키며
적에 따라 **일부 파츠만** 교체한다.

```
기본 엔진:  Material → Overheat → Material

빠른 Burst 상대  → Defense 하나 추가
Destroy 중심 상대 → Reinforce 추가
장기전            → 성장형 파츠 추가
```

흐름은 `Build → Tune → Fight`이지 `Build → Destroy Build → Rebuild`가 아니다.

---

## 6. Encounter 구성 비율

The Bazaar보다 전투 중심으로 구성한다.

| 종류 | 비율 |
|---|---|
| 일반 전투 | 50~55% |
| Elite / 특수 전투 | 10~15% |
| Salvage · Workshop · Event · Anomaly · Merchant | 30~40% |

**총 노드의 60~70%가 전투**인 구조를 목표로 한다.
상점은 게임의 중심이 아니라 희귀한 보조 수단이다.

---

## 7. Combat → Salvage — 파츠 획득의 중심

The Bazaar의 핵심 루프가 `Shop → Item`이라면,
The First Divergence는 **`Combat → Salvage`** 다.

적을 쓰러뜨리면 그 함선에서 파츠를 회수한다.

### 7.1 Salvage 시스템

일반 전투 승리 후 **파츠 후보 3개 중 1개 선택**이 기본이다.

Salvage 풀에 영향을 주는 것:

- 적 팩션
- 해당 지역의 Faction Influence
- **적이 실제로 사용한 파츠**
- 현재 Sector
- Encounter 난이도
- Observation Condition 달성 여부

이를 통해 **"싸우고 싶은 팩션 = 얻고 싶은 파츠"** 라는 관계가 생긴다.

---

## 8. Observation Condition

각 전투에 선택적 추가 목표가 존재할 수 있다.
UI 명칭은 **OBSERVATION CONDITION**. 실패해도 전투 승리에는 영향이 없다.

예: 20초 이내 승리 · Hull 50% 이상 유지 · 파츠 파괴 없이 승리 ·
파괴선을 모두 통과하고 생존 · 파츠 2개 Restore · Material 일정량 소비 ·
**특정 상태이상 일정량 누적**

### 8.1 보상은 재화가 아니라 Salvage 선택권

- Salvage 후보 +1
- **적이 사용한 특정 파츠를 회수 가능**
- 희귀 파츠 등장 확률 증가
- Upgrade 기회
- Attunement 진행 보너스

특히 이 구조가 중요하다:

```
전투 중 적이 쓰는 매력적인 파츠를 발견
→ 그 전투의 Observation Condition 달성
→ 그 파츠를 직접 Salvage
```

**전투 자체가 파츠 쇼케이스** 역할을 한다.

---

## 9. 비전투 노드

### Workshop — 핵심 비전투 노드

일반 상점보다 중요하다. **현재 함선의 Pattern을 정비하는 장소**이지
새 파츠를 대량 구매하는 곳이 아니다.

파츠 Upgrade · Augment 재배치 · 파츠 수리 · 불필요한 파츠 정리 ·
제한적인 파츠 교환 · 특정 기능 탐색

### Merchant — 낮은 빈도

특정 파츠 구매 · 희귀한 거래 · 특정 팩션 파츠 확보.
**상점 방문이 기본 루프가 되어서는 안 된다.**

### Anomaly / Event — 세계관과 시스템 변주

파츠 하나를 희생하고 다른 파츠 강화 · 특정 팩션 영향도 변경 ·
다음 Encounter 조건 변경 · Attunement 조건 즉시 일부 진행 ·
임시 Experimental Condition 획득

---

## 10. Contested Zone

두 팩션의 영향력이 겹치는 지역 (예: Reclaimer 45% / Viridia 45%).

- 두 팩션 적이 모두 등장
- 혼종 함선 등장 가능
- 양쪽 팩션 파츠 Salvage 가능
- **서브 타입 파츠 확률 증가**

Contested Zone은 플레이어가 **순수 아키타입에서 혼종 엔진으로 넘어가는 주요 공간**이다.
[아키타입 스펙](2026-09-01-faction-archetypes.md) §3의 "서브 타입 = 혼종의 씨앗"이
맵 차원에서 나타나는 형태다.

---

## 11. Sector Progression

| Sector | 이름 | 특징 | 플레이어 상태 |
|---|---|---|---|
| **1** | Frontier | 팩션 영향권이 명확 · 적 조합 단순 · 바닐라 파츠 비중 높음 · 한 팩션의 기본 아키타입 확립 | "이번 판은 Reclaimer Thermal 빌드다." |
| **2** | Convergence Zone | 팩션 경계가 겹치기 시작 · 서브 공격 타입 증가 · Contested Zone 등장 · Pivot 파츠와 Augment 선택 중요 | "Viridia 파츠를 하나 넣으면 내 엔진이 더 잘 돌 것 같은데?" |
| **3** | Resonance Depths | 혼종 적 증가 · 팩션 순수성 약화 · 성장형 엔진 폭발 · The First 계열 효과 등장 | "이제 무슨 팩션 빌드인지는 모르겠지만 엔진은 완성됐다." |
| **4** | The Cradle | **팩션 지도 구조가 무너진다.** Faction Influence 대신 Archived Pattern · First Construct · Unknown Signal · Previous Iteration이 등장 | 플레이어가 만든 혼종 Pattern 자체가 테스트 대상이 된다 |

### 11.1 Sector 관문 전투

각 Sector 끝에 강력한 Gatekeeper가 등장한다.
**완전 랜덤이 아니라 플레이어가 지나온 경로의 영향을 받는다.**

| 지나온 경로 | Gatekeeper |
|---|---|
| Reclaimer 영향권 다수 | Reclaimer Dreadnought |
| Viridia 중심 | Viridia Broodship |
| Contested Zone 다수 | Hybrid Gatekeeper |

경로 선택이 보상뿐 아니라 **Sector의 최종 시험에도** 영향을 준다.

---

## 12. 파츠 성장 — 세 개의 축

| 축 | 목적 | 바꾸는 것 |
|---|---|---|
| **Upgrade** | 기존 기능을 더 잘하게 | **수치** |
| **Augment** | 새로운 역할과 Trigger Network를 염 | **관계** |
| **Attunement** | 파츠 자체의 장기적 진화 | **진화** |

### Upgrade — 수치

`Damage 6 → 8` · `Repair 1 → 2` · `Material 2 → 3`

파츠의 정체성을 바꾸지 않는다. **새 Trigger 추가도 기본적으로 지양한다.**

한 Run당 약 **3~5회**. 모든 파츠가 아니라 핵심 파츠를 선택적으로 강화한다.

### Augment — 관계

방어 파츠에 Thermal Damage 추가 · Weapon 발동 시 Repair 추가 ·
Physical 파츠에 Overheat 부여 기능 추가

단순 수치 강화가 아니라 **"이 파츠가 어떤 엔진에 참여할 수 있는가"** 를 바꾼다.

파츠 하나는 Active로 장착하거나 다른 파츠의 Augment로 쓰거나 **둘 중 하나**다.

### Attunement — 진화

파츠별 고유 조건을 갖는다.

| 팩션 | 조건 예 |
|---|---|
| Reclaimer | 파츠 파괴 6회 목격 |
| Viridia | 실제 Repair 30회 발생 |
| Aeonic | Charge 10회 받기 |

조건 충족 시 파츠의 기능 자체가 변하거나 새 Trigger가 열린다.

```
기본:            Damage 6
Upgrade:         Damage 8
Attunement 완료:  파츠가 파괴될 때 이번 전투 동안 Damage +1
```

---

## 13. 파츠 등급 — Normal → Upgraded 한 단계만

The Bazaar식 4단계(Bronze → Silver → Gold → Diamond)는 현재 게임에 과도하다.
플레이어가 이미 관리해야 할 것이 많다 — Active · Augment · Base Role ·
Keyword · Damage Type · Status · Upgrade · Attunement.

**등급 파밍보다 파츠 간 관계를 만드는 것에 집중한다.**

---

## 14. 노드 단위 반복 구조

```
경로 선택
→ Faction / Threat 확인
→ Encounter 진입
→ 적 함선 정보 확인
→ 보드 Tune
→ 전투
→ Observation Condition 판정
→ Salvage
→ 파츠 Active / Augment 선택
→ 다음 경로 결정
```

몇 전투마다 Workshop · Event · Elite가 삽입된다.

---

## 15. 메타 진행 — Iteration

각 Run은 The First가 관찰하는 하나의 **ITERATION**이다.
승리한 함선은 **VALIDATED PATTERN**으로 Archive에 저장된다.

다음 Iteration에서 이전 Pattern이 새로운 Experimental Condition에 영향을 준다.

| 이전 런 | 다음 Iteration |
|---|---|
| Destroy 중심 | Debris Saturation |
| Regen 중심 | Rapid Adaptation |
| 강한 혼종 | Mixed Pressure |

### 15.1 Faction Influence와 메타의 연결

이전 결과가 다음 런의 Faction Influence에도 영향을 줄 수 있다.
Viridia 중심으로 승리하면 다음 Iteration에서 Viridia 영향권이 늘거나
Viridia 관련 Experimental Condition이 추가되는 식이다.

**이전 빌드를 직접 카운터치는 방식은 지양한다.**

> 목표는 "지난번 답을 약화시키는 것"이 아니라
> **"지난번 답을 새로운 환경의 일부로 만드는 것"** 이다.

---

## 16. UI / Lore 통합

처음에 플레이어는 Faction Influence UI를 단순한 전략 지도로 이해한다.

```
REGIONAL PRESSURE
RECLAIMER  ██████░░
VIRIDIA    ████░░░░
AEONIC     ██░░░░░░
```

후반에는 이것이 실제로 **The First가 이번 Iteration에 배치한 실험 환경과 진화압**을
표시하는 인터페이스였음이 드러난다.
게임 UI 자체가 The First의 실험 관제 시스템이라는 기존 설정(GDD §40)과 연결된다.

---

## 17. 핵심 플레이 경험

| 시점 | 플레이어의 생각 |
|---|---|
| 초반 | "어느 팩션 빌드를 만들까?" |
| 중반 | "이 다른 팩션 파츠 하나가 내 병목을 해결할 수 있는데?" |
| 후반 | "내 빌드가 어느 팩션인지는 더 이상 중요하지 않다." |
| 최종부 | "The First는 이것을 새로운 최적해로 분류하려 한다." |

빌드 과정 자체가 **Pure Pattern → Hybrid Pattern → Divergent Pattern** 으로 진행된다.

---

## 18. 최종 설계 원칙

| 축 | 원칙 |
|---|---|
| 진행 구조 | StS식 가지 지도 + FTL식 지역 정체성 + Bazaar식 전투 사이 빌드 수정 |
| 경로 선택 | 어떤 적을 정확히 상대할지가 아니라 **어떤 팩션과 어떤 위험에 노출될지**를 선택 |
| 획득 루프 | `Combat → Salvage`. 상점보다 전투가 주요 수단 |
| 빌드 루프 | `Build → Tune → Fight → Salvage → Evolve` |
| 성장 | Upgrade = 성능 · Augment = 관계 · Attunement = 진화 |
| 맵의 역할 | **맵 자체가 드래프트다.** 경로 선택이 곧 빌드 선택 |

> **한 문장:** 팩션 영향권이 깔린 가지형 우주 지도를 횡단하며, 원하는 기술을 가진 적과
> 위험 환경을 선택하고, 전투에서 회수한 파츠를 Active 또는 Augment로 재구성해
> 점차 순수 팩션 빌드에서 예측 불가능한 혼종 Pattern으로 진화시키는
> PvE 엔진빌딩 로그라이트.

---

## 19. 기존 GDD와의 관계

대조 결과, 이 문서가 **대체하는 것**과 **구체화하는 것**을 구분해 남긴다.

### 19.1 대체 — GDD §12 Run 구조

§12는 런을 **선형 나열**로 적어놨다
(`초기 조건 선택 → 일반전 → Salvage → 전투 → Workshop/Anomaly → Elite → 팩션 구역 → Boss → The Cradle 심부 → 최종 시험`).

이 문서의 **Sector 1–4 가지형 구조 + Faction Influence**가 이를 대체한다.
§12에 포인터를 넣었다.

### 19.2 구체화 — 이미 있던 것에 살을 붙인 것

| GDD | 이 문서가 더한 것 |
|---|---|
| §30 전투 추가 목표 | 예시에 **"특정 상태이상 일정량 누적"** 추가 (상태이상이 구현된 뒤 가능해졌다) |
| §31 추가 목표 보상 | "높은 등급 확률"의 등급 체계를 **Normal → Upgraded 2단계**로 확정 (§13) |
| §34–37 · §53 메타 | Faction Influence가 메타의 대상이 된다는 연결 (§15.1) |
| §59 파츠 교체 비용 | "전투 전 재조립 무료"가 3단계 정보 공개의 **3단계에서 일어난다**는 시점 확정 (§4) |

### 19.3 예시가 달라진 것 — GDD §29 Attunement

조건 예시가 바뀌었다. 새 쪽이 **지금 구현된 키워드에 직접 걸린다.**

| 팩션 | GDD §29 | 이 문서 |
|---|---|---|
| Reclaimer | 파츠 6개의 파괴를 목격 | 동일 |
| Viridia | 공명 5 이상 전투에서 3번 생존 | **실제 Repair 30회 발생** |
| Aeonic | 25초 이전에 전투 3회 승리 | **Charge 10회 받기** |

새 예시는 `repaired`와 `charge_applied` 이벤트에 그대로 매핑된다.
`charge`는 자기 op이며 발동 시 `charge_applied`를 방출하므로
"Charge 10회 받기"는 그 이벤트를 세는 것으로 판정된다.

둘 다 예시일 뿐이므로 GDD를 고치지 않았으나, 파츠를 실제로 만들 때는
**이벤트로 셀 수 있는 조건**을 쓰는 편이 낫다.

---

## 20. 구현 관점에서 미리 알아야 할 것

당장 구현하지 않지만, 이 구조가 현재 sim에 요구하는 것을 미리 적어둔다.

| 항목 | 현재 상태 |
|---|---|
| **전투 밖 계층이 통째로 없다** | `res://sim/`은 전투 1판만 안다. 맵·노드·Salvage·Workshop은 어느 파일에도 없다 |
| **런 상태를 담을 곳이 없다** | 보유 파츠 목록, 진행 위치, Faction Influence를 들고 있을 자료구조가 없다. `ShipState`는 전투 1판의 상태다 |
| **Salvage 풀 결정에 시드가 필요하다** | 결정론 계약상 전역 `randi()` 금지. 런 단위 RNG를 따로 주입해야 한다 |
| **Observation Condition은 이벤트 스트림으로 판정할 수 있다** | 전투가 이벤트를 다 방출하므로 `20초 이내 승리` `파츠 파괴 없이` 등은 로그 후처리로 판정 가능하다. 새 sim 기능이 아니라 소비자 코드다 |
| **Attunement는 전투를 가로질러 누적된다** | 전투 1판을 넘는 상태다. 런 계층이 이벤트 스트림에서 집계해 파츠에 기록하는 형태가 자연스럽다 |
| **Upgrade는 파츠 수치를 바꾼다** | `catalog.merge()`가 JSON 원본에서 사양을 만든다. 런 중 강화된 수치를 얹으려면 병합 단계에 런 계층의 override가 들어가야 한다 |
| **런의 Upgrade와 전투 중 `grow`는 다른 것이다** | `grow` op은 "이번 전투 동안 +1"로 전투가 끝나면 사라진다. 런의 Upgrade는 **전투를 넘어 남는다.** 이름이 비슷해 섞이기 쉬우므로 저장 위치를 분리해야 한다 — `grow`는 파츠 런타임 상태, Upgrade는 런 계층의 파츠 인벤토리 |

마지막 두 줄이 이 구조의 **가장 큰 구현 결정**이다 —
런 계층이 전투 계층을 어떻게 파라미터화하는가.
`sim/`의 순수 로직 계약(Node·씬·전역 RNG 금지)을 지키면서 하려면
**런 계층이 sim에 데이터를 주입하는 방향**이어야 하고, 그 반대가 되면 안 된다.
