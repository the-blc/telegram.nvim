-- User management for Telegram.nvim
local events = require('telegram.core.events')
local tdlib = require('telegram.core.tdlib')

local M = {}

-- User cache state
local state = {
    users = {}, -- Map of user_id to user data
    profile_photos = {} -- Map of user_id to profile photo data
}

-- Initialize user data
function M.init()
    -- Listen for user updates
    events.on(events.events.USER_PROFILE_UPDATED, function(user)
        if not user then
            return
        end

        -- If we received a full user object
        if user["@type"] == "user" then
            state.users[user.id] = {
                id = user.id,
                first_name = user.first_name,
                last_name = user.last_name or "",
                username = user.usernames and user.usernames.active_usernames[1] or "",
                is_bot = user.type["@type"] == "userTypeBot",
                is_premium = user.is_premium,
                is_verified = user.is_verified,
                status = user.status,
                profile_photo = user.profile_photo and {
                    id = user.profile_photo.id,
                    small = user.profile_photo.small,
                    big = user.profile_photo.big,
                    minithumbnail = user.profile_photo.minithumbnail
                } or nil
            }
            -- If we received a user full info update
        elseif user.user_full_info then
            if state.users[user.user_id] then
                state.users[user.user_id].full_info = user.user_full_info
            end
        end
    end)
end

function M.add_user(user_id, user)
    if not state.users[user.user_id] then
        state.users[user.user_id] = user
    end
end

-- Get user by ID
function M.get_user(user_id)
    if not state.users[user_id] then
        -- Request user info if we don't have it
        tdlib.get_user(user_id)
        return nil
    end
    return state.users[user_id]
end

-- Get user's display name
function M.get_display_name(user_id)
    local user = state.users[user_id]
    if not user then
        return "Unknown User"
    end

    if user.last_name and user.last_name ~= "" then
        return string.format("%s %s", user.first_name, user.last_name)
    end
    return user.first_name
end

-- Get user's status text
function M.get_status_text(user_id)
    local user = state.users[user_id]
    if not user then
        return ""
    end

    if user.status then
        if user.status["@type"] == "userStatusOnline" then
            return "online"
        elseif user.status["@type"] == "userStatusOffline" then
            return "offline"
        elseif user.status["@type"] == "userStatusRecently" then
            return "recently"
        elseif user.status["@type"] == "userStatusLastWeek" then
            return "last week"
        elseif user.status["@type"] == "userStatusLastMonth" then
            return "last month"
        end
    end
    return ""
end

-- Get user's profile photo file path
function M.get_profile_photo(user_id)
    local user = state.users[user_id]
    if not user or not user.profile_photo then
        return nil
    end

    -- Check if we have a local copy
    if user.profile_photo.small then
        if user.profile_photo.small["local"].is_downloading_completed then
            return user.profile_photo.small["local"].path
        end

        -- Start download if not already downloading
        if not user.profile_photo.small["local"].is_downloading_active then
            tdlib.download_file(user.profile_photo.id, 1)
        end
    elseif user.profile_photo.big then
        if user.profile_photo.big["local"].is_downloading_completed then
            return user.profile_photo.big["local"].path
        end

        -- Start download if not already downloading
        if not user.profile_photo.big["local"].is_downloading_active then
            tdlib.download_file(user.profile_photo.id, 1)
        end
    end

    return nil
end

-- Clean up
function M.cleanup()
    state.users = {}
    state.profile_photos = {}
end

return M
