return {
  {
    "ibhagwan/fzf-lua",
    opts = function(_, opts)
      opts.winopts = opts.winopts or {}
      local create, close = opts.winopts.on_create, opts.winopts.on_close
      opts.winopts.on_create = function(event)
        if create then create(event) end
        require("config.picker_dismiss").attach(event)
      end
      opts.winopts.on_close = function(...)
        require("config.picker_dismiss").detach()
        if close then close(...) end
      end
    end,
  },
}
