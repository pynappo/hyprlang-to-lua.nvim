vim.api.nvim_buf_create_user_command(0, "HyprlangToLuaSplit", function(args)
  ---@cast args vim.api.keyset.create_user_command.command_args
  local buf = vim.api.nvim_get_current_buf()
  local startline = args.line1
  if startline then
    startline = startline - 1
  else
    startline = 0
  end
  local endline = args.line2 or -1
  local hyprlang_lines = vim.api.nvim_buf_get_lines(buf, startline, endline, false)

  local chunks = require("hyprlang-to-lua").convert(table.concat(hyprlang_lines, "\n"))

  local date = os.date("%Y-%m-%dT%H:%M:%S")
  local lua_lines = {
    ("-- Start of translated config by hyprlang-to-lua.nvim on %s"):format(date),
  }
  for _, chunk in ipairs(chunks) do
    for line in vim.gsplit(chunk, "\n", { plain = true }) do
      lua_lines[#lua_lines + 1] = line
    end
  end
  lua_lines[#lua_lines + 1] = ("-- End of translated config by hyprlang-to-lua.nvim on %s"):format(
    date
  )

  local newbuf = vim.api.nvim_create_buf(false, true)
  local basename = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
  local basename_without_prefix = basename:sub(1, -6)

  vim.api.nvim_buf_set_name(
    newbuf,
    ("%s/hyprlang-to-lua/%s.lua"):format(vim.fn.tempname(), basename_without_prefix)
  )
  vim.api.nvim_buf_set_lines(newbuf, 0, -1, false, chunks)
  vim.bo[newbuf].filetype = "lua"
  vim.api.nvim_open_win(newbuf, true, {
    split = vim.o.splitright and "right" or "left",
    win = 0,
  })
end, { desc = "Opens lua version of selected hyprlang text in a split buffer", range = true })
