class_name CardView
extends PanelContainer

signal selected(card: CardInstance)

const DESC_MAX_FONT := 16
const DESC_MIN_FONT := 9

@onready var name_label: Label = %NameLabel
@onready var cost_label: Label = %CostLabel
@onready var artwork: TextureRect = %Artwork
@onready var description_label: Label = %DescriptionLabel
@onready var select_button: Button = %SelectButton

var card: CardInstance
var is_playable := true
var hover_tween: Tween


func _ready() -> void:
	_update_pivot()
	resized.connect(_update_pivot)


func display(card_instance: CardInstance) -> void:
	card = card_instance
	name_label.text = card.definition.display_name
	cost_label.text = str(card.get_energy_cost())
	artwork.texture = card.definition.artwork
	description_label.text = card.definition.description
	# Shrink the description font until it fits its box, so long text never overflows the card.
	call_deferred("_fit_description")


func set_playable(is_playable: bool) -> void:
	self.is_playable = is_playable
	select_button.disabled = not is_playable
	self_modulate = Color.WHITE if is_playable else Color(0.55, 0.55, 0.55, 1.0)
	if not is_playable:
		_reset_hover()


func set_preview_mode() -> void:
	is_playable = false
	select_button.disabled = true
	self_modulate = Color.WHITE
	_reset_hover()


func show_reward_result(is_selected: bool) -> void:
	is_playable = false
	select_button.disabled = true
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
	var target_scale := Vector2(1.1, 1.1) if is_selected else Vector2(0.94, 0.94)
	var target_color := Color.WHITE if is_selected else Color(0.32, 0.34, 0.4, 0.72)
	z_index = 20 if is_selected else 0
	if is_selected:
		var selected_style := StyleBoxFlat.new()
		selected_style.bg_color = Color(0.09, 0.105, 0.14, 1.0)
		selected_style.border_color = Color(0.95, 0.55, 0.22, 1.0)
		selected_style.set_border_width_all(3)
		selected_style.set_corner_radius_all(7)
		selected_style.shadow_color = Color(1.0, 0.35, 0.08, 0.32)
		selected_style.shadow_size = 10
		add_theme_stylebox_override("panel", selected_style)
	hover_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hover_tween.set_parallel(true)
	hover_tween.tween_property(self, "scale", target_scale, 0.22)
	hover_tween.tween_property(self, "self_modulate", target_color, 0.22)


func animate_play_toward(target_global_position: Vector2) -> void:
	set_playable(false)
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
	self_modulate = Color.WHITE
	z_index = 100
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", target_global_position - size * 0.5, 0.24)
	tween.tween_property(self, "scale", Vector2(0.72, 0.72), 0.24)
	tween.tween_property(self, "modulate:a", 0.0, 0.24)
	await tween.finished


func _on_select_button_pressed() -> void:
	selected.emit(card)


func _on_select_button_mouse_entered() -> void:
	if not is_playable:
		return
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
	z_index = 10
	hover_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.14)


func _on_select_button_mouse_exited() -> void:
	if not is_playable:
		return
	_reset_hover()


func _reset_hover() -> void:
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
	z_index = 0
	hover_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "scale", Vector2.ONE, 0.1)


func _fit_description() -> void:
	var font := description_label.get_theme_font("font")
	if font == null:
		return
	var avail := description_label.size
	if avail.x <= 0.0 or avail.y <= 0.0:
		# Layout not resolved yet; retry next frame.
		call_deferred("_fit_description")
		return
	var chosen := DESC_MIN_FONT
	for candidate in range(DESC_MAX_FONT, DESC_MIN_FONT - 1, -1):
		var needed := font.get_multiline_string_size(
			description_label.text, HORIZONTAL_ALIGNMENT_LEFT, avail.x, candidate)
		if needed.y <= avail.y:
			chosen = candidate
			break
	description_label.add_theme_font_size_override("font_size", chosen)


func _update_pivot() -> void:
	pivot_offset = size * 0.5
