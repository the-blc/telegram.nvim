# Telegram.nvim

A Telegram client for Neovim. WIP. NOT READY FOR USE.

## Currently what it can do

-   Authorization (with or without 2fa password)
-   Chat list display and basic updates

## Goals

-   💬 Complete Telegram messaging functionality
-   🖼️ Media support (images, files, voice messages)
-   😊 Emoji and sticker support
-   🔒 Secure authentication and session management
-   ⌨️ Vim-style keyboard navigation
-   📱 Real-time message updates
-   🎨 Terminal graphics with chafa support

## Requirements

-   Neovim >= 0.8.0
-   TDLib (Telegram Database Library) >= 1.8.40
-   chafa (optional, for terminal graphics)
-   Required plugins:
    -   baleia.nvim (used for highlighting/rendering components)

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'the-blc/telegram.nvim',
    requires = {
        'm00qek/baleia.nvim',
    },
    config = function()
        require('telegram').setup({
            -- Configuration options below
        })
    end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'the-blc/telegram.nvim',
    dependencies = {
        'm00qek/baleia.nvim',
    },
    config = function()
        require('telegram').setup({
            -- Configuration options below
        })
    end
}
```

### Install TDLib

TDLib (Telegram Database Library) is required for this plugin to work. The plugin supports both the standard TDLib C API and the JSON client API versions, automatically detecting the installed one.

#### macOS

```bash
brew install tdlib
```

#### Ubuntu/Debian

```bash
sudo apt install libtdjson-dev # Or libtdjson - check package availability
```

#### Arch Linux

```bash
sudo pacman -S tdlib
```

**Note:** After installation, you might need to configure the `tdlib.path` setting (see below) if the plugin cannot find the library automatically. Common locations include `/usr/lib`, `/usr/local/lib`, or the output of `brew --prefix tdlib`/lib on macOS.

### Install chafa (Optional, for planned image support)

#### macOS

```bash
brew install chafa
```

#### Ubuntu/Debian

```bash
sudo apt install chafa
```

#### Arch Linux

```bash
sudo pacman -S chafa
```

## Configuration

### Getting Telegram API Credentials

To use this plugin, you need to obtain your own Telegram API credentials:

1.  Visit https://my.telegram.org and log in with your Telegram account
2.  Click on 'API development tools'
3.  Create a new application if you haven't already
    -   App title: "Neovim Telegram" (or any name you prefer)
    -   Short name: "nvim_tg" (or any short name)
    -   Platform: "Desktop"
    -   Description: "Telegram client for Neovim" (or your own description)
4.  Note down your `api_id` (a number) and `api_hash` (a string)

### Plugin Configuration

```lua
require('telegram').setup({
    tdlib = {
        -- Path to TDLib shared library.
        -- The plugin tries common paths, but you may need to set this explicitly.
        -- Adjust based on your actual TDLib installation location.
        -- Examples: '/usr/lib/libtdjson.so', '/opt/homebrew/lib/libtdjson.dylib'
        path = nil, -- Default: nil (attempts auto-detection)
        -- Required: Your Telegram API credentials
        api_id = 12345,  -- Replace with your numeric API ID from my.telegram.org
        api_hash = "your_api_hash_string",  -- Replace with your API hash from my.telegram.org
        -- Use test DC (for development, usually false for normal use)
        use_test_dc = false,
    },
    ui = {
        chat_list = {
            -- Width of chat list window
            width = "20%", -- Can be percentage string or number (columns)
            position = "left", -- 'left' or 'right'
        },
        -- Configuration for message and input windows will go here
        -- messages = { width = "80%", position = "right" },
        -- input = { height = 3, position = "bottom" },
    },
    media = {
        -- Image viewer command (for future image support)
        image_viewer = "chafa",
        -- Cache directory for media files (for future media support)
        cache_dir = vim.fn.stdpath('cache') .. '/telegram.nvim',
        -- Maximum file size for auto-download (in bytes, for future use)
        max_file_size = 50 * 1024 * 1024, -- 50MB
    },
    keymaps = {
        chat_list = { -- Keymaps active when the chat list window is focused
            next_chat = "<C-n>",
            prev_chat = "<C-p>",
            open_chat = "<CR>", -- Selects chat (message viewing WIP)
            close_chat = "<C-c>", -- Placeholder/unused for now
        },
        -- Keymaps for messages and input windows will be configurable here
        -- once those features are implemented. Example:
        -- messages = {
        --     scroll_up = "<C-u>",
        --     scroll_down = "<C-d>",
        --     reply = "r",
        -- },
        -- input = {
        --     send = "<C-s>",
        --     attach = "<C-a>",
        -- }
    },
})
```

## Usage

### Commands

-   `:Telegram start` - Start the Telegram client and initiate authentication if needed.
-   `:Telegram stop` - Stop the Telegram client and close its windows.

### Authentication

On the first start, or if the session expires, you'll be prompted within the Neovim command line or a popup to:

1.  Enter your phone number (international format, e.g., +12223334444)
2.  Enter the verification code sent to your Telegram account (check other logged-in devices)
3.  Enter your 2FA password (if you have one enabled)

Your session details will be stored by TDLib for subsequent uses.

### Navigating the Chat List

While the chat list window is focused (using default keymaps):

-   `<C-n>`: Move focus to the next chat in the list.
-   `<C-p>`: Move focus to the previous chat in the list.
-   `<CR>`: Select the highlighted chat. (Note: Actually viewing messages in the chat is Work-In-Progress and may not function yet).
-   `<C-c>`: Currently mapped by default, but its specific function in the chat list might change or is not yet defined.

## Contributing

Contributions are welcome! As the project is WIP, please feel free to open an issue to discuss potential features or changes before submitting a Pull Request.

## Acknowledgments

-   [TDLib](https://github.com/tdlib/td) - Telegram Database Library
-   [chafa](https://github.com/hpjansson/chafa) - Terminal graphics library
-   [baleia.nvim](https://github.com/m00qek/baleia.nvim) - Buffer analysis and highlighting library