return {
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      local lint = require("lint")
      opts.linters = opts.linters or {}
      local names = {}
      for _, configured in pairs(opts.linters_by_ft or {}) do
        for _, name in ipairs(configured) do
          names[name] = true
        end
      end
      for name in pairs(opts.linters) do
        names[name] = true
      end
      for name in pairs(names) do
        local original = lint.linters[name]
        -- Function-based custom linters own their own factory/condition contract.
        if type(original) == "table" then
          local override = opts.linters[name] or {}
          local condition = override.condition or original.condition
          opts.linters[name] = vim.tbl_extend("force", override, {
            condition = function(context)
              if
                context.filename:match("^diffview://")
                or require("config.review_navigation").is_snapshot_path(context.filename)
              then
                return false
              end
              return not condition or condition(context)
            end,
          })
        end
      end
    end,
  },
}
