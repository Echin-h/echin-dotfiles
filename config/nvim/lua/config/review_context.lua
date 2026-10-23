-- Context stays in the review tab; only explicit Open enters reading history.
local M = {}
local states = {}
local api = vim.api
local ns = api.nvim_create_namespace("MateReviewContext")

local function notice(text)
  vim.notify(text, vim.log.levels.INFO, { title = "Review 上下文" })
end

local function valid(win)
  return win and api.nvim_win_is_valid(win)
end

local function escape(text)
  return (text:gsub("%%", "%%%%"):gsub("[\r\n]", " "))
end

local function current()
  return states[api.nvim_get_current_tabpage()]
end

local function origin()
  local state = current()
  local win = api.nvim_get_current_win()
  if state and (win == state.list_win or win == state.preview_win) then
    if win == state.preview_win then
      local point = require("config.navigation").position()
      return state.source, require("config.review_navigation").context(point.buf), point
    end
    return state.source, state.context
  end
  local source = require("config.navigation").position()
  local review = require("config.review_navigation")
  local context = review.context(source.buf)
  if not context and vim.bo[source.buf].buftype ~= "" then
    local lib = package.loaded["diffview.lib"]
    local view = lib and lib.get_current_view()
    local win = vim.t.mate_review_code_win
    local pane_win = false
    if view and view.cur_layout then
      for _, pane in ipairs(view.cur_layout.windows) do
        if pane.id == win then
          pane_win = true
        end
      end
      if not pane_win then
        win = view.cur_layout.b.id
      end
    end
    if valid(win) and api.nvim_win_get_tabpage(win) == api.nvim_get_current_tabpage() then
      source = api.nvim_win_call(win, require("config.navigation").position)
      context = review.context(source.buf)
    end
  end
  return source, context
end

local function state_for(source, context)
  local tab = api.nvim_win_get_tabpage(source.win)
  local state = states[tab]
  if not state then
    state = { tab = tab }
    states[tab] = state
  end
  state.source, state.context = source, context
  return state
end

local function cancel(state)
  state.token = nil
  if state.cancel then
    state.cancel()
    state.cancel = nil
  end
end

function M.close(restore)
  local state = current()
  if not state then
    return false
  end
  cancel(state)
  local had_drawer = valid(state.list_win) or valid(state.preview_win)
  if valid(state.preview_win) then
    state.width = api.nvim_win_get_width(state.preview_win)
  end
  state.closing = true
  for _, key in ipairs({ "preview_win", "list_win" }) do
    if valid(state[key]) then
      api.nvim_win_close(state[key], true)
    end
    state[key] = nil
  end
  state.closing = false
  if state.restore_panel and state.panel then
    state.restore_panel = nil
    state.panel:open()
  end
  if restore ~= false and had_drawer and valid(state.source.win) then
    api.nvim_set_current_win(state.source.win)
    if api.nvim_win_get_buf(state.source.win) == state.source.buf then
      api.nvim_win_set_cursor(state.source.win, state.source.cursor)
      vim.fn.winrestview(state.source.view)
    end
  end
  return had_drawer
end

function M.focused()
  local state = current()
  local win = api.nvim_get_current_win()
  return state and (win == state.list_win or win == state.preview_win) or false
end
function M.dismiss()
  if M.focused() then
    return M.close()
  end
  return false
end

local function scope(buf, line, col)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return
  end
  local parsed, trees = pcall(parser.parse, parser)
  if not parsed or not trees[1] then
    return
  end
  local node = trees[1]:root():named_descendant_for_range(line, col, line, col)
  while node do
    local kind = node:type()
    if kind:find("function") or kind:find("method") then
      local names = node:field("name")
      if #names > 0 then
        return vim.treesitter.get_node_text(names[1], buf)
      end
      local parent = node:parent()
      if parent and parent:type() == "variable_declarator" then
        names = parent:field("name")
        if #names > 0 then
          return vim.treesitter.get_node_text(names[1], buf)
        end
      end
    end
    node = node:parent()
  end
end

