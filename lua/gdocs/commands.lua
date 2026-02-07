-- gdocs.nvim - User commands

local M = {}

local gdocs = require("gdocs")
local rpc = require("gdocs.rpc")
local buffer = require("gdocs.buffer")

function M.setup()
  vim.api.nvim_create_user_command("GDocsAuth", M.auth, {
    desc = "Authenticate with Google",
  })

  vim.api.nvim_create_user_command("GDocsList", M.list, {
    desc = "List Google Docs",
  })

  vim.api.nvim_create_user_command("GDocsOpen", M.open, {
    nargs = "?",
    desc = "Open a Google Doc by ID",
  })

  vim.api.nvim_create_user_command("GDocsNew", M.new, {
    nargs = "?",
    desc = "Create a new Google Doc",
  })

  vim.api.nvim_create_user_command("GDocsPush", M.push, {
    desc = "Push current buffer to Google Docs",
  })

  vim.api.nvim_create_user_command("GDocsPull", M.pull, {
    desc = "Pull latest from Google Docs",
  })

  vim.api.nvim_create_user_command("GDocsInfo", M.info, {
    desc = "Show data directory info",
  })
end

function M.auth()
  gdocs.notify("Starting authentication...")

  rpc.call("auth", {}, function(result, err)
    vim.schedule(function()
      if err then
        gdocs.notify("Auth error: " .. err, vim.log.levels.ERROR)
      elseif result and result.success then
        gdocs.notify(result.message or "Authenticated!")
      else
        gdocs.notify(result and result.error or "Authentication failed", vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.list()
  rpc.call("is_authenticated", {}, function(result, err)
    vim.schedule(function()
      if err or not result or not result.authenticated then
        gdocs.notify("Not authenticated. Run :GDocsAuth first.", vim.log.levels.WARN)
        return
      end
      M._fetch_and_show_list()
    end)
  end)
end

function M._fetch_and_show_list()
  gdocs.notify("Fetching documents...")

  rpc.call("list", { max_results = 50 }, function(result, err)
    vim.schedule(function()
      if err then
        gdocs.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      if not result or not result.success then
        gdocs.notify(result and result.error or "Failed to list documents", vim.log.levels.ERROR)
        return
      end

      local docs = result.documents or {}
      if #docs == 0 then
        gdocs.notify("No documents found")
        return
      end

      M._show_picker(docs)
    end)
  end)
end

function M._show_picker(docs)
  local picker = gdocs.config.picker

  if picker == "telescope" and pcall(require, "telescope") then
    M._telescope_picker(docs)
  elseif picker == "fzf" and pcall(require, "fzf-lua") then
    M._fzf_picker(docs)
  else
    M._native_picker(docs)
  end
end

function M._native_picker(docs)
  local items = {}
  for i, doc in ipairs(docs) do
    table.insert(items, string.format("%d. %s", i, doc.name))
  end

  vim.ui.select(items, {
    prompt = "Select a Google Doc:",
  }, function(choice, idx)
    if idx then
      M._open_doc(docs[idx].id)
    end
  end)
end

function M._telescope_picker(docs)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Google Docs",
      finder = finders.new_table({
        results = docs,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.name,
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            M._open_doc(selection.value.id)
          end
        end)
        return true
      end,
    })
    :find()
end

function M._fzf_picker(docs)
  local fzf = require("fzf-lua")

  local items = {}
  local lookup = {}
  for _, doc in ipairs(docs) do
    table.insert(items, doc.name)
    lookup[doc.name] = doc.id
  end

  fzf.fzf_exec(items, {
    prompt = "Google Docs> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local doc_id = lookup[selected[1]]
          if doc_id then
            M._open_doc(doc_id)
          end
        end
      end,
    },
  })
end

function M._open_doc(doc_id)
  gdocs.notify("Opening document...")

  rpc.call("get", { doc_id = doc_id }, function(result, err)
    vim.schedule(function()
      if err then
        gdocs.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      if not result or not result.success then
        gdocs.notify(result and result.error or "Failed to open document", vim.log.levels.ERROR)
        return
      end

      buffer.create(result.id, result.title, result.content, result.revision)
      gdocs.notify("Opened: " .. result.title)
    end)
  end)
end

function M.open(opts)
  local doc_id = opts.args

  if not doc_id or doc_id == "" then
    -- If no ID provided, show list
    M.list()
    return
  end

  M._open_doc(doc_id)
end

function M.new(opts)
  local title = opts.args

  if not title or title == "" then
    vim.ui.input({ prompt = "Document title: " }, function(input)
      if input and input ~= "" then
        M._create_doc(input)
      end
    end)
  else
    M._create_doc(title)
  end
end

function M._create_doc(title)
  gdocs.notify("Creating document...")

  rpc.call("create", { title = title }, function(result, err)
    vim.schedule(function()
      if err then
        gdocs.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      if not result or not result.success then
        gdocs.notify(result and result.error or "Failed to create document", vim.log.levels.ERROR)
        return
      end

      buffer.create(result.id, result.title, "", "")
      gdocs.notify("Created: " .. result.title)
    end)
  end)
end

function M.push()
  local bufnr = vim.api.nvim_get_current_buf()
  require("gdocs.sync").push(bufnr)
end

function M.pull()
  local bufnr = vim.api.nvim_get_current_buf()
  require("gdocs.sync").pull(bufnr)
end

function M.info()
  gdocs.notify("Calling data_dir...")
  rpc.call("data_dir", {}, function(result, err)
    vim.schedule(function()
      gdocs.notify("Got response")
      if err then
        gdocs.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      if result and result.path then
        gdocs.notify("Data directory: " .. result.path)
        gdocs.notify("Place your credentials.json file there")
      else
        gdocs.notify("No result returned", vim.log.levels.WARN)
      end
    end)
  end)
end

return M
