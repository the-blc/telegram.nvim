local api = vim.api
local tdlib = require('telegram.core.tdlib')

local M = {}

-- Local state
local state = {
    phone_number = nil,
    auth_state = nil,
    input_buffer = nil,
    input_window = nil,
    need_quit = false,
    can_quit = false,
    have_authorization = false
}

-- Create floating input window
local function create_input_window(prompt, callback)
    local api = vim.api

    -- Create a scratch buffer for our prompt.
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'buftype', 'prompt')
    api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf, 'modified', false)
    api.nvim_buf_set_option(buf, 'modifiable', true)

    -- Configure prompt text (empty in this case).
    vim.fn.prompt_setprompt(buf, "")

    -- Create the input window.
    local width = 60
    local height = 1
    local win = api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = 'minimal',
        border = 'rounded',
        title = prompt,
        title_pos = 'center'
    })

    -- Set window-specific options.
    api.nvim_win_set_option(win, 'wrap', false)
    api.nvim_win_set_option(win, 'winblend', 10)

    -- Create an autocommand group for closing the window on BufLeave.
    local group = api.nvim_create_augroup('TelegramAuth', {
        clear = true
    })
    api.nvim_create_autocmd('BufLeave', {
        group = group,
        buffer = buf,
        callback = function()
            if api.nvim_win_is_valid(win) then
                api.nvim_win_close(win, true)
            end
        end
    })

    -- Use vim.keymap.set (which supports Lua function callbacks) for mapping keys.

    -- Map Enter key (<CR>) to grab input, notify and run the callback.
    vim.keymap.set('i', '<CR>', function()
        -- Get the current line input
        local input = api.nvim_get_current_line() or ""
        vim.notify("Input received: " .. input, vim.log.levels.DEBUG)
        if api.nvim_win_is_valid(win) then
            api.nvim_win_close(win, true)
        end
        callback(input)
    end, {
        buffer = buf,
        noremap = true,
        silent = true
    })

    -- Map Esc to simply close the window.
    vim.keymap.set('i', '<Esc>', function()
        if api.nvim_win_is_valid(win) then
            api.nvim_win_close(win, true)
        end
    end, {
        buffer = buf,
        noremap = true,
        silent = true
    })

    -- Set the current window and buffer to our input window and buffer.
    api.nvim_set_current_win(win)
    api.nvim_set_current_buf(buf)
    vim.cmd('startinsert!')

    vim.notify("Input window ready", vim.log.levels.DEBUG)

    return buf, win
end


local function show_auth_2fa_password()
    state.input_buffer, state.input_window = create_input_window('Enter 2FA password: ', function(password)
        tdlib.send({
            ["@type"] = "checkAuthenticationPassword",
            password = password
        })
    end)
end

local function show_verification_code()
    state.input_buffer, state.input_window = create_input_window('Enter verification code: ', function(code)
        tdlib.send({
            ["@type"] = "checkAuthenticationCode",
            code = code
        })
    end)
end

