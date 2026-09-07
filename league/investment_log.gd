extends RefCounted
## 근거리 투자 경로 로그 (r5b 피드백 §5.1·§5.2).
##
## r5b는 최종 선택의 potential만 집계했다. 그래서 "미래 가치가 양수인 선택 2.9%"라는
## 숫자가 나왔는데, 그것이 **준비 후보가 제안되지 않은 것인지 / 후보 생성에서 탈락한
## 것인지 / 낮게 평가된 것인지** 구별되지 않았다. 게다가 지금 선택이 이미 연결을
## 완성했다면 점수는 미래가 아니라 connection·relief에 나타난다 — 낮은 potential
## 하나로 "장기 계획이 없다"고 결론 낼 수 없다.
##
## 그래서 네 단계를 **따로** 기록한다.
##   1 제안  미래 연결을 만들 수 있는 파츠가 제안됐는가        → offer_stage()
##   2 후보  합법적인 본체·증강·보관 후보가 생성됐는가          → assembly_policy의 reward_uses
##   3 평가  그 후보를 어느 정도 가치 있게 평가했는가            → assembly_policy의 best_potential
##   4 실현  선택 이후 실제로 연결이 열리고 전투에 기여했는가    → open()·observe_board()·observe_combat()
##
## 4단계는 개체(uid) 단위로 추적한다. part_id만으로 세면 "보관한 바로 그 개체를 썼는가"를
## 증명할 수 없다 — 같은 파츠를 다시 획득했을 수도 있다 (§5.2).
##
## **미해결을 실패로 적지 않는다.** 런이 끝나 관측이 없는 보관은 outcome이
## "unresolved"이고, 그것을 회수 실패와 합치면 §5.2가 경고한 오독을 그대로 되풀이한다.

const PartMeta = preload("res://league/part_meta.gd")
const Graph = preload("res://league/build_graph.gd")
const Inventory = preload("res://run/inventory.gd")

## 1단계. 제안된 파츠 하나가 **어휘만 보고** 미래 연결을 만들 수 있는가.
##
## 후보 생성·평가를 거치지 않는다는 것이 요점이다. 2·3단계와 섞으면 "제안조차 없었다"와
## "제안은 있었는데 후보가 안 만들어졌다"를 다시 구별할 수 없게 된다.
##
## before는 Graph.analyze()의 결과. 반환: {fills, unblocks, needs_support, future}
##   fills          이 파츠가 채울 수 있는, 지금 보드에 실제로 있는 병목 이름들
##   unblocks       그것으로 **실제로 켜질** 침묵 단위 수 (미충족 전제가 그 하나뿐인 것)
##   needs_support  이 파츠 자신이 이 보드에서는 아직 침묵한다 — 나중을 보는 베팅이다
##
## 처음에는 "제안 파츠와 보드의 이벤트 키가 겹치는가"로 재려 했다. 그것은 **거의 항상
## 참**이었다 — part_fired@own을 거의 모든 파츠가 내고 거의 모든 증강이 듣기 때문이다.
## 항상 참인 신호는 1단계와 2·3단계를 구별해 주지 못한다. connection 특징이 네 전략
## 모두 1.00으로 포화했던 것과 같은 결함이므로, 포화하지 않는 지표로 바꿨다.
static func offer_stage(part_id: String, meta_index: Dictionary,
		before: Dictionary) -> Dictionary:
	var fills: Array[String] = []
	if not meta_index.has(part_id):
		return {"fills": fills, "unblocks": 0, "needs_support": false,
			"future": false}

	# 본체로 쓸 때와 증강으로 쓸 때 어휘가 다르다. 제안 단계에서는 아직 어느 쪽으로
	# 쓸지 모르므로 **둘 다** 본다.
	var supplies: Dictionary = PartMeta.supplies_of_parts(meta_index, [part_id])
	var missing: Dictionary = before["missing"]
	for need: String in supplies:
		if int(missing.get(need, 0)) > 0 and not fills.has(need):
			fills.append(need)

	# 실제로 켜질 단위 수. 미충족 전제가 정확히 하나이고 그것을 이 파츠가 채울 때만
	# 센다 — 전제가 둘이면 이 획득 하나로는 열리지 않는다.
	var unblocks: int = 0
	for needs: Variant in before.get("dead_needs", []):
		var list: Array = needs
		if list.size() == 1 and supplies.has(str(list[0])):
			unblocks += 1

	# 이 파츠 자신이 아직 침묵하는가. 본체로 쓸 때를 기준으로 본다 —
	# 증강은 숙주가 있어야 놓을 수 있어 "지금 침묵"의 뜻이 달라진다.
	var body: Dictionary = (meta_index[part_id] as Dictionary)["body"]
	var needs_support: bool = bool(body.get("usable", false)) 		and not Graph.unmet_for(body, before).is_empty()

	return {"fills": fills, "unblocks": unblocks, "needs_support": needs_support,
		"future": unblocks > 0 or needs_support}

# --- 4단계: 개체 단위 추적 ---

## 미해결 투자 [{uid, part_id, use, ...}]. 참가자마다 하나씩 만든다.
var pending: Array = []
## 결론이 난 투자. 리포터가 이것을 센다.
var closed: Array = []

