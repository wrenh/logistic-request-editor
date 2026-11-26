local util = require("__core__.lualib.util")

local PANEL_NAME = "first_factorio_mod_bulk_imports"
local SHORTCUT_NAME = "first-factorio-mod-request-editor"
local EDITOR_ICON = "first-factorio-mod-editor-icon"
local RESET_INPUT_NAME = "first-factorio-mod-reset-editor-position"
local SETTING_PREFIX = "first-factorio-mod-"
local SETTINGS = {
  visible = SETTING_PREFIX .. "show-editor",
  placement = SETTING_PREFIX .. "placement",
  locked = SETTING_PREFIX .. "floating-locked",
  remember_position = SETTING_PREFIX .. "remember-position",
  selection = SETTING_PREFIX .. "default-selection",
  units = SETTING_PREFIX .. "default-units",
  requested = SETTING_PREFIX .. "default-requested",
  requested_mode = SETTING_PREFIX .. "default-requested-mode",
  chest_requested = SETTING_PREFIX .. "default-chest-requested",
  chest_requested_mode = SETTING_PREFIX .. "default-chest-requested-mode",
  maximum = SETTING_PREFIX .. "default-maximum",
  payload_units = SETTING_PREFIX .. "default-payload-units",
  payload = SETTING_PREFIX .. "default-payload",
  sort_enabled = SETTING_PREFIX .. "sort",
  clear_empty_slots = SETTING_PREFIX .. "default-clear-empty-slots",
  filters_enabled = SETTING_PREFIX .. "edit-filters",
  platform_amounts_enabled = SETTING_PREFIX .. "edit-platform-amounts",
  other_amounts_enabled = SETTING_PREFIX .. "edit-other-amounts",
  quality_enabled = SETTING_PREFIX .. "edit-quality",
  payload_enabled = SETTING_PREFIX .. "edit-payload",
  quality_policy = SETTING_PREFIX .. "quality-range-behavior",
  confirmation_seconds = SETTING_PREFIX .. "confirmation-seconds"
}
local SETTING_KEYS = {}
for key, name in pairs(SETTINGS) do
  SETTING_KEYS[name] = key
