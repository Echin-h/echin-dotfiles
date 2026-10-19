local M = {}
local ns = vim.api.nvim_create_namespace("MatePickerDismiss")
local active
local left_mouse = {}
for _, key in ipairs({ "<LeftMouse>", "<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>" }) do
  left_mouse[vim.keycode(key)] = true
end
local close_win
local close_buf
local redraw_owner
local original_redraw

local function contains(win, row, col)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local pos = vim.api.nvim_win_get_position(win)
  local border = vim.api.nvim_win_get_config(win).border or {}
  local function edge(index)
    local char = border[index]
    if type(char) == "table" then char = char[1] end
    return char and char ~= "" and 1 or 0
  end
  local height = vim.api.nvim_win_get_height(win) + edge(2) + edge(6)
  local width = vim.api.nvim_win_get_width(win) + edge(4) + edge(8)
  -- nvim_win_get_position reports the outer border's origin.
  return row >= pos[1] and row < pos[1] + height and col >= pos[2] and col < pos[2] + width
end

function M.detach()
  active = nil
  vim.on_key(nil, ns)
  if redraw_owner then redraw_owner.redraw = original_redraw end
  redraw_owner, original_redraw = nil, nil
  if close_win and vim.api.nvim_win_is_valid(close_win) then
    vim.api.nvim_win_close(close_win, true)
  end
  if close_buf and vim.api.nvim_buf_is_valid(close_buf) then
    vim.api.nvim_buf_delete(close_buf, { force = true })
  end
  close_win, close_buf = nil, nil
end

local function draw_close(picker)
  if active ~= picker or not picker:validate() then return end
  local main = picker.fzf_winid
  local pos = vim.api.nvim_win_get_position(main)
  local text = " 关闭 × "
  local width = vim.fn.strdisplaywidth(text)
  local options = {
    relative = "editor", row = pos[1], col = pos[2] + 2,
    width = width, height = 1, style = "minimal", border = "none",
    focusable = false,
    zindex = (vim.api.nvim_win_get_config(main).zindex or 50) + 5,
  }
  -- A separate label on the border keeps fzf's query and terminal mouse input
  -- intact. It never takes focus, and is removed with the native picker close.
  if close_win and vim.api.nvim_win_is_valid(close_win) then
    local old = vim.api.nvim_win_get_config(close_win)
    if old.row ~= options.row or old.col ~= options.col then
      vim.api.nvim_win_set_config(close_win, options)
    end
  else
    close_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[close_buf].bufhidden = "wipe"
    vim.bo[close_buf].filetype = "mate_picker_close"
    vim.api.nvim_buf_set_lines(close_buf, 0, -1, false, { text })
    vim.bo[close_buf].modifiable = false
    close_win = vim.api.nvim_open_win(close_buf, false, options)
    vim.wo[close_win].winhl = "Normal:Special,NormalNC:Special"
  end
end

function M.attach(event)
  M.detach()
  local picker = require("fzf-lua.win").__SELF()
  if not picker or not event.winid or picker.winopts.split then return end
  active = picker
  local origin_view = picker.src_winid and vim.api.nvim_win_is_valid(picker.src_winid)
    and vim.api.nvim_win_call(picker.src_winid, vim.fn.winsaveview) or nil
  draw_close(picker)
  -- fzf redraws can suppress WinResized. Wrap only this picker instance, and
  -- restore its previous method on close; remove when fzf exposes a redraw hook.
  redraw_owner, original_redraw = picker, rawget(picker, "redraw")
  local redraw = picker.redraw
  picker.redraw = function(self, ...)
    redraw(self, ...)
    draw_close(self)
  end
  -- Observe rather than remap mouse keys: fzf terminal input, selection, preview
  -- scrolling, right-click and the editor's original click behavior stay native.
  vim.on_key(function(key, typed)
    if active ~= picker or not (left_mouse[key] or left_mouse[typed]) then return end
    local mouse = vim.fn.getmousepos()
    local row, col = mouse.screenrow - 1, mouse.screencol - 1
    local close_clicked = contains(close_win, row, col)
    if not close_clicked and (contains(picker.fzf_winid, row, col) or contains(picker.preview_winid, row, col)) then return end
    vim.schedule(function()
      if active ~= picker or not picker:validate() then return end
      local clicked = close_clicked and picker.src_winid or mouse.winid
      local original = close_clicked and picker.src_bufnr or nil
      local saved = close_clicked and origin_view
        or clicked ~= 0 and vim.api.nvim_win_is_valid(clicked)
          and vim.api.nvim_win_call(clicked, vim.fn.winsaveview) or nil
      picker:close()
      -- Closing fzf restores its origin; keep a genuine click on another editor
      -- split focused there, without opening the highlighted search result.
      if saved and vim.api.nvim_win_is_valid(clicked) then
        if original and vim.api.nvim_buf_is_valid(original) then
          vim.api.nvim_win_set_buf(clicked, original)
        end
        vim.api.nvim_set_current_win(clicked)
        vim.fn.winrestview(saved)
      end
    end)
  end, ns)
end

return M
