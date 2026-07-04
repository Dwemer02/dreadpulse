# DREADPULSE Phase 0 전투 시뮬레이터 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 심박 펄스 기반 결정론적 1:1 자동 전투 시뮬레이터를 구현하고, GDD 검증 지표 3종(지수 곡선·촉수 추월·자원 고갈)을 자동 리포트로 확인한다.

**Architecture:** `res://sim/`에 씬 비의존 순수 로직(RefCounted), `res://tests/`에 헤드리스 assert 러너와 배치 통계 러너, `res://debug/`에 이벤트 스트림만 소비하는 시각화 씬. 스펙: `docs/superpowers/specs/2026-07-04-dreadpulse-phase0-design.md`.

**Tech Stack:** Godot 4.6 / GDScript only. 외부 테스트 프레임워크 없음(SceneTree 스크립트 + assert 헬퍼).

## Global Constraints

- 네이밍은 GDD 부록 A 강제: `heart`, `pulse_interval`, `pulse`, `charge`, `steam`, `ammo`, `ichor`, `hull`, `graft` 등.
- `sim/`은 Node/씬/Engine 싱글톤(시간·입력·렌더) 참조 금지. 모든 클래스 `extends RefCounted`.
- **class_name을 쓰지 않는다.** 헤드리스 실행 시 전역 클래스 캐시 스테일 문제를 피하기 위해 모든 참조는 `const X := preload("res://sim/x.gd")` 방식.
- 확률은 주입된 `RandomNumberGenerator`만 사용. `randf()` 등 전역 RNG 금지.
- `TICK_DT = 0.05`, `MAX_TIME = 300.0` (combat_sim.gd 상수).
- 밸런스 수치는 전부 플레이스홀더 — 스펙 §4의 값을 그대로 쓴다.
- 각 태스크 종료 시 커밋. 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- 테스트 실행 명령(PowerShell, 프로젝트 루트에서):
  ```powershell
  $godot = Get-Content tests/out/godot_path.txt
  & $godot --headless --path . --script res://tests/run_unit.gd
  ```
  종료 코드 0 = 전부 통과. GDScript 파스 에러도 콘솔에 찍히므로 출력 전체를 확인할 것.
- **GDScript 람다 주의:** 람다는 지역 변수를 값으로 캡처한다. 카운터·상태는 반드시 Dictionary/Array에 담아 내용을 변경할 것(재할당은 반영 안 됨).

---

### Task 1: 테스트 하니스 + Godot 실행 경로 확보

**Files:**
- Create: `tests/run_unit.gd`
- Create: `tests/out/godot_path.txt` (gitignore 대상 — `tests/out/`은 이미 ignore됨)

**Interfaces:**
- Produces: `check(cond: bool, label: String)` assert 헬퍼, `_run_all()`에 태스크별 테스트 함수를 추가하는 패턴. 이후 모든 태스크가 이 파일에 `_test_*` 함수를 추가한다.

- [ ] **Step 1: Godot 실행 파일 경로 확보**

Godot 에디터가 MCP로 연결되어 있다. `execute_editor_script`로:
```
_mcp_print(OS.get_executable_path())
```
반환된 경로를 `tests/out/godot_path.txt`에 저장한다(디렉토리 생성 포함):
```powershell
New-Item -ItemType Directory -Force tests/out | Out-Null
Set-Content -Encoding utf8 tests/out/godot_path.txt "<반환된 경로>"
```
MCP가 안 붙어 있으면 `Get-ChildItem "$env:LOCALAPPDATA","C:\Program Files" -Recurse -Filter "Godot*.exe" -ErrorAction SilentlyContinue`로 탐색.

- [ ] **Step 2: 실행 검증**

```powershell
$godot = Get-Content tests/out/godot_path.txt
& $godot --version
```
Expected: `4.6.x` 버전 문자열. 출력이 안 보이면 같은 폴더의 `*_console.exe`(콘솔 래퍼)를 대신 godot_path.txt에 기록.

- [ ] **Step 3: 러너 골격 작성**

`tests/run_unit.gd`:
```gdscript
extends SceneTree
# DREADPULSE Phase 0 단위 검증 러너.
# 실행: & $godot --headless --path . --script res://tests/run_unit.gd

var _pass := 0
var _fail := 0

func _init() -> void:
	_run_all()
	print("unit result: %d passed / %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_all() -> void:
	_test_harness()

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + label)

func _test_harness() -> void:
	check(true, "harness boots")
```

- [ ] **Step 4: 실행해 통과 확인**

```powershell
$godot = Get-Content tests/out/godot_path.txt
& $godot --headless --path . --script res://tests/run_unit.gd
```
Expected: `unit result: 1 passed / 0 failed`, 종료 코드 0.

- [ ] **Step 5: Commit**

```powershell
git add tests/run_unit.gd
git commit -m "test: headless unit test harness"
```

---

### Task 2: 부품 카탈로그 (parts_catalog.gd)

**Files:**
- Create: `sim/parts_catalog.gd`
- Modify: `tests/run_unit.gd` (테스트 추가)

**Interfaces:**
- Produces: `Catalog.Effect` enum(18종), `Catalog.PARTS: Dictionary`, `Catalog.GRAFTS: Dictionary`, `static func get_def(type: String, graft: String = "") -> Dictionary` — 실패 시 빈 Dictionary. def 필드: `name, kind("steel"|"bio"|"core"), hull, required_charge, effects: Array[Dictionary], graft_slot: bool(옵션)`.

- [ ] **Step 1: 실패하는 테스트 작성** — `run_unit.gd`에 추가하고 `_run_all()`에 `_test_catalog()` 등록:

```gdscript
const Catalog := preload("res://sim/parts_catalog.gd")

func _test_catalog() -> void:
	var b := Catalog.get_def("boiler")
	check(not b.is_empty(), "boiler exists")
	check(b.kind == "steel" and int(b.required_charge) == 2, "boiler def fields")
	var adr := Catalog.get_def("main_turret", "nerve")
	check(adr.name == "아드레날린 포", "graft substitutes name")
	var has_adr := false
	for e in adr.effects:
		if int(e.type) == Catalog.Effect.INTERVAL_REDUCE_ON_HIT:
			has_adr = true
	check(has_adr, "adrenaline effect present")
	check(Catalog.get_def("no_such_part").is_empty(), "unknown type -> empty")
	check(Catalog.get_def("autoloader", "nerve").is_empty(), "invalid graft -> empty")
	for t in Catalog.PARTS:
		var d: Dictionary = Catalog.PARTS[t]
		check(d.has("kind") and d.has("hull") and d.has("effects"), "part %s complete" % t)
```

- [ ] **Step 2: 실행해 실패 확인**

Run: 위 Global Constraints의 테스트 명령.
Expected: 파스 에러 `Could not preload resource "res://sim/parts_catalog.gd"` — 파일 부재로 실패.

- [ ] **Step 3: 구현** — `sim/parts_catalog.gd` 전체:

