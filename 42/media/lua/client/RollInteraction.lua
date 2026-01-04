Roll = Roll or {}
Roll.Verbose = Roll.Verbose or false
Roll.inhibit = Roll.inhibit or false -- inhibit reading once computed
Roll._keyDown = Roll._keyDown or false -- edge-detect for key presses

require 'RollConfig'

-- Safe endurance getter for different builds
local function getEnduranceValue(isoPlayer)
    if not isoPlayer then return nil end
    local stats = isoPlayer:getStats()
    if not stats then return nil end

    -- Preferred (works in many builds): 0..1
    if stats.getEndurance then
        local ok, val = pcall(function() return stats:getEndurance() end)
        if ok then return val end
    end

    -- Fallback for builds where CharacterStat exists
    if stats.get and CharacterStat and CharacterStat.ENDURANCE then
        local ok, val = pcall(function() return stats:get(CharacterStat.ENDURANCE) end)
        if ok then return val end
    end

    return nil
end

function Roll.OnPlayerUpdate(isoPlayer)
    if not isoPlayer then return end
    if isoPlayer:getVehicle() then return end -- don't Roll in the car
    local square = isoPlayer:getSquare()
    if not square then return end -- teleport / not placed yet
    -- don't roll while falling
    if isoPlayer:isCurrentState(PlayerFallingState.instance()) then return end


    local keyDown = isKeyPressed(Roll.getKey())
    if not keyDown then Roll._keyDown = false end

    -- when pressing interaction key while no action active (on key-down edge)
    if keyDown and not Roll._keyDown
        and not isoPlayer:hasTimedActions()
        and not square:HasStairs()
        and not Roll.isHealthInhibitingRoll(isoPlayer)
        and Roll.hasEnoughEndurance(isoPlayer)
    then
        if Roll.Verbose then
            print('Roll.OnPlayerUpdate targetSquareValidForRoll '..sq2str(square))
        end

        Roll._keyDown = true
        ISTimedActionQueue.clear(isoPlayer)
        ISTimedActionQueue.add(ISRollAction:new(isoPlayer))
    end
end

Events.OnPlayerUpdate.Add(Roll.OnPlayerUpdate)


function Roll.hasEnoughEndurance(isoPlayer)
    local e = getEnduranceValue(isoPlayer)

    -- If we can't read endurance, don't hard-block rolling
    if e == nil then
        if Roll.Verbose then print('Roll.hasEnoughEndurance: endurance unavailable -> allow') end
        return true
    end

    -- If endurance looks like 0..1, use a sane threshold
    if e <= 1.5 then
        -- You can override in RollConfig: Roll.MinEndurance = 0.20
        local min = Roll.MinEndurance or 0.20
        return e >= min
    end

    -- Otherwise, keep old "stat scale" logic (protected)
    local reduce = (ZomboidGlobals and ZomboidGlobals.RunningEnduranceReduce) or 0
    local ticks = Roll.RollEnduranceTicks or 4807.7
    return e > (reduce * ticks)
end