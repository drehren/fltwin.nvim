# fltwin

A small library to open a floating window and reuse it with the specified
buffer.

## Requirements

- neovim >= 0.11.0

## Instalation

Just add this plugin with your favorite package manager, there are no
dependencies.

## Configuration

The plugin accepts the following configuration.

The configuration is used as defaults when opening a new floating window
through the library.

```lua
    vim.g.fltwin_config = {
        -- Defines where to show the buffer name. ('title'|'footer')
        name_pos = 'title', 
        -- Defines the position of the buffer name. ('left'|'center'|'right')
        name_align = 'left',
        -- Defines default width for a new floating window. (number)
        -- If less than 1, width is calculated relative.
        win_width = 2 / 5,
        -- Defines default height for a new floating window. (number)
        -- If less than 1, height is calculated relative.
        win_height = 2 / 7,
        -- Defines default anchor for a new floating window.
        -- ('NW'|'SW'|'NE'|'SE')
        win_anchor = 'NE',
        -- Defines default border for a new floating window. (string|string[])
        -- Defaults to 'solid' if no 'winborder'
        win_border = 'solid',
        -- Defines `w:winhl` for a new floating window. (string?)
        win_highlight = nil,
    }
```

If the configuration does not apply, please check that the global variable has
been setup prior to defining the plugin by your plugin manager.

## Keymaps

The plugin adds the following keymaps:

- `<Plug>(FltWinOpen)`: Opens a floating window with an empty buffer.
- `<Plug>(FltWinHide)`: Hides the floating window.
- `<Plug>(FltWinToggle)`: Opens/closes the floating window.

## License

MIT