```gdscript
extends RefCounted
# 부품 카탈로그: 정적 데이터 + 융합(graft) 치환. 수치는 전부 플레이스홀더(스펙 §4).

enum Effect {
	PRODUCE_RESOURCE,         # {resource, amount} 발동 시 자원 생산
	FIRE_PROJECTILE,          # {damage, cost} 발동 시 발사
	ADJACENT_DAMAGE_BUFF,     # {amount} 인접 무기 피해 가산 (패시브)
	ADJACENT_CHARGE_DISCOUNT, # {amount} 인접 무기 required_charge 감소 (패시브)
	EXTRA_PULSE,              # {cost} 발동 시 심장 기점 즉시 추가 펄스
	ABSORB_ADJACENT_DAMAGE,   # {ratio} 인접 부품 피격 흡수 (패시브)
	PULSE_REPLICATE,          # {chance} 펄스 통과 시 복제 (통과형)
	PERMANENT_STACK_ON_HIT,   # {amount} 적중마다 이번 전투 피해 스택
	PART_TARGETING,           # {priority} 연결 무기에 부품 조준 부여 (패시브)
	DAMAGE_TO_RESOURCE,       # {resource, ratio} 함 피격 피해 일부를 자원으로
	STORE_PULSE,              # {threshold, explode_mult} 펄스 저장, 하류 차단
	SECOND_HEART,             # {interval} 제2 펄스원
	ON_DEATH_EXPLODE,         # {self_damage} 파괴 시 자함 유폭
	INTERVAL_REDUCE_ON_HIT,   # {amount, floor, overload_self_damage} 적중 시 박동 가속
	AMMO_RESERVE,             # {amount} 전투 시작 시 ammo 가산
	ALL_FIRE_ON_THRESHOLD,    # {} 저장 임계 도달 시 연결 포탑 일제사격
	PRODUCE_PER_HIT_TAKEN,    # {resource, per_hit} 피격 횟수 비례 생산 보너스
}

const PARTS: Dictionary = {
	"heart": {"name": "심장", "kind": "core", "hull": 20, "required_charge": 0,
		"effects": []},
	"boiler": {"name": "보일러", "kind": "steel", "hull": 15, "required_charge": 2,
		"graft_slot": true,
		"effects": [{"type": Effect.PRODUCE_RESOURCE, "resource": "steam", "amount": 1}]},
	"main_turret": {"name": "주포탑", "kind": "steel", "hull": 10, "required_charge": 3,
		"graft_slot": true,
		"effects": [{"type": Effect.FIRE_PROJECTILE, "damage": 8,
			"cost": {"steam": 1, "ammo": 1}}]},
	"magazine": {"name": "탄약고", "kind": "steel", "hull": 12, "required_charge": 0,
		"graft_slot": true,
		"effects": [
			{"type": Effect.AMMO_RESERVE, "amount": 15},
			{"type": Effect.ADJACENT_DAMAGE_BUFF, "amount": 2},
			{"type": Effect.ON_DEATH_EXPLODE, "self_damage": 20}]},
	"autoloader": {"name": "자동장전기", "kind": "steel", "hull": 10, "required_charge": 0,
		"effects": [{"type": Effect.ADJACENT_CHARGE_DISCOUNT, "amount": 1}]},
	"steam_turbine": {"name": "증기터빈", "kind": "steel", "hull": 12, "required_charge": 2,
		"effects": [{"type": Effect.EXTRA_PULSE, "cost": {"steam": 3}}]},
	"armor_bulkhead": {"name": "장갑구획", "kind": "steel", "hull": 40, "required_charge": 0,
		"effects": [{"type": Effect.ABSORB_ADJACENT_DAMAGE, "ratio": 0.3}]},
	"ganglion": {"name": "신경절", "kind": "bio", "hull": 8, "required_charge": 0,
		"effects": [{"type": Effect.PULSE_REPLICATE, "chance": 0.25}]},
	"tentacle": {"name": "촉수", "kind": "bio", "hull": 10, "required_charge": 2,
		"effects": [
			{"type": Effect.FIRE_PROJECTILE, "damage": 3, "cost": {}},
			{"type": Effect.PERMANENT_STACK_ON_HIT, "amount": 1}]},
	"eye": {"name": "눈알", "kind": "bio", "hull": 6, "required_charge": 0,
		"effects": [{"type": Effect.PART_TARGETING, "priority": "magazine"}]},
	"gills": {"name": "아가미", "kind": "bio", "hull": 10, "required_charge": 0,
		"effects": [{"type": Effect.DAMAGE_TO_RESOURCE, "resource": "steam", "ratio": 0.5}]},
	"cyst": {"name": "낭포", "kind": "bio", "hull": 12, "required_charge": 0,
		"effects": [{"type": Effect.STORE_PULSE, "threshold": 10, "explode_mult": 3}]},
	"ancillary_heart": {"name": "부심장", "kind": "bio", "hull": 15, "required_charge": 0,
		"effects": [{"type": Effect.SECOND_HEART, "interval": 1.5}]},
}

const GRAFTS: Dictionary = {
	"main_turret+nerve": {"name": "아드레날린 포",
		"effects": [
			{"type": Effect.FIRE_PROJECTILE, "damage": 8, "cost": {"steam": 1, "ammo": 1}},
			{"type": Effect.INTERVAL_REDUCE_ON_HIT, "amount": 0.05, "floor": 0.5,
				"overload_self_damage": 5}]},
	"boiler+gills": {"name": "혈압 보일러",
		"effects": [
			{"type": Effect.PRODUCE_RESOURCE, "resource": "steam", "amount": 1},
			{"type": Effect.PRODUCE_PER_HIT_TAKEN, "resource": "steam", "per_hit": 0.2}]},
	"magazine+cyst": {"name": "유폭 심장",
		"effects": [
			{"type": Effect.STORE_PULSE, "threshold": 6, "explode_mult": 0},
			{"type": Effect.ALL_FIRE_ON_THRESHOLD}]},
}

static func get_def(type: String, graft: String = "") -> Dictionary:
	if not PARTS.has(type):
		return {}
	var def: Dictionary = (PARTS[type] as Dictionary).duplicate(true)
	if graft != "":
		var key := type + "+" + graft
		if not GRAFTS.has(key) or not def.get("graft_slot", false):
			return {}
		var g: Dictionary = GRAFTS[key]
		def["name"] = g["name"]
		def["effects"] = (g["effects"] as Array).duplicate(true)
	return def
```

- [ ] **Step 4: 테스트 통과 확인**

Expected: `unit result: N passed / 0 failed` (N ≥ 19).

- [ ] **Step 5: Commit**

```powershell
git add sim/parts_catalog.gd tests/run_unit.gd
git commit -m "feat(sim): parts catalog with graft substitution"
```

---

### Task 3: 부품 런타임 + 함선 상태 (part.gd, ship_state.gd)

**Files:**
- Create: `sim/part.gd`, `sim/ship_state.gd`
- Modify: `tests/run_unit.gd`

**Interfaces:**
- Consumes: `Catalog.get_def`, `Catalog.Effect`.
- Produces:
  - `Part`(part.gd): `var id/type/graft/def/hull/charge/stored_pulses/stacks/aux_timer`; `func setup(id, type, graft="") -> bool`, `is_destroyed() -> bool`, `base_required_charge() -> int`, `display_name() -> String`, `has_effect(t: int) -> bool`, `get_effect(t: int) -> Dictionary`.
  - `Ship`(ship_state.gd): `var name/hull/start_hull/pulse_interval/time_since_pulse/resources/parts/part_order/adjacency/hits_taken/load_errors`; `func load_build(build: Dictionary) -> bool`, `is_valid() -> bool`, `heart_id() -> String`, `add_resource(res, amount)`, `try_spend(cost: Dictionary) -> bool`, `effective_required_charge(pid: String) -> int`.

- [ ] **Step 1: 실패하는 테스트 작성** — `run_unit.gd`에 추가, `_run_all()`에 `_test_ship()` 등록:

```gdscript
const Ship := preload("res://sim/ship_state.gd")

func _mk_ship(parts: Array, wires: Array, extra: Dictionary = {}):
	var b := {"name": "test", "parts": parts, "wires": wires}
	b.merge(extra)
	var s = Ship.new()
	s.load_build(b)
	return s

func _test_ship() -> void:
	var s = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "mag", "type": "magazine"},
		 {"id": "t1", "type": "main_turret"}, {"id": "al", "type": "autoloader"}],
		[["heart", "t1"], ["mag", "t1"], ["al", "t1"]])
	check(s.is_valid(), "valid build loads: %s" % [s.load_errors])
	check(int(s.resources.ammo) == 35, "ammo = 20 base + 15 reserve")
	check(s.heart_id() == "heart", "heart_id")
	check(s.effective_required_charge("t1") == 2, "autoloader discount 3->2")
	check(s.try_spend({"ammo": 30}) and int(s.resources.ammo) == 5, "spend ok")
	check(not s.try_spend({"steam": 1}), "spend fails on shortage")

	var bad = _mk_ship([{"id": "a", "type": "boiler"}], [])
	check(not bad.is_valid(), "missing heart rejected")
	var orphan = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "b", "type": "boiler"}], [])
	check(not orphan.is_valid(), "orphan part rejected")
	var dup = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "heart", "type": "boiler"}], [])
	check(not dup.is_valid(), "duplicate id rejected")
	var badgraft = _mk_ship(
		[{"id": "heart", "type": "heart"},
		 {"id": "x", "type": "autoloader", "graft": "nerve"}], [["heart", "x"]])
	check(not badgraft.is_valid(), "invalid graft rejected")
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: preload 실패(ship_state.gd 부재).

- [ ] **Step 3: 구현** — `sim/part.gd` 전체:

```gdscript
extends RefCounted
# 부품 런타임 상태.

const Catalog := preload("res://sim/parts_catalog.gd")

var id: String
var type: String
var graft: String = ""
var def: Dictionary = {}
var hull: int = 0
var charge: int = 0
var stored_pulses: int = 0   # STORE_PULSE 저장량
var stacks: int = 0          # PERMANENT_STACK_ON_HIT 누적
var aux_timer: float = 0.0   # SECOND_HEART 타이머

func setup(p_id: String, p_type: String, p_graft: String = "") -> bool:
	var d := Catalog.get_def(p_type, p_graft)
	if d.is_empty():
		return false
	id = p_id
	type = p_type
	graft = p_graft
	def = d
	hull = int(d.get("hull", 10))
	return true

func is_destroyed() -> bool:
	return hull <= 0

func base_required_charge() -> int:
	return int(def.get("required_charge", 0))

func display_name() -> String:
	return str(def.get("name", type))

func has_effect(t: int) -> bool:
	return not get_effect(t).is_empty()

func get_effect(t: int) -> Dictionary:
	for e in def.get("effects", []):
		if int(e.get("type", -1)) == t:
			return e
	return {}
```

`sim/ship_state.gd` 전체:

```gdscript
extends RefCounted
# 함선 상태: 부품 그래프 + hull + 자원 풀. 빌드 Dictionary에서 로드.

const Catalog := preload("res://sim/parts_catalog.gd")
const Part := preload("res://sim/part.gd")

var name := "ship"
var hull := 100
var start_hull := 100
var pulse_interval := 1.0
var time_since_pulse := 0.0
var resources := {"steam": 0, "ammo": 20, "ichor": 0}
var parts := {}             # id -> Part
var part_order: Array = []  # 발동·순회 고정 순서 (빌드 정의 순)
var adjacency := {}         # id -> Array[String]
var hits_taken := 0
var load_errors: Array = []

func load_build(build: Dictionary) -> bool:
	name = str(build.get("name", "ship"))
	hull = int(build.get("ship_hull", 100))
	start_hull = hull
	for pd in build.get("parts", []):
		var pid := str(pd.get("id", ""))
		if pid == "" or parts.has(pid):
			load_errors.append("duplicate or empty part id: '%s'" % pid)
			continue
		var part = Part.new()
		if not part.setup(pid, str(pd.get("type", "")), str(pd.get("graft", ""))):
			load_errors.append("unknown part type or invalid graft: %s (%s+%s)"
				% [pid, pd.get("type", ""), pd.get("graft", "")])
			continue
		parts[pid] = part
		part_order.append(pid)
		adjacency[pid] = []
	for w in build.get("wires", []):
		if w.size() != 2 or not parts.has(str(w[0])) or not parts.has(str(w[1])):
			load_errors.append("invalid wire: %s" % [w])
			continue
		adjacency[str(w[0])].append(str(w[1]))
		adjacency[str(w[1])].append(str(w[0]))
	var heart_count := 0
	for pid in part_order:
		if parts[pid].type == "heart":
			heart_count += 1
	if heart_count != 1:
		load_errors.append("build must contain exactly one heart (found %d)" % heart_count)
	for pid in part_order:
		if parts[pid].type != "heart" and (adjacency[pid] as Array).is_empty():
			load_errors.append("orphan part (no wires): " + pid)
	for pid in part_order:
		var e: Dictionary = parts[pid].get_effect(Catalog.Effect.AMMO_RESERVE)
		if not e.is_empty():
			resources["ammo"] = int(resources["ammo"]) + int(e.get("amount", 0))
	return is_valid()

