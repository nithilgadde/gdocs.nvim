-- gdocs.nvim - Health check

local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

function M.check()
  start("gdocs.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.8") == 1 then
    ok("Neovim >= 0.8")
  else
    error("Neovim >= 0.8 required")
  end

  -- Check Python
  local gdocs = require("gdocs")
  local python_cmd = gdocs.config.python_cmd

  if vim.fn.executable(python_cmd) == 1 then
    ok(python_cmd .. " is executable")

    -- Check Python version
    local handle = io.popen(python_cmd .. " --version 2>&1")
    if handle then
      local result = handle:read("*a")
      handle:close()
      ok("Python version: " .. vim.trim(result))
    end
  else
    error(python_cmd .. " not found in PATH")
  end

  -- Check dependencies
  local check_module = python_cmd .. " -c 'import %s' 2>&1"

  local modules = {
    "google.oauth2.credentials",
    "google_auth_oauthlib.flow",
    "googleapiclient.discovery",
  }

  for _, mod in ipairs(modules) do
    local cmd = string.format(check_module, mod)
    local result = vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
      ok(mod .. " is installed")
    else
      error(mod .. " not found. Run: pip install -r python/requirements.txt")
    end
  end

  -- Check credentials file
  local plugin_path = gdocs.get_plugin_path()
  local rpc = require("gdocs.rpc")

  rpc.call("data_dir", {}, function(result, err)
    vim.schedule(function()
      if result and result.path then
        local creds_path = result.path .. "/credentials.json"
        if vim.fn.filereadable(creds_path) == 1 then
          ok("credentials.json found")
        else
          warn("credentials.json not found at: " .. creds_path)
          warn("Download OAuth credentials from Google Cloud Console")
        end

        local token_path = result.path .. "/token.json"
        if vim.fn.filereadable(token_path) == 1 then
          ok("token.json found (authenticated)")
        else
          warn("Not authenticated. Run :GDocsAuth after setting up credentials")
        end
      end
    end)
  end)

  -- Check optional dependencies
  if pcall(require, "telescope") then
    ok("telescope.nvim available")
  else
    warn("telescope.nvim not found (optional, using native picker)")
  end

  if pcall(require, "fzf-lua") then
    ok("fzf-lua available")
  else
    warn("fzf-lua not found (optional)")
  end
end

return M
