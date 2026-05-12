local count = 0
vim.api.nvim_buf_create_user_command(0, "HyprlangToLua", function(args)
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

  local basename = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
  local ext = vim.fs.ext(basename)
  local basename_without_prefix = basename:sub(1, -6)

  local lua_lines = require("hyprlang-to-lua").convert(table.concat(hyprlang_lines, "\n"))
  local newbuf = vim.api.nvim_create_buf(false, true)
  count = count + 1
  vim.api.nvim_buf_set_name(
    newbuf,
    ("/tmp/hyprlang-to-lua/%s/%s.lua"):format(count, basename_without_prefix)
  )
  vim.api.nvim_buf_set_lines(newbuf, 0, -1, false, lua_lines)
  vim.bo[newbuf].buftype = "nowrite"
  vim.bo[newbuf].filetype = "lua"
  vim.api.nvim_open_win(newbuf, true, {
    split = vim.o.splitright and "right" or "left",
    win = 0,
  })
end, { desc = "Prints out lua version of selected hyprlang text", range = true })
