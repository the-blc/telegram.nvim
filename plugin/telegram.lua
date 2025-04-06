-- Telegram.nvim plugin loader
if vim.g.loaded_telegram_nvim then
    return
end
vim.g.loaded_telegram_nvim = true

-- Commands
vim.api.nvim_create_user_command('Telegram', function(opts)
    if opts.args == 'start' then
        require('telegram').start()
    elseif opts.args == 'stop' then
        require('telegram').stop()
    else
        vim.notify([[
Usage:
  :Telegram start - Start Telegram client
  :Telegram stop  - Stop Telegram client
]], vim.log.levels.INFO)
    end
end, {
    nargs = '?',
    complete = function(_, _, _)
        return {'start', 'stop'}
    end,
})

-- Health checks
local health = vim.health or require('health')

local function check_tdlib()
    local tdlib_path = vim.fn.expand('$HOME/.local/lib/libtdjson.so')
    
    if vim.fn.filereadable(tdlib_path) == 1 then
        health.ok('TDLib found at ' .. tdlib_path)
    else
        health.error('TDLib not found. Please install TDLib and ensure libtdjson.so is available.')
    end
end

local function check_dependencies()
    -- Check for required plugins
    local required_plugins = {
        ['baleia.nvim'] = 'm00qek/baleia.nvim',
    }
    
    for plugin, repo in pairs(required_plugins) do
        local ok = pcall(require, plugin:gsub('%.nvim$', ''))
        if ok then
            health.ok(plugin .. ' found')
        else
            health.warn(plugin .. ' not found. Install with: ' .. repo)
        end
    end
    
    -- Check for chafa
    local chafa = vim.fn.executable('chafa')
    if chafa == 1 then
        health.ok('chafa found')
    else
        health.warn('chafa not found. Install for image preview support.')
    end
end

function _G.telegram_health()
    health.start('telegram.nvim')
    
    -- Check Neovim version
    if vim.fn.has('nvim-0.8') == 1 then
        health.ok('Neovim version >= 0.8.0')
    else
        health.error('Neovim version must be >= 0.8.0')
        return
    end
    
    -- Check TDLib
    check_tdlib()
    
    -- Check dependencies
    check_dependencies()
end

-- Set up health check command
vim.api.nvim_create_user_command('CheckHealth', function()
    _G.telegram_health()
end, {})

-- Default configuration
local default_config = {
    tdlib = {
        path = vim.fn.expand('$HOME/.local/lib/libtdjson.so'),
        verbosity = 2,
        use_test_dc = false,
    },
    ui = {
        chat_list = {
            width = "20%",
            position = "left",
        },
        messages = {
            width = "80%",
            position = "right",
        },
        input = {
            height = 3,
            position = "bottom",
        },
    },
    media = {
        image_viewer = "chafa",
        cache_dir = vim.fn.expand('$HOME/.cache/telegram.nvim'),
        max_file_size = 50 * 1024 * 1024, -- 50MB
    },
    keymaps = {
        chat_list = {
            next_chat = "<C-n>",
            prev_chat = "<C-p>",
            open_chat = "<CR>",
            close_chat = "<C-c>",
        },
        messages = {
            scroll_up = "<C-u>",
            scroll_down = "<C-d>",
            reply = "r",
            forward = "f",
            delete = "dd",
            copy = "y",
        },
        input = {
            send = "<C-s>",
            attach = "<C-a>",
            emoji = "<C-e>",
        },
    },
}

-- Setup function
_G.setup_telegram = function(opts)
    -- Merge user config with defaults
    opts = vim.tbl_deep_extend("force", default_config, opts or {})
    
    -- Initialize plugin
    require('telegram').setup(opts)
end

-- Export setup function
return {
    setup = _G.setup_telegram,
}
