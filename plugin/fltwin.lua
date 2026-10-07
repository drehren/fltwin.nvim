if vim.g.loaded_fltwin then
	return
end

vim.g.loaded_fltwin = true

---@type fltwin.float
local qnote

local function get_or_create()
	function get_or_create()
		if not vim.api.nvim_buf_is_loaded(qnote.buf) then
			qnote.buf = -1
		end
		return qnote
	end
	qnote = require('fltwin').new()
	return qnote
end

vim.keymap.set('n', '<Plug>(FltWinOpen)', function()
	get_or_create():open(true)
end, { desc = 'Opens the quick window' })

vim.keymap.set('n', '<Plug>(FltWinToggle)', function()
	get_or_create():toggle()
end, { desc = 'Opens/hides the quick window' })

vim.keymap.set('n', '<Plug>(FltWinHide)', function()
	get_or_create():hide()
end, { desc = 'Hides the quick window' })
