-- Historical definitions must resolve against the reviewed tree, never the live worktree.
local M = {}
local snapshots = {}
local sequence = 0
local temp = vim.fn.tempname() .. "-mate-review"
vim.fn.mkdir(temp, "p")
local base = vim.uv.fs_realpath(temp) or temp
local building = {}

function M.is_snapshot_path(path)
  if type(path) ~= "string" then
    return false
  end
  local real = vim.uv.fs_realpath(path) or path
  return real:sub(1, #base + 1) == base .. "/"
end

function M.context(buf)
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  if not view or not view.cur_layout then
    return
  end
  for _, pane in ipairs(view.cur_layout.windows) do
    local file = pane.file
    if file and file.bufnr == buf and file.rev and file.rev.type ~= 1 then
      return { root = file.adapter.ctx.toplevel, revision = file.rev.commit, path = file.path }
    end
  end
end

function M.is_review_buffer(buf)
  return M.context(buf) ~= nil or vim.api.nvim_buf_get_name(buf):match("^diffview://") ~= nil
end

local function server(filetype)
  if filetype == "go" then
    return "gopls", { "gopls" }
  end
  if vim.tbl_contains({ "typescript", "typescriptreact", "javascript", "javascriptreact" }, filetype) then
    return "vtsls", { vim.fn.expand("~/.local/share/mate-code-tools/node_modules/.bin/vtsls"), "--stdio" }
  end
end

local function remove(snapshot)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf):sub(1, #snapshot.dir + 1) == snapshot.dir .. "/" then
      if #vim.fn.win_findbuf(buf) > 0 then
        return false
      end
    end
  end
  for _, id in ipairs(snapshot.clients or {}) do
    local client = vim.lsp.get_client_by_id(id)
    if client then
      client:stop(true)
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf):sub(1, #snapshot.dir + 1) == snapshot.dir .. "/" then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  vim.fn.delete(snapshot.dir, "rf")
  return true
end

local function trim(protected)
  local keys = vim.tbl_keys(snapshots)
  table.sort(keys, function(a, b)
    return snapshots[a].used < snapshots[b].used
  end)
  while #keys > 2 do
    local key = table.remove(keys, 1)
    if key ~= protected and remove(snapshots[key]) then
      snapshots[key] = nil
    end
  end
  return vim.tbl_count(snapshots) <= 2
end

local function snapshot(context, callback)
  local key = context.root .. ":" .. context.revision
  sequence = sequence + 1
  if snapshots[key] then
    snapshots[key].used = sequence
    callback(nil, snapshots[key])
    return
  end
  if building[key] then
    table.insert(building[key], callback)
    return
  end
  building[key] = { callback }
  local item =
    { dir = base .. "/" .. sequence, used = sequence, revision = context.revision, root = context.root, clients = {} }
  vim.fn.mkdir(item.dir, "p")
  local archive = item.dir .. ".tar"
  local function done(err)
    vim.schedule(function()
      vim.fn.delete(archive)
      if not err then
        snapshots[key] = item
        if not trim(key) then
          snapshots[key] = nil
          err = "已有两个历史快照正在查看，请先关闭其中一个历史阅读标签"
        end
      end
      if err then
        vim.fn.delete(item.dir, "rf")
      end
      local callbacks = building[key] or {}
      building[key] = nil
      for _, fn in ipairs(callbacks) do
        fn(err, item)
      end
    end)
  end
  -- Git archive never changes HEAD, index, or another worktree's uncommitted files.
  vim.system(
    { "git", "-C", context.root, "archive", "--format=tar", "--output=" .. archive, context.revision },
    {},
    function(result)
      if result.code ~= 0 then
        done("无法读取该提交的完整代码：" .. result.stderr)
        return
      end
      vim.system({ "tar", "-xf", archive, "-C", item.dir }, {}, function(extracted)
        if extracted.code ~= 0 then
          done("无法创建历史代码快照：" .. extracted.stderr)
          return
        end
        -- Reuse installed external TypeScript packages, but reject definition results
        -- outside the archived tree (workspace dependency links may point at live code).
        vim.schedule(function()
          local matches = vim.fs.find("node_modules", {
            path = context.root,
            type = "directory",
            limit = 100,
            skip = function(path)
              return path:match("/%.git$") or path:match("/node_modules$") or path:match("/%.cache$")
            end,
          })
          for _, path in ipairs(matches) do
            local relative = path:sub(#context.root + 2)
            local target = item.dir .. "/" .. relative
            if vim.fn.isdirectory(vim.fn.fnamemodify(target, ":h")) == 1 and vim.fn.getftype(target) == "" then
              vim.uv.fs_symlink(path, target, { dir = true })
            end
          end
          done()
        end)
      end)
    end
  )
end

-- Read a historical document without starting a language service or touching
-- the live checkout. This reuses the bounded revision cache used by definitions.
function M.open_file(context, callback)
  if not context.revision then
    callback("暂存区或冲突版本无法解析完整历史路径，请打开对应提交")
    return
  end
  snapshot(context, function(err, item)
    if err then
      callback(err)
      return
    end
    local path = vim.fs.normalize(item.dir .. "/" .. context.path)
    local real = vim.uv.fs_realpath(path)
    local stat = real and vim.uv.fs_stat(real)
    if not real or real:sub(1, #item.dir + 1) ~= item.dir .. "/" or not stat or stat.type ~= "file" then
      callback("该提交中找不到文件，或路径指向历史快照之外：" .. context.path, nil, "not_found")
      return
    end
    local buf = vim.fn.bufadd(path)
    vim.b[buf].mate_review_snapshot = { dir = item.dir, revision = context.revision, root = context.root }
    vim.b[buf].autoformat = false
    vim.fn.bufload(buf)
    vim.bo[buf].filetype = vim.filetype.match({ filename = path, buf = buf }) or ""
    vim.bo[buf].readonly = true
    vim.bo[buf].modifiable = false
    callback(nil, { buf = buf, snapshot = item })
  end)
end

-- callback(error, {client, buf, params, snapshot}); return cancel function.
function M.prepare(context, source, callback)
  local cancelled = false
  if not context.revision then
    callback(
      "暂存区/冲突版本不是完整提交，无法准确解析历史定义；请打开对应提交或工作区文件"
    )
    return function()
      cancelled = true
    end
  end
  local name, command = server(vim.bo[source.buf].filetype)
  if not name then
    callback("该历史文件暂未配置语言服务（支持 Go、TypeScript、JavaScript、React）")
    return function()
      cancelled = true
    end
  end
  vim.notify(
    "正在准备 " .. context.revision:sub(1, 8) .. " 的历史定义…",
    vim.log.levels.INFO,
    { title = "历史代码导航" }
  )
  snapshot(context, function(err, item)
    if cancelled then
      return
    end
    if err then
      callback(err)
      return
    end
    local path = item.dir .. "/" .. context.path
    -- Do not follow a tracked symlink out of the reviewed tree.
    local real = vim.uv.fs_realpath(path)
    if not real or real:sub(1, #item.dir + 1) ~= item.dir .. "/" then
      callback("历史文件不可读取或指向快照之外")
      return
    end
    local buf = vim.fn.bufadd(path)
    -- Set this before BufRead/FileType hooks so readers never treat it as live code.
    vim.b[buf].mate_review_snapshot = { dir = item.dir, revision = context.revision, root = context.root }
    vim.b[buf].autoformat = false
    vim.fn.bufload(buf)
    vim.b[buf].mate_review_snapshot = { dir = item.dir, revision = context.revision, root = context.root }
    vim.bo[buf].filetype = vim.bo[source.buf].filetype
    vim.bo[buf].readonly = true
    vim.bo[buf].modifiable = false
    vim.b[buf].autoformat = false
    local config = vim.tbl_deep_extend("force", vim.deepcopy(vim.lsp.config[name] or {}), {
      name = name,
      cmd = command,
      root_dir = item.dir,
      workspace_folders = { { uri = vim.uri_from_fname(item.dir), name = "Review " .. context.revision:sub(1, 8) } },
      settings = name == "gopls" and { gopls = { buildFlags = { "-mod=readonly" } } } or {},
    })
    if name == "gopls" then
      config.cmd_env = vim.tbl_extend("force", config.cmd_env or {}, {
        GOPROXY = "off",
      })
    end
    local ok, id = pcall(vim.api.nvim_buf_call, buf, function()
      return vim.lsp.start(config, {
        bufnr = buf,
        reuse_client = function(client, candidate)
          return client.name == candidate.name and client.config.root_dir == item.dir
        end,
      })
    end)
    if not ok or not id then
      callback("历史语言服务启动失败：" .. tostring(id))
      return
    end
    if not vim.tbl_contains(item.clients, id) then
      table.insert(item.clients, id)
    end
    local started = vim.uv.now()
    local function ready()
      if cancelled then
        return
      end
      local client = vim.lsp.get_client_by_id(id)
      if not client or client:is_stopped() then
        callback("历史语言服务已停止，请检查安装与日志")
        return
      end
      if not client.initialized then
        if vim.uv.now() - started > 15000 then
          callback("历史语言服务初始化超时，请重试")
          return
        end
        vim.defer_fn(ready, 100)
        return
      end
      local line = vim.api.nvim_buf_get_lines(buf, source.cursor[1] - 1, source.cursor[1], false)[1] or ""
      -- vtsls initializes before its first project finishes loading; give the
      -- newly opened project a turn to index imports instead of jumping to an alias.
      vim.defer_fn(function()
        if cancelled then
          return
        end
        callback(nil, {
          client = client,
          buf = buf,
          snapshot = item,
          params = {
            textDocument = { uri = vim.uri_from_bufnr(buf) },
            position = {
              line = source.cursor[1] - 1,
              character = vim.str_utfindex(line, client.offset_encoding, source.cursor[2], false),
            },
          },
        })
      end, 1000)
    end
    ready()
  end)
  return function()
    cancelled = true
  end
end

function M.valid_location(location, item)
  local uri = location.uri or location.targetUri
  if not uri or uri:sub(1, 7) ~= "file://" then
    return false
  end
  local real = vim.uv.fs_realpath(vim.uri_to_fname(uri))
  return real and real:sub(1, #item.dir + 1) == item.dir .. "/"
end

function M.mark(buf, item)
  vim.b[buf].mate_review_snapshot = { dir = item.dir, revision = item.revision, root = item.root }
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false
  vim.b[buf].autoformat = false
  vim.api.nvim_exec_autocmds("User", { pattern = "MateReviewSnapshot", modeline = false, data = { buf = buf } })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("MateReviewNavigation", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, item in pairs(snapshots) do
        for _, id in ipairs(item.clients) do
          local client = vim.lsp.get_client_by_id(id)
          if client then
            client:stop(true)
          end
        end
      end
      vim.fn.delete(base, "rf")
    end,
  })
end

return M
