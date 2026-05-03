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
  local lines = vim.api.nvim_buf_get_lines(buf, startline, endline, false)
  local text = table.concat(lines, "\n")
  require("hyprlang-to-lua").convert(text)
end, { desc = "Prints out lua version of selected hyprlang text", range = true })
