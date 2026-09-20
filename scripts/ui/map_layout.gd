class_name MapLayout
extends RefCounted
## GENERATED FILE -- do not edit by hand.
##
## Baked from assets/map/layout.json and assets/map/layout_bonus.json by
## tools/bake_layout.gd. Edit those and re-run the tool:
##
##   godot --headless --path . --script res://tools/bake_layout.gd
##
## It is baked rather than read at runtime because export_presets.cfg excludes
## *.json from every preset, so the .json is not present in a shipped build.

const SIZE := Vector2i(960, 640)

## Pool sprite size in pixels; also the click target for a pool.
const POOL_SIZE := Vector2i(88, 60)

const POOLS := [
	{"level": 1, "x": 118, "y": 126, "pool": [74, 96], "shells": [[90, 94], [108, 94], [126, 94]], "digits": [[112, 118]], "bonus": false},
	{"level": 2, "x": 270, "y": 114, "pool": [226, 84], "shells": [[242, 82], [260, 82], [278, 82]], "digits": [[264, 106]], "bonus": false},
	{"level": 3, "x": 400, "y": 118, "pool": [356, 88], "shells": [[372, 86], [390, 86], [408, 86]], "digits": [[394, 110]], "bonus": false},
	{"level": 4, "x": 552, "y": 112, "pool": [508, 82], "shells": [[524, 80], [542, 80], [560, 80]], "digits": [[546, 104]], "bonus": false},
	{"level": 5, "x": 704, "y": 124, "pool": [660, 94], "shells": [[676, 92], [694, 92], [712, 92]], "digits": [[698, 116]], "bonus": false},
	{"level": 6, "x": 834, "y": 124, "pool": [790, 94], "shells": [[806, 92], [824, 92], [842, 92]], "digits": [[828, 116]], "bonus": false},
	{"level": 7, "x": 122, "y": 226, "pool": [78, 196], "shells": [[94, 194], [112, 194], [130, 194]], "digits": [[116, 218]], "bonus": false},
	{"level": 8, "x": 274, "y": 228, "pool": [230, 198], "shells": [[246, 196], [264, 196], [282, 196]], "digits": [[268, 220]], "bonus": false},
	{"level": 9, "x": 404, "y": 218, "pool": [360, 188], "shells": [[376, 186], [394, 186], [412, 186]], "digits": [[398, 210]], "bonus": false},
	{"level": 10, "x": 556, "y": 226, "pool": [512, 196], "shells": [[528, 194], [546, 194], [564, 194]], "digits": [[542, 218], [558, 218]], "bonus": false},
	{"level": 11, "x": 686, "y": 224, "pool": [642, 194], "shells": [[658, 192], [676, 192], [694, 192]], "digits": [[672, 216], [688, 216]], "bonus": false},
	{"level": 12, "x": 838, "y": 238, "pool": [794, 208], "shells": [[810, 206], [828, 206], [846, 206]], "digits": [[824, 230], [840, 230]], "bonus": false},
	{"level": 13, "x": 126, "y": 384, "pool": [82, 354], "shells": [[98, 352], [116, 352], [134, 352]], "digits": [[112, 376], [128, 376]], "bonus": false},
	{"level": 14, "x": 256, "y": 372, "pool": [212, 342], "shells": [[228, 340], [246, 340], [264, 340]], "digits": [[242, 364], [258, 364]], "bonus": false},
	{"level": 15, "x": 408, "y": 376, "pool": [364, 346], "shells": [[380, 344], [398, 344], [416, 344]], "digits": [[394, 368], [410, 368]], "bonus": false},
	{"level": 16, "x": 560, "y": 370, "pool": [516, 340], "shells": [[532, 338], [550, 338], [568, 338]], "digits": [[546, 362], [562, 362]], "bonus": false},
	{"level": 17, "x": 690, "y": 382, "pool": [646, 352], "shells": [[662, 350], [680, 350], [698, 350]], "digits": [[676, 374], [692, 374]], "bonus": false},
	{"level": 18, "x": 842, "y": 382, "pool": [798, 352], "shells": [[814, 350], [832, 350], [850, 350]], "digits": [[828, 374], [844, 374]], "bonus": false},
	{"level": 19, "x": 130, "y": 516, "pool": [86, 486], "shells": [[102, 484], [120, 484], [138, 484]], "digits": [[116, 508], [132, 508]], "bonus": false},
	{"level": 20, "x": 260, "y": 516, "pool": [216, 486], "shells": [[232, 484], [250, 484], [268, 484]], "digits": [[246, 508], [262, 508]], "bonus": false},
	{"level": 21, "x": 412, "y": 512, "pool": [368, 482], "shells": [[384, 480], [402, 480], [420, 480]], "digits": [[398, 504], [414, 504]], "bonus": false},
	{"level": 22, "x": 542, "y": 518, "pool": [498, 488], "shells": [[514, 486], [532, 486], [550, 486]], "digits": [[528, 510], [544, 510]], "bonus": false},
	{"level": 23, "x": 694, "y": 512, "pool": [650, 482], "shells": [[666, 480], [684, 480], [702, 480]], "digits": [[680, 504], [696, 504]], "bonus": false},
	{"level": 24, "x": 846, "y": 518, "pool": [802, 488], "shells": [[818, 486], [836, 486], [854, 486]], "digits": [[832, 510], [848, 510]], "bonus": false},
	{"level": 25, "x": 640, "y": 592, "pool": [596, 562], "shells": [[612, 560], [630, 560], [648, 560]], "digits": [[626, 584], [642, 584]], "bonus": true},
	{"level": 26, "x": 732, "y": 606, "pool": [688, 576], "shells": [[704, 574], [722, 574], [740, 574]], "digits": [[718, 598], [734, 598]], "bonus": true},
	{"level": 27, "x": 824, "y": 590, "pool": [780, 560], "shells": [[796, 558], [814, 558], [832, 558]], "digits": [[810, 582], [826, 582]], "bonus": true},
	{"level": 28, "x": 914, "y": 604, "pool": [870, 574], "shells": [[886, 572], [904, 572], [922, 572]], "digits": [[900, 596], [916, 596]], "bonus": true},
]
