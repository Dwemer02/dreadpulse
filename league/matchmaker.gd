extends RefCounted
## 같은 라운드 참가자를 짝짓는다. 기획서 §8.1~§8.2.
##
## 결정론이 이 파일의 계약이다: 참가자 목록을 **안정적으로 정렬한 뒤** 매칭 난수로
## 섞는다. 실행 병렬 순서나 Dictionary 순회 순서가 결과를 바꾸면 안 된다 (§8.1 마지막).

const Config = preload("res://league/league_config.gd")

## 반환: {pairs: [[a, b]], fill: [{participant, opponent_snapshot}], censored: [...]}
##
## a·b는 참가자 인덱스다. fill은 짝이 없어 **같은 라운드 스냅샷의 복제본**과 싸우는
## 참가자다 (§8.2) — 복제 상대는 결과를 반영받지 않는다.
static func pair(active: Array, round_index: int, config: RefCounted,
		snapshots: Array) -> Dictionary:
	if active.is_empty():
		return {"pairs": [], "fill": [], "censored": []}
	if active.size() == 1:
		# 활성 참가자가 1명이고 같은 라운드 스냅샷도 없으면 배치를 끝낸다.
		# 이것은 우승도 탈락도 아니라 **관측 중단**이다 (§8.2).
		if snapshots.size() <= 1:
			return {"pairs": [], "fill": [], "censored": [active[0]]}
		return {"pairs": [], "fill": [{"participant": active[0],
			"opponent": _other_snapshot(snapshots, active[0], round_index, config)}],
			"censored": []}

	var rng: RandomNumberGenerator = Config.rng_for(
		["match", config.batch_id, round_index])
	var order: Array = active.duplicate()
	order.sort()  # 안정적인 기준 정렬 — 섞기 전의 출발점을 고정한다

	var random_group: Array = []
	var ranked_group: Array = []
	if round_index <= config.random_opening_rounds:
		random_group = order
	else:
		# 참가자의 약 20%를 무작위 매칭 구간으로 뽑고, 나머지는 승점끼리 붙인다 (§8.1).
		var want: int = int(round(float(order.size()) * config.later_random_fraction))
		var pool: Array = order.duplicate()
		_shuffle(pool, rng)
		random_group = pool.slice(0, want)
		ranked_group = pool.slice(want)
		# 승점 정렬. 동점은 참가자 인덱스로 갈라 재현을 보장한다.
		ranked_group.sort_custom(func(a: int, b: int) -> bool:
			var pa: int = int((snapshots[a] as Dictionary)["points"])
			var pb: int = int((snapshots[b] as Dictionary)["points"])
			return a < b if pa == pb else pa > pb)

	_shuffle(random_group, rng)
	var queue: Array = random_group + ranked_group

	var pairs: Array = []
	var fill: Array = []
	var used: Dictionary = {}
	for i: int in queue.size():
		var a: int = int(queue[i])
		if used.has(a):
			continue
		var partner: int = _find_partner(queue, used, a, snapshots)
		if partner < 0:
			continue
		used[a] = true
		used[partner] = true
		pairs.append([a, partner])
	for id: Variant in queue:
		if not used.has(int(id)):
			fill.append({"participant": int(id),
				"opponent": _other_snapshot(snapshots, int(id), round_index, config)})
	return {"pairs": pairs, "fill": fill, "censored": []}

## 최근 상대와의 재대결을 가능한 한 피한다. **매칭 불능보다 우선하지 않는다** (§8.1) —
## 피할 수 없으면 그냥 붙인다.
static func _find_partner(queue: Array, used: Dictionary, a: int, snapshots: Array) -> int:
	var fallback: int = -1
	var recent: Array = (snapshots[a] as Dictionary).get("recent_opponents", [])
	for candidate: Variant in queue:
		var b: int = int(candidate)
		if b == a or used.has(b):
			continue
		if fallback < 0:
			fallback = b
		if not recent.has(b):
			return b
	return fallback

## 자신을 제외한 같은 라운드 스냅샷 하나. 당시 상태를 그대로 쓰고 성장·보상은 없다.
static func _other_snapshot(snapshots: Array, self_index: int, round_index: int,
		config: RefCounted) -> int:
	var rng: RandomNumberGenerator = Config.rng_for(
		["fill", config.batch_id, round_index, self_index])
	var pool: Array[int] = []
	for i: int in snapshots.size():
		if i != self_index and not (snapshots[i] as Dictionary).get("build", {}).is_empty():
			pool.append(i)
	if pool.is_empty():
		return -1
	return pool[rng.randi_range(0, pool.size() - 1)]

## Fisher-Yates. 주입 RNG만 쓴다 — 전역 난수를 쓰면 배치가 재현되지 않는다.
static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(list.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp
