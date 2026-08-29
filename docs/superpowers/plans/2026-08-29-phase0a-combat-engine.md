# Phase 0a — 전투 엔진 코어 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** THE FIRST DIVERGENCE의 결정론적 전투 시뮬레이션 엔진을 만든다 — 파츠가 쿨타임에 따라 발동하고, 트리거 연쇄가 이벤트 스트림으로 관측되며, 같은 시드는 언제나 같은 결과를 낸다.

**Architecture:** `res://sim/`은 순수 로직 계층이다 (RefCounted만, Node/씬/전역 RNG 금지). 파츠 효과는 코드가 아니라 **선언적 데이터** — `{on, where, do}` 트리거 규칙과 원자 액션 op의 조합이다. AUGMENT는 숙주 파츠 정의에 대한 데이터 병합이다. 엔진은 매 틱 이벤트 배열을 방출하고, 소비자(`tests/`, `debug/`)는 그것만 읽는다.

**Tech Stack:** Godot 4.7.1 / GDScript / JSON 데이터 파일 / 헤드리스 SceneTree 스크립트 테스트 러너

**근거 문서:** [Phase 0 설계 스펙](../specs/2026-08-29-first-divergence-phase0-design.md) · [GDD](../../THE_FIRST_DIVERGENCE_GDD.md)

---

## 범위 — 왜 스펙을 둘로 쪼갰는가

스펙 §1의 Phase 0은 (a) 전투 엔진, (b) 파츠 21종·적 6종 콘텐츠, (c) 배치 지표 리포트, (d) 디버그 뷰를 담는다. 이 계획은 **(a)만** 다룬다.

(b)~(d)는 후속 계획 `Phase 0b — 콘텐츠와 계측`으로 뺀다. 이유는 하나다: **엔진이 존재하지 않는 상태에서 파츠 21종의 JSON을 확정하면, 엔진을 만들다 발견한 계약 문제가 21개 파일에 이미 퍼져 있다.** 0a는 합성 테스트 파츠(§Task 5의 픽스처)로 모든 op와 조건을 검증하고, 0b가 그 위에 실제 콘텐츠를 얹는다.

0a 완료 시점의 산출물: `godot --headless --script res://tests/run_unit.gd`가 exit 0으로 통과하는, 결정론이 증명된 전투 엔진.

---

## 구현 결정 — 모든 시간은 정수다

스펙 §4.3은 "같은 빌드 + 같은 시드 = 완전히 같은 이벤트 스트림"을 요구한다. 부동소수 쿨타임 누산(`progress += 0.05 * 2.0`)은 수천 틱 뒤 드리프트로 이 계약을 깬다. 따라서:

- **시간의 단위는 틱(int)이다.** `TICK_DT = 0.05초`는 이벤트에 실을 `t`를 계산할 때만 쓴다 (`t = tick * TICK_DT`).
- **쿨타임 진행도 정수다.** 속도 배율을 정수로 표현한다 — 보통 `2`, 가속 `4`, 둔화 `1` "유닛/틱". 쿨타임 5초 파츠의 목표치는 `100틱 × 2 = 200유닛`. 가속이면 틱당 4유닛이 쌓여 정확히 절반 시간에 도달한다.
- 나눗셈이 없으므로 드리프트도 없고, 발동 상한(`MIN_FIRE_TICKS = 4`)도 `tick - last_fire_tick < 4`라는 정확한 정수 비교가 된다.

지속시간(`duration: 3.0`)은 로드 시점에 틱으로 변환한다. `duration: -1`(영구)은 `PERMANENT = -1` 센티넬로 유지하고 감소시키지 않는다.

**센티넬이 음수라는 점을 조심하라.** `if ticks > 0` 같은 가드는 영구값(-1)을 조용히 건너뛴다. 실제로 초안의 가속 상쇄 로직이 이 실수를 저질러, 영구 둔화가 걸린 파츠에 유한 가속을 걸면 둔화가 통째로 무시됐다. 센티넬을 다루는 곳에서는 `!= 0` 또는 `== K.PERMANENT`로 명시적으로 분기하라.

---

## 테스트 모듈 규약

모든 테스트 모듈은 두 가지를 지켜야 한다. 러너가 강제한다.

1. **`run()`의 마지막 줄은 `t.done()`이다.** GDScript에는 예외가 없어서, `run()`이 런타임 에러로 중단되면 러너가 감지할 방법이 이 완료 센티넬뿐이다.
2. **`extends RefCounted` 바로 아래에 `const EXPECTED_CHECKS := N`을 선언한다.** 센티넬은 `run()` 자체의 중단만 잡는다 — 서브테스트(`_test_*`) 안에서 에러가 나면 GDScript는 그 함수만 중단하고 `run()`으로 돌아오므로 `t.done()`이 정상 호출되고 모듈 전체가 통과처럼 보인다. 우리 모듈은 전부 서브함수로 위임하므로 이 개수 검증이 실질적인 방어선이다.

`N`은 러너를 한 번 돌려 출력되는 모듈별 개수를 그대로 넣으면 된다. 어서션을 추가·삭제할 때마다 갱신해야 하고, 잊으면 러너가 정확히 그 불일치를 실패로 보고한다 — 의도된 마찰이다.

### 러너는 `bash tests/run.sh`로 돌린다

Godot을 직접 부르지 마라. GDScript 런타임 에러는 서브테스트를 중단시키지 않고 **stderr로만** 흘러가므로, 잘못된 코드가 우연히 기대값과 같은 결과를 내면 `ALL PASS` / exit 0이 나온다. 실제로 그런 사각지대가 발견됐다 — 존재 검사를 지운 코드가 매 호출마다 `SCRIPT ERROR`를 찍는데도 스위트가 통과했다.

래퍼는 두 조건을 모두 요구한다: **어서션 실패 0건, 그리고 SCRIPT ERROR 0건.** 타임아웃도 함께 처리한다.

---

## 각 태스크의 필수 자기검토 — 돌연변이 점검

**모든 태스크에서, 커밋 전에 구현을 일부러 망가뜨려 테스트가 잡는지 확인하라.** 최소 세 군데를 골라 각각 러너를 돌리고, 실패 메시지를 확인한 뒤 원상복구한다. 하나라도 통과해버리면 그 테스트는 아무것도 지키지 않는 것이므로 어서션을 보강한다.

이 계획을 실행하는 동안 이 점검이 실제로 잡아낸 것들:
- 러너가 크래시한 모듈을 `ALL PASS`로 보고 (Task 1)
- 계약 상수 두 개가 아무 어서션에도 걸리지 않음 (Task 2)
- 가속 상쇄가 영구 센티넬을 무시하는 버그와, 그것을 방어하는 테스트의 부재 (Task 3)

러너는 `timeout 120`을 앞에 붙여 실행하라.

---

## 파일 구조

```
sim/
  sim_const.gd       상수 + 초↔틱 변환. 의존 없음
  part.gd            파츠 런타임 상태 (쿨타임, 가속/둔화, 발동 횟수, 보강, 파괴 불가, 파손)
  ship_state.gd      함선 상태 (슬롯, HP/보호막, 자재/공명, 재생/과열, 파괴선)
  catalog.gd         파츠·Frame JSON 로드 + 스키마 검증 + AUGMENT 병합
  build_loader.gd    빌드 JSON 로드 + 빌드 검증 → ShipState 조립
  targeting.gd       대상 셀렉터 해석. ship/part를 인자로 받음(덕타이핑, preload 순환 회피)
  conditions.gd      where 조건 평가
  actions.gd         원자 액션 op 실행
  trigger_engine.gd  이벤트 큐 → 트리거 매칭 → 액션 실행 → 새 이벤트
  combat_sim.gd      틱 루프, 발동 단계, 파괴선 검사, 승패 판정
  data/
    frames/standard_frame.json
    test_parts/*.json      0a 전용 합성 픽스처 (0b에서 실제 파츠로 대체)
    test_builds/*.json
tests/
  test_helpers.gd    어서션 수집기
  unit/*.gd          모듈별 테스트. 각각 `run(t)` 하나를 노출
  run_unit.gd        모듈 수집 → 실행 → exit code
```

**의존 방향은 단방향이다.** `targeting`/`conditions`/`actions`는 `ship_state.gd`를 `preload`하지 **않는다** — 함선·파츠 객체를 인자로 받아 덕타이핑으로 쓴다. GDScript의 `preload` 순환을 원천 차단하기 위함이며, 동시에 이 세 모듈을 가짜 함선으로 단독 테스트할 수 있게 한다.

---

## Task 1: 테스트 하네스

**Files:**
- Create: `tests/test_helpers.gd`
- Create: `tests/run_unit.gd`
- Create: `tests/unit/test_harness.gd`

- [ ] **Step 1: 어서션 수집기를 쓴다**

`tests/test_helpers.gd`:

```gdscript
extends RefCounted
## 테스트 모듈이 결과를 모으는 수집기. 예외를 던지지 않고 실패를 누적한다 —
## GDScript에는 예외가 없고, 한 모듈에서 여러 실패를 한 번에 보는 편이 낫다.

var failures: Array[String] = []
var checks: int = 0

## 모듈이 끝까지 실행됐음을 표시한다. 모듈의 run() 마지막 줄에서 호출한다.
## GDScript에는 예외가 없어서, 런타임 에러로 중단된 모듈은 이 플래그가 서지 않는다 —
## 러너가 그것을 크래시로 판정하는 유일한 방법이다.
var completed: bool = false

func done() -> void:
	completed = true

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func eq(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s — expected <%s>, got <%s>" % [message, str(expected), str(actual)])

func near(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s — expected ~%f, got %f" % [message, expected, actual])
```

- [ ] **Step 2: 러너를 쓴다**

`tests/run_unit.gd`:

```gdscript
extends SceneTree
## 헤드리스 단위 테스트 러너.
## 실행: godot --headless --path . --script res://tests/run_unit.gd
## exit 0 = 전체 통과, exit 1 = 실패 있음.

const HELPERS_PATH := "res://tests/test_helpers.gd"

const MODULES: Array[String] = [
	"res://tests/unit/test_harness.gd",
]

func _init() -> void:
	var helpers_script: GDScript = load(HELPERS_PATH)
	var total_checks: int = 0
	var all_failures: Array[String] = []
	var module_lines: Array[String] = []

	for path: String in MODULES:
		# 파싱 에러가 난 스크립트는 null이 아니라 인스턴스화 불가능한 GDScript로 돌아온다.
		# null만 걸러내면 아래 script.new()가 _init() 안에서 에러를 내고,
		# 그러면 quit()에 도달하지 못해 헤드리스 프로세스가 멈춘 채 남는다.
		# 이 계획의 모든 태스크가 "Step 3에서 일부러 실패시키기"로 시작하므로 매번 밟는다.
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			all_failures.append("%s :: 모듈을 로드할 수 없음 — 파싱 에러 (stderr 확인)" % path.get_file())
			continue
		var module: RefCounted = script.new()
		var t: RefCounted = helpers_script.new()
		module.run(t)

		# 완료 센티넬은 run() 자체가 중단된 경우만 잡는다.
		# 서브테스트(_test_*)에서 에러가 나면 GDScript는 그 함수만 중단하고 run()으로
		# 돌아오므로 t.done()이 정상 호출되고 모듈은 통과처럼 보인다.
		# 그래서 어서션 개수도 함께 검증한다 — 서브테스트가 통째로 건너뛰어지면 수가 모자란다.
		if not t.completed:
			all_failures.append("%s :: 모듈이 끝까지 실행되지 않았다 — run()이 중간에 중단됐다 (stderr 확인)"
				% path.get_file())
		var expected: int = int(script.get_script_constant_map().get("EXPECTED_CHECKS", -1))
		if expected < 0:
			all_failures.append("%s :: EXPECTED_CHECKS 상수가 없다 — 서브테스트 중단을 감지할 수 없다"
				% path.get_file())
		elif t.checks != expected:
			all_failures.append("%s :: 어서션 %d개를 기대했는데 %d개가 실행됐다 — 서브테스트가 중단됐거나, 어서션을 바꾸고 EXPECTED_CHECKS를 갱신하지 않았다"
				% [path.get_file(), expected, t.checks])

		module_lines.append("  %-28s %3d checks" % [path.get_file(), t.checks])
		total_checks += t.checks
		for failure: String in t.failures:
			all_failures.append("%s :: %s" % [path.get_file(), failure])

	print("")
	for line: String in module_lines:
		print(line)
	print("checks: %d, failures: %d" % [total_checks, all_failures.size()])
	for failure: String in all_failures:
		print("  FAIL  %s" % failure)
	if all_failures.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		quit(1)
```

- [ ] **Step 3: 하네스 자체를 검증하는 테스트를 쓴다 (실패하도록)**

`tests/unit/test_harness.gd`:

```gdscript
extends RefCounted

func run(t: RefCounted) -> void:
	t.eq(1 + 1, 2, "sanity: 덧셈")
	t.check(true, "sanity: check")
	t.eq("intentional", "failure", "의도된 실패 — 러너가 exit 1을 내는지 확인")
```

- [ ] **Step 4: 실행해서 실패하는지 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `checks: 3, failures: 1` / `FAIL  test_harness.gd :: 의도된 실패 ...` / `EXIT=1`

- [ ] **Step 5: 의도된 실패를 제거하고 통과시킨다**

`tests/unit/test_harness.gd`의 마지막 줄을 다음 세 줄로 교체:

```gdscript
	t.eq("intentional", "intentional", "러너가 통과 시 exit 0")
	t.near(1.0, 1.00001, "sanity: near — 기본 허용오차 안")
	t.done()
```

- [ ] **Step 6: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `checks: 4, failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 6b: 완료 센티넬이 실제로 크래시를 잡는지 증명한다**

`run()` 중간에 일부러 런타임 에러를 내는 두 줄을 임시로 넣고 러너를 돌린다:

```gdscript
	var nothing: RefCounted = null
	nothing.some_method()
```

Expected: stderr에 `SCRIPT ERROR`가 찍히고, 러너가
`FAIL  test_harness.gd :: 모듈이 끝까지 실행되지 않았다` / `EXIT=1`을 낸다.
확인 후 두 줄을 지우고 `git status`가 깨끗한지 확인한다.

**이 검증이 이 태스크의 전부다.** GDScript에는 예외가 없어서, 모듈의 `run()`이 런타임
에러로 중단되면 그 호출만 중단되고 러너의 루프는 계속 돈다. 크래시는 `t.failures`에
아무것도 남기지 않으므로, 센티넬이 없으면 크래시한 모듈이 `ALL PASS` / exit 0으로
보고된다. 앞으로 11개 모듈이 이 위에 올라간다.

- [ ] **Step 7: 커밋**

```bash
git add tests/ && git commit -m "test: headless unit test harness

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: 상수와 시간 단위

**Files:**
- Create: `sim/sim_const.gd`
- Create: `tests/unit/test_sim_const.gd`
- Modify: `tests/run_unit.gd` (MODULES에 추가)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/unit/test_sim_const.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")

func run(t: RefCounted) -> void:
	# 스펙 §4.1 §4.2 §4.5 §4.6의 불변 규칙이 코드에 그대로 있는지
	t.near(K.TICK_DT, 0.05, "고정 틱 0.05초")
	t.eq(K.MIN_FIRE_TICKS, 4, "발동 상한 초당 5회 = 4틱")
	t.eq(K.MAX_CHAIN_DEPTH, 12, "체인 깊이 상한")
	t.eq(K.DEFAULT_FIRE_LIMIT, 5, "drain_fires가 무제한 파츠에 씌우는 기본 수명")
	t.eq(K.RESONANCE_PER_FIRES, 8, "발동 8회마다 공명 +1")

	# 정수 속도 유닛 — 가속은 정확히 2배, 둔화는 정확히 절반
	t.eq(K.SPEED_NORMAL, 2, "보통 속도 유닛")
	t.eq(K.SPEED_ACCEL, K.SPEED_NORMAL * 2, "가속은 보통의 2배")
	t.eq(K.SPEED_SLOW, 1, "둔화는 보통의 절반")

	# 나머지 계약 상수 — 이 값들이 조용히 바뀌면 결정론과 전투 길이가 달라진다.
	# 센티넬은 리터럴과 대조한다. 상수를 상수 자신과 비교하면 지키는 게 없다.
	t.eq(K.MAX_COMBAT_TICKS, 2400, "전투 시간 상한 120초 = 2400틱")
	t.eq(K.PERIOD_TICKS, 20, "재생·과열 주기 1초 = 20틱")
	t.eq(K.UNLIMITED, -1, "무제한 발동 횟수 센티넬")
	t.eq(K.PERMANENT, -1, "영구 지속시간 센티넬")

	# 초 → 틱 변환
	t.eq(K.secs_to_ticks(3.0), 60, "3초 = 60틱")
	t.eq(K.secs_to_ticks(0.2), 4, "0.2초 = 4틱")
	t.eq(K.secs_to_ticks(-1.0), K.PERMANENT, "음수 지속시간은 영구 센티넬")

	# 쿨타임 → 유닛 변환. 5초 파츠는 100틱 * 2유닛 = 200유닛
	t.eq(K.cooldown_to_units(5.0), 200, "쿨타임 5초 = 200유닛")
	t.eq(K.cooldown_to_units(0.2), 8, "쿨타임 0.2초 = 8유닛")

	# 틱 → 초 (이벤트의 t 필드용)
	t.near(K.ticks_to_secs(60), 3.0, "60틱 = 3.0초")
	t.done()
```

- [ ] **Step 2: 러너에 모듈을 등록한다**

`tests/run_unit.gd`의 `MODULES`를 다음으로 교체:

```gdscript
const MODULES: Array[String] = [
	"res://tests/unit/test_harness.gd",
	"res://tests/unit/test_sim_const.gd",
]
```

- [ ] **Step 3: 실행해서 실패하는지 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/sim_const.gd` 로드 실패로 파싱 에러 또는 `모듈을 로드할 수 없음`, `EXIT=1`

- [ ] **Step 4: 구현한다**

`sim/sim_const.gd`:

```gdscript
extends RefCounted
## 전투 시뮬레이션의 불변 상수. 여기 있는 값은 밸런스 수치가 아니라 계약이다.
## 스펙 §4를 참조. 의존 없음 — sim/ 전체가 이것을 preload한다.

## 고정 틱. 이벤트의 t 필드를 만들 때만 쓴다. 내부 시간 계산은 전부 정수 틱이다.
const TICK_DT: float = 0.05

## 발동 상한 초당 5회 = 마지막 발동으로부터 4틱(0.2초) 미경과 시 발동 불가. 스펙 §4.2
const MIN_FIRE_TICKS: int = 4

## 체인 깊이 상한. 초과 시 chain_capped 이벤트. 스펙 §4.6
const MAX_CHAIN_DEPTH: int = 12

## 무제한 파츠가 drain_fires를 처음 맞을 때 확정되는 수명. 스펙 §4.5
const DEFAULT_FIRE_LIMIT: int = 5

## 발동 누적 8회마다 공명 +1. 스펙 §7.2
const RESONANCE_PER_FIRES: int = 8

## 전투 시간 상한. 초과 시 잔여 HP 비율로 판정. 스펙 §4.1
const MAX_COMBAT_TICKS: int = 2400  # 120초

## 재생·과열이 적용되는 주기 (1초)
const PERIOD_TICKS: int = 20

## 쿨타임 진행 속도 유닛. 정수라서 드리프트가 없다. 스펙 §6.5
const SPEED_NORMAL: int = 2
const SPEED_ACCEL: int = 4   # 가속: 정확히 2배
const SPEED_SLOW: int = 1    # 둔화: 정확히 절반

## 무제한 발동 횟수 / 영구 지속시간 센티넬
const UNLIMITED: int = -1
const PERMANENT: int = -1

static func secs_to_ticks(secs: float) -> int:
	if secs < 0.0:
		return PERMANENT
	return int(round(secs / TICK_DT))

static func ticks_to_secs(ticks: int) -> float:
	return float(ticks) * TICK_DT

## 쿨타임(초)을 진행 유닛 목표치로. 보통 속도로 정확히 그 초가 걸린다.
static func cooldown_to_units(secs: float) -> int:
	return secs_to_ticks(secs) * SPEED_NORMAL
```

- [ ] **Step 5: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 6: 커밋**

```bash
git add sim/sim_const.gd tests/ && git commit -m "feat(sim): tick-integer time constants

모든 시간을 정수 틱/유닛으로 다뤄 부동소수 드리프트를 제거한다.
결정론(같은 시드 = 같은 스트림)이 배치 검증의 전제이므로 계약이다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: 파츠 런타임 — 쿨타임, 가속·둔화, 발동 상한, 발동 횟수

**Files:**
- Create: `sim/part.gd`
- Create: `tests/unit/test_part_timing.gd`
- Modify: `tests/run_unit.gd`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/unit/test_part_timing.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")

func _make(cooldown: float, fire_limit: int = K.UNLIMITED) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = "weapon_1"
	p.part_id = "test_gun"
	p.part_name = "테스트 포"
	p.faction = "reclaimer"
	p.cooldown_units = K.cooldown_to_units(cooldown)
	p.fire_limit = fire_limit
	p.fires_remaining = fire_limit
	return p

func run(t: RefCounted) -> void:
	_test_cooldown(t)
	_test_accel_slow(t)
	_test_rate_cap(t)
	_test_fire_limit(t)
	_test_broken_stops_everything(t)
	_test_empower(t)
	t.done()

func _test_cooldown(t: RefCounted) -> void:
	var p: RefCounted = _make(1.0)  # 20틱 = 40유닛
	for i: int in 19:
		p.advance()
	t.check(not p.is_ready(), "쿨타임 1초 파츠는 19틱에 준비되지 않는다")
	p.advance()
	t.check(p.is_ready(), "20틱에 준비된다")

	# 발동 시 초과분이 이월된다
	p.advance()  # 21틱: 42유닛
	p.consume_fire(21)
	t.eq(p.progress_units, 2, "발동 후 초과분 2유닛이 이월된다")

	# 쿨타임에 미달한 상태에서 강제 발동하면 진행도를 빼지 않는다
	# (체인이 fire_part로 준비되지 않은 파츠를 발동시킬 수 있다)
	var early: RefCounted = _make(1.0)   # 40유닛 필요
	early.advance()                      # 2유닛
	early.consume_fire(1)
	t.eq(early.progress_units, 2, "쿨타임 미달 시 발동해도 진행도가 깎이지 않는다")

func _test_accel_slow(t: RefCounted) -> void:
	# 가속: 쿨타임 1초 파츠가 10틱에 준비된다
	var p: RefCounted = _make(1.0)
	p.apply_accel(K.secs_to_ticks(1.0))
	for i: int in 10:
		p.advance()
	t.check(p.is_ready(), "가속 중이면 절반 시간에 준비된다")

	# 둔화: 40틱 걸린다
	var q: RefCounted = _make(1.0)
	q.apply_slow(K.secs_to_ticks(3.0))
	for i: int in 39:
		q.advance()
	t.check(not q.is_ready(), "둔화 중이면 39틱에 준비되지 않는다")
	q.advance()
	t.check(q.is_ready(), "둔화 중이면 40틱에 준비된다")

	# 같은 종류는 지속시간 합산. 스펙 §6.5
	var r: RefCounted = _make(10.0)
	r.apply_accel(20)
	r.apply_accel(30)
	t.eq(r.accel_ticks, 50, "가속끼리는 지속시간이 합산된다")

	# 반대 종류는 상쇄. 짧은 쪽이 사라지고 긴 쪽에 차이만 남는다
	var s: RefCounted = _make(10.0)
	s.apply_slow(30)
	s.apply_accel(50)
	t.eq(s.slow_ticks, 0, "상쇄: 둔화가 전부 지워진다")
	t.eq(s.accel_ticks, 20, "상쇄: 가속에 차이 20틱만 남는다")
	t.eq(s.speed_units(), K.SPEED_ACCEL, "상쇄 후에는 가속 상태")

	var u: RefCounted = _make(10.0)
	u.apply_accel(30)
	u.apply_slow(30)
	t.eq(u.accel_ticks, 0, "완전 상쇄: 가속 0")
	t.eq(u.slow_ticks, 0, "완전 상쇄: 둔화 0")
	t.eq(u.speed_units(), K.SPEED_NORMAL, "완전 상쇄 후에는 보통 속도")

	# 영구 지속시간은 감소하지 않는다
	var v: RefCounted = _make(10.0)
	v.apply_accel(K.PERMANENT)
	for i: int in 100:
		v.advance()
	t.eq(v.accel_ticks, K.PERMANENT, "영구 가속은 만료되지 않는다")

	# 영구를 걸면 반대 효과는 지워진다
	var w: RefCounted = _make(10.0)
	w.apply_slow(30)
	w.apply_accel(K.PERMANENT)
	t.eq(w.slow_ticks, 0, "영구 가속은 남아 있던 둔화를 지운다")
	t.eq(w.accel_ticks, K.PERMANENT, "영구 가속이 걸린다")

	# 영구인 반대 효과는 유한한 양에 깎이지 않는다.
	# 상쇄 가드를 `ticks > 0`으로 쓰면 여기서 영구 둔화가 통째로 무시된다.
	var x: RefCounted = _make(10.0)
	x.apply_slow(K.PERMANENT)
	x.apply_accel(20)
	t.eq(x.slow_ticks, K.PERMANENT, "영구 둔화는 유한 가속에 지워지지 않는다")
	t.eq(x.accel_ticks, 0, "유한 가속은 영구 둔화에 전부 흡수된다")
	t.eq(x.speed_units(), K.SPEED_SLOW, "영구 둔화가 계속 유효하다")

	# 영구끼리는 서로를 지운다
	var y: RefCounted = _make(10.0)
	y.apply_slow(K.PERMANENT)
	y.apply_accel(K.PERMANENT)
	t.eq(y.accel_ticks, 0, "영구끼리 맞부딪히면 가속이 0")
	t.eq(y.slow_ticks, 0, "영구끼리 맞부딪히면 둔화도 0")
	t.eq(y.speed_units(), K.SPEED_NORMAL, "상쇄되어 보통 속도")

	# 불변식: 가속과 둔화가 동시에 0이 아닌 상태는 존재하지 않는다
	for pair: Array in [[20, 50], [50, 20], [30, 30], [K.PERMANENT, 10], [10, K.PERMANENT]]:
		var z: RefCounted = _make(10.0)
		z.apply_slow(pair[0])
		z.apply_accel(pair[1])
		t.check(z.accel_ticks == 0 or z.slow_ticks == 0,
			"불변식: 가속(%d)과 둔화(%d)가 동시에 0이 아닐 수 없다" % [z.accel_ticks, z.slow_ticks])

func _test_broken_stops_everything(t: RefCounted) -> void:
	# 파손 파츠는 쿨타임도 지속효과도 멈춘다
	var p: RefCounted = _make(10.0)
	p.apply_accel(50)
	p.advance()
	var progress: int = p.progress_units
	var accel: int = p.accel_ticks

	p.broken = true
	for i: int in 10:
		p.advance()
	t.eq(p.progress_units, progress, "파손 파츠는 쿨타임이 멈춘다")
	t.eq(p.accel_ticks, accel, "파손 파츠는 가속 지속시간도 멈춘다")
	t.check(not p.is_ready(), "파손 파츠는 준비 상태가 될 수 없다")

func _test_empower(t: RefCounted) -> void:
	# empower 스택은 넣은 순서대로 하나씩 소모된다
	var p: RefCounted = _make(1.0)
	t.near(p.take_empower(), 1.0, "스택이 없으면 1.0배")

	p.empower_stacks.append(1.5)
	p.empower_stacks.append(2.0)
	t.near(p.take_empower(), 1.5, "먼저 넣은 스택이 먼저 나온다")
	t.eq(p.empower_stacks.size(), 1, "한 스택 소모")
	t.near(p.take_empower(), 2.0, "다음 스택")
	t.eq(p.empower_stacks.size(), 0, "전부 소모")
	t.near(p.take_empower(), 1.0, "소진 후에는 다시 1.0배")

func _test_rate_cap(t: RefCounted) -> void:
	# 스펙 §4.2 — 마지막 발동으로부터 4틱 미경과면 발동 불가
	var p: RefCounted = _make(0.2)
	p.consume_fire(100)
	t.eq(p.block_reason(103), "rate_cap", "3틱 뒤에는 상한에 막힌다")
	t.eq(p.block_reason(104), "", "4틱 뒤에는 발동할 수 있다")

func _test_fire_limit(t: RefCounted) -> void:
	# 스펙 §4.5 — 유한 파츠는 발동할 때마다 1 감소, 0이면 발동 불가
	var p: RefCounted = _make(1.0, 2)
	t.eq(p.fires_remaining, 2, "초기 남은 횟수")
	p.consume_fire(0)
	t.eq(p.fires_remaining, 1, "발동하면 1 감소")
	p.consume_fire(10)
	t.eq(p.fires_remaining, 0, "두 번째 발동으로 소진")
	t.eq(p.block_reason(20), "fire_limit", "소진되면 발동 불가")

	# 무제한 파츠는 줄지 않는다
	var q: RefCounted = _make(1.0)
	q.consume_fire(0)
	t.eq(q.fires_remaining, K.UNLIMITED, "무제한 파츠는 감소하지 않는다")
	t.eq(q.block_reason(20), "", "무제한 파츠는 횟수로 막히지 않는다")

	# fires_used는 무제한 파츠에서도 누적된다 (every_nth_fire 조건용)
	t.eq(q.fires_used, 1, "무제한 파츠도 발동 이력은 센다")

	# 파손 파츠는 발동 불가
	var r: RefCounted = _make(1.0)
	r.broken = true
	t.eq(r.block_reason(100), "broken", "파손 파츠는 발동 불가")
```