func is_valid() -> bool:
	return load_errors.is_empty()

func heart_id() -> String:
	for pid in part_order:
		if parts[pid].type == "heart":
			return pid
	return ""

func add_resource(res: String, amount: int) -> void:
	resources[res] = int(resources.get(res, 0)) + amount

func try_spend(cost: Dictionary) -> bool:
	for res in cost:
		if int(resources.get(res, 0)) < int(cost[res]):
			return false
	for res in cost:
		resources[res] = int(resources[res]) - int(cost[res])
	return true

func effective_required_charge(pid: String) -> int:
	var part = parts[pid]
	var rc: int = part.base_required_charge()
	if rc <= 0:
		return rc
	for nb in adjacency.get(pid, []):
		var np = parts[nb]
		if not np.is_destroyed() and np.has_effect(Catalog.Effect.ADJACENT_CHARGE_DISCOUNT):
			rc -= int(np.get_effect(Catalog.Effect.ADJACENT_CHARGE_DISCOUNT).get("amount", 1))
	return maxi(rc, 1)
```

- [ ] **Step 4: 테스트 통과 확인** — Expected: 0 failed.

- [ ] **Step 5: Commit**

```powershell
git add sim/part.gd sim/ship_state.gd tests/run_unit.gd
git commit -m "feat(sim): part runtime state and ship state with build validation"
```

---

### Task 4: 펄스 전파 (pulse_network.gd)

**Files:**
- Create: `sim/pulse_network.gd`
- Modify: `tests/run_unit.gd`

**Interfaces:**
- Consumes: `Ship.adjacency/parts`, `Part.charge/stored_pulses/is_destroyed/has_effect/get_effect`.
- Produces: `static func propagate(ship, origin: String, power: int, rng: RandomNumberGenerator, events: Array, tick: int, side: int, depth: int = 0) -> void`. origin 자신은 charge를 받지 않는다. 이벤트: `pulse_emitted{origin,power}`, `pulse_arrived{part,charge}`, `pulse_stored{part,stored}`.

- [ ] **Step 1: 실패하는 테스트 작성** — `_run_all()`에 `_test_pulse()` 등록:

```gdscript
const Pulse := preload("res://sim/pulse_network.gd")

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _test_pulse() -> void:
	# 체인 전파: heart-a-b 모두 charge 1
	var s = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "a", "type": "boiler"},
		 {"id": "b", "type": "main_turret"}],
		[["heart", "a"], ["a", "b"]])
	var evs: Array = []
	Pulse.propagate(s, "heart", 1, _rng(1), evs, 1, 0)
	check(s.parts.a.charge == 1 and s.parts.b.charge == 1, "chain propagation")
	check(s.parts.heart.charge == 0, "origin gets no charge")

	# 낭포: 흡수하고 하류 차단
	var c = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "cy", "type": "cyst"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "cy"], ["cy", "t"]])
	Pulse.propagate(c, "heart", 1, _rng(1), [], 1, 0)
	check(c.parts.cy.stored_pulses == 1 and c.parts.cy.charge == 0, "cyst stores")
	check(c.parts.t.charge == 0, "cyst blocks downstream")

	# 파괴 부품은 전도하지 않음
	var d = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "m", "type": "boiler"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "m"], ["m", "t"]])
	d.parts.m.hull = 0
	Pulse.propagate(d, "heart", 1, _rng(1), [], 1, 0)
	check(d.parts.t.charge == 0, "destroyed part does not conduct")

	# 신경절: 결정론적 복제, 200회에서 25% 근방
	var g = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "g1", "type": "ganglion"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "g1"], ["g1", "t"]])
	var rng_a := _rng(7)
	for i in 200:
		Pulse.propagate(g, "heart", 1, rng_a, [], i, 0)
	var extra: int = g.parts.t.charge - 200
	check(extra >= 25 and extra <= 80, "ganglion ~25%% replication (got +%d)" % extra)
	# 같은 시드로 재실행 = 같은 결과
	var g2 = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "g1", "type": "ganglion"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "g1"], ["g1", "t"]])
	var rng_b := _rng(7)
	for i in 200:
		Pulse.propagate(g2, "heart", 1, rng_b, [], i, 0)
	check(g2.parts.t.charge == g.parts.t.charge, "replication deterministic")
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: preload 실패.

- [ ] **Step 3: 구현** — `sim/pulse_network.gd` 전체:

```gdscript
extends RefCounted
# 펄스 전파: 배선 그래프 BFS. 신경절 복제, 낭포 흡수, 복제 깊이 상한.

const Catalog := preload("res://sim/parts_catalog.gd")

const MAX_REPLICATION_DEPTH := 8

static func propagate(ship, origin: String, power: int, rng: RandomNumberGenerator,
		events: Array, tick: int, side: int, depth: int = 0) -> void:
	if depth > MAX_REPLICATION_DEPTH:
		return
	events.append({"tick": tick, "side": side, "type": "pulse_emitted",
		"origin": origin, "power": power})
	var visited := {origin: true}
	var frontier: Array = [origin]
	while not frontier.is_empty():
		var next: Array = []
		for cur in frontier:
			for nb in ship.adjacency.get(cur, []):
				if visited.has(nb):
					continue
				visited[nb] = true
				var part = ship.parts[nb]
				if part.is_destroyed():
					continue  # 파괴 부품은 수신도 전도도 하지 않음
				if part.has_effect(Catalog.Effect.STORE_PULSE):
					part.stored_pulses += power
					events.append({"tick": tick, "side": side, "type": "pulse_stored",
						"part": nb, "stored": part.stored_pulses})
					continue  # 낭포는 하류 차단
				part.charge += power
				events.append({"tick": tick, "side": side, "type": "pulse_arrived",
					"part": nb, "charge": part.charge})
				var rep: Dictionary = part.get_effect(Catalog.Effect.PULSE_REPLICATE)
				if not rep.is_empty() and rng.randf() < float(rep.get("chance", 0.25)):
					propagate(ship, nb, power, rng, events, tick, side, depth + 1)
				next.append(nb)
		frontier = next
```

- [ ] **Step 4: 테스트 통과 확인** — Expected: 0 failed.

- [ ] **Step 5: Commit**

```powershell
git add sim/pulse_network.gd tests/run_unit.gd
git commit -m "feat(sim): pulse propagation with ganglion replication and cyst absorption"
```

---

### Task 5: 전투 시뮬레이션 코어 (combat_sim.gd)

**Files:**
- Create: `sim/combat_sim.gd`
- Modify: `tests/run_unit.gd`

**Interfaces:**
- Consumes: Ship, Pulse, Catalog 전부.
- Produces: `Sim`(combat_sim.gd): `const TICK_DT := 0.05`, `const MAX_TIME := 300.0`; `var ships: Array`, `tick: int`, `ended: bool`, `winner: int(-1/0/1)`, `end_reason: String`; `func setup(build_a, build_b, seed_value) -> bool`, `step() -> Array`(이벤트), `run_to_end(on_events: Callable = Callable()) -> Dictionary{winner, reason, time, ticks, hull_a, hull_b}`, `time_now() -> float`. 내부 훅 `_fire_part(side, part, events, forced)`, `_deal_damage(attacker_side, source, amount, events, part_target := "") -> bool`, `_on_successful_hit(side, part, events)`, `_on_part_destroyed(owner_side, part, events)`, `_update_stores(side, events)` — Task 6·7이 이 함수들을 확장한다.

이 태스크의 구현 범위: 심장 타이머(주심장 + 부심장 + 공명), PRODUCE_RESOURCE, FIRE_PROJECTILE(함체 직격만), 불발(charge 유지), ichor/hits_taken 축적, 승패/타임아웃, 결정론. 나머지 효과 분기는 빈 채로 두지 말고 **이 태스크에서 함수 골격에 pass 없이 아래 코드 그대로** 작성한다(§6·7 효과는 카탈로그에 있으므로 분기 자체는 무해).

- [ ] **Step 1: 실패하는 테스트 작성** — `_run_all()`에 `_test_combat_core()` 등록:

