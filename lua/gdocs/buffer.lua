local M = {}

local function get_gdocs() return require("gdocs") end

M._buffers = {}
M._doc_buffers = {}

function M.create(doc_id, title, content, revision)
  if M._doc_buffers[doc_id] then
    local existing_bufnr = M._doc_buffers[doc_id]
    if vim.api.nvim_buf_is_valid(existing_bufnr) then
      vim.api.nvim_set_current_buf(existing_bufnr)
      return existing_bufnr
    end
  end

  local bufname = "gdocs://" .. doc_id
  local bufnr = vim.fn.bufnr(bufname, true)

  vim.api.nvim_buf_set_name(bufnr, bufname)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })

  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.api.nvim_set_option_value("modified", false, { buf = bufnr })

  M._buffers[bufnr] = {
    doc_id = doc_id,
    title = title,
    revision = revision,
  }
  M._doc_buffers[doc_id] = bufnr

  vim.api.nvim_buf_set_var(bufnr, "gdocs_title", title)
  vim.api.nvim_buf_set_var(bufnr, "gdocs_id", doc_id)
  vim.api.nvim_buf_set_var(bufnr, "gdocs_sync_status", "synced")

  vim.api.nvim_set_current_buf(bufnr)

  return bufnr
end

function M.get_doc_id(bufnr)
  local meta = M._buffers[bufnr]
  return meta and meta.doc_id or nil
end

function M.get_metadata(bufnr)
  return M._buffers[bufnr]
end

function M.set_revision(bufnr, revision)
  local meta = M._buffers[bufnr]
  if meta then
    meta.revision = revision
  end
end

function M.set_sync_status(bufnr, status)
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_set_var, bufnr, "gdocs_sync_status", status)
  end
end

function M.get_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.set_content(bufnr, content)
  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
end

function M.on_delete(bufnr)
  local meta = M._buffers[bufnr]
  if meta then
    M._doc_buffers[meta.doc_id] = nil
    M._buffers[bufnr] = nil
  end

  require("gdocs.sync").stop_timer(bufnr)
end

function M.is_gdocs_buffer(bufnr)
  return M._buffers[bufnr] ~= nil
end

return M
