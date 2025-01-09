-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- Check the operating system using WezTerm's built-in API
local os_name = wezterm.os

if os_name == "Darwin" then
  -- macOS specific configuration
elseif os_name == "Linux" then
  -- Further check for specific Linux distributions
  local handle = io.popen("cat /etc/os-release")
  local os_info = handle:read("*a")
  handle:close()

  if os_info:match("Ubuntu") then
    -- Ubuntu specific configuration
    if os.getenv("WSL_DISTRO_NAME") then
      -- WSL Ubuntu specific configuration
    else
      -- Native Ubuntu configuration
    end
  elseif os_info:match("Kali") then
    -- Kali Linux specific configuration
  end
elseif os_name == "Windows" then
  -- Windows Terminal specific configuration
end

-- Apply the basic configuration settings

config.font = wezterm.font("MesloLGS Nerd Font Mono")
config.font_size = 16

config.enable_tab_bar = false

config.window_decorations = "RESIZE"
config.window_background_opacity = 0.9
config.macos_window_background_blur = 20

-- my coolnight colorscheme:
config.colors = {
  foreground = "#CBE0F0",
  background = "#011423",
  cursor_bg = "#47FF9C",
  cursor_border = "#47FF9C",
  cursor_fg = "#011423",
  selection_bg = "#033259",
  selection_fg = "#CBE0F0",
  ansi = { "#214969", "#E52E2E", "#44FFB1", "#FFE073", "#0FC5ED", "#a277ff", "#24EAF7", "#24EAF7" },
  brights = { "#214969", "#E52E2E", "#44FFB1", "#FFE073", "#A277FF", "#a277ff", "#24EAF7", "#24EAF7" },
}

-- Finally, return the configuration to wezterm
return config
