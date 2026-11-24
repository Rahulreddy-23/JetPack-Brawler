class_name Menu
extends Control
## Minimal start menu (Host, IP field, Join) and, once a session runs, a small
## strip that shows the host's addresses (or the joined address) and a Leave button.

signal host_pressed
signal join_pressed(address: String)
signal leave_pressed

## Longest IP literal: a full IPv6 address is 39 characters, 45 with an embedded IPv4 tail.
const ADDRESS_MAX_LENGTH: int = 45

var _form: VBoxContainer
var _message: Label
var _address_field: LineEdit
var _strip: HBoxContainer
var _strip_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_form()
	_build_strip()
	show_menu("")

## Show the start menu, with an optional message (for example why a session ended).
func show_menu(message: String) -> void:
	_form.visible = true
	_strip.visible = false
	_message.text = message

## Show the in-session strip with a line of text.
func show_session(text: String) -> void:
	_form.visible = false
	_strip.visible = true
	_strip_label.text = text

func _build_form() -> void:
	_form = VBoxContainer.new()
	_form.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_form.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_form.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_form)

	var title: Label = Label.new()
	title.text = "Jetpack Brawler prototype"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_form.add_child(title)

	var host_button: Button = Button.new()
	host_button.text = "Host"
	host_button.pressed.connect(func() -> void: host_pressed.emit())
	_form.add_child(host_button)

	_address_field = LineEdit.new()
	_address_field.placeholder_text = "Host IP address"
	_address_field.max_length = ADDRESS_MAX_LENGTH
	_address_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_address_field.gui_input.connect(_on_address_input)
	_form.add_child(_address_field)

	var join_button: Button = Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(func() -> void: join_pressed.emit(_address_field.text.strip_edges()))
	_form.add_child(join_button)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(_message)

func _on_address_input(event: InputEvent) -> void:
	# Mouse emulation from touch is off (the gameplay sticks use raw touch), so
	# bring the IP field into edit mode on a tap. Not tested on a device.
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_address_field.edit()

func _build_strip() -> void:
	_strip = HBoxContainer.new()
	_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_strip)

	_strip_label = Label.new()
	_strip.add_child(_strip_label)

	var leave_button: Button = Button.new()
	leave_button.text = "Leave"
	leave_button.pressed.connect(func() -> void: leave_pressed.emit())
	_strip.add_child(leave_button)
