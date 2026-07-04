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
