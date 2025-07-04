-- darkmatter.lua - Windower Addon
-- Automates Dark Matter augment attempts via Oseem
-- this lua is not tested

_addon.name = 'darkmatter'
_addon.version = '1.0'
_addon.author = 'hehehe'
_addon.commands = {'dm', 'darkmatter'}

packets = require('packets')
res = require('resources')
texts = require('texts')

-- ============================
-- Configurable Section
-- ============================
local gear_list = {
    -- Format: {name = "item name", id = item_id (decimal), desired = {"STAT+20", "Accuracy+"}}
    {name="Herculean Helm", id=26794, desired={"Accuracy+", "STR+"}},
    {name="Valorous Mail", id=26891, desired={"Attack+", "Store TP+"}},
    -- Add more gear pieces here
}

-- Distance to trigger NPC
local NPC_NAME = "Oseem"
local INTERACT_RANGE = 6

-- ============================
-- State Tracking
-- ============================
local augmenting = false
local current_index = 1
local retry_limit = 5
local retries = 0

-- ============================
-- Helpers
-- ============================
function find_npc(name)
    for i,v in pairs(windower.ffxi.get_mob_array()) do
        if v and v.name == name and v.distance < INTERACT_RANGE^2 then
            return v
        end
    end
    return nil
end

function interact_with_oseem(npc)
    windower.packets.inject_outgoing(0x1A, packets.new('outgoing', 0x1A, {
        Target = npc.id,
        TargetIndex = npc.index,
        Category = 0x00,
    }))
end

function initiate_augment()
    local item = gear_list[current_index]
    windower.add_to_chat(200, ('[DM] Attempting augment on: %s'):format(item.name))
    local npc = find_npc(NPC_NAME)
    if npc then
        interact_with_oseem(npc)
    else
        windower.add_to_chat(123, '[DM] Oseem not found nearby!')
        augmenting = false
    end
end

function check_augments(item_data)
    local item = gear_list[current_index]
    if not item_data or not item_data.extdata then return false end
    local augments = extdata.decode(item_data)
    if not augments or not augments.augments then return false end
    for _,desired in ipairs(item.desired) do
        local match = false
        for _,aug in ipairs(augments.augments) do
            if aug and aug:find(desired) then
                match = true
                break
            end
        end
        if not match then return false end
    end
    return true
end

function process_next()
    if current_index > #gear_list then
        windower.add_to_chat(200, '[DM] All gear processed.')
        augmenting = false
        return
    end

    local inventory = windower.ffxi.get_items()
    local item_info = inventory.equipment or {}
    local inv_item = windower.ffxi.get_items(0, item_info[current_index])

    if check_augments(inv_item) then
        windower.add_to_chat(200, ('[DM] %s has desired augments. Skipping.'):format(gear_list[current_index].name))
        current_index = current_index + 1
        retries = 0
        process_next()
    else
        if retries < retry_limit then
            retries = retries + 1
            initiate_augment()
        else
            windower.add_to_chat(123, ('[DM] Retry limit reached for %s. Skipping.'):format(gear_list[current_index].name))
            retries = 0
            current_index = current_index + 1
            process_next()
        end
    end
end

-- ============================
-- Incoming Packet Handler
-- ============================
windower.register_event('incoming chunk', function(id, data)
    if not augmenting then return end

    if id == 0x034 or id == 0x032 then -- Menu opened
        -- Simulate menu navigation (Dark Matter path)
        coroutine.sleep(1.5)
        windower.send_command('input /dialog yes')
        coroutine.sleep(3.0)
        current_index = current_index + 1
        retries = 0
        process_next()
    end
end)

-- ============================
-- Commands
-- ============================
windower.register_event('addon command', function(cmd, ...)
    if cmd == 'start' then
        if augmenting then
            windower.add_to_chat(123, '[DM] Already running.')
            return
        end
        augmenting = true
        current_index = 1
        retries = 0
        process_next()
    elseif cmd == 'stop' then
        augmenting = false
        windower.add_to_chat(200, '[DM] Stopped.')
    elseif cmd == 'status' then
        windower.add_to_chat(200, ('[DM] Index: %d, Retry: %d, Running: %s'):format(current_index, retries, tostring(augmenting)))
    end
end)

-- ============================
-- Extdata decoding (simple helper)
-- ============================
extdata = require('extdata')
