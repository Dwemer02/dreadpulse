extends SceneTree
## 씬을 실제로 열어 본다. **단위 테스트는 씬을 로드하지 않는다** — 그래서 리포터의
## 문법 오류를 배치가 잡지 못했던 것과 같은 일이 화면에서도 일어난다.
##
## 실행:
##   godot --headless --path . --script res://tests/check_scenes.gd
##
## 여는 것만으로 파싱·preload·_ready의 오류가 전부 드러난다. 헤드리스에서도
## Control 트리는 만들어진다 — 그리지 않을 뿐이다.

const SCENES: Array[String] = [
	"res://debug/voyage_view.tscn",
	"res://debug/run_view.tscn",
	"res://debug/combat_view.tscn",
]

func _init() -> void:
	var failed: int = 0
	for path: String in SCENES:
		var packed: PackedScene = load(path)
		if packed == null:
			print("  FAIL  %s — 로드할 수 없다" % path)
			failed += 1
			continue
		var node: Node = packed.instantiate()
		if node == null:
			print("  FAIL  %s — 인스턴스화할 수 없다" % path)
			failed += 1
			continue
		# **스크립트가 붙었는지 본다.** 스크립트 컴파일이 실패하면 씬은 그대로
		# 인스턴스화되고 루트의 스크립트만 null이 된다 — 첫 판본이 그 상태를
		# "ok"로 넘겼다.
		if node.get_script() == null:
			print("  FAIL  %s — 루트 스크립트가 붙지 않았다 (컴파일 실패)" % path)
			failed += 1
			node.queue_free()
			continue
		root.add_child(node)
		# 한 프레임 돌려 _ready와 첫 _process까지 지난다.
		await process_frame
		await process_frame
		print("  ok    %s — 자식 %d개" % [path, node.get_child_count()])
		node.queue_free()
	print("씬 %d개 · 실패 %d개" % [SCENES.size(), failed])
	failed += await _drive_voyage()
	quit(1 if failed > 0 else 0)


## **화면을 실제로 조작한다** (A~G 검토 §8.3 마지막: "적어도 한 번은 실제 시작
## 화면에서 조립→전투→보상→종료→내보내기까지 조작한다").
##
## 사람의 클릭 대신 같은 핸들러를 부른다. 화면에만 있는 경로 — 카드 만들기, 보드 행,
## 재생 컨트롤, 결과표 — 가 실제로 도는지는 이렇게만 확인할 수 있다.
func _drive_voyage() -> int:
	print("")
	print("── 화면 조작 (§8.3) ──────────────────────────────────────────")
	var view: Node = load("res://debug/voyage_view.tscn").instantiate()
	root.add_child(view)
	await process_frame
	if view._state == null:
		print("  FAIL  항해가 시작되지 않았다")
		return 1

	var guard: int = 0
	while str(view._state.status) == "active" and guard < 60:
		guard += 1
		await process_frame
		if view._replaying:
			# '결과까지'와 같은 경로 — 남은 이벤트를 흘려보낸다.
			while view._cursor < view._display.size():
				view._consume(view._display[view._cursor])
				view._cursor += 1
			view._finish_replay()
			continue
		match str(view._state.phase):
			"choice":
				view._on_choose(0)
			"assemble":
				var uid: int = int(view._state.pending_uid)
				if uid != -1:
					view._on_select(uid)
					var targets: Dictionary = view._targets(uid)
					if not (targets["bodies"] as Array).is_empty():
						view._on_command({"kind": "place", "uid": uid,
							"slot": str((targets["bodies"] as Array)[0])})
					view._state.pending_uid = -1
					view._refresh()
				if str(view._state.next_action()) == "offer":
					view._state.open_offer()
					view._refresh()
				else:
					# 보관이 넘치면 사람이 고르는 자리다 — 여기서는 가장 오래된 것을 버린다.
					while int(view._state.launch_check()["storage_over"]) > 0:
						var spare: Array = view._state.inventory.unplaced()
						if spare.is_empty():
							break
						view._on_command({"kind": "discard",
							"uid": int((spare[0] as Dictionary)["uid"])})
					view._on_launch()
			"result":
				view._state.continue_after_result()
				view._combat_result = {}
				view._refresh()
			_:
				break
	print("  항해 %s · %s" % [str(view._state.status),
		str(view._state.progress_line())])
	view._on_save()
	view._on_export()
	print("  저장·내보내기 %s" % str(view._toast.text))

	# 실험실도 한 번 돈다.
	view._mode = "lab"
	view._start_voyage()
	await process_frame
	view._lab.load_player("ve_starter_ward")
	view._on_lab_fight()
	await process_frame
	while view._cursor < view._display.size():
		view._consume(view._display[view._cursor])
		view._cursor += 1
	view._finish_replay()
	var lab_ok: bool = not view._combat_result.is_empty()
	print("  실험실 전투 %s" % ("정리 표시됨" if lab_ok else "결과 없음"))
	view.queue_free()
	return 0 if lab_ok and guard < 60 else 1