- [ ] **Step 2: 러너에 등록한다**

`tests/run_unit.gd`의 `MODULES`에 `"res://tests/unit/test_part_timing.gd",`를 추가한다.

- [ ] **Step 3: 실행해서 실패하는지 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/part.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 4: 구현한다**

`sim/part.gd`:

```gdscript
extends RefCounted
## 파츠 하나의 런타임 상태. 스펙 §4.2 §4.5 §6.5 §8.
## 정의(JSON)는 catalog가 병합해서 넣어준다 — 이 클래스는 상태만 갖는다.

const K = preload("res://sim/sim_const.gd")

# --- 정체 (catalog가 채움) ---
var slot_id: String = ""
var role: String = ""
var part_id: String = ""
var part_name: String = ""
var faction: String = ""
var keywords: Array[String] = []
var augment_id: String = ""

# --- 발동 규칙 (catalog가 채움) ---
var cooldown_units: int = 0
var cost: Dictionary = {}
var on_fire: Array = []
var triggers: Array = []
## triggers와 같은 길이. max_fires 계산용 — 트리거별 전투당 발동 횟수.
var trigger_fires: Array[int] = []

# --- 런타임 상태 ---
var progress_units: int = 0
var accel_ticks: int = 0
var slow_ticks: int = 0
var fire_limit: int = K.UNLIMITED
var fires_remaining: int = K.UNLIMITED
var fires_used: int = 0
var last_fire_tick: int = -99999
var reinforce_stacks: int = 0
## 0 = 없음, K.PERMANENT = 영구, 그 외 = 남은 틱
var indestructible_ticks: int = 0
## empower 스택. 각 원소가 damage_mult 하나. 발동 시 앞에서부터 소모한다.
var empower_stacks: Array[float] = []
var broken: bool = false

# --- 쿨타임 ---

func speed_units() -> int:
	if accel_ticks != 0:
		return K.SPEED_ACCEL
	if slow_ticks != 0:
		return K.SPEED_SLOW
	return K.SPEED_NORMAL

## 한 틱 진행. 파손 상태면 쿨타임도 지속효과도 멈춘다 (스펙 §8 파손 상태).
func advance() -> void:
	if broken:
		return
	progress_units += speed_units()
	if accel_ticks > 0:
		accel_ticks -= 1
	if slow_ticks > 0:
		slow_ticks -= 1
	if indestructible_ticks > 0:
		indestructible_ticks -= 1

func is_ready() -> bool:
	return not broken and progress_units >= cooldown_units

# --- 가속 / 둔화 (스펙 §6.5) ---

func apply_accel(ticks: int) -> void:
	_apply_speed_effect(ticks, true)

func apply_slow(ticks: int) -> void:
	_apply_speed_effect(ticks, false)

## 가속과 둔화는 서로 배타적이다 — 상쇄 규칙상 둘 중 하나는 항상 0이다.
## 이 불변식을 유지하는 것이 이 함수의 유일한 책임이다.
## 영구(K.PERMANENT = -1)는 무한한 지속시간이므로 유한한 양으로 깎을 수 없고,
## 유한한 양을 아무리 쌓아도 영구를 넘어설 수 없다.
##
## 주의: 상쇄 가드를 `ticks > 0`으로 쓰면 안 된다. 영구 센티넬이 -1이라
## 그 조건을 통과하지 못해, 영구 둔화가 걸린 파츠에 유한 가속을 걸었을 때
## 둔화가 상쇄되지 않고 speed_units()가 가속을 먼저 보아 영구 둔화를 통째로 무시한다.
func _apply_speed_effect(ticks: int, accelerating: bool) -> void:
	var same: int = accel_ticks if accelerating else slow_ticks
	var opposite: int = slow_ticks if accelerating else accel_ticks

	if ticks == K.PERMANENT:
		if opposite == K.PERMANENT:
			# 영구끼리 맞부딪히면 서로를 지운다
			same = 0
			opposite = 0
		else:
			# 영구는 유한한 반대 효과를 전부 덮는다
			same = K.PERMANENT
			opposite = 0
	elif opposite == K.PERMANENT:
		# 영구인 반대 효과는 유한한 양에 깎이지 않는다 — 들어온 양이 전부 흡수된다
		pass
	elif same == K.PERMANENT:
		# 이미 영구다. 더 쌓을 것이 없다
		pass
	else:
		var remaining: int = ticks
		var cancel: int = mini(opposite, remaining)
		opposite -= cancel
		remaining -= cancel
		same += remaining

	if accelerating:
		accel_ticks = same
		slow_ticks = opposite
	else:
		slow_ticks = same
		accel_ticks = opposite

# --- 발동 ---

## 발동을 막는 이유. 빈 문자열이면 발동 가능.
## 자재 비용은 함선 상태가 필요하므로 ShipState가 따로 검사한다.
func block_reason(tick: int) -> String:
	if broken:
		return "broken"
	if tick - last_fire_tick < K.MIN_FIRE_TICKS:
		return "rate_cap"
	if fires_remaining == 0:
		return "fire_limit"
	return ""

## 발동 확정. 쿨타임 초과분은 이월한다.
func consume_fire(tick: int) -> void:
	fires_used += 1
	last_fire_tick = tick
	if progress_units >= cooldown_units:
		progress_units -= cooldown_units
	if fires_remaining != K.UNLIMITED:
		fires_remaining = maxi(0, fires_remaining - 1)

## 이번 발동에 적용할 피해 배율. empower 스택을 하나 소모한다.
func take_empower() -> float:
	if empower_stacks.is_empty():
		return 1.0
	return empower_stacks.pop_front()

func has_keyword(kw: String) -> bool:
	return keywords.has(kw)
```

- [ ] **Step 5: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 6: 커밋**

```bash
git add sim/part.gd tests/ && git commit -m "feat(sim): part runtime — cooldown, accel/slow cancellation, fire limit

가속/둔화는 배율 고정(x2 / x0.5)이고 파츠가 지정하는 것은 지속시간뿐이다.
같은 종류는 합산, 반대 종류는 남은 시간끼리 상쇄한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: 파츠 런타임 — 보강, 파괴 불가, 파손·복구

**Files:**
- Modify: `sim/part.gd` (파손·복구·방어 메서드 추가)
- Create: `tests/unit/test_part_destruction.gd`
- Modify: `tests/run_unit.gd`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/unit/test_part_destruction.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")

func _make(fire_limit: int = K.UNLIMITED) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = "weapon_1"
	p.part_id = "test_gun"
	p.cooldown_units = K.cooldown_to_units(1.0)
	p.fire_limit = fire_limit
	p.fires_remaining = fire_limit
	return p

func run(t: RefCounted) -> void:
	_test_indestructible(t)
	_test_reinforce(t)
	_test_break_and_restore(t)
	_test_fires_drain_restore(t)
	_test_defense_edge_cases(t)
	t.done()

func _test_indestructible(t: RefCounted) -> void:
	# 스펙 §8 — 기간제 면제. 보강보다 먼저 적용되고 보강 스택을 소모하지 않는다.
	var p: RefCounted = _make()
	p.reinforce_stacks = 1
	p.make_indestructible(K.secs_to_ticks(1.0))
	t.eq(p.try_break(), "indestructible", "파괴 불가면 파손이 막힌다")
	t.eq(p.reinforce_stacks, 1, "파괴 불가는 보강 스택을 소모하지 않는다")
	t.check(not p.broken, "파괴 불가 파츠는 파손되지 않는다")

	# 20틱 뒤 만료
	for i: int in 20:
		p.advance()
	t.eq(p.indestructible_ticks, 0, "20틱 뒤 파괴 불가가 만료된다")
	t.eq(p.try_break(), "reinforce", "만료 후에는 보강이 막는다")

	# 영구
	var q: RefCounted = _make()
	q.make_indestructible(K.PERMANENT)
	for i: int in 500:
		q.advance()
	t.eq(q.try_break(), "indestructible", "영구 파괴 불가는 만료되지 않는다")

func _test_reinforce(t: RefCounted) -> void:
	# 스펙 §8 — 횟수제 방어. 1 소모하고 파손을 막는다.
	var p: RefCounted = _make()
	p.reinforce_stacks = 2
	t.eq(p.try_break(), "reinforce", "보강이 첫 파손을 막는다")
	t.eq(p.reinforce_stacks, 1, "보강 스택 1 소모")
	t.eq(p.try_break(), "reinforce", "보강이 두 번째 파손을 막는다")
	t.eq(p.reinforce_stacks, 0, "보강 스택 소진")
	t.eq(p.try_break(), "broken", "보강이 떨어지면 파손된다")
	t.check(p.broken, "파손 플래그")

func _test_break_and_restore(t: RefCounted) -> void:
	# 스펙 §8 — 파손: 효과·쿨타임 정지, 슬롯 유지. 복구: 쿨타임 0 재시작 + 횟수 초기화
	var p: RefCounted = _make(3)
	p.consume_fire(0)
	p.consume_fire(10)
	p.apply_accel(50)
	p.advance()
	var progress_before: int = p.progress_units

	t.eq(p.try_break(), "broken", "파손")
	p.advance()
	t.eq(p.progress_units, progress_before, "파손 파츠는 쿨타임이 멈춘다")
	# 파손 전 advance()가 이미 50 → 49로 깎았다. 파손 후 advance()가 no-op인지를 보는 것이다.
	t.eq(p.accel_ticks, 49, "파손 파츠는 지속효과도 멈춘다")

	p.restore()
	t.check(not p.broken, "복구되면 파손이 풀린다")
	t.eq(p.progress_units, 0, "복구 시 쿨타임은 0에서 재시작")
	t.eq(p.fires_remaining, 3, "복구 시 남은 횟수는 초기값으로 돌아간다")

func _test_fires_drain_restore(t: RefCounted) -> void:
	# 스펙 §4.5 — 무제한 파츠가 처음 drain을 맞으면 DEFAULT_FIRE_LIMIT로 확정된다
	var p: RefCounted = _make()
	var drained: int = p.drain_fires(1)
	t.eq(drained, 1, "실제로 깎인 양을 돌려준다")
	t.eq(p.fire_limit, K.DEFAULT_FIRE_LIMIT, "무제한 파츠에 기본 수명이 확정된다")
	t.eq(p.fires_remaining, K.DEFAULT_FIRE_LIMIT - 1, "확정 후 깎인다")

	# 이미 유한한 파츠는 그냥 깎인다
	var q: RefCounted = _make(4)
	q.drain_fires(2)
	t.eq(q.fire_limit, 4, "유한 파츠의 초기값은 바뀌지 않는다")
	t.eq(q.fires_remaining, 2, "유한 파츠는 그대로 깎인다")

	# 0 아래로는 내려가지 않는다
	q.drain_fires(5)
	t.eq(q.fires_remaining, 0, "남은 횟수는 0 미만이 되지 않는다")

	# restore_fires는 초기값을 넘지 않는다
	q.restore_fires(10)
	t.eq(q.fires_remaining, 4, "회복은 초기값을 초과하지 않는다")

	# 무제한 파츠에 restore_fires는 아무 일도 하지 않는다
	var r: RefCounted = _make()
	t.eq(r.restore_fires(3), 0, "무제한 파츠는 회복 대상이 아니다")
	t.eq(r.fires_remaining, K.UNLIMITED, "무제한 그대로")

	# 남은 횟수 0 + 파괴 불가 = 파손 유예, 그러나 발동은 불가 (스펙 §8)
	var s: RefCounted = _make(1)
	s.make_indestructible(K.secs_to_ticks(1.0))
	s.consume_fire(0)
	t.eq(s.fires_remaining, 0, "소진")
	t.eq(s.try_break(), "indestructible", "파괴 불가면 소진해도 파손이 유예된다")
	t.eq(s.block_reason(100), "fire_limit", "유예되어도 발동은 불가")

func _test_defense_edge_cases(t: RefCounted) -> void:
	# 이미 파손된 파츠는 다시 파손되지 않고 보강도 먹지 않는다
	var p: RefCounted = _make()
	p.reinforce_stacks = 2
	p.broken = true
	t.eq(p.try_break(), "already_broken", "이미 파손된 파츠는 already_broken")
	t.eq(p.reinforce_stacks, 2, "이미 파손된 파츠는 보강 스택을 소모하지 않는다")

	# 긴 파괴 불가는 짧은 것에 덮어쓰이지 않는다
	var q: RefCounted = _make()
	q.make_indestructible(100)
	q.make_indestructible(10)
	t.eq(q.indestructible_ticks, 100, "짧은 파괴 불가가 긴 것을 덮어쓰지 않는다")
	q.make_indestructible(200)
	t.eq(q.indestructible_ticks, 200, "더 긴 파괴 불가는 연장한다")

	# 영구 파괴 불가는 유한한 값에 깎이지 않는다 (센티넬이 -1이라 maxi만으로는 못 지킨다)
	var r: RefCounted = _make()
	r.make_indestructible(K.PERMANENT)
	r.make_indestructible(50)
	t.eq(r.indestructible_ticks, K.PERMANENT, "영구는 유한값에 깎이지 않는다")
	t.check(r.is_indestructible(), "영구 파괴 불가가 유지된다")

	# is_limited — Task 8의 셀렉터(all_own_limited)가 이 계약에 의존한다
	var s: RefCounted = _make()
	t.check(not s.is_limited(), "무제한 파츠는 제한 걸린 파츠가 아니다")
	s.drain_fires(1)
	t.check(s.is_limited(), "drain_fires를 맞으면 제한이 걸린다")
	var u: RefCounted = _make(3)
	t.check(u.is_limited(), "fire_limit을 명시한 파츠는 처음부터 제한이 걸려 있다")
	u.drain_fires(3)
	t.check(u.is_limited(), "횟수를 다 써도 제한 걸린 파츠인 것은 변하지 않는다")
```

- [ ] **Step 2: 러너에 `"res://tests/unit/test_part_destruction.gd",`를 추가한다**

- [ ] **Step 3: 실행해서 실패하는지 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `try_break`, `make_indestructible`, `restore`, `drain_fires`, `restore_fires` 미정의로 실패, `EXIT=1`

- [ ] **Step 4: 구현한다 — `sim/part.gd` 끝에 추가**

```gdscript
# --- 방어와 파손 (스펙 §8) ---

func is_indestructible() -> bool:
	return indestructible_ticks == K.PERMANENT or indestructible_ticks > 0

func make_indestructible(ticks: int) -> void:
	if ticks == K.PERMANENT:
		indestructible_ticks = K.PERMANENT
	elif indestructible_ticks != K.PERMANENT:
		indestructible_ticks = maxi(indestructible_ticks, ticks)

## 파손을 시도한다. 방어 우선순위: 파괴 불가 → 보강 → 파손.
## 반환값이 그대로 이벤트의 사유가 된다: "indestructible" / "reinforce" / "broken" / "already_broken"
func try_break() -> String:
	if broken:
		return "already_broken"
	if is_indestructible():
		return "indestructible"
	if reinforce_stacks > 0:
		reinforce_stacks -= 1
		return "reinforce"
	broken = true
	return "broken"

## 파손 해제 + 쿨타임 0 재시작 + 남은 횟수 초기화 (스펙 §8)
func restore() -> void:
	broken = false
	progress_units = 0
	fires_remaining = fire_limit

# --- 발동 횟수 (스펙 §4.5) ---

## 남은 횟수를 깎고 실제로 깎인 양을 돌려준다.
## 무제한 파츠는 이 순간 DEFAULT_FIRE_LIMIT로 수명이 확정된다.
func drain_fires(amount: int) -> int:
	if amount <= 0:
		return 0
	if fires_remaining == K.UNLIMITED:
		fire_limit = K.DEFAULT_FIRE_LIMIT
		fires_remaining = K.DEFAULT_FIRE_LIMIT
	var actual: int = mini(amount, fires_remaining)
	fires_remaining -= actual
	return actual

## 남은 횟수를 회복하고 실제 회복량을 돌려준다. 초기값을 넘지 않는다.
## 무제한 파츠는 회복 대상이 아니다.
func restore_fires(amount: int) -> int:
	if amount <= 0 or fires_remaining == K.UNLIMITED:
		return 0
	var actual: int = mini(amount, fire_limit - fires_remaining)
	fires_remaining += actual
	return actual

## 발동 제한이 걸린 파츠인가 (all_own_limited 셀렉터용)
func is_limited() -> bool:
	return fires_remaining != K.UNLIMITED
```

- [ ] **Step 5: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 6: 커밋**

```bash
git add sim/part.gd tests/ && git commit -m "feat(sim): reinforce, indestructible, break and restore

방어 우선순위는 파괴 불가 -> 보강 -> 파손. 파괴 불가는 보강 스택을 소모하지 않는다.
남은 횟수 0 + 파괴 불가 = 파손 유예하되 발동은 불가.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: 카탈로그 — 파츠·Frame 로드, 스키마 검증, AUGMENT 병합

**Files:**
- Create: `sim/data/frames/standard_frame.json`
- Create: `sim/data/test_parts/fixtures.json`
- Create: `sim/catalog.gd`
- Create: `tests/unit/test_catalog.gd`
- Modify: `tests/run_unit.gd`

이 태스크가 스펙 §3.2의 핵심을 구현한다 — **AUGMENT는 특수 코드 경로가 아니라 숙주 파츠 정의에 대한 데이터 병합**(트리거 append / 키워드 union / modify 적용)이다.

- [ ] **Step 1: Frame 데이터를 쓴다**

`sim/data/frames/standard_frame.json` (스펙 §5.2 그대로):

```json
{
  "id": "standard_frame",
  "name": "표준 Frame",
  "hull": 200,
  "relic_slots": 1,
  "thresholds": [0.75, 0.50, 0.25],
  "slots": [
    { "id": "core",      "role": "core"     },
    { "id": "weapon_1",  "role": "weapon"   },
    { "id": "weapon_2",  "role": "weapon"   },
    { "id": "defense_1", "role": "defense"  },
    { "id": "utility_1", "role": "utility"  },
    { "id": "utility_2", "role": "utility"  },
    { "id": "flex_1",    "role": "flexible" }
  ]
}
```

- [ ] **Step 2: 합성 픽스처 파츠를 쓴다**

`sim/data/test_parts/fixtures.json` — 0a 전용이다. 실제 파츠 21종은 Phase 0b에서 만든다.
여기 4종은 모든 병합 규칙과 액션 계열을 덮기 위한 최소 집합이다.

```json
{
  "parts": [
    {
      "id": "fx_gun",
      "name": "픽스처 포",
      "faction": "reclaimer",
      "roles": ["weapon"],
      "keywords": ["damage"],
      "active": {
        "cooldown": 2.0,
        "on_fire": [ { "op": "deal_damage", "amount": 10 } ]
      },
      "augment": {
        "add_keywords": ["damage"],
        "triggers": [
          { "on": "part_fired", "where": { "is_host": true },
            "do": [ { "op": "deal_damage", "amount": 6 } ] }
        ]
      }
    },
    {
      "id": "fx_turbine",
      "name": "픽스처 터빈",
      "faction": "reclaimer",
      "roles": ["utility", "flexible"],
      "keywords": ["accelerate", "fire_limit"],
      "active": {
        "cooldown": 5.0,
        "fire_limit": 6,
        "on_fire": [ { "op": "accelerate", "target": "self", "duration": 3.0 } ]
      },
      "augment": {
        "add_keywords": ["accelerate", "fire_limit"],
        "modify": { "cooldown_mult": 0.5 },
        "triggers": [
          { "on": "part_fired", "where": { "is_host": true },
            "do": [
              { "op": "accelerate",  "target": "host", "duration": 2.0 },
              { "op": "drain_fires", "target": "host", "amount": 1 }
            ] }
        ]
      }
    },
    {
      "id": "fx_medic",
      "name": "픽스처 재생낭",
      "faction": "viridia",
      "roles": ["defense"],
      "keywords": ["repair"],
      "active": {
        "cooldown": 4.0,
        "cost": { "material": 3 },
        "on_fire": [ { "op": "repair", "amount": 10 } ]
      },
      "augment": {
        "add_keywords": ["regen"],
        "triggers": [
          { "on": "material_spent", "where": { "is_host": true },
            "do": [ { "op": "apply_regen", "amount": 2, "duration": 5.0 } ] }
        ]
      }
    },
    {
      "id": "fx_core",
      "name": "픽스처 코어",
      "faction": "aeonic",
      "roles": ["core"],
      "keywords": ["resonance"],
      "active": {
        "cooldown": 10.0,
        "on_fire": [ { "op": "gain_resonance", "amount": 1 } ],
        "triggers": [
          { "on": "combat_start", "do": [ { "op": "gain_material", "amount": 5 } ] }
        ]
      }
    }
  ]
}
```

`fx_core`에 `augment` 블록이 없는 것은 의도적이다 — 스펙 §5.1의 "Core 파츠는 ACTIVE 전용"을 빌드 검증(Task 7)이 걸러내는지 확인하는 데 쓴다.

- [ ] **Step 3: 실패하는 테스트를 쓴다**

`tests/unit/test_catalog.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")

