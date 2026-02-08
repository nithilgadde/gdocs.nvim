local M = {}

local function get_gdocs() return require("gdocs") end

M._pending = {}
M._request_id = 0
M._job = nil
M._buffer = ""

function M.start_server()
  if M._job then
    return true
  end

  local gdocs = get_gdocs()
  local plugin_path = gdocs.get_plugin_path()
  local server_path = plugin_path .. "/python/gdocs_server.py"

  if vim.fn.filereadable(server_path) == 0 then
    gdocs.notify("Server script not found: " .. server_path, vim.log.levels.ERROR)
    return false
  end

  M._job = vim.fn.jobstart({ gdocs.config.python_cmd, server_path }, {
    on_stdout = function(_, data)
      M._on_stdout(data)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        get_gdocs().notify("Server error: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
      end
    end,
    on_exit = function(_, code)
      M._job = nil
      if code ~= 0 then
        get_gdocs().notify("Server exited with code: " .. code, vim.log.levels.WARN)
      end
    end,
    stdin = "pipe",
    stdout_buffered = false,
  })

  if M._job <= 0 then
    gdocs.notify("Failed to start server", vim.log.levels.ERROR)
    M._job = nil
    return false
  end

  return true
end

function M.stop_server()
  if M._job then
    vim.fn.jobstop(M._job)
    M._job = nil
  end
end

function M._on_stdout(data)
  if not data then
    return
  end

  for i, chunk in ipairs(data) do
    if chunk ~= "" then
      local ok, response = pcall(vim.json.decode, chunk)
      if ok and response then
        M._handle_response(response)
      else
        M._buffer = M._buffer .. chunk
        ok, response = pcall(vim.json.decode, M._buffer)
        if ok and response then
          M._handle_response(response)
          M._buffer = ""
        end
      end
    end
  end
end

function M._handle_response(response)
  local id = response.id
  if id and M._pending[id] then
    local callback = M._pending[id]
    M._pending[id] = nil

    if response.error then
      callback(nil, response.error.message or "Unknown error")
    else
      callback(response.result, nil)
    end
  end
end

function M.call(method, params, callback)
  if not M.start_server() then
    if callback then
      callback(nil, "Failed to start server")
    end
    return
  end

  M._request_id = M._request_id + 1
  local id = M._request_id

  local request = vim.json.encode({
    id = id,
    method = method,
    params = params or {},
  })

  if callback then
    M._pending[id] = callback
  end

  vim.fn.chansend(M._job, request .. "\n")
end

function M.call_sync(method, params, timeout_ms)
  timeout_ms = timeout_ms or 10000

  local result = nil
  local err = nil
  local done = false

  M.call(method, params, function(r, e)
    result = r
    err = e
    done = true
  end)

  local start = vim.loop.now()
  while not done do
    vim.wait(10, function()
      return done
    end)
    if vim.loop.now() - start > timeout_ms then
      err = "Timeout waiting for response"
      break
    end
  end

  return result, err
end

return M
