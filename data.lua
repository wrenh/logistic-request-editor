-- Saved GUIs may reference this frame style before configuration reset.
data.raw["gui-style"].default.first_factorio_mod_edit_content = {
  type = "frame_style",
  parent = "inside_shallow_frame_with_padding",
  vertical_flow_style = {
    type = "vertical_flow_style",
    vertical_spacing = 5
  }
}

data.raw["gui-style"].default.first_factorio_mod_edit_content_scroll = {
  type = "scroll_pane_style",
  parent = "scroll_pane",
  padding = 12,
  right_padding = 0,
  extra_padding_when_activated = 0,
  always_draw_borders = true,
  graphical_set = table.deepcopy(data.raw["gui-style"].default.inside_shallow_frame.graphical_set),
  vertical_scrollbar_style = { type = "vertical_scrollbar_style", parent = "vertical_scrollbar", width = 12 },
  vertical_flow_style = { type = "vertical_flow_style", vertical_spacing = 5 }
}

data.raw["gui-style"].default.first_factorio_mod_editor_icon_button = {
  type = "button_style",
  parent = "frame_action_button",
  invert_colors_of_picture_when_hovered_or_toggled = false
}

local editor_icon = "__first-factorio-mod__/graphics/editor-icon.png"
local editor_icon_small = "__first-factorio-mod__/graphics/editor-icon-small.png"
data:extend {
  -- Saved GUIs may reference these sprites before configuration reset.
  {
    type = "sprite",
    name = "first-factorio-mod-sort-ascending",
    filename = "__core__/graphics/arrows/table-header-sort-arrow-up-white.png",
    width = 16,
    height = 16
  },
  {
    type = "sprite",
    name = "first-factorio-mod-sort-descending",
    filename = "__core__/graphics/arrows/table-header-sort-arrow-down-white.png",
    width = 16,
    height = 16
  },
  {
    type = "sprite",
    name = "first-factorio-mod-editor-icon",
    filename = editor_icon_small,
    width = 24,
    height = 24,
    flags = { "gui-icon" }
  },
  {
    type = "custom-input",
    name = "first-factorio-mod-reset-editor-position",
    key_sequence = "",
    consuming = "none",
    localised_name = { "bulk-imports.reset-position-name" },
    localised_description = { "bulk-imports.reset-position-tooltip" }
  },
  {
    type = "shortcut",
    name = "first-factorio-mod-request-editor",
    action = "lua",
    toggleable = true,
    localised_name = { "bulk-imports.launcher-name" },
    localised_description = { "bulk-imports.launcher-tooltip" },
    order = "z[bulk-request-editor]",
    icon = editor_icon,
    icon_size = 32,
    small_icon = editor_icon_small,
    small_icon_size = 24
  }
}