```gdscript
const Sim := preload("res://sim/combat_sim.gd")

const B_GUN := {"name": "gun", "parts": [
	{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
	{"id": "t1", "type": "main_turret"}],
	"wires": [["heart", "b1"], ["b1", "t1"]]}
const B_IDLE := {"name": "idle", "parts": [
	{"id": "heart", "type": "heart"}, {"id": "a1", "type": "armor_bulkhead"}],
	"wires": [["heart", "a1"]]}

func _test_combat_core() -> void:
	var sim = Sim.new()
	check(sim.setup(B_GUN, B_IDLE, 42), "setup with valid builds")
	# 2.1초(42틱): 보일러(rc2)가 최소 1회 발동해 steam 생산
	var evs: Array = []
	for i in 42:
		evs.append_array(sim.step())
	var produced := false
	var fired := false
	for e in evs:
		if e.type == "part_fired" and e.side == 0 and e.part == "b1":
			produced = true
		if e.type == "part_fired" and e.side == 0 and e.part == "t1":
			fired = true
	check(produced, "boiler produced steam")
	# 주포: rc3 = 3펄스 = 3초 시점. 42틱(2.1s)에는 미발동, steam1+ammo1 필요.
	check(not fired, "turret not yet at 2.1s")
	# 끝까지: gun이 idle을 격침
	var r = sim.run_to_end()
	check(r.winner == 0, "gun defeats idle (winner=%s reason=%s)" % [r.winner, r.reason])
	check(sim.ships[1].hull <= 0 or r.reason == "timeout", "defender dead or timeout")

	# 불발: 보일러 없는 포탑, steam 없음 → misfire 이벤트, charge 유지
	var starving := {"name": "starve", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "t1"]]}
	var sim2 = Sim.new()
	sim2.setup(starving, B_IDLE, 42)
	var evs2: Array = []
	for i in 70:
		evs2.append_array(sim2.step())
	var misfired := false
	for e in evs2:
		if e.type == "misfire" and e.side == 0:
			misfired = true
	check(misfired, "misfire on steam shortage")
	check(sim2.ships[0].parts.t1.charge >= 3, "misfire keeps charge")

	# 결정론: 같은 시드 = 같은 결과
	var ra = Sim.new(); ra.setup(B_GUN, B_GUN, 7)
	var rb = Sim.new(); rb.setup(B_GUN, B_GUN, 7)
	var res_a = ra.run_to_end()
	var res_b = rb.run_to_end()
	check(res_a.ticks == res_b.ticks and res_a.hull_a == res_b.hull_a
		and res_a.hull_b == res_b.hull_b and res_a.winner == res_b.winner,
		"determinism: same seed same outcome")

	# ichor: 함체 피격 시 양측 +1
	check(int(sim.ships[0].resources.ichor) > 0 or int(sim.ships[1].resources.ichor) > 0,
		"ichor accumulates on hits")
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: preload 실패.

- [ ] **Step 3: 구현** — `sim/combat_sim.gd` 전체 (Task 6·7 분기 포함 최종형):

```gdscript
extends RefCounted
# 전투 1판: 고정 틱 루프, 심장/발동/자원 갱신, 승패 판정, 이벤트 방출.

const Catalog := preload("res://sim/parts_catalog.gd")
const Ship := preload("res://sim/ship_state.gd")
const Pulse := preload("res://sim/pulse_network.gd")

const TICK_DT := 0.05
const MAX_TIME := 300.0

var ships: Array = []
var rng := RandomNumberGenerator.new()
var tick := 0
var ended := false
var winner := -1        # 0/1, -1 = 무승부/미정
var end_reason := ""

func setup(build_a: Dictionary, build_b: Dictionary, seed_value: int) -> bool:
	rng.seed = seed_value
	var a = Ship.new()
	var b = Ship.new()
	var ok := a.load_build(build_a)
	ok = b.load_build(build_b) and ok
	ships = [a, b]
	if not ok:
		push_error("invalid builds: %s / %s" % [a.load_errors, b.load_errors])
	return ok

func time_now() -> float:
	return tick * TICK_DT

func step() -> Array:
	var events: Array = []
	if ended:
		return events
	tick += 1
	for side in [0, 1]:
		_update_hearts(side, events)
		_update_firing(side, events)
		_update_stores(side, events)
	_check_end(events)
	return events

func run_to_end(on_events: Callable = Callable()) -> Dictionary:
	while not ended:
		var evs := step()
		if on_events.is_valid():
			on_events.call(evs)
	return {"winner": winner, "reason": end_reason, "time": time_now(),
		"ticks": tick, "hull_a": ships[0].hull, "hull_b": ships[1].hull}

func _update_hearts(side: int, events: Array) -> void:
	var ship = ships[side]
	ship.time_since_pulse += TICK_DT
	var main_fires := false
	if ship.time_since_pulse >= ship.pulse_interval:
		ship.time_since_pulse -= ship.pulse_interval
		main_fires = true
	var resonated := false
	for pid in ship.part_order:
		var part = ship.parts[pid]
		if part.is_destroyed():
			continue
		var e: Dictionary = part.get_effect(Catalog.Effect.SECOND_HEART)
		if e.is_empty():
			continue
		part.aux_timer += TICK_DT
		if part.aux_timer >= float(e.get("interval", 1.5)):
			part.aux_timer -= float(e.get("interval", 1.5))
			if main_fires and not resonated:
				resonated = true  # 주심장 펄스에 통합 (공명, power 2)
				events.append(_ev(side, "resonance", {"part": pid}))
			else:
				Pulse.propagate(ship, pid, 1, rng, events, tick, side)
	if main_fires:
		Pulse.propagate(ship, ship.heart_id(), 2 if resonated else 1, rng, events, tick, side)

func _update_firing(side: int, events: Array) -> void:
	var ship = ships[side]
	for pid in ship.part_order:
		var part = ship.parts[pid]
		if part.is_destroyed() or part.base_required_charge() <= 0:
			continue
		if part.charge < ship.effective_required_charge(pid):
			continue
		_fire_part(side, part, events, false)

func _fire_part(side: int, part, events: Array, forced: bool) -> void:
	var ship = ships[side]
	for e in part.def.get("effects", []):
		match int(e.get("type", -1)):
			Catalog.Effect.PRODUCE_RESOURCE:
				var res := str(e.get("resource", "steam"))
				var amount := int(e.get("amount", 1))
				var bonus: Dictionary = part.get_effect(Catalog.Effect.PRODUCE_PER_HIT_TAKEN)
				if not bonus.is_empty():
					amount += int(ship.hits_taken * float(bonus.get("per_hit", 0.2)))
				ship.add_resource(res, amount)
				part.charge = 0
				events.append(_ev(side, "part_fired", {"part": part.id, "part_type": part.type}))
				events.append(_ev(side, "resource_changed",
					{"resource": res, "total": ship.resources[res]}))
			Catalog.Effect.FIRE_PROJECTILE:
				var cost: Dictionary = e.get("cost", {})
				if not ship.try_spend(cost):
					events.append(_ev(side, "misfire", {"part": part.id, "part_type": part.type}))
					continue  # 불발: charge 유지
				for res in cost:
					events.append(_ev(side, "resource_changed",
						{"resource": res, "total": ship.resources[res]}))
				var dmg := int(e.get("damage", 0)) + part.stacks
				for nb in ship.adjacency.get(part.id, []):
					var np = ship.parts[nb]
					if not np.is_destroyed() and np.has_effect(Catalog.Effect.ADJACENT_DAMAGE_BUFF):
						dmg += int(np.get_effect(Catalog.Effect.ADJACENT_DAMAGE_BUFF).get("amount", 0))
				events.append(_ev(side, "part_fired", {"part": part.id, "part_type": part.type}))
				var target := _select_part_target(side, part)
				if _deal_damage(side, part, dmg, events, target):
					_on_successful_hit(side, part, events)
				part.charge = 0
			Catalog.Effect.EXTRA_PULSE:
				var cost2: Dictionary = e.get("cost", {})
				if not ship.try_spend(cost2):
					events.append(_ev(side, "misfire", {"part": part.id, "part_type": part.type}))
					continue
				events.append(_ev(side, "part_fired", {"part": part.id, "part_type": part.type}))
				events.append(_ev(side, "resource_changed",
					{"resource": "steam", "total": ship.resources["steam"]}))
				part.charge = 0
				Pulse.propagate(ship, ship.heart_id(), 1, rng, events, tick, side)
			_:
				pass

func _select_part_target(side: int, part) -> String:
	var ship = ships[side]
	var enemy = ships[1 - side]
	for nb in ship.adjacency.get(part.id, []):
		var np = ship.parts[nb]
		if np.is_destroyed() or not np.has_effect(Catalog.Effect.PART_TARGETING):
			continue
		var prio := str(np.get_effect(Catalog.Effect.PART_TARGETING).get("priority", "magazine"))
		for eid in enemy.part_order:
			var ep = enemy.parts[eid]
			if ep.type == prio and not ep.is_destroyed():
				return eid
	return ""  # 폴백: 함 hull 직격

func _deal_damage(attacker_side: int, source, amount: int, events: Array,
		part_target := "") -> bool:
	var attacker = ships[attacker_side]
	var defender = ships[1 - attacker_side]
	var dmg := amount
	if part_target != "":
		var tgt = defender.parts[part_target]
		for nb in defender.adjacency.get(part_target, []):
			var np = defender.parts[nb]
			if not np.is_destroyed() and np.has_effect(Catalog.Effect.ABSORB_ADJACENT_DAMAGE):
				var ratio := float(np.get_effect(Catalog.Effect.ABSORB_ADJACENT_DAMAGE).get("ratio", 0.3))
				var absorbed := int(dmg * ratio)
				if absorbed > 0:
					np.hull -= absorbed
					dmg -= absorbed
					events.append(_ev(attacker_side, "damage_dealt",
						{"source_part": source.id, "source_type": source.type,
						"amount": absorbed, "target_part": np.id,
						"target_hull_left": np.hull, "absorbed": true}))
					if np.is_destroyed():
						_on_part_destroyed(1 - attacker_side, np, events)
				break
		tgt.hull -= dmg
		events.append(_ev(attacker_side, "damage_dealt",
			{"source_part": source.id, "source_type": source.type, "amount": dmg,
			"target_part": tgt.id, "target_hull_left": tgt.hull}))
		if tgt.is_destroyed():
			_on_part_destroyed(1 - attacker_side, tgt, events)
		return true
	# 함체 직격: 아가미 변환 → hull 감소 → ichor/hits 축적
	for pid in defender.part_order:
		var p = defender.parts[pid]
		if p.is_destroyed():
			continue
		var g: Dictionary = p.get_effect(Catalog.Effect.DAMAGE_TO_RESOURCE)
		if g.is_empty():
			continue
		var conv := int(dmg * float(g.get("ratio", 0.5)))
		if conv > 0:
			dmg -= conv
			defender.add_resource(str(g.get("resource", "steam")), conv)
			events.append(_ev(1 - attacker_side, "resource_changed",
				{"resource": g.get("resource"), "total": defender.resources[g.get("resource")]}))
		break
	defender.hull -= dmg
	defender.hits_taken += 1
	defender.add_resource("ichor", 1)
	attacker.add_resource("ichor", 1)
	events.append(_ev(attacker_side, "damage_dealt",
		{"source_part": source.id, "source_type": source.type, "amount": dmg,
		"defender_hull": defender.hull}))
	return true

