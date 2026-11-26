local bootstrap = script
local handlers = {}
local initialize
local configure

script = {
  on_init = function(handler) initialize = handler end,
  on_configuration_changed = function(handler) configure = handler end,
  on_event = function(events, handler)
    if type(events) == "table" then
      for _, event in ipairs(events) do
        handlers[event] = handler
      end
    else
      handlers[events] = handler
    end
  end
}
require("editor")
script = bootstrap

-- Dispatch in the real mod context so writes to its own user settings are authorized.
remote.add_interface("first-factorio-mod-tests", {
  initialize = function() initialize() end,
  configure = function() configure({}) end,
  dispatch = function(event, data)
    assert(handlers[event], "Missing editor event handler: " .. tostring(event))(data)
  end,
  get_preferences = function(player_index)
    return storage.bulk_import_preferences[player_index]
  end,
  set_preference = function(player_index, key, value)
    storage.bulk_import_preferences[player_index][key] = value
  end,
  get_deadline = function(player_index)
    return storage.bulk_import_panels[player_index].status_expires_at
  end,
  set_deadline = function(player_index, value)
    storage.bulk_import_panels[player_index].status_expires_at = value
  end,
  get_pending_translations = function(player_index)
    local state = storage.bulk_import_panels[player_index]
    return state and state.sort_names and state.sort_names.pending or {}
  end,
  set_setting = function(player_index, name, value)
    settings.get_player_settings(player_index)[name] = { value = value }
    if handlers[defines.events.on_runtime_mod_setting_changed] then
      handlers[defines.events.on_runtime_mod_setting_changed] {
        player_index = player_index,
        setting = name,
        setting_type = "runtime-per-user"
      }
    end
  end
})
