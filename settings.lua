local prefix = "first-factorio-mod-"
local definitions = {
  { type = "bool-setting", name = prefix .. "show-editor", default_value = true, order = "a-a" },
  {
    type = "string-setting", name = prefix .. "placement", default_value = "right",
    allowed_values = { "right", "left", "top", "bottom", "floating" }, order = "a-b"
  },
  { type = "bool-setting", name = prefix .. "floating-locked", default_value = false, order = "a-c" },
  { type = "bool-setting", name = prefix .. "remember-position", default_value = true, order = "a-d" },
  {
    type = "string-setting", name = prefix .. "default-selection", default_value = "single",
    allowed_values = { "single", "multiple" }, order = "b-a"
  },
  {
    type = "string-setting", name = prefix .. "default-units", default_value = "stacks",
    allowed_values = { "items", "stacks" }, order = "b-b"
  },
  {
    type = "string-setting", name = prefix .. "default-requested-mode", default_value = "custom",
    allowed_values = { "custom", "max" }, order = "b-c-a"
  },
  {
    type = "int-setting", name = prefix .. "default-requested", default_value = 1,
    minimum_value = 0, maximum_value = 2147483647, order = "b-c-b"
  },
  {
    type = "string-setting", name = prefix .. "default-chest-requested-mode", default_value = "max",
    allowed_values = { "custom", "max" }, order = "b-c-c"
  },
  {
    type = "int-setting", name = prefix .. "default-chest-requested", default_value = 1,
    minimum_value = 0, maximum_value = 2147483647, order = "b-c-d"
  },
  {
    type = "string-setting", name = prefix .. "default-maximum", default_value = "inf.",
    allow_blank = false, order = "b-d"
  },
  {
    type = "string-setting", name = prefix .. "default-payload-units", default_value = "stacks",
    allowed_values = { "items", "stacks" }, order = "b-e"
  },
  {
    type = "string-setting", name = prefix .. "default-payload", default_value = "1",
    allow_blank = false, order = "b-f"
  },
  {
    type = "string-setting", name = prefix .. "sort", default_value = "enabled",
    allowed_values = { "enabled", "disabled", "hidden" }, order = "c-a"
  },
  {
    type = "bool-setting", name = prefix .. "default-clear-empty-slots", default_value = true,
    order = "c-a-b"
  },
  {
    type = "string-setting", name = prefix .. "edit-filters", default_value = "enabled",
    allowed_values = { "enabled", "disabled", "hidden" }, order = "c-b"
  },
  {
    type = "string-setting", name = prefix .. "edit-platform-amounts", default_value = "enabled",
    allowed_values = { "enabled", "disabled", "hidden" }, order = "c-c"
  },
  {
    type = "string-setting", name = prefix .. "edit-other-amounts", default_value = "enabled",
    allowed_values = { "enabled", "disabled", "hidden" }, order = "c-d"
  },
  {
    type = "string-setting", name = prefix .. "edit-quality", default_value = "disabled",
    allowed_values = { "enabled", "disabled", "hidden" }, order = "c-e"
  },
  {
    type = "string-setting", name = prefix .. "edit-payload", default_value = "disabled",
    allowed_values = { "enabled", "disabled", "hidden" }, order = "c-f"
  },
  { type = "bool-setting", name = prefix .. "default-edit-filters", default_value = true, hidden = true },
  { type = "bool-setting", name = prefix .. "default-platform-amounts", default_value = true, hidden = true },
  { type = "bool-setting", name = prefix .. "default-other-amounts", default_value = true, hidden = true },
  { type = "bool-setting", name = prefix .. "default-edit-quality", default_value = false, hidden = true },
  { type = "bool-setting", name = prefix .. "default-edit-payload", default_value = false, hidden = true },
  {
    type = "string-setting", name = prefix .. "quality-range-behavior", default_value = "set-to-zero",
    allowed_values = { "prevent", "set-to-zero" }, order = "d-a"
  },
  {
    type = "int-setting", name = prefix .. "confirmation-seconds", default_value = 5,
    minimum_value = 1, order = "d-b"
  }
}

for _, definition in ipairs(definitions) do
  definition.setting_type = "runtime-per-user"
end
data:extend(definitions)
