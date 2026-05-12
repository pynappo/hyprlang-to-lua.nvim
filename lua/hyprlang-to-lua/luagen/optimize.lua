local pretty = require("hyprlang-to-lua.luagen.pretty")
local M = {}

---@param chunks string[]
---@nodiscard
M.optimize = function(chunks)
  ---@type string[]
  local optimized_chunks = {}

  for i = 1, #chunks do
    local chunk = chunks[i]

    -- Pattern matches hl.on("event", function() body end)
    -- %b() matches balanced parentheses for the function body
    if vim.startswith(chunk, "hl.on") then
      local event, body = chunk:match('^hl%.on%("([^"]+)"%,%s*function%(%)%s*(.-)%s*end%)%s*$')

      if not event and body then
        error("could not parse hl.on chunk for optimization" .. chunk)
      end
      local indent1 = pretty.indent(1)

      -- Check if the previous chunk was also an hl.on for the same event
      local prev_event, prev_body
      local prev_chunk = optimized_chunks[#optimized_chunks]
      if prev_chunk then
        prev_event, prev_body =
          prev_chunk:match('^hl%.on%("([^"]+)"%,%s*function%(%)%s*(.-)%s*end%)%s*$')
      end

      if prev_event ~= event then
        optimized_chunks[#optimized_chunks + 1] = chunk
      else
        optimized_chunks[#optimized_chunks] = string.format(
          [[hl.on("%s", function()
%s%s
%s%s
end)]],
          event,
          indent1,
          prev_body,
          indent1,
          body
        )
      end
    else
      optimized_chunks[#optimized_chunks + 1] = chunk
    end
  end

  return optimized_chunks
end
return M