## 이번 선택이 **근거리 투자**였으면 등록한다. 두 종류만 투자로 본다.
##   stored  보관했다 — 지금 쓰지 않고 나중을 위해 남겼다
##   silent  본체/증강으로 놓았지만 지금 침묵한다 — 열리기를 기다린다
##
## 즉시 도는 파츠를 장착한 것은 투자가 아니다. 그것은 이미 회수된 현재 기여이고,
## 여기 넣으면 "투자 회수율"이 즉시 전력 선택으로 희석된다.
func open(choice_index: int, round_index: int, inv: RefCounted, uid: int,
		use: String, analysis: Dictionary, needs: Array) -> void:
	if uid == Inventory.NONE or inv.part_id_of(uid) == "":
		return
	var kind: String = ""
	if use == "storage":
		kind = "stored"
	elif (use == "body" or use == "augment") and not _is_active(inv, uid, use, analysis):
		kind = "silent"
	if kind == "":
		return
	pending.append({
		"choice_index": choice_index, "opened_round": round_index,
		"part_id": inv.part_id_of(uid), "part_instance_id": uid,
		"kind": kind, "use_at_open": use,
		# 무엇을 기다리는 투자인지. 이름이 없으면 나중에 "무엇이 열렸는가"를 말할 수 없다.
		"needs": needs.duplicate(),
		"active_round": 0, "fired_round": 0, "fires": 0, "via": "",
	})

## 조립 시점마다 부른다. 놓였고 실제로 도는 상태가 됐으면 그 라운드를 적는다.
func observe_board(round_index: int, inv: RefCounted, analysis: Dictionary) -> void:
	for entry: Dictionary in pending:
		var uid: int = int(entry["part_instance_id"])
		if inv.part_id_of(uid) == "":
			_mark(entry, "discarded", round_index)
			continue
		var use: String = _use_of(inv, uid)
		if use == "storage":
			continue
		if int(entry["active_round"]) == 0 and _is_active(inv, uid, use, analysis):
			entry["active_round"] = round_index
			entry["use_at_open"] = use
	_sweep()

## 전투 하나가 끝날 때마다 부른다. side는 이 참가자가 선 진영("player"/"enemy").
##
## 기여는 **슬롯 단위**로 잰다. 증강의 트리거는 숙주 파츠에 병합되므로 증강 자신의
## part_fired가 없다 — 그래서 증강은 숙주 슬롯의 발동으로 센다. via에 어느 쪽인지
## 적어 두는 것이 중요하다: 숙주 슬롯 발동을 증강의 기여로 그대로 읽으면 과대평가다.
func observe_combat(round_index: int, inv: RefCounted, log: Array,
		side: String) -> void:
	var fired: Dictionary = {}
	for event: Dictionary in log:
		if str(event["type"]) != "part_fired" or str(event.get("ship", "")) != side:
			continue
		var slot: String = str(event.get("slot", ""))
		fired[slot] = int(fired.get(slot, 0)) + 1
	for entry: Dictionary in pending:
		var uid: int = int(entry["part_instance_id"])
		if inv.part_id_of(uid) == "":
			continue
		var use: String = _use_of(inv, uid)
		if use != "body" and use != "augment":
			continue
		var slot_id: String = inv.slot_of(uid)
		var count: int = int(fired.get(slot_id, 0))
		if count <= 0:
			continue
		if int(entry["fired_round"]) == 0:
			entry["fired_round"] = round_index
			entry["via"] = "own_slot" if use == "body" else "host_slot"
		entry["fires"] = int(entry["fires"]) + count
	_sweep()

## 런이 끝날 때 부른다. 남은 투자는 **미해결**이지 실패가 아니다 (§5.2).
func finish(round_index: int) -> void:
	for entry: Dictionary in pending:
		if not entry.has("outcome"):
			_mark(entry, "unresolved", round_index)
	_sweep()

# --- 내부 ---

## 결론이 난 투자를 pending에서 옮긴다.
func _sweep() -> void:
	var rest: Array = []
	for entry: Dictionary in pending:
		if int(entry["fires"]) > 0 and not entry.has("outcome"):
			_mark(entry, "contributed", int(entry["fired_round"]))
		if entry.has("outcome"):
			closed.append(entry)
		else:
			rest.append(entry)
	pending = rest

## 결론을 찍기만 한다. pending에서 빼는 것은 _sweep 한 곳이다 —
## 순회 중에 erase하면 뒤 항목을 건너뛴다.
func _mark(entry: Dictionary, outcome: String, round_index: int) -> void:
	entry["outcome"] = outcome
	entry["closed_round"] = round_index

static func _use_of(inv: RefCounted, uid: int) -> String:
	for slot_id: String in inv.board:
		var slot: Dictionary = inv.board[slot_id]
		if int(slot.get("active", Inventory.NONE)) == uid:
			return "body"
		if int(slot.get("augment", Inventory.NONE)) == uid:
			return "augment"
	return "storage" if inv.part_id_of(uid) != "" else "gone"

## 이 개체의 평가 단위가 지금 도는가. analysis는 Graph.analyze()의 결과.
static func _is_active(inv: RefCounted, uid: int, use: String,
		analysis: Dictionary) -> bool:
	var slot_id: String = inv.slot_of(uid)
	if slot_id == "":
		return false
	var units: Array = analysis["units"]
	var active: Dictionary = analysis["active"]
	for i: int in units.size():
		var unit: Dictionary = units[i]
		if str(unit["slot"]) == slot_id and str(unit["kind"]) == use:
			return active.has(i)
	# 평가 단위가 아예 없다 = 어휘가 없는 파츠(inert). 기다릴 것이 없으므로 투자가 아니다.
	return true

## 리포터용 집계. 4단계의 결과를 종류별로 센다.
func tally() -> Dictionary:
	var out: Dictionary = {"stored": {}, "silent": {}}
	for entry: Dictionary in closed:
		var bucket: Dictionary = out[str(entry["kind"])]
		var outcome: String = str(entry["outcome"])
		bucket[outcome] = int(bucket.get(outcome, 0)) + 1
	return out
