---@module "ergoterm.pickers.terminal_label"
local terminal_label = require("ergoterm.pickers.terminal_label")

local M = {}


function M.select(terminals, prompt, callbacks)
  local labels = {}
  for _, term in ipairs(terminals) do
    labels[term] = terminal_label.format(term)
  end
  vim.ui.select(terminals, {
    prompt = prompt,
    format_item = function(term)
      return labels[term]
    end,
  }, function(term)
    if term then
      callbacks.default.fn(term)
    end
  end)
end

return M
