local util = require('vim.lsp.util')
local api = vim.api
local M = {}

local links_by_buf = {}

local augroup = api.nvim_create_augroup('icholy/nvim-lsplinks', {})

local function get_cursor_pos()
  local cursor = api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1 -- adjust line number for 0-indexing
  local character = vim.lsp.util.character_offset(0, line, cursor[2], "utf-8")
  return { line = line, character = character }
end

local function in_range(pos, range)
  if pos.line > range.start.line and pos.line < range['end'].line then
    return true
  elseif pos.line == range.start.line and pos.line == range['end'].line then
    return pos.character >= range.start.character and pos.character <= range['end'].character
  elseif pos.line == range.start.line then
    return pos.character >= range.start.character
  elseif pos.line == range['end'].line then
    return pos.character <= range['end'].character
  else
    return false
  end
end

local function lsp_has_capability(name)
  for _, client in ipairs(vim.lsp.buf_get_clients()) do
    local capabilities = client.server_capabilities
    if capabilities[name] then
      return true
    end
  end
  return false
end

local function jump_to_target(target)
  local file_uri, line_no, col_no = target:match('(file://.-)#(%d+),(%d+)')
  if file_uri then
    vim.lsp.util.jump_to_location({ uri = file_uri }, "utf-8", true)
    api.nvim_win_set_cursor(0, { tonumber(line_no), tonumber(col_no) - 1 })
  end
end

local function resolve_bufnr(bufnr)
  return bufnr == 0 and api.nvim_get_current_buf() or bufnr
end

function M.setup()
  api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = M.refresh
  })
  api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = M.refresh
  })
  api.nvim_create_autocmd("LspAttach", {
    group = augroup,
    callback = M.refresh
  })
end

function M.jump()
  local cursor = get_cursor_pos()
  for _, link in ipairs(M.get(0)) do
    if in_range(cursor, link.range) then
      jump_to_target(link.target)
      return true
    end
  end
  return false
end

function M.refresh()
  if not lsp_has_capability("documentLinkProvider") then
    return
  end
  local params = { textDocument = util.make_text_document_params() }
  vim.lsp.buf_request(0, "textDocument/documentLink", params, function(err, result, ctx)
    if err then
      api.nvim_err_writeln(err.message)
      return
    end
    M.save(result, ctx.bufnr)
  end)
end

function M.save(links, bufnr)
  if not links_by_buf[bufnr] then
    api.nvim_buf_attach(bufnr, false, {
      on_detach = function(b)
        links_by_buf[b] = nil
      end
    })
  end
  links_by_buf[bufnr] = links
end

function M.get(bufnr)
  bufnr = resolve_bufnr(bufnr or 0)
  return links_by_buf[bufnr] or {}
end

return M
