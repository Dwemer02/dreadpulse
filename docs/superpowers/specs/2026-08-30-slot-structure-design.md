# 슬롯 구조 — Base Role과 기능 키워드의 분리

작성일: 2026-08-30
상태: 설계 확정 · 코드 반영 완료
관련: GDD §13 · §14 · §15 · §16 · §21 · §54
선행: `2026-08-30-keyword-system-design.md` (이 문서가 그 §4를 대체한다)

---

## 0. 왜 다시 세우는가

키워드를 7층으로 재정의하면서 슬롯 종류를 2층 키워드로 승격시켰지만,
슬롯 **자체의 정의**는 손대지 않아 두 문제가 남았다.

### 문제 1 — `utility`가 잡동사니 서랍이었다

Reclaimer 6종 중 3종이 `utility`였다.

| 파츠 | 하는 일 |
|---|---|
| `breaker` 분해기 | 자재 생산 |
| `supercharged_turbine` 과급 터빈 | 자기 가속 |
| `venting_manifold` 방출 다기관 | 발동 횟수 소진 |

공통점은 **"weapon도 defense도 아님"** 뿐이었다. 잔여 정의라서
분류가 애매한 파츠가 전부 여기로 흘러든다.

### 문제 2 — AUGMENT가 슬롯을 우회하도록 써버렸다

`2026-08-30-keyword-system-design.md` §4와 GDD §13에
"설치는 되나 키워드가 맞지 않으면 비작동"이라고 기록했다.
근거는 AUGMENT의 `add_keywords`로 슬롯 키워드를 붙일 수 있다는 것이었다.

이 설계는 **AUGMENT 하나로 파츠의 정체성을 통째로 바꿀 수 있게 만든다.**
방어 파츠에 `weapon`을 붙이면 무기 슬롯에 들어가므로,
함선 보드가 강제하려던 구조적 다양성(GDD §13)이 무너진다.

---

## 1. 해결 — 장착 판정과 기능 판정을 분리한다

> **슬롯은 파츠가 원래 무엇이었는지를 제한하고,
> 증강은 그 파츠가 지금 무엇을 할 수 있는지를 확장한다.**

| | 정체 | 개수 | 변경 | 하는 일 |
|---|---|---|---|---|
| **Base Role** | 파츠의 필드 | 1개 고정 | 불가 (The First 예외) | 어느 슬롯에 장착되는가 |
| **슬롯 키워드** | `keywords` 배열의 원소 | 여러 개 | AUGMENT로 추가 가능 | 어떤 트리거와 연결되는가 |

예시:

```
Base Role: Defense
기본 키워드:      defense / energy_shield
화염 공격 증강 후: defense / weapon / energy_shield / thermal / damage
```

이 파츠는 이제 Weapon 관련 트리거를 발동시키지만
**여전히 Defense 슬롯에만 장착된다.**

슬롯 판정은 Base Role만 확인하고, 전투 중 조건과 시너지는 기능 키워드를 확인한다.

---

## 2. Base Role 4종

| Base Role | 한 줄 | 정의 |
|---|---|---|
| **Weapon** | 출력물을 적에게 투사한다 | 적에게 출력을 전달하는 공격용 기본 파츠 |
| **Defense** | 출력물을 내게 투사한다 | 선체·방어층·파츠를 보호하거나 복구하는 기본 파츠 |
| **System** | 무언가를 무언가로 변환한다 | 자원·쿨타임·공명·다른 파츠의 작동을 변환하는 기본 파츠 |
| **Core** | 함선의 중추 | 기본 재질과 전역 특성을 결정하는 파츠 |

### 2.1 System은 잔여 정의가 아니다

`utility`가 잡동사니가 된 것은 이름이 아니라 **정의의 형태** 때문이다.
"weapon도 defense도 아닌 것"은 부정 정의라서 무엇이든 받아들인다.

`System`은 **"입력을 출력으로 바꾸는 것"** 이다. 긍정 정의이므로
분류가 애매한 파츠를 여기로 떠밀 수 없다. 무엇을 무엇으로 바꾸는지
말할 수 없으면 System이 아니다.

### 2.2 Defense와 System의 경계

Defense의 정의에 "파츠를 보호하거나 복구"가 들어 있고
System의 정의에 "다른 파츠의 작동을 변환"이 들어 있어 **파츠에서 겹친다.**

선을 명시한다.

> **보호·복구는 Defense. 그 밖의 파츠 조작은 System.**

| op | Base Role |
|---|---|
| `reinforce` · `restore_part` · `restore_fires` | Defense |
| `accelerate` · `slow` · `reduce_cooldown` · `drain_fires` · `fire_part` | System |

---

## 3. 부품 관점이 사후 정당화하는 것

슬롯을 효과 분류가 아니라 **함선의 물리적 구획**으로 보면,
이미 정해둔 규칙 세 개가 게임적 편의가 아니라 구조적 귀결이 된다.

