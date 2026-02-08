local M = {}

M.config = {
  sync_interval = 5000,
  notify = true,
  python_cmd = "python3",
  picker = "native",
}

M._state = {
  initialized = false,
  server_job = nil,
  buffers = {},
  revisions = {},
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  require("gdocs.commands").setup()
  M._setup_autocommands()
  M._state.initialized = true
end

function M._setup_autocommands()
  local group = vim.api.nvim_create_augroup("GDocs", { clear = true })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    pattern = "gdocs://*",
    callback = function(ev)
      require("gdocs.sync").push(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    pattern = "gdocs://*",
    callback = function(ev)
      require("gdocs.buffer").on_delete(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "gdocs://*",
    callback = function(ev)
      if M.config.sync_interval > 0 then
        require("gdocs.sync").start_timer(ev.buf)
      end
    end,
  })

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
