class_name UiStyle
## Shared UI look: Fredoka at a chosen weight, ink text, rounded boxes.

const FONT := preload("res://assets/fonts/Fredoka.ttf")
const TEXT_SIZE := 26


## Fredoka is a variable font; this picks one weight from it.
static func font(weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = FONT
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	variation.variation_opentype = {wght: weight}
	return variation


static func theme(weight := 600, size := TEXT_SIZE) -> Theme:
	var result := Theme.new()
	result.default_font = font(weight)
	result.default_font_size = size
	return result


static func box(color: Color, radius := 11) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.anti_aliasing = true
	return result


static func panel_box() -> StyleBoxFlat:
	var result := box(Color(Palette.BACKGROUND, 0.95), 20)
	result.set_border_width_all(4)
	result.border_color = Palette.INK
	result.set_content_margin_all(24)
	return result


static func label(alignment := HORIZONTAL_ALIGNMENT_LEFT, size := TEXT_SIZE) -> Label:
	var result := Label.new()
	result.horizontal_alignment = alignment
	result.add_theme_color_override("font_color", Palette.INK)
	result.add_theme_font_size_override("font_size", size)
	return result


## Menu button: white with an ink outline, green when hovered or focused.
static func button(text: String, width := 320.0) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(width, 56)
	result.focus_mode = Control.FOCUS_ALL
	result.add_theme_font_override("font", font(600))
	result.add_theme_font_size_override("font_size", 26)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.add_theme_color_override(state, Palette.INK)
	var styles := {
		"normal": Palette.WHITE,
		"hover": Palette.PLAYER,
		"pressed": Palette.PLAYER.darkened(0.15),
		"focus": Palette.PLAYER,
	}
	for state: String in styles:
		var style := box(styles[state], 16)
		style.set_border_width_all(4)
		style.border_color = Palette.INK
		result.add_theme_stylebox_override(state, style)
	return result


## Centered, outlined panel for menus (pause, about, controls).
static func menu_panel(min_width := 520.0) -> PanelContainer:
	var result := PanelContainer.new()
	result.custom_minimum_size = Vector2(min_width, 0)
	var style := panel_box()
	style.set_content_margin_all(36)
	result.add_theme_stylebox_override("panel", style)
	return result