| 규칙 | 부품 관점의 설명 |
|---|---|
| Base Role이 안 맞으면 장착 불가 | 하드포인트에는 발사 연결이 있고 내장 베이에는 없다. 반응로를 포탑 자리에 볼트로 박을 수는 있어도 그것은 포탑이 아니다 |
| Core는 파괴선으로 부서지지 않는다 (§14) | 주 동력로는 선체 심부에 있다. 표면 피해가 닿지 않는다 |
| 파괴선은 무작위 파츠를 부순다 (§18) | 선체가 뚫리면 그 구획의 부품이 나간다. 어디가 뚫릴지는 고를 수 없다 |

`Flexible` 슬롯은 이 그림에서 **범용 베이 / 개조 구획**이다.
규격이 정해지지 않은 공간이라 무엇이든 물릴 수 있다.

---

## 4. The First 예외

일반 파츠와 일반 증강은 Base Role을 변경할 수 없다.

The First 계열의 희귀 파츠와 유물은 **규칙 자체를 수정하는 존재**이므로
예외적으로 Base Role 변경 · 추가 Role 획득 · 다른 Role 슬롯 장착이 가능하다.

기본 규칙은 단순하게 유지하고, 슬롯 규칙을 깨는 것은 The First의 고유 영역으로 남긴다.
룰브레이킹이 흔해지면 그것은 더 이상 룰브레이킹이 아니다.

**Phase 0 범위 밖.** 현재 `first` 팩션은 `sim/catalog.gd`의 `VALID_FACTIONS`에만
있고 실제 파츠가 없다. 설계만 기록하고 스키마는 건드리지 않는다.

---

## 5. 데이터 구조

### 5.1 `roles: Array` → `base_role: String`

옛 스키마는 배열이라 `["utility", "flexible"]` 같은 복수 role이 가능했다.
Base Role이 하나라는 규칙과 맞지 않으므로 단일 문자열로 바꾼다.

```json
{ "id": "weld_plating", "faction": "reclaimer", "base_role": "defense", ... }
```

`sim/catalog.gd`가 배열을 받으면 **거부한다** — 옛 스키마를 그대로 옮긴
저작 실수가 조용히 통과하면 첫 원소만 쓰이거나 전부 무시되기 때문이다.

### 5.2 Base Role은 키워드에 자동 주입된다

`catalog.merge()`가 `base_role`을 `keywords` 배열 맨 앞에 넣는다.

저작자가 `base_role`과 `keywords`에 같은 값을 두 번 쓰면 반드시 어긋난다.
`sim/ship_state.gd`의 `add_part()`가 Core에 `indestructible`을 자동으로 붙이는
것과 같은 패턴이며, 그 선례를 따른다.

주입된 뒤에는 다른 키워드와 구별되지 않는다. AUGMENT가 `weapon`을 덧붙일 수 있고
그것이 트리거에 걸리지만, **장착 판정은 여전히 `base_role` 필드만 본다.**

### 5.3 슬롯 role과 파츠 base_role은 다른 값이다

`sim/part.gd`는 둘 다 갖는다.

- `role` — 이 파츠가 꽂힌 **슬롯**의 role. `flexible`일 수 있다
- `base_role` — **파츠 자신**의 Base Role. `flexible`일 수 없다

flexible 슬롯에 꽂힌 파츠는 둘이 다르다.
`VALID_BASE_ROLES`에 `flexible`이 없는 이유다.

---

## 6. 기존 6종 재분류

| 파츠 | 옛 roles | Base Role | 근거 |
|---|---|---|---|
| 리벳 레일건 | `["weapon"]` | **weapon** | 출력물을 적에게 투사 |
| 용접 장갑 | `["defense"]` | **defense** | 보강·수리·복구 |
| 과급 터빈 | `["utility"]` | **system** | 발동 횟수 → 가속 |
| 분해기 | `["utility"]` | **system** | 파손 → 자재 |
| 방출 다기관 | `["utility"]` | **system** | 발동 횟수 → 자재 |
| 폐선 재활용로 | `["core"]` | **core** | 재질 + 전역 특성 |

`utility` 3종이 전부 System으로 들어가며, 각각 "무엇을 무엇으로 바꾸는가"를
한 줄로 말할 수 있다. 복수 Base Role이 필요한 파츠는 없었다.

프레임 슬롯도 함께 개칭했다 — `utility_1` / `utility_2` → `system_1` / `system_2`.
슬롯 정의 순서가 곧 발동 순서(결정론 계약)이므로 순서는 유지했다.

---

## 7. 미해결

| 항목 | 내용 |
|---|---|
| 팩션 키워드 자동 주입 | 1층 팩션 키워드는 아직 `keywords`에 들어가지 않는다. 키워드 7층 마이그레이션에서 `base_role`과 같은 방식으로 주입한다 |
| 프레임 다양성 | GDD §15의 Frame 3종(공격형·지원형·중장갑)이 아직 데이터로 없다. `standard_frame` 하나뿐이다 |
| The First 스키마 | Base Role을 바꾸는 데이터 표현(`base_role_override` 등)을 아직 정하지 않았다. The First 파츠를 실제로 만들 때 정한다 |
