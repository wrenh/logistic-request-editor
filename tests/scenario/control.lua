local TEST_INTERFACE = "logistic-request-editor-tests"
local handlers = setmetatable({}, {
  __index = function(_, event)
    return function(data) remote.call(TEST_INTERFACE, "dispatch", event, data) end
  end
})
local PANEL_NAME = "logistic_request_editor_bulk_imports"
local SHORTCUT_NAME = "logistic-request-editor-request-editor"
local RESET_INPUT_NAME = "logistic-request-editor-reset-editor-position"
local SETTING_PREFIX = "logistic-request-editor-"

local function initialize()
  remote.call(TEST_INTERFACE, "initialize")
end

local function get_test_preferences(player)
  return remote.call(TEST_INTERFACE, "get_preferences", player.index)
end

local function get_user_setting(player, suffix)
  return settings.get_player_settings(player)[SETTING_PREFIX .. suffix].value
end

local function set_user_setting(player, suffix, value)
  remote.call(TEST_INTERFACE, "set_setting", player.index, SETTING_PREFIX .. suffix, value)
end

local function get_editor(player)
  return player.gui.relative[PANEL_NAME] or player.gui.screen[PANEL_NAME]
end

local function assert_same(expected, actual, path)
  path = path or "filter"
  assert(type(expected) == type(actual), path .. ": type changed")
  if type(expected) ~= "table" then
    assert(expected == actual, path .. ": value changed")
    return
  end
  for key, value in pairs(expected) do
    assert_same(value, actual[key], path .. "." .. tostring(key))
  end
  for key in pairs(actual) do
    assert(expected[key] ~= nil, path .. "." .. tostring(key) .. ": unexpected field")
  end
end

local function without_imports(section)
  local filters = section.filters
  for _, filter in pairs(filters) do
    filter.import_from = nil
    filter.request_from = nil
  end
  return filters
end

local function without_amounts(section)
  local filters = section.filters
  for _, filter in pairs(filters) do
    filter.min = nil
    filter.max = nil
  end
  return filters
end

local function without_quality(section)
  local filters = section.filters
  for _, filter in pairs(filters) do
    if filter.value then
      filter.value.quality = nil
      filter.value.comparator = nil
    end
  end
  return filters
end

local function without_payload(section)
  local filters = section.filters
  for _, filter in pairs(filters) do
    filter.minimum_delivery_count = nil
  end
  return filters
end

local function assert_quality(section, name, comparator)
  for _, filter in pairs(section.filters) do
    if filter.value then
      assert(filter.value.quality == name and filter.value.comparator == comparator,
        "The quality condition was not applied to every selected request")
    end
  end
end

local function without_requested_quality(section)
  local filters = without_quality(section)
  for _, filter in pairs(filters) do
    filter.min = nil
  end
  return filters
end

local function make_hub(name)
  local platform = assert(game.forces.player.create_space_platform {
    name = name,
    planet = "nauvis",
    starter_pack = "space-platform-starter-pack"
  })
  return assert(platform.apply_starter_pack(true))
end