func _on_successful_hit(side: int, part, events: Array) -> void:
	var ship = ships[side]
	var stack_e: Dictionary = part.get_effect(Catalog.Effect.PERMANENT_STACK_ON_HIT)
	if not stack_e.is_empty():
		part.stacks += int(stack_e.get("amount", 1))
		events.append(_ev(side, "stack_gained", {"part": part.id, "stacks": part.stacks}))
	var adr: Dictionary = part.get_effect(Catalog.Effect.INTERVAL_REDUCE_ON_HIT)
	if not adr.is_empty():
		var floor_v := float(adr.get("floor", 0.5))
		var amount := float(adr.get("amount", 0.05))
		if ship.pulse_interval - amount >= floor_v:
			ship.pulse_interval -= amount
			events.append(_ev(side, "interval_changed", {"interval": ship.pulse_interval}))
		else:
			ship.pulse_interval = floor_v
			var od := int(adr.get("overload_self_damage", 5))
			ship.hull -= od
			events.append(_ev(side, "explosion",
				{"kind": "overload", "amount": od, "hull": ship.hull}))

func _on_part_destroyed(owner_side: int, part, events: Array) -> void:
	events.append(_ev(owner_side, "part_destroyed", {"part": part.id, "part_type": part.type}))
	var boom: Dictionary = part.get_effect(Catalog.Effect.ON_DEATH_EXPLODE)
	if not boom.is_empty():
		var ship = ships[owner_side]
		var d := int(boom.get("self_damage", 20))
		ship.hull -= d
		events.append(_ev(owner_side, "explosion",
			{"kind": "magazine", "amount": d, "hull": ship.hull}))
	var store: Dictionary = part.get_effect(Catalog.Effect.STORE_PULSE)
	if not store.is_empty() and part.stored_pulses > 0 and int(store.get("explode_mult", 0)) > 0:
		var enemy = ships[1 - owner_side]
		var dmg: int = part.stored_pulses * int(store.get("explode_mult", 3))
		part.stored_pulses = 0
		enemy.hull -= dmg
		events.append(_ev(owner_side, "explosion",
			{"kind": "cyst", "amount": dmg, "enemy_hull": enemy.hull}))

func _update_stores(side: int, events: Array) -> void:
	var ship = ships[side]
	for pid in ship.part_order:
		var part = ship.parts[pid]
		if part.is_destroyed():
			continue
		var store: Dictionary = part.get_effect(Catalog.Effect.STORE_PULSE)
		if store.is_empty() or part.stored_pulses < int(store.get("threshold", 10)):
			continue
		if part.has_effect(Catalog.Effect.ALL_FIRE_ON_THRESHOLD):
			part.stored_pulses = 0
			events.append(_ev(side, "explosion", {"kind": "all_fire", "part": pid}))
			for nb in ship.adjacency.get(pid, []):
				var np = ship.parts[nb]
				if not np.is_destroyed() and np.has_effect(Catalog.Effect.FIRE_PROJECTILE):
					_fire_part(side, np, events, true)
		else:
			var dmg: int = part.stored_pulses * int(store.get("explode_mult", 3))
			part.stored_pulses = 0
			var enemy = ships[1 - side]
			enemy.hull -= dmg
			events.append(_ev(side, "explosion",
				{"kind": "cyst", "amount": dmg, "enemy_hull": enemy.hull}))

func _check_end(events: Array) -> void:
	var a_dead: bool = ships[0].hull <= 0
	var b_dead: bool = ships[1].hull <= 0
	if a_dead or b_dead:
		ended = true
		end_reason = "destruction"
		winner = -1 if (a_dead and b_dead) else (1 if a_dead else 0)
	elif time_now() >= MAX_TIME:
		ended = true
		end_reason = "timeout"
		var fa := float(ships[0].hull) / float(ships[0].start_hull)
		var fb := float(ships[1].hull) / float(ships[1].start_hull)
		winner = 0 if fa > fb else (1 if fb > fa else -1)
	if ended:
		events.append({"tick": tick, "side": -1, "type": "battle_end",
			"winner": winner, "reason": end_reason})

func _ev(side: int, type: String, payload: Dictionary) -> Dictionary:
	var e := {"tick": tick, "side": side, "type": type}
	e.merge(payload)
	return e
```

- [ ] **Step 4: 테스트 통과 확인** — Expected: 0 failed.

- [ ] **Step 5: Commit**

```powershell
git add sim/combat_sim.gd tests/run_unit.gd
git commit -m "feat(sim): combat simulation core with hearts, firing, damage, win/loss"
```

---

### Task 6: 지원 효과 검증 (조준·방어·버프)

combat_sim.gd 코드는 Task 5에서 최종형으로 작성됐다. 이 태스크는 **눈알 조준 / 장갑 흡수 / 아가미 변환 / 탄약고 버프·유폭 / 자동장전기**가 실제로 스펙대로 동작하는지 테스트로 못박는다. 테스트가 실패하면 combat_sim.gd의 해당 분기를 수정한다.

**Files:**
- Modify: `tests/run_unit.gd`
- (필요 시) Modify: `sim/combat_sim.gd`

**Interfaces:**
- Consumes: Task 5의 `Sim` 전체 표면.

- [ ] **Step 1: 테스트 작성** — `_run_all()`에 `_test_support_effects()` 등록:

```gdscript
func _test_support_effects() -> void:
	# 탄약고 버프: 8+2=10 피해
	var gunner := {"name": "g", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "mag", "type": "magazine"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["b1", "t1"], ["mag", "t1"]]}
	var sim = Sim.new()
	sim.setup(gunner, B_IDLE, 42)
	var evs: Array = []
	for i in 200:
		evs.append_array(sim.step())
	var buffed := false
	for e in evs:
		if e.type == "damage_dealt" and e.side == 0 and int(e.amount) == 10:
			buffed = true
	check(buffed, "magazine adjacency buff +2")

	# 눈알 조준: 적 탄약고 저격 → 파괴 → 유폭 explosion(kind=magazine)
	var sniper := {"name": "s", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "ey", "type": "eye"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["b1", "t1"], ["heart", "ey"], ["ey", "t1"]]}
	var victim := {"name": "v", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "mag", "type": "magazine"}],
		"wires": [["heart", "mag"]]}
	var sim2 = Sim.new()
	sim2.setup(sniper, victim, 42)
	var evs2: Array = []
	for i in 400:
		if sim2.ended:
			break
		evs2.append_array(sim2.step())
	var sniped := false
	var detonated := false
	for e in evs2:
		if e.type == "damage_dealt" and e.side == 0 and e.get("target_part", "") == "mag":
			sniped = true
		if e.type == "explosion" and e.get("kind", "") == "magazine" and e.side == 1:
			detonated = true
	check(sniped, "eye targets enemy magazine")
	check(detonated, "magazine destruction detonates own ship")

	# 장갑 흡수: 부품 조준 피해 30% 흡수
	var armored := {"name": "a", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "mag", "type": "magazine"},
		{"id": "ar", "type": "armor_bulkhead"}],
		"wires": [["heart", "mag"], ["ar", "mag"]]}
	var sim3 = Sim.new()
	sim3.setup(sniper, armored, 42)
	var evs3: Array = []
	for i in 200:
		if sim3.ended:
			break
		evs3.append_array(sim3.step())
	var absorbed := false
	for e in evs3:
		if e.type == "damage_dealt" and e.get("absorbed", false):
			absorbed = true
	check(absorbed, "armor absorbs part-target damage")

	# 아가미: 함 피격 피해 절반이 steam으로
	var gilled := {"name": "gl", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "gl", "type": "gills"}],
		"wires": [["heart", "gl"]]}
	var sim4 = Sim.new()
	sim4.setup(gunner, gilled, 42)
	for i in 200:
		if sim4.ended:
			break
		sim4.step()
	check(int(sim4.ships[1].resources.steam) > 0, "gills convert damage to steam")

	# 자동장전기: rc3-1=2 → 2펄스(약 2초) 시점에 첫 발사 가능
	var fastgun := {"name": "f", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "al", "type": "autoloader"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["b1", "t1"], ["al", "t1"]]}
	var sim5 = Sim.new()
	sim5.setup(fastgun, B_IDLE, 42)
	var first_fire_tick := -1
	for i in 200:
		for e in sim5.step():
			if e.type == "part_fired" and e.side == 0 and e.part == "t1" and first_fire_tick < 0:
				first_fire_tick = e.tick
	check(first_fire_tick > 0 and first_fire_tick * Sim.TICK_DT <= 2.5,
		"autoloader accelerates first shot (%.2fs)" % (first_fire_tick * Sim.TICK_DT))
