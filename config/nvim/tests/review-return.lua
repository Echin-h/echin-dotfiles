-- Run: nvim --headless -i NONE -c 'luafile ~/.config/nvim/tests/review-return.lua'
-- Real Diffview windows and shared definition/link navigation; no LSP needed.
local fixture = vim.fn.tempname() .. "-review-return-test"
local original_cwd = vim.fn.getcwd()
local function git(...)
  local args = { "git", "-C", fixture }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
local function run()
  vim.fn.mkdir(fixture, "p")
  git("init", "--quiet")
  git("config", "user.name", "Review Test")
  git("config", "user.email", "review-test@example.invalid")
  local lines = {}
  for i = 1, 80 do lines[i] = "-- original line " .. i end
  vim.fn.writefile(lines, fixture .. "/source.lua")
  git("add", "source.lua")
  git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "before")
  lines[40] = "-- changed line 40"
  vim.fn.writefile(lines, fixture .. "/source.lua")
  git("add", "source.lua")
  git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "after")
  vim.cmd.cd(vim.fn.fnameescape(fixture))
  require("config.keymaps")
  vim.cmd("DiffviewOpen HEAD^..HEAD")
  assert(vim.wait(10000, function()
    local view = require("diffview.lib").get_current_view()
    local pane = view and view.cur_layout and view.cur_layout.b
    return pane and pane.file and pane.file.bufnr and pane.id
      and vim.api.nvim_win_get_buf(pane.id) == pane.file.bufnr
      and vim.api.nvim_buf_get_name(pane.file.bufnr):match("^diffview://.+/%.git/")
  end, 20), "diff did not load")
  local view = require("diffview.lib").get_current_view()
  vim.api.nvim_set_current_win(view.cur_layout.b.id)
  local nav = require("config.navigation")
  vim.api.nvim_win_set_cursor(0, {40, 3})
  vim.fn.winrestview({topline=32})
  local source = nav.position()
  assert(source.review_origin, "fixture must start in a historical diff")
  local path = fixture .. "/target.lua"
  local lines = {}
  for _ = 1, 12 do lines[#lines+1] = "local function target() end" end
  vim.fn.writefile(lines, path)
  local item = {dir=vim.fn.fnamemodify(path, ":h"), revision="1234567890", root=vim.fn.getcwd()}
  local function jump(line)
    nav.open_location({uri=vim.uri_from_fname(path), range={start={line=line,character=0}, ["end"]={line=line,character=0}}}, item)
  end
  for i = 0, 7 do jump(i) end
  local snapshot_buf = vim.api.nvim_get_current_buf()
  assert(vim.wo.winbar:find("返回审阅", 1, true), "historical definitions need a visible direct return button")
  local bar = vim.api.nvim_eval_statusline(vim.wo.winbar, {winid=vim.api.nvim_get_current_win(), use_winbar=true, maxwidth=80})
  assert(bar.str:find("返回审阅", 1, true), "return button must fit in an 80-column window")
  assert(vim.wo.winbar:find("%10@v:lua.MateCodeToolbar@", 1, true), "return button must invoke the direct return action")
  local back = vim.fn.maparg("mm", "n", false, true)
  back.callback()
  assert(vim.api.nvim_get_current_buf() == snapshot_buf and vim.api.nvim_win_get_cursor(0)[1] == 7, "mm must return one level")
  _G.MateCodeToolbar(10)
  vim.wait(1000, function() return vim.api.nvim_get_current_win() == source.win end, 10)
  assert(vim.api.nvim_get_current_win() == source.win, "button must return directly to original review")
  assert(vim.api.nvim_get_current_buf() == source.buf, "review file changed")
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), source.cursor), "review cursor changed")
  assert(require("diffview.lib").get_current_view() == view, "review view changed")
  assert(vim.fn.winsaveview().topline == source.view.topline, "review scroll position changed")
  nav.forward()
  assert(vim.api.nvim_get_current_buf() == snapshot_buf, "Next must reopen historical definition")
  local direct = vim.fn.maparg("gR", "n", false, true)
  direct.callback()
  assert(vim.api.nvim_get_current_win() == source.win, "gR must return to review after Next")
  vim.fn.delete(path)
  print("PASS: 8 levels, visible return button, mm, Next, gR, original diff/cursor")
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then print(err) end
  pcall(vim.cmd.cd, original_cwd)
  vim.fn.delete(fixture, "rf")
  vim.cmd(ok and "qa!" or "cq!")
end)
