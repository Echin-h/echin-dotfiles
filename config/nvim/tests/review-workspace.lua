-- Regression: bounded same-tab history, identical paths across revisions,
-- pagination, initial commits, scope restoration and narrow-window chrome.
local api = vim.api
local fixture = vim.fn.tempname() .. "-review-workspace"
local cwd = vim.fn.getcwd()
local function git(...)
  local args = { "git", "-C", fixture }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function wait(fn, message)
  assert(vim.wait(10000, fn, 20), message)
end
local function run()
  vim.o.columns = 180
  vim.o.lines = 45
  vim.fn.mkdir(fixture, "p")
  git("init", "-qb", "main")
  git("config", "user.name", "Review Test")
  git("config", "user.email", "test@example.invalid")
  local hashes = {}
  for n = 1, 25 do
    local lines = { "version " .. n }
    for i = 2, 80 do
      lines[i] = "unchanged line " .. i
    end
    vim.fn.writefile(lines, fixture .. "/same.txt")
    git("add", ".")
    git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "change " .. n)
    hashes[n] = git("rev-parse", "HEAD")
  end
  vim.fn.writefile({ "uncommitted" }, fixture .. "/same.txt")
  vim.cmd.cd(fixture)
  require("config.keymaps")
  vim.cmd("DiffviewOpen " .. hashes[1] .. ".." .. hashes[25])
  local lib = require("diffview.lib")
  local view = lib.get_current_view()
  wait(function()
    return view.ready and view.cur_entry and view.cur_entry.opened
  end, "initial diff")
  local commits = require("config.review_commits")
  local ui = require("config.review_workspace")
  local tabs = #api.nvim_list_tabpages()
  local function contents(side)
    return api.nvim_buf_get_lines(api.nvim_win_get_buf(view.cur_layout[side].id), 0, 1, false)[1]
  end
  api.nvim_set_current_win(view.cur_layout.b.id)
  vim.wo.foldenable = false
  api.nvim_win_set_cursor(0, { 40, 0 })
  vim.fn.winrestview({ topline = 32 })
  local original_position = require("config.navigation").position()
  commits.open("HEAD")
  wait(function()
    return commits.state().entries
  end, "history entries")
  local state = commits.state()
  assert(#state.entries == 20 and state.more, "first page must contain 20 commits")
  local function select(row, number)
    api.nvim_set_current_win(state.win)
    api.nvim_win_set_cursor(0, { row, 0 })
    commits.select()
    wait(function()
      return not state.busy and view.cur_entry and view.cur_entry.opened and contents("b") == "version " .. number
    end, "selected version " .. number)
    assert(contents("a") == (number == 1 and "" or "version " .. (number - 1)), "old side retained a stale revision")
    assert(#api.nvim_list_tabpages() == tabs and lib.get_current_view() == view, "history created a nested review")
  end
  select(2, 24)
  select(5, 21)
  select(1, 25)
  api.nvim_set_current_win(state.win)
  api.nvim_win_set_cursor(0, { 21, 0 })
  commits.select()
  wait(function()
    return not state.loading and #state.entries == 25
  end, "load more")
  assert(not state.more, "end of history must stop pagination")
  select(25, 1)
  api.nvim_set_current_win(view.cur_layout.b.id)
  ui.refresh()
  assert(ui.line():find(hashes[1] .. "^!", 1, true), "current comparison range missing")
  commits.overall()
  wait(function()
    return not state.busy and view.cur_entry and view.cur_entry.opened and contents("b") == "version 25"
  end, "overall restored")
  assert(contents("a") == "version 1", "overall base lost")
  assert(
    vim.deep_equal(api.nvim_win_get_cursor(view.cur_layout.b.id), original_position.cursor),
    "scope return lost cursor"
  )
  assert(
    api.nvim_win_call(view.cur_layout.b.id, vim.fn.winsaveview).topline == original_position.view.topline,
    "scope return lost scroll position: expected "
      .. original_position.view.topline
      .. ", got "
      .. api.nvim_win_call(view.cur_layout.b.id, vim.fn.winsaveview).topline
  )
  assert(view.rev_arg == hashes[1] .. ".." .. hashes[25], "overall range lost")
  for _, width in ipairs({ 180, 95, 80 }) do
    vim.o.columns = width
    ui.refresh()
    local bar = api.nvim_eval_statusline(ui.line(), { use_tabline = true, maxwidth = width }).str
    assert(
      bar:find("退出审阅", 1, true) and bar:find("提交历史", 1, true),
      "scope controls clipped at " .. width .. ": " .. bar
    )
    for _, side in ipairs({ "a", "b" }) do
      local win = view.cur_layout[side].id
      local code = api.nvim_eval_statusline(
        vim.wo[win].winbar,
        { use_winbar = true, winid = win, maxwidth = api.nvim_win_get_width(win) }
      ).str
      assert(
        code:find(side == "a" and hashes[1]:sub(1, 8) or hashes[25]:sub(1, 8), 1, true),
        "version label clipped: " .. code
      )
      assert(
        not vim.wo[win].winbar:find("MateCodeToolbar", 1, true),
        "diff code header must only show version and path"
      )
    end
  end
  vim.o.columns = 180
  vim.cmd.DiffviewClose()
  ui.refresh()
  assert(not vim.o.tabline:find("MateReviewWorkspaceLine", 1, true), "normal editor chrome not restored")
  vim.env.MATE_REVIEW_MODE = "history"
  vim.env.MATE_REVIEW_RANGE = "HEAD~2..HEAD"
  commits.open_history()
  view = lib.get_current_view()
  wait(function()
    return view.ready and view.cur_entry and view.cur_entry.opened and commits.state().entries
  end, "explicit history launch")
  assert(
    #commits.state().entries == 2 and commits.state().commit == hashes[25],
    "history launch lost range or newest selection"
  )
  assert(#api.nvim_list_tabpages() == tabs, "history launcher created extra tabs")
  commits.overall()
  wait(function()
    return not commits.state().busy and view.cur_entry and view.cur_entry.opened
  end, "history range overall")
  assert(contents("a") == "version 23" and contents("b") == "version 25", "history range comparison incorrect")
  vim.env.MATE_REVIEW_MODE = nil
  vim.env.MATE_REVIEW_RANGE = nil
  vim.cmd.DiffviewClose()
  ui.refresh()
  assert(
    git("status", "--porcelain") == "M same.txt" and vim.fn.readfile(fixture .. "/same.txt")[1] == "uncommitted",
    "review changed the checkout"
  )
  print(
    "PASS same-tab history, pagination, root commit, same-path revisions, overall range, 180/95/80 columns, dirty checkout"
  )
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then
    print(err)
  end
  pcall(vim.cmd.cd, cwd)
  vim.fn.delete(fixture, "rf")
  vim.cmd(ok and "qa!" or "cq!")
end)
