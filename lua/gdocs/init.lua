-- gdocs.nvim - Edit Google Docs in Neovim
-- Main entry point

local M = {}

M.config = {
  -- Auto-sync interval in milliseconds (0 to disable)
  sync_interval = 5000,
  -- Show notifications
  notify = true,
  -- Python executable
  python_cmd = "python3",
  -- Picker: "telescope", "fzf", or "native"
  picker = "native",
}

-- Internal state
M._state = {
  initialized = false,
  server_job = nil,
  buffers = {}, -- doc_id -> bufnr mapping
  revisions = {}, -- doc_id -> last known revision
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Register commands
  require("gdocs.commands").setup()

  -- Set up autocommands
  M._setup_autocommands()

  M._state.initialized = true
end

function M._setup_autocommands()
  local group = vim.api.nvim_create_augroup("GDocs", { clear = true })

  -- Auto-sync on buffer write
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    pattern = "gdocs://*",
    callback = function(ev)
      require("gdocs.sync").push(ev.buf)
    end,
  })

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    pattern = "gdocs://*",
    callback = function(ev)
      require("gdocs.buffer").on_delete(ev.buf)
    end,
  })

  -- Start auto-sync timer when entering a gdocs buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "gdocs://*",
    callback = function(ev)
      if M.config.sync_interval > 0 then
        require("gdocs.sync").start_timer(ev.buf)
      end
    end,
  })

  -- Stop auto-sync timer when leaving a gdocs buffer
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    pattern = "gdocs://*",
    callback = function(ev)
      require("gdocs.sync").stop_timer(ev.buf)
    end,
  })
end

function M.notify(msg, level)
  if M.config.notify then
    vim.notify("[GDocs] " .. msg, level or vim.log.levels.INFO)
  end
end

function M.get_plugin_path()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h")
end

return M