script.on_event(defines.events.on_tick, function()
  initialize()
  local player = assert(game.get_player(1))
  assert(get_user_setting(player, "sort") == "enabled", "Sorting must start enabled by default")
  set_user_setting(player, "sort", "disabled")
  set_user_setting(player, "default-chest-requested-mode", "custom")
  local panel
  local function sort_element(name)
    local controls = panel.content.sort_controls
    if name == "property" or name == "sort_order" then
      return controls.primary_row[name]
    end
    if name == "secondary_property" or name == "secondary_sort_order" then
      return controls.secondary_row[name]
    end
    error("Unknown sort control: " .. name)
  end
  local function launch_editor()
    handlers[defines.events.on_lua_shortcut] {
      player_index = player.index,
      prototype_name = SHORTCUT_NAME
    }
    panel = assert(get_editor(player), "The shortcut did not open the request editor")
    return panel
  end
  game.forces.player.research_all_technologies()
  local hub = make_hub("Bulk import integration tests")
  local point = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
  local section
  for _, candidate in ipairs(point.sections) do
    if candidate.is_manual then
      section = candidate
      break
    end
  end
  section = section or assert(point.add_section())
  section.group = "Bulk import integration group"
  section.active = false
  section.multiplier = 2.5

  local items = {
    "iron-plate", "copper-plate", "steel-plate", "iron-gear-wheel", "copper-cable",
    "electronic-circuit", "advanced-circuit", "processing-unit", "engine-unit",
    "electric-engine-unit", "low-density-structure", "rocket-fuel", "battery",
    "plastic-bar", "sulfur", "stone", "stone-brick", "concrete", "refined-concrete",
    "uranium-235", "uranium-238", "tungsten-ore", "tungsten-plate", "holmium-ore",
    "holmium-plate", "superconductor", "supercapacitor", "calcite", "carbon", "ice"
  }
  local qualities = { "normal", "rare", "legendary" }
  for index, item in ipairs(items) do
    local slot = index > 10 and index + 1 or index
    assert(section.set_slot(slot, {
      value = { name = item, quality = qualities[(index - 1) % 3 + 1] },
      min = index == 30 and 0 or index * 10,
      max = index % 3 ~= 0 and index * 100 or nil,
      minimum_delivery_count = index % 4 == 0 and index + 1 or nil,
      import_from = index % 2 == 0 and "nauvis" or "fulgora",
      request_from = index % 2 == 0 and "platforms" or "planet"
    }) == nil)
  end
  local original = without_imports(section)
  local automatic = {}
  for _, candidate in ipairs(point.sections) do
    if not candidate.is_manual then
      automatic[#automatic + 1] = { section = candidate, filters = candidate.filters }
    end
  end

  local before_default_open = section.filters
  player.set_controller { type = defines.controllers.remote, surface = hub.surface, position = hub.position }
  player.opened = hub
  handlers[defines.events.on_gui_opened] {
    player_index = player.index,
    entity = hub,
    gui_type = defines.gui_type.entity
  }
  panel = assert(get_editor(player), "The factory visibility default must open the editor automatically")
  assert(panel.content.edit_amounts.state and panel.content.amount_controls.visible
    and panel.content.amount_controls.requested.multiplier.text == "1"
    and panel.content.payload_controls.payload_header.units.selected_index == 2
    and panel.content.payload_controls.quantity_row.multiplier.text == "1"
    and not panel.content.edit_payload.state,
    "A fresh platform editor must enable amount editing and default payload units to Stacks")
  assert_same(before_default_open, section.filters, "Opening the editor with new defaults must not apply requests")
  set_user_setting(player, "show-editor", false)
  set_user_setting(player, "default-payload-units", "items")
  set_user_setting(player, "edit-platform-amounts", "disabled")
  remote.call(TEST_INTERFACE, "configure")
  assert(not get_user_setting(player, "show-editor")
    and get_user_setting(player, "default-payload-units") == "items"
    and get_user_setting(player, "edit-platform-amounts") == "disabled",
    "A configuration change must retain saved choices that differ from the new defaults")
  assert(not get_editor(player), "Disabling automatic opening must leave the editor hidden")
  assert(player.is_shortcut_available(SHORTCUT_NAME) and not player.is_shortcut_toggled(SHORTCUT_NAME),
    "The supported inventory did not enable the closed editor's launcher")
  launch_editor()
  assert(player.opened == hub and player.is_shortcut_toggled(SHORTCUT_NAME),
    "Launching the editor closed the inventory or failed to toggle its shortcut")

  local function click(element)
    handlers[defines.events.on_gui_click] {
      player_index = player.index,
      element = element,
      button = defines.mouse_button_type.left
    }
  end

  local function choose_sort_direction(name, index)
    assert(index == 1 or index == 2, "Choose an ascending or descending sort direction")
    local direction = index == 1 and "ascending" or "descending"
    local element = sort_element(name)
    if element.tags.sort_direction ~= direction then
      click(element)
    end
    local sprite = direction == "ascending" and "virtual-signal/up-arrow" or "virtual-signal/down-arrow"
    assert(element.tags.sort_direction == direction and element.sprite == sprite,
      "The sort direction button must toggle and display the current direction")
  end

  local function poll_editor()
    handlers[defines.events.on_tick] { tick = game.tick + 60 }
  end

  local function checkbox_for(target)
    for _, checkbox in ipairs(panel.content.multiple_sections.section_list.children) do
      if checkbox.tags.section_index == target.index then
        return checkbox
      end
    end
    error("Request section is missing from the checkbox list: " .. target.group)
  end

  local function choose_section(target)
    panel.content.section.selected_index = checkbox_for(target).tags.entry_index
    handlers[defines.events.on_gui_selection_state_changed] {
      player_index = player.index,
      element = panel.content.section
    }
  end

  local function choose_placement(value)
    if not panel.placement_menu.visible then
      click(panel.titlebar.dock_toggle)
    end
    click(panel.placement_menu["place_" .. value])
    panel = assert(get_editor(player), "Choosing placement removed the editor")
  end

  -- Headless GUI getters omit inherited sizes; the fixture captures real prototype dimensions.
  local button_styles = assert(prototypes.mod_data["logistic-request-editor-test-button-styles"]).data
  local editor_icon = button_styles.editor_icon
  assert(editor_icon.shortcut_size == 32 and editor_icon.small_shortcut_size == 24
    and editor_icon.shortcut_filename == "__logistic-request-editor__/graphics/editor-icon.png"
    and editor_icon.small_shortcut_filename == "__logistic-request-editor__/graphics/editor-icon-small.png"
    and editor_icon.filename == editor_icon.small_shortcut_filename,
    "Shortcut and panel icons must use the thumbnail's appropriately resized variants")
  assert(panel.titlebar.minimize.sprite == "logistic-request-editor-editor-icon"
    and panel.titlebar.minimize.style.name == "logistic_request_editor_editor_icon_button"
    and panel.minimized_icon.sprite == panel.titlebar.minimize.sprite
    and editor_icon.width <= editor_icon.header_button_size and editor_icon.height <= editor_icon.header_button_size
    and panel.minimized_icon.style.maximal_width == 28 and panel.minimized_icon.style.maximal_height == 28
    and editor_icon.header_preserves_colors,
    "The shared thumbnail must preserve its colors and fit the existing minimize/restore button slots")
  local function button_height(element, property)
    local value = element.style[property]
    if value then
      return value
    end
    local name = element.style.name
    while name do
      local definition = assert(button_styles[name], "Missing action-button style data: " .. name)
      value = definition[property] or definition.height
      if value then
        return value
      end
      name = definition.parent
    end
  end
  local undo_min = button_height(panel.actions.undo, "minimal_height")
  local undo_max = button_height(panel.actions.undo, "maximal_height")
  local apply_min = button_height(panel.actions.apply, "minimal_height")
  local apply_max = button_height(panel.actions.apply, "maximal_height")
  assert(undo_min and undo_min > 0
    and undo_min == undo_max
    and undo_min == apply_min
    and undo_max == apply_max,
    "Undo and Apply button heights do not match")
  assert(apply_min == button_styles.button.minimal_height
    and panel.actions.apply.style.font == button_styles.button.font,
    "Footer buttons must use the native compact height and standard button font")
  assert(panel.style.minimal_width <= 370 * 0.8 and panel.style.maximal_width <= 370 * 0.8,
    "The panel must be at least 20 percent narrower than the original")
  assert(panel.style.minimal_width == 296 and panel.style.maximal_width == 296
    and panel.content.style.minimal_width == panel.style.minimal_width - 24
    and panel.content.style.maximal_width == panel.style.maximal_width - 24,
    "Balanced inset margins must consume interior space without widening the outer panel")
  local control_width = panel.content.style.maximal_width - button_styles.content_left_padding
    - button_styles.content_right_padding - button_styles.content_scrollbar_width
  assert(panel.content.section.style.maximal_width == control_width
    and panel.content.sort_controls.primary_row.style.maximal_width == control_width
    and sort_element("property").style.maximal_width + sort_element("sort_order").style.maximal_width
      + panel.content.sort_controls.primary_row.style.horizontal_spacing == control_width
    and panel.content.amount_controls.style.maximal_width == control_width
    and panel.content.quality_controls.style.maximal_width == control_width
    and panel.content.payload_controls.style.maximal_width == control_width
    and panel.content.status.style.maximal_width == control_width,
    "Inner controls must fit the narrower inset, including scrollbar space")
  assert(sort_element("property").get_index_in_parent() == 1
    and sort_element("sort_order").get_index_in_parent() == 2
    and sort_element("sort_order").style.maximal_width == 28
    and sort_element("sort_order").style.maximal_height == 28,
    "The compact direction toggle must sit to the right of its sort dropdown")
  local balance_actions = panel.content.amount_controls.share_actions
  assert(balance_actions.share_capacity.style.maximal_width + balance_actions.cancel_share.style.maximal_width
    + balance_actions.style.horizontal_spacing <= control_width,
    "Balance requests and Custom must fit together without expanding the inset")
  assert(panel.actions.apply.style.maximal_width <= 100
    and panel.actions.apply.style.horizontal_align == "center",
    "Apply must be compact with centered text")
  assert(panel.actions.apply.style.maximal_width
    + panel.actions.undo.style.maximal_width + panel.actions.style.horizontal_spacing
    <= panel.style.maximal_width - 16, "The Undo button makes the footer too wide")
  assert(not panel.actions.undo.visible, "Undo was available before the first Apply")
  assert(panel.actions.undo.style.name == "red_button"
    and panel.actions.undo.get_index_in_parent() == 1
    and panel.actions.footer_space.get_index_in_parent() == 2
    and panel.actions.apply.get_index_in_parent() == 3
    and panel.actions.style.horizontally_stretchable
    and panel.actions.footer_space.style.horizontally_stretchable,
    "Footer layout must keep red Undo on the left and Apply on the right")
  assert(panel.actions.style.top_margin >= 8 and panel.actions.style.vertical_align == "center"
    and panel.content.style.maximal_height
      == math.max(1, math.floor(player.display_resolution.height / player.display_scale)
        - 112 - panel.actions.style.top_margin),
    "Footer buttons need room above them, taken from the viewport's interior height budget")
  assert(button_styles.content_vertical_spacing == 5
    and panel.content.source_label.style.top_margin + button_styles.content_vertical_spacing == 10,
    "Label/control spacing and group spacing do not match the requested layout")
  assert(panel.actions.refresh == nil, "Automatic updates should replace the Refresh button")
  assert(button_styles.content_always_draw_borders and button_styles.content_inset_matches_frame,
    "The scrolling body must always show the native shallow-frame inset")

  local before_close = section.filters
  click(panel.titlebar.close_panel)
  assert(not panel.valid and not get_editor(player),
    "X did not close the companion panel")
  assert(player.opened == hub, "Closing the companion panel also closed the hub")
  assert_same(before_close, section.filters, "closed-panel requests")

  player.opened = nil
  handlers[defines.events.on_gui_closed] {
    player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
  }
  assert(not player.is_shortcut_available(SHORTCUT_NAME) and not player.is_shortcut_toggled(SHORTCUT_NAME))
  player.opened = hub
  handlers[defines.events.on_gui_opened] {
    player_index = player.index,
    entity = hub,
    gui_type = defines.gui_type.entity
  }
  assert(not get_editor(player), "Reopening an inventory must leave the editor closed")
  launch_editor()
  assert_same(before_close, section.filters, "reopened-panel requests")
  log("BULK_IMPORT_TEST: matching button heights (" .. apply_min
    .. " px); panel-only close and hub reopening preserve requests")

  local function apply(location, source)
    if location then
      panel.content.planet_row.planet_selector.elem_value = location
    else
      click(panel.content.planet_row.clear_planet)
      assert(panel.content.planet_row.planet_selector.elem_value == nil)
    end
    handlers[defines.events.on_gui_checked_state_changed] {
      player_index = player.index,
      element = panel.content.sources[source]
    }
    click(panel.actions.apply)
  end

  for _, source in ipairs({ "planet", "platforms", "all" }) do
    for _, location in ipairs({ "fulgora", false }) do
      apply(location, source)
      local count = 0
      for _, filter in pairs(section.filters) do
        if filter.value then
          count = count + 1
          assert((filter.request_from or "planet") == source, "Import source was not applied")
          if location then
            assert(filter.import_from and filter.import_from.name == location, "Import planet was not applied")
          else
            assert(filter.import_from == nil, "Planet restriction was not cleared")
          end
        end
      end
      assert(count == 30, "Expected exactly 30 item requests")
      assert(tonumber(panel.content.status.caption[2]) == 30,
        "Confirmation count is incorrect: " .. helpers.table_to_json(panel.content.status.caption))
      assert_same(original, without_imports(section))
      assert(section.active == false and section.multiplier == 2.5)
      assert(section.get_slot(11).value == nil, "An empty slot was filled")
    end
  end
  for _, entry in ipairs(automatic) do
    assert_same(entry.filters, entry.section.filters, "automatic section")
  end
  log("BULK_IMPORT_TEST: 30 requests, six import combinations, preserved fields and empty slots")

  local second_hub = make_hub("Shared group integration tests")
  local second_point = second_hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
  local alias = assert(second_point.add_section(section.group))
  local untouched = assert(point.add_section())
  untouched.set_slot(1, {
    value = { name = "iron-plate", quality = "normal" },
    min = 17,
    import_from = "fulgora",
    request_from = "planet"
  })
  local untouched_filters = untouched.filters
  poll_editor()
  apply("nauvis", "platforms")
  assert_same(section.filters, alias.filters, "shared group")
  assert_same(untouched_filters, untouched.filters, "other manual section")
  assert(section.group == "Bulk import integration group")
  log("BULK_IMPORT_TEST: shared groups propagate; other sections remain unchanged")

  section.group = "Renamed integration group"
  local renamed_filters = section.filters
  click(panel.actions.apply)
  assert_same(renamed_filters, section.filters, "renamed section")
  assert(panel.content.status.caption[1] == "bulk-imports.selection-updated")

  choose_section(section)
  assert(point.remove_section(section.index))
  click(panel.actions.apply)
  assert_same(untouched_filters, untouched.filters, "replacement section")
  assert(panel.content.status.caption[1] == "bulk-imports.selection-updated")
  log("BULK_IMPORT_TEST: stale renamed and removed sections are not edited")

  local original_permissions = player.permission_group
  local restricted = assert(game.permissions.create_group("Bulk import permission test"))
  restricted.set_allows_action(defines.input_action.set_logistic_filter_item, false)
  player.permission_group = restricted
  click(panel.actions.apply)
  assert_same(untouched_filters, untouched.filters, "permission-denied section")
  assert(panel.content.status.caption[1] == "bulk-imports.permission-denied")
  player.permission_group = original_permissions
  log("BULK_IMPORT_TEST: logistics edit permissions are respected")

  local function add_batch_section(group, item, quantity)
    local result = assert(point.add_section(group))
    result.set_slot(1, {
      value = { name = item, quality = "normal" },
      min = quantity,
      max = quantity * 2,
      minimum_delivery_count = 7,
      import_from = "fulgora",
      request_from = "planet"
    })
    return result
  end

  local batch_a = add_batch_section("Batch A", "iron-plate", 12)
  batch_a.set_slot(3, {
    value = { name = "iron-gear-wheel", quality = "rare" },
    min = 0,
    max = 40,
    import_from = "fulgora",
    request_from = "planet"
  })
  batch_a.active = false
  batch_a.multiplier = 3
  local batch_b = add_batch_section("Batch B", "copper-plate", 23)
  local batch_c = add_batch_section("Batch C", "steel-plate", 34)
  local batch_alias = assert(point.add_section(batch_a.group))
  local empty_section = assert(point.add_section())
  poll_editor()

  local function choose_mode(mode)
    handlers[defines.events.on_gui_checked_state_changed] {
      player_index = player.index,
      element = panel.content.selection_modes[mode]
    }
  end

  local function check_section(target, checked)
    local checkbox = checkbox_for(target)
    checkbox.state = checked
    handlers[defines.events.on_gui_checked_state_changed] {
      player_index = player.index,
      element = checkbox
    }
  end

  choose_section(batch_a)
  choose_mode("multiple")
  assert(not panel.content.section.visible and panel.content.multiple_sections.visible)
  assert(checkbox_for(batch_a).state and not checkbox_for(batch_b).state,
    "Multiple mode did not keep the initial dropdown selection")

  click(panel.content.multiple_sections.selection_actions.check_all)
  local manual_count = 0
  for _, candidate in ipairs(point.sections) do
    if candidate.is_manual then
      manual_count = manual_count + 1
    end
  end
  assert(#panel.content.multiple_sections.section_list.children == manual_count,
    "The list must contain all manual sections and no automatic sections")
  for _, checkbox in ipairs(panel.content.multiple_sections.section_list.children) do
    assert(checkbox.state, "All did not check a listed section")
  end
  click(panel.content.multiple_sections.selection_actions.check_none)
  for _, checkbox in ipairs(panel.content.multiple_sections.section_list.children) do
    assert(not checkbox.state, "None did not uncheck a listed section")
  end
  assert(not panel.actions.apply.enabled, "Apply must be disabled with no checked sections")
  local unchanged_a, unchanged_b = batch_a.filters, batch_b.filters
  click(panel.actions.apply)
  assert_same(unchanged_a, batch_a.filters, "no-selection batch A")
  assert_same(unchanged_b, batch_b.filters, "no-selection batch B")
  assert(panel.content.status.caption[1] == "bulk-imports.select-sections")

  check_section(batch_a, true)
  check_section(batch_b, true)
  check_section(batch_alias, true)
  check_section(empty_section, true)
  choose_mode("single")
  assert(panel.content.section.visible and not panel.content.multiple_sections.visible)
  choose_section(batch_c)
  apply("fulgora", "all")
  assert_same(unchanged_a, batch_a.filters, "Single mode batch A")
  assert_same(unchanged_b, batch_b.filters, "Single mode batch B")
  assert(batch_c.get_slot(1).request_from == "all", "Single mode did not apply to its dropdown section")
  choose_mode("multiple")
  assert(checkbox_for(batch_a).state and checkbox_for(batch_b).state
    and checkbox_for(batch_alias).state and not checkbox_for(batch_c).state,
    "Mode switching lost or replaced the checkbox selection")

  local batch_d = add_batch_section("Batch D", "battery", 45)
  poll_editor()
  assert(checkbox_for(batch_a).state and checkbox_for(batch_b).state,
    "Refresh lost checked sections")
  assert(not checkbox_for(batch_d).state, "Refresh unexpectedly selected a new section")
  log("BULK_IMPORT_TEST: mode switching, All/None, no-selection refusal, and retained selections")

  local preserved_a, preserved_b = without_imports(batch_a), without_imports(batch_b)
  local unchanged_c, unchanged_d = batch_c.filters, batch_d.filters
  apply("nauvis", "platforms")
  for _, target in ipairs({ batch_a, batch_b, batch_alias }) do
    for _, filter in pairs(target.filters) do
      if filter.value then
        assert(filter.import_from.name == "nauvis" and filter.request_from == "platforms",
          "A checked section did not receive the imports")
      end
    end
  end
  assert_same(preserved_a, without_imports(batch_a), "batch A preserved fields")
  assert_same(preserved_b, without_imports(batch_b), "batch B preserved fields")
  assert_same(unchanged_c, batch_c.filters, "unchecked batch C")
  assert_same(unchanged_d, batch_d.filters, "unchecked batch D")
  assert_same(untouched_filters, untouched.filters, "unchecked unnamed section")
  assert(batch_a.active == false and batch_a.multiplier == 3)
  assert(batch_a.get_slot(2).value == nil, "A batch edit filled an empty slot")
  local batch_result = panel.content.status.caption
  assert(batch_result[1] == "" and batch_result[4][1] == "bulk-imports.skipped-empty-sections",
    "Skipped empty sections were not reported")
  assert(tonumber(batch_result[2][2]) == 3 and tonumber(batch_result[2][3]) == 2,
    "A repeated shared group was counted more than once")
  log("BULK_IMPORT_TEST: checked-only batches, shared-group deduplication, and empty-section reporting")

  unchanged_a = batch_a.filters
  batch_b.group = "Renamed Batch B"
  unchanged_b = batch_b.filters
  panel.content.planet_row.planet_selector.elem_value = "fulgora"
  handlers[defines.events.on_gui_checked_state_changed] {
    player_index = player.index,
    element = panel.content.sources.all
  }
  assert_same(unchanged_a, batch_a.filters, "stale batch A")
  assert_same(unchanged_b, batch_b.filters, "stale batch B")
  assert(panel.content.status.caption[1] == "bulk-imports.selection-updated" and not panel.actions.apply.enabled,
    "A stale selected section did not clear the batch selection")
  log("BULK_IMPORT_TEST: stale sections reject the batch before any request changes")

  click(panel.content.multiple_sections.selection_actions.check_none)
  check_section(empty_section, true)
  click(panel.actions.apply)
  assert_same(unchanged_a, batch_a.filters, "empty-only batch A")
  assert_same(unchanged_b, batch_b.filters, "empty-only batch B")
  assert(panel.content.status.caption[1] == "bulk-imports.empty-sections")

  local small_amount_section = add_batch_section("Smaller stack amount tests", "engine-unit", 19)
  local amount_section = add_batch_section("Stack amount tests", "iron-plate", 28)
  amount_section.set_slot(3, {
    value = { name = "rocket-fuel", quality = "rare" },
    min = 15,
    max = 75,
    minimum_delivery_count = 3,
    import_from = "nauvis",
    request_from = "platforms"
  })
  amount_section.active = false
  amount_section.multiplier = 2
  local amount_alias = assert(second_point.add_section(amount_section.group))
  local long_section = assert(point.add_section("Long group " .. string.rep("name ", 35)))
  for index = 1, 20 do
    assert(point.add_section("Layout test group " .. index))
  end
  poll_editor()
  assert(panel.content.multiple_sections.section_list.style.maximal_height <= 168)
  assert(checkbox_for(long_section).style.maximal_width
    < panel.content.multiple_sections.section_list.style.maximal_width,
    "A long section name can grow beyond the narrower list")

  local function edit_option(name, checked)
    local element = panel.content[name]
    element.state = checked
    handlers[defines.events.on_gui_checked_state_changed] { player_index = player.index, element = element }
  end

  local function choose_quality(name, comparator_index)
    panel.content.quality_controls.comparator.selected_index = comparator_index or 1
    handlers[defines.events.on_gui_selection_state_changed] {
      player_index = player.index,
      element = panel.content.quality_controls.comparator
    }
    if name then
      click(panel.content.quality_controls.qualities["quality_" .. name])
    end
  end

  local function enter_text(element, text)
    element.text = tostring(text)
    handlers[defines.events.on_gui_text_changed] {
      player_index = player.index,
      element = element,
      text = element.text
    }
  end

  local function enter_amount(name, text)
    enter_text(panel.content.amount_controls[name].multiplier, text)
  end

  local function enter_payload(text)
    enter_text(panel.content.payload_controls.quantity_row.multiplier, text)
  end

  local function change_units(element, unit_index)
    element.selected_index = unit_index
    handlers[defines.events.on_gui_selection_state_changed] { player_index = player.index, element = element }
  end

  local function move_slider(element, position)
    element.slider_value = position
    handlers[defines.events.on_gui_value_changed] { player_index = player.index, element = element }
  end

  local function drag_amount(name, position)
    move_slider(panel.content.amount_controls[name].amount_slider, position)
  end

  local function assert_amounts(target, requested, maximum, unit)
    for _, filter in pairs(target.filters) do
      if filter.value then
        local factor = unit == "items" and 1 or prototypes.item[filter.value.name].stack_size
        assert((filter.min or 0) == requested * factor, "Requested did not use the selected unit")
        assert(filter.max == (maximum and maximum * factor or nil),
          "Trash above did not use the selected unit or clear an infinite maximum")
      end
    end
  end

  local function assert_payload(target, value, unit)
    for _, filter in pairs(target.filters) do
      if filter.value then
        local factor = unit == "stacks" and prototypes.item[filter.value.name].stack_size or 1
        assert(filter.minimum_delivery_count == value * factor, "Minimum payload did not use the selected unit")
      end
    end
  end

  local function exercise_quality_range_policies()
    choose_mode("single")
    choose_section(amount_section)
    edit_option("edit_filters", false)
    edit_option("edit_amounts", false)
    edit_option("edit_quality", true)
    local original = amount_section.filters
    local metadata = without_requested_quality(amount_section)
    assert(get_user_setting(player, "quality-range-behavior") == "set-to-zero")
    choose_quality(nil, #panel.content.quality_controls.comparator.items)
    click(panel.actions.apply)
    assert_quality(amount_section, nil, nil)
    for _, filter in pairs(amount_section.filters) do
      if filter.value then
        assert((filter.min or 0) == 0, "Default quality policy did not zero Requested")
      end
    end
    assert_same(metadata, without_requested_quality(amount_section),
      "Automatic zeroing changed Trash above or unrelated request fields")
    assert(panel.content.status.caption[4][1] == "bulk-imports.quality-zeroed",
      "Automatic zeroing did not explain its effect")
    click(panel.actions.undo)
    assert_same(original, amount_section.filters, "Undo of default Set to 0 quality behavior")

    local range = assert(point.add_section("Quality policy effective amount"))
    range.set_slot(1, {
      value = { name = "iron-plate", quality = "normal", comparator = ">" },
      min = 0,
      max = 10
    })
    local original_range = range.filters
    poll_editor()
    choose_section(range)
    edit_option("edit_quality", false)
    edit_option("edit_amounts", true)
    enter_amount("requested", 2147483647)
    enter_amount("trash_above", "inf.")
    click(panel.actions.apply)
    assert_amounts(range, 0, nil)
    assert_quality(range, "normal", ">")
    click(panel.actions.undo)
    assert_same(original_range, range.filters, "Effective zero amount must be validated before item-count limits")
    enter_amount("trash_above", 2147483647)
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.amount-overflow")
    assert_same(original_range, range.filters, "Set to 0 must not bypass the finite maximum count limit")

    set_user_setting(player, "quality-range-behavior", "prevent")
    choose_section(amount_section)
    edit_option("edit_amounts", false)
    edit_option("edit_quality", true)
    choose_quality(nil, #panel.content.quality_controls.comparator.items)
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.amount-quality-range")
    assert_same(original, amount_section.filters, "Prevent quality behavior modified requests")
    set_user_setting(player, "quality-range-behavior", "set-to-zero")
    assert(not panel.content.status.visible, "Changing quality policy retained the obsolete Prevent error")
    assert_same(original, amount_section.filters, "Changing quality policy edited requests before Apply")
    click(panel.actions.apply)
    assert_quality(amount_section, nil, nil)
    for _, filter in pairs(amount_section.filters) do
      if filter.value then
        assert((filter.min or 0) == 0)
      end
    end
    click(panel.actions.undo)
    assert_same(original, amount_section.filters, "Undo after changing quality policy live")
    set_user_setting(player, "quality-range-behavior", "prevent")
    edit_option("edit_quality", false)
    edit_option("edit_filters", true)
    enter_amount("requested", 1)
    enter_amount("trash_above", "inf.")
    choose_quality("normal")
    log("BULK_IMPORT_TEST: default Set to 0, preserved maxima, effective count limits, Prevent, and quality-policy Undo")
  end
  exercise_quality_range_policies()

  choose_mode("single")
  choose_section(amount_section)
  local amount_metadata = without_amounts(amount_section)
  local before_amounts = amount_section.filters
  edit_option("edit_filters", false)
  assert(not panel.content.planet_row.visible and not panel.content.sources.visible,
    "Edit filters did not hide its controls")
  assert(not panel.content.amount_controls.visible and not panel.actions.apply.enabled)
  click(panel.actions.apply)
  assert_same(before_amounts, amount_section.filters, "disabled edit categories")
  assert(panel.content.status.caption[1] == "bulk-imports.select-edits")

  edit_option("edit_amounts", true)
  assert(panel.content.amount_controls.visible and panel.actions.apply.enabled)
  click(panel.actions.apply)
  assert_amounts(amount_section, 1, nil)
  enter_amount("requested", 10)
  enter_amount("trash_above", 25)
  click(panel.actions.apply)
  assert_amounts(amount_section, 10, 25)
  assert_same(amount_metadata, without_amounts(amount_section), "amount-only metadata and import settings")
  assert_same(amount_section.filters, amount_alias.filters, "amount changes in shared groups")
  assert(amount_section.active == false and amount_section.multiplier == 2)
  assert(amount_section.get_slot(2).value == nil, "An amount edit filled an empty slot")
  assert(prototypes.item["iron-plate"].stack_size ~= prototypes.item["rocket-fuel"].stack_size,
    "The amount fixture must exercise different stack sizes")
  log("BULK_IMPORT_TEST: amount-only edits use each item's stack size and preserve filters and metadata")

  enter_amount("requested", 100)
  assert(tonumber(panel.content.amount_controls.trash_above.multiplier.text) == 100,
    "Raising Requested did not raise a finite maximum")
  local requested_slider = panel.content.amount_controls.requested.amount_slider
  local maximum_slider = panel.content.amount_controls.trash_above.amount_slider
  assert(requested_slider.get_slider_minimum() == maximum_slider.get_slider_minimum()
    and requested_slider.get_slider_maximum() == maximum_slider.get_slider_maximum()
    and requested_slider.style.maximal_width == maximum_slider.style.maximal_width,
    "The sliders must have matching tick positions and widths")
  drag_amount("requested", requested_slider.get_slider_maximum() - 1)
  assert(tonumber(panel.content.amount_controls.requested.multiplier.text) == 750
    and tonumber(panel.content.amount_controls.trash_above.multiplier.text) == 750,
    "The penultimate Requested stop must stay at 750x without forcing infinity")
  drag_amount("requested", requested_slider.get_slider_maximum())
  assert(tonumber(panel.content.amount_controls.requested.multiplier.text) == 1000
    and panel.content.amount_controls.trash_above.multiplier.text == "inf."
    and requested_slider.slider_value == maximum_slider.slider_value,
    "The aligned endpoints must mean 1000x requested and unlimited Trash above")
  click(panel.actions.apply)
  assert_amounts(amount_section, 1000, nil)

  enter_amount("trash_above", 1000)
  assert(tonumber(panel.content.amount_controls.trash_above.multiplier.text) == 1000,
    "A typed finite maximum was replaced by infinity")
  click(panel.actions.apply)
  assert_amounts(amount_section, 1000, 1000)
  drag_amount("trash_above", maximum_slider.get_slider_maximum())
  click(panel.actions.apply)
  assert_amounts(amount_section, 1000, nil)

  drag_amount("trash_above", 0)
  assert(tonumber(panel.content.amount_controls.requested.multiplier.text) == 0,
    "Lowering the maximum did not lower Requested")
  click(panel.actions.apply)
  assert_amounts(amount_section, 0, 0)
  enter_amount("requested", 7)
  enter_amount("trash_above", 250)
  click(panel.actions.apply)
  assert_amounts(amount_section, 7, 250)
  assert(tonumber(panel.content.amount_controls.requested.multiplier.text) == 7,
    "Custom input was replaced by the nearest slider preset")
  log("BULK_IMPORT_TEST: linked slider endpoints, zero amounts, infinity, and custom whole multipliers")

  before_amounts = amount_section.filters
  for _, invalid in ipairs({ "", "1.5", "2147483648" }) do
    enter_amount("requested", invalid)
    assert(not panel.actions.apply.enabled, "Invalid multiplier input left Apply enabled")
    click(panel.actions.apply)
    assert_same(before_amounts, amount_section.filters, "invalid multiplier input")
    assert(panel.content.status.caption[1] == "bulk-imports.invalid-requested")
  end
  local preserved_quantities = without_imports(amount_section)
  edit_option("edit_amounts", false)
  edit_option("edit_filters", true)
  assert(panel.content.planet_row.visible and not panel.content.amount_controls.visible)
  apply("fulgora", "all")
  assert_same(preserved_quantities, without_imports(amount_section), "filter-only quantities")
  assert(amount_section.get_slot(1).request_from == "all",
    "Invalid hidden amount input blocked filter-only edits")

  edit_option("edit_filters", false)
  edit_option("edit_amounts", true)
  enter_amount("requested", 3)
  enter_amount("trash_above", "2.5")
  assert(not panel.actions.apply.enabled)
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.invalid-maximum")
  assert_same(preserved_quantities, without_imports(amount_section), "invalid maximum")
  log("BULK_IMPORT_TEST: invalid amounts are refused, but hidden amount fields do not affect filter edits")

  choose_mode("multiple")
  click(panel.content.multiple_sections.selection_actions.check_none)
  check_section(small_amount_section, true)
  check_section(amount_section, true)
  local before_small = small_amount_section.filters
  before_amounts = amount_section.filters
  local overflow_multiplier = math.floor(2147483647 / prototypes.item["iron-plate"].stack_size) + 1
  assert(overflow_multiplier * prototypes.item["engine-unit"].stack_size <= 2147483647,
    "The first section must pass count validation to test batch preflight")
  enter_amount("trash_above", overflow_multiplier)
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.amount-overflow")
  assert_same(before_small, small_amount_section.filters, "overflow batch's earlier section")
  assert_same(before_amounts, amount_section.filters, "overflow batch's later section")

  enter_amount("requested", 10)
  enter_amount("trash_above", 25)
  edit_option("edit_filters", true)
  apply("nauvis", "platforms")
  assert_amounts(small_amount_section, 10, 25)
  assert_amounts(amount_section, 10, 25)
  assert(small_amount_section.get_slot(1).request_from == "platforms"
    and amount_section.get_slot(1).import_from.name == "nauvis",
    "Combined filter and amount edits did not update both categories")
  assert_same(unchanged_c, batch_c.filters, "unchecked section during amount batch edits")
  log("BULK_IMPORT_TEST: count overflow rejects the entire batch; combined edits target checked sections")

  local quality_range = assert(point.add_section("Quality range amount tests"))
  quality_range.set_slot(1, {
    value = { name = "steel-plate", quality = "normal", comparator = ">" },
    min = 0,
    max = 100
  })
  poll_editor()
  check_section(quality_range, true)
  before_small = small_amount_section.filters
  local before_range = quality_range.filters
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.amount-quality-range")
  assert_same(before_small, small_amount_section.filters, "quality-range batch's earlier section")
  assert_same(before_range, quality_range.filters, "quality-range condition")
  enter_amount("requested", 0)
  click(panel.actions.apply)
  assert(quality_range.get_slot(1).value.comparator == ">", "The quality range was changed")
  assert_amounts(quality_range, 0, 25)
  log("BULK_IMPORT_TEST: positive requests preserve quality-range conditions by refusing incompatible batches")

  choose_mode("single")
  choose_section(amount_section)
  enter_amount("requested", 2000)
  enter_amount("trash_above", 5000)
  assert(panel.content.amount_controls.requested.amount_slider.slider_value
    == panel.content.amount_controls.requested.amount_slider.get_slider_maximum())
  assert(panel.content.amount_controls.trash_above.amount_slider.slider_value
    == panel.content.amount_controls.trash_above.amount_slider.get_slider_maximum())
  click(panel.actions.apply)
  assert_amounts(amount_section, 2000, 5000)
  assert(tonumber(panel.content.amount_controls.requested.multiplier.text) == 2000
    and tonumber(panel.content.amount_controls.trash_above.multiplier.text) == 5000,
    "Visually capped sliders changed large typed multipliers")

  local largest_stack = 0
  for _, filter in pairs(amount_section.filters) do
    if filter.value then
      largest_stack = math.max(largest_stack, prototypes.item[filter.value.name].stack_size)
    end
  end
  local signed_stack_limit = math.floor(2147483647 / largest_stack)
  enter_amount("requested", signed_stack_limit)
  enter_amount("trash_above", signed_stack_limit)
  click(panel.actions.apply)
  assert_amounts(amount_section, signed_stack_limit, signed_stack_limit)
  local at_signed_limit = amount_section.filters
  enter_amount("requested", signed_stack_limit + 1)
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.amount-overflow")
  assert_same(at_signed_limit, amount_section.filters, "requested signed-count overflow")
  enter_amount("requested", 2000)
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.amount-overflow")
  assert_same(at_signed_limit, amount_section.filters, "maximum signed-count overflow")

  local single_item_limit = assert(point.add_section("Single item signed-count boundary"))
  assert(prototypes.item.spidertron.stack_size == 1, "The boundary fixture needs an item with stack size 1")
  single_item_limit.set_slot(1, {
    value = { name = "spidertron", quality = "normal" },
    min = 1,
    max = 2
  })
  poll_editor()
  choose_section(single_item_limit)
  enter_amount("requested", 2147483647)
  enter_amount("trash_above", 2147483647)
  click(panel.actions.apply)
  assert_amounts(single_item_limit, 2147483647, 2147483647)
  enter_amount("trash_above", "2147483648")
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.invalid-maximum")
  assert_amounts(single_item_limit, 2147483647, 2147483647)
  log("BULK_IMPORT_TEST: large typed multipliers, capped sliders, and exact signed 32-bit item-count boundaries")

  local quality_first = add_batch_section("Quality first group", "iron-plate", 19)
  quality_first.set_slot(3, {
    value = { name = "engine-unit", quality = "rare" },
    min = 0,
    max = 40,
    import_from = "nauvis",
    request_from = "platforms"
  })
  local quality_second = add_batch_section("Quality second group", "iron-plate", 23)
  local quality_shared = assert(second_point.add_section(quality_first.group))
  poll_editor()
  choose_mode("single")
  choose_section(quality_first)
  assert(not panel.content.edit_quality.state and not panel.content.quality_controls.visible,
    "Quality editing must start off without changing existing defaults")
  edit_option("edit_filters", false)
  edit_option("edit_amounts", false)
  edit_option("edit_quality", true)
  assert(panel.content.quality_controls.visible and panel.actions.apply.enabled)
  choose_quality("rare")
  local toggled_qualities = 0
  for _, button in ipairs(panel.content.quality_controls.qualities.children) do
    assert(button.style.minimal_width == button_styles.tool_button.minimal_width
      and button.style.maximal_width == button_styles.tool_button.minimal_width
      and button.style.minimal_height == button_styles.tool_button.height
      and button.style.maximal_height == button_styles.tool_button.height,
      "Quality buttons must match the native compact tool-button dimensions")
    if button.toggled then
      toggled_qualities = toggled_qualities + 1
    end
    assert(panel.content.quality_controls.comparator.style.minimal_height == button_styles.dropdown.minimal_height
      and panel.content.quality_controls.comparator.style.maximal_height == button_styles.dropdown.minimal_height,
      "The quality comparison dropdown must match the native dropdown height")
  end
  assert(toggled_qualities == 1, "The native quality buttons must act as a single selection")
  local quality_before = quality_first.filters
  local quality_metadata = without_quality(quality_first)
  local quality_second_before = quality_second.filters
  click(panel.actions.apply)
  assert_quality(quality_first, "rare", "=")
  assert_same(quality_metadata, without_quality(quality_first), "quality-only amounts and import metadata")
  assert_same(quality_first.filters, quality_shared.filters, "quality edits in shared groups")
  assert_same(quality_second_before, quality_second.filters, "unselected quality section")

  choose_quality("rare", 4)
  local after_quality_apply = quality_first.filters
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.amount-quality-range")
  assert_same(after_quality_apply, quality_first.filters, "quality ranges must not silently clear positive requests")
  local any_quality_index = #panel.content.quality_controls.comparator.items
  choose_quality(nil, any_quality_index)
  for _, button in ipairs(panel.content.quality_controls.qualities.children) do
    assert(not button.enabled, "Any quality must disable individual quality selection")
  end
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.amount-quality-range")
  assert_same(after_quality_apply, quality_first.filters, "Any quality must not clear positive requests")
  click(panel.actions.undo)
  assert_same(quality_before, quality_first.filters, "quality Undo after a refused range edit")
  log("BULK_IMPORT_TEST: quality-only edits preserve amounts/imports, propagate shared groups, and support Undo")

  edit_option("edit_quality", false)
  assert(not panel.content.quality_controls.visible)
  choose_quality("legendary")
  edit_option("edit_amounts", true)
  enter_amount("requested", 2)
  enter_amount("trash_above", 5)
  local disabled_quality_metadata = without_amounts(quality_first)
  click(panel.actions.apply)
  assert_same(disabled_quality_metadata, without_amounts(quality_first),
    "Disabled quality controls changed the original quality condition")
  click(panel.actions.undo)
  assert_same(quality_before, quality_first.filters)

  edit_option("edit_quality", true)
  choose_quality("rare", 4)
  enter_amount("requested", 0)
  enter_amount("trash_above", 25)
  click(panel.actions.apply)
  local range_comparator = panel.content.quality_controls.comparator.get_item(4)
  assert_quality(quality_first, "rare", range_comparator)
  assert_amounts(quality_first, 0, 25)
  local before_any_quality = quality_first.filters
  local any_quality_metadata = without_quality(quality_first)
  edit_option("edit_amounts", false)
  choose_quality(nil, any_quality_index)
  player.force.lock_quality("rare")
  click(panel.actions.apply)
  assert_quality(quality_first, nil, nil)
  assert_same(any_quality_metadata, without_quality(quality_first), "Any quality preserves amounts and imports")
  assert_same(quality_first.filters, quality_shared.filters, "Any quality in shared groups")
  player.force.unlock_quality("rare")
  click(panel.actions.undo)
  assert_same(before_any_quality, quality_first.filters, "Any quality Undo")
  choose_quality(nil, 4)
  assert(panel.content.quality_controls.qualities.quality_rare.enabled
    and panel.content.quality_controls.qualities.quality_rare.toggled,
    "Leaving Any quality did not restore the previous quality selection")
  edit_option("edit_amounts", true)
  log("BULK_IMPORT_TEST: Any quality clears restrictions, preserves values, rejects positive requests, and supports Undo")
  local before_combined_quality = quality_first.filters
  choose_mode("multiple")
  click(panel.content.multiple_sections.selection_actions.check_none)
  check_section(quality_first, true)
  check_section(quality_second, true)
  choose_quality("epic")
  enter_amount("requested", 3)
  enter_amount("trash_above", 7)
  edit_option("edit_filters", true)
  apply("nauvis", "all")
  assert_quality(quality_first, "epic", "=")
  assert_quality(quality_second, "epic", "=")
  assert_amounts(quality_first, 3, 7)
  assert_amounts(quality_second, 3, 7)
  assert(quality_first.get_slot(1).import_from.name == "nauvis"
    and quality_second.get_slot(1).request_from == "all")
  click(panel.actions.undo)
  assert_same(before_combined_quality, quality_first.filters, "combined quality/amount/filter Undo")
  assert_same(quality_second_before, quality_second.filters, "combined batch's second section Undo")
  log("BULK_IMPORT_TEST: explicit zero-request ranges and combined exact-quality/amount/filter edits")

  local quality_collision = assert(point.add_section("Quality collision group"))
  quality_collision.set_slot(1, {
    value = { name = "iron-plate", quality = "normal" },
    min = 1,
    max = 10
  })
  quality_collision.set_slot(3, {
    value = { name = "iron-plate", quality = "rare" },
    min = 2,
    max = 20
  })
  poll_editor()
  click(panel.content.multiple_sections.selection_actions.check_none)
  check_section(quality_first, true)
  check_section(quality_collision, true)
  edit_option("edit_filters", false)
  edit_option("edit_amounts", false)
  choose_quality("legendary")
  local collision_first_before = quality_first.filters
  local collision_before = quality_collision.filters
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.quality-duplicate")
  assert_same(collision_first_before, quality_first.filters, "quality collision batch's earlier section")
  assert_same(collision_before, quality_collision.filters, "quality collision batch's duplicate item")
  assert(not panel.actions.undo.visible, "A refused quality collision created new Undo history")
  check_section(quality_collision, false)
  click(panel.actions.apply)
  assert_quality(quality_first, "legendary", "=")
  log("BULK_IMPORT_TEST: quality collisions refuse the whole batch without losing filters or quantities")

  player.force.lock_quality("epic")
  poll_editor()
  local locked_quality = panel.content.quality_controls.qualities.quality_epic
  assert(not locked_quality.enabled, "A research-locked quality remained selectable")
  click(panel.actions.apply)
  click(locked_quality)
  assert(panel.content.status.caption[1] == "bulk-imports.quality-unavailable")
  handlers[defines.events.on_tick] { tick = game.tick + 300 }
  assert(panel.content.status.visible
    and panel.content.status.caption[1] == "bulk-imports.quality-unavailable",
    "An old confirmation timer hid a newer quality error")
  player.force.unlock_quality("epic")
  player.force.lock_quality("legendary")
  click(panel.actions.apply)
  assert(panel.content.status.caption[1] == "bulk-imports.quality-unavailable")
  assert_quality(quality_first, "legendary", "=")
  player.force.unlock_quality("legendary")
  poll_editor()
  choose_quality("rare")
  click(panel.actions.apply)
  handlers[defines.events.on_tick] { tick = game.tick + 299 }
  assert(panel.content.status.visible, "Apply confirmation hid before five seconds")
  handlers[defines.events.on_tick] { tick = game.tick + 300 }
  assert(not panel.content.status.visible and panel.actions.undo.visible,
    "Apply confirmation did not hide after five seconds, or hid Undo too")
  click(panel.actions.undo)
  assert_quality(quality_first, "legendary", "=")
  handlers[defines.events.on_tick] { tick = game.tick + 299 }
  assert(panel.content.status.visible, "Undo confirmation hid before five seconds")
  handlers[defines.events.on_tick] { tick = game.tick + 300 }
  assert(not panel.content.status.visible, "Undo confirmation did not hide after five seconds")
  log("BULK_IMPORT_TEST: quality unlock safeguards and exact five-second Apply/Undo confirmations")
  edit_option("edit_quality", false)
  edit_option("edit_amounts", true)
  edit_option("edit_filters", true)

  local undo_first = add_batch_section("Undo first group", "iron-plate", 17)
  local undo_second = add_batch_section("Undo second group", "copper-plate", 23)
  local undo_repeat = assert(point.add_section(undo_first.group))
  local undo_other_alias = assert(second_point.add_section(undo_second.group))
  poll_editor()
  choose_mode("single")
  choose_section(undo_first)
  local manual_request = undo_first.get_slot(1)
  manual_request.min = 19
  manual_request.max = 81
  undo_first.set_slot(1, manual_request)
  local before_first_apply = undo_first.filters
  enter_amount("requested", 10)
  enter_amount("trash_above", 25)
  apply("nauvis", "all")
  local after_first_apply = undo_first.filters
  assert(panel.actions.undo.visible, "Apply did not expose Undo")
  click(panel.actions.undo)
  assert_same(before_first_apply, undo_first.filters, "exact values just before Apply")
  assert_same(before_first_apply, undo_repeat.filters, "shared group Undo")
  assert(not panel.actions.undo.visible, "Undo was not consumed")

  apply("nauvis", "all")
  enter_amount("requested", 3)
  enter_amount("trash_above", 7)
  apply("fulgora", "platforms")
  enter_amount("requested", "invalid")
  click(panel.actions.apply)
  assert(panel.actions.undo.visible, "A failed Apply discarded the prior Undo")
  choose_mode("multiple")
  click(panel.content.multiple_sections.selection_actions.check_none)
  click(panel.actions.undo)
  assert_same(after_first_apply, undo_first.filters, "Undo replaces, rather than stacks, Apply history")
  assert(not panel.actions.undo.visible)
  click(panel.actions.undo)
  assert(panel.content.status.caption[1] == "bulk-imports.nothing-to-undo")
  assert_same(after_first_apply, undo_first.filters, "Undo has no second history entry")
  log("BULK_IMPORT_TEST: Undo captures pre-Apply values, keeps one level, survives failed Apply, and ignores form selection")

  check_section(undo_first, true)
  check_section(undo_repeat, true)
  check_section(undo_second, true)
  enter_amount("requested", 5)
  enter_amount("trash_above", 10)
  local before_undo_batch_first = undo_first.filters
  local before_undo_batch_second = undo_second.filters
  apply("fulgora", "planet")
  local after_undo_batch_first = undo_first.filters
  local after_undo_batch_second = undo_second.filters
  local undo_permissions = player.permission_group
  player.permission_group = restricted
  click(panel.actions.undo)
  assert(panel.content.status.caption[1] == "bulk-imports.permission-denied")
  assert_same(after_undo_batch_first, undo_first.filters, "permission-denied Undo")
  player.permission_group = undo_permissions

  local later_edit = undo_other_alias.get_slot(1)
  later_edit.min = later_edit.min + 1
  undo_other_alias.set_slot(1, later_edit)
  local later_filters = undo_second.filters
  click(panel.actions.undo)
  assert(panel.content.status.caption[1] == "bulk-imports.undo-conflict")
  assert_same(after_undo_batch_first, undo_first.filters, "conflict in a later section must refuse the whole Undo")
  assert_same(later_filters, undo_second.filters, "Undo must preserve later edits through a shared group")
  undo_other_alias.filters = after_undo_batch_second
  click(panel.actions.undo)
  assert_same(before_undo_batch_first, undo_first.filters, "first batch section restored")
  assert_same(before_undo_batch_first, undo_repeat.filters, "duplicate shared group restored once")
  assert_same(before_undo_batch_second, undo_second.filters, "second batch section restored")
  assert_same(before_undo_batch_second, undo_other_alias.filters, "Undo propagated to another platform")
  log("BULK_IMPORT_TEST: batch Undo respects permissions and refuses later shared-group edits without partial restoration")

  apply("fulgora", "planet")
  after_undo_batch_first = undo_first.filters
  assert(point.remove_section(undo_second.index))
  click(panel.actions.undo)
  assert(panel.content.status.caption[1] == "bulk-imports.undo-conflict")
  assert_same(after_undo_batch_first, undo_first.filters, "deleted section must refuse the whole Undo")
  click(panel.titlebar.close_panel)
  assert(player.opened == hub, "Closing the editor closed the hub")
  assert_same(after_undo_batch_first, undo_first.filters, "Closing the editor must not apply Undo")
  player.opened = nil
  handlers[defines.events.on_gui_closed] {
    player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
  }
  player.opened = hub
  handlers[defines.events.on_gui_opened] {
    player_index = player.index,
    entity = hub,
    gui_type = defines.gui_type.entity
  }
  assert(not get_editor(player), "Reopening after Undo must still wait for the launcher")
  launch_editor()
  assert(not panel.actions.undo.visible, "Closing the editor did not discard Undo")
  assert_same(after_undo_batch_first, undo_first.filters, "Reopening must not restore discarded Undo")
  log("BULK_IMPORT_TEST: removed sections block Undo; closing the window discards its snapshot")

  local function exercise_quantity_units_and_payload()
    local quantities = assert(point.add_section("Item and stack quantity units"))
    quantities.set_slot(1, { value = { name = "iron-plate", quality = "normal" }, min = 5, max = 10 })
    quantities.set_slot(3, { value = { name = "engine-unit", quality = "rare" }, min = 7, max = 12 })
    poll_editor()
    choose_mode("single")
    choose_section(quantities)
    edit_option("edit_filters", false)
    edit_option("edit_amounts", true)
    edit_option("edit_quality", false)
    local unit_metadata = without_amounts(quantities)
    assert(panel.content.amount_controls.requested_header.units.selected_index == 2
      and panel.content.amount_controls.trash_above_header.units == nil)
    change_units(panel.content.amount_controls.requested_header.units, 1)
    assert(panel.content.amount_controls.trash_above.unit_label.caption == "")
    enter_amount("requested", 10)
    enter_amount("trash_above", 25)
    click(panel.actions.apply)
    assert_amounts(quantities, 10, 25, "items")
    assert_same(unit_metadata, without_amounts(quantities), "item-count edits preserve metadata")
    change_units(panel.content.amount_controls.requested_header.units, 2)
    assert(panel.content.amount_controls.requested_header.units.selected_index == 2
      and panel.content.amount_controls.requested.multiplier.text == "10"
      and panel.content.amount_controls.trash_above.multiplier.text == "25",
      "Linked unit changes converted the entered numbers")
    click(panel.actions.apply)
    assert_amounts(quantities, 10, 25, "stacks")
    change_units(panel.content.amount_controls.requested_header.units, 1)
    drag_amount("requested", panel.content.amount_controls.requested.amount_slider.get_slider_maximum())
    click(panel.actions.apply)
    assert_amounts(quantities, 1000, nil, "items")
    enter_amount("requested", 2147483647)
    enter_amount("trash_above", 2147483647)
    click(panel.actions.apply)
    assert_amounts(quantities, 2147483647, 2147483647, "items")
    local item_counts = quantities.filters
    change_units(panel.content.amount_controls.requested_header.units, 2)
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.amount-overflow")
    assert_same(item_counts, quantities.filters, "stack-unit overflow must not convert existing item counts")
    click(panel.actions.undo)
    assert_amounts(quantities, 1000, nil, "items")
    enter_amount("requested", 1)
    enter_amount("trash_above", "inf.")
    panel.content.amount_controls.requested_header.units.selected_index = 0
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.select-amount-units")
    change_units(panel.content.amount_controls.requested_header.units, 2)
    log("BULK_IMPORT_TEST: linked Items/Stacks units preserve numbers, enforce per-item limits, and support Undo")

    local payload_section = assert(point.add_section("Minimum payload tests"))
    payload_section.set_slot(1, {
      value = { name = "iron-plate", quality = "normal" },
      min = 5,
      max = 10,
      import_from = "fulgora",
      request_from = "planet"
    })
    payload_section.set_slot(3, {
      value = { name = "engine-unit", quality = "rare" },
      min = 7,
      max = 12,
      minimum_delivery_count = 3,
      import_from = "nauvis",
      request_from = "platforms"
    })
    local shared_payload = assert(second_point.add_section(payload_section.group))
    local before_payload = payload_section.filters
    local payload_metadata = without_payload(payload_section)
    poll_editor()
    choose_section(payload_section)
    edit_option("edit_amounts", false)
    assert(not panel.content.edit_payload.state and not panel.content.payload_controls.visible)
    edit_option("edit_payload", true)
    assert(panel.content.payload_controls.visible and panel.actions.apply.enabled
      and panel.content.payload_controls.quantity_row.multiplier.text == "1"
      and panel.content.payload_controls.payload_header.units.selected_index == 1)
    click(panel.actions.apply)
    assert_payload(payload_section, 1, "items")
    assert_same(payload_metadata, without_payload(payload_section), "payload-only metadata")
    assert_same(payload_section.filters, shared_payload.filters, "shared minimum payload")
    click(panel.actions.undo)
    assert_same(before_payload, payload_section.filters, "restoring automatic and custom minimum payloads")
    assert(payload_section.get_slot(1).minimum_delivery_count == nil
      and payload_section.get_slot(3).minimum_delivery_count == 3)

    change_units(panel.content.payload_controls.payload_header.units, 2)
    assert(panel.content.payload_controls.quantity_row.multiplier.text == "1",
      "Payload units converted the entered number")
    local payload_slider = panel.content.payload_controls.quantity_row.amount_slider
    for index, value in ipairs({ 1, 2, 3, 4, 5, 10, 25, 50, 100, 1000 }) do
      move_slider(payload_slider, index - 1)
      click(panel.actions.apply)
      assert_payload(payload_section, value, "stacks")
    end
    enter_payload(7)
    click(panel.actions.apply)
    assert_payload(payload_section, 7, "stacks")
    assert(panel.content.payload_controls.quantity_row.multiplier.text == "7")
    change_units(panel.content.payload_controls.payload_header.units, 1)
    enter_payload(4294967295)
    click(panel.actions.apply)
    assert_payload(payload_section, 4294967295, "items")
    assert_same(payload_metadata, without_payload(payload_section),
      "Unsigned payloads must be independent of Requested, Trash above, quality, and imports")
    local unsigned_payload = payload_section.filters
    for _, invalid in ipairs({ "0", "-1", "1.5", "inf.", "4294967296" }) do
      enter_payload(invalid)
      assert(not panel.actions.apply.enabled)
      click(panel.actions.apply)
      assert(panel.content.status.caption[1] == "bulk-imports.invalid-payload")
      assert_same(unsigned_payload, payload_section.filters, "invalid unsigned payload")
    end
    log("BULK_IMPORT_TEST: single-item and stack payload presets, custom input, unsigned maximum, and independent counts")

    change_units(panel.content.payload_controls.payload_header.units, 2)
    local payload_limit = math.floor(4294967295 / prototypes.item["iron-plate"].stack_size)
    enter_payload(payload_limit)
    click(panel.actions.apply)
    assert_payload(payload_section, payload_limit, "stacks")
    choose_mode("multiple")
    click(panel.content.multiple_sections.selection_actions.check_none)
    check_section(small_amount_section, true)
    check_section(payload_section, true)
    local small_before_payload = small_amount_section.filters
    local payload_before_batch = payload_section.filters
    enter_payload(payload_limit + 1)
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.payload-overflow")
    assert_same(small_before_payload, small_amount_section.filters, "payload overflow batch's earlier section")
    assert_same(payload_before_batch, payload_section.filters, "payload overflow batch's later section")
    enter_payload(2)
    click(panel.actions.apply)
    assert_payload(small_amount_section, 2, "stacks")
    assert_payload(payload_section, 2, "stacks")
    click(panel.actions.undo)
    assert_same(small_before_payload, small_amount_section.filters, "payload batch Undo earlier section")
    assert_same(payload_before_batch, payload_section.filters, "payload batch Undo later section")
    choose_mode("single")
    choose_section(payload_section)
    edit_option("edit_payload", false)
    enter_payload("ignored invalid value")
    edit_option("edit_amounts", true)
    change_units(panel.content.amount_controls.requested_header.units, 1)
    enter_amount("requested", 1)
    enter_amount("trash_above", 2)
    local hidden_payload = without_amounts(payload_section)
    click(panel.actions.apply)
    assert_amounts(payload_section, 1, 2, "items")
    assert_same(hidden_payload, without_amounts(payload_section), "disabled minimum payload controls")
    click(panel.actions.undo)
    change_units(panel.content.amount_controls.requested_header.units, 2)
    enter_amount("requested", 1)
    enter_amount("trash_above", "inf.")
    edit_option("edit_filters", true)
    log("BULK_IMPORT_TEST: unsigned stack overflow rejects a whole batch; payload Undo and disabled-field isolation")
  end
  exercise_quantity_units_and_payload()

  local function exercise_automatic_updates()
    local leading = assert(point.add_section("Automatic leading section"))
    local selected = assert(point.add_section("Automatic selected section"))
    selected.set_slot(1, {
      value = { name = "iron-plate", quality = "normal" }, min = 7, max = 21
    })
    local other = assert(point.add_section("Automatic other section"))
    poll_editor()
    choose_mode("single")
    choose_section(selected)
    edit_option("edit_filters", false)
    edit_option("edit_amounts", true)
    edit_option("edit_quality", false)
    edit_option("edit_payload", false)
    change_units(panel.content.amount_controls.requested_header.units, 1)
    enter_amount("requested", 2)
    enter_amount("trash_above", 5)
    local original = selected.filters
    click(panel.actions.apply)
    local applied = selected.filters
    local deadline = remote.call(TEST_INTERFACE, "get_deadline", player.index)
    local old_selector = panel.content.section
    local old_count = #panel.content.multiple_sections.section_list.children
    local added = assert(point.add_section("Automatic empty addition"))
    handlers[defines.events.on_tick] { tick = game.tick + 59 }
    assert(panel.content.section == old_selector
      and #panel.content.multiple_sections.section_list.children == old_count,
      "Fallback synchronization ran before 60 ticks")
    handlers[defines.events.on_tick] { tick = game.tick + 60 }
    assert(not old_selector.valid
      and #panel.content.multiple_sections.section_list.children == old_count + 1
      and not checkbox_for(added).state,
      "The 60-tick fallback missed an empty section or reused stale selector IDs")
    assert(panel.content.section.selected_index == checkbox_for(selected).tags.entry_index
      and panel.actions.undo.visible
      and remote.call(TEST_INTERFACE, "get_deadline", player.index) == deadline,
      "An unselected section addition reset selection, Undo, or a confirmation")
    assert_same(applied, selected.filters, "automatic section addition must not edit requests")

    enter_amount("requested", "draft")
    local event_section = assert(point.add_section("Automatic event addition"))
    event_section.set_slot(1, {
      value = { name = "copper-plate", quality = "normal" }, min = 3, max = 9
    })
    handlers[defines.events.on_entity_logistic_slot_changed] {
      entity = hub, section = event_section, slot_index = 1
    }
    assert(not checkbox_for(event_section).state
      and panel.content.amount_controls.requested.multiplier.text == "draft"
      and panel.content.amount_controls.requested_header.units.selected_index == 1
      and panel.actions.undo.visible, "A slot-change update lost the pending form or Undo")
    local previous_index = selected.index
    assert(point.remove_section(leading.index))
    poll_editor()
    assert(selected.valid and selected.index < previous_index
      and panel.content.section.selected_index == checkbox_for(selected).tags.entry_index,
      "Removing another section silently retargeted the selected request section")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Unrelated reindexing must not invalidate safe Undo")
    log("BULK_IMPORT_TEST: 60-tick fallback, immediate slot events, stable selection, drafts, timers, and reindexed Undo")

    other.group = "Automatic other renamed"
    poll_editor()
    assert(panel.content.section.selected_index == checkbox_for(selected).tags.entry_index,
      "An unselected group rename cleared an unchanged selection")
    enter_amount("requested", 2)
    enter_amount("trash_above", 5)
    choose_mode("multiple")
    click(panel.content.multiple_sections.selection_actions.check_none)
    check_section(selected, true)
    check_section(other, true)
    local before_group_change = selected.filters
    selected.group = "Automatic selected group changed"
    handlers[defines.events.on_entity_logistic_slot_changed] {
      entity = hub, section = selected, slot_index = 1
    }
    assert(panel.content.status.caption[1] == "bulk-imports.selection-updated"
      and not panel.actions.apply.enabled, "A selected group change did not require a new selection")
    for _, checkbox in ipairs(panel.content.multiple_sections.section_list.children) do
      assert(not checkbox.state, "An unsafe batch update retained part of the old selection")
    end
    assert_same(before_group_change, selected.filters, "automatic group changes must not apply proposed edits")
    check_section(selected, true)
    check_section(other, true)
    assert(point.remove_section(other.index))
    change_units(panel.content.amount_controls.requested_header.units, 2)
    assert(panel.content.status.caption[1] == "bulk-imports.selection-updated"
      and not panel.actions.apply.enabled,
      "An editor interaction did not detect a removed selected section without waiting for ticks")
    assert_same(before_group_change, selected.filters, "interaction-driven synchronization must not edit requests")

    click(panel.titlebar.close_panel)
    local hidden_section = assert(point.add_section("Automatic hidden editor addition"))
    handlers[defines.events.on_entity_logistic_slot_changed] {
      entity = hub, section = hidden_section, slot_index = 1
    }
    poll_editor()
    assert(not get_editor(player) and not get_user_setting(player, "show-editor"),
      "Automatic synchronization reopened a deliberately hidden editor")
    launch_editor()
    log("BULK_IMPORT_TEST: changed/removed selected groups clear the batch safely; interaction checks and hidden-state preservation")
  end
  exercise_automatic_updates()

  local function exercise_window_modes()
    choose_mode("single")
    choose_section(amount_section)
    choose_mode("multiple")
    click(panel.content.multiple_sections.selection_actions.check_none)
    check_section(amount_section, true)
    check_section(small_amount_section, true)
    edit_option("edit_amounts", true)
    change_units(panel.content.amount_controls.requested_header.units, 1)
    edit_option("edit_quality", true)
    choose_quality("epic")
    enter_amount("requested", 2)
    enter_amount("trash_above", 5)
    edit_option("edit_payload", true)
    change_units(panel.content.payload_controls.payload_header.units, 2)
    enter_payload(3)
    local original_amounts = amount_section.filters
    local original_small = small_amount_section.filters
    apply("fulgora", "platforms")
    edit_option("edit_filters", false)
    choose_quality(nil, #panel.content.quality_controls.comparator.items)
    enter_payload("waiting")
    enter_amount("requested", "pending")
    local selected_index = panel.content.section.selected_index
    local requested_position = panel.content.amount_controls.requested.amount_slider.slider_value
    local expected_error = panel.content.status.caption

    local function toggle_dock()
      local old_panel = panel
      choose_placement(player.gui.screen[PANEL_NAME] == panel and "right" or "floating")
      assert(not old_panel.valid and player.opened == hub,
        "Docking must replace only the editor, not the native inventory")
    end

    local function assert_preserved_form()
      assert(panel.content.section.selected_index == selected_index
        and panel.content.selection_modes.multiple.state and not panel.content.section.visible)
      assert(checkbox_for(amount_section).state and checkbox_for(small_amount_section).state
        and not checkbox_for(quality_collision).state, "Docking lost checked request sections")
      assert(not panel.content.edit_filters.state and panel.content.edit_amounts.state
        and panel.content.edit_quality.state and panel.content.edit_payload.state,
        "Docking changed edit categories")
      assert(panel.content.amount_controls.requested_header.units.selected_index == 1
        and panel.content.amount_controls.trash_above_header.units == nil
        and panel.content.payload_controls.payload_header.units.selected_index == 2
        and panel.content.payload_controls.quantity_row.multiplier.text == "waiting"
        and panel.content.payload_controls.quantity_row.amount_slider.slider_value == 2,
        "Docking lost quantity units or payload input")
      assert(panel.content.planet_row.planet_selector.elem_value == "fulgora"
        and panel.content.sources.platforms.state and not panel.content.sources.planet.state
        and not panel.content.sources.all.state, "Docking lost import form values")
      assert(panel.content.amount_controls.requested.multiplier.text == "pending"
        and panel.content.amount_controls.trash_above.multiplier.text == "5"
        and panel.content.amount_controls.requested.amount_slider.slider_value == requested_position,
        "Docking changed invalid text or its last valid slider position")
      assert(panel.content.quality_controls.comparator.selected_index
        == #panel.content.quality_controls.comparator.items
        and panel.content.quality_controls.qualities.quality_epic.toggled
        and not panel.content.quality_controls.qualities.quality_epic.enabled,
        "Docking lost Any quality or the previous quality selection")
      assert(panel.actions.undo.visible and not panel.actions.apply.enabled)
      assert_same(expected_error, panel.content.status.caption, "docking status message")
    end

    local function assert_minimized()
      assert(panel.minimized_icon.visible and panel.minimized_icon.sprite == "logistic-request-editor-editor-icon"
        and panel.titlebar.minimize.sprite == panel.minimized_icon.sprite
        and panel.style.horizontal_align == "center"
        and panel.minimized_icon.style.minimal_width == 28
        and panel.minimized_icon.style.maximal_height == 28
        and panel.minimized_icon.style.left_margin == 0 and panel.minimized_icon.style.right_margin == 0,
        "Minimizing must shrink the editor to its compact requester-chest icon")
      assert((panel.style.minimal_width == nil or panel.style.minimal_width == 0)
        and (panel.style.maximal_width == nil or panel.style.maximal_width == 0)
        and panel.style.left_padding == 8 and panel.style.right_padding == 8
        and panel.style.top_padding == 8 and panel.style.bottom_padding == 8,
        "The compact frame must size naturally around the icon with equal padding, not retain a forced width")
      for _, child in ipairs(panel.children) do
        assert(child == panel.minimized_icon or not child.visible,
          "A minimized editor still displays non-icon controls")
      end
      assert(player.opened == hub and get_user_setting(player, "show-editor")
        and player.is_shortcut_toggled(SHORTCUT_NAME),
        "Minimizing closed the inventory or forgot the editor's visible state")
    end

    local expanded_width = panel.style.maximal_width
    local expanded_height_limit = panel.content.style.maximal_height
    local before_minimize = panel
    local before_minimize_requests = amount_section.filters
    click(panel.titlebar.dock_toggle)
    assert(panel.placement_menu.visible)
    click(panel.titlebar.minimize)
    assert(panel == before_minimize, "Minimizing rebuilt the GUI and risked losing the draft")
    assert_minimized()
    poll_editor()
    assert_minimized()
    assert_same(before_minimize_requests, amount_section.filters, "Minimizing or polling must not edit requests")
    click(panel.minimized_icon)
    assert(panel == before_minimize and panel.titlebar.visible and panel.content.visible
      and panel.actions.visible and not panel.minimized_icon.visible
      and panel.style.horizontal_align == "left"
      and panel.style.top_padding ~= 8
      and not panel.placement_menu.visible and panel.style.maximal_width == expanded_width
      and panel.content.style.maximal_height == expanded_height_limit,
      "Restoring did not recover the original panel size and controls")
    assert_preserved_form()

    toggle_dock()
    assert(player.gui.screen[PANEL_NAME] == panel and not player.gui.relative[PANEL_NAME])
    assert(panel.titlebar.lock_toggle.visible and panel.titlebar.recenter.visible
      and panel.titlebar.lock_toggle.type == "sprite-button"
      and panel.titlebar.lock_toggle.sprite == "virtual-signal/signal-unlock"
      and panel.titlebar.lock_toggle.style.name == panel.titlebar.close_panel.style.name
      and panel.titlebar.drag_space.drag_target == panel and panel.titlebar.heading.drag_target == panel,
      "The undocked editor must be draggable by its title bar")
    assert_preserved_form()
    click(panel.titlebar.lock_toggle)
    assert(panel.titlebar.drag_target == nil and panel.titlebar.drag_space.drag_target == nil
      and panel.titlebar.heading.drag_target == nil
      and panel.titlebar.lock_toggle.sprite == "virtual-signal/signal-lock",
      "Locking must disable title-bar dragging and show the current closed-padlock state")
    click(panel.titlebar.lock_toggle)
    assert(panel.titlebar.drag_space.drag_target == panel
      and panel.titlebar.lock_toggle.sprite == "virtual-signal/signal-unlock",
      "Unlocking must restore dragging and show the current open-padlock state")
    panel.location = { x = -100, y = -100 }
    handlers[defines.events.on_gui_location_changed] { player_index = player.index, element = panel }
    assert(panel.location.x == 0 and panel.location.y == 0, "Dragging lost the title bar off screen")
    panel.location = { x = 100, y = 120 }
    handlers[defines.events.on_gui_location_changed] { player_index = player.index, element = panel }
    click(panel.titlebar.lock_toggle)
    toggle_dock()
    assert(player.gui.relative[PANEL_NAME] == panel
      and panel.anchor.gui == defines.relative_gui_type.space_platform_hub_gui
      and not panel.titlebar.lock_toggle.visible and not panel.titlebar.recenter.visible)
    assert_preserved_form()
    toggle_dock()
    assert(player.gui.screen[PANEL_NAME] == panel and panel.location.x == 100 and panel.location.y == 120,
      "Undocking did not restore the remembered floating position")
    assert(panel.titlebar.drag_space.drag_target == nil, "Undocking lost the floating lock preference")
    assert_preserved_form()
    click(panel.titlebar.minimize)
    assert_minimized()
    assert(panel.titlebar.drag_space.drag_target == nil and panel.location.x == 100 and panel.location.y == 120,
      "Minimizing a locked floating panel moved or unlocked it")
    set_user_setting(player, "placement", "right")
    panel = assert(get_editor(player))
    assert_minimized()
    set_user_setting(player, "placement", "floating")
    panel = assert(get_editor(player))
    assert_minimized()
    assert(panel.location.x == 100 and panel.location.y == 120 and panel.titlebar.drag_space.drag_target == nil,
      "Moving the minimized editor lost its remembered position or lock")
    click(panel.minimized_icon)
    assert_preserved_form()
    local same_panel = panel
    handlers[defines.events.on_gui_opened] { player_index = player.index, gui_type = defines.gui_type.custom }
    assert(get_editor(player) == same_panel, "An unrelated GUI notification reset the current editor")

    click(panel.actions.undo)
    assert_same(original_amounts, amount_section.filters, "Undo after changing window modes")
    assert_same(original_small, small_amount_section.filters, "batch Undo after changing window modes")
    -- Simulate a partially elapsed confirmation while the scenario remains on one tick.
    local deadline = game.tick + 150
    remote.call(TEST_INTERFACE, "set_deadline", player.index, deadline)
    toggle_dock()
    assert(remote.call(TEST_INTERFACE, "get_deadline", player.index) == deadline
      and panel.content.status.caption[1] == "bulk-imports.undone",
      "Docking reset the confirmation timer")
    click(panel.titlebar.minimize)
    assert_minimized()
    assert(remote.call(TEST_INTERFACE, "get_deadline", player.index) == deadline,
      "Minimizing reset the confirmation deadline")
    handlers[defines.events.on_tick] { tick = deadline - 1 }
    assert(panel.content.status.visible)
    handlers[defines.events.on_tick] { tick = deadline }
    assert(not panel.content.status.visible)
    assert_minimized()
    click(panel.minimized_icon)
    toggle_dock()
    remote.call(TEST_INTERFACE, "set_preference", player.index, "display_width", player.display_resolution.width - 1)
    handlers[defines.events.on_player_display_resolution_changed] { player_index = player.index }
    local preferences = get_test_preferences(player)
    assert(panel.auto_center and preferences.position == nil and panel.titlebar.drag_space.drag_target == nil,
      "A display change must recenter the floating editor without unlocking it")
    remote.call(TEST_INTERFACE, "set_preference", player.index, "display_scale", player.display_scale + 0.25)
    handlers[defines.events.on_player_display_scale_changed] { player_index = player.index }
    preferences = get_test_preferences(player)
    assert(panel.auto_center and preferences.display_scale == player.display_scale)
    click(panel.titlebar.minimize)
    handlers[RESET_INPUT_NAME] { player_index = player.index }
    assert(panel.titlebar.visible and panel.content.visible and not panel.minimized_icon.visible
      and panel.auto_center and panel.style.maximal_width == expanded_width,
      "The rescue input must expand and center a minimized editor")
    click(panel.titlebar.lock_toggle)
    panel.location = { x = 80, y = 90 }
    handlers[defines.events.on_gui_location_changed] { player_index = player.index, element = panel }
    click(panel.titlebar.recenter)
    preferences = get_test_preferences(player)
    assert(panel.auto_center and preferences.position == nil, "Center did not reset the floating position")
    assert_same(original_amounts, amount_section.filters, "Moving and centering must not apply requests")
    click(panel.titlebar.minimize)
    assert_minimized()
    click(panel.minimized_icon)
    assert(panel.titlebar.drag_space.drag_target == panel, "Restoring must keep the floating window unlocked")
    panel.location = { x = 82, y = 94 }
    handlers[defines.events.on_gui_location_changed] { player_index = player.index, element = panel }
    click(panel.titlebar.minimize)
    click(panel.minimized_icon)
    assert(panel.location.x == 82 and panel.location.y == 94,
      "Restoring discarded the floating window's dragged position")
    log("BULK_IMPORT_TEST: minimize/restore icons, unchanged drafts and Undo, minimized placement, drag/lock, confirmation expiry, rescue, and display recentering")

    choose_mode("single")
    choose_section(amount_section)
    edit_option("edit_quality", false)
    edit_option("edit_payload", false)
    enter_amount("requested", 2)
    enter_amount("trash_above", 5)
    amount_section.group = "Window mode renamed group"
    local before_stale_move = amount_section.filters
    toggle_dock()
    assert(panel.content.status.caption[1] == "bulk-imports.selection-updated" and not panel.actions.apply.enabled,
      "Changing docking modes masked a stale request-section selection")
    assert_same(before_stale_move, amount_section.filters, "stale selection after docking")

    toggle_dock()
    panel.location = { x = 88, y = 96 }
    handlers[defines.events.on_gui_location_changed] { player_index = player.index, element = panel }
    click(panel.titlebar.lock_toggle)
    click(panel.titlebar.minimize)
    handlers[defines.events.on_lua_shortcut] { player_index = player.index, prototype_name = SHORTCUT_NAME }
    assert(not get_editor(player) and player.opened == hub
      and player.is_shortcut_available(SHORTCUT_NAME) and not player.is_shortcut_toggled(SHORTCUT_NAME),
      "The launcher did not close only the editor")
    launch_editor()
    assert(player.gui.screen[PANEL_NAME] == panel and panel.location.x == 88 and panel.location.y == 96
      and panel.titlebar.drag_space.drag_target == nil and not panel.content.visible
      and panel.minimized_icon.visible,
      "Relaunching must preserve placement and the shared minimized preference")
    assert(not panel.actions.undo.visible and panel.content.selection_modes.single.state
      and panel.content.edit_filters.state and not panel.content.edit_amounts.state
      and not panel.content.edit_quality.state and not panel.content.edit_payload.state
      and panel.content.amount_controls.requested.multiplier.text == "1"
      and panel.content.amount_controls.requested_header.units.selected_index == 2
      and panel.content.payload_controls.payload_header.units.selected_index == 1,
      "Closing the editor did not discard its temporary form")
    handlers[defines.events.on_player_controller_changed] { player_index = player.index }
    assert(get_editor(player) == panel, "An unchanged request context was lost on a controller notification")
    handlers[defines.events.on_player_left_game] { player_index = player.index }
    assert(not get_editor(player) and not player.is_shortcut_available(SHORTCUT_NAME))
    handlers[defines.events.on_player_joined_game] { player_index = player.index }
    panel = assert(get_editor(player), "Rejoining lost the remembered visible state")
    assert(player.is_shortcut_available(SHORTCUT_NAME))
    for _, event_name in ipairs({
      defines.events.on_player_joined_game,
      defines.events.on_player_changed_force,
      defines.events.on_player_died
    }) do
      local old_panel = panel
      handlers[event_name] { player_index = player.index }
      panel = assert(get_editor(player), "A valid player context lost the remembered visible state")
      assert(not old_panel.valid and not panel.actions.undo.visible,
        "A player context reset retained its temporary editor state")
      assert(player.gui.screen[PANEL_NAME] == panel and panel.location.x == 88 and panel.location.y == 96
        and panel.titlebar.drag_space.drag_target == nil and panel.minimized_icon.visible,
        "Resetting temporary player context discarded window preferences")
    end
    player.opened = nil
    handlers[defines.events.on_gui_closed] {
      player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
    }
    assert(not get_editor(player) and not player.is_shortcut_available(SHORTCUT_NAME)
      and player.is_shortcut_toggled(SHORTCUT_NAME))
    player.opened = hub
    handlers[defines.events.on_gui_opened] {
      player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
    }
    panel = assert(get_editor(player), "A remembered visible editor did not reopen with the inventory")
    assert(player.gui.screen[PANEL_NAME] == panel and panel.location.x == 88 and panel.location.y == 96
      and panel.titlebar.drag_space.drag_target == nil and panel.minimized_icon.visible)
    click(panel.minimized_icon)
    click(panel.titlebar.lock_toggle)
    toggle_dock()
    assert(player.gui.relative[PANEL_NAME] == panel)
    log("BULK_IMPORT_TEST: stale section checks survive mode changes; shared minimized and placement preferences survive session resets")
  end
  exercise_window_modes()

  player.opened = nil
  handlers[defines.events.on_gui_closed] {
    player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
  }
  assert(not get_editor(player), "Panel was not closed")

  player.exit_remote_view()
  local character = assert(player.character, "Personal request tests need the player's character")
  local surface = character.surface
  surface.request_to_generate_chunks({ 0, 0 }, 2)
  surface.force_generate_chunk_requests()

  local function open_requester(owner, gui_type)
    local was_visible = get_user_setting(player, "show-editor")
    if gui_type == defines.gui_type.controller then
      player.opened = defines.gui_type.controller
    else
      player.opened = owner
    end
    assert(player.opened_gui_type == gui_type, "The native requester inventory did not open")
    handlers[defines.events.on_gui_opened] {
      player_index = player.index,
      gui_type = gui_type,
      entity = gui_type == defines.gui_type.entity and owner or nil
    }
    assert(player.is_shortcut_available(SHORTCUT_NAME), "The requester did not enable its launcher")
    if was_visible then
      panel = assert(get_editor(player), "The next requester did not restore the editor's visible state")
    else
      assert(not get_editor(player), "A hidden editor opened without using its launcher")
      launch_editor()
    end
  end

  local function close_requester(owner, gui_type)
    local was_visible = get_user_setting(player, "show-editor")
    player.opened = nil
    handlers[defines.events.on_gui_closed] {
      player_index = player.index,
      gui_type = gui_type,
      entity = gui_type == defines.gui_type.entity and owner or nil
    }
    assert(not get_editor(player),
      "Closing the inventory did not close its request editor")
    assert(not player.is_shortcut_available(SHORTCUT_NAME)
      and player.is_shortcut_toggled(SHORTCUT_NAME) == was_visible,
      "Closing an inventory changed the launcher's remembered visibility")
  end

  local function exercise_requester(owner, gui_type, anchor, label)
    local requester = assert(owner.get_requester_point(), label .. " is missing its requester point")
    local first = assert(requester.add_section("Other requester test " .. label))
    first.set_slot(1, {
      value = { name = "iron-plate", quality = "normal" },
      min = 11,
      max = 77,
      import_from = "fulgora",
      request_from = "platforms",
      minimum_delivery_count = 3
    })
    first.set_slot(3, {
      value = { name = "engine-unit", quality = "rare" },
      min = 15,
      max = 90,
      import_from = "nauvis",
      request_from = "planet"
    })
    first.active = false
    first.multiplier = 1.5
    local second = assert(requester.add_section())
    second.set_slot(1, {
      value = { name = "steel-plate", quality = "normal" },
      min = 9,
      max = 45
    })
    local shared_platform = assert(point.add_section(first.group))
    local metadata = without_amounts(first)
    local original_second = second.filters
    local before_open = first.filters

    open_requester(owner, gui_type)
    assert(panel.anchor.gui == anchor, "The panel is attached to the wrong native inventory")
    assert(not panel.content.edit_filters.visible and not panel.content.edit_filters.enabled
      and not panel.content.planet_row.visible and not panel.content.sources.visible
      and not panel.content.filters_divider.visible,
      "A non-platform inventory exposes platform filters")
    assert(not panel.content.edit_payload.visible and not panel.content.edit_payload.enabled
      and not panel.content.payload_controls.visible and not panel.content.payload_divider.visible,
      "A non-platform inventory exposes minimum payload controls")
    assert(panel.content.edit_amounts.state and panel.content.amount_controls.visible,
      "Non-platform amount controls should be enabled when opened")
    assert(not panel.content.edit_quality.state and not panel.content.quality_controls.visible)
    assert(not panel.actions.undo.visible, "A new inventory retained another window's Undo")
    assert_same(before_open, first.filters, "opening " .. label)
    edit_option("edit_payload", true)
    enter_payload("ignored for non-platform requests")
    choose_section(first)
    enter_amount("requested", 3)
    enter_amount("trash_above", 7)
    edit_option("edit_filters", true)
    apply("nauvis", "all")
    assert_amounts(first, 3, 7)
    assert_same(metadata, without_amounts(first), label .. " metadata and hidden imports")
    assert_same(original_second, second.filters, label .. " unselected section")
    assert_same(first.filters, shared_platform.filters, label .. " shared platform section")
    assert(first.active == false and first.multiplier == 1.5 and first.get_slot(2).value == nil)
    click(panel.actions.undo)
    assert_same(before_open, first.filters, label .. " Undo")
    assert_same(before_open, shared_platform.filters, label .. " shared platform Undo")
    assert_same(original_second, second.filters, label .. " unselected section during Undo")
    apply("nauvis", "all")

    choose_mode("multiple")
    click(panel.content.multiple_sections.selection_actions.check_none)
    check_section(first, true)
    check_section(second, true)
    enter_amount("requested", 2)
    enter_amount("trash_above", 5)
    click(panel.actions.apply)
    assert_amounts(first, 2, 5)
    assert_amounts(second, 2, 5)
    assert_same(metadata, without_amounts(first), label .. " batch metadata")
    local before_quality_first, before_quality_second = first.filters, second.filters
    local quality_only_first, quality_only_second = without_quality(first), without_quality(second)
    edit_option("edit_amounts", false)
    edit_option("edit_quality", true)
    choose_quality("rare")
    click(panel.actions.apply)
    assert_quality(first, "rare", "=")
    assert_quality(second, "rare", "=")
    assert_same(quality_only_first, without_quality(first), label .. " quality-only amounts and imports")
    assert_same(quality_only_second, without_quality(second), label .. " quality-only second section")
    assert_same(first.filters, shared_platform.filters, label .. " shared platform quality")
    click(panel.actions.undo)
    assert_same(before_quality_first, first.filters, label .. " quality Undo")
    assert_same(before_quality_second, second.filters, label .. " quality Undo second section")
    choose_quality(nil, #panel.content.quality_controls.comparator.items)
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.amount-quality-range")
    assert_same(before_quality_first, first.filters, label .. " refused Any quality request")
    edit_option("edit_amounts", true)
    enter_amount("requested", 0)
    click(panel.actions.apply)
    assert_quality(first, nil, nil)
    assert_quality(second, nil, nil)
    assert_amounts(first, 0, 5)
    assert_amounts(second, 0, 5)
    assert_same(first.filters, shared_platform.filters, label .. " shared platform Any quality")
    click(panel.actions.undo)
    assert_same(before_quality_first, first.filters, label .. " Any quality Undo")
    assert_same(before_quality_second, second.filters, label .. " Any quality Undo second section")
    edit_option("edit_quality", false)
    local before_disable = first.filters
    edit_option("edit_amounts", false)
    assert(not panel.actions.apply.enabled, "Hidden filters enabled a non-platform Apply")
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.select-edits")
    assert_same(before_disable, first.filters, label .. " disabled amount edits")
    edit_option("edit_amounts", true)

    local before_floating = first.filters
    choose_placement("floating")
    assert(player.gui.screen[PANEL_NAME] == panel and player.opened_gui_type == gui_type,
      "Undocking changed the native request inventory")
    assert(checkbox_for(first).state and checkbox_for(second).state
      and not panel.content.edit_filters.visible)
    choose_placement("right")
    assert(player.gui.relative[PANEL_NAME] == panel and panel.anchor.gui == anchor)
    assert_same(before_floating, first.filters, label .. " docking must not apply form values")
    click(panel.titlebar.close_panel)
    assert(player.opened_gui_type == gui_type, "Closing the panel closed the native inventory")
    assert(not get_editor(player))
    close_requester(owner, gui_type)
    open_requester(owner, gui_type)
    assert(panel.content.edit_amounts.state and not panel.content.edit_filters.visible,
      "Reopening an inventory did not restore its category defaults")
    assert(not panel.actions.undo.visible, "Reopening retained the closed window's Undo")
    close_requester(owner, gui_type)
    log("BULK_IMPORT_TEST: " .. label .. " amounts, quality, Undo, selection, hidden imports, sharing, and GUI lifecycle")
  end

  exercise_requester(character, defines.gui_type.controller, defines.relative_gui_type.controller_gui,
    "Personal logistics")
  game.forces.player.character_logistic_requests = false
  player.opened = defines.gui_type.controller
  handlers[defines.events.on_gui_opened] { player_index = player.index, gui_type = defines.gui_type.controller }
  assert(not get_editor(player) and not player.is_shortcut_available(SHORTCUT_NAME),
    "Personal requests were exposed before requester logistics was available")
  player.opened = nil
  game.forces.player.character_logistic_requests = true

  local requester_fixtures = {
    { name = "requester-chest", gui = defines.relative_gui_type.container_gui, label = "Requester chest" },
    { name = "buffer-chest", gui = defines.relative_gui_type.container_gui, label = "Buffer chest" },
    { name = "spidertron", gui = defines.relative_gui_type.spider_vehicle_gui, label = "Spidertron" },
    { name = "tank", gui = defines.relative_gui_type.car_gui, label = "Tank" },
    { name = "cargo-landing-pad", gui = defines.relative_gui_type.cargo_landing_pad_gui, label = "Cargo landing pad" }
  }
  for index, fixture in ipairs(requester_fixtures) do
    local owner = assert(surface.create_entity {
      name = fixture.name,
      position = { index * 8, 8 },
      force = player.force
    }, "Could not create " .. fixture.label)
    player.set_controller { type = defines.controllers.remote, surface = surface, position = owner.position }
    exercise_requester(owner, defines.gui_type.entity, fixture.gui, fixture.label)
  end

  do
    local first_owner = assert(surface.create_entity {
      name = "requester-chest", position = { 0, 40 }, force = player.force
    })
    local second_owner = assert(surface.create_entity {
      name = "requester-chest", position = { 8, 40 }, force = player.force
    })
    local first_requests = assert(first_owner.get_requester_point().add_section("Visibility first inventory"))
    first_requests.set_slot(1, {
      value = { name = "iron-plate", quality = "normal" }, min = 11, max = 22
    })
    local second_requests = assert(second_owner.get_requester_point().add_section("Visibility second inventory"))
    second_requests.set_slot(1, {
      value = { name = "copper-plate", quality = "normal" }, min = 33, max = 66
    })
    open_requester(first_owner, defines.gui_type.entity)
    choose_section(first_requests)
    enter_amount("requested", 2)
    enter_amount("trash_above", 5)
    click(panel.actions.apply)
    local first_applied = first_requests.filters
    local old_panel = panel
    open_requester(second_owner, defines.gui_type.entity)
    assert(not old_panel.valid and not panel.actions.undo.visible,
      "Switching containers carried over the old editor or Undo")
    choose_section(second_requests)
    click(panel.actions.apply)
    assert_amounts(second_requests, 1, nil, "stacks")
    assert_same(first_applied, first_requests.filters, "The new inventory edited the old target")
    click(panel.titlebar.close_panel)
    player.opened = first_owner
    handlers[defines.events.on_gui_opened] {
      player_index = player.index, entity = first_owner, gui_type = defines.gui_type.entity
    }
    assert(not get_editor(player) and player.is_shortcut_available(SHORTCUT_NAME)
      and not player.is_shortcut_toggled(SHORTCUT_NAME), "X did not remember the hidden state")
    launch_editor()
    handlers[defines.events.on_lua_shortcut] { player_index = player.index, prototype_name = SHORTCUT_NAME }
    player.opened = second_owner
    handlers[defines.events.on_gui_opened] {
      player_index = player.index, entity = second_owner, gui_type = defines.gui_type.entity
    }
    assert(not get_editor(player) and not player.is_shortcut_toggled(SHORTCUT_NAME),
      "The launcher did not remember the hidden state")
    launch_editor()
    close_requester(second_owner, defines.gui_type.entity)
    log("BULK_IMPORT_TEST: visibility follows container changes; X and the launcher remember hidden state")

    open_requester(first_owner, defines.gui_type.entity)
    choose_placement("floating")
    choose_section(first_requests)
    enter_amount("requested", 4)
    enter_amount("trash_above", 8)
    click(panel.actions.apply)
    local before_window_changes = first_requests.filters
    enter_amount("requested", "unsaved draft")
    click(panel.titlebar.minimize)
    close_requester(first_owner, defines.gui_type.entity)
    poll_editor()
    remote.call(TEST_INTERFACE, "configure")
    assert(not get_editor(player) and get_test_preferences(player).minimized,
      "Closing all inventories or resetting GUIs lost the minimized preference")
    open_requester(first_owner, defines.gui_type.entity)
    assert(panel.minimized_icon.visible and not panel.content.visible
      and not panel.actions.undo.visible
      and panel.content.amount_controls.requested.multiplier.text == "1",
      "Reopening the same chest must retain minimization but discard its old draft and Undo")
    player.set_controller { type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    open_requester(hub, defines.gui_type.entity)
    assert(panel.minimized_icon.visible and not panel.content.visible,
      "The minimized chest preference was not shared with a platform")
    set_user_setting(player, "placement", "right")
    panel = assert(get_editor(player))
    assert(panel.minimized_icon.visible, "Redocking reset the shared minimized preference")
    player.exit_remote_view()
    open_requester(character, defines.gui_type.controller)
    assert(panel.minimized_icon.visible, "Personal inventory used a different minimized preference")
    click(panel.minimized_icon)
    close_requester(character, defines.gui_type.controller)
    player.set_controller { type = defines.controllers.remote, surface = surface, position = first_owner.position }
    open_requester(first_owner, defines.gui_type.entity)
    assert(panel.content.visible and not panel.minimized_icon.visible,
      "Restoring from personal inventory did not restore the next chest editor")
    click(panel.titlebar.close_panel)
    player.set_controller { type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    player.opened = hub
    handlers[defines.events.on_gui_opened] {
      player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
    }
    assert(not get_editor(player) and not get_user_setting(player, "show-editor"),
      "Hiding a chest editor did not keep a platform editor hidden")
    launch_editor()
    assert(panel.content.visible, "Turning the editor back on lost its restored preference")
    click(panel.titlebar.minimize)
    handlers[defines.events.on_lua_shortcut] { player_index = player.index, prototype_name = SHORTCUT_NAME }
    player.set_controller { type = defines.controllers.remote, surface = surface, position = second_owner.position }
    player.opened = second_owner
    handlers[defines.events.on_gui_opened] {
      player_index = player.index, entity = second_owner, gui_type = defines.gui_type.entity
    }
    assert(not get_editor(player), "Switching from a hidden minimized platform reopened a chest editor")
    launch_editor()
    assert(panel.minimized_icon.visible, "Showing a hidden editor discarded its last minimized preference")
    close_requester(second_owner, defines.gui_type.entity)
    handlers[RESET_INPUT_NAME] { player_index = player.index }
    poll_editor()
    assert(not get_editor(player) and not get_test_preferences(player).minimized,
      "Rescue without an inventory must remember restoration without displaying an orphan editor")
    open_requester(second_owner, defines.gui_type.entity)
    assert(panel.content.visible and not panel.minimized_icon.visible and panel.auto_center,
      "Rescue did not restore the next supported inventory's editor")
    choose_placement("right")
    close_requester(second_owner, defines.gui_type.entity)
    assert_same(before_window_changes, first_requests.filters, "Shared window preferences edited chest requests")
    log("BULK_IMPORT_TEST: global per-player hidden/minimized/restored state across chests, platforms, personal inventory, configuration resets and no-inventory rescue")
  end

  for index, name in ipairs({ "steel-chest", "passive-provider-chest", "storage-chest", "car", "constant-combinator" }) do
    local owner = assert(surface.create_entity {
      name = name,
      position = { index * 8, 24 },
      force = player.force
    })
    player.opened = owner
    assert(player.opened == owner, "The unsupported inventory fixture did not open")
    handlers[defines.events.on_gui_opened] {
      player_index = player.index,
      entity = owner,
      gui_type = defines.gui_type.entity
    }
    assert(not get_editor(player) and not player.is_shortcut_available(SHORTCUT_NAME),
      "An inventory without supported requests opened the editor")
    close_requester(owner, defines.gui_type.entity)
  end
  log("BULK_IMPORT_TEST: unavailable personal logistics and unsupported inventories do not expose the editor")

  local function exercise_mod_options()
    local function reset_options()
      local names = {}
      for name in pairs(prototypes.mod_setting) do
        if name:sub(1, #SETTING_PREFIX) == SETTING_PREFIX then
          names[#names + 1] = name
        end
      end
      table.sort(names)
      for _, name in ipairs(names) do
        remote.call(TEST_INTERFACE, "set_setting", player.index, name, prototypes.mod_setting[name].default_value)
      end
    end

    local function reopen_editor()
      if get_editor(player) then
        click(panel.titlebar.close_panel)
      end
      launch_editor()
    end

    reset_options()
    player.set_controller { type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    player.opened = hub
    handlers[defines.events.on_gui_opened] {
      player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
    }
    assert(get_editor(player), "Resetting to factory defaults must restore automatic opening")
    set_user_setting(player, "show-editor", true)
    panel = assert(get_editor(player), "The visibility option did not reveal the current editor")
    assert(player.is_shortcut_toggled(SHORTCUT_NAME))
    assert(panel.content.sort_controls.clear_empty_slots.state,
      "Clear empty slots must be enabled by default")
    set_user_setting(player, "default-clear-empty-slots", false)
    assert(panel.content.sort_controls.clear_empty_slots.state,
      "Changing the clearing default replaced the current form")
    reopen_editor()
    assert(not panel.content.sort_controls.clear_empty_slots.state,
      "A fresh editor ignored the disabled clearing default")
    set_user_setting(player, "default-clear-empty-slots", true)
    reopen_editor()
    assert(panel.content.sort_controls.clear_empty_slots.state,
      "A fresh editor ignored the enabled clearing default")
    local options_section = assert(point.add_section("Per-player option tests"))
    options_section.set_slot(1, {
      value = { name = "iron-plate", quality = "normal" }, min = 7, max = 21
    })
    local original_options = options_section.filters
    poll_editor()
    local original_requested_text = panel.content.amount_controls.requested.multiplier.text
    set_user_setting(player, "default-selection", "multiple")
    set_user_setting(player, "default-units", "items")
    set_user_setting(player, "default-requested", 4)
    set_user_setting(player, "default-maximum", "9")
    set_user_setting(player, "default-payload-units", "stacks")
    set_user_setting(player, "default-payload", "3")
    assert(panel.content.selection_modes.single.state
      and panel.content.amount_controls.requested.multiplier.text == original_requested_text,
      "Default option changes replaced the open form")
    reopen_editor()
    assert(panel.content.selection_modes.multiple.state
      and panel.content.amount_controls.requested_header.units.selected_index == 1
      and panel.content.amount_controls.trash_above_header.units == nil
      and panel.content.amount_controls.requested.multiplier.text == "4"
      and panel.content.amount_controls.trash_above.multiplier.text == "9"
      and panel.content.payload_controls.payload_header.units.selected_index == 2
      and panel.content.payload_controls.quantity_row.multiplier.text == "3",
      "A fresh editor did not consume configured defaults")
    local checked = 0
    for _, checkbox in ipairs(panel.content.multiple_sections.section_list.children) do
      if checkbox.state then
        checked = checked + 1
      end
    end
    assert(checked == 1, "Default Multiple mode must select only the first editable section")

    for _, option in ipairs({
      { setting = "edit-filters", control = "edit_filters" },
      { setting = "edit-platform-amounts", control = "edit_amounts" },
      { setting = "edit-quality", control = "edit_quality" },
      { setting = "edit-payload", control = "edit_payload" }
    }) do
      for _, enabled in ipairs({ false, true }) do
        local old_state = panel.content[option.control].state
        set_user_setting(player, option.setting, enabled and "enabled" or "disabled")
        assert(panel.content[option.control].state == old_state,
          "A category default changed the current form")
        reopen_editor()
        assert(panel.content[option.control].state == enabled,
          "A platform category default was ignored: " .. option.setting)
      end
    end
    set_user_setting(player, "default-payload-units", "items")
    set_user_setting(player, "default-payload", "4294967295")
    reopen_editor()
    assert(panel.content.payload_controls.quantity_row.multiplier.text == "4294967295"
      and panel.actions.apply.enabled, "The default payload lost the unsigned range")
    set_user_setting(player, "default-payload", "0")
    reopen_editor()
    assert(not panel.actions.apply.enabled and panel.content.status.caption[1] == "bulk-imports.invalid-payload",
      "An invalid default payload was silently replaced")
    assert_same(original_options, options_section.filters, "Changing defaults modified actual requests")
    log("BULK_IMPORT_TEST: fresh-form defaults, individual platform categories, and unsigned/invalid payload defaults")

    local option_chest = assert(surface.create_entity {
      name = "requester-chest", position = { 24, 40 }, force = player.force
    })
    option_chest.get_requester_point().add_section("Other inventory option tests").set_slot(1, {
      value = { name = "iron-plate", quality = "normal" }, min = 3, max = 10
    })
    player.set_controller { type = defines.controllers.remote, surface = surface, position = option_chest.position }
    open_requester(option_chest, defines.gui_type.entity)
    for _, option in ipairs({
      { setting = "edit-other-amounts", control = "edit_amounts" },
      { setting = "edit-quality", control = "edit_quality" }
    }) do
      for _, enabled in ipairs({ false, true }) do
        set_user_setting(player, option.setting, enabled and "enabled" or "disabled")
        reopen_editor()
        assert(panel.content[option.control].state == enabled,
          "An other-inventory category default was ignored: " .. option.setting)
        assert(not panel.content.edit_filters.visible and not panel.content.edit_filters.state
          and not panel.content.edit_payload.visible and not panel.content.edit_payload.state,
          "Platform category defaults leaked into another inventory")
      end
    end
    set_user_setting(player, "default-maximum", "not a count")
    set_user_setting(player, "edit-other-amounts", "enabled")
    reopen_editor()
    assert(not panel.actions.apply.enabled and panel.content.status.caption[1] == "bulk-imports.invalid-maximum")
    reset_options()
    set_user_setting(player, "show-editor", false)
    assert(not get_editor(player) and not player.is_shortcut_toggled(SHORTCUT_NAME),
      "Turning off visibility through options did not hide the editor")
    log("BULK_IMPORT_TEST: independent non-platform category defaults and explicit invalid-default validation")

    player.set_controller { type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    player.opened = hub
    handlers[defines.events.on_gui_opened] {
      player_index = player.index, entity = hub, gui_type = defines.gui_type.entity
    }
    set_user_setting(player, "show-editor", true)
    panel = assert(get_editor(player))
    choose_mode("single")
    choose_section(options_section)
    edit_option("edit_filters", false)
    edit_option("edit_amounts", true)
    enter_amount("requested", 2)
    enter_amount("trash_above", 5)
    set_user_setting(player, "confirmation-seconds", 2)
    click(panel.actions.apply)
    handlers[defines.events.on_tick] { tick = game.tick + 119 }
    assert(panel.content.status.visible, "Configured confirmation duration expired early")
    handlers[defines.events.on_tick] { tick = game.tick + 120 }
    assert(not panel.content.status.visible and panel.actions.undo.visible)
    enter_amount("requested", "unapplied")
    for _, choice in ipairs({ "left", "right", "top", "bottom" }) do
      choose_placement(choice)
      assert(get_user_setting(player, "placement") == choice
        and player.gui.relative[PANEL_NAME] == panel
        and panel.anchor.position == defines.relative_gui_position[choice]
        and panel.content.amount_controls.requested.multiplier.text == "unapplied"
        and panel.actions.undo.visible and not panel.placement_menu.visible,
        "A placement menu choice lost form state or failed to update options")
    end
    set_user_setting(player, "placement", "floating")
    panel = assert(get_editor(player))
    assert(player.gui.screen[PANEL_NAME] == panel
      and panel.content.amount_controls.requested.multiplier.text == "unapplied"
      and panel.content.type == "scroll-pane"
      and panel.content.style.maximal_height < player.display_resolution.height / player.display_scale,
      "External placement changes failed to preserve the form or bound the body height")
    set_user_setting(player, "floating-locked", true)
    assert(panel.titlebar.drag_space.drag_target == nil
      and panel.titlebar.lock_toggle.sprite == "virtual-signal/signal-lock",
      "Changing the lock option must update both dragging and the padlock icon")
    click(panel.titlebar.lock_toggle)
    assert(not get_user_setting(player, "floating-locked") and panel.titlebar.drag_space.drag_target == panel
      and panel.titlebar.lock_toggle.sprite == "virtual-signal/signal-unlock",
      "The lock button did not update its user option")
    panel.location = { x = -5000, y = -5000 }
    handlers[RESET_INPUT_NAME] { player_index = player.index }
    panel = assert(get_editor(player))
    assert(panel.auto_center and get_user_setting(player, "placement") == "floating"
      and get_user_setting(player, "show-editor") and panel.actions.undo.visible
      and panel.content.amount_controls.requested.multiplier.text == "unapplied",
      "The external rescue input lost the form or Undo")
    click(panel.actions.undo)
    assert_same(original_options, options_section.filters, "Undo after settings placement and rescue")

    panel.location = { x = 70, y = 80 }
    handlers[defines.events.on_gui_location_changed] { player_index = player.index, element = panel }
    set_user_setting(player, "remember-position", false)
    assert(panel.auto_center and get_test_preferences(player).position == nil)
    panel.location = { x = 90, y = 100 }
    handlers[defines.events.on_gui_location_changed] { player_index = player.index, element = panel }
    assert(get_test_preferences(player).position == nil, "Disabled position remembering still stored dragged positions")
    click(panel.titlebar.close_panel)
    launch_editor()
    assert(panel.auto_center)
    close_requester(hub, defines.gui_type.entity)
    handlers[RESET_INPUT_NAME] { player_index = player.index }
    assert(not get_editor(player) and get_user_setting(player, "show-editor"))
    open_requester(hub, defines.gui_type.entity)
    assert(panel.auto_center and player.gui.screen[PANEL_NAME] == panel,
      "Rescue without an open inventory did not recover the next editor")
    log("BULK_IMPORT_TEST: all docking edges, live options, mirrored lock/visibility, rescue, Undo, and message duration")

    reset_options()
    remote.call(TEST_INTERFACE, "set_preference", player.index, "position", { x = 72, y = 84 })
    remote.call(TEST_INTERFACE, "set_preference", player.index, "visible", true)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "docked", false)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "locked", true)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "settings_migrated", false)
    remote.call(TEST_INTERFACE, "configure")
    panel = assert(get_editor(player))
    assert(get_user_setting(player, "show-editor") and get_user_setting(player, "placement") == "floating"
      and get_user_setting(player, "floating-locked") and panel.location.x == 72 and panel.location.y == 84,
      "Legacy window preferences did not migrate to untouched user options")
    set_user_setting(player, "placement", "left")
    panel = assert(get_editor(player))
    set_user_setting(player, "show-editor", false)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "visible", true)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "docked", false)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "locked", false)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "settings_migrated", false)
    remote.call(TEST_INTERFACE, "configure")
    assert(not get_editor(player) and not get_user_setting(player, "show-editor")
      and get_user_setting(player, "placement") == "left" and get_user_setting(player, "floating-locked"),
      "Legacy migration overwrote explicitly configured non-default options")
    set_user_setting(player, "show-editor", true)
    panel = assert(get_editor(player))
    assert(panel.anchor.position == defines.relative_gui_position.left)
    reset_options()
    log("BULK_IMPORT_TEST: legacy preference migration preserves position and respects configured user options")
  end
  exercise_mod_options()

  local function exercise_sorting_and_capacity()
    set_user_setting(player, "default-units", "stacks")
    set_user_setting(player, "show-editor", true)
    player.set_controller { type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    open_requester(hub, defines.gui_type.entity)
    local sort_section = assert(point.add_section("Sorting integration tests"))
    local prefix = "logistic-request-editor-test-"
    local occupied = { 1, 3, 4, 6 }
    for index, fixture in ipairs({
      { name = "middle", min = 5, quality = "uncommon", planet = "gleba", source = "planet", payload = 5 },
      { name = "alpha", min = 10, max = 1000, quality = "legendary", source = "platforms", payload = 2 },
      { name = "zulu", min = 4, max = 200, quality = "normal", planet = "fulgora", source = "all", payload = 6 },
      { name = "beta", min = 3, max = 150, quality = "rare", planet = "nauvis", source = "planet" }
    }) do
      sort_section.set_slot(occupied[index], {
        value = { name = prefix .. fixture.name, quality = fixture.quality },
        min = fixture.min, max = fixture.max, import_from = fixture.planet,
        request_from = fixture.source, minimum_delivery_count = fixture.payload
      })
    end
    poll_editor()
    choose_mode("single")
    choose_section(sort_section)
    for _, name in ipairs({ "edit_filters", "edit_amounts", "edit_quality", "edit_payload" }) do
      edit_option(name, false)
    end
    assert(panel.content.sort.state and panel.content.sort_controls.visible
      and #sort_element("property").items == 8,
      "Fresh editors must enable Default sorting and expose all platform properties")
    local function clear_empty_slots(enabled)
      local checkbox = panel.content.sort_controls.clear_empty_slots
      checkbox.state = enabled
      handlers[defines.events.on_gui_checked_state_changed] { player_index = player.index, element = checkbox }
    end
    clear_empty_slots(false)
    local before_sort = sort_section.filters
    local by_name = {}
    for _, filter in pairs(before_sort) do
      if filter.value then
        by_name[filter.value.name] = filter
      end
    end
    local expected_orders = {
      { "beta", "zulu", "alpha", "middle" },
      { "alpha", "beta", "middle", "zulu" },
      { "beta", "zulu", "middle", "alpha" },
      { "zulu", "middle", "beta", "alpha" },
      { "beta", "zulu", "alpha", "middle" },
      { "alpha", "beta", "middle", "zulu" },
      { "beta", "middle", "alpha", "zulu" },
      { "beta", "alpha", "middle", "zulu" }
    }
    for property, expected in ipairs(expected_orders) do
      change_units(sort_element("property"), property)
      change_units(panel.content.sort_controls.units, 1)
      if property == 2 then
        assert(not panel.actions.apply.enabled, "Name sorting applied before translated names were ready")
        local pending = remote.call(TEST_INTERFACE, "get_pending_translations", player.index)
        local labels = { alpha = "Alpha", beta = "Beta", middle = "Middle", zulu = "Zulu" }
        for id, name in pairs(pending) do
          handlers[defines.events.on_string_translated] {
            player_index = player.index, id = id, translated = true,
            result = labels[name:sub(#prefix + 1)]
          }
        end
        assert(panel.actions.apply.enabled, "Translated names did not make Name sorting available")
      end
      for direction = 1, 2 do
        choose_sort_direction("sort_order", direction)
        click(panel.actions.apply)
        assert(panel.content.status.caption[1] == "bulk-imports.applied",
          "Sort Apply failed: " .. helpers.table_to_json(panel.content.status.caption))
        for index, slot in ipairs(occupied) do
          local name = prefix .. expected[direction == 1 and index or #expected - index + 1]
          local filter = sort_section.get_slot(slot)
          assert(filter.value.name == name, "Unexpected sort order for property " .. property
            .. ", direction " .. direction .. ": expected " .. name .. ", got " .. filter.value.name)
          assert_same(by_name[name], filter, "Sorting detached request settings from their item")
        end
        assert(sort_section.get_slot(2).value == nil and sort_section.get_slot(5).value == nil,
          "Sorting moved or filled empty slots")
        click(panel.actions.undo)
        assert_same(before_sort, sort_section.filters, "Undo must restore the original item order")
      end
    end
    local clear_section = assert(point.add_section("Clear empty slot tests"))
    clear_section.set_slot(2, {
      value = { name = "iron-plate", quality = "normal" }, min = 0, max = 20,
      import_from = "fulgora", request_from = "platforms"
    })
    clear_section.set_slot(5, {
      value = { name = "copper-plate", quality = "rare" }, min = 3, max = 55,
      import_from = "nauvis", minimum_delivery_count = 7
    })
    local before_clear = clear_section.filters
    poll_editor()
    choose_section(clear_section)
    change_units(sort_element("property"), 1)
    choose_sort_direction("sort_order", 1)
    set_user_setting(player, "default-clear-empty-slots", false)
    clear_empty_slots(true)
    choose_placement("floating")
    assert(panel.content.sort_controls.clear_empty_slots.state,
      "Docking changes lost the clearing choice to the configured default")
    assert_same(before_clear, clear_section.filters, "Clearing must wait for Apply")
    click(panel.actions.apply)
    assert(#clear_section.filters == 2, "Clearing did not remove empty gaps and trailing entries")
    assert_same(before_clear[2], clear_section.get_slot(1), "Clearing removed or changed a zero-request item")
    assert_same(before_clear[5], clear_section.get_slot(2), "Clearing detached request settings from the item")
    click(panel.actions.undo)
    assert_same(before_clear, clear_section.filters, "Undo must restore the original empty-slot positions")
    clear_empty_slots(false)
    choose_placement("right")
    assert(not panel.content.sort_controls.clear_empty_slots.state)
    click(panel.actions.apply)
    assert(clear_section.get_slot(1).value == nil and clear_section.get_slot(3).value == nil
      and clear_section.get_slot(4).value == nil,
      "Unchecked clearing must preserve empty slots while sorting")
    click(panel.actions.undo)
    assert_same(before_clear, clear_section.filters, "Undo of sorting without clearing")
    set_user_setting(player, "default-clear-empty-slots", true)
    choose_section(sort_section)
    log("BULK_IMPORT_TEST: configurable clearing defaults, dense sorted slots, zero requests, attached settings, gap-preserving opt-out and Undo")
    change_units(sort_element("property"), 3)
    choose_sort_direction("sort_order", 1)
    change_units(panel.content.sort_controls.units, 2)
    click(panel.actions.apply)
    for index, name in ipairs({ "middle", "zulu", "alpha", "beta" }) do
      assert(sort_section.get_slot(occupied[index]).value.name == prefix .. name,
        "Stack-normalized Requested sorting used raw item counts")
    end
    click(panel.actions.undo)
    change_units(sort_element("property"), 6)
    edit_option("edit_filters", true)
    panel.content.planet_row.planet_selector.elem_value = "nauvis"
    click(panel.actions.apply)
    for index, name in ipairs({ "beta", "zulu", "alpha", "middle" }) do
      local filter = sort_section.get_slot(occupied[index])
      assert(filter.value.name == prefix .. name and filter.import_from.name == "nauvis",
        "Import sorting did not use the final planet edit before writing")
    end
    click(panel.actions.undo)
    assert_same(before_sort, sort_section.filters, "Undo of combined import edits and sorting")
    edit_option("edit_filters", false)
    change_units(sort_element("property"), 2)
    handlers[defines.events.on_player_locale_changed] { player_index = player.index }
    local pending = remote.call(TEST_INTERFACE, "get_pending_translations", player.index)
    local id = next(pending)
    assert(id, "Changing locale did not invalidate translated sort names")
    handlers[defines.events.on_string_translated] {
      player_index = player.index, id = id, translated = false, result = ""
    }
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.sort-name-failed")
    assert_same(before_sort, sort_section.filters, "Translation failures must not apply partial sorting")
    change_units(sort_element("property"), 1)
    assert(point.remove_section(sort_section.index))
    change_units(sort_element("property"), 2)
    assert(panel.content.section.selected_index == 0 and not panel.actions.apply.enabled
      and panel.content.status.caption[1] == "bulk-imports.selection-updated",
      "Name sorting did not safely handle a selected section removed before its interaction check")
    log("BULK_IMPORT_TEST: all eight sort properties in both directions, native hierarchy, translated names, final import edits, stack normalization, holes, stale targets and Undo")

    local function exercise_unnamed_capacity()
      local owner = assert(surface.create_entity {
        name = "requester-chest", position = { 48, 40 }, force = player.force
      })
      local requester = owner.get_requester_point()
      local first = assert(requester.add_section())
      local item_names = { "copper-cable", "processing-unit" }
      for index, name in ipairs(item_names) do
        first.set_slot(index, { value = { name = name, quality = "normal" }, min = 100 })
      end
      assert(first.group == "" and first.active and first.multiplier == 1,
        "The unnamed request fixture must be active with a positive multiplier")
      local before_first = first.filters
      player.set_controller { type = defines.controllers.remote, surface = surface, position = owner.position }
      open_requester(owner, defines.gui_type.entity)
      choose_mode("single")
      choose_section(first)
      edit_option("sort", false)
      click(panel.content.amount_controls.share_actions.share_capacity)
      assert(panel.content.amount_controls.requested.multiplier.text == "24",
        "An active unnamed section was not recognized: " .. helpers.table_to_json({ panel.content.status.caption }))
      assert_same(before_first, first.filters, "Unnamed sharing must remain staged until Apply")
      click(panel.actions.apply)
      assert_amounts(first, 24, nil, "stacks")
      click(panel.actions.undo)
      assert_same(before_first, first.filters, "Undo of unnamed-section sharing")
      click(panel.content.amount_controls.share_actions.cancel_share)

      local second = assert(requester.add_section())
      second.set_slot(1, {
        value = { name = "steel-plate", quality = "normal" },
        min = 4 * prototypes.item["steel-plate"].stack_size
      })
      local before_second = second.filters
      poll_editor()
      choose_section(first)
      click(panel.content.amount_controls.share_actions.share_capacity)
      assert(panel.content.amount_controls.requested.multiplier.text == "22",
        "Unselected unnamed requests were not reserved separately")
      click(panel.actions.apply)
      assert_amounts(first, 22, nil, "stacks")
      assert_same(before_second, second.filters, "An unselected unnamed section was edited")
      click(panel.actions.undo)
      assert_same(before_first, first.filters, "Undo with unselected unnamed reservations")
      click(panel.content.amount_controls.share_actions.cancel_share)

      choose_mode("multiple")
      click(panel.content.multiple_sections.selection_actions.check_none)
      check_section(first, true)
      check_section(second, true)
      click(panel.content.amount_controls.share_actions.share_capacity)
      assert(panel.content.amount_controls.requested.multiplier.text == "16",
        "Multiple unnamed sections were not matched to their own requests")
      click(panel.actions.apply)
      assert_amounts(first, 16, nil, "stacks")
      assert_amounts(second, 16, nil, "stacks")
      click(panel.actions.undo)
      assert_same(before_first, first.filters, "Batch Undo of the first unnamed section")
      assert_same(before_second, second.filters, "Batch Undo of the second unnamed section")
      click(panel.content.amount_controls.share_actions.cancel_share)
      first.active = false
      click(panel.content.amount_controls.share_actions.share_capacity)
      assert(panel.content.status.caption[1] == "bulk-imports.capacity-inactive",
        "A genuinely inactive section must still be rejected")
      assert_same(before_first, first.filters, "Inactive unnamed sharing changed requests")
      log("BULK_IMPORT_TEST: unnamed-section sharing, separate reservations, multiple targets, Undo and genuine inactive-section refusal")
    end
    exercise_unnamed_capacity()

    local chest = assert(surface.create_entity {
      name = "requester-chest", position = { 40, 40 }, force = player.force
    })
    local inventory = chest.get_inventory(defines.inventory.chest)
    assert(#inventory == 48)
    local chest_point = chest.get_requester_point()
    local selected = assert(chest_point.add_section("Capacity primary"))
    local names = { "iron-plate", "copper-plate", "steel-plate", "electronic-circuit" }
    for index, name in ipairs(names) do
      selected.set_slot(index, {
        value = { name = name, quality = "normal" }, min = index,
        max = index ~= 3 and (index == 1 and 10000 or 10) or nil
      })
    end
    player.set_controller { type = defines.controllers.remote, surface = surface, position = chest.position }
    open_requester(chest, defines.gui_type.entity)
    choose_section(selected)
    assert(panel.content.amount_controls.requested.multiplier.text == "48"
      and panel.content.amount_controls.requested_header.units.selected_index == 2,
      "The chest Max default must open at 48 stacks")
    assert(#sort_element("property").items == 5,
      "Platform-only sort properties leaked into a chest")
    edit_option("sort", false)
    local before_ticks = selected.filters
    local expected_ticks = { 0, 1, 2, 3, 4, 5, 10, 25, 48, 50, 75, 100, 250, 500, 750, 1000 }
    local request_slider = panel.content.amount_controls.requested.amount_slider
    assert(request_slider.get_slider_maximum() == #expected_ticks - 1)
    for index, value in ipairs(expected_ticks) do
      drag_amount("requested", index - 1)
      assert(panel.content.amount_controls.requested.multiplier.text == tostring(value),
        "A standard stack stop or the inserted 48-slot capacity is missing")
    end
    for index, value in ipairs(expected_ticks) do
      drag_amount("trash_above", index - 1)
      assert(panel.content.amount_controls.trash_above.multiplier.text
        == (index == #expected_ticks and "inf." or tostring(value)),
        "Trash stops must match Requested except for the final infinity stop")
    end
    assert_same(before_ticks, selected.filters, "Moving slider stops applied requests prematurely")
    change_units(panel.content.amount_controls.requested_header.units, 1)
    assert(panel.content.amount_controls.requested.amount_slider.get_slider_maximum() == 10,
      "Items mode must retain its existing presets")
    change_units(panel.content.amount_controls.requested_header.units, 2)
    enter_amount("requested", 7)
    enter_amount("trash_above", "inf.")
    inventory.set_bar(24)
    poll_editor()
    assert(panel.content.amount_controls.requested.multiplier.text == "7",
      "Updating capacity overwrote a numeric draft")
    drag_amount("requested", 7)
    assert(panel.content.amount_controls.requested.multiplier.text == "23",
      "A changed inventory bar was not inserted at the appropriate slider position")
    inventory.set_bar(49)
    poll_editor()
    log("BULK_IMPORT_TEST: all standard stack ticks, inserted 48/23-slot stops, final Trash infinity, unchanged Items presets, and chest Max defaults")

    inventory.insert { name = "stone", count = 1 }
    local original = selected.filters
    local metadata = without_amounts(selected)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "12"
      and not panel.content.amount_controls.requested.multiplier.enabled
      and not panel.content.amount_controls.trash_above.visible,
      "Capacity sharing did not stage 12 stacks per type with preserved-trash semantics")
    assert_same(original, selected.filters, "Sharing capacity must wait for Apply")
    choose_placement("floating")
    assert(panel.content.amount_controls.requested.multiplier.text == "12"
      and panel.content.amount_controls.share_actions.cancel_share.visible,
      "Changing placement discarded staged capacity sharing")
    click(panel.actions.apply)
    for _, filter in pairs(selected.filters) do
      if filter.value then
        local count = 12 * prototypes.item[filter.value.name].stack_size
        assert(filter.min == count, "48 slots and four types must request 12 stacks each")
        local old = original[filter.value.name == "iron-plate" and 1
          or filter.value.name == "copper-plate" and 2
          or filter.value.name == "steel-plate" and 3 or 4]
        assert(filter.max == (old.max and math.max(old.max, count) or nil),
          "Capacity sharing changed an already-sufficient or infinite Trash threshold")
      end
    end
    assert_same(metadata, without_amounts(selected), "Capacity sharing changed unrelated request fields")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Undo of equal capacity sharing")
    click(panel.content.amount_controls.share_actions.cancel_share)
    assert(panel.content.amount_controls.requested.multiplier.text == "23"
      and panel.content.amount_controls.trash_above.visible,
      "Custom did not restore the pre-sharing amount draft")

    local stone_size = prototypes.item.stone.stack_size
    local outside_a = assert(chest_point.add_section("Reserved capacity A"))
    outside_a.set_slot(1, {
      value = { name = "stone", quality = "normal" }, min = 3 * stone_size + 1
    })
    local outside_b = assert(chest_point.add_section("Reserved capacity B"))
    outside_b.set_slot(1, {
      value = { name = "stone", quality = "normal" }, min = 5 * stone_size - 1
    })
    local inactive = assert(chest_point.add_section("Inactive reserved capacity"))
    inactive.set_slot(1, {
      value = { name = "stone-brick", quality = "normal" }, min = 100000
    })
    inactive.active = false
    poll_editor()
    choose_section(selected)
    local reserved_before = { outside_a.filters, outside_b.filters, inactive.filters }
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "10",
      "Eight reserved stacks must leave ten stacks for each of four selected types")
    click(panel.actions.apply)
    for _, filter in pairs(selected.filters) do
      if filter.value then
        assert(filter.min == 10 * prototypes.item[filter.value.name].stack_size,
          "Reserved requests were not subtracted before sharing space")
      end
    end
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Undo with unselected reservation")
    for index, section in ipairs({ outside_a, outside_b, inactive }) do
      assert_same(reserved_before[index], section.filters, "Capacity sharing edited an unselected request")
    end
    click(panel.content.amount_controls.share_actions.cancel_share)

    outside_a.multiplier = 0.5
    outside_a.set_slot(1, {
      value = { name = "stone", quality = "normal" }, min = stone_size + 1
    })
    outside_b.set_slot(1, {
      value = { name = "stone", quality = "normal" }, min = stone_size / 2
    })
    inventory.set_bar(46)
    local native_reserved = 0
    for _, filter in pairs(chest_point.filters) do
      if filter.name == "stone" and filter.quality == "normal" then
        native_reserved = native_reserved + filter.count
      end
    end
    assert(native_reserved > 0, "The engine did not compile the fractional unselected requests")
    local expected_share = math.floor((45 - math.ceil(native_reserved / stone_size)) / 4)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == tostring(expected_share),
      "Fractional reservations disagree with native compiled count " .. native_reserved)
    assert_same(original, selected.filters, "Fractional reservation preview applied requests")
    click(panel.content.amount_controls.share_actions.cancel_share)
    outside_a.multiplier = 1
    outside_a.filters = reserved_before[1]
    outside_b.filters = reserved_before[2]
    inventory.set_bar(49)
    poll_editor()

    local duplicate = assert(chest_point.add_section("Capacity duplicate"))
    duplicate.multiplier = 2
    duplicate.set_slot(1, {
      value = { name = "iron-plate", quality = "normal" }, min = 2, max = 4
    })
    local alias = assert(chest_point.add_section(selected.group))
    alias.multiplier = 0.5
    poll_editor()
    choose_mode("multiple")
    click(panel.content.multiple_sections.selection_actions.check_none)
    check_section(selected, true)
    check_section(duplicate, true)
    local duplicate_before = duplicate.filters
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "10")
    click(panel.actions.apply)
    local iron_count = math.floor(10 * prototypes.item["iron-plate"].stack_size / 3.5)
    local selected_iron
    for _, filter in pairs(selected.filters) do
      if filter.value and filter.value.name == "iron-plate" then
        selected_iron = filter.min
      end
    end
    assert(selected_iron == iron_count and duplicate.get_slot(1).min == iron_count,
      "Duplicate requests and linked section multipliers exceeded their shared type allocation")
    assert_same(selected.filters, alias.filters, "Shared aliases must retain native propagation")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Undo of weighted capacity sharing")
    assert_same(duplicate_before, duplicate.filters, "Undo of weighted duplicate request")

    selected.set_slot(7, {
      value = { name = "iron-plate", quality = "rare" }, min = 1, max = 3
    })
    local with_quality = selected.filters
    poll_editor()
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "8",
      "Different qualities must consume separate shares of the remaining slots")
    click(panel.actions.apply)
    assert(selected.get_slot(7).min == math.floor(8 * prototypes.item["iron-plate"].stack_size / 1.5),
      "The rare item did not get a separate multiplier-adjusted allocation")
    click(panel.actions.undo)
    assert_same(with_quality, selected.filters, "Undo of quality-specific capacity sharing")
    original = with_quality

    inventory.set_bar(2)
    poll_editor()
    assert(not panel.actions.apply.enabled)
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.capacity-insufficient")
    assert_same(original, selected.filters, "Insufficient space must not zero requests or apply a partial batch")
    assert_same(duplicate_before, duplicate.filters, "Insufficient space changed a second selected section")
    inventory.set_bar(49)
    click(panel.content.amount_controls.share_actions.cancel_share)
    log("BULK_IMPORT_TEST: 48/4 sharing, staged Apply and Undo, preserved/clamped Trash, merged outside reservations, inactive groups, duplicate types and linked multipliers")

    edit_option("sort", false)
    edit_option("edit_amounts", false)
    edit_option("edit_quality", false)
    set_user_setting(player, "edit-other-amounts", "hidden")
    panel.content.edit_amounts.state = true
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.select-edits")
    assert_same(original, selected.filters, "Hidden amount editing must be excluded by backend validation")
    assert_same(duplicate_before, duplicate.filters, "Hidden editing changed another selected section")

    for _, option in ipairs({
      { setting = "sort", control = "sort" },
      { setting = "edit-other-amounts", control = "edit_amounts" },
      { setting = "edit-quality", control = "edit_quality" }
    }) do
      local before = selected.filters
      set_user_setting(player, option.setting, "hidden")
      assert(not panel.content[option.control].visible and not panel.content[option.control].state,
        "Hidden did not remove and disable a category")
      assert_same(before, selected.filters, "Hiding a category applied pending edits")
      set_user_setting(player, option.setting, "enabled")
      assert(panel.content[option.control].visible and panel.content[option.control].state,
        "Unhiding an enabled category did not reveal its controls")
    end
    set_user_setting(player, "edit-quality", "disabled")
    set_user_setting(player, "default-chest-requested-mode", "custom")
    set_user_setting(player, "default-chest-requested", 7)
    set_user_setting(player, "default-units", "items")
    click(panel.titlebar.close_panel)
    launch_editor()
    assert(panel.content.amount_controls.requested.multiplier.text == "7"
      and panel.content.amount_controls.requested_header.units.selected_index == 1,
      "Independent chest custom defaults did not retain numeric Items mode")

    set_user_setting(player, "default-requested-mode", "max")
    player.set_controller { type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    open_requester(hub, defines.gui_type.entity)
    local max_section = assert(point.add_section("Global Max default"))
    max_section.set_slot(1, { value = { name = "iron-plate", quality = "normal" }, min = 1 })
    poll_editor()
    choose_mode("single")
    choose_section(max_section)
    edit_option("edit_filters", false)
    edit_option("edit_amounts", true)
    local hub_inventory = hub.get_inventory(defines.inventory.hub_main)
    local hub_capacity = #hub_inventory
    if hub_inventory.supports_bar() then
      hub_capacity = math.min(hub_capacity, hub_inventory.get_bar() - 1)
    end
    assert(panel.content.amount_controls.requested_header.units.selected_index == 2
      and panel.content.amount_controls.requested.multiplier.text == tostring(hub_capacity),
      "Global Max must override Items defaults with the actual stack capacity")
    local before_max = max_section.filters
    click(panel.actions.apply)
    assert(max_section.get_slot(1).min == hub_capacity * prototypes.item["iron-plate"].stack_size,
      "Max did not apply the actual full-container stack amount")
    click(panel.actions.undo)
    assert_same(before_max, max_section.filters, "Undo of the global Max default")
    set_user_setting(player, "default-requested-mode", "custom")
    player.set_controller { type = defines.controllers.remote, surface = surface, position = chest.position }
    open_requester(chest, defines.gui_type.entity)

    set_user_setting(player, "edit-other-amounts", "enabled")
    set_user_setting(player, "default-other-amounts", false)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "categories_migrated", false)
    remote.call(TEST_INTERFACE, "configure")
    panel = assert(get_editor(player))
    assert(get_user_setting(player, "edit-other-amounts") == "disabled"
      and not panel.content.edit_amounts.state,
      "Existing boolean category preferences were lost during migration")
    set_user_setting(player, "edit-other-amounts", "hidden")
    set_user_setting(player, "default-other-amounts", true)
    remote.call(TEST_INTERFACE, "set_preference", player.index, "categories_migrated", false)
    remote.call(TEST_INTERFACE, "configure")
    panel = assert(get_editor(player))
    assert(get_user_setting(player, "edit-other-amounts") == "hidden" and not panel.content.edit_amounts.visible,
      "Legacy migration overwrote a configured Hidden category")
    log("BULK_IMPORT_TEST: tri-state category visibility, numeric chest defaults, and safe legacy preference migration")
  end
  exercise_sorting_and_capacity()

  local function exercise_reserved_inventory_slots()
    local owner = assert(surface.create_entity {
      name = "character", position = { 56, 40 }, force = player.force
    })
    player.set_controller { type = defines.controllers.character, character = owner }
    local inventory = owner.get_inventory(defines.inventory.character_main)
    local capacity = #inventory
    assert(inventory.supports_filters() and capacity > 8)
    local reserved_indices = { capacity - 2, capacity - 1, capacity }
    for index, name in ipairs({ "speed-module", "iron-plate", "processing-unit" }) do
      assert(inventory.set_filter(reserved_indices[index], name), "The reserved-slot fixture was rejected")
    end
    assert(inventory[capacity - 1].set_stack { name = "iron-plate", count = 1 })
    assert(not inventory[capacity - 2].valid_for_read and not inventory[capacity].valid_for_read)
    local contents = inventory.get_contents()
    local filters = {}
    for _, index in ipairs(reserved_indices) do
      filters[index] = inventory.get_filter(index)
    end
    local requester = assert(owner.get_requester_point())
    for _, section in ipairs(requester.sections) do
      if section.is_manual then
        section.active = false
      end
    end
    local selected = assert(requester.add_section())
    for index, name in ipairs({ "copper-cable", "processing-unit" }) do
      selected.set_slot(index, { value = { name = name, quality = "normal" }, min = 100 })
    end
    local original = selected.filters
    set_user_setting(player, "edit-other-amounts", "enabled")
    set_user_setting(player, "default-units", "stacks")
    open_requester(owner, defines.gui_type.controller)
    choose_mode("single")
    choose_section(selected)
    edit_option("sort", false)
    edit_option("edit_quality", false)
    local share = math.floor((capacity - 3) / 2)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == tostring(share),
      "Empty, occupied and matching reserved inventory slots must all count as taken")
    local preview = panel.content.amount_controls.share_preview.caption
    assert(preview[4][1] == "bulk-imports.share-filtered-slots" and tonumber(preview[4][2]) == 3,
      "The balance preview did not explain the excluded reserved slots: " .. helpers.table_to_json(preview))
    assert_same(original, selected.filters, "Balancing reserved slots must wait for Apply")
    click(panel.actions.apply)
    assert_amounts(selected, share, nil, "stacks")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Undo of balancing around reserved inventory slots")
    change_units(panel.content.amount_controls.requested_header.units, 1)
    click(panel.actions.apply)
    local item_target = selected.get_slot(1).min
    local first_size = prototypes.item["copper-cable"].stack_size
    local second_size = prototypes.item["processing-unit"].stack_size
    assert(selected.get_slot(2).min == item_target
      and math.ceil(item_target / first_size) + math.ceil(item_target / second_size) <= capacity - 3
      and math.ceil((item_target + 1) / first_size) + math.ceil((item_target + 1) / second_size) > capacity - 3,
      "Items balancing must find the largest equal count that fits outside reserved inventory slots")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Undo of Items balancing around reserved inventory slots")
    click(panel.content.amount_controls.share_actions.cancel_share)

    local outside = assert(requester.add_section("Reserved inventory unedited requests"))
    local steel_size = prototypes.item["steel-plate"].stack_size
    outside.set_slot(1, { value = { name = "steel-plate", quality = "normal" }, min = 4 * steel_size })
    local outside_original = outside.filters
    poll_editor()
    choose_section(selected)
    click(panel.content.amount_controls.share_actions.share_capacity)
    click(panel.actions.apply)
    assert_amounts(selected, math.floor((capacity - 3 - 4) / 2), nil, "stacks")
    assert_same(outside_original, outside.filters, "Unedited requests changed during balancing with reserved slots")
    click(panel.actions.undo)
    assert_same(original, selected.filters)
    click(panel.content.amount_controls.share_actions.cancel_share)
    for _, index in ipairs(reserved_indices) do
      assert_same(filters[index], inventory.get_filter(index), "Balancing changed an inventory slot filter")
    end
    assert_same(contents, inventory.get_contents(), "Balancing changed reserved-slot contents")

    outside.set_slot(1, {
      value = { name = "steel-plate", quality = "normal" }, min = (capacity - 3) * steel_size
    })
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.status.caption[1] == "bulk-imports.capacity-insufficient",
      "Fully reserved space must refuse balancing rather than clear requests")
    assert_same(original, selected.filters, "Insufficient unreserved capacity changed requests")
    assert_same(contents, inventory.get_contents())
    log("BULK_IMPORT_TEST: personal reserved inventory slots count as taken, including empty/occupied/matching filters; staged balancing, other reservations, Undo and contents preservation")
  end
  exercise_reserved_inventory_slots()

  local function exercise_balance_units()
    local owner = assert(surface.create_entity {
      name = "requester-chest", position = { 64, 40 }, force = player.force
    })
    local inventory = owner.get_inventory(defines.inventory.chest)
    inventory.set_bar(6)
    local requester = owner.get_requester_point()
    local selected = assert(requester.add_section("Balance units primary"))
    local prefix = "logistic-request-editor-test-"
    selected.set_slot(1, {
      value = { name = prefix .. "middle", quality = "normal" }, min = 5, max = 50
    })
    selected.set_slot(2, {
      value = { name = prefix .. "alpha", quality = "normal" }, min = 3
    })
    local original = selected.filters
    player.set_controller { type = defines.controllers.remote, surface = surface, position = owner.position }
    open_requester(owner, defines.gui_type.entity)
    choose_mode("single")
    choose_section(selected)
    edit_option("sort", false)
    edit_option("edit_quality", false)
    change_units(panel.content.amount_controls.requested_header.units, 1)
    enter_amount("requested", 9)
    enter_amount("trash_above", 25)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested_header.units.selected_index == 1
      and panel.content.amount_controls.requested_header.units.enabled
      and panel.content.amount_controls.requested.multiplier.text == "150"
      and panel.content.amount_controls.share_preview.caption[1] == "bulk-imports.share-preview-items",
      "Items balancing must keep the selected unit and fit 150 items of each type into five slots")
    assert_same(original, selected.filters, "Items balancing applied requests before Apply")
    choose_placement("floating")
    assert(panel.content.amount_controls.requested_header.units.selected_index == 1
      and panel.content.amount_controls.requested.multiplier.text == "150",
      "Changing placement discarded the Items balancing mode")
    click(panel.actions.apply)
    assert(selected.get_slot(1).min == 150 and selected.get_slot(2).min == 150
      and selected.get_slot(1).max == 150 and selected.get_slot(2).max == nil,
      "Items balancing must allow partial stacks and preserve or raise the existing trash threshold")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Undo of equal item-count balancing")

    change_units(panel.content.amount_controls.requested_header.units, 2)
    assert(panel.content.amount_controls.requested.multiplier.text == "2"
      and panel.content.amount_controls.share_preview.caption[1] == "bulk-imports.share-preview",
      "Changing the balancing unit must recalculate equal whole-stack targets")
    click(panel.actions.apply)
    assert(selected.get_slot(1).min == 200 and selected.get_slot(2).min == 100,
      "Five slots must give each selected type two stacks in Stacks mode")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Undo after switching from Items to Stacks")
    change_units(panel.content.amount_controls.requested_header.units, 1)
    click(panel.content.amount_controls.share_actions.cancel_share)
    assert(panel.content.amount_controls.requested_header.units.selected_index == 1
      and panel.content.amount_controls.requested.multiplier.text == "9"
      and panel.content.amount_controls.trash_above.multiplier.text == "25",
      "Custom must restore the pre-balancing numbers and unit after mode changes")

    inventory.set_bar(5)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "100",
      "Equal item counts must round down enough for whole inventory slots, not merely floor a fractional item target")
    click(panel.actions.apply)
    assert(selected.get_slot(1).min == 100 and selected.get_slot(2).min == 100,
      "Four slots must keep item counts equal rather than redistribute the leftover slot")
    click(panel.actions.undo)
    assert_same(original, selected.filters)
    click(panel.content.amount_controls.share_actions.cancel_share)
    inventory.set_bar(2)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.status.caption[1] == "bulk-imports.capacity-insufficient"
      and not panel.content.amount_controls.share_actions.cancel_share.visible,
      "Insufficient Items capacity must refuse the proposal without leaving balancing active")
    assert_same(original, selected.filters, "Insufficient Items capacity changed requests")

    inventory.set_bar(7)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "200")
    local outside = assert(requester.add_section("Balance units reservation"))
    outside.set_slot(1, { value = { name = "stone", quality = "normal" }, min = prototypes.item.stone.stack_size })
    poll_editor()
    assert(panel.content.amount_controls.requested.multiplier.text == "150",
      "Items preview did not subtract a new unselected reservation")
    outside.set_slot(1, {
      value = { name = "stone", quality = "normal" }, min = 2 * prototypes.item.stone.stack_size
    })
    local outside_original = outside.filters
    click(panel.actions.apply)
    assert(selected.get_slot(1).min == 100 and selected.get_slot(2).min == 100,
      "Items Apply used a stale reservation preview")
    assert_same(outside_original, outside.filters, "Items balancing edited unselected requests")
    click(panel.actions.undo)
    assert_same(original, selected.filters)
    click(panel.content.amount_controls.share_actions.cancel_share)
    outside.active = false

    local duplicate = assert(requester.add_section("Balance units duplicate"))
    duplicate.multiplier = 2
    duplicate.set_slot(1, {
      value = { name = prefix .. "middle", quality = "normal" }, min = 5, max = 7
    })
    local duplicate_original = duplicate.filters
    local alias = assert(requester.add_section(selected.group))
    alias.multiplier = 0.5
    poll_editor()
    choose_mode("multiple")
    click(panel.content.multiple_sections.selection_actions.check_none)
    check_section(selected, true)
    check_section(duplicate, true)
    click(panel.content.amount_controls.share_actions.share_capacity)
    click(panel.actions.apply)
    assert(selected.get_slot(1).min == 57 and duplicate.get_slot(1).min == 57
      and selected.get_slot(2).min == 133,
      "Items allocations did not account for duplicate requests and linked multipliers")
    local counts = { middle = 0, alpha = 0 }
    for _, filter in pairs(requester.filters) do
      for name in pairs(counts) do
        if filter.name == prefix .. name then
          counts[name] = counts[name] + filter.count
        end
      end
    end
    assert(counts.middle == 200 and counts.alpha == 200,
      "Native effective request counts must fit the equal Items targets after multiplier rounding")
    assert_same(selected.filters, alias.filters, "Items balancing lost shared-group propagation")
    click(panel.actions.undo)
    assert_same(original, selected.filters, "Items Undo after duplicate and multiplier allocation")
    assert_same(duplicate_original, duplicate.filters)
    change_units(panel.content.amount_controls.requested_header.units, 0)
    assert(not panel.actions.apply.enabled, "Invalid balancing units must disable Apply")
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.select-amount-units")
    assert_same(original, selected.filters, "Invalid Items/Stacks selection changed requests")
    assert_same(duplicate_original, duplicate.filters)
    change_units(panel.content.amount_controls.requested_header.units, 2)
    assert(panel.actions.apply.enabled, "Choosing valid balancing units did not recover Apply")
    click(panel.content.amount_controls.share_actions.cancel_share)
    log("BULK_IMPORT_TEST: selected Items/Stacks balancing, partial stacks, whole-item rounding, spare capacity, live reservations, duplicates, multipliers, staged Apply and Undo")
  end
  exercise_balance_units()

  local function exercise_secondary_sort()
    local owner = make_hub("Secondary sorting tests")
    local requester = owner.get_requester_point()
    local section = assert(requester.add_section("Secondary sorting requests"))
    local prefix = "logistic-request-editor-test-"
    local occupied = { 1, 3, 4, 6 }
    for index, entry in ipairs({
      { name = "middle", quality = "normal", min = 4 },
      { name = "alpha", quality = "rare", min = 10 },
      { name = "zulu", quality = "normal", min = 5 },
      { name = "beta", quality = "rare", min = 3 }
    }) do
      section.set_slot(occupied[index], {
        value = { name = prefix .. entry.name, quality = entry.quality }, min = entry.min, max = 45
      })
    end
    local original = section.filters
    player.set_controller { type = defines.controllers.remote, surface = owner.surface, position = owner.position }
    open_requester(owner, defines.gui_type.entity)
    choose_mode("single")
    choose_section(section)
    edit_option("sort", true)
    for _, name in ipairs({ "edit_filters", "edit_amounts", "edit_quality", "edit_payload" }) do
      edit_option(name, false)
    end
    panel.content.sort_controls.clear_empty_slots.state = false
    handlers[defines.events.on_gui_checked_state_changed] {
      player_index = player.index, element = panel.content.sort_controls.clear_empty_slots
    }

    local function has_property(name, property)
      for _, caption in ipairs(sort_element(name).items) do
        if type(caption) == "table" and caption[1] == "bulk-imports.sort-" .. property then
          return true
        end
      end
      return false
    end

    local function choose_property(name, property)
      local element = sort_element(name)
      for index, caption in ipairs(element.items) do
        if type(caption) == "table" and caption[1] == "bulk-imports.sort-" .. property then
          change_units(element, index)
          return
        end
      end
      error("Sort property is missing: " .. name .. "/" .. property)
    end

    local function assert_property(name, property)
      local element = sort_element(name)
      local caption = element.items[element.selected_index]
      assert(caption and caption[1] == "bulk-imports.sort-" .. property,
        "A changing dropdown index retargeted " .. name)
    end

    local function assert_order(expected)
      for index, name in ipairs(expected) do
        assert(section.get_slot(occupied[index]).value.name == prefix .. name,
          "Unexpected primary/secondary order at slot " .. occupied[index])
      end
      assert(section.get_slot(2).value == nil and section.get_slot(5).value == nil,
        "Secondary sorting must keep gaps when clearing is unchecked")
    end

    assert(not sort_element("secondary_property").visible
      and not sort_element("secondary_sort_order").visible
      and not panel.content.sort_controls.primary_label.visible
      and not has_property("property", "none"), "Default primary must hide secondary; primary must stay required")
    choose_property("property", "quality")
    assert(panel.content.sort_controls.primary_label.visible
      and panel.content.sort_controls.secondary_label.visible,
      "Both priority labels must be shown when the secondary controls are available")
    choose_sort_direction("sort_order", 2)
    local previous_primary = sort_element("property")
    choose_property("secondary_property", "name")
    assert(not previous_primary.valid and not has_property("property", "name")
      and not has_property("secondary_property", "quality") and has_property("secondary_property", "none"),
      "The two dropdowns must omit each other's selected property")
    assert(sort_element("secondary_property").get_index_in_parent() == 1
      and sort_element("secondary_sort_order").get_index_in_parent() == 2
      and sort_element("secondary_property").style.maximal_width
        + sort_element("secondary_sort_order").style.maximal_width
        + panel.content.sort_controls.secondary_row.style.horizontal_spacing == control_width,
      "The secondary direction toggle must fit to the right without widening the panel")
    assert_property("property", "quality")
    assert(not panel.actions.apply.enabled, "Secondary Name must wait for translated names")
    local pending = remote.call(TEST_INTERFACE, "get_pending_translations", player.index)
    assert(next(pending), "Secondary Name did not request translations")
    local labels = { alpha = "Alpha", beta = "Beta", middle = "Middle", zulu = "Zulu" }
    for id, name in pairs(pending) do
      handlers[defines.events.on_string_translated] {
        player_index = player.index, id = id, translated = true, result = labels[name:sub(#prefix + 1)]
      }
    end
    click(panel.actions.apply)
    assert_order({ "alpha", "beta", "middle", "zulu" })
    choose_placement("floating")
    assert_property("property", "quality")
    assert_property("secondary_property", "name")
    assert(sort_element("sort_order").tags.sort_direction == "descending"
      and sort_element("secondary_sort_order").tags.sort_direction == "ascending",
      "Changing placement lost independently directed sorting priorities")
    click(panel.actions.undo)
    assert_same(original, section.filters, "Undo after moving a two-priority sort form")

    choose_sort_direction("secondary_sort_order", 2)
    assert(not has_property("secondary_property", "default"),
      "Secondary Default must be omitted when its direction matches primary")
    click(panel.actions.apply)
    assert_order({ "beta", "alpha", "zulu", "middle" })
    click(panel.actions.undo)
    assert_same(original, section.filters)
    choose_sort_direction("secondary_sort_order", 1)
    choose_property("secondary_property", "default")
    assert(not has_property("property", "default"), "The primary dropdown retained the secondary's property")
    click(panel.actions.apply)
    assert_order({ "beta", "alpha", "zulu", "middle" })
    click(panel.actions.undo)
    assert_same(original, section.filters)
    local previous_secondary = sort_element("secondary_property")
    choose_sort_direction("sort_order", 1)
    assert(not previous_secondary.valid
      and panel.content.status.caption[1] == "bulk-imports.secondary-sort-cleared",
      "A direction conflict must clear secondary to None with an explicit notice")
    assert_property("secondary_property", "none")
    assert(panel.content.sort_controls.primary_label.visible,
      "Secondary None must keep First by visible while the secondary controls are present")
    handlers[defines.events.on_gui_selection_state_changed] {
      player_index = player.index, element = previous_secondary
    }
    assert_property("secondary_property", "none")
    assert_same(original, section.filters, "Clearing a redundant priority must not apply requests")
    click(panel.actions.apply)
    assert_order({ "zulu", "middle", "beta", "alpha" })
    click(panel.actions.undo)
    assert_same(original, section.filters, "Secondary None must preserve the previous native fallback")

    choose_property("property", "default")
    assert_property("secondary_property", "none")
    assert(not sort_element("secondary_property").visible
      and not panel.content.sort_controls.primary_label.visible
      and not panel.content.sort_controls.secondary_label.visible
      and not panel.content.sort_controls.secondary_row.visible
      and not sort_element("secondary_sort_order").visible)
    sort_element("secondary_sort_order").tags = { sort_direction = "invalid" }
    click(panel.actions.apply)
    assert_order({ "beta", "zulu", "alpha", "middle" })
    click(panel.actions.undo)
    assert_same(original, section.filters, "Default primary must ignore the hidden secondary controls")
    sort_element("secondary_sort_order").tags = { sort_direction = "ascending" }
    choose_sort_direction("secondary_sort_order", 1)
    choose_property("property", "quality")
    choose_sort_direction("sort_order", 2)
    choose_property("secondary_property", "requested")
    assert(panel.content.sort_controls.units.visible, "Secondary numeric sorting must reveal the shared units")
    change_units(panel.content.sort_controls.units, 1)
    click(panel.actions.apply)
    assert_order({ "beta", "alpha", "middle", "zulu" })
    click(panel.actions.undo)
    assert_same(original, section.filters)
    change_units(panel.content.sort_controls.units, 2)
    click(panel.actions.apply)
    assert_order({ "alpha", "beta", "middle", "zulu" })
    click(panel.actions.undo)
    assert_same(original, section.filters, "Secondary stack-normalized sorting changed request values")

    choose_property("secondary_property", "none")
    choose_property("property", "requested")
    choose_sort_direction("sort_order", 1)
    choose_property("secondary_property", "quality")
    choose_sort_direction("secondary_sort_order", 2)
    change_units(panel.content.sort_controls.units, 1)
    edit_option("edit_amounts", true)
    change_units(panel.content.amount_controls.requested_header.units, 1)
    enter_amount("requested", 2)
    enter_amount("trash_above", 25)
    click(panel.actions.apply)
    assert_order({ "beta", "alpha", "zulu", "middle" })
    assert_amounts(section, 2, 25, "items")
    click(panel.actions.undo)
    assert_same(original, section.filters, "Two-priority sorting must use final edited values and support Undo")
    edit_option("edit_amounts", false)
    choose_property("secondary_property", "none")
    choose_property("property", "quality")
    local secondary = sort_element("secondary_property")
    secondary.items = { { "bulk-imports.sort-quality" } }
    secondary.tags = { sort_properties = { "quality" } }
    secondary.selected_index = 1
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.sort-priorities-duplicate")
    assert_same(original, section.filters, "Backend validation must refuse duplicate priorities")
    choose_sort_direction("sort_order", 2)
    choose_sort_direction("sort_order", 1)
    secondary = sort_element("secondary_property")
    secondary.items = { { "bulk-imports.sort-default" } }
    secondary.tags = { sort_properties = { "default" } }
    secondary.selected_index = 1
    sort_element("secondary_sort_order").tags = { sort_direction = "ascending" }
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.sort-default-redundant")
    assert_same(original, section.filters, "Backend validation must refuse redundant secondary Default")
    choose_sort_direction("secondary_sort_order", 2)
    change_units(sort_element("property"), 0)
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.select-sort")
    assert_same(original, section.filters, "An invalid primary selection must not silently use a default")

    local chest = assert(surface.create_entity {
      name = "requester-chest", position = { 72, 40 }, force = player.force
    })
    local chest_section = assert(chest.get_requester_point().add_section("Secondary sort inventory limits"))
    chest_section.set_slot(1, { value = { name = "iron-plate", quality = "normal" }, min = 11, max = 22 })
    local chest_original = chest_section.filters
    player.set_controller { type = defines.controllers.remote, surface = surface, position = chest.position }
    open_requester(chest, defines.gui_type.entity)
    choose_section(chest_section)
    edit_option("sort", true)
    edit_option("edit_amounts", false)
    choose_property("property", "quality")
    assert(not has_property("secondary_property", "planet")
      and not has_property("secondary_property", "source") and not has_property("secondary_property", "payload"),
      "Platform-only properties leaked into another inventory's secondary sort")
    secondary = sort_element("secondary_property")
    secondary.items = { { "bulk-imports.sort-planet" } }
    secondary.tags = { sort_properties = { "planet" } }
    secondary.selected_index = 1
    click(panel.actions.apply)
    assert(panel.content.status.caption[1] == "bulk-imports.select-sort")
    assert_same(chest_original, chest_section.filters, "Secondary platform properties must be backend validated")
    log("BULK_IMPORT_TEST: independent sorting priorities, None, Default restrictions, omitted choices, stale GUI events, translated names, numeric units, final edits, layout and Undo")
  end
  exercise_secondary_sort()

  local function exercise_gui_event_guards()
    local owner = assert(surface.create_entity {
      name = "requester-chest", position = { 80, 40 }, force = player.force
    })
    local requester = owner.get_requester_point()
    local section = assert(requester.add_section("GUI event guard requests"))
    section.set_slot(1, { value = { name = "iron-plate", quality = "normal" }, min = 17, max = 50 })
    local original = section.filters
    player.set_controller { type = defines.controllers.remote, surface = surface, position = owner.position }
    open_requester(owner, defines.gui_type.entity)
    choose_mode("single")
    choose_section(section)
    edit_option("sort", false)
    edit_option("edit_amounts", true)
    edit_option("edit_quality", false)
    change_units(panel.content.amount_controls.requested_header.units, 2)
    enter_amount("requested", 2)
    enter_amount("trash_above", 4)
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "48")
    local removed_checkbox = checkbox_for(section)
    choose_placement(player.gui.screen[PANEL_NAME] == panel and "right" or "floating")
    assert(not removed_checkbox.valid)
    local outside = assert(requester.add_section("GUI guard pending reservation"))
    outside.set_slot(1, { value = { name = "stone", quality = "normal" }, min = prototypes.item.stone.stack_size })
    local outside_original = outside.filters
    local foreign_frame = player.gui.screen.add {
      type = "frame", name = "logistic_request_editor_guard_foreign", direction = "vertical"
    }
    local foreign = foreign_frame.add { type = "button", name = "foreign_button", caption = "Foreign GUI" }
    assert(foreign.get_mod() ~= panel.get_mod(), "The foreign GUI fixture must not be owned by the editor mod")
    local events = {
      defines.events.on_gui_click,
      defines.events.on_gui_checked_state_changed,
      defines.events.on_gui_selection_state_changed,
      defines.events.on_gui_elem_changed,
      defines.events.on_gui_value_changed,
      defines.events.on_gui_text_changed,
      defines.events.on_gui_confirmed,
      defines.events.on_gui_location_changed
    }
    for _, event in ipairs(events) do
      handlers[event] { player_index = player.index, button = defines.mouse_button_type.left }
      handlers[event] {
        player_index = player.index, element = removed_checkbox, button = defines.mouse_button_type.left
      }
      handlers[event] { player_index = player.index, element = foreign, button = defines.mouse_button_type.left }
      handlers[event] {
        player_index = player.index + 1000, element = panel.actions.apply, button = defines.mouse_button_type.left
      }
      assert_same(original, section.filters, "Ignored GUI events changed selected requests")
      assert(panel.content.amount_controls.requested.multiplier.text == "48",
        "Missing, stale, foreign or removed-player events must not refresh the editor")
    end
    foreign_frame.destroy()
    click(panel.content.amount_controls.share_actions.share_capacity)
    assert(panel.content.amount_controls.requested.multiplier.text == "47",
      "An owned GUI action stopped working after ignored events")
    assert_same(original, section.filters, "Recalculating the owned balance proposal applied requests")
    assert_same(outside_original, outside.filters, "GUI guards changed an unselected reservation")
    click(panel.content.amount_controls.share_actions.cancel_share)
    change_units(panel.content.amount_controls.requested_header.units, 1)
    handlers[defines.events.on_gui_click] {
      player_index = player.index, element = panel.actions.apply, button = defines.mouse_button_type.right
    }
    assert_same(original, section.filters, "Right-clicking Apply must not apply the proposal")
    click(panel.actions.apply)
    assert_amounts(section, 2, 4, "items")
    click(panel.actions.undo)
    assert_same(original, section.filters, "Apply and Undo must still work after ignored GUI events")
    log("BULK_IMPORT_TEST: shared GUI guards ignore missing/destroyed/foreign/deleted-player events; right clicks do not apply; owned actions and Undo still work")
  end
  exercise_gui_event_guards()

  log("BULK_IMPORT_TESTS_PASSED")
  script.finish_test(true)
end)