func _loaded() -> RefCounted:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/fixtures.json")
	c.load_frame("res://sim/data/frames/standard_frame.json")
	return c

func run(t: RefCounted) -> void:
	_test_load(t)
	_test_merge_plain(t)
	_test_merge_augment(t)
	_test_schema_errors(t)
	_test_frame_schema_errors(t)
	t.done()

func _test_load(t: RefCounted) -> void:
	var c: RefCounted = _loaded()
	t.check(c.ok(), "픽스처와 Frame이 에러 없이 로드된다: %s" % str(c.errors))
	t.eq(c.parts.size(), 4, "파츠 4종")
	t.check(c.parts.has("fx_gun"), "fx_gun 로드")
	t.eq(c.frames["standard_frame"]["hull"], 200, "Frame hull")
	t.eq(c.frames["standard_frame"]["slots"].size(), 7, "슬롯 7칸")

func _test_merge_plain(t: RefCounted) -> void:
	var c: RefCounted = _loaded()
	var m: Dictionary = c.merge("fx_turbine", "")
	t.eq(m["part_id"], "fx_turbine", "part_id")
	t.eq(m["cooldown_units"], K.cooldown_to_units(5.0), "쿨타임 유닛")
	t.eq(m["fire_limit"], 6, "fire_limit")
	t.eq(m["augment_id"], "", "augment 없음")
	t.eq(m["triggers"].size(), 0, "ACTIVE 트리거 없음")
	t.eq(m["keywords"].size(), 2, "키워드 2종")

	# fire_limit을 명시하지 않은 파츠는 무제한이다.
	# -1(무제한)과 0(발동 불가)은 의미가 정반대이므로 리터럴 대조까지 한다.
	var plain: Dictionary = c.merge("fx_gun", "")
	t.eq(plain["fire_limit"], K.UNLIMITED, "fire_limit 미지정이면 무제한")
	t.eq(plain["fire_limit"], -1, "무제한 센티넬은 -1이다 (0이면 발동 불가라는 정반대 의미가 된다)")

	# roles도 다른 필드와 마찬가지로 원본과 공유하지 않는다
	plain["roles"].append("core")
	var fresh: Dictionary = c.merge("fx_gun", "")
	t.eq(fresh["roles"].size(), 1, "roles를 바꿔도 카탈로그 원본이 오염되지 않는다")
	t.check(not fresh["roles"].has("core"), "오염된 역할이 새 병합에 새지 않는다")

func _test_merge_augment(t: RefCounted) -> void:
	# 스펙 §3.2 — 병합의 세 가지 연산
	var c: RefCounted = _loaded()
	var m: Dictionary = c.merge("fx_gun", "fx_turbine")

	# (1) 트리거 append
	t.eq(m["triggers"].size(), 1, "AUGMENT 트리거가 숙주에 append된다")
	t.eq(m["triggers"][0]["do"].size(), 2, "append된 트리거의 액션 2개")

	# (2) 키워드 union — 중복은 합쳐지지 않는다
	t.check(m["keywords"].has("damage"), "숙주 키워드 유지")
	t.check(m["keywords"].has("accelerate"), "AUGMENT 키워드 추가")
	t.check(m["keywords"].has("fire_limit"), "AUGMENT 키워드 추가")
	t.eq(m["keywords"].size(), 3, "union이므로 중복 없이 3종")

	# (3) modify 적용 — fx_gun 쿨타임 2.0초에 0.5배
	t.eq(m["cooldown_units"], K.cooldown_to_units(1.0), "cooldown_mult 0.5 적용")

	# 정체는 숙주의 것을 유지한다
	t.eq(m["part_id"], "fx_gun", "병합해도 숙주 파츠다")
	t.eq(m["faction"], "reclaimer", "팩션은 숙주의 것")
	t.eq(m["augment_id"], "fx_turbine", "장착된 augment id를 기록한다")

	# 원본 정의가 오염되지 않는다 — 같은 파츠를 두 슬롯에 쓸 수 있어야 한다 (스펙 §5.3)
	var m2: Dictionary = c.merge("fx_gun", "")
	t.eq(m2["triggers"].size(), 0, "병합이 카탈로그 원본을 오염시키지 않는다")
	t.eq(m2["keywords"].size(), 1, "원본 키워드도 오염되지 않는다")

	# 위 두 어서션만으로는 얕은 복사를 잡지 못한다 — fx_gun은 active.triggers가 없어서
	# get("triggers", [])가 매번 새 리터럴을 돌려주므로 별칭 경로를 타지 않기 때문이다.
	# 실제로 내용이 있는 on_fire의 내부 딕셔너리를 변형해서 확인한다.
	m["on_fire"][0]["amount"] = 999
	var m3: Dictionary = c.merge("fx_gun", "")
	t.eq(m3["on_fire"][0]["amount"], 10, "on_fire 딕셔너리를 바꿔도 카탈로그 원본이 오염되지 않는다")

	# 키워드 중복 제거도 fx_gun/fx_turbine 조합으로는 검증되지 않는다 — 두 키워드 집합이
	# 겹치지 않아 중복이 생길 일이 없다. 숙주와 AUGMENT가 같은 키워드를 선언하는 조합으로 본다.
	var m4: Dictionary = c.merge("fx_turbine", "fx_turbine")
	t.eq(m4["keywords"].size(), 2, "숙주와 AUGMENT가 겹치는 키워드는 중복 없이 유지된다")

func _test_schema_errors(t: RefCounted) -> void:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/nope.json")
	t.check(not c.ok(), "없는 파일은 에러다")

	var c2: RefCounted = Catalog.new()
	c2.ingest_parts([
		{ "id": "bad_no_active", "name": "x", "faction": "reclaimer", "roles": ["weapon"] },
		{ "id": "bad_role", "name": "x", "faction": "reclaimer", "roles": ["wizard"],
		  "active": { "cooldown": 1.0 } },
		{ "id": "bad_faction", "name": "x", "faction": "atlantis", "roles": ["weapon"],
		  "active": { "cooldown": 1.0 } },
		{ "id": "bad_cooldown", "name": "x", "faction": "reclaimer", "roles": ["weapon"],
		  "active": { "cooldown": 0.0 } }
	], "inline")
	t.eq(c2.errors.size(), 4, "스키마 위반 4건이 전부 잡힌다: %s" % str(c2.errors))

func _test_frame_schema_errors(t: RefCounted) -> void:
	# 파츠에는 스키마 검증이 있는데 Frame에는 없으면, 망가진 Frame이 조용히 로드된다
	var missing: RefCounted = Catalog.new()
	missing.load_frame("res://sim/data/frames/nope.json")
	t.check(not missing.ok(), "없는 Frame 파일은 에러다")
	t.eq(missing.frames.size(), 0, "실패한 로드는 frames에 아무것도 넣지 않는다")

	# 필수 키가 빠진 Frame은 거부된다. 의도적으로 깨뜨린 고정 픽스처를 쓴다 —
	# 임시 파일을 만들고 지우는 것보다 결정론적이고 읽기 쉽다.
	var broken: RefCounted = Catalog.new()
	broken.load_frame("res://sim/data/frames/broken_frame.json")
	t.check(not broken.ok(), "hull과 thresholds가 빠진 Frame은 거부된다")
	t.eq(broken.frames.size(), 0, "거부된 Frame은 등록되지 않는다")
```

`sim/data/frames/broken_frame.json` — 일부러 `hull`과 `thresholds`를 뺀 픽스처:

```json
{ "id": "broken", "name": "깨진 Frame", "slots": [] }
```

- [ ] **Step 4: 러너에 `"res://tests/unit/test_catalog.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/catalog.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 5: 구현한다**

`sim/catalog.gd`:

```gdscript
extends RefCounted
## 파츠·Frame 정의를 JSON에서 읽어 검증하고, ACTIVE + AUGMENT를 병합한다.
## 스펙 §3.2 §5.1 §5.2.
##
## 병합이 이 파일의 존재 이유다. AUGMENT는 특수 코드 경로가 아니라
## 숙주 파츠 정의에 대한 세 가지 데이터 연산이다:
##   트리거 append / 키워드 union / modify 적용

const K = preload("res://sim/sim_const.gd")

const VALID_ROLES: Array[String] = ["core", "weapon", "defense", "utility", "flexible"]
const VALID_FACTIONS: Array[String] = ["reclaimer", "viridia", "aeonic", "first"]

var parts: Dictionary = {}    # part_id -> 정의 Dictionary
var frames: Dictionary = {}   # frame_id -> 정의 Dictionary
var relics: Dictionary = {}   # relic_id -> 정의 Dictionary
var errors: Array[String] = []

func ok() -> bool:
	return errors.is_empty()

# --- 로드 ---

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("파일 없음: %s" % path)
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("파일을 열 수 없음: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		errors.append("JSON 파싱 실패: %s" % path)
		return null
	return parsed

func load_parts(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	if not (data is Dictionary) or not data.has("parts"):
		errors.append("%s: 최상위에 \"parts\" 배열이 필요하다" % path)
		return
	ingest_parts(data["parts"], path)

func load_relics(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	for relic: Variant in data.get("relics", []):
		if not (relic is Dictionary) or not relic.has("id"):
			errors.append("%s: relic에 id가 없다" % path)
			continue
		relics[relic["id"]] = relic

func load_frame(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	for key: String in ["id", "name", "hull", "slots", "thresholds"]:
		if not data.has(key):
			errors.append("%s: Frame에 \"%s\"가 없다" % [path, key])
			return
	frames[data["id"]] = data

## 배열을 직접 받아 검증한다. 테스트가 인라인 정의를 넣을 수 있게 분리했다.
func ingest_parts(defs: Array, source: String) -> void:
	for def: Variant in defs:
		var problem: String = _validate_part(def)
		if problem != "":
			errors.append("%s: %s" % [source, problem])
			continue
		parts[def["id"]] = def

func _validate_part(def: Variant) -> String:
	if not (def is Dictionary):
		return "파츠 정의가 Dictionary가 아니다"
	for key: String in ["id", "name", "faction", "roles", "active"]:
		if not def.has(key):
			return "%s: \"%s\" 누락" % [str(def.get("id", "?")), key]
	var pid: String = def["id"]
	if not VALID_FACTIONS.has(def["faction"]):
		return "%s: 알 수 없는 팩션 \"%s\"" % [pid, def["faction"]]
	for role: Variant in def["roles"]:
		if not VALID_ROLES.has(role):
			return "%s: 알 수 없는 역할 \"%s\"" % [pid, str(role)]
	var active: Variant = def["active"]
	if not (active is Dictionary):
		return "%s: active가 Dictionary가 아니다" % pid
	if float(active.get("cooldown", 0.0)) <= 0.0:
		return "%s: active.cooldown이 0 이하다" % pid
	return ""

# --- 병합 (스펙 §3.2) ---

## part_id를 ACTIVE로, augment_id를 AUGMENT로 결합한 파츠 사양을 만든다.
## augment_id가 빈 문자열이면 ACTIVE만.
## 반환값은 catalog 원본과 공유하지 않는 깊은 복사본이다 —
## 같은 파츠 id를 여러 슬롯에 쓸 수 있어야 하기 때문이다 (스펙 §5.3).
func merge(part_id: String, augment_id: String) -> Dictionary:
	var host: Dictionary = parts[part_id]
	var active: Dictionary = host["active"]

	var keywords: Array[String] = []
	for kw: Variant in host.get("keywords", []):
		if not keywords.has(str(kw)):
			keywords.append(str(kw))

	var merged: Dictionary = {
		"part_id": part_id,
		"part_name": host["name"],
		"faction": host["faction"],
		"roles": host["roles"].duplicate(),
		"keywords": keywords,
		"cooldown_units": K.cooldown_to_units(float(active["cooldown"])),
		"fire_limit": int(active.get("fire_limit", K.UNLIMITED)),
		"cost": (active.get("cost", {}) as Dictionary).duplicate(true),
		"on_fire": (active.get("on_fire", []) as Array).duplicate(true),
		"triggers": (active.get("triggers", []) as Array).duplicate(true),
		"augment_id": augment_id,
	}
	if augment_id == "":
		return merged

	var aug: Dictionary = parts[augment_id]["augment"]

	# (1) 키워드 union
	for kw: Variant in aug.get("add_keywords", []):
		if not merged["keywords"].has(str(kw)):
			merged["keywords"].append(str(kw))

	# (2) modify 적용
	var mod: Dictionary = aug.get("modify", {})
	if mod.has("cooldown_mult"):
		merged["cooldown_units"] = int(round(merged["cooldown_units"] * float(mod["cooldown_mult"])))

	# (3) 트리거 append
	for tr: Variant in aug.get("triggers", []):
		merged["triggers"].append((tr as Dictionary).duplicate(true))

	return merged
```

- [ ] **Step 6: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 7: 커밋**

```bash
git add sim/catalog.gd sim/data/ tests/ && git commit -m "feat(sim): catalog with AUGMENT as data merge

AUGMENT는 특수 코드 경로가 아니라 숙주 파츠 정의에 대한 세 연산이다 —
트리거 append / 키워드 union / modify 적용. 병합 결과는 깊은 복사본이라
같은 파츠 id를 여러 슬롯에 써도 원본이 오염되지 않는다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: 함선 상태 — 자원, 피해·보호막, 재생·과열, 파괴선

**Files:**
- Create: `sim/ship_state.gd`
- Create: `tests/unit/test_ship_state.gd`
- Modify: `tests/run_unit.gd`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/unit/test_ship_state.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")

func _make_ship(max_hull: int = 200) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = max_hull
	s.hull = max_hull
	s.thresholds = [0.75, 0.50, 0.25]
	s.thresholds_crossed = [false, false, false]
	return s

func _add_part(s: RefCounted, slot_id: String, role: String) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = slot_id
	p.role = role
	p.part_id = "fx_" + slot_id
	p.cooldown_units = K.cooldown_to_units(1.0)
	s.add_part(p)
	return p

func run(t: RefCounted) -> void:
	_test_damage(t)
	_test_thresholds(t)
	_test_material(t)
	_test_resonance(t)
	_test_regen_overheat(t)
	_test_part_lookup(t)
	t.done()

func _test_damage(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	s.shield = 12
	var r: Dictionary = s.take_damage(20)
	t.eq(r["absorbed"], 12, "보호막이 먼저 흡수한다")
	t.eq(r["hull_damage"], 8, "나머지가 선체로")
	t.eq(s.shield, 0, "보호막 소진")
	t.eq(s.hull, 192, "선체 감소")

	s.take_damage(9999)
	t.eq(s.hull, 0, "선체 하한 0")

	var q: RefCounted = _make_ship()
	q.take_damage(50)
	q.repair(200)
	t.eq(q.hull, 200, "수리는 최대 HP를 넘지 않는다")

	# 과열은 보호막을 무시하고 선체를 직접 때린다 (GDD §21 "선체 피해")
	var r2: RefCounted = _make_ship()
	r2.shield = 50
	r2.damage_hull_direct(10)
	t.eq(r2.shield, 50, "과열은 보호막을 소모하지 않는다")
	t.eq(r2.hull, 190, "과열은 선체를 직접 깎는다")

func _test_thresholds(t: RefCounted) -> void:
	# 스펙 §8 — 처음 통과할 때만, 한 방에 두 선을 넘으면 두 번
	var s: RefCounted = _make_ship()
	s.take_damage(36)  # 200 -> 164 = 82%
	t.eq(s.newly_crossed_thresholds().size(), 0, "82퍼센트는 아직 아무 선도 안 넘었다")

	s.take_damage(78)  # 164 -> 86 = 43%
	t.eq(s.newly_crossed_thresholds().size(), 2, "82에서 43으로 떨어지면 75선과 50선을 함께 넘는다")

	s.repair(200)
	t.eq(s.newly_crossed_thresholds().size(), 0, "수리해도 통과한 선은 재활성화되지 않는다")
	s.take_damage(120)  # 200 -> 80 = 40%
	t.eq(s.newly_crossed_thresholds().size(), 0, "재하강해도 이미 통과한 선은 작동하지 않는다")

	s.take_damage(40)   # 80 -> 40 = 20%
	t.eq(s.newly_crossed_thresholds().size(), 1, "25선은 처음이므로 작동한다")

func _test_material(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	s.gain_material(10)
	t.eq(s.material, 10, "자재 획득")
	t.check(s.can_afford({"material": 6}), "6은 지불 가능")
	t.check(not s.can_afford({"material": 11}), "11은 지불 불가")
	t.eq(s.spend_material(4), 4, "실제 지출액을 돌려준다")
	t.eq(s.material, 6, "자재 차감")
	t.check(s.can_afford({}), "비용이 없으면 항상 지불 가능")

	# 잔액을 넘겨 지출하면 있는 만큼만 나가고 음수가 되지 않는다.
	# 상한이 없으면 자재가 음수가 되고, can_afford가 계속 거짓이 되어
	# 비용 있는 파츠가 전투 내내 불발한다.
	t.eq(s.spend_material(100), 6, "잔액 6에서 100을 요구하면 6만 지출된다")
	t.eq(s.material, 0, "자재는 음수가 되지 않는다")
	t.eq(s.spend_material(5), 0, "빈 상태에서 지출하면 0")
	t.eq(s.material, 0, "여전히 0")

func _test_resonance(t: RefCounted) -> void:
	# 스펙 §7.2 — 발동 누적 8회마다 +1, 감소하지 않는다
	var s: RefCounted = _make_ship()
	for i: int in 7:
		t.eq(s.register_fire_for_resonance(), 0, "7회까지는 공명이 오르지 않는다")
	t.eq(s.register_fire_for_resonance(), 1, "8회째에 공명 +1")
	t.eq(s.resonance, 1, "공명 누적")
	for i: int in 8:
		s.register_fire_for_resonance()
	t.eq(s.resonance, 2, "16회째에 공명 2")

	s.gain_resonance(3)
	t.eq(s.resonance, 5, "직접 생성도 누적된다")

func _test_regen_overheat(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	s.take_damage(100)

	# 재생 2를 5초. 1초마다 2씩 5회 = 10
	s.add_regen(2, K.secs_to_ticks(5.0))
	var healed: int = 0
	for tick: int in range(1, 121):
		healed += int(s.advance_effects(tick)["regen"])
	t.eq(healed, 10, "재생 2(5초)는 총 10 회복한다")

	# 과열 3 = 3 + 2 + 1 = 6 피해, 3초에 걸쳐
	var q: RefCounted = _make_ship()
	q.add_overheat(3)
	var burned: int = 0
	for tick: int in range(1, 121):
		burned += int(q.advance_effects(tick)["overheat"])
	t.eq(burned, 6, "과열 3은 3+2+1 = 6 피해")
	t.eq(q.hull, 194, "선체 감소")
	t.eq(q.overheat_stacks, 0, "과열 소진")

	# 틱 0에서는 아무것도 적용되지 않는다 — 전투 시작 즉시 재생·과열이 터지면 안 된다
	var zero: RefCounted = _make_ship()
	zero.take_damage(50)
	zero.add_regen(5, K.secs_to_ticks(5.0))
	zero.add_overheat(3)
	var at_zero: Dictionary = zero.advance_effects(0)
	t.eq(int(at_zero["regen"]), 0, "틱 0에서는 재생이 적용되지 않는다")
	t.eq(int(at_zero["overheat"]), 0, "틱 0에서는 과열이 적용되지 않는다")
	t.eq(zero.overheat_stacks, 3, "틱 0에서는 과열 스택도 줄지 않는다")

	# 지속시간 0인 재생은 아무것도 회복하지 않는다 (적용 가드가 막는 유일한 경로다 —
	# 순서를 고친 뒤로는 목록에 남은 항목이 항상 ticks_left > 0 또는 PERMANENT다)
	var instant: RefCounted = _make_ship()
	instant.take_damage(50)
	instant.add_regen(5, 0)
	t.eq(int(instant.advance_effects(K.PERIOD_TICKS)["regen"]), 0, "지속시간 0 재생은 회복하지 않는다")

	# 영구 재생은 만료되지 않는다
	var forever: RefCounted = _make_ship()
	forever.take_damage(100)
	forever.add_regen(1, K.PERMANENT)
	var forever_healed: int = 0
	for tick: int in range(1, 201):
		forever_healed += int(forever.advance_effects(tick)["regen"])
	t.eq(forever_healed, 10, "영구 재생은 10초 동안 10회 적용된다")
	t.eq(forever.regen_entries.size(), 1, "영구 재생 항목은 제거되지 않는다")

func _test_part_lookup(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	var core: RefCounted = _add_part(s, "core", "core")
	var gun: RefCounted = _add_part(s, "weapon_1", "weapon")
	var util: RefCounted = _add_part(s, "utility_1", "utility")

	t.eq(s.get_part("weapon_1"), gun, "슬롯 id로 조회")
	t.eq(s.get_part("nope"), null, "없는 슬롯은 null")
	t.eq(s.parts.size(), 3, "파츠 3개")

	# Core는 영구 파괴 불가를 기본 보유한다 (스펙 §8)
	t.check(core.is_indestructible(), "Core는 영구 파괴 불가")
	t.check(not gun.is_indestructible(), "일반 파츠는 아니다")

	t.eq(s.destructible_parts().size(), 2, "Core를 뺀 2개가 파괴선 후보")
	gun.broken = true
	t.eq(s.destructible_parts().size(), 1, "파손 파츠는 후보에서 빠진다")
	util.make_indestructible(K.secs_to_ticks(5.0))
	t.eq(s.destructible_parts().size(), 0, "파괴 불가 파츠도 후보에서 빠진다")

	t.eq(s.alive_parts().size(), 2, "살아있는 파츠 2개")
	t.eq(s.broken_parts().size(), 1, "파손 파츠 1개")

	# Core의 면제는 예외 분기가 아니라 키워드로 표현된다 —
	# Phase 0b의 조건 평가기가 source_keyword로 이걸 읽는다
	t.check(core.has_keyword("indestructible"), "Core는 indestructible 키워드를 갖는다")
	t.check(not gun.has_keyword("indestructible"), "일반 파츠는 갖지 않는다")
```

- [ ] **Step 2: 러너에 `"res://tests/unit/test_ship_state.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/ship_state.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 3: 구현한다**

`sim/ship_state.gd`:

```gdscript
extends RefCounted
## 함선 하나의 상태. 스펙 §7 §8.
## 세 개의 축을 갖는다 — 자재(유동성), 공명(패턴 안정도), 각 파츠의 발동 횟수(수명).

const K = preload("res://sim/sim_const.gd")

var side: String = "player"          # "player" / "enemy"
var frame_id: String = ""
var build_id: String = ""

var max_hull: int = 0
var hull: int = 0
var shield: int = 0
var material: int = 0
var resonance: int = 0

## 공명 기본 규칙(발동 8회마다 +1)용 누적 카운터
var fires_total: int = 0

var parts: Array = []                # Part, 슬롯 정의 순서. 이 순서가 발동 순서다.
var _slot_index: Dictionary = {}     # slot_id -> parts 인덱스
var links: Dictionary = {}           # slot_id -> Array[String]

var thresholds: Array = []           # 내림차순 [0.75, 0.50, 0.25]
var thresholds_crossed: Array = []

var regen_entries: Array = []        # [{amount:int, ticks_left:int}]
var overheat_stacks: int = 0

# --- Relic 수준 modifier (스펙 §9.4) ---
var relic_ids: Array[String] = []
var relic_triggers: Array = []
var relic_trigger_fires: Array[int] = []
## relic_triggers와 같은 길이. every_nth_accumulated 조건이 쓰는 트리거별 누적값.
## 파츠 트리거와 Relic 트리거의 능력이 이유 없이 달라지지 않게 한다.
var relic_trigger_accum: Array[int] = []
## prime_oscillator: resonance_at_least 요구치를 이만큼 낮춰 평가한다
var resonance_discount: int = 0
## convergence_engine: 0이면 없음. 그 외에는 재발동 최소 간격(틱)
var convergence_gap_ticks: int = 0
var last_fire_faction: String = ""
var last_convergence_tick: int = -99999

# --- 파츠 ---

func add_part(part: RefCounted) -> void:
	_slot_index[part.slot_id] = parts.size()
	parts.append(part)
	# 스펙 §8 — Core는 영구 파괴 불가를 기본 보유한다. 예외 분기가 아니라 키워드다.
	if part.role == "core":
		part.make_indestructible(K.PERMANENT)
		if not part.keywords.has("indestructible"):
			part.keywords.append("indestructible")

func get_part(slot_id: String) -> RefCounted:
	if not _slot_index.has(slot_id):
		return null
	return parts[_slot_index[slot_id]]

