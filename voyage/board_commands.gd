extends RefCounted
## 사람이 내리는 조립 명령. **검증을 새로 구현하지 않는다** (검토 §8.1의 "조립 명령"
## 행: 장착·이동·분리·보관·폐기와 합법성 검증을 AI/사람이 공유).
##
## 상태 변경은 `candidate_generator.apply()`가 하고, 합법성은
## `build_loader.assemble()`가 본다. 둘 다 AI가 쓰는 것과 같은 함수다 — 사람 경로에
## 검증을 한 벌 더 만들면 "AI에서는 합법인데 사람 화면에서는 불법"인 조립이 생긴다.
##
## 이 파일이 추가하는 것은 **사람에게 필요한 조회**뿐이다: 이 파츠를 어디에 놓을 수
## 있는가, 어느 숙주에 증강으로 붙일 수 있는가, 지금 출격이 가능한가.

const Generator = preload("res://league/candidate_generator.gd")
const Graph = preload("res://league/build_graph.gd")
const Inventory = preload("res://run/inventory.gd")
const BuildLoader = preload("res://sim/build_loader.gd")

## 명령 하나를 적용한다. 원본은 건드리지 않고 새 인벤토리를 돌려준다.
##
## ctx: {catalog, slots, allow_augment, storage_limit}
## 반환: {ok, inventory, error}
static func apply(inv: RefCounted, command: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind: String = str(command.get("kind", ""))
	var uid: int = int(command.get("uid", Inventory.NONE))
	if kind == "detach_augment":
		# AI 어휘에는 없는 명령이다 — AI는 증강을 뗄 이유가 없으면 후보로 만들지
		# 않는다. 사람은 "이 증강을 본체로 돌리고 싶다"를 두 단계로 해야 하므로
		# 분리를 별도 명령으로 둔다. 결과 상태는 place와 같은 함수로 만든다.
		var slot_id: String = str(command.get("slot", ""))
		if not inv.board.has(slot_id):
			return _fail("빈 슬롯의 증강은 뗄 수 없다: %s" % slot_id)
		var entry: Dictionary = inv.board[slot_id]
		if int(entry.get("augment", Inventory.NONE)) == Inventory.NONE:
			return _fail("그 슬롯에는 증강이 없다: %s" % slot_id)
		var copy: RefCounted = inv.clone()
		copy.place(slot_id, int(entry["active"]), Inventory.NONE)
		return {"ok": true, "inventory": copy, "error": ""}

	if not ["place", "augment", "store", "discard", "keep"].has(kind):
		return _fail("모르는 조립 명령: %s" % kind)
	if kind != "keep" and inv.part_id_of(uid) == "":
		return _fail("보유하지 않은 개체다: %d" % uid)
	if kind != "keep" and _is_core(inv, uid, ctx):
		# Core는 사람의 결정 공간에도 없다. 떼면 조립 자체가 무효가 된다.
		return _fail("Core는 옮기거나 버릴 수 없다")
	if kind == "place":
		# **역할은 여기서 본다.** `Generator.apply()`의 place는 실패하지 않는다 —
		# 인벤토리 컨테이너는 슬롯 역할을 모르기 때문이다. AI는 후보를 만들 때
		# `_body_fits`로 걸러서 불법 조립을 애초에 만들지 않는데, 사람은 아무
		# 슬롯이나 지목할 수 있으므로 명령을 받는 자리에서 막아야 한다.
		# 출격 검증까지 미루면 "장착은 됐는데 출격이 안 된다"가 된다.
		var slot_def: Dictionary = _slot_def(ctx, str(command.get("slot", "")))
		if slot_def.is_empty():
			return _fail("없는 슬롯이다: %s" % str(command.get("slot", "")))
		if str(slot_def["role"]) == "core":
			return _fail("Core 슬롯은 비교 조건이다 — 바꿀 수 없다")
		if not _body_fits(inv, uid, slot_def, ctx):
			return _fail("역할이 맞지 않는다 — %s 슬롯에는 %s를 놓을 수 없다"
				% [str(slot_def["role"]),
					str((ctx["catalog"] as RefCounted).parts[
						inv.part_id_of(uid)]["base_role"])])
	var result: RefCounted = Generator.apply(inv, command, ctx)
	if result == null:
		return _fail("그 조립은 규칙상 불가능하다 (%s)" % kind)
	return {"ok": true, "inventory": result, "error": ""}

## 이 개체를 지금 놓을 수 있는 자리. §7.3의 첫 필수 동작이다 —
## "파츠 선택 시 장착 가능한 슬롯과 증강 숙주를 표시한다."
##
## 태그로 판정하지 않고 **실제로 놓아 보고** 판정한다. 규칙이 한 곳에만 있으려면
## 조회도 같은 함수를 지나야 한다.
##
## 반환: {bodies: [slot_id...], hosts: [slot_id...]}
static func legal_targets(inv: RefCounted, uid: int, ctx: Dictionary) -> Dictionary:
	var bodies: Array[String] = []
	var hosts: Array[String] = []
	for slot_def: Dictionary in (ctx["slots"] as Array):
		var slot_id: String = str(slot_def["id"])
		if str(slot_def["role"]) == "core":
			continue
		if Generator.apply(inv, {"kind": "place", "uid": uid, "slot": slot_id},
				ctx) != null and _body_fits(inv, uid, slot_def, ctx):
			bodies.append(slot_id)
		if bool(ctx.get("allow_augment", true)) and Generator.apply(inv,
				{"kind": "augment", "uid": uid, "slot": slot_id}, ctx) != null:
			hosts.append(slot_id)
	return {"bodies": bodies, "hosts": hosts}

## 출격 가능한가. **합법성과 공격 가능성을 나눠서** 돌려준다 (§7.3 마지막).
##
## 공격 경로가 없는 보드는 불법이 아니다 — 리그는 그것을 실험 조건 오류로 보지만
## 사람은 일부러 시험할 수 있어야 한다. 그래서 "막는 것"과 "경고하는 것"을 가른다.
##
## 반환: {ok, errors, warnings, operational, storage_over}
static func check_launch(inv: RefCounted, ctx: Dictionary,
		config: RefCounted) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var build: Dictionary = inv.to_build("voyage_check", str(ctx["frame_id"]))
	var loader: RefCounted = BuildLoader.new()
	if loader.assemble(build, ctx["catalog"], "player") == null:
		errors.append_array(loader.errors)

	var analysis: Dictionary = Graph.analyze(
		Generator.placed_units(inv, ctx["catalog"], ctx["meta_index"]),
		int(ctx["body_slots"]), {})
	var operational: bool = bool(analysis["operational"])
	if not operational:
		var line: String = "적 선체에 피해가 도달하는 경로가 없다"
		if bool(config.allow_unarmed_launch):
			warnings.append(line + " — 이대로 출격하면 이길 수 없다")
		else:
			errors.append(line)

	# 보관 한도를 넘은 상태로는 출격하지 않는다. **자동 폐기는 하지 않는다** —
	# 무엇을 버릴지는 사람이 고른다 (§7.3의 네 번째 필수 동작).
	var over: int = inv.unplaced().size() - int(config.league.storage_limit)
	if over > 0:
		errors.append("보관 한도 %d개를 %d개 넘었다 — 버릴 파츠를 고르라"
			% [int(config.league.storage_limit), over])

	return {
		"ok": errors.is_empty(), "errors": errors, "warnings": warnings,
		"operational": operational, "storage_over": maxi(0, over),
	}

## 사람이 읽는 명령 이름. 선택 기록이 "무엇을 했는가"를 설명할 수 있어야 한다.
static func describe(command: Dictionary, inv: RefCounted) -> String:
	var part: String = inv.part_id_of(int(command.get("uid", Inventory.NONE)))
	match str(command.get("kind", "")):
		"place": return "%s를 %s에 장착" % [part, str(command.get("slot", ""))]
		"augment": return "%s를 %s의 증강으로" % [part, str(command.get("slot", ""))]
		"store": return "%s를 보관" % part
		"discard": return "%s를 폐기" % part
		"detach_augment": return "%s의 증강을 분리" % str(command.get("slot", ""))
		"keep": return "그대로 둔다"
	return str(command)

# --- 내부 ---

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "inventory": null, "error": message}

static func _slot_def(ctx: Dictionary, slot_id: String) -> Dictionary:
	for slot_def: Dictionary in (ctx["slots"] as Array):
		if str(slot_def["id"]) == slot_id:
			return slot_def
	return {}

static func _is_core(inv: RefCounted, uid: int, ctx: Dictionary) -> bool:
	var def: Dictionary = (ctx["catalog"] as RefCounted).parts.get(
		inv.part_id_of(uid), {})
	return not def.is_empty() and str(def["base_role"]) == "core"

## 역할이 맞는가. `Generator.apply()`는 place를 무조건 성공시키므로 (인벤토리
## 컨테이너는 역할을 모른다) 역할 판정은 여기서 한 번 더 본다. 판정 기준은
## `build_loader`와 같다 — flexible 슬롯은 아무 역할이나 받고, 나머지는 같은 역할만.
static func _body_fits(inv: RefCounted, uid: int, slot_def: Dictionary,
		ctx: Dictionary) -> bool:
	var def: Dictionary = (ctx["catalog"] as RefCounted).parts.get(
		inv.part_id_of(uid), {})
	if def.is_empty():
		return false
	var role: String = str(slot_def["role"])
	return role == "flexible" or role == str(def["base_role"])