```

- [ ] **Step 2: 실행** — 통과하면 Step 3으로. 실패하면 combat_sim.gd의 해당 분기(`_select_part_target`, `_deal_damage`, `effective_required_charge`)를 수정 후 재실행.

- [ ] **Step 3: Commit**

```powershell
git add tests/run_unit.gd sim/combat_sim.gd
git commit -m "test(sim): verify eye targeting, armor absorb, gills, magazine, autoloader"
```

---

### Task 7: 성장·가속 효과 검증 (촉수·아드레날린·터빈·낭포·유폭 심장·공명)

**Files:**
- Modify: `tests/run_unit.gd`
- (필요 시) Modify: `sim/combat_sim.gd`

**Interfaces:**
- Consumes: Task 5의 `Sim` 전체 표면.

- [ ] **Step 1: 테스트 작성** — `_run_all()`에 `_test_growth_effects()` 등록:

```gdscript
func _test_growth_effects() -> void:
	# 촉수: 스택으로 피해 증가 (3, 4, 5, ...)
	var biter := {"name": "bt", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "tc", "type": "tentacle"}],
		"wires": [["heart", "tc"]]}
	var sim = Sim.new()
	sim.setup(biter, B_IDLE, 42)
	var dmgs: Array = []
	for i in 200:
		if sim.ended:
			break
		for e in sim.step():
			if e.type == "damage_dealt" and e.side == 0:
				dmgs.append(int(e.amount))
	check(dmgs.size() >= 3 and dmgs[0] == 3 and dmgs[1] == 4 and dmgs[2] == 5,
		"tentacle permanent stacks (%s)" % [dmgs.slice(0, 3)])

	# 아드레날린 포: interval 감소, 하한 0.5, 하한 이후 과부하 자해
	var adren := {"name": "ad", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "b2", "type": "boiler"}, {"id": "mag", "type": "magazine"},
		{"id": "t1", "type": "main_turret", "graft": "nerve"}],
		"wires": [["heart", "b1"], ["heart", "b2"], ["b1", "t1"], ["mag", "t1"]]}
	var big_idle := {"name": "bi", "ship_hull": 3000, "parts": [
		{"id": "heart", "type": "heart"}, {"id": "a1", "type": "armor_bulkhead"}],
		"wires": [["heart", "a1"]]}
	var sim2 = Sim.new()
	sim2.setup(adren, big_idle, 42)
	var overloaded := false
	var min_interval := 1.0
	for i in 6000:
		if sim2.ended:
			break
		for e in sim2.step():
			if e.type == "interval_changed":
				min_interval = minf(min_interval, float(e.interval))
			if e.type == "explosion" and e.get("kind", "") == "overload":
				overloaded = true
	check(min_interval <= 0.55, "adrenaline reduces interval (min %.2f)" % min_interval)
	check(sim2.ships[0].pulse_interval >= 0.5, "interval floor respected")
	check(overloaded, "overload self-damage past floor")

	# 증기터빈: steam 3 소모 → 추가 펄스 (pulse_emitted origin=heart 증가)
	var turbo := {"name": "tb", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "b2", "type": "boiler"}, {"id": "b3", "type": "boiler"},
		{"id": "st", "type": "steam_turbine"}],
		"wires": [["heart", "b1"], ["heart", "b2"], ["heart", "b3"], ["heart", "st"]]}
	var sim3 = Sim.new()
	sim3.setup(turbo, B_IDLE, 42)
	var turbine_fired := false
	for i in 600:
		if sim3.ended:
			break
		for e in sim3.step():
			if e.type == "part_fired" and e.side == 0 and e.part == "st":
				turbine_fired = true
	check(turbine_fired, "steam turbine fires extra pulse")

	# 낭포: threshold 10 도달 시 폭발 → 적 hull 30 감소 (10*3)
	var cystic := {"name": "cy", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "cy", "type": "cyst"}],
		"wires": [["heart", "cy"]]}
	var sim4 = Sim.new()
	sim4.setup(cystic, B_IDLE, 42)
	var cyst_boom := false
	for i in 300:
		if sim4.ended:
			break
		for e in sim4.step():
			if e.type == "explosion" and e.get("kind", "") == "cyst" and int(e.amount) == 30:
				cyst_boom = true
	check(cyst_boom, "cyst explodes at threshold for stored*3")

	# 유폭 심장(magazine+cyst): 임계 6 도달 시 연결 포탑 강제 일제사격
	var alpha := {"name": "al", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "b2", "type": "boiler"},
		{"id": "dh", "type": "magazine", "graft": "cyst"},
		{"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["heart", "b2"], ["heart", "dh"], ["dh", "t1"]]}
	var sim5 = Sim.new()
	sim5.setup(alpha, B_IDLE, 42)
	var all_fire := false
	for i in 600:
		if sim5.ended:
			break
		for e in sim5.step():
			if e.type == "explosion" and e.get("kind", "") == "all_fire":
				all_fire = true
	check(all_fire, "detonation heart triggers all-fire")

	# 부심장 공명: resonance 이벤트 + power 2 pulse_emitted
	var twin := {"name": "tw", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "ah", "type": "ancillary_heart"},
		{"id": "b1", "type": "boiler"}],
		"wires": [["heart", "ah"], ["heart", "b1"]]}
	var sim6 = Sim.new()
	sim6.setup(twin, B_IDLE, 42)
	var resonance := false
	var power2 := false
	for i in 1200:
		if sim6.ended:
			break
		for e in sim6.step():
			if e.type == "resonance" and e.side == 0:
				resonance = true
			if e.type == "pulse_emitted" and e.side == 0 and int(e.power) == 2:
				power2 = true
	check(resonance and power2, "ancillary heart resonance (res=%s p2=%s)" % [resonance, power2])
```

주의: 부심장 interval 1.5s vs 주심장 1.0s — 3초마다 같은 틱에 겹친다(1.5×2 = 1.0×3). 1200틱(60초)이면 공명이 반드시 발생한다.

- [ ] **Step 2: 실행** — 실패 시 combat_sim.gd의 `_on_successful_hit`/`_update_stores`/`_update_hearts` 수정 후 재실행. Expected: 0 failed.

- [ ] **Step 3: Commit**

```powershell
git add tests/run_unit.gd sim/combat_sim.gd
git commit -m "test(sim): verify tentacle, adrenaline, turbine, cyst, detonation heart, resonance"
```

---

### Task 8: 테스트 빌드 5종 + 빌드 로더

**Files:**
- Create: `sim/build_loader.gd`, `sim/builds/pure_steel.json`, `sim/builds/overdrive.json`, `sim/builds/bloodpressure.json`, `sim/builds/gaze.json`, `sim/builds/dummy_tank.json`
- Modify: `tests/run_unit.gd`

**Interfaces:**
- Produces: `Loader`(build_loader.gd): `static func load_build(path: String) -> Dictionary`(실패 시 빈 Dict + push_error), `static func list_builds(dir_path := "res://sim/builds") -> Array`(경로 문자열 배열, 정렬).

- [ ] **Step 1: 실패하는 테스트 작성** — `_run_all()`에 `_test_builds()` 등록:

```gdscript
const Loader := preload("res://sim/build_loader.gd")

func _test_builds() -> void:
	var paths: Array = Loader.list_builds()
	check(paths.size() == 5, "5 build files (got %d)" % paths.size())
	for p in paths:
		var b: Dictionary = Loader.load_build(p)
		check(not b.is_empty(), "build parses: " + str(p))
		var s = Ship.new()
		check(s.load_build(b), "build valid: %s %s" % [p, s.load_errors])
	check(Loader.load_build("res://sim/builds/nope.json").is_empty(), "missing file -> empty")
	# 대표 매치업 스모크: pure_steel vs overdrive가 300초 안에 끝난다
	var a: Dictionary = Loader.load_build("res://sim/builds/pure_steel.json")
	var b2: Dictionary = Loader.load_build("res://sim/builds/overdrive.json")
	var sim = Sim.new()
	sim.setup(a, b2, 42)
	var r = sim.run_to_end()
	check(r.ticks > 0 and r.has("winner"), "smoke battle completes (%s)" % [r])
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: preload 실패.

- [ ] **Step 3: 구현** — `sim/build_loader.gd` 전체:

```gdscript
extends RefCounted
# 빌드 JSON 파일 로더.

static func load_build(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("build file missing: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("build file is not a JSON object: " + path)
		return {}
	return data

static func list_builds(dir_path := "res://sim/builds") -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".json"):
			out.append(dir_path + "/" + f)
	out.sort()
	return out
```

`sim/builds/pure_steel.json`:
```json
{
  "name": "pure_steel",
  "parts": [
    {"id": "heart", "type": "heart"},
    {"id": "b1", "type": "boiler"},
    {"id": "b2", "type": "boiler"},
    {"id": "al", "type": "autoloader"},
    {"id": "mag", "type": "magazine"},
    {"id": "t1", "type": "main_turret"},
    {"id": "t2", "type": "main_turret"}
  ],
  "wires": [
    ["heart", "b1"], ["heart", "b2"],
    ["b1", "t1"], ["b2", "t2"],
    ["mag", "t1"], ["mag", "t2"],
    ["al", "t1"], ["al", "t2"]
  ]
}
```

`sim/builds/overdrive.json`:
```json
{
  "name": "overdrive",
  "parts": [
    {"id": "heart", "type": "heart"},
    {"id": "b1", "type": "boiler"},
    {"id": "b2", "type": "boiler"},
    {"id": "st", "type": "steam_turbine"},
    {"id": "g1", "type": "ganglion"},
    {"id": "mag", "type": "magazine"},
    {"id": "t1", "type": "main_turret", "graft": "nerve"}
  ],
  "wires": [
    ["heart", "b1"], ["heart", "b2"], ["heart", "st"],
    ["heart", "g1"], ["g1", "t1"], ["mag", "t1"]
  ]
}
```

