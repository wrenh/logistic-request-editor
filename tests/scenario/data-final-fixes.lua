local styles = data.raw["gui-style"].default
local button_styles = {}
button_styles.content_vertical_spacing = styles.first_factorio_mod_edit_content_scroll.vertical_flow_style.vertical_spacing
button_styles.content_always_draw_borders = styles.first_factorio_mod_edit_content_scroll.always_draw_borders
button_styles.content_inset_matches_frame = table.compare(
  styles.first_factorio_mod_edit_content_scroll.graphical_set, styles.inside_shallow_frame.graphical_set)
local content_style = styles.first_factorio_mod_edit_content_scroll
button_styles.content_left_padding = content_style.left_padding or content_style.padding
button_styles.content_right_padding = content_style.right_padding or content_style.padding
button_styles.content_scrollbar_width = content_style.vertical_scrollbar_style.width
local editor_icon = assert(data.raw.sprite["first-factorio-mod-editor-icon"])
local editor_shortcut = assert(data.raw.shortcut["first-factorio-mod-request-editor"])
button_styles.editor_icon = {
  filename = editor_icon.filename,
  width = editor_icon.width,
  height = editor_icon.height,
  shortcut_filename = editor_shortcut.icon,
  shortcut_size = editor_shortcut.icon_size,
  small_shortcut_filename = editor_shortcut.small_icon,
  small_shortcut_size = editor_shortcut.small_icon_size,
  header_button_size = styles.frame_action_button.size,
  header_preserves_colors = styles.first_factorio_mod_editor_icon_button.invert_colors_of_picture_when_hovered_or_toggled == false
}

local function capture(name)
  if button_styles[name] then
    return
  end
  local style = assert(styles[name])
  button_styles[name] = {
    parent = style.parent,
    font = style.font,
    height = style.height,
    minimal_width = style.minimal_width,
    minimal_height = style.minimal_height,
    maximal_height = style.maximal_height
  }
  if style.parent then
    capture(style.parent)
  end
end

capture("dialog_button")
capture("confirm_button")
capture("red_button")
capture("tool_button")
capture("dropdown")
data:extend {
  { type = "mod-data", name = "first-factorio-mod-test-button-styles", data = button_styles }
}

local prefix = "first-factorio-mod-test-"
data:extend {
  {
    type = "item-group", name = prefix .. "group-a", order = "a",
    icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64
  },
  {
    type = "item-group", name = prefix .. "group-b", order = "b",
    icon = "__base__/graphics/icons/copper-plate.png", icon_size = 64
  },
  { type = "item-subgroup", name = prefix .. "subgroup-a", group = prefix .. "group-a", order = "a" },
  { type = "item-subgroup", name = prefix .. "subgroup-b", group = prefix .. "group-a", order = "b" },
  { type = "item-subgroup", name = prefix .. "subgroup-c", group = prefix .. "group-b", order = "a" }
}
for _, fixture in ipairs({
  { name = "beta", subgroup = "a", order = "a", stack_size = 10, label = "Beta" },
  { name = "zulu", subgroup = "a", order = "z", stack_size = 20, label = "Zulu" },
  { name = "alpha", subgroup = "b", order = "a", stack_size = 50, label = "Alpha" },
  { name = "middle", subgroup = "c", order = "a", stack_size = 100, label = "Middle" }
}) do
  data:extend {
    {
      type = "item", name = prefix .. fixture.name, localised_name = fixture.label,
      subgroup = prefix .. "subgroup-" .. fixture.subgroup, order = fixture.order,
      stack_size = fixture.stack_size, icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64
    }
  }
end