local function relative(buf, snapshot)
  return api.nvim_buf_get_name(buf):sub(#snapshot.dir + 2)
end

local function location_buf(item)
  local uri = item.location.uri or item.location.targetUri
  local buf = vim.uri_to_bufnr(uri)
  if not api.nvim_buf_is_loaded(buf) then
    -- Tag before FileType/BufRead so autosave and live LSP cannot claim it.
    vim.b[buf].mate_review_snapshot = item.snapshot
    vim.b[buf].autoformat = false
    vim.fn.bufload(buf)
  end
  require("config.review_navigation").mark(buf, item.snapshot)
  return buf
end

local function selection(state)
  if not valid(state.list_win) then
    return state.selected
  end
  return state.rows and state.rows[api.nvim_win_get_cursor(state.list_win)[1]]
end

function M.preview()
  local state = current()
  local item = state and selection(state)
  if not item or not valid(state.preview_win) then
    return
  end
  local buf = location_buf(item)
  local range = item.location.targetSelectionRange or item.location.range
  local line = api.nvim_buf_get_lines(buf, range.start.line, range.start.line + 1, false)[1] or ""
  local col = vim.str_byteindex(line, item.encoding or "utf-8", range.start.character, false)
  state.selected = item
  api.nvim_win_set_buf(state.preview_win, buf)
  api.nvim_win_set_cursor(state.preview_win, { range.start.line + 1, col })
  api.nvim_win_call(state.preview_win, function()
    vim.cmd("normal! zz")
  end)
  local label = relative(buf, item.snapshot) .. ":" .. (range.start.line + 1)
  vim.wo[state.preview_win].winbar = "%@v:lua.MateReviewContextClose@ 关闭预览 %X%@v:lua.MateReviewContextOpen@ 打开阅读 %X"
    .. " "
    .. item.snapshot.revision:sub(1, 8)
    .. " %<"
    .. escape(label)
  vim.keymap.set("n", "<CR>", function()
    if vim.w.mate_review_preview then
      M.open()
    else
      vim.cmd.normal({ args = { "\r" }, bang = true })
    end
  end, { buffer = buf, desc = "打开阅读" })
  vim.wo[state.preview_win].cursorline = true
end

function M.open()
  local state = current()
  local item = state and state.selected
  if not item then
    return
  end
  local source = state.source
  if api.nvim_get_current_win() == state.preview_win then
    item = vim.deepcopy(item)
    local cursor = api.nvim_win_get_cursor(state.preview_win)
    item.location = {
      uri = vim.uri_from_bufnr(api.nvim_win_get_buf(state.preview_win)),
      range = {
        start = { line = cursor[1] - 1, character = cursor[2] },
        ["end"] = {
          line = cursor[1] - 1,
          character = cursor[2],
        },
      },
    }
    item.encoding = "utf-8"
  end
  M.close()
  require("config.navigation").open_location(item.location, item.snapshot, source, item.encoding)
end

function M.reveal()
  local state = current()
  if not state or not state.selected then
    return
  end
  local item = state.selected
  local buf = location_buf(item)
  require("config.review_tree").open({
    root = item.snapshot.root,
    revision = item.snapshot.revision,
    path = relative(buf, item.snapshot),
  }, state.source)
end

local function drawer(state, title, items)
  M.close(false)
  if not valid(state.source.win) or api.nvim_get_current_tabpage() ~= state.tab then
    return
  end
  state.items, state.rows = items, {}
  local lines, previous = {}, nil
  for _, item in ipairs(items) do
    local buf = location_buf(item)
    local range = item.location.targetSelectionRange or item.location.range
    local path = relative(buf, item.snapshot)
    if path ~= previous then
      lines[#lines + 1] = " " .. path
      state.rows[#lines] = item
      previous = path
    end
    local text = api.nvim_buf_get_lines(buf, range.start.line, range.start.line + 1, false)[1] or ""
    local col = vim.str_byteindex(text, item.encoding or "utf-8", range.start.character, false)
    local name = item.label or scope(buf, range.start.line, col)
    lines[#lines + 1] = ("   %d  %s%s"):format(
      range.start.line + 1,
      name and (name .. " · ") or "",
      vim.trim(text):sub(1, 180)
    )
    state.rows[#lines] = item
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "mate_review_context"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  require("config.review_commits").close(false)
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  if vim.o.columns < 110 and view and view.panel:is_open() then
    state.panel, state.restore_panel = view.panel, true
    view.panel:close()
  end
  api.nvim_set_current_win(state.source.win)
  local width = state.width or math.floor(vim.o.columns * 0.36)
  width = math.max(32, math.min(width, math.floor(vim.o.columns * (vim.o.columns < 110 and 0.36 or 0.55))))
  vim.cmd("botright " .. width .. "vsplit")
  state.preview_win = api.nvim_get_current_win()
  -- A split inherits the source pane's diff bindings. Clear them before
  -- replacing its buffer, otherwise even a transient preview moves the diff.
  vim.wo[state.preview_win].diff = false
  vim.wo[state.preview_win].scrollbind = false
  vim.wo[state.preview_win].cursorbind = false
  api.nvim_win_set_var(state.preview_win, "mate_review_preview", true)
  local file_preview = title == "文件预览"
  if not file_preview then
    local height = math.max(4, math.min(10, math.floor(vim.o.lines / 4)))
    vim.cmd("aboveleft " .. height .. "split")
    state.list_win = api.nvim_get_current_win()
    vim.w.mate_review_preview = false
    api.nvim_win_set_buf(state.list_win, buf)
  end
  for _, win in ipairs({ state.preview_win, state.list_win }) do
    for key, value in pairs({
      diff = false,
      scrollbind = false,
      cursorbind = false,
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      winfixwidth = true,
    }) do
      vim.wo[win][key] = value
    end
  end
  vim.wo[state.preview_win].number = true
  if file_preview then
    state.selected = items[1]
    api.nvim_buf_delete(buf, { force = true })
    M.preview()
  else
    vim.wo[state.list_win].cursorline = true
    vim.wo[state.list_win].winfixheight = true
    vim.wo[state.list_win].winbar = "%@v:lua.MateReviewContextClose@ 关闭预览 %X "
      .. escape(title)
      .. " "
      .. #items
      .. " · "
      .. state.context.revision:sub(1, 8)
      .. "%<"
    local map = function(key, fn)
      vim.keymap.set("n", key, fn, { buffer = buf, silent = true, nowait = true })
    end
    map("<CR>", M.open)
    map("o", M.open)
    map("t", M.reveal)
    map("q", M.close)
    map("<Esc>", M.close)
    map("<LeftRelease>", M.preview)
    map("<2-LeftMouse>", M.open)
    api.nvim_create_autocmd("CursorMoved", {
      buffer = buf,
      callback = function()
        if current() == state then
          M.preview()
        end
      end,
    })
    for index, text in ipairs(lines) do
      if text:sub(1, 2) ~= "  " then
        api.nvim_buf_add_highlight(buf, ns, "Directory", index - 1, 0, -1)
      end
    end
    api.nvim_win_set_cursor(state.list_win, { math.min(2, #lines), 0 })
    M.preview()
  end
  M.resize()
  -- Diffview may finish reattaching its panes while the LSP request is in
  -- flight. Restore the query's reading position after the drawer is laid out.
  if valid(state.source.win) and api.nvim_win_get_buf(state.source.win) == state.source.buf then
    api.nvim_win_call(state.source.win, function()
      api.nvim_win_set_cursor(state.source.win, state.source.cursor)
      vim.fn.winrestview(state.source.view)
    end)
  end
end

-- Public seam also used by directory browsing. All locations must be in snapshot.
function M.show(source, context, title, items)
  local filtered = {}
  for _, item in ipairs(items) do
    if require("config.review_navigation").valid_location(item.location, item.snapshot) then
      filtered[#filtered + 1] = item
    end
  end
  if #filtered == 0 then
    notice("该版本没有可显示的结果")
    return
  end
  local state = state_for(source, context)
  drawer(state, title, filtered)
end

function M.resize()
  local state = current()
  if state and valid(state.preview_win) then
    local width = api.nvim_win_get_width(state.preview_win)
    local maximum = math.max(32, math.floor(vim.o.columns * (vim.o.columns < 110 and 0.36 or 0.55)))
    if width > maximum then
      api.nvim_win_set_width(state.preview_win, maximum)
    end
    local lib = package.loaded["diffview.lib"]
    local view = lib and lib.get_current_view()
    if view and vim.o.columns < 110 and view.panel:is_open() then
      state.panel, state.restore_panel = view.panel, true
      view.panel:close()
    elseif state.restore_panel and state.panel and vim.o.columns >= 110 then
      state.restore_panel = nil
      state.panel:open()
    end
    local layout = view and view.cur_layout
    local a, b = layout and layout.a and layout.a.id, layout and layout.b and layout.b.id
    if valid(a) and valid(b) then
      local diff_width = api.nvim_win_get_width(a) + api.nvim_win_get_width(b)
      api.nvim_win_set_width(a, math.floor(diff_width / 2))
    end
  end
end

local function query(method, params, callback)
  local source, context, point = origin()
  if not context then
    return false
  end
  M.close(false)
  local state = state_for(source, context)
  cancel(state)
  local token = {}
  state.token = token
  local function active()
    return state.token == token
      and valid(source.win)
      and api.nvim_win_get_buf(source.win) == source.buf
      and api.nvim_get_current_tabpage() == state.tab
  end
  state.cancel = require("config.review_navigation").prepare(context, point or source, function(err, prepared)
    if not active() then
      if state.token == token then
        cancel(state)
      end
      return
    end
    if err then
      cancel(state)
      notice(err)
      return
    end
    local client = prepared.client
    if not client:supports_method(method, prepared.buf) then
      cancel(state)
      notice("该语言服务不支持此项查询")
      return
    end
    local request_params = params(prepared.params)
    local ok, id = client:request(method, request_params, function(error, result)
      if not active() then
        if state.token == token then
          cancel(state)
        end
        return
      end
      state.token, state.cancel = nil, nil
      if error then
        notice("查询失败：" .. error.message)
        return
      end
      callback(source, context, prepared, result or {}, client.offset_encoding)
    end, prepared.buf)
    if not ok then
      cancel(state)
      notice("无法发起查询")
      return
    end
    state.cancel = function()
      client:cancel_request(id)
    end
  end)
  vim.defer_fn(function()
    if state.token == token then
      local visible = active()
      cancel(state)
      if visible then
        notice("上下文查询超时，请稍后重试")
      end
    end
  end, 30000)
  return true
end

function M.documentation()
  return query("textDocument/hover", function(params)
    return params
  end, function(source, _, _, result)
    if not result.contents then
      notice("该版本没有文档说明")
      return
    end
    local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    if #lines == 0 then
      notice("该版本没有文档说明")
      return
    end
    api.nvim_win_call(source.win, function()
      vim.lsp.util.open_floating_preview(lines, "markdown", { border = "rounded", max_width = 78 })
      -- Preparing a new snapshot can run buffer/window hooks. Keep manual
      -- documentation at the position that initiated the query, like drawers.
      if api.nvim_win_get_buf(source.win) == source.buf then
        api.nvim_win_set_cursor(source.win, source.cursor)
        vim.fn.winrestview(source.view)
      end
    end)
  end)
end

function M.definition()
  return query("textDocument/definition", function(params)
    return params
  end, function(source, context, prepared, locations, encoding)
    if not vim.islist(locations) then
      locations = { locations }
    end
    local items = {}
    for _, location in ipairs(locations) do
      if location.uri or location.targetUri then
        items[#items + 1] = { location = location, snapshot = prepared.snapshot, encoding = encoding }
      end
    end
    M.show(source, context, "定义", items)
  end)
end

function M.references()
  return query("textDocument/references", function(params)
    return vim.tbl_extend("force", params, { context = { includeDeclaration = false } })
  end, function(source, context, prepared, locations, encoding)
    local items, seen = {}, {}
    for _, location in ipairs(locations) do
      local key = (location.uri or "") .. ":" .. location.range.start.line .. ":" .. location.range.start.character
      if not seen[key] then
        seen[key] = true
        items[#items + 1] = { location = location, snapshot = prepared.snapshot, encoding = encoding }
      end
    end
    table.sort(items, function(a, b)
      if a.location.uri ~= b.location.uri then
        return a.location.uri < b.location.uri
      end
      local x, y = a.location.range.start, b.location.range.start
      return x.line < y.line or (x.line == y.line and x.character < y.character)
    end)
    M.show(source, context, "引用", items)
  end)
end

function M.outline()
  return query("textDocument/documentSymbol", function(params)
    return { textDocument = params.textDocument }
  end, function(source, context, prepared, symbols, encoding)
    local items = {}
    local function visit(list, depth)
      for _, symbol in ipairs(list) do
        local location = symbol.location
          or { uri = vim.uri_from_bufnr(prepared.buf), range = symbol.selectionRange or symbol.range }
        items[#items + 1] = {
          location = location,
          snapshot = prepared.snapshot,
          encoding = encoding,
          label = string.rep("  ", depth) .. symbol.name,
        }
        visit(symbol.children or {}, depth + 1)
      end
    end
    visit(symbols, 0)
    M.show(source, context, "文件大纲", items)
  end)
end

function M.tree()
  local source, context = origin()
  if not context or not context.revision then
    notice("请先选择一个历史版本的代码窗口")
    return
  end
  require("config.review_tree").open(context, source)
end

function M.setup()
  local function click(action)
    return function(_, _, button)
      if button ~= "l" then
        return
      end
      local win = vim.fn.getmousepos().winid
      vim.schedule(function()
        if valid(win) then
          api.nvim_set_current_win(win)
        end
        action()
      end)
    end
  end
  _G.MateReviewContextClose = click(M.close)
  _G.MateReviewContextOpen = click(M.open)
  local group = api.nvim_create_augroup("MateReviewContext", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      local win = tonumber(event.match)
      for _, state in pairs(states) do
        if not state.closing and (win == state.list_win or win == state.preview_win) then
          vim.schedule(function()
            if api.nvim_get_current_tabpage() == state.tab then
              M.close()
            end
          end)
        end
      end
    end,
  })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab, state in pairs(states) do
        if not api.nvim_tabpage_is_valid(tab) then
          cancel(state)
          states[tab] = nil
        end
      end
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      vim.schedule(M.resize)
    end,
  })
end

return M
