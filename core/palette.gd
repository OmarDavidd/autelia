class_name Palette
## Style guide "Juguete pastel" (direction A) with hatched shadows and bullet trails from direction B.

const BACKGROUND := Color("eaf6ee")
const FLOOR := Color("f7fbf8")
const INK := Color("2b2340")
const INK_SOFT := Color(0.169, 0.137, 0.251, 0.55)
const PLAYER := Color("3ddc97")
## One color per co-op player; the first is the classic green.
const PLAYER_COLORS: Array[Color] = [
	PLAYER, Color("4da6ff"), Color("b98cff"), Color("ffd84d"),
	Color("26c6da"), Color("a3e635"), Color("e879f9"), Color("f8fafc"),
]
const ENEMY := Color("ff6b8b")
const SHOOTER := Color("ffb547")
const WHITE := Color("ffffff")
const OUTLINE_WIDTH := 4.0
const ART_RADIUS := 18.0