func alive_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if not p.broken:
			out.append(p)
	return out

func broken_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if p.broken:
			out.append(p)
	return out

func limited_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if not p.broken and p.is_limited():
			out.append(p)
	return out

## 파괴선이 고를 수 있는 후보 (스펙 §8)
func destructible_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if not p.broken and not p.is_indestructible():
			out.append(p)
	return out

# --- 피해와 회복 ---

func take_damage(amount: int) -> Dictionary:
	if amount <= 0:
		return {"absorbed": 0, "hull_damage": 0, "from": hull, "to": hull}
	var absorbed: int = mini(shield, amount)
	shield -= absorbed
	var before: int = hull
	hull = maxi(0, hull - (amount - absorbed))
	return {"absorbed": absorbed, "hull_damage": before - hull, "from": before, "to": hull}

## 과열 전용 — GDD §21은 과열을 "선체 피해"로 정의한다. 보호막을 무시한다.
func damage_hull_direct(amount: int) -> int:
	var before: int = hull
	hull = maxi(0, hull - maxi(0, amount))
	return before - hull

func repair(amount: int) -> int:
	var before: int = hull
	hull = mini(max_hull, hull + maxi(0, amount))
	return hull - before

func add_shield(amount: int) -> void:
	shield += maxi(0, amount)

func hull_ratio() -> float:
	if max_hull <= 0:
		return 0.0
	return float(hull) / float(max_hull)

## 이번에 처음 통과한 파괴선 목록. 호출하면 통과 표시가 남는다 (한 번만 작동).
func newly_crossed_thresholds() -> Array:
	var crossed: Array = []
	var ratio: float = hull_ratio()
	for i: int in thresholds.size():
		if not thresholds_crossed[i] and ratio < float(thresholds[i]):
			thresholds_crossed[i] = true
			crossed.append(thresholds[i])
	return crossed

# --- 자원 ---

func gain_material(amount: int) -> int:
	var actual: int = maxi(0, amount)
	material += actual
	return actual

func spend_material(amount: int) -> int:
	var actual: int = mini(maxi(0, amount), material)
	material -= actual
	return actual

func can_afford(cost: Dictionary) -> bool:
	return material >= int(cost.get("material", 0))

func gain_resonance(amount: int) -> int:
	var actual: int = maxi(0, amount)
	resonance += actual
	return actual

## 파츠 하나가 발동했음을 알린다. 공명이 올랐으면 오른 양을 돌려준다.
## 스펙 §7.2 — 기본 획득은 "행동 누적 → 공명"이다.
func register_fire_for_resonance() -> int:
	fires_total += 1
	if fires_total % K.RESONANCE_PER_FIRES == 0:
		resonance += 1
		return 1
	return 0

# --- 지속 효과 ---

func add_regen(amount: int, ticks: int) -> void:
	if amount <= 0:
		return
	regen_entries.append({"amount": amount, "ticks_left": ticks})

func add_overheat(stacks: int) -> void:
	overheat_stacks += maxi(0, stacks)

## 한 틱 진행. PERIOD_TICKS(1초)마다 재생과 과열이 적용된다.
## 반환: {"regen": 회복량, "overheat": 과열 피해량}
##
## 순서가 중요하다: 적용 → 감소 → 필터.
## 감소를 먼저 하면 5초짜리 재생의 마지막 회차가 누락된다 —
## 틱 100에서 ticks_left가 이미 0이 되어 적용 가드를 통과하지 못하기 때문이다.
## (초안이 이 순서로 되어 있어 총 10 대신 8만 회복했다.)
func advance_effects(tick: int) -> Dictionary:
	var result: Dictionary = {"regen": 0, "overheat": 0}

	if tick > 0 and tick % K.PERIOD_TICKS == 0:
		var total: int = 0
		for entry: Dictionary in regen_entries:
			var left: int = int(entry["ticks_left"])
			if left > 0 or left == K.PERMANENT:
				total += int(entry["amount"])
		if total > 0:
			result["regen"] = repair(total)
		if overheat_stacks > 0:
			result["overheat"] = damage_hull_direct(overheat_stacks)
			overheat_stacks -= 1

	for entry: Dictionary in regen_entries:
		var left: int = int(entry["ticks_left"])
		if left > 0:
			entry["ticks_left"] = left - 1

	var kept: Array = []
	for entry: Dictionary in regen_entries:
		if int(entry["ticks_left"]) != 0:
			kept.append(entry)
	regen_entries = kept

	return result
```

- [ ] **Step 4: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 5: 커밋**

```bash
git add sim/ship_state.gd tests/ && git commit -m "feat(sim): ship state — resources, damage, regen/overheat, thresholds

파괴선은 처음 통과할 때만 작동하고 한 방에 두 선을 넘으면 두 번 작동한다.
Core는 add_part 시점에 영구 indestructible을 받는다 — 예외 분기가 아니라 키워드다.
과열은 GDD 21절의 '선체 피해' 정의에 따라 보호막을 무시한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: 빌드 로더 — 검증 8종과 함선 조립

**Files:**
- Create: `sim/data/test_builds/fx_basic.json`
- Create: `sim/build_loader.gd`
- Create: `tests/unit/test_build_loader.gd`
- Modify: `tests/run_unit.gd`

- [ ] **Step 1: 테스트 빌드를 쓴다**

`sim/data/test_builds/fx_basic.json`:

```json
{
  "id": "fx_basic",
  "frame": "standard_frame",
  "relic": null,
  "slots": {
    "core":      { "part": "fx_core" },
    "weapon_1":  { "part": "fx_gun", "augment": "fx_turbine" },
    "weapon_2":  { "part": "fx_gun" },
    "defense_1": { "part": "fx_medic" },
    "utility_1": { "part": "fx_turbine" },
    "utility_2": { "part": "fx_turbine" },
    "flex_1":    { "part": "fx_turbine" }
  },
  "links": [ ["utility_1", "weapon_1"] ]
}
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`tests/unit/test_build_loader.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")
const BuildLoader = preload("res://sim/build_loader.gd")

func _catalog() -> RefCounted:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/fixtures.json")
	c.load_frame("res://sim/data/frames/standard_frame.json")
	return c

func _base_build() -> Dictionary:
	return {
		"id": "t",
		"frame": "standard_frame",
		"relic": null,
		"slots": {
			"core":      { "part": "fx_core" },
			"weapon_1":  { "part": "fx_gun", "augment": "fx_turbine" },
			"weapon_2":  { "part": "fx_gun" },
			"defense_1": { "part": "fx_medic" },
			"utility_1": { "part": "fx_turbine" },
			"utility_2": { "part": "fx_turbine" },
			"flex_1":    { "part": "fx_turbine" }
		},
		"links": []
	}

## 빌드를 한 군데만 망가뜨려 검증이 잡아내는지 본다.
## 거부되기만 하면 통과시키면 안 된다 — 다른 버그 때문에 거부돼도 통과하기 때문이다.
## 그래서 기대 문구까지 대조한다.
func _expect_error(t: RefCounted, mutate: Callable, label: String, expect_text: String) -> void:
	var b: Dictionary = _base_build()
	mutate.call(b)
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(b, _catalog(), "player")
	t.check(ship == null, "%s — 조립이 거부되어야 한다" % label)
	var joined: String = "\n".join(loader.errors)
	t.check(joined.contains(expect_text),
		"%s — 에러에 \"%s\"가 있어야 한다. 실제: %s" % [label, expect_text, joined])

func run(t: RefCounted) -> void:
	_test_happy_path(t)
	_test_validation(t)
	_test_missing_augment_block(t)
	_test_relic_modifiers(t)
	_test_file_load(t)
	t.done()

func _test_happy_path(t: RefCounted) -> void:
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(_base_build(), _catalog(), "player")
	t.check(ship != null, "정상 빌드는 조립된다: %s" % str(loader.errors))
	if ship == null:
		return

	t.eq(ship.side, "player", "진영")
	t.eq(ship.max_hull, 200, "Frame의 hull이 최대 HP")
	t.eq(ship.hull, 200, "가득 찬 상태로 시작")
	t.eq(ship.parts.size(), 7, "슬롯 7칸 전부 채워짐")
	t.eq(ship.thresholds.size(), 3, "파괴선 3개")
	t.eq(ship.thresholds_crossed, [false, false, false], "아직 통과한 선 없음")

	# 파츠 순서는 Frame의 슬롯 정의 순서다 — 발동 순서가 결정론적이어야 하므로
	t.eq(ship.parts[0].slot_id, "core", "첫 파츠는 core")
	t.eq(ship.parts[1].slot_id, "weapon_1", "둘째는 weapon_1")

	# AUGMENT가 적용된 슬롯
	var w1: RefCounted = ship.get_part("weapon_1")
	t.eq(w1.augment_id, "fx_turbine", "weapon_1에 augment 장착")
	t.eq(w1.triggers.size(), 1, "augment 트리거가 붙었다")
	t.eq(w1.trigger_fires.size(), 1, "트리거별 발동 카운터가 함께 만들어진다")
	t.eq(w1.cooldown_units, K.cooldown_to_units(1.0), "cooldown_mult 0.5 반영")

	# 같은 파츠 id를 여러 슬롯에 써도 서로 독립이다 (스펙 §5.3)
	var w2: RefCounted = ship.get_part("weapon_2")
	t.eq(w2.augment_id, "", "weapon_2는 augment 없음")
	t.eq(w2.triggers.size(), 0, "같은 fx_gun이지만 트리거가 붙지 않았다")
	t.eq(w2.cooldown_units, K.cooldown_to_units(2.0), "weapon_2는 원래 쿨타임")

	# fire_limit이 런타임에 반영된다
	var u1: RefCounted = ship.get_part("utility_1")
	t.eq(u1.fire_limit, 6, "fx_turbine의 fire_limit")
	t.eq(u1.fires_remaining, 6, "남은 횟수 초기값")

	# 무제한 파츠
	t.eq(w2.fires_remaining, K.UNLIMITED, "fire_limit 없는 파츠는 무제한")

	# links는 양방향 인접 목록이 된다
	var loader2: RefCounted = BuildLoader.new()
	var b: Dictionary = _base_build()
	b["links"] = [["utility_1", "weapon_1"]]
	var ship2: RefCounted = loader2.assemble(b, _catalog(), "player")
	t.eq(ship2.links["utility_1"], ["weapon_1"], "정방향 연결")
	t.eq(ship2.links["weapon_1"], ["utility_1"], "연결은 방향이 없다")

	# role이 슬롯 정의에서 제대로 전달되는지. 이게 틀리면 ship.add_part()가
	# Core에 영구 파괴 불가를 부여하지 못해 Core가 전투 중 파괴선에 죽는다.
	var core: RefCounted = ship.get_part("core")
	t.eq(core.role, "core", "Core 슬롯의 파츠는 core 역할을 갖는다")
	t.check(core.is_indestructible(), "조립된 Core는 영구 파괴 불가다")
	t.check(core.has_keyword("indestructible"), "Core는 indestructible 키워드를 갖는다")
	t.eq(w1.role, "weapon", "weapon 슬롯의 파츠는 weapon 역할을 갖는다")
	t.check(not w1.is_indestructible(), "일반 파츠는 파괴 불가가 아니다")

	# cost가 전달되는지. 이게 비면 자재 게이팅이 통째로 사라진다.
	var d1: RefCounted = ship.get_part("defense_1")
	t.eq(int(d1.cost.get("material", 0)), 3, "fx_medic의 자재 비용 3이 전달된다")
	t.eq(int(w1.cost.get("material", 0)), 0, "비용 없는 파츠는 0")

	# 키워드도 전달된다
	t.check(w1.has_keyword("damage"), "숙주 키워드가 전달된다")
	t.check(w1.has_keyword("accelerate"), "AUGMENT 키워드도 전달된다")

func _test_validation(t: RefCounted) -> void:
	# 스펙 §5.3의 검증 9종.
	# 람다 본문은 반드시 한 줄이어야 한다 — 여러 줄로 쓰면 GDScript가 문장과
	# 뒤따르는 인자를 한 표현식으로 읽어 파싱에 실패한다.
	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"]["weapon_1"] = {"part": "fx_medic"},
		"역할 불일치 (defense 파츠를 weapon 슬롯에)", "역할 불일치")

	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"]["weapon_1"] = {"part": "nonexistent"},
		"존재하지 않는 파츠 id", "존재하지 않는 파츠")

	_expect_error(t,
		func(b: Dictionary) -> void: b["frame"] = "nonexistent_frame",
		"존재하지 않는 Frame id", "존재하지 않는 Frame")

	_expect_error(t,
		func(b: Dictionary) -> void: b["relic"] = "nonexistent_relic",
		"존재하지 않는 Relic id", "존재하지 않는 Relic")

	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"].erase("core"),
		"Core 슬롯이 비어 있음", "Core 슬롯")

	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"]["weapon_1"] = {"part": "fx_gun", "augment": "fx_core"},
		"Core 파츠를 Augment로 사용", "Core 파츠")

	_expect_error(t,
		func(b: Dictionary) -> void: b["links"] = [["utility_1", "nonexistent_slot"]],
		"존재하지 않는 슬롯을 links에 지정", "links: 존재하지 않는 슬롯")

	_expect_error(t,
		func(b: Dictionary) -> void: b["relic"] = ["a", "b"],
		"Relic을 relic_slots보다 많이 지정", "relic_slots")

	# flexible 슬롯은 아무 역할이나 받는다
	var loader: RefCounted = BuildLoader.new()
	var b2: Dictionary = _base_build()
	b2["slots"]["flex_1"] = {"part": "fx_medic"}
	t.check(loader.assemble(b2, _catalog(), "player") != null,
		"flexible 슬롯은 아무 역할이나 받는다: %s" % str(loader.errors))

	# Core만 필수다. 나머지 슬롯은 비어 있어도 조립된다.
	var loader3: RefCounted = BuildLoader.new()
	var b3: Dictionary = _base_build()
	b3["slots"].erase("utility_2")
	b3["slots"].erase("flex_1")
	var sparse: RefCounted = loader3.assemble(b3, _catalog(), "player")
	t.check(sparse != null, "빈 슬롯이 있어도 조립된다: %s" % str(loader3.errors))
	t.eq(sparse.parts.size(), 5, "채운 슬롯 수만큼만 파츠가 생긴다")
	t.eq(sparse.get_part("utility_2"), null, "비운 슬롯은 조회되지 않는다")
	t.eq(sparse.parts[0].slot_id, "core", "빈 슬롯이 있어도 순서는 Frame 정의 순서다")

## "augment 블록이 없는 파츠를 Augment로" 케이스는 fx_core로는 시험할 수 없다 —
## fx_core는 Core 역할이기도 해서 앞선 검사에 먼저 걸리기 때문이다.
## Core가 아니면서 augment 블록도 없는 파츠를 인라인으로 주입해서 두 검사를 구분한다.
func _test_missing_augment_block(t: RefCounted) -> void:
	var c: RefCounted = _catalog()
	c.ingest_parts([
		{ "id": "fx_plain", "name": "블록 없는 픽스처", "faction": "reclaimer",
		  "roles": ["weapon"], "active": { "cooldown": 3.0 } }
	], "inline")

	var b: Dictionary = _base_build()
	b["slots"]["weapon_1"] = {"part": "fx_gun", "augment": "fx_plain"}
	var loader: RefCounted = BuildLoader.new()
	t.check(loader.assemble(b, c, "player") == null, "augment 블록이 없으면 거부된다")
	var joined: String = "\n".join(loader.errors)
	t.check(joined.contains("augment 블록이 없다"), "그 이유로 거부된다: %s" % joined)
	t.check(not joined.contains("Core 파츠"), "Core 검사가 아니라 블록 검사에 걸린 것이다")

func _test_relic_modifiers(t: RefCounted) -> void:
	# Relic은 파츠가 아니라 함선 수준 modifier다.
	# relic 픽스처 파일이 없으므로 인라인 주입으로 덮는다 — 이 경로는
	# 덮지 않으면 실제 Relic이 들어오는 Phase 0b까지 한 번도 실행되지 않는다.
	var c: RefCounted = _catalog()
	c.relics["fx_relay"] = {
		"id": "fx_relay",
		"name": "픽스처 중계기",
		"triggers": [
			{ "on": "resonance_gained",
			  "do": [ { "op": "accelerate", "target": "all_own_active", "duration": 2.0 } ] }
		],
		"modifiers": { "resonance_discount": 1, "convergence_gap_seconds": 2.0 }
	}

	var b: Dictionary = _base_build()
	b["relic"] = "fx_relay"
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(b, c, "player")
	t.check(ship != null, "Relic이 있는 빌드가 조립된다: %s" % str(loader.errors))
	if ship == null:
		return

	t.eq(ship.relic_ids, ["fx_relay"], "Relic id가 기록된다")
	t.eq(ship.relic_triggers.size(), 1, "Relic 트리거가 함선에 붙는다")
	t.eq(ship.relic_trigger_fires.size(), 1, "트리거별 발동 카운터가 함께 만들어진다")
	t.eq(ship.relic_trigger_fires[0], 0, "카운터는 0에서 시작한다")
	t.eq(ship.resonance_discount, 1, "resonance_discount가 적용된다")
	t.eq(ship.convergence_gap_ticks, K.secs_to_ticks(2.0), "convergence_gap이 틱으로 변환된다")

	var plain: RefCounted = BuildLoader.new().assemble(_base_build(), c, "player")
	t.eq(plain.resonance_discount, 0, "Relic이 없으면 할인도 없다")
	t.eq(plain.convergence_gap_ticks, 0, "Relic이 없으면 간격도 없다")
	t.eq(plain.relic_triggers.size(), 0, "Relic이 없으면 트리거도 없다")

	# 정확히 relic_slots 개수(1)는 허용된다 — 초과 검사의 경계
	var exact: RefCounted = BuildLoader.new()
	var b2: Dictionary = _base_build()
	b2["relic"] = ["fx_relay"]
	t.check(exact.assemble(b2, c, "player") != null,
		"relic_slots와 같은 개수는 허용된다: %s" % str(exact.errors))

func _test_file_load(t: RefCounted) -> void:
	var loader: RefCounted = BuildLoader.new()
	var b: Dictionary = loader.load_build("res://sim/data/test_builds/fx_basic.json")
	t.eq(b.get("id", ""), "fx_basic", "빌드 파일 로드")
	t.check(loader.errors.is_empty(), "정상 파일은 에러 없음")

	var loader2: RefCounted = BuildLoader.new()
	loader2.load_build("res://sim/data/test_builds/nope.json")
	t.check(not loader2.errors.is_empty(), "없는 빌드 파일은 에러")
```

`fx_gun2`는 존재하지 않는 파츠이므로 "존재하지 않는 파츠 id" 경로로도 걸린다. 두 케이스가 같은 코드 경로를 타지 않도록, 구현에서 augment 존재 검사와 `augment` 블록 보유 검사를 **분리된 메시지**로 남긴다.

- [ ] **Step 3: 러너에 `"res://tests/unit/test_build_loader.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/build_loader.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 4: 구현한다**

`sim/build_loader.gd`:

```gdscript
extends RefCounted
## 빌드 JSON을 검증하고 ShipState로 조립한다. 스펙 §5.3.
## 잘못된 빌드는 조용히 넘어가지 않는다 — null을 돌려주고 errors에 이유를 남긴다.

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")

var errors: Array[String] = []

func load_build(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("빌드 파일 없음: %s" % path)
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		errors.append("빌드 JSON 파싱 실패: %s" % path)
		return {}
	return parsed

## 빌드를 검증하고 ShipState를 만든다. 실패하면 null.
func assemble(build: Dictionary, catalog: RefCounted, side: String) -> RefCounted:
	var frame_id: String = str(build.get("frame", ""))
	if not catalog.frames.has(frame_id):
		errors.append("존재하지 않는 Frame id: %s" % frame_id)
		return null
	var frame: Dictionary = catalog.frames[frame_id]

	var slots: Dictionary = build.get("slots", {})
	var slot_defs: Array = frame["slots"]

	# --- Core 슬롯 검사 ---
	var has_core: bool = false
	for slot_def: Dictionary in slot_defs:
		if str(slot_def["role"]) == "core" and slots.has(slot_def["id"]):
			has_core = true
	if not has_core:
		errors.append("Core 슬롯이 비어 있다")
		return null

	# --- Relic 검사 ---
	var relic_ids: Array[String] = []
	var relic_field: Variant = build.get("relic", null)
	if relic_field != null:
		if relic_field is Array:
			for r: Variant in relic_field:
				relic_ids.append(str(r))
		else:
			relic_ids.append(str(relic_field))
	var relic_slots: int = int(frame.get("relic_slots", 0))
	if relic_ids.size() > relic_slots:
		errors.append("Relic이 relic_slots(%d)보다 많다: %d개" % [relic_slots, relic_ids.size()])
		return null
	for rid: String in relic_ids:
		if not catalog.relics.has(rid):
			errors.append("존재하지 않는 Relic id: %s" % rid)
			return null

	# --- 슬롯별 파츠 검증 ---
	var ship: RefCounted = Ship.new()
	ship.side = side
	ship.frame_id = frame_id
	ship.build_id = str(build.get("id", ""))
	ship.max_hull = int(frame["hull"])
	ship.hull = ship.max_hull
	ship.thresholds = (frame["thresholds"] as Array).duplicate()
	ship.thresholds_crossed = []
	for i: int in ship.thresholds.size():
		ship.thresholds_crossed.append(false)

	var valid_slot_ids: Array[String] = []
	for slot_def: Dictionary in slot_defs:
		valid_slot_ids.append(str(slot_def["id"]))

	for slot_def: Dictionary in slot_defs:
		var slot_id: String = str(slot_def["id"])
		var role: String = str(slot_def["role"])
		if not slots.has(slot_id):
			continue  # 빈 슬롯은 허용 (Core만 필수)
		var entry: Dictionary = slots[slot_id]
		var part_id: String = str(entry.get("part", ""))
		var augment_id: String = str(entry.get("augment", ""))

		if not catalog.parts.has(part_id):
			errors.append("%s: 존재하지 않는 파츠 id \"%s\"" % [slot_id, part_id])
			return null

		var roles: Array = catalog.parts[part_id]["roles"]
		if role != "flexible" and not roles.has(role):
			errors.append("%s: 역할 불일치 — \"%s\"는 %s 슬롯에 들어갈 수 없다"
				% [slot_id, part_id, role])
			return null

		if augment_id != "":
			if not catalog.parts.has(augment_id):
				errors.append("%s: 존재하지 않는 augment 파츠 id \"%s\"" % [slot_id, augment_id])
				return null
			var aug_def: Dictionary = catalog.parts[augment_id]
			if (aug_def["roles"] as Array).has("core"):
				errors.append("%s: Core 파츠 \"%s\"는 Augment로 쓸 수 없다" % [slot_id, augment_id])
				return null
			if not aug_def.has("augment"):
				errors.append("%s: \"%s\"에는 augment 블록이 없다" % [slot_id, augment_id])
				return null

		ship.add_part(_make_part(catalog, slot_id, role, part_id, augment_id))

	# --- links 검증 (양방향) ---
	for pair: Variant in build.get("links", []):
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		for slot_id: String in [a, b]:
			if not valid_slot_ids.has(slot_id):
				errors.append("links: 존재하지 않는 슬롯 \"%s\"" % slot_id)
				return null
		_link(ship, a, b)
		_link(ship, b, a)

	# --- Relic 적용 (스펙 §9.4 — 파츠가 아니라 함선 수준 modifier) ---
	for rid: String in relic_ids:
		var relic: Dictionary = catalog.relics[rid]
		ship.relic_ids.append(rid)
		for tr: Variant in relic.get("triggers", []):
			ship.relic_triggers.append((tr as Dictionary).duplicate(true))
			ship.relic_trigger_fires.append(0)
			ship.relic_trigger_accum.append(0)
		var mods: Dictionary = relic.get("modifiers", {})
		ship.resonance_discount += int(mods.get("resonance_discount", 0))
		if mods.has("convergence_gap_seconds"):
			ship.convergence_gap_ticks = K.secs_to_ticks(float(mods["convergence_gap_seconds"]))

	return ship

func _link(ship: RefCounted, from_slot: String, to_slot: String) -> void:
	if not ship.links.has(from_slot):
		ship.links[from_slot] = []
	if not ship.links[from_slot].has(to_slot):
		ship.links[from_slot].append(to_slot)

func _make_part(catalog: RefCounted, slot_id: String, role: String,
		part_id: String, augment_id: String) -> RefCounted:
	var spec: Dictionary = catalog.merge(part_id, augment_id)
	var p: RefCounted = Part.new()
	p.slot_id = slot_id
	p.role = role
	p.part_id = spec["part_id"]
	p.part_name = spec["part_name"]
	p.faction = spec["faction"]
	p.keywords = spec["keywords"]
	p.augment_id = spec["augment_id"]
	p.cooldown_units = spec["cooldown_units"]
	p.cost = spec["cost"]
	p.on_fire = spec["on_fire"]
	p.triggers = spec["triggers"]
	p.fire_limit = spec["fire_limit"]
	p.fires_remaining = spec["fire_limit"]
	for i: int in p.triggers.size():
		p.trigger_fires.append(0)
		p.trigger_accum.append(0)
	return p
```

- [ ] **Step 5: `sim/part.gd`에 트리거 누적 필드를 추가한다**

`trigger_fires` 선언 바로 아래에 추가:

```gdscript
## triggers와 같은 길이. every_nth_accumulated 조건이 쓰는 트리거별 누적값.
var trigger_accum: Array[int] = []
```

- [ ] **Step 6: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 7: 커밋**

```bash
git add sim/build_loader.gd sim/part.gd sim/data/ tests/ && git commit -m "feat(sim): build validation and ship assembly

스펙 5.3절의 검증 8종. 잘못된 빌드는 null + errors로 거부하고 조용히 넘어가지 않는다.
파츠 순서는 Frame의 슬롯 정의 순서 — 발동 순서가 결정론적이어야 하기 때문이다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: 대상 셀렉터

**Files:**
- Create: `sim/targeting.gd`
- Create: `tests/unit/test_targeting.gd`
- Modify: `tests/run_unit.gd`

스펙 §6.4의 계약을 구현한다. 핵심 규칙: **셀렉터는 `do` 블록 시작 시점에 한 번만 해석하고 결과를 블록 전체가 공유한다.** 그 규칙 자체는 Task 10(actions)에서 강제하고, 여기서는 해석기만 만든다.

`targeting.gd`는 `ship_state.gd`를 `preload`하지 않는다 — 함선 객체를 인자로 받아 덕타이핑으로 쓴다. `preload` 순환을 막고, 가짜 함선으로 단독 테스트할 수 있게 하기 위함이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/unit/test_targeting.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Targeting = preload("res://sim/targeting.gd")

func _ship() -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = 200
	s.hull = 200
	for spec: Array in [["core", "core"], ["weapon_1", "weapon"], ["weapon_2", "weapon"],
			["utility_1", "utility"]]:
		var p: RefCounted = Part.new()
		p.slot_id = spec[0]
		p.role = spec[1]
		p.part_id = "fx_" + spec[0]
		p.cooldown_units = K.cooldown_to_units(2.0)
		s.add_part(p)
	return s

func _ctx(s: RefCounted, owner: RefCounted, rng: RandomNumberGenerator) -> Dictionary:
	return {"own_ship": s, "enemy_ship": null, "part": owner, "rng": rng}

func _slots(parts: Array) -> Array[String]:
	var out: Array[String] = []
	for p: RefCounted in parts:
		out.append(p.slot_id)
	return out

func run(t: RefCounted) -> void:
	_test_basic(t)
	_test_slowest(t)
	_test_linked(t)
	_test_broken_and_limited(t)
	_test_determinism(t)
	_test_unknown(t)
	t.done()

func _test_basic(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var owner: RefCounted = s.get_part("weapon_1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, owner, rng)

	t.eq(_slots(Targeting.resolve("self", ctx)), ["weapon_1"], "self는 트리거 소유 파츠")
	t.eq(_slots(Targeting.resolve("host", ctx)), ["weapon_1"], "host는 self와 같다 (병합된 문맥)")
	t.eq(Targeting.resolve("all_own_active", ctx).size(), 4, "살아있는 아군 파츠 전부")

	# 파손 파츠는 all_own_active에서 빠진다
	s.get_part("weapon_2").broken = true
	t.eq(Targeting.resolve("all_own_active", ctx).size(), 3, "파손 파츠 제외")

func _test_slowest(t: RefCounted) -> void:
	# slowest_own = 남은 쿨타임(cooldown_units - progress_units)이 가장 큰 파츠
	var s: RefCounted = _ship()
	s.get_part("core").progress_units = 70
	s.get_part("weapon_1").progress_units = 10
	s.get_part("weapon_2").progress_units = 50
	s.get_part("utility_1").progress_units = 30
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, s.get_part("weapon_1"), rng)
	t.eq(_slots(Targeting.resolve("slowest_own", ctx)), ["weapon_1"],
		"진행도가 가장 적은 파츠가 가장 느리다")

	# 동점이면 슬롯 순서가 이긴다 — 결정론을 위해
	var s2: RefCounted = _ship()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1
	t.eq(_slots(Targeting.resolve("slowest_own", _ctx(s2, s2.get_part("core"), rng2))), ["core"],
		"전부 동점이면 첫 슬롯")

	# 모든 파츠가 발동 준비된 상태(잔여 쿨타임 전부 0)에서도 대상을 고른다.
	# best_remaining 초기값이 0이면 여기서 빈 배열이 나오고,
	# slowest_own을 쓰는 파츠가 전투 내내 아무것도 하지 못한다.
	var ready: RefCounted = _ship()
	for p: RefCounted in ready.parts:
		p.progress_units = p.cooldown_units
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 1
	var picked: Array = Targeting.resolve("slowest_own", _ctx(ready, ready.get_part("core"), rng3))
	t.eq(picked.size(), 1, "전부 준비된 상태에서도 대상을 고른다")
	t.eq(_slots(picked), ["core"], "전부 동점이면 첫 슬롯")

	# 진행도가 쿨타임을 넘긴 상태에서도 고른다 — 잔여가 음수다
	var over: RefCounted = _ship()
	for p: RefCounted in over.parts:
		p.progress_units = p.cooldown_units + 10
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 1
	t.eq(_slots(Targeting.resolve("slowest_own", _ctx(over, over.get_part("core"), rng4))), ["core"],
		"잔여 쿨타임이 음수여도 대상을 고른다")

	# 가장 느린 파츠가 파손이면 그다음으로 느린 살아있는 파츠를 고른다
	var with_broken: RefCounted = _ship()
	with_broken.get_part("core").progress_units = 70
	with_broken.get_part("weapon_1").progress_units = 10
	with_broken.get_part("weapon_2").progress_units = 50
	with_broken.get_part("utility_1").progress_units = 30
	with_broken.get_part("weapon_1").broken = true
	var rng5 := RandomNumberGenerator.new()
	rng5.seed = 1
	t.eq(_slots(Targeting.resolve("slowest_own", _ctx(with_broken, with_broken.get_part("core"), rng5))),
		["utility_1"], "가장 느린 파츠가 파손이면 그다음으로 느린 살아있는 파츠")

func _test_linked(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	s.links["weapon_1"] = ["utility_1", "weapon_2"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, s.get_part("weapon_1"), rng)
	t.eq(_slots(Targeting.resolve("linked", ctx)), ["utility_1", "weapon_2"], "연결된 파츠 전부")

	var ctx2: Dictionary = _ctx(s, s.get_part("core"), rng)
	t.eq(Targeting.resolve("linked", ctx2).size(), 0, "연결이 없으면 빈 배열")

func _test_broken_and_limited(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, s.get_part("core"), rng)

	t.eq(Targeting.resolve("random_broken_own", ctx).size(), 0, "파손 파츠가 없으면 빈 배열")
	s.get_part("weapon_2").broken = true
	t.eq(_slots(Targeting.resolve("random_broken_own", ctx)), ["weapon_2"], "유일한 파손 파츠")

	t.eq(Targeting.resolve("all_own_limited", ctx).size(), 0, "제한 걸린 파츠가 없다")
	s.get_part("utility_1").fire_limit = 4
	s.get_part("utility_1").fires_remaining = 4
	t.eq(_slots(Targeting.resolve("all_own_limited", ctx)), ["utility_1"], "제한 걸린 파츠 1개")
	t.eq(_slots(Targeting.resolve("random_own_limited", ctx)), ["utility_1"], "무작위 제한 파츠")

func _test_determinism(t: RefCounted) -> void:
	# 스펙 §4.3 — 무작위 셀렉터는 주입된 시드 RNG만 쓴다
	var picks: Array[String] = []
	for run_index: int in 2:
		var s: RefCounted = _ship()
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var ctx: Dictionary = _ctx(s, s.get_part("core"), rng)
		var seq: String = ""
		for i: int in 20:
			seq += Targeting.resolve("random_own_active", ctx)[0].slot_id + ","
		picks.append(seq)
	t.eq(picks[0], picks[1], "같은 시드는 같은 무작위 대상 순열을 낸다")

func _test_unknown(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	t.eq(Targeting.resolve("no_such_selector", _ctx(s, s.get_part("core"), rng)).size(), 0,
		"알 수 없는 셀렉터는 빈 배열")
	t.check(not Targeting.SELECTORS.has("no_such_selector"), "셀렉터 목록에도 없다")
	t.check(Targeting.SELECTORS.has("slowest_own"), "알려진 셀렉터는 목록에 있다")
```

- [ ] **Step 2: 러너에 `"res://tests/unit/test_targeting.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/targeting.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 3: 구현한다**

`sim/targeting.gd`:

```gdscript
extends RefCounted
## 대상 셀렉터 해석. 스펙 §6.4.
##
## ship_state.gd를 preload하지 않는다 — 함선 객체를 인자로 받아 덕타이핑으로 쓴다.
## preload 순환을 막고, 가짜 함선으로 단독 테스트할 수 있게 하기 위함이다.
##
## 함선 자체를 겨냥하는 op(deal_damage / gain_shield / repair 등)는 target을 쓰지 않고
## 암묵적으로 적함 또는 자함에 적용된다. 여기서 해석하는 것은 파츠 셀렉터뿐이다.

const SELECTORS: Array[String] = [
	"self", "host", "linked",
	"random_own_active", "slowest_own", "random_broken_own",
	"all_own_active", "all_own_limited", "random_own_limited",
]

## ctx: {own_ship, enemy_ship, part, rng}
## 항상 파츠 배열을 돌려준다. 대상이 없으면 빈 배열.
static func resolve(selector: String, ctx: Dictionary) -> Array:
	var ship: RefCounted = ctx["own_ship"]
	var owner: RefCounted = ctx["part"]

	match selector:
		"self", "host":
			# 병합된 문맥에서 host와 self는 같다 — AUGMENT 트리거는 숙주 파츠가 소유한다
			return [owner] if owner != null else []
		"linked":
			return _linked(ship, owner)
		"all_own_active":
			return ship.alive_parts()
		"all_own_limited":
			return ship.limited_parts()
		"random_own_active":
			return _pick_one(ship.alive_parts(), ctx["rng"])
		"random_own_limited":
			return _pick_one(ship.limited_parts(), ctx["rng"])
		"random_broken_own":
			return _pick_one(ship.broken_parts(), ctx["rng"])
		"slowest_own":
			return _slowest(ship)
	return []

static func _linked(ship: RefCounted, owner: RefCounted) -> Array:
	if owner == null or not ship.links.has(owner.slot_id):
		return []
	var out: Array = []
	for slot_id: String in ship.links[owner.slot_id]:
		var p: RefCounted = ship.get_part(slot_id)
		if p != null and not p.broken:
			out.append(p)
	return out

static func _pick_one(pool: Array, rng: RandomNumberGenerator) -> Array:
	if pool.is_empty():
		return []
	return [pool[rng.randi_range(0, pool.size() - 1)]]

## 남은 쿨타임이 가장 큰 파츠. 동점이면 슬롯 순서가 이긴다 (결정론).
## 첫 후보를 무조건 채택한 뒤 비교한다 — 고정 센티넬(-1 등)을 쓰면 잔여 쿨타임이
## 그 센티넬보다 작은 상태에서 어떤 파츠도 선택되지 못한다. 진행도가 쿨타임을
## 넘겨 잔여가 음수인 상태는 흔하다(체인 강제 발동, 가속 초과분 이월).
static func _slowest(ship: RefCounted) -> Array:
	var candidates: Array = ship.alive_parts()
	if candidates.is_empty():
		return []
	var best: RefCounted = candidates[0]
	var best_remaining: int = best.cooldown_units - best.progress_units
	for i: int in range(1, candidates.size()):
		var p: RefCounted = candidates[i]
		var remaining: int = p.cooldown_units - p.progress_units
		if remaining > best_remaining:
			best_remaining = remaining
			best = p
	return [best]
```

- [ ] **Step 4: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 5: 커밋**

```bash
git add sim/targeting.gd tests/ && git commit -m "feat(sim): target selectors

무작위 셀렉터는 주입된 시드 RNG만 쓴다. slowest_own의 동점은 슬롯 순서로 깬다 —
둘 다 결정론 계약을 지키기 위한 것이다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 9: 조건 평가

**Files:**
- Create: `sim/conditions.gd`
- Create: `tests/unit/test_conditions.gd`
- Modify: `tests/run_unit.gd`

스펙 §6.2의 조건 15종. 여러 조건이 함께 오면 AND다. 알 수 없는 조건 키는 **거짓**을 돌려준다 — 오타 난 조건이 조용히 항상 참이 되는 것보다 조용히 항상 거짓인 편이 배치 리포트에서 눈에 띈다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/unit/test_conditions.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Cond = preload("res://sim/conditions.gd")

func _ship() -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = 200
	s.hull = 200
	var p: RefCounted = Part.new()
	p.slot_id = "weapon_1"
	p.role = "weapon"
	p.part_id = "fx_gun"
	p.faction = "reclaimer"
	p.keywords = ["damage", "fire_limit"]
	p.cooldown_units = K.cooldown_to_units(2.0)
	s.add_part(p)
	return s

func _ctx(s: RefCounted, event: Dictionary, tick: int = 0) -> Dictionary:
	return {
		"own_ship": s, "enemy_ship": null, "part": s.get_part("weapon_1"),
		"event": event, "tick": tick, "source_part": s.get_part("weapon_1"),
		"accum": 0, "accum_prev": 0,
	}

func run(t: RefCounted) -> void:
	_test_empty_and_and(t)
	_test_resources(t)
	_test_time(t)
	_test_fire_counts(t)
	_test_event_shape(t)
	_test_part_state(t)
	_test_unknown(t)
	t.done()

