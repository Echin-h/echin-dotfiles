local M = {}
local history = {}
local pending = {}
local departed = {}
local moving = false

local function quiet_move(action)
  local previous = moving
  moving = true
  local ok, result = pcall(action)
  moving = previous
  if not ok then
    error(result)
  end
  return result
end

local function notice(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "代码导航" })
end

local function capture(win)
  return vim.api.nvim_win_call(win, function()
    return {
      win = win,
      buf = vim.api.nvim_win_get_buf(win),
      cursor = vim.api.nvim_win_get_cursor(win),
      view = vim.fn.winsaveview(),
      snapshot = vim.b.mate_review_snapshot,
      review_origin = not vim.b.mate_review_snapshot
        and require("config.review_navigation").context(vim.api.nvim_get_current_buf()) ~= nil,
    }
  end)
end

local function restore(position, win)
  if not vim.api.nvim_buf_is_valid(position.buf) then
    return false
  end
  quiet_move(function()
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_buf(win, position.buf)
    vim.api.nvim_win_set_cursor(win, position.cursor)
    vim.fn.winrestview(position.view)
  end)
  return true
end

local function record(source, target_win)
  target_win = target_win or source.win
  local state = history[target_win] or { back = {}, forward = {} }
  state.back[#state.back + 1] = source
  if #state.back > 100 then
    table.remove(state.back, 1)
  end
  state.forward = {}
  history[target_win] = state
end

local function cancel(win)
  local request = pending[win]
  if request then
    pending[win] = nil
    if request.cancel then
      request.cancel()
    end
  end
end

local function navigate(direction)
  local win = vim.api.nvim_get_current_win()
  cancel(win)
  local state = history[win]
  local from = state and state[direction]
  if not from or #from == 0 then
    notice(direction == "back" and "没有可返回的阅读位置" or "没有可前进的阅读位置")
    return
  end
  local target = table.remove(from)
  local current = capture(win)
  local restore_win = win
  local closing_tab
  if target.review_origin and not vim.api.nvim_win_is_valid(target.win) then
    notice("原 审阅窗口已关闭，请重新打开比较", vim.log.levels.WARN)
    return
  end
  if target.review_origin then
    restore_win = target.win
    closing_tab = vim.api.nvim_win_get_tabpage(win)
  elseif target.snapshot and not current.snapshot then
    quiet_move(function()
      vim.cmd.tabnew()
    end)
    restore_win = vim.api.nvim_get_current_win()
  end
  if not restore(target, restore_win) then
    notice("目标文件的缓冲区已关闭，请重新打开文件", vim.log.levels.WARN)
    return
  end
  history[restore_win] = state
  if closing_tab and closing_tab ~= vim.api.nvim_get_current_tabpage() then
    quiet_move(function()
      vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(closing_tab))
    end)
  end
  if target.snapshot then
    require("config.review_navigation").mark(target.buf, target.snapshot)
  end
  local to = direction == "back" and state.forward or state.back
  to[#to + 1] = current
end

function M.back()
  local context = package.loaded["config.review_context"]
  if context and context.dismiss() then return end
  navigate("back")
end
function M.forward()
  navigate("forward")
end

-- Return directly to the Diffview window that started a historical definition
-- chain. `mm` remains a one-step back operation for users who want to inspect
-- each intermediate definition.
function M.return_review()
  local context = package.loaded["config.review_context"]
  if context and context.dismiss() and not vim.b.mate_review_snapshot then return end
  for _ = 1, 100 do
    local state = history[vim.api.nvim_get_current_win()]
    local back = state and state.back
    if not back or #back == 0 then
      notice("没有可返回的 审阅窗口")
      return
    end
    if back[#back].review_origin then
      navigate("back")
      return
    end
    navigate("back")
  end
  notice("定义跳转链过长，未能返回 审阅窗口", vim.log.levels.WARN)
end

local function jump(source, candidate)
  if not vim.api.nvim_win_is_valid(source.win) or not vim.api.nvim_buf_is_valid(source.buf) then
    return
  end
  if vim.api.nvim_win_get_buf(source.win) ~= source.buf then
    notice("源文件已切换，已取消这次跳转")
    return
  end
  restore(source, source.win)
  local target_win = source.win
  if candidate.snapshot and not source.snapshot then
    source.review_origin = true
    quiet_move(function()
      vim.cmd.tabnew()
    end)
    target_win = vim.api.nvim_get_current_win()
    history[target_win] = history[source.win]
  end
  -- Keep Vim's native jump list and tag stack useful alongside Back / Next.
  local ok, result = pcall(quiet_move, function()
    return vim.lsp.util.show_document(candidate.location, candidate.encoding, { focus = true, reuse_win = false })
  end)
  if not ok or not result then
    if target_win ~= source.win then
      quiet_move(function()
        vim.cmd.tabclose()
        restore(source, source.win)
      end)
    end
    notice("无法打开定义位置：" .. tostring(ok and "目标不可用" or result), vim.log.levels.WARN)
    return
  end
  local target = capture(target_win)
  if target.buf == source.buf and vim.deep_equal(target.cursor, source.cursor) then
    notice("已经位于该定义处")
    return
  end
  if candidate.snapshot then
    require("config.review_navigation").mark(target.buf, candidate.snapshot)
  end
  record(source, target_win)
end

-- Shared file/link entry point: keep Back/Next and native jump lists identical
-- to definition navigation instead of giving document links a second history.
function M.position()
  return capture(vim.api.nvim_get_current_win())
end

function M.open_location(location, snapshot, source, encoding)
  jump(source or capture(vim.api.nvim_get_current_win()), {
    location = location,
    encoding = encoding or "utf-8",
    snapshot = snapshot,
  })
end

function M.select_definition()
  local list = vim.fn.getqflist({ idx = 0, context = 0 })
  local context = type(list.context) == "table" and list.context or {}
  if not context.mate_definitions then
    return false
  end
  local index = vim.bo.filetype == "qf" and vim.api.nvim_win_get_cursor(0)[1] or list.idx
  local candidate = context.mate_definitions[index]
  if candidate then
    vim.cmd.cclose()
    jump(context.source, candidate)
  end
  return true
end

function M.is_review_buffer(buf)
  return require("config.review_navigation").is_review_buffer(buf)
end

function M.definition()
  local win = vim.api.nvim_get_current_win()
  cancel(win)
  local source = capture(win)
  local review = require("config.review_navigation")
  local context = review.context(source.buf)
  if not context and source.snapshot then
    context = {
      root = source.snapshot.root,
      revision = source.snapshot.revision,
      path = vim.api.nvim_buf_get_name(source.buf):sub(#source.snapshot.dir + 2),
    }
  end
  local request = {}
  pending[win] = request
  local function present(results, snapshot)
    if pending[win] ~= request then
      return
    end
    pending[win] = nil
    local candidates, seen, errors = {}, {}, {}
    for id, response in pairs(results) do
      local client = vim.lsp.get_client_by_id(id)
      if response.err then
        errors[#errors + 1] = response.err.message
      elseif client and response.result then
        local locations = vim.islist(response.result) and response.result or { response.result }
        for _, location in ipairs(locations) do
          local uri = location.uri or location.targetUri
          local range = location.range or location.targetSelectionRange
          local key = uri and range and (uri .. ":" .. range.start.line .. ":" .. range.start.character)
          if
            key
            and not seen[key]
            and (not snapshot or require("config.review_navigation").valid_location(location, snapshot))
          then
            seen[key] = true
            candidates[#candidates + 1] =
              { location = location, encoding = client.offset_encoding, snapshot = snapshot }
          end
        end
      end
    end
    if #candidates == 0 then
      notice(
        #errors > 0 and ("语言服务查询失败：" .. table.concat(errors, "; "))
          or (
            snapshot
              and "该版本未找到定义，或目标属于快照之外的依赖；不会跳到当前工作区代码"
            or "未找到当前位置的定义"
          ),
        #errors > 0 and vim.log.levels.WARN or nil
      )
    elseif #candidates == 1 then
      jump(source, candidates[1])
    else
      local items = {}
      for _, candidate in ipairs(candidates) do
        vim.list_extend(items, vim.lsp.util.locations_to_items({ candidate.location }, candidate.encoding))
      end
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      vim.api.nvim_set_current_win(win)
      vim.fn.setqflist(
        {},
        " ",
        { title = "选择函数定义", items = items, context = { source = source, mate_definitions = candidates } }
      )
      vim.cmd.copen()
    end
  end
  if context then
    request.cancel = review.prepare(context, source, function(err, prepared)
      if pending[win] ~= request then
        return
      end
      if err then
        pending[win] = nil
        notice(err, vim.log.levels.WARN)
        return
      end
      local client = prepared.client
      local ok, id = client:request("textDocument/definition", prepared.params, function(error, result)
        present({ [client.id] = { err = error, result = result } }, prepared.snapshot)
      end, prepared.buf)
      if not ok then
        pending[win] = nil
        notice("历史定义查询无法发起", vim.log.levels.WARN)
        return
      end
      request.cancel = function()
        client:cancel_request(id)
      end
    end)
  else
    if review.is_review_buffer(source.buf) then
      pending[win] = nil
      notice("无法识别该历史版本，不能使用当前工作区定义代替", vim.log.levels.WARN)
      return
    end
    local clients = vim.lsp.get_clients({ bufnr = source.buf, method = "textDocument/definition" })
    if #clients == 0 then
      pending[win] = nil
      notice("当前文件的语言服务尚未就绪，或不支持定义跳转", vim.log.levels.WARN)
      return
    end
    request.cancel = vim.lsp.buf_request_all(source.buf, "textDocument/definition", function(client)
      return vim.lsp.util.make_position_params(win, client.offset_encoding)
    end, function(results)
      present(results, source.snapshot)
    end)
  end
  vim.defer_fn(function()
    if pending[win] ~= request then
      return
    end
    cancel(win)
    notice("定义查询超时，请稍后重试或检查语言服务", vim.log.levels.WARN)
  end, context and 30000 or 8000)
end

function M.setup()
  require("config.review_navigation").setup()
  local group = vim.api.nvim_create_augroup("MateCodeNavigation", { clear = true })
  local function readable(win)
    if vim.w[win].mate_review_preview or vim.bo.buftype ~= "" or vim.api.nvim_buf_get_name(0) == "" then
      return false
    end
    local diffview = package.loaded["diffview.lib"]
    return not (diffview and diffview.tabpage_to_view(vim.api.nvim_win_get_tabpage(win)))
  end
  -- Preserve loaded-file history when enabling this in an existing editor.
  quiet_move(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      vim.api.nvim_win_call(win, function()
        if history[win] or not readable(win) then
          return
        end
        local jumps = vim.fn.getjumplist()
        local previous = {}
        for i = 1, math.min(jumps[2], #jumps[1]) do
          local item = jumps[1][i]
          if
            item.bufnr ~= vim.api.nvim_get_current_buf()
            and vim.api.nvim_buf_is_loaded(item.bufnr)
            and vim.bo[item.bufnr].buftype == ""
          then
            local position = {
              win = win,
              buf = item.bufnr,
              cursor = { item.lnum, item.col },
              view = { lnum = item.lnum, col = item.col, topline = math.max(1, item.lnum - 4) },
            }
            if previous[#previous] and previous[#previous].buf == item.bufnr then
              previous[#previous] = position
            else
              previous[#previous + 1] = position
            end
          end
        end
        if #previous > 0 then
          history[win] = { back = previous, forward = {} }
        end
      end)
    end
  end)
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if not moving and readable(win) then
        departed[win] = capture(win)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if moving then
        return
      end
      local win = vim.api.nvim_get_current_win()
      if not readable(win) then
        return
      end
      local source = departed[win]
      departed[win] = nil
      if source and source.buf ~= vim.api.nvim_get_current_buf() then
        record(source)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      local win = tonumber(event.match)
      cancel(win)
      history[win] = nil
      departed[win] = nil
    end,
  })
end

return M
