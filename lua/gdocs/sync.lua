-- gdocs.nvim - Sync logic

local M = {}

local gdocs = require("gdocs")
local rpc = require("gdocs.rpc")
local buffer = require("gdocs.buffer")

-- Timers for each buffer
M._timers = {} -- bufnr -> timer
M._dirty = {} -- bufnr -> bool (has unsaved changes)
M._last_sync = {} -- bufnr -> timestamp

function M.push(bufnr)
  local doc_id = buffer.get_doc_id(bufnr)
  if not doc_id then
    gdocs.notify("Not a Google Docs buffer", vim.log.levels.WARN)
    return
  end

  local content = buffer.get_content(bufnr)
  buffer.set_sync_status(bufnr, "syncing")

  rpc.call("update", { doc_id = doc_id, markdown = content }, function(result, err)
    vim.schedule(function()
      if err then
        buffer.set_sync_status(bufnr, "error")
        gdocs.notify("Push error: " .. err, vim.log.levels.ERROR)
        return
      end

      if not result or not result.success then
        buffer.set_sync_status(bufnr, "error")
        gdocs.notify(result and result.error or "Push failed", vim.log.levels.ERROR)
        return
      end

      -- Update revision and mark as synced
      M._fetch_revision(bufnr, doc_id)
      vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
      buffer.set_sync_status(bufnr, "synced")
      M._dirty[bufnr] = false
      M._last_sync[bufnr] = vim.loop.now()

      gdocs.notify("Pushed to Google Docs")
    end)
  end)
end

function M.pull(bufnr)
  local doc_id = buffer.get_doc_id(bufnr)
  if not doc_id then
    gdocs.notify("Not a Google Docs buffer", vim.log.levels.WARN)
    return
  end

  buffer.set_sync_status(bufnr, "syncing")

  rpc.call("get", { doc_id = doc_id }, function(result, err)
    vim.schedule(function()
      if err then
        buffer.set_sync_status(bufnr, "error")
        gdocs.notify("Pull error: " .. err, vim.log.levels.ERROR)
        return
      end

      if not result or not result.success then
        buffer.set_sync_status(bufnr, "error")
        gdocs.notify(result and result.error or "Pull failed", vim.log.levels.ERROR)
        return
      end

      buffer.set_content(bufnr, result.content)
      buffer.set_revision(bufnr, result.revision)
      buffer.set_sync_status(bufnr, "synced")
      M._dirty[bufnr] = false
      M._last_sync[bufnr] = vim.loop.now()

      gdocs.notify("Pulled from Google Docs")
    end)
  end)
end

function M._fetch_revision(bufnr, doc_id)
  rpc.call("revision", { doc_id = doc_id }, function(result, err)
    vim.schedule(function()
      if result and result.success then
        buffer.set_revision(bufnr, result.revision)
      end
    end)
  end)
end

function M.check_remote_changes(bufnr, callback)
  local meta = buffer.get_metadata(bufnr)
  if not meta then
    callback(false)
    return
  end

  rpc.call("revision", { doc_id = meta.doc_id }, function(result, err)
    vim.schedule(function()
      if err or not result or not result.success then
        callback(false)
        return
      end

      local changed = result.revision ~= meta.revision
      callback(changed)
    end)
  end)
end

function M.start_timer(bufnr)
  if M._timers[bufnr] then
    return
  end

  local interval = gdocs.config.sync_interval
  if interval <= 0 then
    return
  end

  -- Track changes
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      M._dirty[bufnr] = true
    end,
    on_detach = function()
      M.stop_timer(bufnr)
    end,
  })

  local timer = vim.loop.new_timer()
  timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      M._auto_sync(bufnr)
    end)
  )

  M._timers[bufnr] = timer
end

function M.stop_timer(bufnr)
  local timer = M._timers[bufnr]
  if timer then
    timer:stop()
    timer:close()
    M._timers[bufnr] = nil
  end
end

function M._auto_sync(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    M.stop_timer(bufnr)
    return
  end

  -- Only sync if there are changes
  if not M._dirty[bufnr] then
    return
  end

  -- Debounce: don't sync if we just synced
  local last = M._last_sync[bufnr] or 0
  local now = vim.loop.now()
  if now - last < gdocs.config.sync_interval then
    return
  end

  M.push(bufnr)
end

return M
