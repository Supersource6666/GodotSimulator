extends RefCounted
## Repair only short, extreme terrain sampling holes/spikes; keep normal relief.
const OUTLIER_THRESHOLD_M := 20.0
const MAX_RUN := 4

static func repair(route: Array, ground: Array) -> Dictionary:
	var heights := ground.duplicate()
	var repaired: Array[int] = []
	if route.size() != ground.size():
		return {"heights": heights, "indices": repaired}
	var bad: Array[bool] = []
	for i in range(ground.size()):
		var window: Array[float] = []
		for j in range(maxi(0, i - 4), mini(ground.size(), i + 5)):
			window.append(float(ground[j]))
		window.sort()
		bad.append(absf(float(ground[i]) - window[window.size() / 2]) > OUTLIER_THRESHOLD_M)
	var i := 0
	while i < ground.size():
		if not bad[i]:
			i += 1
			continue
		var start := i
		while i < ground.size() and bad[i]:
			i += 1
		if start == 0 or i == ground.size() or i - start > MAX_RUN:
			continue
		var chain := PackedFloat64Array([0.0])
		for j in range(start, i + 1):
			var a: Array = route[j - 1]
			var b: Array = route[j]
			chain.append(chain[chain.size() - 1] + Vector2(float(b[0]) - float(a[0]), float(b[2]) - float(a[2])).length())
		var span := chain[chain.size() - 1]
		if span <= 0.001:
			continue
		for j in range(start, i):
			heights[j] = lerpf(float(ground[start - 1]), float(ground[i]), chain[j - start + 1] / span)
			repaired.append(j)
	return {"heights": heights, "indices": repaired}