end
local PLACEMENTS = { "left", "right", "top", "bottom", "floating" }
local DOCK_POSITIONS = {
  left = defines.relative_gui_position.left,
  right = defines.relative_gui_position.right,
  top = defines.relative_gui_position.top,
  bottom = defines.relative_gui_position.bottom
}
local migrating_settings = false
local SOURCES = { "planet", "platforms", "all" }
local SECTION_MODES = { "single", "multiple" }
-- Native comparison glyphs for =, >, <, >=, <= and !=.
local QUALITY_COMPARATORS = { "=", ">", "<", "\226\137\165", "\226\137\164", "\226\137\160" }
local ANY_QUALITY_INDEX = #QUALITY_COMPARATORS + 1
local ITEM_PRESETS = { 0, 1, 2, 3, 4, 5, 10, 25, 50, 100, 1000 }
local STACK_PRESETS = { 0, 1, 2, 3, 4, 5, 10, 25, 50, 75, 100, 250, 500, 750, 1000 }
local PAYLOAD_PRESETS = {}
for _, value in ipairs(ITEM_PRESETS) do
  if value > 0 then
    PAYLOAD_PRESETS[#PAYLOAD_PRESETS + 1] = value
  end
end
local QUANTITY_UNITS = { "items", "stacks" }
local SORT_PROPERTIES = { "default", "name", "requested", "quality", "maximum", "planet", "source", "payload" }
local SORT_DIRECTION_SPRITES = { ascending = "virtual-signal/up-arrow", descending = "virtual-signal/down-arrow" }
local FLOATING_LOCK_SPRITES = { locked = "virtual-signal/signal-lock", unlocked = "virtual-signal/signal-unlock" }
local NUMERIC_SORT_PROPERTIES = { requested = true, maximum = true, payload = true }
local INVENTORIES = {
  ["character"] = defines.inventory.character_main,
  ["logistic-container"] = defines.inventory.chest,
  ["space-platform-hub"] = defines.inventory.hub_main,
  ["cargo-landing-pad"] = defines.inventory.cargo_landing_pad_main,
  ["car"] = defines.inventory.car_trunk,
  ["spider-vehicle"] = defines.inventory.spider_trunk
}
local EDIT_CATEGORIES = {
  { name = "sort", setting = "sort_enabled" },
  { name = "edit_filters", setting = "filters_enabled", platform_only = true },
  { name = "edit_amounts", setting = "other_amounts_enabled", platform_setting = "platform_amounts_enabled" },
  { name = "edit_quality", setting = "quality_enabled" },
  { name = "edit_payload", setting = "payload_enabled", platform_only = true }
}
local CATEGORIES_BY_NAME, CATEGORY_SETTING_KEYS = {}, {}
for _, category in ipairs(EDIT_CATEGORIES) do
  CATEGORIES_BY_NAME[category.name] = category
  CATEGORY_SETTING_KEYS[category.setting] = true
  if category.platform_setting then
    CATEGORY_SETTING_KEYS[category.platform_setting] = true
  end
end
local prepare_request_updates
local refresh_capacity_preview
local PANEL_WIDTH = 296
local CONTENT_WIDTH = 248
local SORT_PROPERTY_WIDTH = CONTENT_WIDTH - 32
local MAX_ITEM_COUNT = 2147483647
local MAX_PAYLOAD_COUNT = 4294967295
local SYNCHRONIZE_INTERVAL = 60
local REQUESTER_GUIS = {
  ["space-platform-hub"] = defines.relative_gui_type.space_platform_hub_gui,
  ["logistic-container"] = defines.relative_gui_type.container_gui,
  ["spider-vehicle"] = defines.relative_gui_type.spider_vehicle_gui,
  ["car"] = defines.relative_gui_type.car_gui,
  ["cargo-landing-pad"] = defines.relative_gui_type.cargo_landing_pad_gui
}

local function get_panel(player)
  return player.gui.relative[PANEL_NAME] or player.gui.screen[PANEL_NAME]
end

local function get_gui_event_context(event)
  local element = event.element
  if not element or not element.valid or element.get_mod() ~= script.mod_name then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local panel = get_panel(player)
  if panel then
    return player, panel
  end
end

local function get_setting(player, key)
  return settings.get_player_settings(player)[SETTINGS[key]].value
end

local function category_setting(state, name)
  local category = assert(CATEGORIES_BY_NAME[name], "Unknown edit category: " .. tostring(name))
  return state.is_platform and category.platform_setting or category.setting
end

local function category_visible(player, name)
  local state = storage.bulk_import_panels[player.index]
  local category = assert(CATEGORIES_BY_NAME[name], "Unknown edit category: " .. tostring(name))
  return (state.is_platform or not category.platform_only)
    and get_setting(player, category_setting(state, name)) ~= "hidden"
end

local function edit_flags(player)
  local content = get_panel(player).content
  local flags = {}
  for _, category in ipairs(EDIT_CATEGORIES) do
    flags[category.name] = category_visible(player, category.name) and content[category.name].state
  end
  return flags
end

local function get_inventory_capacity(owner)
  if not owner.valid then
    return nil
  end
  local index = INVENTORIES[owner.type]
  local inventory = index and owner.get_inventory(index)
  if not inventory or not inventory.valid then
    return nil
  end
  local capacity = #inventory
  if inventory.supports_bar() then
    capacity = math.min(capacity, inventory.get_bar() - 1)
  end
  return capacity, inventory
end

local function selected_sections(player)
  local panel = get_panel(player)
  local state = storage.bulk_import_panels[player.index]
  local selected = {}
  if state.selection_mode == "single" then
    local entry = state.sections[panel.content.section.selected_index]
    if entry then
      selected[1] = entry
    end
  elseif state.selection_mode == "multiple" then
    for _, entry in ipairs(state.sections) do
      if entry.checked then
        selected[#selected + 1] = entry
      end
    end
  else
    return nil, "select-mode"
  end
  if #selected == 0 then
    return nil, state.selection_mode == "single" and "select-section" or "select-sections"
  end
  return selected
end

local function get_preferences(player)
  local preferences = storage.bulk_import_preferences[player.index]
  if not preferences then
    local resolution = player.display_resolution
    preferences = {
      settings_migrated = true,
      display_width = resolution.width,
      display_height = resolution.height,
      display_scale = player.display_scale
    }
    storage.bulk_import_preferences[player.index] = preferences
  end
  if not preferences.settings_migrated then
    preferences.settings_migrated = true
    migrating_settings = true
    local old_placement
    if type(preferences.docked) == "boolean" then
      old_placement = preferences.docked and "right" or "floating"
    end
    local legacy = {
      { key = "visible", value = preferences.visible },
      { key = "placement", value = old_placement },
      { key = "locked", value = preferences.locked }
    }
    local values = settings.get_player_settings(player)
    for _, old in ipairs(legacy) do
      local name = SETTINGS[old.key]
      if old.value ~= nil and values[name].value == prototypes.mod_setting[name].default_value
        and values[name].value ~= old.value then
        values[name] = { value = old.value }
      end
    end
    migrating_settings = false
    preferences.visible = nil
    preferences.docked = nil
    preferences.locked = nil
  end
  if not preferences.categories_migrated then
    local legacy = {
      filters_enabled = "default-edit-filters",
      platform_amounts_enabled = "default-platform-amounts",
      other_amounts_enabled = "default-other-amounts",
      quality_enabled = "default-edit-quality",
      payload_enabled = "default-edit-payload"
    }
    local values = settings.get_player_settings(player)
    migrating_settings = true
    for key, old_name in pairs(legacy) do
      local name = SETTINGS[key]
      if values[name].value == prototypes.mod_setting[name].default_value then
        local mode = values[SETTING_PREFIX .. old_name].value and "enabled" or "disabled"
        if values[name].value ~= mode then
          values[name] = { value = mode }
        end
      end
    end
    migrating_settings = false
    preferences.categories_migrated = true
  end
  if not get_setting(player, "remember_position") then
    preferences.position = nil
  end
  return preferences
end

local function destroy_panel_gui(player)
  for _, root in ipairs({ player.gui.relative, player.gui.screen }) do
    local panel = root[PANEL_NAME]
    if panel then
      panel.destroy()
    end
  end
end

local function set_status(panel, message, expire)
  panel.content.status.caption = message
  panel.content.status.visible = message ~= ""
  local state = storage.bulk_import_panels[panel.player_index]
  if state then
    state.status_expires_at = expire and game.tick + get_setting(panel.gui.player, "confirmation_seconds") * 60 or nil
  end
end

local function destroy_panel(player)
  destroy_panel_gui(player)
  storage.bulk_import_panels[player.index] = nil
  player.set_shortcut_toggled(SHORTCUT_NAME, get_setting(player, "visible"))
end

local function notify_error(player, key, ...)
  local message = { "bulk-imports." .. key, ... }
  local panel = get_panel(player)
  if panel then
    set_status(panel, message)
  end
  player.print(message)
end

local function get_open_requester(player)
  local gui_type = player.opened_gui_type
  local owner, anchor
  if gui_type == defines.gui_type.controller then
    owner = player.character
    anchor = defines.relative_gui_type.controller_gui
    if not player.force.character_logistic_requests then
      return nil
    end
  elseif gui_type == defines.gui_type.entity then
    owner = player.opened
    if owner and owner.valid then
      anchor = REQUESTER_GUIS[owner.type]
    end
  end
  if not owner or not owner.valid or not anchor or owner.force ~= player.force then
    return nil
  end

  local point = owner.get_requester_point()
  if not point or not point.valid
    or (point.mode ~= defines.logistic_mode.requester and point.mode ~= defines.logistic_mode.buffer) then
    return nil
  end
  return {
    owner = owner,
    point = point,
    anchor = anchor,
    gui_type = gui_type,
    is_platform = owner.type == "space-platform-hub"
  }
end

local function get_context(player)
  local state = storage.bulk_import_panels[player.index]
  local target = get_open_requester(player)
  if not state or not target or state.owner ~= target.owner or state.point ~= target.point
    or state.gui_type ~= target.gui_type then
    return nil
  end
  return state, target.point, target
end

local function can_edit_requests(player)
  local permissions = player.permission_group or game.permissions.get_group(0)
  return not permissions or permissions.allows_action(defines.input_action.set_logistic_filter_item)
end

local function section_caption(entry)
  return entry.group == ""
    and { "bulk-imports.unnamed-section", entry.index }
    or { "bulk-imports.named-section", entry.index, entry.group }
end

local function parse_multiplier(text, limit, allow_infinity)
  text = text:match("^%s*(.-)%s*$"):lower()
  if allow_infinity and (text == "inf" or text == "inf.") then
    return nil, true
  end
  if not text:match("^%d+$") then
    return nil, false
  end
  local value = tonumber(text)
  return value, value ~= nil and value <= limit
end

local function read_amount_unit(panel)
  local unit = QUANTITY_UNITS[panel.content.amount_controls.requested_header.units.selected_index]
  if not unit then
    return nil, "select-amount-units"
  end
  return unit
end

local function read_amounts(panel)
  local controls = panel.content.amount_controls
  local unit, unit_error = read_amount_unit(panel)
  if unit_error then
    return nil, nil, unit_error
  end
  local requested, requested_valid = parse_multiplier(controls.requested.multiplier.text, MAX_ITEM_COUNT, false)
  if not requested_valid then
    return nil, nil, "invalid-requested"
  end
  local maximum, maximum_valid = parse_multiplier(controls.trash_above.multiplier.text, MAX_ITEM_COUNT, true)
  if not maximum_valid then
    return nil, nil, "invalid-maximum"
  end
  if maximum and maximum < requested then
    return nil, nil, "invalid-amount-range"
  end
  return requested, maximum, nil, unit
end

local function read_payload(panel)
  local controls = panel.content.payload_controls
  local unit = QUANTITY_UNITS[controls.payload_header.units.selected_index]
  if not unit then
    return nil, nil, "select-payload-units"
  end
  local value, valid = parse_multiplier(controls.quantity_row.multiplier.text, MAX_PAYLOAD_COUNT, false)
  if not valid or value < 1 then
    return nil, nil, "invalid-payload"
  end
  return value, unit
end

local function update_unit_labels(player)
  local panel = get_panel(player)
  local controls = panel.content.amount_controls
  local amount_unit = QUANTITY_UNITS[controls.requested_header.units.selected_index]
  for _, name in ipairs({ "requested", "trash_above" }) do
    controls[name].unit_label.caption = amount_unit == "stacks" and "x" or ""
  end
  local payload = panel.content.payload_controls
  local unit = QUANTITY_UNITS[payload.payload_header.units.selected_index]
  payload.quantity_row.unit_label.caption = unit == "stacks" and "x" or ""
end

local function update_quality_availability(player)
  local controls = get_panel(player).content.quality_controls
  local any_quality = controls.comparator.selected_index == ANY_QUALITY_INDEX
  local changed = false
  controls.comparator.tooltip = {
    "bulk-imports.quality-comparator-tooltip",
    { get_setting(player, "quality_policy") == "prevent"
      and "bulk-imports.quality-policy-prevent" or "bulk-imports.quality-policy-zero" }
  }
  for _, button in ipairs(controls.qualities.children) do
    local quality = prototypes.quality[button.tags.quality_name]
    local unlocked = quality and not quality.hidden and player.force.is_quality_unlocked(quality.name)
    local enabled = not any_quality and unlocked == true
    changed = changed or button.enabled ~= enabled
    button.enabled = enabled
    button.tooltip = unlocked and quality.localised_name
      or { "bulk-imports.quality-locked", quality and quality.localised_name or button.tags.quality_name }
  end
  return changed
end

local function read_quality(player, panel)
  local controls = panel.content.quality_controls
  if controls.comparator.selected_index == ANY_QUALITY_INDEX then
    -- Factorio represents any quality with no quality or comparator restriction.
    return nil, nil
  end
  local comparator = QUALITY_COMPARATORS[controls.comparator.selected_index]
  if not comparator then
    return nil, nil, "select-quality-comparator"
  end
  local selected
  for _, button in ipairs(controls.qualities.children) do
    if button.toggled then
      if selected then
        return nil, nil, "select-quality"
      end
      selected = button.tags.quality_name
    end
  end
  if not selected then
    return nil, nil, "select-quality"
  end
  local quality = prototypes.quality[selected]
  if not quality or quality.hidden or not player.force.is_quality_unlocked(selected) then
    return nil, nil, "quality-unavailable"
  end
  return selected, comparator
end

local function sort_property_choice(element)
  local properties = element.tags.sort_properties
  return properties and properties[element.selected_index]
end

local function sort_direction_choice(element)
  local direction = element.tags.sort_direction
  if direction == "ascending" or direction == "descending" then
    return direction
  end
end

local function update_sort_direction(element)
  local direction = sort_direction_choice(element)
  if direction then
    element.sprite = SORT_DIRECTION_SPRITES[direction]
    element.tooltip = { "bulk-imports.sort-direction-tooltip", { "bulk-imports." .. direction } }
  else
    element.sprite = ""
    element.tooltip = { "bulk-imports.select-sort" }
  end
end

local function supported_sort_property(state, property)
  for index = 1, state.is_platform and #SORT_PROPERTIES or 5 do
    if SORT_PROPERTIES[index] == property then
      return true
    end
  end
  return false
end

local function secondary_sort_conflict(primary, secondary, direction, secondary_direction)
  if secondary and secondary == primary then
    return "sort-priorities-duplicate"
  end
  if secondary == "default" and direction and secondary_direction and direction == secondary_direction then
    return "sort-default-redundant"
  end
end

local function update_sort_dropdown(controls, name, properties, selected)
  local row = name == "property" and controls.primary_row or controls.secondary_row
  local selector = row[name]
  local items, selected_index = {}, 0
  for index, property in ipairs(properties) do
    items[index] = { "bulk-imports.sort-" .. property }
    if property == selected then
      selected_index = index
    end
  end
  local previous = selector.tags.sort_properties
  if previous and util.table.compare(previous, properties) then
    selector.selected_index = selected_index
    return
  end
  local position = selector.get_index_in_parent()
  -- Invalidate queued events that still refer to the previous item indices.
  selector.destroy()
  selector = row.add {
    type = "drop-down", name = name, index = position, items = items,
    selected_index = selected_index, tags = { sort_properties = properties },
    tooltip = { name == "property" and "bulk-imports.sort-tooltip" or "bulk-imports.secondary-sort-tooltip" }
  }
  selector.style.width = SORT_PROPERTY_WIDTH
end

local function update_sort_choices(player, saved)
  local state = storage.bulk_import_panels[player.index]
  local controls = get_panel(player).content.sort_controls
  local primary, secondary
  if saved then
    primary, secondary = saved.primary, saved.secondary
  else
    primary = sort_property_choice(controls.primary_row.property)
    secondary = sort_property_choice(controls.secondary_row.secondary_property)
  end
  local direction = sort_direction_choice(controls.primary_row.sort_order)
  local secondary_direction = sort_direction_choice(controls.secondary_row.secondary_sort_order)
  update_sort_direction(controls.primary_row.sort_order)
  update_sort_direction(controls.secondary_row.secondary_sort_order)
  local cleared = false
  if primary == "default" then
    secondary = "none"
  elseif secondary_sort_conflict(primary, secondary, direction, secondary_direction) then
    secondary = "none"
    cleared = true
  end
  local primary_properties, secondary_properties = {}, { "none" }
  for index = 1, state.is_platform and #SORT_PROPERTIES or 5 do
    local property = SORT_PROPERTIES[index]
    if property ~= secondary then
      primary_properties[#primary_properties + 1] = property
    end
    if primary ~= "default" and not secondary_sort_conflict(primary, property, direction, secondary_direction) then
      secondary_properties[#secondary_properties + 1] = property
    end
  end
  update_sort_dropdown(controls, "property", primary_properties, primary)
  update_sort_dropdown(controls, "secondary_property", secondary_properties, secondary)
  local visible = primary ~= "default"
  controls.primary_label.visible = visible
  controls.secondary_label.visible = visible
  controls.secondary_row.visible = visible
  controls.secondary_row.secondary_property.visible = visible
  controls.secondary_row.secondary_property.enabled = visible
  controls.secondary_row.secondary_sort_order.visible = visible
  controls.secondary_row.secondary_sort_order.enabled = visible
  return cleared
end

local function sort_uses_name(controls)
  local primary = sort_property_choice(controls.primary_row.property)
  return primary == "name"
    or (primary ~= "default" and sort_property_choice(controls.secondary_row.secondary_property) == "name")
end

local function read_sort(player)
  local state = storage.bulk_import_panels[player.index]
  local controls = get_panel(player).content.sort_controls
  local property = sort_property_choice(controls.primary_row.property)
  local secondary = property == "default" and "none" or sort_property_choice(controls.secondary_row.secondary_property)
  local direction = sort_direction_choice(controls.primary_row.sort_order)
  local secondary_direction = sort_direction_choice(controls.secondary_row.secondary_sort_order)
  local unit = QUANTITY_UNITS[controls.units.selected_index]
  if not supported_sort_property(state, property) or not direction or not unit or not secondary then
    return nil, "select-sort"
  end
  if secondary ~= "none" then
    if not supported_sort_property(state, secondary) or not secondary_direction then
      return nil, "select-sort"
    end
    local conflict = secondary_sort_conflict(property, secondary, direction, secondary_direction)
    if conflict then
      return nil, conflict
    end
  end
  if sort_uses_name(controls) then
    local selected = selected_sections(player)
    local names = state.sort_names
    if not names or names.locale ~= player.locale then
      names = { locale = player.locale, values = {}, pending = {}, requested = {}, failed = {} }
      state.sort_names = names
    end
    local pending = false
    for _, entry in ipairs(selected or {}) do
      if not entry.section.valid or not entry.section.is_manual or entry.section.owner ~= state.owner
        or entry.section.group ~= entry.group then
        return nil, "selection-updated"
      end
      for _, filter in pairs(entry.section.filters) do
        if filter.value then
          local item = prototypes.item[filter.value.name]
          if not item then
            return nil, "amount-non-item"
          end
          if names.failed[item.name] then
            return nil, "sort-name-failed"
          end
          if not names.values[item.name] then
            pending = true
            if not names.requested[item.name] then
              local id = player.request_translation(item.localised_name)
              names.pending[id] = item.name
              names.requested[item.name] = true
            end
          end
        end
      end
    end
    if pending then
      return nil, "sort-names-pending"
    end
  end
  local sort = {
    property = property, descending = direction == "descending", unit = unit,
    clear_empty_slots = controls.clear_empty_slots.state
  }
  if secondary ~= "none" then
    sort.secondary = { property = secondary, descending = secondary_direction == "descending" }
  end
  return sort
end

local function update_apply_state(player, clear_status, preserve_status)
  local panel = get_panel(player)
  local state = storage.bulk_import_panels[player.index]
  local has_selection = false
  if state.selection_mode == "single" then
    has_selection = state.sections[panel.content.section.selected_index] ~= nil
  else
    for _, entry in ipairs(state.sections) do
      has_selection = has_selection or entry.checked
    end
  end

  if clear_status then
    set_status(panel, "")
  end
  local flags = edit_flags(player)
  local error_key
  local error_message
  if flags.edit_amounts then
    if state.share_active then
      local error = refresh_capacity_preview(player)
      error_key = error and error[1]
      if error then
        error_message = { "bulk-imports." .. error[1], table.unpack(error, 2) }
      end
    else
      local _, _, amount_error = read_amounts(panel)
      error_key = amount_error
    end
  end
  if flags.edit_quality and not error_key then
    local _, _, quality_error = read_quality(player, panel)
    error_key = quality_error
  end
  if flags.edit_payload and not error_key then
    local _, _, payload_error = read_payload(panel)
    error_key = payload_error
  end
  if flags.sort and not error_key then
    local _, sort_error = read_sort(player)
    error_key = sort_error
  end
  if error_key and not preserve_status then
    set_status(panel, error_message or { "bulk-imports." .. error_key })
  end
  panel.actions.apply.enabled = has_selection and not error_key
    and (flags.sort or flags.edit_filters or flags.edit_amounts or flags.edit_quality or flags.edit_payload)
end

local function update_edit_controls(player)
  local panel = get_panel(player)
  local state = storage.bulk_import_panels[player.index]
  for _, category in ipairs(EDIT_CATEGORIES) do
    local name = category.name
    local visible = category_visible(player, name)
    panel.content[name].visible = visible
    panel.content[name].enabled = visible
    if not visible then
      panel.content[name].state = false
    end
  end
  local flags = edit_flags(player)
  local edit_filters = flags.edit_filters
  local secondary_cleared = update_sort_choices(player)
  panel.content.sort_controls.visible = flags.sort
  local property = sort_property_choice(panel.content.sort_controls.primary_row.property)
  local secondary = sort_property_choice(panel.content.sort_controls.secondary_row.secondary_property)
  panel.content.sort_controls.units.visible = NUMERIC_SORT_PROPERTIES[property] == true
    or NUMERIC_SORT_PROPERTIES[secondary] == true
  panel.content.sort_divider.visible = category_visible(player, "sort")
    and (category_visible(player, "edit_filters") or category_visible(player, "edit_amounts")
      or category_visible(player, "edit_quality") or category_visible(player, "edit_payload"))
  panel.content.filters_divider.visible = category_visible(player, "edit_filters")
  for _, name in ipairs({ "planet_label", "planet_row", "source_label", "sources" }) do
    panel.content[name].visible = edit_filters
  end
  panel.content.amount_controls.visible = flags.edit_amounts
  panel.content.quality_controls.visible = flags.edit_quality
  panel.content.quality_divider.visible = category_visible(player, "edit_amounts")
  panel.content.payload_divider.visible = category_visible(player, "edit_payload")
  panel.content.payload_controls.visible = flags.edit_payload
  local amounts = panel.content.amount_controls
  amounts.requested_header.units.enabled = true
  amounts.share_actions.cancel_share.visible = state.share_active == true
  amounts.share_preview.visible = state.share_active == true
  amounts.share_trash_note.visible = state.share_active == true
  amounts.trash_above.visible = not state.share_active
  amounts.trash_above_header.visible = not state.share_active
  for _, name in ipairs({ "requested", "trash_above" }) do
    amounts[name].multiplier.enabled = not state.share_active
    amounts[name].amount_slider.enabled = not state.share_active
  end
  update_unit_labels(player)
  update_quality_availability(player)
  update_apply_state(player, true)
  if secondary_cleared and not panel.content.status.visible then
    set_status(panel, { "bulk-imports.secondary-sort-cleared" })
  end
end

local function preset_position(value, is_maximum, presets)
  presets = presets or ITEM_PRESETS
  if value >= presets[#presets] then
    return #presets - 1
  end
  local closest = 1
  for index = 1, #presets - (is_maximum and 1 or 0) do
    local preset = presets[index]
    if math.abs(preset - value) < math.abs(presets[closest] - value) then
      closest = index
    end
  end
  return closest - 1
end

local function amount_presets(owner, unit)
  local presets = util.table.deepcopy(unit == "stacks" and STACK_PRESETS or ITEM_PRESETS)
  if unit == "stacks" then
    local capacity = get_inventory_capacity(owner)
    if capacity then
      local present = false
      for _, value in ipairs(presets) do
        present = present or value == capacity
      end
      if not present then
        presets[#presets + 1] = capacity
        table.sort(presets)
      end
    end
  end
  return presets
end

local function refresh_amount_presets(player)
  local panel = get_panel(player)
  local state = storage.bulk_import_panels[player.index]
  local controls = panel.content.amount_controls
  local unit = QUANTITY_UNITS[controls.requested_header.units.selected_index]
  local presets = amount_presets(state.owner, unit)
  if state.amount_presets and util.table.compare(state.amount_presets, presets) and state.amount_unit == unit then
    return false
  end
  state.amount_presets = presets
  state.amount_unit = unit
  for _, name in ipairs({ "requested", "trash_above" }) do
    local row = controls[name]
    row.amount_slider.set_slider_minimum_maximum(0, #presets - 1)
    local legend = {}
    for index, value in ipairs(presets) do
      legend[index] = name == "trash_above" and index == #presets and "inf." or tostring(value)
    end
    row.amount_slider.tooltip = {
      "bulk-imports.slider-tooltip", table.concat(legend, ", "),
      { unit == "stacks" and "bulk-imports.units-stacks" or "bulk-imports.units-items" }
    }
    local value, valid = parse_multiplier(row.multiplier.text, MAX_ITEM_COUNT, name == "trash_above")
    if valid then
      row.amount_slider.slider_value = value and preset_position(value, name == "trash_above", presets) or #presets - 1
    end
  end
  return true
end

local function update_amount_controls(player, row_name, from_slider)
  local state = storage.bulk_import_panels[player.index]
  if state.share_active then
    return
  end
  refresh_amount_presets(player)
  local controls = get_panel(player).content.amount_controls
  local presets = state.amount_presets
  local requested, requested_valid = parse_multiplier(controls.requested.multiplier.text, MAX_ITEM_COUNT, false)
  local maximum, maximum_valid = parse_multiplier(controls.trash_above.multiplier.text, MAX_ITEM_COUNT, true)

  if from_slider then
    local position = controls[row_name].amount_slider.slider_value
    if row_name == "requested" then
      requested, requested_valid = presets[position + 1], true
      if position == #presets - 1 then
        maximum, maximum_valid = nil, true
      end
    elseif position == #presets - 1 then
      maximum, maximum_valid = nil, true
    else
      maximum, maximum_valid = presets[position + 1], true
    end
  end
  if requested_valid and maximum_valid and maximum and maximum < requested then
    if row_name == "requested" then
      maximum = requested
    else
      requested = maximum
    end
  end

  if requested_valid then
    controls.requested.multiplier.text = tostring(requested)
    controls.requested.amount_slider.slider_value = preset_position(requested, false, presets)
  end
  if maximum_valid then
    controls.trash_above.multiplier.text = maximum and tostring(maximum) or "inf."
    controls.trash_above.amount_slider.slider_value = maximum and preset_position(maximum, true, presets) or #presets - 1
  end
  update_apply_state(player, true)
end

local function update_payload_controls(player, from_slider)
  local row = get_panel(player).content.payload_controls.quantity_row
  if from_slider then
    row.multiplier.text = tostring(PAYLOAD_PRESETS[row.amount_slider.slider_value + 1])
  else
    local value, valid = parse_multiplier(row.multiplier.text, MAX_PAYLOAD_COUNT, false)
    if valid and value >= 1 then
      row.amount_slider.slider_value = preset_position(value, false, PAYLOAD_PRESETS)
    end
  end
  update_apply_state(player, true)
end

local function update_selection_ui(player, clear_status, preserve_status)
  local panel = get_panel(player)
  local state = storage.bulk_import_panels[player.index]
  for _, mode in ipairs(SECTION_MODES) do
    panel.content.selection_modes[mode].state = state.selection_mode == mode
  end
  panel.content.section.visible = state.selection_mode == "single"
  panel.content.multiple_sections.visible = state.selection_mode == "multiple"

  for index, entry in ipairs(state.sections) do
    panel.content.multiple_sections.section_list["request_section_" .. index].state = entry.checked
  end
  panel.content.multiple_sections.selection_actions.check_all.enabled = #state.sections > 0
  panel.content.multiple_sections.selection_actions.check_none.enabled = #state.sections > 0
  update_apply_state(player, clear_status, preserve_status)
end

local function rebuild_section_list(player)
  local state = storage.bulk_import_panels[player.index]
  local list = get_panel(player).content.multiple_sections.section_list
  list.clear()
  for index, entry in ipairs(state.sections) do
    local caption = section_caption(entry)
    local checkbox = list.add {
      type = "checkbox",
      name = "request_section_" .. index,
      caption = caption,
      tooltip = caption,
      state = entry.checked,
      tags = { entry_index = index, section_index = entry.index }
    }
    checkbox.style.minimal_width = 0
    checkbox.style.maximal_width = CONTENT_WIDTH - 20
    checkbox.style.horizontally_stretchable = true
  end
end

local function set_selection_mode(player, mode)
  if mode ~= "single" and mode ~= "multiple" then
    notify_error(player, "select-mode")
    return
  end

  local panel = get_panel(player)
  local state = storage.bulk_import_panels[player.index]
  if mode == "multiple" and not state.multiple_initialized then
    for index, entry in ipairs(state.sections) do
      entry.checked = index == panel.content.section.selected_index
    end
    state.multiple_initialized = true
  end
  state.selection_mode = mode
  update_selection_ui(player, true)
end

local function set_all_sections(player, checked)
  local state = storage.bulk_import_panels[player.index]
  for _, entry in ipairs(state.sections) do
    entry.checked = checked
  end
  update_selection_ui(player, true)
end

local function refresh_sections(player, initial)
  local state, point = get_context(player)
  if not state then
    notify_error(player, "target-unavailable")
    destroy_panel(player)
    return
  end

  local panel = get_panel(player)
  local selector = panel.content.section
  local previous = state.sections[selector.selected_index]
  local sections, captions = {}, {}
  local selected_index = initial and 1 or 0
  local selected_count = 0
  local preserved_count = 0
  for _, entry in ipairs(state.sections) do
    if (state.selection_mode == "single" and entry == previous)
      or (state.selection_mode == "multiple" and entry.checked) then
      selected_count = selected_count + 1
    end
  end

  for _, section in ipairs(point.sections) do
    if section.is_manual then
      local checked = false
      for _, old_entry in ipairs(state.sections) do
        if old_entry.section == section and old_entry.group == section.group then
          checked = old_entry.checked
          if (state.selection_mode == "single" and old_entry == previous)
            or (state.selection_mode == "multiple" and old_entry.checked) then
            preserved_count = preserved_count + 1
          end
          break
        end
      end
      sections[#sections + 1] = {
        section = section,
        index = section.index,
        group = section.group,
        checked = checked
      }
      captions[#captions + 1] = section_caption(sections[#sections])
      if previous and previous.section == section and previous.group == section.group then
        selected_index = #sections
      end
    end
  end

  local selection_changed = preserved_count < selected_count
  if selection_changed then
    selected_index = 0
    for _, entry in ipairs(sections) do
      entry.checked = false
    end
  end
  state.sections = sections
  local selector_position = selector.get_index_in_parent()
  -- New element IDs prevent queued clicks from selecting a different reordered entry.
  selector.destroy()
  selector = panel.content.add {
    type = "drop-down",
    name = "section",
    index = selector_position,
    items = captions,
    selected_index = #sections > 0 and selected_index or 0,
    enabled = #sections > 0
  }
  selector.style.width = CONTENT_WIDTH
  if initial and state.selection_mode == "multiple" and not state.multiple_initialized then
    for index, entry in ipairs(sections) do
      entry.checked = index == selector.selected_index
    end
    state.multiple_initialized = true
  end
  if selection_changed then
    set_status(panel, { "bulk-imports.selection-updated" })
  elseif initial or #sections == 0 then
    set_status(panel, #sections > 0 and "" or { "bulk-imports.no-sections" })
  else
    local caption = panel.content.status.caption
    if type(caption) == "table" and caption[1] == "bulk-imports.no-sections" then
      set_status(panel, "")
    end
  end
  rebuild_section_list(player)
  update_selection_ui(player, false, not initial)
  return selection_changed
end

local function synchronize_sections(player)
  local state, point = get_context(player)
  if not state or not get_panel(player) then
    return false, false
  end
  local count = 0
  local changed = false
  for _, section in ipairs(point.sections) do
    if section.is_manual then
      count = count + 1
      local old = state.sections[count]
      if not old or old.section ~= section or old.index ~= section.index or old.group ~= section.group then
        changed = true
        break
      end
    end
  end
  if changed or count ~= #state.sections then
    return true, refresh_sections(player)
  end
  return false, false
end

local function synchronize_editor(player)
  local state = get_context(player)
  local panel = get_panel(player)
  if not state or not panel then
    return
  end
  synchronize_sections(player)
  local caption = panel.content.status.caption
  local quality_error = type(caption) == "table" and caption[1] == "bulk-imports.quality-unavailable"
  local quality_changed = update_quality_availability(player)
  if quality_changed then
    update_apply_state(player, quality_error, not quality_error and panel.content.status.visible)
  end
  local presets_changed = refresh_amount_presets(player)
  local flags = edit_flags(player)
  if presets_changed or (flags.sort and sort_uses_name(panel.content.sort_controls))
    or (flags.edit_amounts and state.share_active) then
    update_apply_state(player, false, panel.content.status.visible)
  end
end

local function capture_form(player)
  local panel = get_panel(player)
  local content = panel.content
  local form = {
    section_items = content.section.items,
    section_index = content.section.selected_index,
    section_enabled = content.section.enabled,
    edit_filters = content.edit_filters.state,
    sort = content.sort.state,
    sort_property = sort_property_choice(content.sort_controls.primary_row.property),
    sort_direction = sort_direction_choice(content.sort_controls.primary_row.sort_order),
    sort_secondary_property = sort_property_choice(content.sort_controls.secondary_row.secondary_property),
    sort_secondary_direction = sort_direction_choice(content.sort_controls.secondary_row.secondary_sort_order),
    sort_units = content.sort_controls.units.selected_index,
    sort_clear_empty_slots = content.sort_controls.clear_empty_slots.state,
    edit_amounts = content.edit_amounts.state,
    edit_quality = content.edit_quality.state,
    edit_payload = content.edit_payload.state,
    amount_units_index = content.amount_controls.requested_header.units.selected_index,
    import_from = content.planet_row.planet_selector.elem_value,
    comparator_index = content.quality_controls.comparator.selected_index,
    sources = {},
    qualities = {},
    amounts = {},
    payload = {
      text = content.payload_controls.quantity_row.multiplier.text,
      slider_value = content.payload_controls.quantity_row.amount_slider.slider_value,
      units_index = content.payload_controls.payload_header.units.selected_index
    },
    status_caption = content.status.caption,
    status_visible = content.status.visible,
    status_expires_at = storage.bulk_import_panels[player.index].status_expires_at
  }
  for _, source in ipairs(SOURCES) do
    form.sources[source] = content.sources[source].state
  end
  for _, button in ipairs(content.quality_controls.qualities.children) do
    form.qualities[button.tags.quality_name] = button.toggled
  end
  for _, name in ipairs({ "requested", "trash_above" }) do
    local row = content.amount_controls[name]
    form.amounts[name] = {
      text = row.multiplier.text,
      slider_value = row.amount_slider.slider_value,
      tooltip = row.amount_slider.tooltip
    }
  end
  return form
end

local function restore_form(player, form)
  local panel = get_panel(player)
  local content = panel.content
  content.section.items = form.section_items
  content.section.selected_index = form.section_index
  content.section.enabled = form.section_enabled
  content.edit_filters.state = form.edit_filters
  content.sort.state = form.sort
  content.sort_controls.primary_row.sort_order.tags = { sort_direction = form.sort_direction }
  content.sort_controls.secondary_row.secondary_sort_order.tags = { sort_direction = form.sort_secondary_direction }
  update_sort_choices(player, { primary = form.sort_property, secondary = form.sort_secondary_property })
  content.sort_controls.units.selected_index = form.sort_units
  content.sort_controls.clear_empty_slots.state = form.sort_clear_empty_slots
  content.edit_amounts.state = form.edit_amounts
  content.edit_quality.state = form.edit_quality
  content.edit_payload.state = form.edit_payload
  content.amount_controls.requested_header.units.selected_index = form.amount_units_index
  content.planet_row.planet_selector.elem_value = form.import_from
  content.quality_controls.comparator.selected_index = form.comparator_index
  for _, source in ipairs(SOURCES) do
    content.sources[source].state = form.sources[source]
  end
  for _, button in ipairs(content.quality_controls.qualities.children) do
    button.toggled = form.qualities[button.tags.quality_name] == true
  end
  for _, name in ipairs({ "requested", "trash_above" }) do
    local row = content.amount_controls[name]
    row.multiplier.text = form.amounts[name].text
    row.amount_slider.slider_value = form.amounts[name].slider_value
    row.amount_slider.tooltip = form.amounts[name].tooltip
  end
  content.payload_controls.quantity_row.multiplier.text = form.payload.text
  content.payload_controls.quantity_row.amount_slider.slider_value = form.payload.slider_value
  content.payload_controls.payload_header.units.selected_index = form.payload.units_index
  refresh_amount_presets(player)
  rebuild_section_list(player)
  update_edit_controls(player)
  update_selection_ui(player)
  local state = storage.bulk_import_panels[player.index]
  panel.actions.undo.visible = state.undo ~= nil
  set_status(panel, form.status_caption)
  panel.content.status.visible = form.status_visible
  if form.status_expires_at then
    if form.status_expires_at <= game.tick then
      set_status(panel, "")
    else
      state.status_expires_at = form.status_expires_at
    end
  end
end

local function update_window_controls(player)
  local panel = get_panel(player)
  local minimized = get_preferences(player).minimized == true
  local floating = player.gui.screen[PANEL_NAME] == panel
  local locked = get_setting(player, "locked")
  local titlebar = panel.titlebar
  panel.style = "frame"
  if minimized then
    panel.style.padding = 8
  else
    panel.style.width = PANEL_WIDTH
  end
  panel.style.horizontal_align = minimized and "center" or "left"
  titlebar.visible = not minimized
  panel.content.visible = not minimized
  panel.actions.visible = not minimized
  panel.minimized_icon.visible = minimized
  if minimized then
    panel.placement_menu.visible = false
  end
  titlebar.dock_toggle.sprite = floating and "utility/collapse" or "utility/expand"
  titlebar.dock_toggle.tooltip = { "bulk-imports.placement-menu" }
  titlebar.lock_toggle.visible = floating
  titlebar.lock_toggle.sprite = locked and FLOATING_LOCK_SPRITES.locked or FLOATING_LOCK_SPRITES.unlocked
  titlebar.lock_toggle.tooltip = { locked and "bulk-imports.unlock-tooltip" or "bulk-imports.lock-tooltip" }
  titlebar.recenter.visible = floating
  for _, choice in ipairs(PLACEMENTS) do
    panel.placement_menu["place_" .. choice].toggled = get_setting(player, "placement") == choice
  end
  local drag_target = floating and not locked and panel or nil
  titlebar.drag_target = drag_target
  titlebar.heading.drag_target = drag_target
  titlebar.drag_space.drag_target = drag_target
end

local function remember_floating_position(player)
  local panel = get_panel(player)
  local preferences = get_preferences(player)
  if panel and player.gui.screen[PANEL_NAME] == panel and get_setting(player, "remember_position")
    and not panel.auto_center and panel.location then
    preferences.position = panel.location
  end
end

local function center_floating_panel(player)
  local preferences = get_preferences(player)
  preferences.position = nil
  local panel = get_panel(player)
  if panel and player.gui.screen[PANEL_NAME] == panel then
    panel.auto_center = true
    panel.force_auto_center()
  end
end

local function clamp_floating_position(player, position)
  local resolution = player.display_resolution
  local scale = player.display_scale
  return {
    x = math.max(0, math.min(position.x, math.max(0, resolution.width - PANEL_WIDTH * scale))),
    y = math.max(0, math.min(position.y, math.max(0, resolution.height - 32 * scale)))
  }
end

local function update_panel_height(player)
  local panel = get_panel(player)
  if panel then
    local menu_height = panel.placement_menu.visible and 64 or 0
    panel.content.style.maximal_height = math.max(1,
      math.floor(player.display_resolution.height / player.display_scale)
        - 112 - menu_height - panel.actions.style.top_margin)
  end
end

local function set_panel_minimized(player, minimized)
  get_preferences(player).minimized = minimized
  local panel = get_panel(player)
  if not panel then
    return
  end
  update_window_controls(player)
  update_panel_height(player)
  if player.gui.screen[PANEL_NAME] == panel and panel.auto_center then
    panel.force_auto_center()
  end
end

local function add_quantity_header(parent, name, caption, unit_index)
  local header = parent.add { type = "flow", name = name, direction = "horizontal" }
  header.style.width = CONTENT_WIDTH
  header.style.vertical_align = "center"
  header.add { type = "label", caption = caption }
  local spacer = header.add { type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
  if unit_index then
    local units = header.add {
      type = "drop-down",
      name = "units",
      items = { { "bulk-imports.units-items" }, { "bulk-imports.units-stacks" } },
      selected_index = unit_index,
      tooltip = { name == "requested_header" and "bulk-imports.amount-units-tooltip" or "bulk-imports.units-tooltip" }
    }
    units.style.width = 88
  end
  return header
end

local function add_sort_direction_button(parent, name)
  local button = parent.add {
    type = "sprite-button", name = name, style = "tool_button",
    sprite = SORT_DIRECTION_SPRITES.ascending, tags = { sort_direction = "ascending" },
    tooltip = { "bulk-imports.sort-direction-tooltip", { "bulk-imports.ascending" } }
  }
  button.style.width = 28
  button.style.height = 28
end

local function open_panel(player, target, form)
  if form then
    destroy_panel_gui(player)
  else
    destroy_panel(player)
    storage.bulk_import_panels[player.index] = {
      owner = target.owner,
      point = target.point,
      gui_type = target.gui_type,
      is_platform = target.is_platform,
      sections = {},
      selection_mode = get_setting(player, "selection"),
      multiple_initialized = false
    }
  end

  local preferences = get_preferences(player)
  local placement = get_setting(player, "placement")
  local state = storage.bulk_import_panels[player.index]
  local chest = target.owner.type == "logistic-container"
  local max_default = get_setting(player, chest and "chest_requested_mode" or "requested_mode") == "max"
  local capacity = get_inventory_capacity(target.owner)
  local initial_requested = max_default and capacity or get_setting(player, chest and "chest_requested" or "requested")
  if max_default and capacity == nil then
    initial_requested = ""
  end
  local initial_unit = max_default and "stacks" or get_setting(player, "units")
  local initial_presets = amount_presets(target.owner, initial_unit)
  state.placement = placement
  state.remember_position = get_setting(player, "remember_position")
  local definition = {
    type = "frame",
    name = PANEL_NAME,
    direction = "vertical"
  }
  local root = player.gui.screen
  if placement ~= "floating" then
    root = player.gui.relative
    definition.anchor = {
      gui = target.anchor,
      position = DOCK_POSITIONS[placement]
    }
  end
  local panel = root.add(definition)
  panel.style.width = PANEL_WIDTH
  local minimized_icon = panel.add {
    type = "sprite-button",
    name = "minimized_icon",
    sprite = EDITOR_ICON,
    style = "tool_button",
    tooltip = { "bulk-imports.restore-tooltip" },
    visible = false
  }
  minimized_icon.style.width = 28
  minimized_icon.style.height = 28
  minimized_icon.style.margin = 0
  minimized_icon.style.horizontal_align = "center"
  minimized_icon.style.vertical_align = "center"

  local titlebar = panel.add {
    type = "flow",
    name = "titlebar",
    direction = "horizontal",
    style = "frame_header_flow"
  }
  titlebar.style.vertical_align = "center"
  titlebar.style.horizontal_spacing = 2
  titlebar.add { type = "label", name = "heading", caption = { "bulk-imports.title" }, style = "frame_title" }
  local filler = titlebar.add { type = "empty-widget", name = "drag_space", style = "draggable_space_header" }
  filler.style.horizontally_stretchable = true
  filler.style.minimal_width = 0
  filler.style.height = 24
  titlebar.add {
    type = "sprite-button",
    name = "dock_toggle",
    sprite = "utility/expand",
    style = "frame_action_button"
  }
  titlebar.add {
    type = "sprite-button",
    name = "lock_toggle",
    sprite = FLOATING_LOCK_SPRITES.unlocked,
    style = "frame_action_button"
  }
  titlebar.add {
    type = "sprite-button",
    name = "recenter",
    sprite = "utility/center",
    style = "frame_action_button",
    tooltip = { "bulk-imports.recenter" }
  }
  titlebar.add {
    type = "sprite-button",
    name = "minimize",
    sprite = EDITOR_ICON,
    style = "first_factorio_mod_editor_icon_button",
    tooltip = { "bulk-imports.minimize-tooltip" }
  }
  titlebar.add {
    type = "sprite-button",
    name = "close_panel",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "frame_action_button",
    tooltip = { "bulk-imports.close" }
  }

  local placement_menu = panel.add {
    type = "table", name = "placement_menu", column_count = 3, visible = false
  }
  placement_menu.style.horizontal_spacing = 4
  placement_menu.style.vertical_spacing = 4
  for _, choice in ipairs({ "left", "right", "top", "bottom", "floating", "center" }) do
    local button = placement_menu.add {
      type = "button",
      name = "place_" .. choice,
      caption = { "bulk-imports.placement-" .. choice },
      tags = { placement = choice }
    }
    button.style.width = 88
    button.style.height = 28
  end

  local content = panel.add {
    type = "scroll-pane",
    name = "content",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
    style = "first_factorio_mod_edit_content_scroll"
  }
  content.style.width = PANEL_WIDTH - 24
  local selection_label = content.add { type = "label", caption = { "bulk-imports.section" } }
  selection_label.style.font = "default-bold"
  local selection_modes = content.add { type = "flow", name = "selection_modes", direction = "horizontal" }
  for _, mode in ipairs(SECTION_MODES) do
    selection_modes.add {
      type = "radiobutton",
      name = mode,
      caption = { "bulk-imports.mode-" .. mode },
      state = mode == "single"
    }
  end
  local selector = content.add { type = "drop-down", name = "section" }
  selector.style.width = CONTENT_WIDTH
  local multiple_sections = content.add { type = "flow", name = "multiple_sections", direction = "vertical" }
  multiple_sections.style.vertical_spacing = 5
  local selection_actions = multiple_sections.add {
    type = "flow",
    name = "selection_actions",
    direction = "horizontal"
  }
  for _, choice in ipairs({ "all", "none" }) do
    local button = selection_actions.add {
      type = "button",
      name = "check_" .. choice,
      caption = { "bulk-imports.check-" .. choice }
    }
    button.style.width = 90
  end
  local section_list = multiple_sections.add {
    type = "scroll-pane",
    name = "section_list",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto"
  }
  section_list.style.width = CONTENT_WIDTH
  section_list.style.maximal_height = 168

  local selection_divider = content.add { type = "line", direction = "horizontal" }
  selection_divider.style.width = CONTENT_WIDTH
  local sort = content.add {
    type = "checkbox", name = "sort", caption = { "bulk-imports.sort" },
    state = get_setting(player, "sort_enabled") == "enabled"
  }
  sort.style.top_margin = 5
  sort.style.font = "default-bold"
  local sort_controls = content.add { type = "flow", name = "sort_controls", direction = "vertical" }
  sort_controls.style.vertical_spacing = 5
  sort_controls.add { type = "label", name = "primary_label", caption = { "bulk-imports.sort-primary" } }
  local sort_items, sort_properties = {}, {}
  for index = 1, target.is_platform and #SORT_PROPERTIES or 5 do
    sort_items[index] = { "bulk-imports.sort-" .. SORT_PROPERTIES[index] }
    sort_properties[index] = SORT_PROPERTIES[index]
  end
  local primary_row = sort_controls.add { type = "flow", name = "primary_row", direction = "horizontal" }
  primary_row.style.width = CONTENT_WIDTH
  primary_row.style.horizontal_spacing = 4
  primary_row.style.vertical_align = "center"
  local sort_property = primary_row.add {
    type = "drop-down", name = "property", items = sort_items, selected_index = 1,
    tooltip = { "bulk-imports.sort-tooltip" }, tags = { sort_properties = sort_properties }
  }
  sort_property.style.width = SORT_PROPERTY_WIDTH
  add_sort_direction_button(primary_row, "sort_order")
  local secondary_label = sort_controls.add {
    type = "label", name = "secondary_label", caption = { "bulk-imports.sort-secondary" }, visible = false
  }
  secondary_label.style.top_margin = 5
  local secondary_row = sort_controls.add {
    type = "flow", name = "secondary_row", direction = "horizontal", visible = false
  }
  secondary_row.style.width = CONTENT_WIDTH
  secondary_row.style.horizontal_spacing = 4
  secondary_row.style.vertical_align = "center"
  local secondary_property = secondary_row.add {
    type = "drop-down", name = "secondary_property", items = { { "bulk-imports.sort-none" } },
    selected_index = 1, tags = { sort_properties = { "none" } }, visible = false,
    tooltip = { "bulk-imports.secondary-sort-tooltip" }
  }
  secondary_property.style.width = SORT_PROPERTY_WIDTH
  add_sort_direction_button(secondary_row, "secondary_sort_order")
  local sort_units = sort_controls.add {
    type = "drop-down", name = "units",
    items = { { "bulk-imports.units-items" }, { "bulk-imports.units-stacks" } }, selected_index = 2,
    tooltip = { "bulk-imports.sort-units-tooltip" }, visible = false
  }
  sort_units.style.width = 90
  sort_controls.add {
    type = "checkbox", name = "clear_empty_slots", caption = { "bulk-imports.clear-empty-slots" },
    state = get_setting(player, "clear_empty_slots"), tooltip = { "bulk-imports.clear-empty-slots-tooltip" }
  }
  local sort_divider = content.add { type = "line", name = "sort_divider", direction = "horizontal" }
  sort_divider.style.width = CONTENT_WIDTH
  local edit_filters = content.add {
    type = "checkbox",
    name = "edit_filters",
    caption = { "bulk-imports.edit-filters" },
    state = target.is_platform and get_setting(player, "filters_enabled") == "enabled"
  }
  edit_filters.style.top_margin = 5
  edit_filters.style.font = "default-bold"
  content.add { type = "label", name = "planet_label", caption = { "bulk-imports.planet-label" } }
  local planet_row = content.add { type = "flow", name = "planet_row", direction = "horizontal" }
  planet_row.add {
    type = "choose-elem-button",
    name = "planet_selector",
    elem_type = "space-location",
    elem_filters = { { filter = "type", type = "planet" } },
    tooltip = { "bulk-imports.planet-tooltip" }
  }
  planet_row.add { type = "button", name = "clear_planet", caption = { "bulk-imports.no-planet" } }

  local source_label = content.add { type = "label", name = "source_label", caption = { "bulk-imports.source-label" } }
  source_label.style.top_margin = 5
  local sources = content.add { type = "flow", name = "sources", direction = "horizontal" }
  for _, source in ipairs(SOURCES) do
    sources.add {
      type = "radiobutton",
      name = source,
      caption = { "bulk-imports.source-" .. source },
      state = source == "planet"
    }
  end

  local filters_divider = content.add { type = "line", name = "filters_divider", direction = "horizontal" }
  filters_divider.style.width = CONTENT_WIDTH
  local edit_amounts = content.add {
    type = "checkbox",
    name = "edit_amounts",
    caption = { "bulk-imports.edit-amounts" },
    state = get_setting(player, target.is_platform and "platform_amounts_enabled" or "other_amounts_enabled") == "enabled"
  }
  edit_amounts.style.top_margin = 5
  edit_amounts.style.font = "default-bold"
  local amount_controls = content.add { type = "flow", name = "amount_controls", direction = "vertical" }
  amount_controls.style.vertical_spacing = 5
  amount_controls.style.width = CONTENT_WIDTH
  for _, name in ipairs({ "requested", "trash_above" }) do
    local is_maximum = name == "trash_above"
    local header = add_quantity_header(amount_controls, name .. "_header", { "bulk-imports." .. name },
      not is_maximum and (initial_unit == "items" and 1 or 2) or nil)
    header.style.top_margin = is_maximum and 5 or 0
    local row = amount_controls.add { type = "flow", name = name, direction = "horizontal" }
    row.style.horizontal_spacing = 5
    row.style.vertical_align = "center"
    local field = row.add {
      type = "textfield",
      name = "multiplier",
      text = is_maximum and get_setting(player, "maximum") or tostring(initial_requested),
      lose_focus_on_confirm = true,
      tooltip = { "bulk-imports." .. (is_maximum and "maximum-tooltip" or "requested-tooltip") }
    }
    field.style.width = 60
    field.style.horizontal_align = "center"
    local unit = row.add { type = "label", name = "unit_label", caption = "x" }
    unit.style.width = 10
    local slider = row.add {
      type = "slider",
      name = "amount_slider",
      style = "notched_slider",
      minimum_value = 0,
      maximum_value = #initial_presets - 1,
      value = 0,
      value_step = 1,
      discrete_values = true,
      tooltip = { "bulk-imports.slider-tooltip" }
    }
    slider.style.width = CONTENT_WIDTH - 80
    local initial, valid = parse_multiplier(field.text, MAX_ITEM_COUNT, is_maximum)
    if valid then
      slider.slider_value = initial and preset_position(initial, is_maximum, initial_presets) or #initial_presets - 1
    end
    if not is_maximum then
      local share_actions = amount_controls.add { type = "flow", name = "share_actions", direction = "horizontal" }
      share_actions.style.horizontal_spacing = 4
      local share = share_actions.add {
        type = "button", name = "share_capacity", caption = { "bulk-imports.share-capacity" },
        tooltip = { "bulk-imports.share-tooltip" }
      }
      share.style.width = CONTENT_WIDTH - 92
      share.style.height = 28
      local cancel = share_actions.add {
        type = "button", name = "cancel_share", caption = { "bulk-imports.share-custom" }, visible = false
      }
      cancel.style.width = 88
      cancel.style.height = 28
      local preview = amount_controls.add { type = "label", name = "share_preview", visible = false }
      preview.style.width = CONTENT_WIDTH
      preview.style.single_line = false
      local trash_note = amount_controls.add {
        type = "label", name = "share_trash_note", caption = { "bulk-imports.share-trash-note" }, visible = false
      }
      trash_note.style.width = CONTENT_WIDTH
      trash_note.style.single_line = false
    end
  end

  local quality_divider = content.add { type = "line", name = "quality_divider", direction = "horizontal" }
  quality_divider.style.width = CONTENT_WIDTH
  local edit_quality = content.add {
    type = "checkbox",
    name = "edit_quality",
    caption = { "bulk-imports.edit-quality" },
    state = get_setting(player, "quality_enabled") == "enabled"
  }
  edit_quality.style.top_margin = 5
  edit_quality.style.font = "default-bold"
  local quality_controls = content.add { type = "flow", name = "quality_controls", direction = "horizontal" }
  quality_controls.style.width = CONTENT_WIDTH
  quality_controls.style.horizontal_spacing = 5
  quality_controls.style.vertical_align = "center"
  local comparator_items = util.table.deepcopy(QUALITY_COMPARATORS)
  comparator_items[ANY_QUALITY_INDEX] = { "gui.any" }
  local comparator = quality_controls.add {
    type = "drop-down",
    name = "comparator",
    items = comparator_items,
    selected_index = 1,
    tooltip = { "bulk-imports.quality-comparator-tooltip" }
  }
  comparator.style.width = 56
  comparator.style.height = 28
  local quality_buttons = quality_controls.add { type = "table", name = "qualities", column_count = 5 }
  quality_buttons.style.horizontal_spacing = 0
  quality_buttons.style.vertical_spacing = 0
  local qualities = {}
  for _, quality in pairs(prototypes.quality) do
    if not quality.hidden then
      qualities[#qualities + 1] = quality
    end
  end
  table.sort(qualities, function(left, right)
    if left.level ~= right.level then
      return left.level < right.level
    end
    if left.order ~= right.order then
      return left.order < right.order
    end
    return left.name < right.name
  end)
  for _, quality in ipairs(qualities) do
    local button = quality_buttons.add {
      type = "sprite-button",
      name = "quality_" .. quality.name,
      sprite = "quality/" .. quality.name,
      style = "tool_button",
      toggled = quality.name == "normal",
      tags = { quality_name = quality.name }
    }
    button.style.width = 28
    button.style.height = 28
  end

  local payload_divider = content.add { type = "line", name = "payload_divider", direction = "horizontal" }
  payload_divider.style.width = CONTENT_WIDTH
  local edit_payload = content.add {
    type = "checkbox",
    name = "edit_payload",
    caption = { "bulk-imports.edit-payload" },
    state = target.is_platform and get_setting(player, "payload_enabled") == "enabled"
  }
  edit_payload.style.top_margin = 5
  edit_payload.style.font = "default-bold"
  local payload_controls = content.add { type = "flow", name = "payload_controls", direction = "vertical" }
  payload_controls.style.vertical_spacing = 5
  payload_controls.style.width = CONTENT_WIDTH
  add_quantity_header(payload_controls, "payload_header", { "bulk-imports.payload-label" },
    get_setting(player, "payload_units") == "items" and 1 or 2)
  local payload_row = payload_controls.add { type = "flow", name = "quantity_row", direction = "horizontal" }
  payload_row.style.horizontal_spacing = 5
  payload_row.style.vertical_align = "center"
  local payload_field = payload_row.add {
    type = "textfield",
    name = "multiplier",
    text = get_setting(player, "payload"),
    lose_focus_on_confirm = true,
    tooltip = { "bulk-imports.payload-tooltip" }
  }
  payload_field.style.width = 60
  payload_field.style.horizontal_align = "center"
  local payload_unit = payload_row.add { type = "label", name = "unit_label", caption = "" }
  payload_unit.style.width = 10
  local payload_slider = payload_row.add {
    type = "slider",
    name = "amount_slider",
    style = "notched_slider",
    minimum_value = 0,
    maximum_value = #PAYLOAD_PRESETS - 1,
    value = 0,
    value_step = 1,
    discrete_values = true,
    tooltip = { "bulk-imports.payload-slider-tooltip" }
  }
  payload_slider.style.width = CONTENT_WIDTH - 80
  local initial_payload, valid_payload = parse_multiplier(payload_field.text, MAX_PAYLOAD_COUNT, false)
  if valid_payload and initial_payload >= 1 then
    payload_slider.slider_value = preset_position(initial_payload, false, PAYLOAD_PRESETS)
  end

  local status = content.add { type = "label", name = "status", caption = "" }
  status.style.single_line = false
  status.style.width = CONTENT_WIDTH

  local actions = panel.add { type = "flow", name = "actions", direction = "horizontal" }
  actions.style.horizontal_spacing = 4
  actions.style.top_margin = 8
  actions.style.vertical_align = "center"
  actions.style.horizontally_stretchable = true
  local undo_button = actions.add {
    type = "button",
    name = "undo",
    caption = { "bulk-imports.undo" },
    tooltip = { "bulk-imports.undo-tooltip" },
    style = "red_button",
    visible = false
  }
  undo_button.style.width = 80
  undo_button.style.height = 28
  undo_button.style.horizontal_align = "center"
  local footer_space = actions.add { type = "empty-widget", name = "footer_space" }
  footer_space.style.horizontally_stretchable = true
  footer_space.style.minimal_width = 0
  local apply_button = actions.add {
    type = "button",
    name = "apply",
    caption = { "bulk-imports.apply" },
    tooltip = { "bulk-imports.apply-tooltip" },
    style = "confirm_button"
  }
  apply_button.style.width = 80
  apply_button.style.height = 28
  apply_button.style.font = "default-semibold"
  apply_button.style.bottom_padding = 0
  apply_button.style.horizontal_align = "center"
  refresh_amount_presets(player)
  if form then
    restore_form(player, form)
  else
    update_edit_controls(player)
    refresh_sections(player, true)
  end
  update_window_controls(player)
  update_panel_height(player)
  if placement == "floating" then
    if preferences.position then
      panel.location = clamp_floating_position(player, preferences.position)
      preferences.position = panel.location
      panel.auto_center = false
    else
      panel.auto_center = true
      panel.force_auto_center()
    end
    panel.bring_to_front()
  end
  player.set_shortcut_toggled(SHORTCUT_NAME, true)
end

local function apply_window_placement(player)
  local panel = get_panel(player)
  if not panel then
    return
  end
  local state, _, target = get_context(player)
  if not state then
    notify_error(player, "target-unavailable")
    destroy_panel(player)
    return
  end
  if state.placement ~= get_setting(player, "placement") then
    local form = capture_form(player)
    remember_floating_position(player)
    open_panel(player, target, form)
  else
    update_window_controls(player)
  end
end

local function selected_source(sources)
  local selected
  for _, source in ipairs(SOURCES) do
    if sources[source].state then
      if selected then
        return nil
      end
      selected = source
    end
  end
  return selected
end

local function compare_keys(left, right)
  for index = 1, #left do
    if left[index] ~= right[index] then
      return left[index] < right[index] and -1 or 1
    end
  end
  return 0
end

local function native_item_key(signal)
  local item = prototypes.item[signal.name]
  local quality = signal.quality and prototypes.quality[signal.quality]
  return {
    item.group.order, item.group.name, item.subgroup.order, item.subgroup.name, item.order, item.name,
    quality and quality.level or -1, quality and quality.order or "", signal.quality or "", signal.comparator or ""
  }
end

local function sort_property_key(filter, property, unit, names)
  local signal = filter.value
  local item = prototypes.item[signal.name]
  local factor = unit == "stacks" and item.stack_size or 1
  if property == "default" then
    return native_item_key(signal)
  elseif property == "name" then
    return { names.values[signal.name]:lower() }
  elseif property == "requested" then
    return { (filter.min or 0) / factor }
  elseif property == "maximum" then
    return { filter.max and filter.max / factor or math.huge }
  elseif property == "quality" then
    return { signal.quality and prototypes.quality[signal.quality].level or -1 }
  elseif property == "planet" then
    local location = filter.import_from
    local planet = location
    if type(location) == "string" then
      planet = prototypes.space_location[location]
    end
    if location and not planet then
      return nil, { "sort-planet-unavailable" }
    end
    return { planet and 1 or 0, planet and planet.order or "", planet and planet.name or "" }
  elseif property == "source" then
    local source = filter.request_from or "planet"
    for index, name in ipairs(SOURCES) do
      if name == source then
        return { index }
      end
    end
  elseif property == "payload" then
    return { (filter.minimum_delivery_count or 0) / factor }
  end
  return nil, { "select-sort" }
end

local function sort_filters(filters, sort, names)
  local indices, rows = {}, {}
  for index, filter in pairs(filters) do
    if filter.value then
      indices[#indices + 1] = index
    end
  end
  table.sort(indices)
  for _, index in ipairs(indices) do
    local filter = filters[index]
    local primary, error = sort_property_key(filter, sort.property, sort.unit, names)
    if error then
      return nil, error
    end
    local secondary = {}
    if sort.secondary then
      secondary, error = sort_property_key(filter, sort.secondary.property, sort.unit, names)
      if error then
        return nil, error
      end
    end
    rows[#rows + 1] = {
      filter = filter, primary = primary, secondary = secondary,
      native = native_item_key(filter.value), index = index
    }
  end
  table.sort(rows, function(left, right)
    local comparison = compare_keys(left.primary, right.primary)
    local descending = sort.descending
    if comparison == 0 and sort.secondary then
      comparison = compare_keys(left.secondary, right.secondary)
      descending = sort.secondary.descending
    end
    if comparison == 0 then
      comparison = compare_keys(left.native, right.native)
      descending = sort.descending
    end
    if comparison == 0 then
      return left.index < right.index
    end
    return descending and comparison > 0 or not descending and comparison < 0
  end)
  local sorted = sort.clear_empty_slots and {} or filters
  for index, row in ipairs(rows) do
    sorted[sort.clear_empty_slots and index or indices[index]] = row.filter
  end
  return sorted
end

local function item_type_key(signal)
  return signal.name .. "\0" .. (signal.quality or "")
end

local function quality_range(signal)
  return not signal.quality or (signal.comparator and signal.comparator ~= "=")
end

local function allocate_capacity(player, updates)
  local state = storage.bulk_import_panels[player.index]
  local unit, unit_error = read_amount_unit(get_panel(player))
  if unit_error then
    return nil, { unit_error }
  end
  local capacity, inventory = get_inventory_capacity(state.owner)
  if capacity == nil then
    return nil, { "capacity-unavailable" }
  end
  local filtered_slots = 0
  if inventory.supports_filters() then
    for index = 1, capacity do
      if inventory.get_filter(index) then
        filtered_slots = filtered_slots + 1
      end
    end
  end
  local groups, sections = {}, {}
  for _, update in ipairs(updates) do
    -- LuaObject wrappers compare equal but are not interchangeable table keys.
    sections[update.section.index] = update
    if update.group ~= "" then
      groups[update.group] = update
    end
    update.weight = 0
    update.multipliers = {}
  end
  local reserved_types = {}
  for _, section in ipairs(state.point.sections) do
    if section.active and section.multiplier > 0 then
      local affected = sections[section.index] or (section.is_manual and section.group ~= "" and groups[section.group])
      if affected then
        affected.weight = affected.weight + section.multiplier
        affected.multipliers[#affected.multipliers + 1] = section.multiplier
      else
        for _, filter in pairs(section.filters) do
          if filter.value and (filter.min or 0) > 0 then
            local signal = filter.value
            local item = prototypes.item[signal.name]
            if not item or (signal.type and signal.type ~= "item") or quality_range(signal) then
              return nil, { "capacity-unsupported-request" }
            end
            local key = item_type_key(signal)
            local reserved = reserved_types[key]
            if not reserved then
              reserved = { count = 0, stack_size = item.stack_size }
              reserved_types[key] = reserved
            end
            reserved.count = reserved.count + math.ceil(filter.min * section.multiplier)
          end
        end
      end
    end
  end
  local reserved_slots = 0
  for _, reserved in pairs(reserved_types) do
    reserved_slots = reserved_slots + math.ceil(reserved.count / reserved.stack_size)
  end
  local types, type_count, smallest_stack = {}, 0, math.huge
  for _, update in ipairs(updates) do
    if update.weight <= 0 then
      return nil, { "capacity-inactive" }
    end
    for _, filter in pairs(update.filters) do
      if filter.value then
        local signal = filter.value
        if quality_range(signal) then
          if get_setting(player, "quality_policy") == "prevent" then
            return nil, { "amount-quality-range", prototypes.item[signal.name].localised_name }
          end
          filter.min = 0
        else
          local key = item_type_key(signal)
          local bucket = types[key]
          if not bucket then
            bucket = {
              item = prototypes.item[signal.name], stack_size = prototypes.item[signal.name].stack_size,
              rows = {}, weight = 0
            }
            types[key] = bucket
            type_count = type_count + 1
            smallest_stack = math.min(smallest_stack, bucket.stack_size)
          end
          bucket.rows[#bucket.rows + 1] = { filter = filter, multipliers = update.multipliers }
          bucket.weight = bucket.weight + update.weight
        end
      end
    end
  end
  if type_count == 0 then
    return nil, { "capacity-no-types" }
  end
  local available = capacity - filtered_slots - reserved_slots
  if available < type_count then
    return nil, { "capacity-insufficient" }
  end
  local amount = math.floor(available / type_count)
  if unit == "items" then
    local low, high = 0, available * smallest_stack
    while low < high do
      local candidate = math.floor((low + high + 1) / 2)
      local slots = 0
      -- Even a partial stack occupies a slot.
      for _, bucket in pairs(types) do
        slots = slots + math.ceil(candidate / bucket.stack_size)
        if slots > available then
          break
        end
      end
      if slots <= available then
        low = candidate
      else
        high = candidate - 1
      end
    end
    amount = low
  end
  for _, bucket in pairs(types) do
    local budget = unit == "stacks" and amount * bucket.stack_size or amount
    local low, high = 0, math.floor(budget / bucket.weight)
    if high > MAX_ITEM_COUNT then
      return nil, { "amount-overflow", bucket.item.localised_name }
    end
    while low < high do
      local candidate = math.floor((low + high + 1) / 2)
      local total = 0
      for _, row in ipairs(bucket.rows) do
        for _, multiplier in ipairs(row.multipliers) do
          total = total + math.ceil(candidate * multiplier)
        end
      end
      if total <= budget then
        low = candidate
      else
        high = candidate - 1
      end
    end
    if low == 0 then
      return nil, { "capacity-insufficient" }
    end
    for _, row in ipairs(bucket.rows) do
      row.filter.min = low
      if row.filter.max and row.filter.max < low then
        row.filter.max = low
      end
    end
  end
  return {
    capacity = capacity, reserved = reserved_slots, filtered = filtered_slots,
    types = type_count, amount = amount, unit = unit
  }
end

prepare_request_updates = function(player, ignore_sort)
  local state = get_context(player)
  if not state then
    return nil, { "target-unavailable" }
  end
  local panel = get_panel(player)
  local flags = edit_flags(player)
  if not flags.sort and not flags.edit_filters and not flags.edit_amounts and not flags.edit_quality
    and not flags.edit_payload then
    return nil, { "select-edits" }
  end
  local selected, selection_error = selected_sections(player)
  if not selected then
    return nil, { selection_error }
  end
  for _, entry in ipairs(selected) do
    local section = entry.section
    if not section.valid or not section.is_manual or section.owner ~= state.owner
      or section.index ~= entry.index or section.group ~= entry.group then
      return nil, { state.selection_mode == "single" and "section-changed" or "sections-changed" }
    end
  end
  local source
  if flags.edit_filters then
    source = selected_source(panel.content.sources)
    if not source then
      return nil, { "select-source" }
    end
  end
  local requested, maximum, amount_unit
  if flags.edit_amounts and not state.share_active then
    local error
    requested, maximum, error, amount_unit = read_amounts(panel)
    if error then
      return nil, { error }
    end
  end
  local quality_name, quality_comparator
  if flags.edit_quality then
    local error
    quality_name, quality_comparator, error = read_quality(player, panel)
    if error then
      return nil, { error }
    end
  end
  local payload_value, payload_unit
  if flags.edit_payload then
    local error
    payload_value, payload_unit, error = read_payload(panel)
    if error then
      return nil, { error }
    end
  end
  local sort
  if flags.sort and not ignore_sort then
    local error
    sort, error = read_sort(player)
    if error then
      return nil, { error }
    end
  end
  local plan = { updates = {}, count = 0, empty_count = 0, zeroed_count = 0 }
  local location = panel.content.planet_row.planet_selector.elem_value
  local seen = {}
  for _, entry in ipairs(selected) do
    local key = entry.group == "" and entry.section or entry.group
    if not seen[key] then
      seen[key] = true
      local previous_filters = entry.section.filters
      local filters = util.table.deepcopy(previous_filters)
      local section_count, quality_items = 0, {}
      for _, filter in pairs(filters) do
        if filter.value then
          local signal = filter.value
          local item = prototypes.item[signal.name]
          if (flags.edit_amounts or flags.edit_quality or flags.edit_payload or flags.sort)
            and (not item or (signal.type and signal.type ~= "item")) then
            return nil, { "amount-non-item" }
          end
          if flags.edit_filters then
            filter.import_from = location
            filter.request_from = source
          end
          if flags.edit_quality then
            if quality_items[signal.name] then
              return nil, { "quality-duplicate", item.localised_name }
            end
            quality_items[signal.name] = true
            signal.quality = quality_name
            signal.comparator = quality_comparator
          end
          if flags.edit_amounts and not state.share_active then
            local factor = amount_unit == "stacks" and item.stack_size or 1
            filter.min = requested * factor
            filter.max = maximum and maximum * factor or nil
          end
          if flags.edit_payload then
            local factor = payload_unit == "stacks" and item.stack_size or 1
            local payload_count = payload_value * factor
            if payload_count > MAX_PAYLOAD_COUNT then
              return nil, { "payload-overflow", item.localised_name }
            end
            filter.minimum_delivery_count = payload_count
          end
          section_count = section_count + 1
        end
      end
      if section_count > 0 then
        plan.updates[#plan.updates + 1] = {
          section = entry.section, group = entry.group, previous_filters = previous_filters, filters = filters
        }
        plan.count = plan.count + section_count
      else
        plan.empty_count = plan.empty_count + 1
      end
    end
  end
  if plan.count == 0 then
    return nil, { state.selection_mode == "single" and "empty-section" or "empty-sections" }
  end
  if flags.edit_amounts and state.share_active then
    local error
    plan.share, error = allocate_capacity(player, plan.updates)
    if error then
      return nil, error
    end
  end
  for _, update in ipairs(plan.updates) do
    for _, filter in pairs(update.filters) do
      if filter.value then
        local signal = filter.value
        local item = prototypes.item[signal.name]
        if (flags.edit_amounts or flags.edit_quality) and quality_range(signal)
          and ((filter.min or 0) ~= 0 or (flags.edit_amounts and state.share_active)) then
          if get_setting(player, "quality_policy") == "prevent" then
            return nil, { "amount-quality-range", item.localised_name }
          end
          filter.min = 0
          plan.zeroed_count = plan.zeroed_count + 1
        end
        if flags.edit_amounts and ((filter.min or 0) > MAX_ITEM_COUNT
          or (filter.max and filter.max > MAX_ITEM_COUNT)) then
          return nil, { "amount-overflow", item.localised_name }
        end
      end
    end
    if sort then
      local sorted, error = sort_filters(update.filters, sort, state.sort_names)
      if error then
        return nil, error
      end
      update.filters = sorted
    end
  end
  return plan
end

refresh_capacity_preview = function(player)
  local plan, error = prepare_request_updates(player, true)
  local controls = get_panel(player).content.amount_controls
  if error then
    local message = util.table.deepcopy(error)
    message[1] = "bulk-imports." .. message[1]
    controls.share_preview.caption = message
  else
    controls.share_preview.caption = {
      plan.share.unit == "items" and "bulk-imports.share-preview-items" or "bulk-imports.share-preview",
      plan.share.amount, plan.share.types, plan.share.reserved, plan.share.capacity
    }
    if plan.share.filtered > 0 then
      controls.share_preview.caption = {
        "", controls.share_preview.caption, "\n", { "bulk-imports.share-filtered-slots", plan.share.filtered }
      }
    end
    local presets = storage.bulk_import_panels[player.index].amount_presets
    controls.requested.multiplier.text = tostring(plan.share.amount)
    controls.requested.amount_slider.slider_value = preset_position(plan.share.amount, false, presets)
  end
  return error
end

local function stage_capacity_share(player)
  local state = get_context(player)
  if not state then
    notify_error(player, "target-unavailable")
    return
  end
  local _, changed = synchronize_sections(player)
  if changed then
    notify_error(player, "selection-updated")
    return
  end
  if not edit_flags(player).edit_amounts then
    notify_error(player, "select-amounts")
    return
  end
  local already_active = state.share_active
  state.share_active = true
  local plan, error = prepare_request_updates(player, true)
  if error then
    state.share_active = already_active
    notify_error(player, table.unpack(error))
    return
  end
  local controls = get_panel(player).content.amount_controls
  if not already_active then
    state.share_draft = {
      requested = controls.requested.multiplier.text, maximum = controls.trash_above.multiplier.text,
      units = controls.requested_header.units.selected_index
    }
  end
  controls.requested.multiplier.text = tostring(plan.share.amount)
  refresh_amount_presets(player)
  update_edit_controls(player)
end

local function cancel_capacity_share(player)
  local state = storage.bulk_import_panels[player.index]
  local draft = state.share_draft
  if not draft then
    return
  end
  local controls = get_panel(player).content.amount_controls
  state.share_active = nil
  state.share_draft = nil
  controls.requested_header.units.selected_index = draft.units
  controls.requested.multiplier.text = draft.requested
  controls.trash_above.multiplier.text = draft.maximum
  refresh_amount_presets(player)
  update_edit_controls(player)
end

local function apply_imports(player)
  local state = get_context(player)
  if not state then
    notify_error(player, "target-unavailable")
    destroy_panel(player)
    return
  end
  if not can_edit_requests(player) then
    notify_error(player, "permission-denied")
    return
  end
  local _, selection_changed = synchronize_sections(player)
  if selection_changed then
    notify_error(player, "selection-updated")
    return
  end
  local plan, error = prepare_request_updates(player)
  if error then
    notify_error(player, table.unpack(error))
    return
  end
  for _, update in ipairs(plan.updates) do
    update.section.filters = update.filters
    update.filters = update.section.filters
  end
  state.undo = { updates = plan.updates, count = plan.count }
  local panel = get_panel(player)
  panel.actions.undo.visible = true
  local message = state.selection_mode == "single" and { "bulk-imports.applied", plan.count }
    or { "bulk-imports.applied-multiple", plan.count, #plan.updates }
  if plan.empty_count > 0 then
    message = { "", message, "\n", { "bulk-imports.skipped-empty-sections", plan.empty_count } }
  end
  if plan.zeroed_count > 0 then
    message = { "", message, "\n", { "bulk-imports.quality-zeroed", plan.zeroed_count } }
  end
  set_status(panel, message, true)
end

local function undo_apply(player)
  local state = get_context(player)
  if not state then
    notify_error(player, "target-unavailable")
    destroy_panel(player)
    return
  end
  if not can_edit_requests(player) then
    notify_error(player, "permission-denied")
    return
  end
  local undo = state.undo
  if not undo then
    notify_error(player, "nothing-to-undo")
    return
  end

  for _, update in ipairs(undo.updates) do
    local section = update.section
    if not section.valid or not section.is_manual or section.owner ~= state.owner
      or section.group ~= update.group
      or not util.table.compare(section.filters, update.filters) then
      notify_error(player, "undo-conflict")
      return
    end
  end

  for _, update in ipairs(undo.updates) do
    update.section.filters = update.previous_filters
  end
  state.undo = nil
  local panel = get_panel(player)
  panel.actions.undo.visible = false
  set_status(panel, { "bulk-imports.undone", undo.count }, true)
end

local function synchronize_editor_visibility(player)
  local target = get_open_requester(player)
  local state = storage.bulk_import_panels[player.index]
  local visible = get_setting(player, "visible")
  if state and (not visible or not target or state.owner ~= target.owner or state.point ~= target.point
    or state.gui_type ~= target.gui_type) then
    destroy_panel(player)
  end
  player.set_shortcut_available(SHORTCUT_NAME, target ~= nil)
  if target and visible and not get_panel(player) then
    open_panel(player, target)
  end
  player.set_shortcut_toggled(SHORTCUT_NAME, visible)
end

local function apply_setting_change(player, key)
  if key == "visible" then
    synchronize_editor_visibility(player)
  elseif key == "placement" then
    apply_window_placement(player)
  elseif key == "locked" then
    if get_panel(player) then
      update_window_controls(player)
    end
  elseif key == "remember_position" then
    local remember = get_setting(player, "remember_position")
    local preferences = get_preferences(player)
    local state = storage.bulk_import_panels[player.index]
    if not remember then
      preferences.position = nil
      if state and state.remember_position ~= remember then
        center_floating_panel(player)
      end
    end
    if state then
      state.remember_position = remember
    end
  elseif key == "quality_policy" and get_panel(player) then
    update_quality_availability(player)
    update_apply_state(player, true)
  elseif CATEGORY_SETTING_KEYS[key] and get_panel(player) then
    local panel = get_panel(player)
    local state = storage.bulk_import_panels[player.index]
    for _, category in ipairs(EDIT_CATEGORIES) do
      local name = category.name
      if category_setting(state, name) == key and not panel.content[name].visible
        and category_visible(player, name) then
        panel.content[name].state = get_setting(player, key) == "enabled"
      end
    end
    update_edit_controls(player)
  end
end

local function set_setting(player, key, value)
  local values = settings.get_player_settings(player)
  local name = SETTINGS[key]
  if values[name].value ~= value then
    values[name] = { value = value }
  end
  apply_setting_change(player, key)
end

local function reset_editor_position(player)
  get_preferences(player).position = nil
  set_setting(player, "placement", "floating")
  set_setting(player, "visible", true)
  set_panel_minimized(player, false)
  center_floating_panel(player)
  if not get_panel(player) then
    player.print { "bulk-imports.position-reset" }
  end
end

local function reset_panels()
  local previous_panels = storage.bulk_import_panels
  storage.bulk_import_panels = {}
  storage.bulk_import_preferences = storage.bulk_import_preferences or {}
  for _, player in pairs(game.players) do
    destroy_panel(player)
    local preferences = get_preferences(player)
    if preferences.minimized == nil then
      local previous = previous_panels and previous_panels[player.index]
      preferences.minimized = previous ~= nil and previous.minimized == true
    end
    synchronize_editor_visibility(player)
  end
end

script.on_init(reset_panels)
script.on_configuration_changed(reset_panels)

local function on_inventory_context_changed(event)
  local player = game.get_player(event.player_index)
  synchronize_editor_visibility(player)
  synchronize_editor(player)
end

script.on_event(defines.events.on_gui_opened, on_inventory_context_changed)
script.on_event(defines.events.on_player_controller_changed, on_inventory_context_changed)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  local state = storage.bulk_import_panels[event.player_index]
  if event.gui_type == defines.gui_type.entity or event.gui_type == defines.gui_type.controller
    or (state and event.entity == state.owner) then
    destroy_panel(player)
    player.set_shortcut_available(SHORTCUT_NAME, false)
  else
    synchronize_editor(player)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= SHORTCUT_NAME then
    return
  end
  local player = game.get_player(event.player_index)
  if get_panel(player) then
    set_setting(player, "visible", false)
    return
  end
  local target = get_open_requester(player)
  if not target then
    player.set_shortcut_available(SHORTCUT_NAME, false)
    notify_error(player, "launcher-unavailable")
    return
  end
  player.set_shortcut_available(SHORTCUT_NAME, true)
  set_setting(player, "visible", true)
end)

script.on_event(defines.events.on_gui_click, function(event)
  if event.button ~= defines.mouse_button_type.left then
    return
  end
  local player, panel = get_gui_event_context(event)
  if not player then
    return
  end
  if event.element == panel.titlebar.close_panel then
    set_setting(player, "visible", false)
  elseif event.element == panel.titlebar.minimize then
    set_panel_minimized(player, true)
  elseif event.element == panel.minimized_icon then
    set_panel_minimized(player, false)
  elseif event.element == panel.titlebar.dock_toggle then
    panel.placement_menu.visible = not panel.placement_menu.visible
    update_panel_height(player)
  elseif event.element.parent == panel.placement_menu then
    local choice = event.element.tags.placement
    if choice == "center" then
      reset_editor_position(player)
    else
      set_setting(player, "placement", choice)
    end
    panel = get_panel(player)
    if panel then
      panel.placement_menu.visible = false
      update_panel_height(player)
    end
  elseif event.element == panel.titlebar.lock_toggle then
    if player.gui.screen[PANEL_NAME] == panel then
      set_setting(player, "locked", not get_setting(player, "locked"))
    end
  elseif event.element == panel.titlebar.recenter then
    center_floating_panel(player)
  elseif event.element == panel.content.sort_controls.primary_row.sort_order
    or event.element == panel.content.sort_controls.secondary_row.secondary_sort_order then
    local direction = sort_direction_choice(event.element)
    if not direction then
      notify_error(player, "select-sort")
      return
    end
    event.element.tags = { sort_direction = direction == "ascending" and "descending" or "ascending" }
    update_edit_controls(player)
  elseif event.element == panel.actions.apply then
    apply_imports(player)
    return
  elseif event.element == panel.actions.undo then
    synchronize_editor(player)
    undo_apply(player)
    return
  elseif event.element == panel.content.multiple_sections.selection_actions.check_all then
    synchronize_sections(player)
    set_all_sections(player, true)
  elseif event.element == panel.content.multiple_sections.selection_actions.check_none then
    synchronize_sections(player)
    set_all_sections(player, false)
  elseif event.element == panel.content.planet_row.clear_planet then
    panel.content.planet_row.planet_selector.elem_value = nil
    update_apply_state(player, true)
  elseif event.element == panel.content.amount_controls.share_actions.share_capacity then
    stage_capacity_share(player)
    return
  elseif event.element == panel.content.amount_controls.share_actions.cancel_share then
    cancel_capacity_share(player)
  elseif event.element.parent == panel.content.quality_controls.qualities then
    local quality_name = event.element.tags.quality_name
    if not event.element.enabled or not player.force.is_quality_unlocked(quality_name) then
      notify_error(player, "quality-unavailable")
      return
    end
    for _, button in ipairs(panel.content.quality_controls.qualities.children) do
      button.toggled = button == event.element
    end
    update_apply_state(player, true)
  end
  synchronize_editor(player)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local player, panel = get_gui_event_context(event)
  if not player then
    return
  end
  if event.element.parent == panel.content.sources then
    for _, source in ipairs(SOURCES) do
      panel.content.sources[source].state = source == event.element.name
    end
    update_apply_state(player, true)
  elseif event.element.parent == panel.content and CATEGORIES_BY_NAME[event.element.name] then
    update_edit_controls(player)
  elseif event.element == panel.content.sort_controls.clear_empty_slots then
    update_apply_state(player, true)
  elseif event.element.parent == panel.content.selection_modes then
    set_selection_mode(player, event.element.name)
  elseif event.element.parent == panel.content.multiple_sections.section_list then
    local state = storage.bulk_import_panels[player.index]
    local entry = state.sections[event.element.tags.entry_index]
    if not entry then
      refresh_sections(player)
      notify_error(player, "sections-changed")
      return
    end
    entry.checked = event.element.state
    update_selection_ui(player, true)
  end
  synchronize_editor(player)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local player, panel = get_gui_event_context(event)
  if not player then
    return
  end
  if event.element == panel.content.section then
    update_selection_ui(player, true)
  elseif event.element == panel.content.amount_controls.requested_header.units then
    refresh_amount_presets(player)
    update_unit_labels(player)
    update_apply_state(player, true)
  elseif event.element == panel.content.payload_controls.payload_header.units then
    update_unit_labels(player)
    update_apply_state(player, true)
  elseif event.element == panel.content.quality_controls.comparator then
    update_quality_availability(player)
    update_apply_state(player, true)
  elseif event.element.parent == panel.content.sort_controls
    or event.element.parent == panel.content.sort_controls.primary_row
    or event.element.parent == panel.content.sort_controls.secondary_row then
    update_edit_controls(player)
  end
  synchronize_editor(player)
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  local player, panel = get_gui_event_context(event)
  if not player then
    return
  end
  if event.element == panel.content.planet_row.planet_selector then
    update_apply_state(player, true)
  end
  synchronize_editor(player)
end)

local function on_amount_changed(event)
  local player, panel = get_gui_event_context(event)
  if not player then
    return
  end
  for _, name in ipairs({ "requested", "trash_above" }) do
    local row = panel.content.amount_controls[name]
    if event.element == row.multiplier or event.element == row.amount_slider then
      update_amount_controls(player, name, event.element == row.amount_slider)
      synchronize_editor(player)
      return
    end
  end
  local payload_row = panel.content.payload_controls.quantity_row
  if event.element == payload_row.multiplier or event.element == payload_row.amount_slider then
    update_payload_controls(player, event.element == payload_row.amount_slider)
  end
  synchronize_editor(player)
end

script.on_event(defines.events.on_gui_value_changed, on_amount_changed)
script.on_event(defines.events.on_gui_text_changed, on_amount_changed)
script.on_event(defines.events.on_gui_confirmed, on_amount_changed)

script.on_event(defines.events.on_gui_location_changed, function(event)
  local player, panel = get_gui_event_context(event)
  if not player or event.element ~= panel then
    return
  end
  if player.gui.screen[PANEL_NAME] ~= panel or get_setting(player, "locked") then
    return
  end
  panel.location = clamp_floating_position(player, panel.location)
  panel.auto_center = false
  if get_setting(player, "remember_position") then
    get_preferences(player).position = panel.location
  end
end)

local function on_display_changed(event)
  local player = game.get_player(event.player_index)
  local preferences = get_preferences(player)
  local resolution = player.display_resolution
  local scale = player.display_scale
  local changed = preferences.display_width ~= resolution.width or preferences.display_height ~= resolution.height
    or preferences.display_scale ~= scale
  preferences.display_width = resolution.width
  preferences.display_height = resolution.height
  preferences.display_scale = scale
  update_panel_height(player)
  if changed then
    center_floating_panel(player)
  end
end

script.on_event(defines.events.on_player_display_resolution_changed, on_display_changed)
script.on_event(defines.events.on_player_display_scale_changed, on_display_changed)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  get_preferences(player)
  synchronize_editor_visibility(player)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  local key = SETTING_KEYS[event.setting]
  if migrating_settings or not key or event.setting_type ~= "runtime-per-user" or not event.player_index then
    return
  end
  apply_setting_change(game.get_player(event.player_index), key)
end)

script.on_event(defines.events.on_string_translated, function(event)
  local state = storage.bulk_import_panels[event.player_index]
  local names = state and state.sort_names
  local name = names and names.pending[event.id]
  if not name then
    return
  end
  names.pending[event.id] = nil
  if event.translated then
    names.values[name] = event.result
  else
    names.failed[name] = true
  end
  local player = game.get_player(event.player_index)
  local panel = player and get_panel(player)
  if panel then
    local caption = panel.content.status.caption
    local waiting = type(caption) == "table" and caption[1] == "bulk-imports.sort-names-pending"
    update_apply_state(player, waiting, panel.content.status.visible and not waiting)
    if not event.translated then
      notify_error(player, "sort-name-failed")
    end
  end
end)

script.on_event(defines.events.on_player_locale_changed, function(event)
  local state = storage.bulk_import_panels[event.player_index]
  local player = game.get_player(event.player_index)
  if state and player then
    state.sort_names = nil
    update_apply_state(player, true)
  end
end)

script.on_event(RESET_INPUT_NAME, function(event)
  reset_editor_position(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_player_left_game, function(event)
  local player = game.get_player(event.player_index)
  remember_floating_position(player)
  destroy_panel(player)
  player.set_shortcut_available(SHORTCUT_NAME, false)
end)

local function on_player_context_reset(event)
  local player = game.get_player(event.player_index)
  remember_floating_position(player)
  destroy_panel(player)
  synchronize_editor_visibility(player)
end

script.on_event(defines.events.on_player_joined_game, on_player_context_reset)
script.on_event(defines.events.on_player_changed_force, on_player_context_reset)
script.on_event(defines.events.on_player_died, on_player_context_reset)

script.on_event(defines.events.on_tick, function(event)
  for player_index, state in pairs(storage.bulk_import_panels) do
    if event.tick % SYNCHRONIZE_INTERVAL == 0 then
      local player = game.get_player(player_index)
      if player then
        synchronize_editor(player)
      end
    end
    if state.status_expires_at and event.tick >= state.status_expires_at then
      state.status_expires_at = nil
      local player = game.get_player(player_index)
      local panel = player and get_panel(player)
      if panel then
        set_status(panel, "")
      end
    end
  end
end)

script.on_event(defines.events.on_entity_logistic_slot_changed, function(event)
  for player_index, state in pairs(storage.bulk_import_panels) do
    if state.owner == event.entity and event.section.valid and event.section.is_manual then
      local player = game.get_player(player_index)
      if player then
        synchronize_editor(player)
      end
    end
  end
end)

script.on_event(defines.events.on_player_removed, function(event)
  storage.bulk_import_panels[event.player_index] = nil
  storage.bulk_import_preferences[event.player_index] = nil
end)
