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
