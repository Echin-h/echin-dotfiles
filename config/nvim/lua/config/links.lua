local M = {}
local ticket = 0
local press
local epoch = 0

local function notice(message)
  vim.notify(message, vim.log.levels.WARN, { title = "文件链接" })
end

local function document(buf)
  return vim.bo[buf].filetype == "markdown"
    or vim.bo[buf].filetype == "markdown.mdx"
    or vim.bo[buf].filetype == "text"
    or vim.bo[buf].filetype == "rst"
end

local function destination(value)
  value = vim.trim(value)
  if value:sub(1, 1) == "<" then
    return value:match("^<(.-)>")
  end
  -- A quoted Markdown title follows whitespace, not part of the file path.
  return value:match([=[^(.-)%s+['"].-['"]%s*$]=]) or value
end

local function filelike(value)
  return value:match("^%.%./")
    or value:match("^%./")
    or value:match("^/")
    or value:match("^~/")
    or value:find("/", 1, true)
    or value:match("^[^%s]+%.[%w]+[#:]*")
end

-- All columns are byte columns, matching Neovim's mouse/cursor APIs.
function M.find(line, column, doc)
  local from = 1
  while from <= #line do
    local first, last = line:find("!?%b[]%b()", from)
    if not first then
      break
    end
    if column >= first and column <= last then
      local body = line:sub(first, last):match("^!?%b[]%((.*)%)$")
      return { path = destination(body), first = first, last = last, explicit = true }
    end
    from = last + 1
  end
  from = 1
  while from <= #line do
    local first, last, _, body = line:find("(`+)(.-)%1", from)
    if not first then
      break
    end
    if column >= first and column <= last and filelike(body) then
      return { path = vim.trim(body), first = first, last = last, explicit = true }
    end
    from = last + 1
  end
  local first, last = column, column
  local function character(index)
    local char = line:sub(index, index)
    return index >= 1 and index <= #line and not char:match([=[[%s`"'<>%[%]()]]=])
  end
  if not character(column) then
    return
  end
  while character(first - 1) do
    first = first - 1
  end
  while character(last + 1) do
    last = last + 1
  end
  local value = line:sub(first, last):gsub("[,;.!?]+$", "")
  if
    filelike(value)
    and (not doc or value:match("^%.%./") or value:match("^%./") or value:match("^~/") or value:match("^/"))
  then
    return { path = value, first = first, last = last }
  end
end

local function parse(value)
  if
    not value
    or value == ""
    or (value:match("^[%a][%w+.-]*://") or value:match("^mailto:") or value:match("^javascript:"))
      and not value:match("^file://")
  then
    return
  end
  if value:sub(1, 1) == "#" then
    return
  end
  local line = tonumber(value:match("#L(%d+)"))
  local anchor = value:match("#(.*)$")
  value = value:gsub("#.*$", "")
  local path, number = value:match("^(.-):(%d+)$")
  if path then
    value, line = path, tonumber(number)
  end
  if value:match("^file://") then
    value = vim.uri_to_fname(value)
  end
  value = value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  if value:find("%z") or value:find("\n", 1, true) then
    return
  end
  return { path = value, line = line or 1, anchor = anchor }
end

local function location(buf, number)
  local row = math.max(0, math.min(vim.api.nvim_buf_line_count(buf) - 1, number - 1))
  return {
    uri = vim.uri_from_bufnr(buf),
    range = { start = { line = row, character = 0 }, ["end"] = { line = row, character = 0 } },
  }
end

function M.open(target)
  local reference = target and parse(target.path)
  if not reference then
    return false
  end
  ticket = ticket + 1
  local current = ticket
  local navigation = require("config.navigation")
  local source = navigation.position()
  local review = require("config.review_navigation")
  local context = review.context(source.buf)
  local snapshot = vim.b[source.buf].mate_review_snapshot
  if not context and snapshot then
    context = {
      root = snapshot.root,
      revision = snapshot.revision,
      path = vim.api.nvim_buf_get_name(source.buf):sub(#snapshot.dir + 2),
    }
  end
  if context then
    if reference.path:sub(1, 1) == "/" or reference.path:sub(1, 2) == "~/" then
      notice("历史版本只打开仓库内的相对文件路径")
      return true
    end
    local requested = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(context.path), reference.path))
    if requested == ".." or requested:sub(1, 3) == "../" then
      notice("链接指向历史仓库之外，无法打开对应版本")
      return true
    end
    context.path = requested
    review.open_file(context, function(err, prepared, kind)
      if ticket ~= current then
        return
      end
      if err then
        if target.fallback_missing and kind == "not_found" then
          if vim.api.nvim_win_is_valid(source.win) and vim.api.nvim_win_get_buf(source.win) == source.buf then
            vim.api.nvim_win_call(source.win, navigation.definition)
          end
        else
          notice(err)
        end
        return
      end
      navigation.open_location(location(prepared.buf, reference.line), prepared.snapshot, source)
    end)
    return true
  end
  if review.is_review_buffer(source.buf) then
    notice("无法识别历史版本，未打开当前工作区文件")
    return true
  end
  local file = vim.api.nvim_buf_get_name(source.buf)
  if file == "" then
    notice("当前缓冲区没有文件位置，无法解析相对路径")
    return true
  end
  local path = reference.path
  if path:sub(1, 2) == "~/" then
    path = vim.fn.expand("~") .. path:sub(2)
  elseif path:sub(1, 1) ~= "/" then
    path = vim.fs.joinpath(vim.fs.dirname(file), path)
  end
  path = vim.fs.normalize(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    if target.fallback_missing then
      return false
    end
    notice("文件不存在或不是普通文件：" .. path)
    return true
  end
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  navigation.open_location(location(buf, reference.line), nil, source)
  return true
end

function M.at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local found = M.find(line, cursor[2] + 1, false)
  if found and not found.explicit and not document(vim.api.nvim_get_current_buf()) then
    local value = found.path
    local quote = line:sub(found.first - 1, found.first - 1)
    local quoted = (quote == "'" or quote == '"') and line:sub(found.last + 1, found.last + 1) == quote
    -- Dotted symbols (api.method) and division expressions stay LSP symbols.
    if
      not quoted
      and not value:match("^%.%./")
      and not value:match("^%./")
      and not value:match("^/")
      and not value:match("^~/")
    then
      return false
    end
  end
  if found then
    found.fallback_missing = not document(vim.api.nvim_get_current_buf())
  end
  return M.open(found)
end

local function mouse()
  local point = vim.fn.getmousepos()
  if point.winid == 0 or point.line < 1 or point.column < 1 or not vim.api.nvim_win_is_valid(point.winid) then
    return
  end
  if vim.api.nvim_win_get_config(point.winid).relative ~= "" then
    return
  end
  local buf = vim.api.nvim_win_get_buf(point.winid)
  if vim.bo[buf].buftype ~= "" and not require("config.navigation").is_review_buffer(buf) then
    return
  end
  return { win = point.winid, buf = buf, line = point.line, column = point.column }
end

local function follow_click(initial, target)
  if
    not initial
    or not target
    or not vim.api.nvim_win_is_valid(target.win)
    or not vim.api.nvim_buf_is_valid(target.buf)
    or initial.win ~= target.win
    or initial.buf ~= target.buf
    or initial.line ~= target.line
    or initial.column ~= target.column
    or not document(target.buf)
    or vim.api.nvim_get_mode().mode ~= "n"
  then
    return
  end
  local line = vim.api.nvim_buf_get_lines(target.buf, target.line - 1, target.line, false)[1]
  local found = line and M.find(line, target.column, true)
  if not found then
    return
  end
  vim.api.nvim_set_current_win(target.win)
  vim.api.nvim_win_set_cursor(target.win, { target.line, target.column - 1 })
  M.open(found)
end

local mouse_ns = vim.api.nvim_create_namespace("MateCodeFileLinks")
function M.shutdown()
  epoch = epoch + 1
  ticket = ticket + 1
  press = nil
  vim.on_key(nil, mouse_ns)
end

function M.setup()
  M.shutdown()
  -- Migrate the first link implementation's global mouse mappings. Observing
  -- events keeps native winbar callbacks, selection, trees and tabs untouched.
  local legacy = {
    ["<LeftMouse>"] = "Position cursor or start selection",
    ["<LeftRelease>"] = "Open document file link after click",
  }
  for key, desc in pairs(legacy) do
    if vim.fn.maparg(key, "n", false, true).desc == desc then
      vim.keymap.del("n", key)
    end
  end
  local left, release, drag = vim.keycode("<LeftMouse>"), vim.keycode("<LeftRelease>"), vim.keycode("<LeftDrag>")
  vim.on_key(function(key, typed)
    if key == left or typed == left then
      press = vim.api.nvim_get_mode().mode == "n" and mouse() or nil
    elseif key == drag or typed == drag then
      press = nil
    elseif key == release or typed == release then
      local initial, target = press, mouse()
      press = nil
      if initial and target then
        local generation = epoch
        vim.schedule(function()
          if epoch == generation then
            follow_click(initial, target)
          end
        end)
      end
    end
  end, mouse_ns)
end

return M
