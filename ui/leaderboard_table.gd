class_name LeaderboardTable
extends VBoxContainer
## The global top scores as a titled grid (rank, name, points, wave), with a status line
## for loading, errors and an empty table. Used on the Arcade page and at game over.

const COLUMNS := 4

var status: Label
var rows: GridContainer


func _init(text_size := 22, title := "Mejores puntajes") -> void:
	add_theme_constant_override("separation", 8)
	var heading := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, text_size + 2)
	heading.text = title
	heading.add_theme_font_override("font", UiStyle.font(700))
	add_child(heading)
	status = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, text_size)
	status.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
	add_child(status)
	rows = GridContainer.new()
	rows.columns = COLUMNS
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_theme_constant_override("h_separation", 24)
	rows.add_theme_constant_override("v_separation", 4)
	rows.set_meta("text_size", text_size)
	add_child(rows)
	show_loading()


func show_loading() -> void:
	_clear()
	_status("Cargando la tabla…")


## A message instead of the table (for example, a run that does not count).
func show_note(text: String) -> void:
	_clear()
	_status(text)


func show_error() -> void:
	_clear()
	_status("No se pudo cargar la tabla")


## The first row matching this name and score is highlighted (pass score -1 for none).
func show_rows(entries: Array, player_name: String, score: int) -> void:
	_clear()
	if entries.is_empty():
		_status("Todavía no hay puntajes")
		return
	status.visible = false
	var size: int = rows.get_meta("text_size")
	var marked := false
	for i in entries.size():
		var row: Dictionary = entries[i]
		var mine: bool = not marked and row.name == player_name and row.score == score
		marked = marked or mine
		var cells := ["%d." % (i + 1), row.name, str(row.score), "Oleada %d" % row.wave]
		for c in COLUMNS:
			var cell := UiStyle.label(HORIZONTAL_ALIGNMENT_RIGHT if c != 1 else HORIZONTAL_ALIGNMENT_LEFT, size)
			cell.text = cells[c]
			cell.add_theme_font_override("font", UiStyle.font(700 if mine else 500))
			if mine:
				cell.add_theme_color_override("font_color", Palette.PLAYER.darkened(0.35))
			rows.add_child(cell)


func _clear() -> void:
	for child in rows.get_children():
		child.free()


func _status(text: String) -> void:
	status.text = text
	status.visible = true
