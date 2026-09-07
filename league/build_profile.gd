extends RefCounted
## 빌드 하나의 **구조 분류**. 고정 상대군을 다양성 기준으로 고르기 위한 것이다
## (r5b 피드백 §8.4: "상대 수를 많이 늘리기보다 서로 다른 공격·방어·시동 구조를 포함").
##
## 분류는 전부 `part_meta`가 파츠 정의에서 이미 뽑아 놓은 어휘로 한다. 여기서 파츠
## 이름을 다시 열거하면 파츠를 고칠 때마다 어긋나고, 그 어긋남이 "상대군이 다양하다"는
## 거짓 주장이 된다.
##
## **이 분류는 강도가 아니다.** 어떤 축이 몇 개인지만 말한다 — 어느 구조가 센지는
## 고정 상대군에 붙여 봐야 안다.

const Graph = preload("res://league/build_graph.gd")

## 공격 경로 분류. `damage_paths`(direct/overheat/corrosion/fracture)의 집합이다.
## 활성 단위만 센다 — 침묵한 파츠의 어휘는 그 빌드가 실제로 하는 일이 아니다.
static func attack_profile(analysis: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for i: int in (analysis["units"] as Array).size():
		if not (analysis["active"] as Dictionary).has(i):
			continue
		var meta: Dictionary = ((analysis["units"] as Array)[i] as Dictionary)["meta"]
		for path: String in (meta["damage_paths"] as Array):
			if not out.has(path):
				out.append(path)
	out.sort()
	return out

## 방어 구조 분류. 회복·보호막·시간 조작 중 무엇을 쓰는가.
##
## `functions`에서 읽는다: heal(회복) / defend(보호막) / time(가속·둔화·정지).
## 셋은 서로 다른 생존 방식이고, 상대군에 하나만 들어 있으면 그 축의 대응을
## 시험하지 못한다.
static func defense_profile(analysis: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for i: int in (analysis["units"] as Array).size():
		if not (analysis["active"] as Dictionary).has(i):
			continue
		var meta: Dictionary = ((analysis["units"] as Array)[i] as Dictionary)["meta"]
		for fn: String in (meta["functions"] as Array):
			if ["heal", "defend", "time"].has(fn) and not out.has(fn):
				out.append(fn)
	out.sort()
	return out

## 시동 구조. 전투 시작부터 스스로 도는가, 무언가를 받아야 시작하는가.
##
## "immediate"  전제 없이 도는 본체가 있다
## "gated"      도는 본체는 있지만 시동에 전제가 걸린 단위가 함께 있다
## "dependent"  활성 단위가 전부 무언가에 의존한다
##
## 이 축을 넣는 이유: 시동이 느린 빌드는 초반 상대에게만 지고 후반 상대에게는
## 이기는 식으로 결과가 갈린다. 상대군이 한쪽뿐이면 그 차이가 보이지 않는다.
static func startup_profile(analysis: Dictionary) -> String:
	var immediate: int = 0
	var gated: int = 0
	for i: int in (analysis["units"] as Array).size():
		if not (analysis["active"] as Dictionary).has(i):
			continue
		var meta: Dictionary = ((analysis["units"] as Array)[i] as Dictionary)["meta"]
		if bool(meta.get("inert", false)):
			continue
		if bool(meta["startup_required"]):
			gated += 1
		else:
			immediate += 1
	if immediate == 0:
		return "dependent"
	return "gated" if gated > 0 else "immediate"

## 사람이 읽고 파일에 남길 한 줄 요약.
static func of(analysis: Dictionary) -> Dictionary:
	var attack: Array[String] = attack_profile(analysis)
	return {
		"attack": attack,
		"defense": defense_profile(analysis),
		"startup": startup_profile(analysis),
		"active_units": (analysis["active"] as Dictionary).size(),
		"dead_units": (analysis["dead"] as Array).size(),
		"output_60s": snappedf(float(analysis["output"]), 0.01),
		"sustain_60s": snappedf(float(analysis["sustain"]), 0.01),
		"operational": bool(analysis["operational"]),
	}

## 다양성 버킷 키. 이 키가 다르면 "서로 다른 구조"로 본다.
##
## 출력 크기를 키에 넣지 않는다 — 강한 것과 약한 것을 나누는 것이 아니라
## **작동 방식**을 나누는 것이 목적이기 때문이다 (§8.4의 "상한 생존 빌드만으로
## 구성하지 않음"도 같은 뜻이다).
static func bucket_of(profile: Dictionary) -> String:
	var attack: String = "none"
	if not (profile["attack"] as Array).is_empty():
		attack = "+".join(profile["attack"])
	var defense: String = "none"
	if not (profile["defense"] as Array).is_empty():
		defense = "+".join(profile["defense"])
	return "%s|%s|%s" % [attack, defense, profile["startup"]]

## 획득 단계 구간. §8.4의 "초·중반 및 다른 엔진을 포함한 상대군".
static func stage_of(round_index: int) -> String:
	if round_index <= 2:
		return "early"
	# late를 라운드 8 이상으로 잡는다. 처음엔 7 이상이었는데, 그러면 상대군의
	# "후반"이 전부 정확히 7라운드가 되어 실제 후반 빌드가 하나도 안 들어왔다 —
	# 그 상대군에 레시피 완성 보드를 붙이니 셋 다 100%가 나와 해상도가 없었다.
	if round_index <= 7:
		return "mid"
	return "late"