`sim/builds/bloodpressure.json`:
```json
{
  "name": "bloodpressure",
  "parts": [
    {"id": "heart", "type": "heart"},
    {"id": "bb", "type": "boiler", "graft": "gills"},
    {"id": "gl", "type": "gills"},
    {"id": "ar", "type": "armor_bulkhead"},
    {"id": "t1", "type": "main_turret"},
    {"id": "tc", "type": "tentacle"}
  ],
  "wires": [
    ["heart", "bb"], ["heart", "gl"], ["heart", "ar"],
    ["bb", "t1"], ["heart", "tc"]
  ]
}
```

`sim/builds/gaze.json`:
```json
{
  "name": "gaze",
  "parts": [
    {"id": "heart", "type": "heart"},
    {"id": "ey", "type": "eye"},
    {"id": "b1", "type": "boiler"},
    {"id": "b2", "type": "boiler"},
    {"id": "mag", "type": "magazine"},
    {"id": "t1", "type": "main_turret"},
    {"id": "t2", "type": "main_turret"}
  ],
  "wires": [
    ["heart", "b1"], ["heart", "b2"], ["heart", "ey"],
    ["b1", "t1"], ["b2", "t2"],
    ["ey", "t1"], ["ey", "t2"], ["mag", "t1"]
  ]
}
```

`sim/builds/dummy_tank.json`:
```json
{
  "name": "dummy_tank",
  "ship_hull": 400,
  "parts": [
    {"id": "heart", "type": "heart"},
    {"id": "a1", "type": "armor_bulkhead"},
    {"id": "a2", "type": "armor_bulkhead"},
    {"id": "a3", "type": "armor_bulkhead"},
    {"id": "a4", "type": "armor_bulkhead"}
  ],
  "wires": [
    ["heart", "a1"], ["heart", "a2"], ["heart", "a3"], ["heart", "a4"]
  ]
}
```

- [ ] **Step 4: 테스트 통과 확인** — Expected: 0 failed.

- [ ] **Step 5: Commit**

```powershell
git add sim/build_loader.gd sim/builds tests/run_unit.gd
git commit -m "feat(sim): archetype test builds and JSON build loader"
```

---

### Task 9: 배치 러너 + 검증 지표 3종

**Files:**
- Create: `tests/run_batch.gd`

**Interfaces:**
- Consumes: `Sim.setup/run_to_end/TICK_DT`, `Loader.load_build`.
- Produces: 콘솔 리포트(승률표 + 지표 3종 합격/불합격) + `tests/out/metric1_pulse_curve.csv`.

- [ ] **Step 1: 구현** — `tests/run_batch.gd` 전체:

```gdscript
extends SceneTree
# 배치 검증 러너: 승률표 + GDD §10 검증 지표 3종.
# 실행: & $godot --headless --path . --script res://tests/run_batch.gd

const Sim := preload("res://sim/combat_sim.gd")
const Loader := preload("res://sim/build_loader.gd")

const SEEDS := 50
const OUT_DIR := "res://tests/out"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var builds := {}
	for n in ["pure_steel", "overdrive", "bloodpressure", "gaze", "dummy_tank"]:
		builds[n] = Loader.load_build("res://sim/builds/%s.json" % n)
	_win_matrix(builds)
	_metric1_pulse_curve(builds)
	_metric2_tentacle_overtake(builds)
	_metric3_misfire(builds)
	quit(0)

func _run(a: Dictionary, b: Dictionary, seed_value: int,
		on_events: Callable = Callable()) -> Dictionary:
	var sim = Sim.new()
	sim.setup(a, b, seed_value)
	return sim.run_to_end(on_events)

func _win_matrix(builds: Dictionary) -> void:
	var names := ["pure_steel", "overdrive", "bloodpressure", "gaze"]
	print("\n=== 승률표 (%d시드, 값 = 행 빌드의 승률, 무승부 제외) ===" % SEEDS)
	for an in names:
		var row := "%-14s| " % an
		for bn in names:
			if an == bn:
				row += "   --    "
				continue
			var wins := 0
			for s in SEEDS:
				var r := _run(builds[an], builds[bn], 1000 + s)
				if int(r.winner) == 0:
					wins += 1
			var rate := 100.0 * wins / SEEDS
			row += "%s:%3.0f%% " % [bn.substr(0, 4), rate]
			if rate >= 90.0:
				row += "(!) "
		print(row)
	print("(!) = 90%% 이상 일방 승리 — 밸런스 경고")

func _metric1_pulse_curve(builds: Dictionary) -> void:
	print("\n=== 지표1: 폭주(overdrive) 펄스 지수 곡선 (vs dummy_tank, seed 42) ===")
	var windows: Array = []  # 10초 창별 side0 pulse_emitted 수
	var collector := func(evs: Array) -> void:
		for e in evs:
			if e.type == "pulse_emitted" and int(e.side) == 0:
				var w := int((int(e.tick) * Sim.TICK_DT) / 10.0)
				while windows.size() <= w:
					windows.append(0)
				windows[w] = int(windows[w]) + 1
	var r := _run(builds["overdrive"], builds["dummy_tank"], 42, collector)
	var f := FileAccess.open(OUT_DIR + "/metric1_pulse_curve.csv", FileAccess.WRITE)
	f.store_line("window_10s,pulses")
	for i in windows.size():
		f.store_line("%d,%d" % [i, windows[i]])
	f.close()
	print("  전투 시간 %.1fs (%s), 창별 펄스: %s" % [r.time, r.reason, windows])
	var first := int(windows[0]) if windows.size() > 0 else 0
	var peak := 0
	for w in windows:
		peak = maxi(peak, int(w))
	var ratio := float(peak) / maxf(float(first), 1.0)
	var ok := first > 0 and ratio >= 1.5
	print("  peak/first = %.2f (기준 >= 1.5) → %s" % [ratio, "합격" if ok else "불합격"])

func _metric2_tentacle_overtake(builds: Dictionary) -> void:
	print("\n=== 지표2: 촉수 누적피해의 주포 추월 (bloodpressure vs dummy_tank, seed 42) ===")
	var state := {"tentacle": 0, "turret": 0, "cross": -1.0}
	var collector := func(evs: Array) -> void:
		for e in evs:
			if e.type == "damage_dealt" and int(e.side) == 0 and not e.get("absorbed", false):
				if str(e.source_type) == "tentacle":
					state.tentacle = int(state.tentacle) + int(e.amount)
				elif str(e.source_type) == "main_turret":
					state.turret = int(state.turret) + int(e.amount)
				if float(state.cross) < 0.0 and int(state.turret) > 0 \
						and int(state.tentacle) > int(state.turret):
					state.cross = int(e.tick) * Sim.TICK_DT
	var r := _run(builds["bloodpressure"], builds["dummy_tank"], 42, collector)
	print("  전투 %.1fs, 촉수 누적 %d vs 주포 누적 %d, 추월 시점 %.1fs"
		% [r.time, state.tentacle, state.turret, state.cross])
	var ok: bool = float(state.cross) >= 0.0 and float(state.cross) <= 60.0
	print("  기준: 60초 내 추월 → %s" % ("합격" if ok else "불합격"))

func _metric3_misfire(builds: Dictionary) -> void:
	print("\n=== 지표3: 자원 고갈 불발률 (pure_steel vs 보일러 -1 변형, 10시드) ===")
	var rates: Array = []
	for starved in [false, true]:
		var build: Dictionary = (builds["pure_steel"] as Dictionary).duplicate(true)
		if starved:
			build["name"] = "steel_starved"
			build["parts"] = (build["parts"] as Array).filter(
				func(p): return str(p.id) != "b2")
			build["wires"] = (build["wires"] as Array).filter(
				func(w): return not (w as Array).has("b2"))
		var state := {"fired": 0, "missed": 0}
		var collector := func(evs: Array) -> void:
			for e in evs:
				if int(e.get("side", -1)) == 0 and str(e.get("part_type", "")) == "main_turret":
					if e.type == "part_fired":
						state.fired = int(state.fired) + 1
					elif e.type == "misfire":
						state.missed = int(state.missed) + 1
		for s in 10:
			_run(build, builds["pure_steel"], 2000 + s, collector)
		var total: int = int(state.fired) + int(state.missed)
		var rate := 100.0 * int(state.missed) / maxi(total, 1)
		rates.append(rate)
		print("  %-14s: 발사 %d / 불발 %d → 불발률 %.1f%%"
			% [build["name"], state.fired, state.missed, rate])
	var ok: bool = float(rates[1]) > 15.0
	print("  기준: 변형 빌드 불발률 > 15%% → %s" % ("합격" if ok else "불합격"))
```

- [ ] **Step 2: 실행**

```powershell
$godot = Get-Content tests/out/godot_path.txt
& $godot --headless --path . --script res://tests/run_batch.gd
```
Expected: 승률표 4×4 + 지표 3종 리포트 출력, `tests/out/metric1_pulse_curve.csv` 생성, 종료 코드 0. **지표 불합격은 코드 버그가 아니라 밸런스 신호일 수 있다** — 불합격이 나오면 원인을 분석해 리포트에 남기고, 명백한 시뮬 버그일 때만 수정한다.

- [ ] **Step 3: 단위 테스트 회귀 확인** — run_unit.gd 재실행, 0 failed.

- [ ] **Step 4: Commit**

```powershell
git add tests/run_batch.gd
git commit -m "feat(tests): batch runner with win matrix and GDD verification metrics"
```

---

### Task 10: 디버그 시각화 씬

**Files:**
- Create: `debug/battle_view.gd`, `debug/battle_view.tscn`
- Modify: 프로젝트 설정 `application/run/main_scene` (MCP `set_project_setting` 사용 — project.godot 직접 편집 금지)