-- Handle authorization state updates
local function handle_auth_state(auth_state)
    -- Store current state
    state.auth_state = auth_state

    -- Handle each state
    if auth_state == "authorizationStateWaitTdlibParameters" then
        -- Set TDLib parameters
        local config = tdlib.config
        if not config then
            vim.notify("Missing TDLib configuration!", vim.log.levels.ERROR)
            return
        end

        local db_dir = vim.fn.stdpath("data") .. "/telegram-tdlib"
        local files_dir = vim.fn.stdpath("data") .. "/telegram-files"

        tdlib.send({
            ["@type"] = "setTdlibParameters",
            use_test_dc = config.use_test_dc,
            database_directory = db_dir,
            files_directory = files_dir,
            use_file_database = true,
            use_chat_info_database = true,
            use_message_database = true,
            use_secret_chats = false,
            api_id = config.api_id,
            api_hash = config.api_hash,
            system_language_code = "en",
            device_model = "Neovim",
            application_version = "1.0",
            enable_storage_optimizer = true
        })

    elseif auth_state == "authorizationStateWaitEncryptionKey" then
        -- Silently send empty encryption key
        tdlib.send({
            ["@type"] = "checkDatabaseEncryptionKey",
            encryption_key = ""
        })

    elseif auth_state == "authorizationStateWaitPhoneNumber" then
        -- Show phone number input
        state.input_buffer, state.input_window = create_input_window('Enter phone number: ', function(phone)
            state.phone_number = phone
            vim.notify("Phone number sent: " .. phone, vim.log.levels.INFO)

            tdlib.send({
                ["@type"] = "setAuthenticationPhoneNumber",
                phone_number = phone
            })
        end)

    elseif auth_state == "authorizationStateWaitOtherDeviceConfirmation" then
        -- Show link confirmation message
        vim.notify("Please confirm this login link on another device", vim.log.levels.INFO)

    elseif auth_state == "authorizationStateWaitCode" then
        -- Show verification code input
        show_verification_code()

    elseif auth_state == "authorizationStateWaitRegistration" then
        -- Show registration inputs
        state.input_buffer, state.input_window = create_input_window('Enter your name: ', function(name)
            tdlib.send({
                ["@type"] = "registerUser",
                first_name = name,
                last_name = ""
            })
        end)

    elseif auth_state == "authorizationStateWaitPassword" then
        -- Show password input
        show_auth_2fa_password()

    elseif auth_state == "authorizationStateReady" then
        -- Successfully authenticated
        state.have_authorization = true
        vim.notify("Successfully logged in to Telegram!", vim.log.levels.INFO)

        -- Clean up input window if it exists
        if state.input_window and api.nvim_win_is_valid(state.input_window) then
            api.nvim_win_close(state.input_window, true)
        end

    elseif auth_state == "authorizationStateLoggingOut" then
        state.have_authorization = false
        vim.notify("Logging out of Telegram...", vim.log.levels.INFO)

    elseif auth_state == "authorizationStateClosing" then
        state.have_authorization = false
        vim.notify("Closing Telegram session...", vim.log.levels.INFO)

    elseif auth_state == "authorizationStateClosed" then
        vim.notify("Telegram session closed", vim.log.levels.INFO)
        if not state.need_quit then
            -- Recreate client
            tdlib.cleanup()
            tdlib.init(tdlib.config)
        else
            state.can_quit = true
        end

    else
        vim.notify("Unknown auth state: " .. auth_state, vim.log.levels.WARN)
    end
end


-- Set up authentication state handlers
local function setup_handlers()
    -- Handle authorization state updates
    tdlib.on("updateAuthorizationState", function(update)
        handle_auth_state(update.authorization_state["@type"])
    end)

    -- Handle errors
    tdlib.on("error", function(error)
        if error.message == "PASSWORD_HASH_INVALID" then
            show_auth_2fa_password()
        end
        vim.notify("Telegram error: " .. error.message, vim.log.levels.ERROR)
    end)
end

-- Start authentication process
function M.start()
    setup_handlers()

    -- Check current authorization state
    local current_state = tdlib.get_auth_state()
    if current_state then
        handle_auth_state(current_state)
    else
        -- Request current state
        tdlib.send({
            ["@type"] = "getAuthorizationState"
        })
    end
end

-- Check if authenticated
function M.is_authenticated()
    return state.have_authorization
end

-- Get current phone number
function M.get_phone_number()
    return state.phone_number
end

-- Logout
function M.logout()
    state.need_quit = false
    tdlib.send({
        ["@type"] = "logOut"
    })
end

-- Clean up
function M.cleanup()
    if state.input_window and api.nvim_win_is_valid(state.input_window) then
        api.nvim_win_close(state.input_window, true)
    end
    state.input_buffer = nil
    state.input_window = nil
    state.phone_number = nil
    state.auth_state = nil
    state.need_quit = false
    state.can_quit = false
    state.have_authorization = false
end

return M
