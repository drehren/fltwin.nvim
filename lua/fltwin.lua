---A simple plugin to open floating windows

local aug = vim.api.nvim_create_augroup('fltwin.nvim', { clear = true })

local buf_is_valid = vim.api.nvim_buf_is_valid
local buf_get_name = vim.api.nvim_buf_get_name
local get_current_win = vim.api.nvim_get_current_win
local get_option_value = vim.api.nvim_get_option_value
local win_get_config = vim.api.nvim_win_get_config
local win_is_valid = vim.api.nvim_win_is_valid
local win_set_buf = vim.api.nvim_win_set_buf
local win_get_buf = vim.api.nvim_win_get_buf
local win_get_height = vim.api.nvim_win_get_height
local win_set_height = vim.api.nvim_win_set_height
local win_get_width = vim.api.nvim_win_get_width
local win_set_config = vim.api.nvim_win_set_config

---@alias fltwin.config.name_position 'title'|'footer'
---@alias fltwin.config.name_alignment 'left'|'center'|'right'
---@alias fltwin.config.float_anchor 'NE'|'NW'|'SE'|'SW'

---Default values for any new float window.
---@class fltwin.config
---@field win_highlight? string Sets `w:winhl' for new floats.
local defaults = {
	--- Sets the default name position for new floats.
	---@type fltwin.config.name_position?
	name_pos = 'title',
	--- Sets the default name position alignment for new floats.
	---@type fltwin.config.name_alignment?
	name_align = 'left',
	--- Sets the default width for new floats.
	---
	--- Fractional values are used with screen width.
	---@type number?
	win_width = 1 / 3,
	---@type number?
	--- Sets the default height for new floats.
	---
	--- Fractional values are used with screen height.
	win_height = 3 / 7,
	---@type fltwin.config.float_anchor?
	--- Sets the default position for new floats.
	win_anchor = 'NE',
	--- Sets the default border for new floats.
	---@type ('none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[])?
	win_border = 'solid',
}

---@class fltwin._configimpl
---@field name_pos fltwin.config.name_position
---@field name_align fltwin.config.name_alignment
---@field win_width number
---@field win_height number
---@field win_anchor fltwin.config.float_anchor
---@field win_border? string
---@field win_highlight? string

---@return fltwin._configimpl
local function get_config()
	---@type fltwin.config
	local usrcfg = vim.g.fltwin_config or {}
	return vim.tbl_extend('force', defaults, usrcfg)
end

local relative_line_calc = {
	cursor = 1,
	editor = function()
		return vim.o.lines - vim.o.cmdheight - math.ceil(vim.o.laststatus / 3)
	end,
	laststatus = 1,
	mouse = 1,
	tabline = 1,
	win = function(cfg)
		return win_get_height(cfg.win)
	end,
}

---@param cfg vim.api.keyset.win_config
---@return integer
local function calc_lines(cfg)
	local eh = relative_line_calc[cfg.relative]
	if type(eh) == 'function' then
		eh = eh(cfg)
	else
		eh = eh
	end
	if eh >= 3 and cfg.border then
		if type(cfg.border) == 'string' then
			eh = eh - 2
		else
			eh = eh - (cfg.border[2] and 1 or 0) - (cfg.border[6] and 1 or 0)
		end
	end
	return eh
end

---@param cfg vim.api.keyset.win_config
---@return vim.api.keyset.win_config
local function make_win_config(cfg)
	local wconf = vim.deepcopy(cfg, true)
	if wconf.width <= 1 then
		wconf.width = math.ceil(vim.o.columns * cfg.width)
	end
	if wconf.height < 1 then
		wconf.height = math.ceil(calc_lines(cfg) * cfg.height)
	end
	return wconf
end

local _S_byte = string.byte('S')
local _E_byte = string.byte('E')

local relative_anchor_calc = {
	editor = {
		row = function(l)
			if l == _S_byte then
				return vim.o.lines - vim.o.cmdheight - math.ceil(vim.o.laststatus / 3)
			else
				return 0
			end
		end,
		col = function(r)
			if r == _E_byte then
				return vim.o.columns
			else
				return 0
			end
		end,
	},
	cursor = {
		row = function()
			return 0
		end,
		col = function()
			return 0
		end,
	},
}
relative_anchor_calc.mouse = relative_anchor_calc.cursor
relative_anchor_calc.win = relative_anchor_calc.cursor
relative_anchor_calc.tabline = relative_anchor_calc.cursor
relative_anchor_calc.laststatus = relative_anchor_calc.cursor

---@param anchor fltwin.config.float_anchor
---@param cfg vim.api.keyset.win_config
local function put_anchor(anchor, cfg)
	if not cfg.row then
		local l = anchor:byte(1, 2)
		cfg.row = relative_anchor_calc[cfg.relative].row(l, cfg)
	end
	if not cfg.col then
		local r = anchor:byte(2, 2)
		cfg.col = relative_anchor_calc[cfg.relative].col(r, cfg)
	end
end

---@class fltwin.float
---@field win integer
---@field buf integer
---@field cfg vim.api.keyset.win_config
---@field package name? string
local F = {}
F.__index = F

---Checks if the window is current.
---@return boolean `true` if is current, `false` otherwise.
function F:is_current()
	return get_current_win() == self.win
end

---Checks if the last open buffer is still valid.
---@return boolean `true` if there is an existing buffer, `false` otherwise
function F:buf_is_valid()
	return buf_is_valid(self.buf)
end

---Checks if the window is valid.
function F:win_is_valid()
	return win_is_valid(self.win)
end

---@param mod boolean
---@param cfg vim.api.keyset.win_config
local function put_name_modified(mod, cfg)
	-- local mod = get_option_value('modified', { buf = float.buf })
	local pos = cfg.title and 'title' or cfg.footer and 'footer'
	if not pos then
		return cfg
	end
	---@type string|[string,integer?][]
	local name = cfg[pos]
	if type(name) == 'string' then
		name = { { name } }
	end
	if mod then
		if name[#name][1] ~= ' [+]' then
			name[#name + 1] = { ' [+]' }
			cfg[pos] = name
		end
	else
		if name[#name][1] == ' [+]' then
			table.remove(name)
			cfg[pos] = name
		end
	end
	return cfg
end

---@param float fltwin.float
---@param cfg? vim.api.keyset.win_config
local function put_name(float, cfg)
	if not float:buf_is_valid() then
		return
	end
	cfg = cfg or {}

	local uconf = get_config()
	if not float.cfg[uconf.name_pos] then
		local name = vim.fs.basename(buf_get_name(float.buf))
		if name == '' then
			name = '[No Name]'
		end
		cfg[uconf.name_pos] = name
	end

	if cfg[uconf.name_pos] and not cfg[uconf.name_pos .. '_pos'] then
		cfg[uconf.name_pos .. '_pos'] = uconf.name_align
	end

	return put_name_modified(get_option_value('mod', { buf = float.buf }), cfg)
end

---@param float fltwin.float
local function set_autocmds(float)
	local aids = {}
	vim.api.nvim_create_autocmd('WinClosed', {
		group = aug,
		pattern = tostring(float.win),
		callback = function()
			for _, id in ipairs(aids) do
				vim.api.nvim_del_autocmd(id)
			end
			return true
		end,
	})
	aids[#aids + 1] = vim.api.nvim_create_autocmd('WinEnter', {
		group = aug,
		callback = function()
			if float:is_current() then
				win_set_config(float.win, { hide = false })
			end
		end,
	})
	aids[#aids + 1] = vim.api.nvim_create_autocmd('BufWinEnter', {
		group = aug,
		callback = function(args)
			local cfg = {}
			if float:is_current() then
				if float.buf ~= args.buf then
					float.buf = args.buf
					if float.name then
						float.name = buf_get_name(args.buf)
					end
				end

				cfg = { hide = false }
			end
			if float:win_is_valid() then
				if float.cfg.border and float.cfg.border ~= 'none' then
					put_name(float, cfg)
				end
				if next(cfg) then
					win_set_config(float.win, cfg)
				end
			end
		end,
	})
	aids[#aids + 1] = vim.api.nvim_create_autocmd('BufModifiedSet', {
		group = aug,
		nested = true,
		callback = function(args)
			if float.buf == args.buf and float:win_is_valid() then
				if float.cfg.border and float.cfg.border ~= 'none' then
					win_set_config(float.win, put_name(float))
				end
			end
		end,
	})
	local from_vimr = false
	aids[#aids + 1] = vim.api.nvim_create_autocmd('WinResized', {
		nested = true,
		group = aug,
		callback = function()
			if from_vimr then
				from_vimr = false
				return
			end
			if vim.list_contains(vim.v.event.windows, float.win) then
				local cfg = float.cfg
				local winw = win_get_width(float.win)
				if cfg.width <= 1 then
					cfg.width = winw / vim.o.columns
				else
					cfg.width = winw
				end
				local winh = win_get_height(float.win)
				if cfg.height < 1 then
					local relh = calc_lines(cfg)
					if winh >= relh then
						from_vimr = true
						cfg.height = 0.99
						win_set_height(float.win, relh)
					else
						cfg.height = winh / relh
					end
				else
					cfg.height = winh
				end
			end
		end,
	})
	local resize = function()
		local wcfg = make_win_config(float.cfg)
		put_anchor(float.cfg.anchor, wcfg)

		from_vimr = true
		win_set_config(float.win, wcfg)
	end
	local resize_opts = { group = aug, nested = true, callback = resize }
	aids[#aids + 1] = vim.api.nvim_create_autocmd('VimResized', resize_opts)
	resize_opts.pattern = 'cmdheight'
	aids[#aids + 1] = vim.api.nvim_create_autocmd('OptionSet', resize_opts)
end

---Open a floating window.
---
---If name is omitted it creates a listed scratch buffer.
---If enter is omitted, the cursor will not be moved into the floating window.
---If config is omitted, it uses the default plugin window configuration.
---@param name string|integer A buffer name or buffer-id to display.
---@param enter boolean Move cursor into window.
---@param config vim.api.keyset.win_config Floating window configuration.
---@return [boolean, boolean] changes A boolean tuple indicating if the buffer and or window changed.
---@overload fun(self: fltwin.float, name: string|integer): [boolean, boolean]
---@overload fun(self: fltwin.float, name: string|integer, enter: boolean): [boolean, boolean]
---@overload fun(self: fltwin.float, name: string|integer, config: vim.api.keyset.win_config): [boolean, boolean]
---@overload fun(self: fltwin.float, enter: boolean): [boolean, boolean]
---@overload fun(self: fltwin.float, enter: boolean, config: vim.api.keyset.win_config): [boolean, boolean]
---@overload fun(self: fltwin.float): [boolean, boolean]
function F:open(name, enter, config)
	vim.validate('name', name, { 'boolean', 'number', 'string' }, true)
	vim.validate('enter', enter, { 'boolean', 'table' }, true)
	vim.validate('config', config, 'table', true)

	local newbuf = false
	local newwin = false
	if type(name) == 'string' then
		local bufnr = name ~= '' and vim.fn.bufnr(name, 0) or -1
		newbuf = vim.fn.bufexists(bufnr) == 0
		self.buf = vim.fn.bufadd(name)
		self.name = vim.api.nvim_buf_get_name(self.buf)
		vim.bo[self.buf].buflisted = true
	elseif type(name) == 'number' then
		self.name = nil
		vim.validate('buf', name, buf_is_valid, 'valid buffer')
		self.buf = name
	elseif type(name) == 'boolean' then
		if type(enter) == 'table' then
			config = enter
		end
		enter = name
	end

	if not buf_is_valid(self.buf) then
		if self.name then
			newbuf = vim.fn.bufexists(self.name) == 0
			self.buf = vim.fn.bufadd(self.name)
		else
			newbuf = true
			self.buf = vim.api.nvim_create_buf(true, false)
		end
	end

	if newbuf then
		vim.api.nvim_buf_attach(self.buf, false, {
			on_detach = function()
				self.buf = -1
				self.name = nil
			end,
		})
	end

	-- only if (re)opening or new config
	if not win_is_valid(self.win) or config then
		local wcfg = self:set_config(config or {}, true)

		if not win_is_valid(self.win) then
			newwin = true
			self.win = vim.api.nvim_open_win(self.buf, enter, wcfg)
			local uconf = get_config()
			if uconf.win_highlight then
				vim.api.nvim_set_option_value('winhl', uconf.win_highlight, {
					win = self.win,
				})
			end
			set_autocmds(self)
		elseif config then
			if enter and win_get_config(self.win).hide then
				newwin = true
				wcfg.hide = false
			end
			win_set_config(self.win, wcfg)
		end
	end

	if enter == true and not self:is_current() then
		vim.api.nvim_set_current_win(self.win)
	end

	if win_get_buf(self.win) ~= self.buf then
		win_set_buf(self.win, self.buf)
	end

	return { newbuf, newwin }
end

---Hides the window
function F:hide()
	if win_is_valid(self.win) then
		win_set_config(self.win, { hide = true })
		local previd = vim.fn.win_getid(vim.fn.winnr('#'))
		if vim.fn.has('nvim-0.12') == 1 or not win_get_config(previd).hide then
			vim.api.nvim_set_current_win(previd)
		else
			vim.api.nvim_set_current_win(vim.fn.win_getid(1))
		end
	end
end

---Changes window config if it is still valid.
---Returns effective config to apply.
---@param config vim.api.keyset.win_config Window configuration updates.
---@param noapply boolean? Use to just prepare effective window configuration.
---@return vim.api.keyset.win_config
function F:set_config(config, noapply)
	vim.validate('config', config, 'table')

	local uconf = get_config()
	-- first time opening window, get user defaults
	if self.win == -1 then
		self.cfg.anchor = uconf.win_anchor
		self.cfg.width = uconf.win_width
		self.cfg.height = uconf.win_height
		self.cfg.border = uconf.win_border
	end
	if config then
		self.cfg = vim.tbl_extend('force', self.cfg, config)
	end
	-- always be float
	if not self.cfg.relative or self.cfg.relative == '' then
		self.cfg.relative = 'editor'
	end
	local wcfg = make_win_config(self.cfg)

	put_anchor(self.cfg.anchor, wcfg)
	put_name(self, wcfg)

	if not noapply and self:win_is_valid() then
		vim.api.nvim_win_set_config(self.win, wcfg)
	end

	return wcfg
end

---Toggles the window open/close.
---@return [boolean, boolean]? # If window opens, return is same as s:open()
function F:toggle()
	if not self:win_is_valid() or not self:is_current() then
		self:open(true)
	elseif self:win_is_valid() then
		self:hide()
	end
end

local M = {}

---Creates a new floating window handler.
---
---Pass existing buffer or window ID to handle those.
---@param buf? integer Buffer id
---@param win? integer window-ID
---@return fltwin.float
---@overload fun(win: integer): fltwin.float
function M.new(buf, win)
	vim.validate('buf', buf, 'number', true)
	vim.validate('win', win, 'number', true)
	if buf then
		-- this may be a window ID, start there
		if win_is_valid(buf) then
			win = buf
			buf = win_get_buf(win)
		elseif buf_is_valid(buf) then
			if not win then
				-- try get first floating window
				for _, w in ipairs(vim.fn.getbufinfo(buf)[1].windows) do
					if win_get_config(w).relative ~= '' then
						win = w
						break
					end
				end
			end
		else
			error('buf: expeced valid buffer number or window-ID')
		end
	end
	if win then
		if not win_is_valid(win) then
			error('win: expected valid window')
		end
		if win_get_config(win).relative == '' then
			error('win: expected floating window')
		end
		if buf and win_get_buf(win) ~= buf then
			error('win: expected buffer window, got window for different buffer')
		end
		if not buf then
			buf = win_get_buf(win)
		end
	end

	---@type fltwin.float
	local float = {
		cfg = {},
		buf = buf or -1,
		win = win or -1,
	}
	float = setmetatable(float, F)

	if float:win_is_valid() then
		local wcfg = win_get_config(float.win)
		float.cfg.relative = wcfg.relative
		float.cfg.row = wcfg.row
		float.cfg.col = wcfg.col
		if wcfg.relative == 'win' then
			float.cfg.win = wcfg.win
			float.cfg.bufpos = wcfg.bufpos
		end
		float.cfg.width = wcfg.width
		float.cfg.height = wcfg.height
		set_autocmds(float)
	end

	return float
end

---Creates and opens a new quick floating window.
---@param name string|integer Buffer name or number to use.
---@param enter boolean Move cursor into new window.
---@param cfg vim.api.keyset.win_config Window configuration.
---@return fltwin.float float The created quick floating window.
---@return [boolean, boolean] created A 2-tuple indicating if the buffer or window was created.
---@overload fun(name: string|integer, enter: boolean): fltwin.float, [boolean, boolean]
---@overload fun(name: string|integer, cfg: vim.api.keyset.win_config): fltwin.float, [boolean, boolean]
---@overload fun(name: string|integer): fltwin.float, [boolean, boolean]
---@overload fun(enter: boolean, cfg: vim.api.keyset.win_config): fltwin.float, [boolean, boolean]
---@overload fun(enter: boolean): fltwin.float, [boolean, boolean]
---@overload fun(cfg: vim.api.keyset.win_config): fltwin.float, [boolean, boolean]
function M.open(name, enter, cfg)
	vim.validate('name', name, 'string', true)
	vim.validate('enter', enter, 'boolean', true)
	vim.validate('config', cfg, 'table', true)

	local n = M.new()
	local res = n:open(name, enter, cfg)
	return n, res
end

return M
