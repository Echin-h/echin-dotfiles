-- Run: nvim --headless -i NONE -c 'luafile ~/.config/nvim/tests/review-context.lua'
-- Real Git revisions, Diffview and gopls; live code deliberately differs from HEAD.
local api = vim.api
local root = vim.fn.tempname() .. "-review-context-test"
local original = vim.fn.getcwd()
local function wait(fn, message, timeout)
  assert(vim.wait(timeout or 15000, fn, 30), message)
end
local function git(...)
  local args = { "git", "-C", root }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(root .. "/" .. path), "p")
  vim.fn.writefile(lines, root .. "/" .. path)
end
local function findwin(ft)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(win)].filetype == ft then
      return win
    end
  end
end
local function findpreview()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.w[win].mate_review_preview then
      return win
    end
  end
end
local function contents(win)
  return table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false), "\n")
end
local function run()
  vim.o.columns = 180
  vim.o.lines = 45
  vim.fn.mkdir(root, "p")
  git("init", "-b", "main", "--quiet")
  git("config", "user.name", "Review Test")
  git("config", "user.email", "review-test@example.invalid")
  write("go.mod", { "module example.invalid/review", "", "go 1.23" })
  write("service/service.go", {
    "// Package service handles test records.",
    "package service",
    "",
    "func Changed(x int) int {",
    " return x + 1",
    "}",
  })
  write("service/old_caller.go", { "package service", "", "func OldCaller() {", " _ = Changed(1)", "}" })
  write("service/README.md", { "# Service", "OLD documentation" })
  git("add", ".")
  git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "before")
  local base = git("rev-parse", "HEAD")
  git("checkout", "-qb", "feature/review-context")
  write("service/service.go", {
    "// Package service handles test records.",
    "package service",
    "",
    "func Changed(x int) int {",
    " return x + 2",
    "}",
  })
  vim.fn.delete(root .. "/service/old_caller.go")
  write("service/new_caller.go", { "package service", "", "func NewCaller() {", " _ = Changed(2)", "}" })
  write("service/README.md", { "# Service", "NEW documentation" })
  git("add", ".")
  git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "after")
  local head = git("rev-parse", "HEAD")
  -- Dirty live code must never appear in historical results or previews.
  write("service/new_caller.go", { "package service", "", "func LiveOnly() {", " _ = Changed(999)", "}" })
  vim.cmd.cd(vim.fn.fnameescape(root))
  require("config.keymaps")
  api.nvim_cmd({ cmd = "DiffviewOpen", args = { base .. ".." .. head, "--", "service/service.go" } }, {})
  local lib = require("diffview.lib")
  wait(function()
    local view = lib.get_current_view()
    return view
      and view.cur_layout.b.file.path == "service/service.go"
      and view.cur_layout.b.file.bufnr
      and api.nvim_win_get_buf(view.cur_layout.b.id) == view.cur_layout.b.file.bufnr
  end, "diff load")
  local view = lib.get_current_view()
  local ctx = require("config.review_context")
  local tree = require("config.review_tree")
  local nav = require("config.navigation")
  for _, side in ipairs({
    { pane = view.cur_layout.a, caller = "old_caller.go", name = "OldCaller", revision = base },
    { pane = view.cur_layout.b, caller = "new_caller.go", name = "NewCaller", revision = head },
  }) do
    api.nvim_set_current_win(side.pane.id)
    api.nvim_win_set_cursor(side.pane.id, { 4, 6 })
    local source = nav.position()
    local existing = {}
    for _, win in ipairs(api.nvim_list_wins()) do
      existing[win] = true
    end
    assert(ctx.documentation(), "historical documentation not routed")
    local docwin
    wait(function()
      for _, win in ipairs(api.nvim_list_wins()) do
        if
          not existing[win]
          and api.nvim_win_get_config(win).relative ~= ""
          and contents(win):find("Changed", 1, true)
        then
          docwin = win
          return true
        end
      end
    end, "historical documentation", 30000)
    api.nvim_win_close(docwin, true)
    api.nvim_set_current_win(source.win)
    assert(vim.deep_equal(api.nvim_win_get_cursor(source.win), source.cursor), "documentation moved the review cursor")
    local tabs = #api.nvim_list_tabpages()
    require("config.reader").definition()
    wait(function()
      return findwin("mate_review_context") ~= nil
    end, "definition preview", 30000)
    assert(#api.nvim_list_tabpages() == tabs, "definition preview opened a reading tab")
    assert(contents(findpreview()):find("func Changed", 1, true), "definition preview missing selected version")
    api.nvim_set_current_win(findpreview())
    assert(ctx.references(), "historical references from preview not routed")
    wait(function()
      return findwin("mate_review_context") ~= nil
    end, "reference drawer", 30000)
    local listwin = findwin("mate_review_context")
    local preview = findpreview()
    local preview_pos = api.nvim_win_get_position(preview)
    local diff_pos = api.nvim_win_get_position(view.cur_layout.b.id)
    assert(
      preview_pos[2] > diff_pos[2] + api.nvim_win_get_width(view.cur_layout.b.id),
      "preview must be right of both diff panes"
    )
    assert(api.nvim_win_get_position(listwin)[2] == preview_pos[2], "reference list must stay inside right column")
    assert(
      math.abs(api.nvim_win_get_width(view.cur_layout.a.id) - api.nvim_win_get_width(view.cur_layout.b.id)) <= 1,
      "both diff panes need balanced width"
    )
    assert(contents(listwin):find(side.caller, 1, true), "references must use selected revision: " .. contents(listwin))
    assert(contents(preview):find(side.name, 1, true), "wrong reference content")
    assert(not contents(preview):find("LiveOnly", 1, true), "leaked live code")
    assert(api.nvim_win_get_buf(source.win) == source.buf, "preview replaced diff")
    assert(vim.deep_equal(api.nvim_win_get_cursor(source.win), source.cursor), "preview moved diff cursor")
    assert(vim.bo[api.nvim_win_get_buf(preview)].readonly, "preview writable")
    for _, width in ipairs({ 95, 80, 180 }) do
      vim.o.columns = width
      ctx.resize()
      require("config.review_workspace").refresh()
      for _, pane in ipairs({ view.cur_layout.a, view.cur_layout.b }) do
        local text = api.nvim_eval_statusline(
          vim.wo[pane.id].winbar,
          { use_winbar = true, winid = pane.id, maxwidth = api.nvim_win_get_width(pane.id) }
        ).str
        assert(
          text:find(pane == view.cur_layout.a and base:sub(1, 8) or head:sub(1, 8), 1, true),
          "preview clipped version at " .. width .. ": " .. text
        )
        assert(
          not vim.wo[pane.id].winbar:find("MateCodeToolbar", 1, true),
          "diff code header contains duplicate actions"
        )
      end
    end
    ctx.reveal()
    wait(function()
      return findwin("mate_review_tree") ~= nil
    end, "version tree")
    assert(contents(findwin("mate_review_tree")):find(side.caller, 1, true), "tree must reveal reference siblings")
    api.nvim_set_current_win(listwin)
    ctx.open()
    assert(api.nvim_get_current_tabpage() ~= view.tabpage, "explicit Open should enter reading tab")
    assert(api.nvim_buf_get_lines(0, 0, -1, false)[3]:find(side.name, 1, true), "wrong full reading file")
    nav.return_review()
    assert(api.nvim_get_current_win() == source.win, "return review lost origin")
    assert(vim.deep_equal(api.nvim_win_get_cursor(0), source.cursor), "return lost cursor")
    tree.close()
    assert(ctx.outline(), "outline not routed")
    wait(function()
      return findwin("mate_review_context") ~= nil
    end, "outline drawer", 30000)
    assert(contents(findwin("mate_review_context")):find("Changed", 1, true), "outline missing symbol")
    api.nvim_set_current_win(findpreview())
    nav.back()
    assert(not findwin("mate_review_context"), "Back in preview must close drawer")
    assert(api.nvim_get_current_win() == source.win, "Back lost review")
    print("PASS", side.caller, "references, siblings, explicit open, return, outline, Back")
  end
  api.nvim_set_current_win(view.cur_layout.b.id)
  ctx.tree()
  wait(function()
    return findwin("mate_review_tree") ~= nil
  end, "tree show")
  local win = findwin("mate_review_tree")
  local lines = api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false)
  local row
  for i, line in ipairs(lines) do
    if line:find("README.md", 1, true) then
      row = i
    end
  end
  assert(row, "README sibling absent")
  api.nvim_set_current_win(win)
  api.nvim_win_set_cursor(win, { row, 0 })
  local tree_width = api.nvim_win_get_width(win)
  local tree_height = api.nvim_win_get_height(win)
  tree.select()
  wait(function()
    return findpreview() and contents(findpreview()):find("NEW documentation", 1, true)
  end, "historical README preview")
  assert(not contents(findpreview()):find("OLD documentation", 1, true), "README wrong version")
  assert(not findwin("mate_review_context"), "directory file preview must not create a redundant result list")
  assert(
    math.abs(api.nvim_win_get_width(view.cur_layout.a.id) - api.nvim_win_get_width(view.cur_layout.b.id)) <= 1,
    "file preview squeezed one diff pane"
  )
  assert(
    api.nvim_win_get_position(findpreview())[1] == api.nvim_win_get_position(win)[1],
    "file preview must use full height"
  )
  assert(
    api.nvim_win_get_width(win) == tree_width and api.nvim_win_get_height(win) == tree_height,
    "preview changed directory dimensions"
  )
  local preview_width = api.nvim_win_get_width(findpreview())
  api.nvim_win_set_width(findpreview(), preview_width + 8)
  preview_width = api.nvim_win_get_width(findpreview())
  assert(
    api.nvim_win_get_width(win) == tree_width and api.nvim_win_get_height(win) == tree_height,
    "resizing preview changed directory dimensions"
  )
  api.nvim_set_current_win(win)
  for i, line in ipairs(lines) do
    if line:find("new_caller.go", 1, true) then
      api.nvim_win_set_cursor(win, { i, 0 })
      break
    end
  end
  tree.select()
  wait(function()
    return contents(findpreview()):find("NewCaller", 1, true)
  end, "switch file preview")
  assert(api.nvim_win_get_width(findpreview()) == preview_width, "switching files reset preview width")
  ctx.close()
  tree.close()
  assert(view.panel:is_open(), "changed file panel not restored")
  api.nvim_set_current_win(view.cur_layout.b.id)
  api.nvim_win_set_cursor(0, { 4, 6 })
  assert(ctx.references(), "cancel query not routed")
  ctx.close()
  vim.wait(200, function()
    return false
  end)
  assert(not findwin("mate_review_context"), "cancelled query reopened drawer")
  local parent_win = api.nvim_get_current_win()
  -- Panel windows can briefly inherit a code buffer during split creation.
  -- A stale remembered window must not be mistaken for a real diff pane.
  vim.t.mate_review_code_win = view.panel.winid
  api.nvim_set_current_win(view.panel.winid)
  local tabs = #api.nvim_list_tabpages()
  require("config.review_commits").open()
  wait(function()
    return findwin("mate_review_commits") ~= nil
  end, "commit selector")
  local commits = require("config.review_commits")
  wait(function()
    return commits.state().entries ~= nil
  end, "commit entries")
  assert(lib.get_current_view() == view and #api.nvim_list_tabpages() == tabs, "history must stay in the review tab")
  api.nvim_set_current_win(findwin("mate_review_commits"))
  api.nvim_win_set_cursor(0, { 1, 0 })
  commits.select()
  wait(function()
    return not commits.state().busy and view.cur_entry and view.cur_entry.opened
  end, "commit diff")
  assert(view.rev_arg == head .. "^!", "selected commit not applied")
  assert(#api.nvim_list_tabpages() == tabs, "commit selection opened another tab")
  commits.overall()
  wait(function()
    return not commits.state().busy and view.cur_entry and view.cur_entry.opened
  end, "overall diff restored")
  assert(view.rev_arg == base .. ".." .. head, "overall range lost")
  assert(lib.get_current_view() == view, "scope selection replaced review")
  assert(git("status", "--porcelain") == "M service/new_caller.go", "review changed fixture worktree")
  print("PASS historical README, restore changed files, dirty checkout preserved")
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then
    print(err)
  end
  pcall(vim.cmd.cd, original)
  vim.fn.delete(root, "rf")
  vim.cmd(ok and "qa!" or "cq!")
end)
