@tool
extends Control
## BuildingForge dock: building creation, presets, draw tools, utilities.

var plugin: EditorPlugin = null

var _draw_btn: Button = null
var _shape_opt: OptionButton = null
var _info: Label = null


func _ready() -> void:
        name = "BuildingForge"
        custom_minimum_size = Vector2(230, 0)
        var vbox := VBoxContainer.new()
        vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(vbox)

        var title := Label.new()
        title.text = "BuildingForge"
        title.add_theme_font_size_override("font_size", 17)
        vbox.add_child(title)
        var subtitle := Label.new()
        subtitle.text = "Procedural Building Generator"
        subtitle.add_theme_color_override("font_color", Color(1, 0.72, 0.2))
        subtitle.add_theme_font_size_override("font_size", 11)
        vbox.add_child(subtitle)

        vbox.add_child(HSeparator.new())
        var create_btn := Button.new()
        create_btn.text = "Create Building"
        create_btn.pressed.connect(func():
                if plugin != null:
                        plugin.create_building())
        vbox.add_child(create_btn)

        vbox.add_child(HSeparator.new())
        var presets_label := Label.new()
        presets_label.text = "Presets"
        presets_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
        vbox.add_child(presets_label)
        for preset in ["suburban_house", "cottage", "village_house", "modern_villa", "mansion",
                        "townhouse", "apartment_block", "shop_apartments", "office_tower",
                        "setback_tower", "circular_tower"]:
                var pb := Button.new()
                pb.text = preset.replace("_", " ").capitalize()
                pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                pb.pressed.connect(func():
                        if plugin != null:
                                plugin.apply_preset(preset))
                vbox.add_child(pb)

        vbox.add_child(HSeparator.new())
        var draw_label := Label.new()
        draw_label.text = "Footprint Draw Tool"
        draw_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
        vbox.add_child(draw_label)
        _shape_opt = OptionButton.new()
        _shape_opt.add_item("Rectangle")
        _shape_opt.add_item("Circle")
        _shape_opt.add_item("Polygon")
        vbox.add_child(_shape_opt)
        _draw_btn = Button.new()
        _draw_btn.text = "Draw Footprint"
        _draw_btn.toggle_mode = true
        _draw_btn.pressed.connect(_on_draw_toggled)
        vbox.add_child(_draw_btn)

        vbox.add_child(HSeparator.new())
        var rand_btn := Button.new()
        rand_btn.text = "Randomize Seed"
        rand_btn.pressed.connect(func():
                if plugin != null:
                        plugin.randomize_seed())
        vbox.add_child(rand_btn)
        var finalize_btn := Button.new()
        finalize_btn.text = "Finalize (Bake Static)"
        finalize_btn.tooltip_text = "Convert the selected building into plain,\nhand-editable nodes. The generator is removed."
        finalize_btn.pressed.connect(func():
                if plugin != null:
                        plugin.finalize_selected())
        vbox.add_child(finalize_btn)
        var bake_btn := Button.new()
        bake_btn.text = "Rebake Textures"
        bake_btn.pressed.connect(func():
                if plugin != null:
                        plugin.rebake_textures(1.0))
        vbox.add_child(bake_btn)

        vbox.add_child(HSeparator.new())
        _info = Label.new()
        _info.text = "Select a building and edit\nparameters in the Inspector.\nDrag corners/roof handles to\nreshape; drag a wall-edge\nmidpoint to add a bend point.\nRight-click a wall to cut\nwindows/doors or move the\nentrance. Move any part;\nyour edits survive regen."
        _info.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
        _info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _info.custom_minimum_size = Vector2(210, 80)
        vbox.add_child(_info)


func _on_draw_toggled() -> void:
        if plugin == null:
                return
        plugin.set_draw_mode(_draw_btn.button_pressed, _shape_opt.selected)
