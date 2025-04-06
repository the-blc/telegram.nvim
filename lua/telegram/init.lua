-- Telegram.nvim - Telegram client for Neovim
-- Author: Bugra Levent Condal

local M = {}

    -- Default configuration
M.config = {
    -- TDLib settings
    tdlib = {
        path = vim.fn.expand('$HOME/.local/lib/libtdjson.so'),
        api_id = nil,  -- Required: Your Telegram API ID
        api_hash = nil,  -- Required: Your Telegram API hash
        use_test_dc = false,
    },
    -- UI settings
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
    -- Media settings
    media = {
        image_viewer = "chafa",
        cache_dir = vim.fn.expand('$HOME/.cache/telegram.nvim'),
        max_file_size = 50 * 1024 * 1024, -- 50MB
    },
    -- Keymaps
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

-- Internal state
local state = {
    initialized = false,
    authenticated = false,
    current_chat = nil,
    buffers = {},
    windows = {},
}

-- Forward declarations
local setup_commands, setup_autocommands, setup_highlights

-- Initialize the plugin
function M.setup(opts)
    -- Merge user config with defaults
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    -- Validate configuration
    if not M.config.tdlib.api_id or not M.config.tdlib.api_hash then
        error("Telegram API credentials (api_id and api_hash) are required. Get them from https://my.telegram.org")
    end

    if not vim.fn.filereadable(M.config.tdlib.path) then
        error("TDLib not found at " .. M.config.tdlib.path)
    end

    -- Create cache directory if it doesn't exist
    vim.fn.mkdir(M.config.media.cache_dir, "p")

    -- Load core components
    local core = {
        tdlib = require('telegram.core.tdlib'),
        auth = require('telegram.core.auth'),
        events = require('telegram.core.events'),
    }

    -- Load UI components
    local ui = {
        layout = require('telegram.ui.layout'),
        chat_list = require('telegram.ui.chat_list'),
        messages = require('telegram.ui.messages'),
        input = require('telegram.ui.input'),
    }

    -- Initialize core components
    core.tdlib.init(M.config.tdlib)
    core.events.init()
    users = require('telegram.ui.users')
    users.init()
    -- Set up UI
    ui.layout.init(M.config.ui)
    
    -- Set up commands
    setup_commands()
    
    -- Set up autocommands
    setup_autocommands()
    
    -- Set up highlights
    setup_highlights()

    -- Mark as initialized
    state.initialized = true
end

-- Set up plugin commands
function setup_commands()
    local commands = {
        TelegramStart = 'lua require("telegram").start()',
        TelegramStop = 'lua require("telegram").stop()',
        TelegramChat = 'lua require("telegram").open_chat(<args>)',
        TelegramSend = 'lua require("telegram").send_message(<args>)',
        TelegramFile = 'lua require("telegram").send_file(<args>)',
        TelegramVoice = 'lua require("telegram").record_voice()',
        TelegramEmoji = 'lua require("telegram").emoji_picker()',
    }

    for name, cmd in pairs(commands) do
        vim.api.nvim_create_user_command(name, cmd, {})
    end
end

-- Set up autocommands
function setup_autocommands()
    local group = vim.api.nvim_create_augroup('Telegram', { clear = true })
    
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            M.stop()
        end,
    })
end

-- Set up highlights
function setup_highlights()
    local highlights = {
        TelegramChatName = { link = 'Title' },
        TelegramMessageTime = { link = 'Comment' },
        TelegramMessageText = { link = 'Normal' },
        TelegramMessageOwn = { link = 'Statement' },
        TelegramUnread = { link = 'Error' },
        TelegramOnline = { link = 'String' },
    }

    for name, hl in pairs(highlights) do
        vim.api.nvim_set_hl(0, name, hl)
    end
end

-- Start the Telegram client
function M.start()
    if not state.initialized then
        error("Telegram.nvim not initialized. Call setup() first.")
    end

    -- Start authentication first
    local auth = require('telegram.core.auth')
    auth.start()

    -- Initialize UI layout after successful authentication
    require('telegram.core.tdlib').on("updateAuthorizationState", function(update)
        if update.authorization_state["@type"] == "authorizationStateReady" then
            state.authenticated = true
            -- Create UI layout
            local layout = require('telegram.ui.layout')
            layout.create(function ()
                local chat_list = require('telegram.ui.chat_list')
                chat_list.init()
                local messages = require('telegram.ui.messages')
                messages.init()
            end)
        end
    end)
end

-- Stop the Telegram client
function M.stop()
    if state.initialized then
        -- Clean up UI
        require('telegram.ui.layout').destroy()
        
        -- Clean up TDLib
        require('telegram.core.tdlib').cleanup()
        
        -- Reset state
        state.initialized = false
        state.authenticated = false
        state.current_chat = nil
        state.buffers = {}
        state.windows = {}
    end
end

-- Public API
M.open_chat = function(chat_id)
    if not state.initialized then return end
    require('telegram.ui.chat_list').open_chat(chat_id)
end

M.send_message = function(text)
    if not state.initialized or not state.current_chat then return end
    require('telegram.core.tdlib').send_message(state.current_chat, text)
end

M.send_file = function(path)
    if not state.initialized or not state.current_chat then return end
    require('telegram.core.tdlib').send_file(state.current_chat, path)
end

M.record_voice = function()
    if not state.initialized or not state.current_chat then return end
    require('telegram.media.voice').start_recording()
end

M.emoji_picker = function()
    if not state.initialized then return end
    require('telegram.ui.emoji').show_picker()
end

return M