**Interfaces:**
- Consumes: `Sim`, `Loader`, 이벤트 스트림(스펙 §6). 보드 구성 시 부품 정의(def)와 시작 자원 스냅샷만 읽고, 이후 갱신은 전부 이벤트로.

- [ ] **Step 1: 씬 파일 작성** — `debug/battle_view.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://debug/battle_view.gd" id="1"]

[node name="BattleView" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

- [ ] **Step 2: 스크립트 작성** — `debug/battle_view.gd` 전체:

```gdscript
extends Control
# 디버그 전투 뷰: sim 이벤트 스트림을 소비해 그린다.

const Sim := preload("res://sim/combat_sim.gd")
const Loader := preload("res://sim/build_loader.gd")

const KIND_COLORS := {
	"steel": Color(0.30, 0.40, 0.50),
	"bio": Color(0.45, 0.15, 0.50),
	"core": Color(0.70, 0.25, 0.15),
}

var sim = null
var paused := true
var speed := 1.0   # 배속. 음수 = 최대
var time_acc := 0.0

var pick_a: OptionButton
var pick_b: OptionButton
var seed_spin: SpinBox
var hull_bars: Array = []
var res_labels: Array = []
var interval_labels: Array = []
var boards: Array = []
var rows := [{}, {}]   # side -> part_id -> {rect, bar, lbl, base}
var res_cache := [{}, {}]
var log_view: RichTextLabel
var build_paths: Array = []

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	pick_a = OptionButton.new()
	pick_b = OptionButton.new()
	build_paths = Loader.list_builds()
	for i in build_paths.size():
		var bn := String(build_paths[i]).get_file().get_basename()
		pick_a.add_item(bn, i)
		pick_b.add_item(bn, i)
	pick_b.select(mini(1, build_paths.size() - 1))
	bar.add_child(pick_a)
	bar.add_child(pick_b)
	seed_spin = SpinBox.new()
	seed_spin.max_value = 999999
	seed_spin.value = 42
	bar.add_child(seed_spin)
	var start_btn := Button.new()
	start_btn.text = "시작"
	start_btn.pressed.connect(_on_start)
	bar.add_child(start_btn)
	var pause_btn := Button.new()
	pause_btn.text = "일시정지/재개"
	pause_btn.pressed.connect(func(): paused = not paused)
	bar.add_child(pause_btn)
	for sp in [["1x", 1.0], ["4x", 4.0], ["최대", -1.0]]:
		var b := Button.new()
		b.text = sp[0]
		var v: float = sp[1]
		b.pressed.connect(func(): speed = v)
		bar.add_child(b)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var status := VBoxContainer.new()
	status.custom_minimum_size.x = 280
	for side in [0, 1]:
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boards.append(vb)
		var hb := ProgressBar.new()
		hb.max_value = 100
		hb.value = 100
		hull_bars.append(hb)
		status.add_child(hb)
		var rl := Label.new()
		res_labels.append(rl)
		status.add_child(rl)
		var il := Label.new()
		il.text = "interval 1.00s"
		interval_labels.append(il)
		status.add_child(il)
	mid.add_child(boards[0])
	mid.add_child(status)
	mid.add_child(boards[1])
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.custom_minimum_size.y = 220
	root.add_child(log_view)

func _on_start() -> void:
	var a: Dictionary = Loader.load_build(build_paths[pick_a.selected])
	var b: Dictionary = Loader.load_build(build_paths[pick_b.selected])
	sim = Sim.new()
	if not sim.setup(a, b, int(seed_spin.value)):
		log_view.clear()
		log_view.append_text("[color=red]빌드 로드 실패 — 콘솔 에러 확인[/color]\n")
		sim = null
		return
	log_view.clear()
	_reset_boards([a, b])
	paused = false
	time_acc = 0.0

func _reset_boards(builds: Array) -> void:
	for side in [0, 1]:
		rows[side] = {}
		for c in boards[side].get_children():
			c.queue_free()
		hull_bars[side].max_value = builds[side].get("ship_hull", 100)
		hull_bars[side].value = hull_bars[side].max_value
		# 시작 스냅샷 (이후 갱신은 이벤트로만)
		res_cache[side] = (sim.ships[side].resources as Dictionary).duplicate()
		_refresh_res(side)
		interval_labels[side].text = "interval %.2fs" % sim.ships[side].pulse_interval
		for pd in builds[side].get("parts", []):
			var part = sim.ships[side].parts.get(str(pd.id))
			if part == null:
				continue
			var row := HBoxContainer.new()
			var rect := ColorRect.new()
			rect.custom_minimum_size = Vector2(26, 26)
			rect.color = KIND_COLORS.get(part.def.get("kind", "steel"), Color.GRAY)
			var lbl := Label.new()
			lbl.text = part.display_name()
			var cbar := ProgressBar.new()
			cbar.custom_minimum_size = Vector2(70, 10)
			cbar.max_value = maxi(part.base_required_charge(), 1)
			cbar.show_percentage = false
			row.add_child(rect)
			row.add_child(lbl)
			row.add_child(cbar)
			boards[side].add_child(row)
			rows[side][str(pd.id)] = {"rect": rect, "bar": cbar, "lbl": lbl, "base": rect.color}

func _process(delta: float) -> void:
	if sim == null or paused or sim.ended:
		return
	var steps := 0
	if speed < 0.0:
		steps = 400
	else:
		time_acc += delta * speed
		steps = int(time_acc / Sim.TICK_DT)
		time_acc -= steps * Sim.TICK_DT
	for i in steps:
		if sim.ended:
			break
		_apply_events(sim.step())

func _apply_events(events: Array) -> void:
	for e in events:
		match str(e.type):
			"pulse_arrived":
				var r = rows[e.side].get(str(e.part))
				if r:
					r.bar.value = e.charge
			"part_fired":
				_flash(e.side, str(e.part), Color.WHITE)
				var r = rows[e.side].get(str(e.part))
				if r:
					r.bar.value = 0
			"misfire":
				_flash(e.side, str(e.part), Color.BLACK)
				_log(e, "%s 불발" % e.part)
			"damage_dealt":
				if e.has("defender_hull"):
					hull_bars[1 - int(e.side)].value = e.defender_hull
				_log(e, "%s → 피해 %d%s" % [e.source_part, e.amount,
					" (부품: %s)" % e.get("target_part") if e.has("target_part") else ""])
			"resource_changed":
				res_cache[e.side][str(e.resource)] = e.total
				_refresh_res(e.side)
			"interval_changed":
				interval_labels[e.side].text = "interval %.2fs" % e.interval
				_log(e, "박동간격 → %.2fs" % e.interval)
			"stack_gained":
				var r = rows[e.side].get(str(e.part))
				if r:
					r.lbl.text = "%s +%d" % [sim.ships[e.side].parts[e.part].display_name(), e.stacks]
			"part_destroyed":
				var r = rows[e.side].get(str(e.part))
				if r:
					r.rect.color = Color(0.15, 0.15, 0.15)
					r.base = r.rect.color
				_log(e, "%s 파괴" % e.part)
			"resonance":
				_log(e, "공명 펄스!")
			"explosion":
				if e.has("hull"):
					hull_bars[e.side].value = e.hull
				if e.has("enemy_hull"):
					hull_bars[1 - int(e.side)].value = e.enemy_hull
				_log(e, "폭발(%s) 피해 %s" % [e.kind, e.get("amount", "-")])
			"battle_end":
				_log(e, "전투 종료 — 승자: %s (%s)" % [e.winner, e.reason])

func _flash(side: int, part_id: String, c: Color) -> void:
	var r = rows[side].get(part_id)
	if r == null:
		return
	r.rect.color = c
	var tw := create_tween()
	tw.tween_property(r.rect, "color", r.base, 0.25)

func _refresh_res(side: int) -> void:
	var rc: Dictionary = res_cache[side]
	res_labels[side].text = "steam %s | ammo %s | ichor %s" % [
		rc.get("steam", 0), rc.get("ammo", 0), rc.get("ichor", 0)]

func _log(e: Dictionary, msg: String) -> void:
	var side_tag := "[A]" if int(e.get("side", 0)) == 0 else "[B]"
	log_view.append_text("[%.1fs]%s %s\n" % [int(e.tick) * Sim.TICK_DT, side_tag, msg])

func _side_name(side: int) -> String:
	return "A" if side == 0 else "B"
```

- [ ] **Step 3: 메인 씬 설정** — MCP `set_project_setting`:
```
setting: "application/run/main_scene", value: "res://debug/battle_view.tscn"
```

- [ ] **Step 4: 수동 검증** — MCP로:
1. `play_scene` (main scene)
2. `get_game_screenshot` — 컨트롤 바/보드/로그가 보이는지
3. `click_button_by_text` "시작" → 전투 진행
4. `get_game_screenshot` — hull 바 감소, 로그 스크롤 확인
5. `stop_scene`
Expected: 스크립트 에러 없이 (에디터 output 확인: `get_editor_errors`) 전투가 눈으로 보인다.

- [ ] **Step 5: 회귀 확인 + Commit**

run_unit.gd 재실행 0 failed 확인 후:
```powershell
git add debug/ project.godot
git commit -m "feat(debug): battle visualization scene consuming event stream"
```

---

## 최종 검증 (전체 완료 후)

1. `run_unit.gd` — 0 failed
2. `run_batch.gd` — 승률표 + 지표 3종 리포트 출력. 결과를 해석해 사용자에게 보고:
   - 지표별 합격/불합격과 원인 분석
   - 90% 이상 일방 승리 매치업 여부
3. 디버그 씬 스크린샷 1장
4. superpowers:verification-before-completion 스킬로 완료 선언 전 증거 확인