func _test_empty_and_and(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var ctx: Dictionary = _ctx(s, {})
	t.check(Cond.evaluate({}, ctx), "빈 조건은 항상 참")
	t.check(Cond.evaluate(null, ctx), "조건 없음은 항상 참")

	s.resonance = 5
	s.material = 10
	t.check(Cond.evaluate({"resonance_at_least": 3, "material_at_least": 10}, ctx),
		"여러 조건은 AND — 둘 다 참")
	t.check(not Cond.evaluate({"resonance_at_least": 3, "material_at_least": 11}, ctx),
		"여러 조건은 AND — 하나가 거짓이면 거짓")

func _test_resources(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	s.resonance = 3
	var ctx: Dictionary = _ctx(s, {})
	t.check(Cond.evaluate({"resonance_at_least": 3}, ctx), "공명 3 >= 3")
	t.check(not Cond.evaluate({"resonance_at_least": 4}, ctx), "공명 3 < 4")

	# prime_oscillator Relic은 요구치를 1 낮춰 평가한다 (스펙 §6.2 §9.4)
	s.resonance_discount = 1
	t.check(Cond.evaluate({"resonance_at_least": 4}, ctx), "할인 1이면 요구 4를 3으로 친다")
	t.check(not Cond.evaluate({"resonance_at_least": 5}, ctx), "할인해도 요구 5는 못 넘는다")

	s.hull = 100
	t.check(Cond.evaluate({"hull_below_ratio": 0.6}, ctx), "HP 50%는 0.6 미만")
	t.check(not Cond.evaluate({"hull_below_ratio": 0.5}, ctx), "HP 50%는 0.5 미만이 아니다")

func _test_time(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	# 30초 = 600틱
	t.check(Cond.evaluate({"before_seconds": 30.0}, _ctx(s, {}, 599)), "599틱은 30초 이전")
	t.check(not Cond.evaluate({"before_seconds": 30.0}, _ctx(s, {}, 600)), "600틱은 30초 이전이 아니다")
	t.check(Cond.evaluate({"after_seconds": 30.0}, _ctx(s, {}, 600)), "600틱은 30초 이후")
	t.check(not Cond.evaluate({"after_seconds": 30.0}, _ctx(s, {}, 599)), "599틱은 30초 이후가 아니다")

func _test_fire_counts(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var p: RefCounted = s.get_part("weapon_1")
	var ctx: Dictionary = _ctx(s, {})

	p.fires_used = 0
	t.check(not Cond.evaluate({"every_nth_fire": 3}, ctx), "0회는 3의 배수로 치지 않는다")
	p.fires_used = 3
	t.check(Cond.evaluate({"every_nth_fire": 3}, ctx), "3회째")
	p.fires_used = 4
	t.check(not Cond.evaluate({"every_nth_fire": 3}, ctx), "4회째는 아니다")
	p.fires_used = 6
	t.check(Cond.evaluate({"every_nth_fire": 3}, ctx), "6회째")

	# every_nth_accumulated: 누적값이 n의 배수를 새로 넘을 때만 참
	var c2: Dictionary = _ctx(s, {})
	c2["accum_prev"] = 8
	c2["accum"] = 12
	t.check(Cond.evaluate({"every_nth_accumulated": {"field": "amount", "n": 10}}, c2),
		"8에서 12로 가면 10을 새로 넘는다")
	c2["accum_prev"] = 12
	c2["accum"] = 18
	t.check(not Cond.evaluate({"every_nth_accumulated": {"field": "amount", "n": 10}}, c2),
		"12에서 18은 새 배수를 넘지 않는다")
	c2["accum_prev"] = 18
	c2["accum"] = 31
	t.check(Cond.evaluate({"every_nth_accumulated": {"field": "amount", "n": 10}}, c2),
		"18에서 31은 20과 30을 넘으므로 참")

func _test_event_shape(t: RefCounted) -> void:
	var s: RefCounted = _ship()

	var own_event: Dictionary = {"ship": "player", "slot": "weapon_1", "faction": "reclaimer"}
	var ctx: Dictionary = _ctx(s, own_event)
	t.check(Cond.evaluate({"is_host": true}, ctx), "같은 슬롯·같은 함선이면 숙주다")
	t.check(Cond.evaluate({"own_ship": true}, ctx), "자함 이벤트")
	t.check(not Cond.evaluate({"enemy_ship": true}, ctx), "적함 이벤트가 아니다")
	t.check(Cond.evaluate({"source_faction": "reclaimer"}, ctx), "팩션 일치")
	t.check(not Cond.evaluate({"source_faction": "viridia"}, ctx), "팩션 불일치")
	t.check(Cond.evaluate({"source_keyword": "damage"}, ctx), "소스 파츠가 키워드 보유")
	t.check(not Cond.evaluate({"source_keyword": "regen"}, ctx), "소스 파츠가 키워드 미보유")

	var other_slot: Dictionary = {"ship": "player", "slot": "weapon_2"}
	t.check(not Cond.evaluate({"is_host": true}, _ctx(s, other_slot)), "다른 슬롯은 숙주가 아니다")

	var enemy_event: Dictionary = {"ship": "enemy", "slot": "weapon_1"}
	t.check(not Cond.evaluate({"is_host": true}, _ctx(s, enemy_event)),
		"같은 슬롯 이름이어도 적함이면 숙주가 아니다")
	t.check(Cond.evaluate({"enemy_ship": true}, _ctx(s, enemy_event)), "적함 이벤트")

	# event_field — 임의 필드 비교 (스펙 §6.2)
	var destroyed: Dictionary = {"ship": "player", "slot": "weapon_1", "cause": "fires_exhausted"}
	t.check(Cond.evaluate({"event_field": {"field": "cause", "equals": "fires_exhausted"}},
		_ctx(s, destroyed)), "파손 원인 일치")
	t.check(not Cond.evaluate({"event_field": {"field": "cause", "equals": "threshold"}},
		_ctx(s, destroyed)), "파손 원인 불일치")
	t.check(not Cond.evaluate({"event_field": {"field": "nope", "equals": "x"}},
		_ctx(s, destroyed)), "없는 필드는 거짓")

func _test_part_state(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var p: RefCounted = s.get_part("weapon_1")
	var ctx: Dictionary = _ctx(s, {})

	t.check(not Cond.evaluate({"fires_remaining_at_most": 2}, ctx), "무제한 파츠는 항상 거짓")
	p.fire_limit = 5
	p.fires_remaining = 2
	t.check(Cond.evaluate({"fires_remaining_at_most": 2}, ctx), "남은 2 <= 2")
	t.check(not Cond.evaluate({"fires_remaining_at_most": 1}, ctx), "남은 2 > 1")

	t.check(not Cond.evaluate({"has_broken_own": true}, ctx), "파손 파츠 없음")
	p.broken = true
	t.check(Cond.evaluate({"has_broken_own": true}, ctx), "파손 파츠 있음")
	t.check(not Cond.evaluate({"has_broken_own": false}, ctx), "false를 요구하면 거짓")

func _test_unknown(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	# 오타 난 조건은 조용히 항상 참이 되면 안 된다 — 거짓으로 닫는다
	t.check(not Cond.evaluate({"no_such_condition": 1}, _ctx(s, {})),
		"알 수 없는 조건은 거짓")
	t.eq(Cond.unknown_keys({"resonance_at_least": 1, "typo_here": 2}), ["typo_here"],
		"카탈로그 검증이 쓸 수 있게 알 수 없는 키를 열거한다")

	# 로드 시점 검증자와 전투 시점 평가자가 같은 판단을 해야 한다.
	t.eq(Cond.unknown_keys(null).size(), 0, "null은 조건 없음이므로 정상")
	t.eq(Cond.unknown_keys({}).size(), 0, "빈 조건도 정상")
	t.check(not Cond.evaluate("메모", _ctx(s, {})), "문자열 where는 거짓으로 닫는다")
	t.check(not Cond.evaluate([1, 2], _ctx(s, {})), "배열 where도 거짓으로 닫는다")
	t.check(not Cond.evaluate(42, _ctx(s, {})), "정수 where도 거짓으로 닫는다")
	for bad: Variant in ["메모", [1, 2], 42, true]:
		var closed: bool = not Cond.evaluate(bad, _ctx(s, {}))
		var reported: bool = Cond.unknown_keys(bad).size() > 0
		t.check(closed == reported,
			"evaluate가 닫는 입력은 unknown_keys도 신고해야 한다: %s" % str(bad))
```

- [ ] **Step 2: 러너에 `"res://tests/unit/test_conditions.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/conditions.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 3: 구현한다**

`sim/conditions.gd`:

```gdscript
extends RefCounted
## where 조건 평가. 스펙 §6.2. 여러 조건이 함께 오면 AND.
##
## ship_state.gd를 preload하지 않는다 — 덕타이핑으로 다룬다 (targeting.gd와 같은 이유).
##
## 알 수 없는 조건 키는 거짓이다. 오타 난 조건이 조용히 항상 참이 되는 것보다
## 조용히 항상 거짓인 편이 배치 리포트에서 눈에 띈다.

const K = preload("res://sim/sim_const.gd")

const CONDITIONS: Array[String] = [
	"resonance_at_least", "material_at_least",
	"before_seconds", "after_seconds",
	"every_nth_fire", "every_nth_accumulated",
	"is_host", "event_field", "source_faction", "source_keyword",
	"hull_below_ratio", "fires_remaining_at_most", "has_broken_own",
	"own_ship", "enemy_ship",
]

## ctx: {own_ship, enemy_ship, part, event, tick, source_part, accum, accum_prev}
## tick이 없으면 0(전투 시작)으로 평가된다 — 트리거 엔진이 반드시 채워야 한다.
## accum/accum_prev도 트리거 엔진이 채운다 (every_nth_accumulated용).
##
## null과 {}는 "조건 없음"이라 참이다. 그러나 Dictionary도 null도 아닌 값
## (문자열·배열·정수 등)은 작성 실수이므로 거짓으로 닫는다 — 참으로 열어두면
## 그 파츠가 매 이벤트마다 발동하는데 아무도 눈치채지 못한다.
static func evaluate(where: Variant, ctx: Dictionary) -> bool:
	if where == null:
		return true
	if not (where is Dictionary):
		return false
	var conditions: Dictionary = where
	for key: String in conditions:
		if not _one(key, conditions[key], ctx):
			return false
	return true

## 카탈로그 검증용 — 문제가 있는 키를 열거한다. 빈 배열이면 이상 없음.
##
## evaluate()가 거짓으로 닫는 입력은 여기서도 반드시 신고해야 한다.
## 신고하지 않으면 작성 실수가 카탈로그를 통과한 뒤 전투에서 파츠를 조용히
## 죽인다 — fail-closed가 눈에 띄게 하려던 결함이 가장 눈에 띄어야 할
## 지점(로드 시점)에서 침묵하는 셈이다.
static func unknown_keys(where: Variant) -> Array[String]:
	var out: Array[String] = []
	if where == null:
		return out
	if not (where is Dictionary):
		out.append("<where가 Dictionary가 아니다>")
		return out
	for key: String in (where as Dictionary):
		if not CONDITIONS.has(key):
			out.append(key)
	return out

static func _one(key: String, value: Variant, ctx: Dictionary) -> bool:
	var ship: RefCounted = ctx["own_ship"]
	var part: RefCounted = ctx.get("part", null)
	var event: Dictionary = ctx.get("event", {})
	var tick: int = int(ctx.get("tick", 0))

	match key:
		"resonance_at_least":
			# prime_oscillator Relic이 요구치를 낮춘다 (스펙 §9.4)
			return ship.resonance >= maxi(0, int(value) - ship.resonance_discount)
		"material_at_least":
			return ship.material >= int(value)
		"before_seconds":
			return tick < K.secs_to_ticks(float(value))
		"after_seconds":
			return tick >= K.secs_to_ticks(float(value))
		"every_nth_fire":
			var n: int = int(value)
			return n > 0 and part != null and part.fires_used > 0 and part.fires_used % n == 0
		"every_nth_accumulated":
			var spec: Dictionary = value
			var step: int = int(spec.get("n", 0))
			if step <= 0:
				return false
			var before: int = int(ctx.get("accum_prev", 0))
			var after: int = int(ctx.get("accum", 0))
			return (after / step) > (before / step)
		"is_host":
			var same: bool = part != null \
				and str(event.get("slot", "")) == part.slot_id \
				and str(event.get("ship", "")) == ship.side
			return same == bool(value)
		"event_field":
			var spec2: Dictionary = value
			var field: String = str(spec2.get("field", ""))
			if not event.has(field):
				return false
			return event[field] == spec2.get("equals", null)
		"source_faction":
			# source_keyword와 같은 곳(source_part)을 본다. 같은 접두사를 가진 두 조건이
			# 서로 다른 곳을 보면 함정이 된다. 이벤트가 faction을 직접 실어 보내면
			# 그것도 받아들인다 (part_fired가 그렇다).
			var src: RefCounted = ctx.get("source_part", null)
			if src != null:
				return src.faction == str(value)
			return str(event.get("faction", "")) == str(value)
		"source_keyword":
			var source: RefCounted = ctx.get("source_part", null)
			return source != null and source.has_keyword(str(value))
		"hull_below_ratio":
			return ship.hull_ratio() < float(value)
		"fires_remaining_at_most":
			return part != null and part.is_limited() and part.fires_remaining <= int(value)
		"has_broken_own":
			return (not ship.broken_parts().is_empty()) == bool(value)
		"own_ship":
			return (str(event.get("ship", "")) == ship.side) == bool(value)
		"enemy_ship":
			return (str(event.get("ship", "")) != ship.side) == bool(value)
	return false
```

- [ ] **Step 4: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 5: 커밋**

```bash
git add sim/conditions.gd tests/ && git commit -m "feat(sim): where condition evaluator

알 수 없는 조건 키는 거짓으로 닫는다 — 오타가 조용히 항상 참이 되지 않게.
resonance_at_least는 prime_oscillator Relic의 할인을 반영해 평가한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 10: 원자 액션

**Files:**
- Create: `tests/fake_sim.gd`
- Create: `sim/actions.gd`
- Create: `tests/unit/test_actions.gd`
- Modify: `sim/catalog.gd` (op·조건·셀렉터 이름 검증 추가)
- Modify: `docs/superpowers/specs/2026-08-29-first-divergence-phase0-design.md` (§6.1에 `break_prevented` 추가)
- Modify: `tests/run_unit.gd`

스펙 §6.3의 op 20종. 두 가지 공통 규칙이 이 파일의 까다로운 부분이다:

1. **셀렉터는 `do` 블록 시작 시점에 한 번만 해석하고 블록 전체가 공유한다** (스펙 §6.4).
   `[fire_part{slowest_own}, drain_fires{slowest_own}]`이 같은 파츠를 건드려야 하기 때문이다.
2. **`delay`가 붙은 액션은 예약된다.** 예약할 때 **해석된 대상을 함께 저장한다** — 8초 뒤에
   `random_broken_own`을 다시 뽑으면 전혀 다른 파츠가 복구된다.

- [ ] **Step 1: 테스트용 가짜 sim을 쓴다**

`tests/fake_sim.gd`:

```gdscript
extends RefCounted
## actions.gd가 요구하는 sim 인터페이스의 최소 구현. 호출을 기록만 한다.

const K = preload("res://sim/sim_const.gd")

var events: Array = []
var forced: Array = []
var scheduled: Array = []
var tick: int = 0

func emit(type: String, ship_side: String, fields: Dictionary) -> void:
	var ev: Dictionary = fields.duplicate()
	ev["type"] = type
	ev["ship"] = ship_side
	ev["t"] = K.ticks_to_secs(tick)
	events.append(ev)

func force_fire(part: RefCounted, ship: RefCounted, cause: String) -> void:
	forced.append({"slot": part.slot_id, "ship": ship.side, "cause": cause})

func schedule(delay_ticks: int, action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	scheduled.append({"at": tick + delay_ticks, "action": action, "resolved": resolved})

## 특정 타입의 이벤트만 뽑는다
func of_type(type: String) -> Array:
	var out: Array = []
	for ev: Dictionary in events:
		if ev["type"] == type:
			out.append(ev)
	return out
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`tests/unit/test_actions.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Actions = preload("res://sim/actions.gd")
const FakeSim = preload("res://tests/fake_sim.gd")

var _sim: RefCounted
var _own: RefCounted
var _foe: RefCounted

func _reset() -> Dictionary:
	_sim = FakeSim.new()
	_own = _make_ship("player")
	_foe = _make_ship("enemy")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return {
		"sim": _sim, "own_ship": _own, "enemy_ship": _foe,
		"part": _own.get_part("weapon_1"), "rng": rng,
		"event": {}, "tick": 0, "damage_mult": 1.0,
	}

func _make_ship(side: String) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = side
	s.max_hull = 200
	s.hull = 200
	s.thresholds = [0.75, 0.50, 0.25]
	s.thresholds_crossed = [false, false, false]
	for spec: Array in [["core", "core"], ["weapon_1", "weapon"], ["utility_1", "utility"]]:
		var p: RefCounted = Part.new()
		p.slot_id = spec[0]
		p.role = spec[1]
		p.part_id = "fx_" + spec[0]
		p.faction = "reclaimer"
		p.cooldown_units = K.cooldown_to_units(2.0)
		s.add_part(p)
	return s

func run(t: RefCounted) -> void:
	_test_damage_and_heal(t)
	_test_empower(t)
	_test_resources(t)
	_test_speed(t)
	_test_fires(t)
	_test_part_ops(t)
	_test_where_on_action(t)
	_test_selector_resolved_once(t)
	_test_delay(t)
	_test_multi_fire(t)
	_test_op_vocabulary(t)
	t.done()

func _test_damage_and_heal(t: RefCounted) -> void:
	var ctx: Dictionary = _reset()
	_foe.shield = 4
	Actions.run_block([{"op": "deal_damage", "amount": 10}], ctx)
	t.eq(_foe.hull, 194, "피해는 적함에 간다")
	t.eq(_foe.shield, 0, "보호막이 먼저 흡수")
	var dmg: Array = _sim.of_type("damage_dealt")
	t.eq(dmg.size(), 1, "damage_dealt 이벤트 1건")
	t.eq(dmg[0]["target_ship"], "enemy", "대상 함선")
	t.eq(dmg[0]["absorbed"], 4, "흡수량이 이벤트에 실린다")
	t.eq(dmg[0]["source_slot"], "weapon_1", "출처 슬롯이 실린다")
	t.eq(_sim.of_type("hull_changed").size(), 1, "선체가 줄면 hull_changed도 나온다")

	var ctx2: Dictionary = _reset()
	_own.hull = 100
	Actions.run_block([
		{"op": "repair", "amount": 15},
		{"op": "gain_shield", "amount": 20},
		{"op": "apply_regen", "amount": 2, "duration": 5.0},
		{"op": "apply_overheat", "stacks": 3},
	], ctx2)
	t.eq(_own.hull, 115, "수리는 자함에")
	t.eq(_own.shield, 20, "보호막은 자함에")
	t.eq(_own.regen_entries.size(), 1, "재생은 자함에")
	t.eq(int(_own.regen_entries[0]["ticks_left"]), K.secs_to_ticks(5.0), "재생 지속시간이 틱으로")
	t.eq(_foe.overheat_stacks, 3, "과열은 적함에")

func _test_empower(t: RefCounted) -> void:
	# 스펙 §6.3 — empower는 대상의 다음 발동 피해를 증폭하고 발동 시 1스택 소모한다
	var ctx: Dictionary = _reset()
	Actions.run_block([
		{"op": "empower", "target": "self", "damage_mult": 1.5, "stacks": 2}
	], ctx)
	var p: RefCounted = _own.get_part("weapon_1")
	t.eq(p.empower_stacks.size(), 2, "스택 2개")
	t.near(p.take_empower(), 1.5, "첫 발동에 1.5배")
	t.eq(p.empower_stacks.size(), 1, "1스택 소모")
	t.near(p.take_empower(), 1.5, "둘째 발동에도 1.5배")
	t.near(p.take_empower(), 1.0, "스택이 없으면 1.0배")

	# 발동 문맥의 damage_mult가 deal_damage에 곱해진다
	var ctx2: Dictionary = _reset()
	ctx2["damage_mult"] = 2.0
	Actions.run_block([{"op": "deal_damage", "amount": 10}], ctx2)
	t.eq(_foe.hull, 180, "damage_mult 2.0이면 피해 20")

func _test_resources(t: RefCounted) -> void:
	var ctx: Dictionary = _reset()
	Actions.run_block([
		{"op": "gain_material", "amount": 10},
		{"op": "gain_resonance", "amount": 2},
	], ctx)
	t.eq(_own.material, 10, "자재 획득")
	t.eq(_own.resonance, 2, "공명 획득")
	t.eq(_sim.of_type("material_gained").size(), 1, "material_gained 이벤트")
	t.eq(_sim.of_type("material_gained")[0]["slot"], "weapon_1",
		"material 이벤트에 출처 슬롯이 실린다 (augment가 is_host로 거르기 위해)")
	t.eq(_sim.of_type("resonance_gained").size(), 1, "resonance_gained 이벤트")

	Actions.run_block([{"op": "spend_material", "amount": 4}], ctx)
	t.eq(_own.material, 6, "자재 지출")
	t.eq(_sim.of_type("material_spent").size(), 1, "material_spent 이벤트")

func _test_speed(t: RefCounted) -> void:
	# 스펙 §6.5 — 배율은 고정, 파츠가 지정하는 것은 duration뿐
	var ctx: Dictionary = _reset()
	Actions.run_block([{"op": "accelerate", "target": "self", "duration": 3.0}], ctx)
	var p: RefCounted = _own.get_part("weapon_1")
	t.eq(p.accel_ticks, 60, "3초 = 60틱 가속")
	t.eq(p.speed_units(), K.SPEED_ACCEL, "가속 상태")
	t.eq(_sim.of_type("speed_changed").size(), 1, "speed_changed 이벤트")
	t.eq(_sim.of_type("speed_changed")[0]["state"], "accelerated", "상태 필드")

	Actions.run_block([{"op": "slow", "target": "self", "duration": 1.0}], ctx)
	t.eq(p.accel_ticks, 40, "둔화 20틱이 가속에서 상쇄된다")

	# all_own_active로 여러 파츠 동시 가속
	var ctx2: Dictionary = _reset()
	Actions.run_block([{"op": "accelerate", "target": "all_own_active", "duration": 1.0}], ctx2)
	for part: RefCounted in _own.parts:
		t.eq(part.accel_ticks, 20, "%s 가속" % part.slot_id)

	# 영구 가속
	var ctx3: Dictionary = _reset()
	Actions.run_block([{"op": "accelerate", "target": "self", "duration": -1.0}], ctx3)
	t.eq(_own.get_part("weapon_1").accel_ticks, K.PERMANENT, "duration -1은 영구")

func _test_fires(t: RefCounted) -> void:
	var ctx: Dictionary = _reset()
	var util: RefCounted = _own.get_part("utility_1")
	util.fire_limit = 4
	util.fires_remaining = 4

	Actions.run_block([{"op": "drain_fires", "target": "all_own_limited", "amount": 1}], ctx)
	t.eq(util.fires_remaining, 3, "제한 파츠의 남은 횟수가 깎인다")
	t.eq(_sim.of_type("fires_changed").size(), 1, "fires_changed 이벤트")
	t.eq(_sim.of_type("fires_changed")[0]["delta"], -1, "delta 필드")
	t.eq(_sim.of_type("fires_changed")[0]["remaining"], 3, "remaining 필드")

	# material_per_part — 실제로 깎인 파츠 수에 비례해 자재 (스펙 §6.3)
	var ctx2: Dictionary = _reset()
	for slot: String in ["weapon_1", "utility_1"]:
		var p: RefCounted = _own.get_part(slot)
		p.fire_limit = 3
		p.fires_remaining = 3
	Actions.run_block([
		{"op": "drain_fires", "target": "all_own_limited", "amount": 1, "material_per_part": 4}
	], ctx2)
	t.eq(_own.material, 8, "2개 파츠가 깎였으므로 자재 8")

	# 남은 횟수가 0이 되면 파손된다
	var ctx3: Dictionary = _reset()
	var w: RefCounted = _own.get_part("weapon_1")
	w.fire_limit = 1
	w.fires_remaining = 1
	Actions.run_block([{"op": "drain_fires", "target": "self", "amount": 1}], ctx3)
	t.check(w.broken, "횟수 소진으로 파손")
	var destroyed: Array = _sim.of_type("part_destroyed")
	t.eq(destroyed.size(), 1, "part_destroyed 이벤트")
	t.eq(destroyed[0]["cause"], "fires_exhausted", "파손 원인")

	# restore_fires
	var ctx4: Dictionary = _reset()
	var u: RefCounted = _own.get_part("utility_1")
	u.fire_limit = 5
	u.fires_remaining = 2
	Actions.run_block([{"op": "restore_fires", "target": "self", "amount": 2}], ctx4)
	t.eq(u.fires_remaining, 2, "self는 weapon_1이므로 utility_1은 그대로")

	ctx4["part"] = u
	Actions.run_block([{"op": "restore_fires", "target": "self", "amount": 2}], ctx4)
	t.eq(u.fires_remaining, 4, "회복")
	Actions.run_block([{"op": "restore_fires", "target": "self", "amount": 99}], ctx4)
	t.eq(u.fires_remaining, 5, "회복은 초기값을 넘지 않는다")

func _test_part_ops(t: RefCounted) -> void:
	# destroy_part / restore_part / reinforce / make_indestructible / reduce_cooldown
	var ctx: Dictionary = _reset()
	Actions.run_block([{"op": "reinforce", "target": "self", "stacks": 2}], ctx)
	var p: RefCounted = _own.get_part("weapon_1")
	t.eq(p.reinforce_stacks, 2, "보강 2스택")
	t.eq(_sim.of_type("reinforce_gained").size(), 1, "reinforce_gained 이벤트")

	Actions.run_block([{"op": "destroy_part", "target": "self"}], ctx)
	t.check(not p.broken, "보강이 파손을 막는다")
	t.eq(p.reinforce_stacks, 1, "보강 1 소모")
	t.eq(_sim.of_type("reinforce_consumed").size(), 1, "reinforce_consumed 이벤트")

	# 파괴 불가는 보강보다 먼저 적용되고 보강을 소모하지 않는다 (스펙 §8)
	var ctx2: Dictionary = _reset()
	var q: RefCounted = _own.get_part("weapon_1")
	q.reinforce_stacks = 1
	Actions.run_block([
		{"op": "make_indestructible", "target": "self", "duration": 15.0},
		{"op": "destroy_part", "target": "self"},
	], ctx2)
	t.check(not q.broken, "파괴 불가면 파손되지 않는다")
	t.eq(q.reinforce_stacks, 1, "보강 스택은 그대로")
	t.eq(_sim.of_type("break_prevented").size(), 1, "break_prevented 이벤트 (지표 C가 센다)")
	t.eq(_sim.of_type("indestructible_applied").size(), 1, "indestructible_applied 이벤트")

	# 실제 파손과 복구
	var ctx3: Dictionary = _reset()
	var r: RefCounted = _own.get_part("weapon_1")
	r.fire_limit = 3
	r.fires_remaining = 1
	Actions.run_block([{"op": "destroy_part", "target": "self"}], ctx3)
	t.check(r.broken, "파손")
	t.eq(_sim.of_type("part_destroyed")[0]["cause"], "effect", "액션에 의한 파손 원인은 effect")
	Actions.run_block([{"op": "restore_part", "target": "self"}], ctx3)
	t.check(not r.broken, "복구")
	t.eq(r.fires_remaining, 3, "복구는 남은 횟수를 초기값으로 되돌린다")
	t.eq(_sim.of_type("part_restored").size(), 1, "part_restored 이벤트")

	# reduce_cooldown — 쿨타임 유닛의 비율만큼 진행도를 더한다
	var ctx4: Dictionary = _reset()
	var w: RefCounted = _own.get_part("weapon_1")  # 쿨타임 2초 = 80유닛
	Actions.run_block([{"op": "reduce_cooldown", "target": "self", "ratio": 0.4}], ctx4)
	t.eq(w.progress_units, 32, "80유닛의 40% = 32유닛 진행")
	Actions.run_block([{"op": "reduce_cooldown", "target": "self", "ratio": 10.0}], ctx4)
	t.eq(w.progress_units, w.cooldown_units, "진행도는 쿨타임 목표치를 넘지 않는다")

	# fire_part는 sim에 강제 발동을 요청한다
	var ctx5: Dictionary = _reset()
	Actions.run_block([{"op": "fire_part", "target": "self"}], ctx5)
	t.eq(_sim.forced.size(), 1, "강제 발동 1건")
	t.eq(_sim.forced[0]["slot"], "weapon_1", "대상 슬롯")

func _test_where_on_action(t: RefCounted) -> void:
	# 스펙 §6.3 공통 규칙 — 액션 항목의 where가 거짓이면 그 항목만 건너뛴다
	var ctx: Dictionary = _reset()
	_own.resonance = 2
	Actions.run_block([
		{"op": "gain_material", "amount": 3},
		{"op": "gain_material", "amount": 3, "where": {"resonance_at_least": 4}},
	], ctx)
	t.eq(_own.material, 3, "조건 거짓인 항목만 건너뛴다")

	var ctx2: Dictionary = _reset()
	_own.resonance = 5
	Actions.run_block([
		{"op": "gain_material", "amount": 3},
		{"op": "gain_material", "amount": 3, "where": {"resonance_at_least": 4}},
	], ctx2)
	t.eq(_own.material, 6, "조건 참이면 둘 다 실행")

func _test_selector_resolved_once(t: RefCounted) -> void:
	# 스펙 §6.4 — 블록 시작 시점에 한 번만 해석하고 결과를 공유한다.
	# phase_shifter의 [restore_part{random_broken_own}, drain_fires{random_broken_own}]이
	# 같은 파츠를 건드려야 한다 — 첫 액션이 대상을 파손 목록에서 빼버리기 때문이다.
	var ctx: Dictionary = _reset()
	var w: RefCounted = _own.get_part("weapon_1")
	w.fire_limit = 5
	w.fires_remaining = 5
	w.broken = true

	Actions.run_block([
		{"op": "restore_part", "target": "random_broken_own"},
		{"op": "drain_fires", "target": "random_broken_own", "amount": 2},
	], ctx)
	t.check(not w.broken, "복구되었다")
	t.eq(w.fires_remaining, 3, "같은 파츠가 이어서 깎였다 — 셀렉터가 재평가되지 않았다")

func _test_delay(t: RefCounted) -> void:
	# 스펙 §6.3 — delay는 예약. 해석된 대상을 함께 저장해야 한다.
	var ctx: Dictionary = _reset()
	Actions.run_block([
		{"op": "restore_part", "target": "self", "delay": 8.0}
	], ctx)
	t.eq(_sim.scheduled.size(), 1, "예약 1건")
	t.eq(_sim.scheduled[0]["at"], K.secs_to_ticks(8.0), "8초 뒤 실행")
	t.check(not _sim.scheduled[0]["action"].has("delay"), "예약된 액션에서 delay는 제거된다")
	t.check(_sim.scheduled[0]["resolved"].has("self"), "해석된 대상이 함께 저장된다")
	t.check(not _own.get_part("weapon_1").broken, "지금 당장은 실행되지 않는다")

func _test_multi_fire(t: RefCounted) -> void:
	# do가 있으면 그 블록을 n회
	var ctx: Dictionary = _reset()
	Actions.run_block([
		{"op": "multi_fire", "times": 3, "do": [{"op": "deal_damage", "amount": 5}]}
	], ctx)
	t.eq(_foe.hull, 185, "5 피해 x 3회")

	# do가 없으면 소유 파츠의 on_fire를 n회 (스펙 §6.3)
	var ctx2: Dictionary = _reset()
	var p: RefCounted = _own.get_part("weapon_1")
	p.on_fire = [{"op": "deal_damage", "amount": 7}]
	Actions.run_block([{"op": "multi_fire", "times": 2}], ctx2)
	t.eq(_foe.hull, 186, "숙주 on_fire 7 피해 x 2회")

	# multi_fire는 발동 상한도 발동 횟수도 소모하지 않는다
	var ctx3: Dictionary = _reset()
	var q: RefCounted = _own.get_part("weapon_1")
	q.on_fire = [{"op": "deal_damage", "amount": 1}]
	q.fire_limit = 5
	q.fires_remaining = 5
	Actions.run_block([{"op": "multi_fire", "times": 3}], ctx3)
	t.eq(q.fires_remaining, 5, "multi_fire는 발동 횟수를 소모하지 않는다")
	t.eq(q.fires_used, 0, "발동 이력도 늘지 않는다")

func _test_op_vocabulary(t: RefCounted) -> void:
	t.eq(Actions.OPS.size(), 20, "스펙 §6.3의 op 20종")
	for op: String in ["deal_damage", "drain_fires", "restore_fires", "make_indestructible",
			"empower", "multi_fire", "fire_part"]:
		t.check(Actions.OPS.has(op), "%s는 알려진 op" % op)
	t.check(not Actions.OPS.has("apply_overload"), "과부하 op는 존재하지 않는다")
```

- [ ] **Step 3: 러너에 `"res://tests/unit/test_actions.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/actions.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 4: 구현한다**

`sim/actions.gd`:

```gdscript
extends RefCounted
## 원자 액션 실행기. 스펙 §6.3.
##
## sim 인터페이스는 덕타이핑으로 받는다 (preload 순환 회피). 필요한 것은 네 가지다:
##   sim.emit(type, ship_side, fields) / sim.force_fire(part, ship, cause)
##   sim.schedule(delay_ticks, action, ctx, resolved) / sim.tick

const K = preload("res://sim/sim_const.gd")
const Targeting = preload("res://sim/targeting.gd")
const Conditions = preload("res://sim/conditions.gd")

const OPS: Array[String] = [
	"deal_damage", "gain_shield", "repair", "apply_regen", "apply_overheat",
	"accelerate", "slow", "drain_fires", "restore_fires", "make_indestructible",
	"reduce_cooldown", "destroy_part", "restore_part", "reinforce", "empower",
	"gain_material", "spend_material", "gain_resonance", "fire_part", "multi_fire",
]

## do 블록 하나를 실행한다.
## 스펙 §6.4 — 셀렉터는 블록 시작 시점에 한 번만 해석하고 블록 전체가 공유한다.
static func run_block(block: Array, ctx: Dictionary) -> void:
	var resolved: Dictionary = resolve_selectors(block, ctx)
	for item: Variant in block:
		run_action(item as Dictionary, ctx, resolved)

static func resolve_selectors(block: Array, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for item: Variant in block:
		var selector: String = str((item as Dictionary).get("target", ""))
		if selector != "" and not out.has(selector):
			out[selector] = Targeting.resolve(selector, ctx)
	return out

static func run_action(action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	if action.has("where") and not Conditions.evaluate(action["where"], ctx):
		return
	if action.has("delay"):
		var deferred: Dictionary = action.duplicate(true)
		deferred.erase("delay")
		# 해석된 대상을 함께 넘긴다 — 8초 뒤에 random_broken_own을 다시 뽑으면
		# 전혀 다른 파츠가 복구된다.
		ctx["sim"].schedule(K.secs_to_ticks(float(action["delay"])), deferred, ctx, resolved)
		return
	apply(action, ctx, resolved)

## resolved는 항상 완전해야 한다 — run_block이 블록 전체의 셀렉터를 미리 수집하므로
## 정상 경로에서는 폴백이 도달하지 않는다. Actions.apply()를 run_block을 거치지 않고
## 직접 부르는 곳(combat_sim의 delay 예약 재개)은 저장해 둔 resolved를 그대로 넘겨야
## 한다. 불완전한 resolved를 넘기면 "블록당 1회 해석" 계약이 조용히 깨진다.
static func _targets(action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> Array:
	var selector: String = str(action.get("target", ""))
	if selector == "":
		return []
	if resolved.has(selector):
		return resolved[selector]
	return Targeting.resolve(selector, ctx)

## 파손을 시도하고 결과에 맞는 이벤트를 남긴다.
## 파괴선 검사(combat_sim)와 횟수 소진도 이 함수를 거친다 — 파손 경로는 하나뿐이다.
static func break_part(part: RefCounted, ship: RefCounted, cause: String, sim: RefCounted) -> String:
	var outcome: String = part.try_break()
	match outcome:
		"broken":
			sim.emit("part_destroyed", ship.side, {
				"slot": part.slot_id, "part_id": part.part_id,
				"part_name": part.part_name, "cause": cause,
			})
		"reinforce":
			sim.emit("reinforce_consumed", ship.side, {
				"slot": part.slot_id, "stacks": part.reinforce_stacks,
			})
		"indestructible":
			sim.emit("break_prevented", ship.side, {
				"slot": part.slot_id, "part_id": part.part_id,
				"cause": cause, "by": "indestructible",
			})
	return outcome

static func apply(action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	var op: String = str(action.get("op", ""))
	var sim: RefCounted = ctx["sim"]
	var own: RefCounted = ctx["own_ship"]
	var foe: RefCounted = ctx["enemy_ship"]
	var owner: RefCounted = ctx.get("part", null)
	var owner_slot: String = owner.slot_id if owner != null else ""

	match op:
		"deal_damage":
			var amount: int = int(round(int(action.get("amount", 0)) * float(ctx.get("damage_mult", 1.0))))
			var r: Dictionary = foe.take_damage(amount)
			sim.emit("damage_dealt", own.side, {
				"target_ship": foe.side, "amount": amount,
				"absorbed": r["absorbed"], "source_slot": owner_slot,
			})
			if int(r["absorbed"]) > 0:
				sim.emit("shield_absorbed", foe.side, {"amount": r["absorbed"]})
			if int(r["hull_damage"]) > 0:
				sim.emit("hull_changed", foe.side,
					{"from": r["from"], "to": r["to"], "ratio": foe.hull_ratio()})

		"gain_shield":
			var amount2: int = int(action.get("amount", 0))
			own.add_shield(amount2)
			sim.emit("shield_gained", own.side, {"amount": amount2, "slot": owner_slot})

		"repair":
			var healed: int = own.repair(int(action.get("amount", 0)))
			if healed > 0:
				sim.emit("repaired", own.side, {"amount": healed, "slot": owner_slot})

		"apply_regen":
			var amount3: int = int(action.get("amount", 0))
			var ticks: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			own.add_regen(amount3, ticks)
			sim.emit("regen_applied", own.side,
				{"amount": amount3, "duration": action.get("duration", 0.0), "slot": owner_slot})

		"apply_overheat":
			var stacks: int = int(action.get("stacks", 0))
			foe.add_overheat(stacks)
			sim.emit("overheat_applied", foe.side, {"stacks": stacks})

		"accelerate", "slow":
			var ticks2: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			for target: RefCounted in _targets(action, ctx, resolved):
				if op == "accelerate":
					target.apply_accel(ticks2)
				else:
					target.apply_slow(ticks2)
				sim.emit("speed_changed", own.side, {
					"slot": target.slot_id,
					"state": "accelerated" if op == "accelerate" else "slowed",
					"duration": action.get("duration", 0.0),
				})

		"drain_fires":
			var amount4: int = int(action.get("amount", 0))
			var per_part: int = int(action.get("material_per_part", 0))
			var drained_parts: int = 0
			for target: RefCounted in _targets(action, ctx, resolved):
				var actually_drained: int = target.drain_fires(amount4)
				if actually_drained <= 0:
					continue
				drained_parts += 1
				sim.emit("fires_changed", own.side, {
					"slot": target.slot_id, "delta": -actually_drained,
					"remaining": target.fires_remaining, "cause": "drained",
				})
				if target.fires_remaining == 0:
					break_part(target, own, "fires_exhausted", sim)
			if per_part > 0 and drained_parts > 0:
				var gained: int = own.gain_material(per_part * drained_parts)
				sim.emit("material_gained", own.side, {
					"slot": owner_slot, "amount": gained,
					"total": own.material, "source": "drain_fires",
				})

		"restore_fires":
			var amount5: int = int(action.get("amount", 0))
			for target: RefCounted in _targets(action, ctx, resolved):
				var restored: int = target.restore_fires(amount5)
				if restored > 0:
					sim.emit("fires_changed", own.side, {
						"slot": target.slot_id, "delta": restored,
						"remaining": target.fires_remaining, "cause": "restored",
					})

		"make_indestructible":
			var ticks3: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			for target: RefCounted in _targets(action, ctx, resolved):
				target.make_indestructible(ticks3)
				sim.emit("indestructible_applied", own.side, {
					"slot": target.slot_id, "duration": action.get("duration", 0.0),
				})

		"reduce_cooldown":
			var ratio: float = float(action.get("ratio", 0.0))
			for target: RefCounted in _targets(action, ctx, resolved):
				var delta: int = int(round(target.cooldown_units * ratio))
				target.progress_units = mini(target.cooldown_units, target.progress_units + delta)

		"destroy_part":
			for target: RefCounted in _targets(action, ctx, resolved):
				break_part(target, own, "effect", sim)

		"restore_part":
			for target: RefCounted in _targets(action, ctx, resolved):
				if not target.broken:
					continue
				target.restore()
				sim.emit("part_restored", own.side,
					{"slot": target.slot_id, "part_id": target.part_id})

		"reinforce":
			var stacks2: int = int(action.get("stacks", 0))
			for target: RefCounted in _targets(action, ctx, resolved):
				target.reinforce_stacks += stacks2
				sim.emit("reinforce_gained", own.side,
					{"slot": target.slot_id, "stacks": target.reinforce_stacks})

		"empower":
			var mult: float = float(action.get("damage_mult", 1.0))
			var count: int = int(action.get("stacks", 1))
			for target: RefCounted in _targets(action, ctx, resolved):
				for i: int in count:
					target.empower_stacks.append(mult)

		"gain_material":
			var gained2: int = own.gain_material(int(action.get("amount", 0)))
			if gained2 > 0:
				sim.emit("material_gained", own.side, {
					"slot": owner_slot, "amount": gained2,
					"total": own.material, "source": "effect",
				})

		"spend_material":
			var spent: int = own.spend_material(int(action.get("amount", 0)))
			if spent > 0:
				sim.emit("material_spent", own.side, {
					"slot": owner_slot, "amount": spent,
					"total": own.material, "sink": "effect",
				})

		"gain_resonance":
			var gained3: int = own.gain_resonance(int(action.get("amount", 0)))
			if gained3 > 0:
				sim.emit("resonance_gained", own.side, {
					"amount": gained3, "total": own.resonance, "source": "effect",
				})

		"fire_part":
			for target: RefCounted in _targets(action, ctx, resolved):
				sim.force_fire(target, own, "chain")

		"multi_fire":
			# do가 있으면 그 블록을, 없으면 소유 파츠의 on_fire를 반복한다 (스펙 §6.3).
			# 발동 상한도 발동 횟수도 소모하지 않는다 — 한 발동 안의 반복이기 때문이다.
			var times: int = int(action.get("times", 1))
			var block: Array = action.get("do", [])
			if block.is_empty() and owner != null:
				block = owner.on_fire
			# on_fire 안에 do 없는 multi_fire가 다시 들어있으면 owner.on_fire를 계속
			# 되짚어 무한 재귀가 된다. JSON으로 충분히 쓸 수 있는 형태이므로 막는다.
			# 깊이를 ctx의 복사본에만 실어 형제 액션에 새지 않게 한다.
			var depth: int = int(ctx.get("_multi_fire_depth", 0))
			if depth >= K.MAX_CHAIN_DEPTH:
				return
			var inner_ctx: Dictionary = ctx.duplicate()
			inner_ctx["_multi_fire_depth"] = depth + 1
			for i: int in times:
				run_block(block, inner_ctx)
```

- [ ] **Step 5: 스펙에 `break_prevented` 이벤트를 추가한다**

구현하면서 계약이 하나 늘었다. 스펙 §10 지표 C가 "파괴 불가 유예 발생률"을 요구하는데, 유예를 알리는 이벤트가 §6.1에 없었다. `docs/superpowers/specs/2026-08-29-first-divergence-phase0-design.md`의 §6.1 이벤트 표에서 `indestructible_applied` 줄 **아래에** 다음 줄을 추가한다:

```markdown
| `break_prevented` | `slot`, `part_id`, `cause`, `by` (`indestructible`) — 파손이 유예됨 |
```

- [ ] **Step 6: 카탈로그가 op·조건·셀렉터 이름을 검증하게 한다**

Task 5에서는 actions.gd가 없어 미뤘던 검증이다. `sim/catalog.gd` 상단 const 아래에 추가:

```gdscript
const Actions = preload("res://sim/actions.gd")
const Conditions = preload("res://sim/conditions.gd")
const Targeting = preload("res://sim/targeting.gd")
```

그리고 `_validate_part`의 `return ""` 바로 위에 추가:

```gdscript
	var problem: String = _validate_effects(pid, active.get("on_fire", []), "active.on_fire")
	if problem != "":
		return problem
	problem = _validate_triggers(pid, active.get("triggers", []), "active.triggers")
	if problem != "":
		return problem
	if def.has("augment"):
		problem = _validate_triggers(pid, (def["augment"] as Dictionary).get("triggers", []),
			"augment.triggers")
		if problem != "":
			return problem
```

그리고 파일 끝에 검증 헬퍼를 추가:

```gdscript
func _validate_triggers(pid: String, triggers: Array, where: String) -> String:
	for tr: Variant in triggers:
		var trigger: Dictionary = tr
		if not trigger.has("on"):
			return "%s %s: 트리거에 \"on\"이 없다" % [pid, where]
		for key: String in Conditions.unknown_keys(trigger.get("where", {})):
			return "%s %s: 알 수 없는 조건 \"%s\"" % [pid, where, key]
		var problem: String = _validate_effects(pid, trigger.get("do", []), where)
		if problem != "":
			return problem
	return ""

func _validate_effects(pid: String, block: Array, where: String) -> String:
	for item: Variant in block:
		var action: Dictionary = item
		var op: String = str(action.get("op", ""))
		if not Actions.OPS.has(op):
			return "%s %s: 알 수 없는 op \"%s\"" % [pid, where, op]
		var selector: String = str(action.get("target", ""))
		if selector != "" and not Targeting.SELECTORS.has(selector):
			return "%s %s: 알 수 없는 셀렉터 \"%s\"" % [pid, where, selector]
		for key: String in Conditions.unknown_keys(action.get("where", {})):
			return "%s %s: 알 수 없는 조건 \"%s\"" % [pid, where, key]
		if action.has("do"):
			var problem: String = _validate_effects(pid, action["do"], where)
			if problem != "":
				return problem
	return ""
```

- [ ] **Step 7: 카탈로그 검증 테스트를 추가한다**

`tests/unit/test_catalog.gd`의 `_test_schema_errors` 끝에 추가:

```gdscript
	var c3: RefCounted = Catalog.new()
	c3.ingest_parts([
		{ "id": "bad_op", "name": "x", "faction": "reclaimer", "roles": ["weapon"],
		  "active": { "cooldown": 1.0, "on_fire": [{"op": "apply_overload", "stacks": 1}] } },
		{ "id": "bad_selector", "name": "x", "faction": "reclaimer", "roles": ["weapon"],
		  "active": { "cooldown": 1.0,
		    "on_fire": [{"op": "accelerate", "target": "nowhere", "duration": 1.0}] } },
		{ "id": "bad_condition", "name": "x", "faction": "reclaimer", "roles": ["weapon"],
		  "active": { "cooldown": 1.0, "triggers": [
		    {"on": "part_fired", "where": {"overload_at_least": 2}, "do": []}] } }
	], "inline")
	t.eq(c3.errors.size(), 3, "삭제된 어휘를 쓴 파츠 3건이 잡힌다: %s" % str(c3.errors))
```

- [ ] **Step 8: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 9: 커밋**

```bash
git add sim/actions.gd sim/catalog.gd tests/ docs/superpowers/specs/ && git commit -m "feat(sim): atomic action ops

셀렉터는 do 블록 시작 시점에 한 번만 해석해 블록 전체가 공유한다 —
[restore_part{random_broken_own}, drain_fires{random_broken_own}]이 같은 파츠를
건드려야 하기 때문이다. delay 예약도 해석된 대상을 함께 저장한다.

파손 경로는 break_part() 하나뿐이다. 카탈로그가 op/조건/셀렉터 이름을 검증하므로
삭제된 어휘(apply_overload, overload_at_least)를 쓰면 로드 시점에 걸린다.
스펙 6.1절에 break_prevented 이벤트를 추가했다 (지표 C가 유예 횟수를 센다).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 11: 트리거 엔진

**Files:**
- Create: `sim/trigger_engine.gd`
- Create: `tests/unit/test_trigger_engine.gd`
- Modify: `tests/run_unit.gd`

이벤트 하나를 양측 모든 파츠의 트리거에 매칭한다. 규칙 세 가지:

1. **기본 범위는 자함이다.** 트리거는 자기 함선에서 난 이벤트에만 반응한다. `where`에
   `enemy_ship`을 명시한 트리거만 적함 이벤트를 본다. 이 기본값이 없으면 모든 파츠가
   적의 모든 이벤트에 반응해 체인이 폭발한다.
2. **`max_fires`는 전투당 카운터다.** 트리거별로 `part.trigger_fires[i]`에 센다.
3. **체인 깊이는 이벤트에 실려 전파된다.** 깊이 상한을 넘으면 `chain_capped`를 남기고 멈춘다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/unit/test_trigger_engine.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Engine = preload("res://sim/trigger_engine.gd")
const FakeSim = preload("res://tests/fake_sim.gd")

var _sim: RefCounted
var _own: RefCounted
var _foe: RefCounted

func _setup() -> void:
	_sim = FakeSim.new()
	_sim.rng = RandomNumberGenerator.new()
	_sim.rng.seed = 3
	_own = _ship("player")
	_foe = _ship("enemy")

func _ship(side: String) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = side
	s.max_hull = 200
	s.hull = 200
	for spec: Array in [["core", "core"], ["weapon_1", "weapon"], ["utility_1", "utility"]]:
		var p: RefCounted = Part.new()
		p.slot_id = spec[0]
		p.role = spec[1]
		p.part_id = "fx_" + spec[0]
		p.faction = "reclaimer"
		p.cooldown_units = K.cooldown_to_units(2.0)
		s.add_part(p)
	return s

func _give(ship: RefCounted, slot: String, triggers: Array) -> void:
	var p: RefCounted = ship.get_part(slot)
	p.triggers = triggers
	p.trigger_fires = []
	p.trigger_accum = []
	for i: int in triggers.size():
		p.trigger_fires.append(0)
		p.trigger_accum.append(0)

func _event(type: String, ship_side: String, fields: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = fields.duplicate()
	ev["type"] = type
	ev["ship"] = ship_side
	ev["chain_depth"] = int(fields.get("chain_depth", 0))
	return ev

func run(t: RefCounted) -> void:
	_test_basic_match(t)
	_test_own_ship_default(t)
	_test_is_host(t)
	_test_max_fires(t)
	_test_accumulator(t)
	_test_chain_depth(t)
	_test_broken_parts_silent(t)
	_test_relic_triggers(t)
	t.done()

func _test_basic_match(t: RefCounted) -> void:
	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "do": [{"op": "gain_material", "amount": 3}]}
	])
	Engine.dispatch(_event("part_fired", "player", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 3, "타입이 맞으면 발동한다")

	Engine.dispatch(_event("part_restored", "player", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 3, "타입이 다르면 발동하지 않는다")

func _test_own_ship_default(t: RefCounted) -> void:
	# 기본 범위는 자함이다 — 명시하지 않으면 적함 이벤트에 반응하지 않는다
	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "do": [{"op": "gain_material", "amount": 3}]}
	])
	Engine.dispatch(_event("part_fired", "enemy", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 0, "적함 이벤트는 기본적으로 무시한다")

	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "where": {"enemy_ship": true},
		 "do": [{"op": "gain_material", "amount": 3}]}
	])
	Engine.dispatch(_event("part_fired", "enemy", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 3, "enemy_ship을 명시하면 적함 이벤트를 본다")

func _test_is_host(t: RefCounted) -> void:
	# AUGMENT의 대표 패턴 — 숙주가 발동할 때만
	_setup()
	_give(_own, "weapon_1", [
		{"on": "part_fired", "where": {"is_host": true},
		 "do": [{"op": "gain_material", "amount": 5}]}
	])
	Engine.dispatch(_event("part_fired", "player", {"slot": "utility_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 0, "다른 슬롯이 발동하면 반응하지 않는다")
	Engine.dispatch(_event("part_fired", "player", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 5, "숙주가 발동하면 반응한다")

func _test_max_fires(t: RefCounted) -> void:
	# 스펙 §6.2 — 전투당 n회
	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "max_fires": 2, "do": [{"op": "gain_material", "amount": 1}]}
	])
	for i: int in 5:
		Engine.dispatch(_event("part_fired", "player", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 2, "max_fires 2면 전투당 2회만")
	t.eq(_own.get_part("utility_1").trigger_fires[0], 2, "카운터가 2에서 멈춘다")

	# max_fires가 없으면 제한 없음
	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "do": [{"op": "gain_material", "amount": 1}]}
	])
	for i: int in 5:
		Engine.dispatch(_event("part_fired", "player", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 5, "max_fires가 없으면 제한 없음")

func _test_accumulator(t: RefCounted) -> void:
	# every_nth_accumulated — 이벤트 필드를 누적해 n의 배수를 새로 넘을 때만
	_setup()
	_give(_own, "utility_1", [
		{"on": "material_gained",
		 "where": {"every_nth_accumulated": {"field": "amount", "n": 10}},
		 "do": [{"op": "gain_resonance", "amount": 1}]}
	])
	for i: int in 4:
		Engine.dispatch(_event("material_gained", "player", {"amount": 3}), [_own, _foe], _sim)
	# 누적 3, 6, 9, 12 — 12에서 처음 10을 넘는다
	t.eq(_own.resonance, 1, "누적 12에서 10의 배수를 처음 넘는다")
	for i: int in 3:
		Engine.dispatch(_event("material_gained", "player", {"amount": 3}), [_own, _foe], _sim)
	# 누적 15, 18, 21 — 21에서 20을 넘는다
	t.eq(_own.resonance, 2, "누적 21에서 20을 넘는다")

	# 조건이 거짓이어도 누적은 계속된다
	t.eq(_own.get_part("utility_1").trigger_accum[0], 21, "누적값은 계속 쌓인다")

func _test_chain_depth(t: RefCounted) -> void:
	# 깊이 상한을 넘으면 chain_capped를 남기고 멈춘다
	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "do": [{"op": "gain_material", "amount": 1}]}
	])
	var deep: Dictionary = _event("part_fired", "player",
		{"slot": "weapon_1", "chain_depth": K.MAX_CHAIN_DEPTH})
	Engine.dispatch(deep, [_own, _foe], _sim)
	t.eq(_own.material, 0, "깊이 상한에서는 실행하지 않는다")
	t.eq(_sim.of_type("chain_capped").size(), 1, "chain_capped 이벤트")
	t.eq(_sim.of_type("chain_capped")[0]["slot"], "utility_1", "어느 파츠에서 끊겼는지 실린다")

	# 상한 아래에서는 다음 깊이가 sim에 설정된다
	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "do": [{"op": "gain_material", "amount": 1}]}
	])
	Engine.dispatch(_event("part_fired", "player", {"slot": "weapon_1", "chain_depth": 3}),
		[_own, _foe], _sim)
	t.eq(_sim.of_type("material_gained")[0]["chain_depth"], 4,
		"트리거가 낳은 이벤트는 깊이가 1 깊다")

func _test_broken_parts_silent(t: RefCounted) -> void:
	# 스펙 §8 — 파손 파츠는 효과가 정지한다. 붙어 있던 Augment도 함께.
	_setup()
	_give(_own, "utility_1", [
		{"on": "part_fired", "do": [{"op": "gain_material", "amount": 3}]}
	])
	_own.get_part("utility_1").broken = true
	Engine.dispatch(_event("part_fired", "player", {"slot": "weapon_1"}), [_own, _foe], _sim)
	t.eq(_own.material, 0, "파손 파츠의 트리거는 발동하지 않는다")

func _test_relic_triggers(t: RefCounted) -> void:
	# Relic은 슬롯을 차지하지 않는 함선 수준 트리거 보유자다 (스펙 §9.4)
	_setup()
	_own.relic_triggers = [
		{"on": "resonance_gained", "do": [{"op": "accelerate",
			"target": "all_own_active", "duration": 2.0}]}
	]
	_own.relic_trigger_fires = [0]
	Engine.dispatch(_event("resonance_gained", "player", {"amount": 1}), [_own, _foe], _sim)
	for p: RefCounted in _own.parts:
		t.eq(p.accel_ticks, 40, "%s가 Relic 트리거로 가속된다" % p.slot_id)
```

`FakeSim`에 `rng` 필드가 필요하다 — 트리거 엔진이 ctx를 만들 때 넘긴다.

- [ ] **Step 2: `tests/fake_sim.gd`에 `rng` 필드를 추가한다**

`var tick: int = 0` 아래에 추가:

```gdscript
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var chain_depth: int = 0
```

그리고 `emit`에서 `ev["t"] = ...` 아래에 추가:

```gdscript
	ev["chain_depth"] = chain_depth
```

- [ ] **Step 3: 러너에 `"res://tests/unit/test_trigger_engine.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/trigger_engine.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 4: 구현한다**

`sim/trigger_engine.gd`:

```gdscript
extends RefCounted
## 이벤트 하나를 양측 모든 파츠의 트리거에 매칭하고 실행한다. 스펙 §6.2 §4.6.
##
## 순회 순서는 고정이다 — ships 배열 순서 → 함선의 파츠 순서(= 슬롯 정의 순서) →
## 파츠의 트리거 순서. 결정론 계약(스펙 §4.3)이 이 순서에 의존한다.

const K = preload("res://sim/sim_const.gd")
const Actions = preload("res://sim/actions.gd")
const Conditions = preload("res://sim/conditions.gd")

## ships는 [player, enemy] 순서. sim은 emit/force_fire/schedule/rng/chain_depth를 제공한다.
static func dispatch(event: Dictionary, ships: Array, sim: RefCounted) -> void:
	var depth: int = int(event.get("chain_depth", 0))
	for i: int in ships.size():
		var ship: RefCounted = ships[i]
		var foe: RefCounted = ships[1 - i] if ships.size() == 2 else null

		# Relic 트리거 — 슬롯을 차지하지 않는 함선 수준 보유자 (스펙 §9.4)
		_run_list(ship.relic_triggers, ship.relic_trigger_fires, ship.relic_trigger_accum,
			null, ship, foe, event, depth, sim)

		for part: RefCounted in ship.parts:
			# 파손 파츠는 효과가 정지한다. 붙어 있던 Augment 트리거도 함께 (스펙 §8).
			if part.broken:
				continue
			_run_list(part.triggers, part.trigger_fires, part.trigger_accum,
				part, ship, foe, event, depth, sim)

static func _run_list(triggers: Array, fires: Array, accums: Variant,
		owner: RefCounted, ship: RefCounted, foe: RefCounted,
		event: Dictionary, depth: int, sim: RefCounted) -> void:
	for index: int in triggers.size():
		var trigger: Dictionary = triggers[index]
		if not _matches(trigger, ship, event):
			continue

		var max_fires: int = int(trigger.get("max_fires", -1))
		if max_fires >= 0 and int(fires[index]) >= max_fires:
			continue

		# where가 Dictionary가 아닐 수 있다(작성 실수). Dictionary로 타입 지정해 바로
		# 대입하면 SCRIPT ERROR가 난다 — 안전하게 강제한 뒤 .has()를 쓴다.
		# Conditions.evaluate에는 원본을 그대로 넘겨 그쪽의 fail-closed가 작동하게 둔다.
		var raw_where: Variant = trigger.get("where", {})
		var where: Dictionary = raw_where if raw_where is Dictionary else {}
		var accum_prev: int = 0
		var accum: int = 0
		if accums != null and where.has("every_nth_accumulated"):
			var spec: Dictionary = where["every_nth_accumulated"]
			var field: String = str(spec.get("field", "amount"))
			accum_prev = int(accums[index])
			accum = accum_prev + int(event.get(field, 0))
			# 조건이 거짓이어도 누적은 계속된다 — 이벤트 스트림의 러닝 토탈이기 때문이다
			accums[index] = accum

		# source_part는 이벤트가 난 함선에서 찾아야 한다.
		# 양쪽 함선이 같은 Frame을 쓰면 슬롯 이름이 동일하므로(core, weapon_1, ...),
		# 트리거 소유자의 함선에서 찾으면 적함 이벤트에 대해 크래시도 null도 아닌
		# "자기 함선의 엉뚱한 파츠"를 조용히 집는다.
		var event_ship: RefCounted = ship if str(event.get("ship", "")) == ship.side else foe
		var source_part: RefCounted = null
		if event_ship != null and event.has("slot"):
			source_part = event_ship.get_part(str(event["slot"]))

		var ctx: Dictionary = {
			"sim": sim, "own_ship": ship, "enemy_ship": foe, "part": owner,
			"event": event, "tick": sim.tick, "rng": sim.rng,
			"source_part": source_part,
			"accum": accum, "accum_prev": accum_prev,
			"damage_mult": 1.0,
		}
		if not Conditions.evaluate(raw_where, ctx):
			continue

		# 스펙 §4.6 — 깊이 상한을 넘으면 실행하지 않고 흔적을 남긴다
		if depth + 1 > K.MAX_CHAIN_DEPTH:
			sim.emit("chain_capped", ship.side, {
				"slot": owner.slot_id if owner != null else "relic",
				"part_id": owner.part_id if owner != null else "relic",
				"depth": depth,
			})
			continue

		fires[index] = int(fires[index]) + 1
		var restore_depth: int = sim.chain_depth
		sim.chain_depth = depth + 1
		Actions.run_block(trigger.get("do", []), ctx)
		sim.chain_depth = restore_depth

static func _matches(trigger: Dictionary, ship: RefCounted, event: Dictionary) -> bool:
	if str(trigger.get("on", "")) != str(event.get("type", "")):
		return false
	# 기본 범위는 자함이다. enemy_ship을 명시한 트리거만 적함 이벤트를 본다 —
	# 이 기본값이 없으면 모든 파츠가 적의 모든 이벤트에 반응해 체인이 폭발한다.
	var raw_where: Variant = trigger.get("where", {})
	var where: Dictionary = raw_where if raw_where is Dictionary else {}
	if str(event.get("ship", "")) != ship.side and not where.has("enemy_ship"):
		return false
	return true
```

- [ ] **Step 5: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

- [ ] **Step 6: 커밋**

```bash
git add sim/trigger_engine.gd tests/ && git commit -m "feat(sim): trigger engine with own-ship default scoping

기본 범위는 자함이다 — enemy_ship을 명시한 트리거만 적함 이벤트를 본다.
이 기본값이 없으면 모든 파츠가 적의 모든 이벤트에 반응해 체인이 폭발한다.
순회 순서(함선 -> 슬롯 -> 트리거)는 고정이며 결정론 계약이 여기에 의존한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 12: 전투 시뮬레이션 — 틱 루프와 결정론

**Files:**
- Create: `sim/combat_sim.gd`
- Create: `sim/data/test_builds/fx_slow.json`
- Create: `tests/unit/test_combat_sim.gd`
- Modify: `tests/run_unit.gd`

스펙 §4.4의 틱 순서를 그대로 구현한다. 이 태스크가 끝나면 0a의 목표 — **결정론이 증명된 전투 엔진** — 이 달성된다.

- [ ] **Step 1: 두 번째 테스트 빌드를 쓴다**

적수가 있어야 전투가 성립한다. `sim/data/test_builds/fx_slow.json`:

```json
{
  "id": "fx_slow",
  "frame": "standard_frame",
  "relic": null,
  "slots": {
    "core":      { "part": "fx_core" },
    "weapon_1":  { "part": "fx_gun" },
    "defense_1": { "part": "fx_medic" },
    "utility_1": { "part": "fx_turbine" }
  },
  "links": []
}
```

빈 슬롯이 허용되는지도 함께 확인하는 빌드다 (Core만 필수 — Task 7).

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`tests/unit/test_combat_sim.gd`:

```gdscript
extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")
const BuildLoader = preload("res://sim/build_loader.gd")
const CombatSim = preload("res://sim/combat_sim.gd")

func _catalog() -> RefCounted:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/fixtures.json")
	c.load_frame("res://sim/data/frames/standard_frame.json")
	return c

func _sim(player_build: String, enemy_build: String, seed_value: int) -> RefCounted:
	var catalog: RefCounted = _catalog()
	var loader: RefCounted = BuildLoader.new()
	var p: RefCounted = loader.assemble(
		loader.load_build("res://sim/data/test_builds/%s.json" % player_build), catalog, "player")
	var e: RefCounted = loader.assemble(
		loader.load_build("res://sim/data/test_builds/%s.json" % enemy_build), catalog, "enemy")
	var sim: RefCounted = CombatSim.new()
	sim.setup(p, e, seed_value)
	return sim

func _fingerprint(events: Array) -> String:
	var parts: PackedStringArray = []
	for ev: Dictionary in events:
		var keys: Array = ev.keys()
		keys.sort()
		var line: String = ""
		for key: String in keys:
			line += "%s=%s;" % [key, str(ev[key])]
		parts.append(line)
	return "\n".join(parts)

func run(t: RefCounted) -> void:
	_test_runs_to_completion(t)
	_test_tick_order(t)
	_test_rate_cap_in_loop(t)
	_test_threshold_destruction(t)
	_test_cost_blocking(t)
	_test_scheduled_actions(t)
	_test_determinism(t)
	t.done()

func _test_runs_to_completion(t: RefCounted) -> void:
	var sim: RefCounted = _sim("fx_basic", "fx_slow", 1)
	var events: Array = sim.run()
	t.check(sim.finished, "전투가 끝난다")
	t.check(events.size() > 0, "이벤트가 방출된다")
	t.eq(events[0]["type"], "combat_start", "첫 이벤트는 combat_start")
	t.eq(events[events.size() - 1]["type"], "combat_end", "마지막 이벤트는 combat_end")
	t.check(["player", "enemy", "draw"].has(sim.winner), "승자가 정해진다: %s" % sim.winner)
	t.check(sim.tick <= K.MAX_COMBAT_TICKS, "시간 상한을 넘지 않는다")

	# combat_start 트리거가 실제로 작동한다 (fx_core: 시작 시 자재 +5)
	var gains: Array = []
	for ev: Dictionary in events:
		if ev["type"] == "material_gained" and ev["ship"] == "player":
			gains.append(ev)
	t.check(gains.size() > 0, "combat_start 트리거가 자재를 준다")

func _test_tick_order(t: RefCounted) -> void:
	# 스펙 §4.4 — 파츠가 쿨타임대로 발동한다. fx_gun은 쿨타임 2초 = 40틱.
	var sim: RefCounted = _sim("fx_basic", "fx_slow", 1)
	sim.run()
	var first_fire: Dictionary = {}
	for ev: Dictionary in sim.log:
		if ev["type"] == "part_fired" and ev["ship"] == "player" and ev["slot"] == "weapon_2":
			first_fire = ev
			break
	t.check(not first_fire.is_empty(), "weapon_2가 발동한다")
	t.near(first_fire["t"], 2.0, "쿨타임 2초 파츠는 2.0초에 처음 발동한다", 0.001)

	# weapon_1은 augment로 cooldown_mult 0.5가 걸려 1초
	var w1_fire: Dictionary = {}
	for ev: Dictionary in sim.log:
		if ev["type"] == "part_fired" and ev["ship"] == "player" and ev["slot"] == "weapon_1":
			w1_fire = ev
			break
	t.near(w1_fire["t"], 1.0, "cooldown_mult 0.5가 걸린 파츠는 1.0초에 발동한다", 0.001)

func _test_rate_cap_in_loop(t: RefCounted) -> void:
	# 스펙 §4.2 — 어떤 파츠도 초당 5회를 넘지 못한다
	var sim: RefCounted = _sim("fx_basic", "fx_slow", 5)
	sim.run()
	var last_tick: Dictionary = {}   # "ship/slot" -> tick
	for ev: Dictionary in sim.log:
		if ev["type"] != "part_fired":
			continue
		var key: String = "%s/%s" % [ev["ship"], ev["slot"]]
		var tick: int = K.secs_to_ticks(float(ev["t"]))
		if last_tick.has(key):
			t.check(tick - int(last_tick[key]) >= K.MIN_FIRE_TICKS,
				"%s가 발동 상한을 지킨다 (%d틱 간격)" % [key, tick - int(last_tick[key])])
		last_tick[key] = tick

	# 체인이 폭주하지 않았다
	t.eq(sim.count_events("chain_capped"), 0, "chain_capped가 발생하지 않는다")

func _test_threshold_destruction(t: RefCounted) -> void:
	# 스펙 §8 — 파괴선을 넘으면 파괴 가능한 파츠 하나가 무작위로 파손된다.
	# 전투가 알아서 파괴선까지 가기를 기대하지 않는다 — 픽스처 밸런스에 의존하는
	# 테스트는 수치를 만질 때마다 깨진다. 직접 선체를 깎아 상황을 만든다.
	var sim: RefCounted = _sim("fx_basic", "fx_slow", 11)
	sim.setup_ready()
	sim.player.take_damage(120)   # 200 -> 80 = 40%, 75선과 50선을 함께 넘는다
	sim.step()

	var crossings: Array = []
	var threshold_breaks: Array = []
	for ev: Dictionary in sim.log:
		if ev["type"] == "threshold_crossed" and ev["ship"] == "player":
			crossings.append(ev)
		if ev["type"] == "part_destroyed" and ev["ship"] == "player" \
				and ev["cause"] == "threshold":
			threshold_breaks.append(ev)

	t.eq(crossings.size(), 2, "한 번의 피해로 두 선을 넘으면 두 번 작동한다")
	t.eq(threshold_breaks.size(), 2, "파괴선 하나당 파츠 하나가 파손된다")
	for ev: Dictionary in threshold_breaks:
		t.check(ev["slot"] != "core", "Core는 파괴선 대상이 아니다")

	# 같은 선은 두 번 작동하지 않는다.
	# 적함도 파괴선을 넘을 수 있으므로 플레이어 것만 센다.
	sim.player.repair(200)
	sim.step()
	sim.player.take_damage(120)   # 다시 40%
	sim.step()
	var after: Array = []
	for ev: Dictionary in sim.log:
		if ev["type"] == "threshold_crossed" and ev["ship"] == "player":
			after.append(ev)
	t.eq(after.size(), 2, "수리 후 재하강해도 이미 통과한 선은 작동하지 않는다")

	# 후보가 하나도 없으면 파손 없이 통과만 기록된다
	var sim2: RefCounted = _sim("fx_basic", "fx_slow", 12)
	sim2.setup_ready()
	for part: RefCounted in sim2.player.parts:
		part.broken = true
	sim2.player.take_damage(60)   # 200 -> 140 = 70%, 75선 통과
	sim2.step()
	var empty_crossings: Array = []
	for ev: Dictionary in sim2.log:
		if ev["type"] == "threshold_crossed" and ev["ship"] == "player":
			empty_crossings.append(ev)
	t.eq(empty_crossings.size(), 1, "후보가 없어도 통과 자체는 기록된다")
	t.eq(empty_crossings[0]["destroyed_slot"], "", "파손된 슬롯이 없으면 빈 문자열")

func _test_cost_blocking(t: RefCounted) -> void:
	# fx_medic은 자재 3을 요구한다. 자재가 없으면 불발되고 흔적을 남긴다.
	var sim: RefCounted = _sim("fx_basic", "fx_slow", 2)
	sim.run()
	var blocked: Array = []
	for ev: Dictionary in sim.log:
		if ev["type"] == "part_fire_blocked" and ev["reason"] == "no_material":
			blocked.append(ev)
	t.check(blocked.size() > 0, "자재 부족 불발이 이벤트로 남는다")
	for ev: Dictionary in blocked:
		t.eq(ev["slot"], "defense_1", "불발한 것은 비용이 있는 파츠")

func _test_scheduled_actions(t: RefCounted) -> void:
	# delay 예약이 실제로 나중 틱에 실행된다
	var sim: RefCounted = _sim("fx_basic", "fx_slow", 3)
	sim.setup_ready()
	var target: RefCounted = sim.player.get_part("weapon_2")
	target.broken = true
	sim.schedule(K.secs_to_ticks(1.0), {"op": "restore_part", "target": "self"},
		{"sim": sim, "own_ship": sim.player, "enemy_ship": sim.enemy,
		 "part": target, "rng": sim.rng, "event": {}, "tick": 0, "damage_mult": 1.0},
		{"self": [target]})
	for i: int in 19:
		sim.step()
	t.check(target.broken, "19틱 뒤에는 아직 실행되지 않는다")
	sim.step()
	t.check(not target.broken, "20틱(1초) 뒤에 실행된다")

func _test_determinism(t: RefCounted) -> void:
	# 스펙 §4.3 — 같은 빌드 + 같은 시드 = 완전히 같은 이벤트 스트림
	for seed_value: int in [1, 42, 12345]:
		var a: String = _fingerprint(_sim("fx_basic", "fx_slow", seed_value).run())
		var b: String = _fingerprint(_sim("fx_basic", "fx_slow", seed_value).run())
		t.eq(a.length(), b.length(), "시드 %d — 스트림 길이가 같다" % seed_value)
		t.check(a == b, "시드 %d — 이벤트 스트림이 완전히 같다" % seed_value)

	# 다른 시드는 다른 결과를 낸다 (RNG가 실제로 쓰이고 있다는 증거)
	var s1: String = _fingerprint(_sim("fx_basic", "fx_slow", 1).run())
	var s2: String = _fingerprint(_sim("fx_basic", "fx_slow", 999).run())
	t.check(s1 != s2, "다른 시드는 다른 스트림을 낸다")
```

- [ ] **Step 3: 러너에 `"res://tests/unit/test_combat_sim.gd",`를 추가하고 실행해서 실패를 확인**

Run:
```bash
bash tests/run.sh; echo "EXIT=$?"
```
Expected: `sim/combat_sim.gd` 없음으로 파싱 에러, `EXIT=1`

- [ ] **Step 4: 구현한다**

`sim/combat_sim.gd`:

```gdscript
extends RefCounted
## 전투 1판. 스펙 §4.
##
## 이 클래스가 actions.gd·trigger_engine.gd가 기대하는 sim 인터페이스를 제공한다:
##   emit / force_fire / schedule / tick / rng / chain_depth
##
## 시간은 전부 정수 틱이다. 부동소수는 이벤트의 t 필드를 만들 때만 등장한다.

const K = preload("res://sim/sim_const.gd")
const Actions = preload("res://sim/actions.gd")
const TriggerEngine = preload("res://sim/trigger_engine.gd")

var player: RefCounted
var enemy: RefCounted
var rng: RandomNumberGenerator
var seed_value: int = 0

var tick: int = 0
var chain_depth: int = 0
var finished: bool = false
var winner: String = ""

## 전체 이벤트 스트림. 소비자(tests/, debug/)가 읽는 유일한 것이다.
var log: Array = []
## 아직 트리거에 전달되지 않은 이벤트
var _pending: Array = []
## delay 예약 [{at:int, action:Dictionary, ctx:Dictionary, resolved:Dictionary}]
var _scheduled: Array = []

func setup(player_ship: RefCounted, enemy_ship: RefCounted, combat_seed: int) -> void:
	player = player_ship
	enemy = enemy_ship
	seed_value = combat_seed
	rng = RandomNumberGenerator.new()
	rng.seed = combat_seed

## combat_start를 방출하고 그 체인까지 소진한다. 틱 루프 진입 직전 상태를 만든다.
func setup_ready() -> void:
	emit("combat_start", "player", {
		"player_build": player.build_id, "enemy_build": enemy.build_id, "seed": seed_value,
	})
	_drain_chain()

## 전투 전체를 돌리고 이벤트 스트림을 돌려준다.
func run() -> Array:
	setup_ready()
	while not finished and tick < K.MAX_COMBAT_TICKS:
		step()
	if not finished:
		_finish_by_timeout()
	return log

## 스펙 §4.4의 틱 순서를 그대로 따른다.
func step() -> void:
	if finished:
		return
	tick += 1

	# 1~2. 쿨타임 진행 + 지속 효과 만료 (파손 파츠는 둘 다 멈춘다)
	for ship: RefCounted in [player, enemy]:
		for part: RefCounted in ship.parts:
			part.advance()

	# 2.5. delay 예약 실행 — 시간 기반이므로 발동보다 먼저
	_run_scheduled()

	# 3. 발동 — 양측 후보를 모두 모은 뒤 슬롯 순서로 해소한다 (선공 편향 방지)
	var candidates: Array = []
	for ship: RefCounted in [player, enemy]:
		for part: RefCounted in ship.parts:
			if part.is_ready():
				candidates.append({"part": part, "ship": ship})
	for candidate: Dictionary in candidates:
		_fire(candidate["part"], candidate["ship"], "cooldown")

	# 4. 체인 소진
	_drain_chain()

	# 5. 지속 피해/회복
	for ship: RefCounted in [player, enemy]:
		var effects: Dictionary = ship.advance_effects(tick)
		if int(effects["regen"]) > 0:
			emit("regen_ticked", ship.side, {"amount": effects["regen"]})
		if int(effects["overheat"]) > 0:
			emit("overheat_ticked", ship.side,
				{"damage": effects["overheat"], "stacks": ship.overheat_stacks})
	_drain_chain()

	# 6. 파괴선 검사
	for ship: RefCounted in [player, enemy]:
		_check_thresholds(ship)
	_drain_chain()

	# 7. 승패 판정
	_check_end()

# --- sim 인터페이스 (actions.gd / trigger_engine.gd가 부른다) ---

func emit(type: String, ship_side: String, fields: Dictionary) -> void:
	var event: Dictionary = fields.duplicate()
	event["type"] = type
	event["ship"] = ship_side
	event["t"] = K.ticks_to_secs(tick)
	event["chain_depth"] = chain_depth
	log.append(event)
	_pending.append(event)

func schedule(delay_ticks: int, action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	_scheduled.append({
		"at": tick + maxi(0, delay_ticks),
		"action": action, "ctx": ctx, "resolved": resolved,
	})

## 체인이 요청한 강제 발동. 발동 상한과 비용 검사를 똑같이 거친다 (스펙 §4.2).
func force_fire(part: RefCounted, ship: RefCounted, cause: String) -> void:
	_fire(part, ship, cause)

func count_events(type: String) -> int:
	var total: int = 0
	for event: Dictionary in log:
		if event["type"] == type:
			total += 1
	return total

# --- 내부 ---

func _other(ship: RefCounted) -> RefCounted:
	return enemy if ship == player else player

func _fire(part: RefCounted, ship: RefCounted, cause: String) -> void:
	var foe: RefCounted = _other(ship)

	var reason: String = part.block_reason(tick)
	if reason == "" and not ship.can_afford(part.cost):
		reason = "no_material"
	if reason != "":
		emit("part_fire_blocked", ship.side,
			{"slot": part.slot_id, "part_id": part.part_id, "reason": reason})
		return

	var cost: int = int(part.cost.get("material", 0))
	if cost > 0:
		ship.spend_material(cost)
		emit("material_spent", ship.side, {
			"slot": part.slot_id, "amount": cost, "total": ship.material, "sink": "cost",
		})

	var damage_mult: float = part.take_empower()
	part.consume_fire(tick)

	emit("part_fired", ship.side, {
		"slot": part.slot_id, "part_id": part.part_id, "part_name": part.part_name,
		"faction": part.faction, "cause": cause,
	})
	if part.is_limited():
		emit("fires_changed", ship.side, {
			"slot": part.slot_id, "delta": -1,
			"remaining": part.fires_remaining, "cause": "fired",
		})

	# 공명 기본 규칙: 행동 누적 → 공명 (스펙 §7.2)
	if ship.register_fire_for_resonance() > 0:
		emit("resonance_gained", ship.side,
			{"amount": 1, "total": ship.resonance, "source": "fires_accumulated"})
	_check_convergence(ship, part)

	Actions.run_block(part.on_fire, {
		"sim": self, "own_ship": ship, "enemy_ship": foe, "part": part,
		"rng": rng, "event": {}, "tick": tick, "damage_mult": damage_mult,
	})

	# 스펙 §4.5 — 이번 발동으로 0이 되었으면 효과를 실행한 뒤 파손된다
	if part.fires_remaining == 0:
		Actions.break_part(part, ship, "fires_exhausted", self)

## convergence_engine Relic — 서로 다른 팩션이 연속 발동하면 공명 +1 (최소 간격 있음)
func _check_convergence(ship: RefCounted, part: RefCounted) -> void:
	if ship.convergence_gap_ticks > 0 \
			and ship.last_fire_faction != "" \
			and ship.last_fire_faction != part.faction \
			and tick - ship.last_convergence_tick >= ship.convergence_gap_ticks:
		ship.gain_resonance(1)
		ship.last_convergence_tick = tick
		emit("resonance_gained", ship.side,
			{"amount": 1, "total": ship.resonance, "source": "convergence_engine"})
	ship.last_fire_faction = part.faction

func _drain_chain() -> void:
	while not _pending.is_empty():
		var event: Dictionary = _pending.pop_front()
		chain_depth = int(event.get("chain_depth", 0))
		TriggerEngine.dispatch(event, [player, enemy], self)
	chain_depth = 0

func _run_scheduled() -> void:
	if _scheduled.is_empty():
		return
	var due: Array = []
	var kept: Array = []
	for entry: Dictionary in _scheduled:
		if int(entry["at"]) <= tick:
			due.append(entry)
		else:
			kept.append(entry)
	_scheduled = kept
	for entry: Dictionary in due:
		var ctx: Dictionary = entry["ctx"]
		ctx["tick"] = tick
		Actions.apply(entry["action"], ctx, entry["resolved"])

func _check_thresholds(ship: RefCounted) -> void:
	for threshold: Variant in ship.newly_crossed_thresholds():
		var pool: Array = ship.destructible_parts()
		var destroyed_slot: String = ""
		if not pool.is_empty():
			var victim: RefCounted = pool[rng.randi_range(0, pool.size() - 1)]
			destroyed_slot = victim.slot_id
			Actions.break_part(victim, ship, "threshold", self)
		emit("threshold_crossed", ship.side,
			{"threshold": threshold, "destroyed_slot": destroyed_slot})

func _check_end() -> void:
	var player_dead: bool = player.hull <= 0
	var enemy_dead: bool = enemy.hull <= 0
	if not (player_dead or enemy_dead):
		return
	if player_dead and enemy_dead:
		winner = "draw"
	elif enemy_dead:
		winner = "player"
	else:
		winner = "enemy"
	_finish("hull")

func _finish_by_timeout() -> void:
	var player_ratio: float = player.hull_ratio()
	var enemy_ratio: float = enemy.hull_ratio()
	if player_ratio > enemy_ratio:
		winner = "player"
	elif enemy_ratio > player_ratio:
		winner = "enemy"
	else:
		winner = "draw"
	_finish("timeout")

func _finish(reason: String) -> void:
	finished = true
	emit("combat_end", "player", {
		"winner": winner, "elapsed": K.ticks_to_secs(tick), "reason": reason,
	})
	_pending.clear()
	_scheduled.clear()
```

- [ ] **Step 5: 실행해서 통과하는지 확인**

Run: 위와 동일
Expected: `failures: 0` / `ALL PASS` / `EXIT=0`

만약 `_test_cost_blocking`이나 `_test_threshold_destruction`이 실패하면, 픽스처 수치가 그 상황을 만들어내지 못한 것이다 — 엔진 버그가 아니다. `sim/data/test_parts/fixtures.json`의 `fx_gun` 피해량을 올리거나(파괴선 도달) `fx_medic`의 `cost.material`을 올려서(자재 부족) 상황을 만들고, **테스트가 아니라 픽스처를 고친다.**

- [ ] **Step 6: 전체 테스트를 다시 돌려 회귀가 없는지 확인**

Run: 위와 동일
Expected: 12개 모듈 전부 통과, `ALL PASS`, `EXIT=0`

- [ ] **Step 7: 커밋**

```bash
git add sim/combat_sim.gd sim/data/ tests/ && git commit -m "feat(sim): combat tick loop with proven determinism

스펙 4.4절의 틱 순서 그대로. 발동 단계는 양측 후보를 모두 모은 뒤 슬롯 순서로
해소해 선공 편향을 없앤다. 같은 빌드 + 같은 시드가 완전히 같은 이벤트 스트림을
낸다는 것을 시드 3종으로 검증한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Phase 0a 완료 확인

전체 단위 테스트가 통과하면 0a는 끝이다.

```bash
bash tests/run.sh; echo "EXIT=$?"
```

스펙 §12가 요구한 단위 검증 항목이 전부 덮였는지 대조한다:

| 스펙 §12의 요구 | 태스크 |
|---|---|
| 파츠 개별 효과 | Task 10 |
| 트리거 매칭 | Task 11 |
| 조건 평가 | Task 9 |
| 대상 셀렉터 | Task 8 |
| 발동 상한 0.2초 | Task 3 (단위) + Task 12 (루프 안에서) |
| 발동 횟수 소진 파손 | Task 4, Task 10 |
| 파괴 불가 유예 | Task 4, Task 10 |
| 가속·둔화 상쇄 | Task 3 |
| 파괴선 통과(1선/2선 동시) | Task 6, Task 12 |
| 보강 소모 | Task 4, Task 10 |
| 파손·복구 | Task 4, Task 10 |
| 자재 부족 시 불발 | Task 12 |
| 공명 누적 규칙 | Task 6, Task 12 |
| 빌드 검증 실패 케이스 | Task 7 |
| 결정론 | Task 12 |

**다음 계획: Phase 0b — 콘텐츠와 계측.** 실제 파츠 18종 + Relic 3종 + 적 6종, 순수/혼종 빌드, 배치 러너와 검증 지표 5종, Trigger Chain 디버그 뷰. 0a의 이벤트 계약 위에서만 작동하므로 sim 코어는 더 이상 건드리지 않는다.
