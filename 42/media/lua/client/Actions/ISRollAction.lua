

require "TimedActions/ISBaseTimedAction"
require 'Shared_time'

ISRollAction = ISBaseTimedAction:derive("ISRollAction");
ISRollAction.RollTimeMs = 900.0
ISRollAction.RollNESODistance = ISRollAction.RollTimeMs * 0.003
ISRollAction.RollDistance = math.sqrt(ISRollAction.RollNESODistance*ISRollAction.RollNESODistance*2)
ISRollAction.RollDistanceRun = ISRollAction.RollDistance * 1.15
ISRollAction.RollDistanceSprint = ISRollAction.RollDistance * 1.30

function ISRollAction:isValidStart()
    return true
end

function ISRollAction:isValid()
    return not self.isInvalid
end

function ISRollAction:animEvent(event, parameter)
    if event == 'RollDone' then
        self.isInvalid = true
        self:releaseAnimControl()
        if Roll.Verbose then  print ('ISRollAction stop.') end
    end
end

function ISRollAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic);
    if not self.isInvalid then
        self.character:setRunning(false)
        self.character:setSprinting(false)
        self.character:setIsAiming(false)
        self.character:setForwardDirection(self.directionX, self.directionY)
    end
    
    --movement update
    self.RollRefTimeMs = self:updateDistanceAlteration(self.RollRefTimeMs, self.RollStopTimeMs, self.RollSpeedX, self.RollSpeedY, self.RollSpeedZ, self.character)
end

function ISRollAction:start()
    self.action:setUseProgressBar(false)
    
    local anim = 'RollAction'
    self.isSprinting = self.character:isSprinting()
    self.isRunning = self.character:isRunning()
    self:setActionAnim(anim);
    self:consumeEndurance()
    self.callBackCalmDown = function ()ISRollAction.calmDown(self)end
    Events.OnTick.Add(self.callBackCalmDown)
    if Roll.Verbose then print ('ISRollAction start '..anim) end
    
    --start movement
    local RollDirection = self.character:getAnimAngleRadians()
    self.directionX = math.cos(RollDirection)
    self.directionY = math.sin(RollDirection)
    local distance = self.isSprinting and ISRollAction.RollDistanceSprint or self.isRunning and ISRollAction.RollDistanceRun or ISRollAction.RollDistance
    local deltaX = distance*self.directionX
    local deltaY = distance*self.directionY
    local deltaZ = 0.0
    
    local deltaTime = ISRollAction.RollTimeMs / 1000.0
    if deltaTime > 0 then
        local RollEndTime = 0
        local currentTime = getTimestampMs()
        if ISRollAction.RollTimeMs then RollEndTime = currentTime + ISRollAction.RollTimeMs end
        self.RollRefTimeMs = currentTime
        self.RollSpeedX = deltaX / deltaTime
        self.RollSpeedY = deltaY / deltaTime
        self.RollSpeedZ = deltaZ / deltaTime
        self.RollStopTimeMs = RollEndTime
    else
        self.isInvalid = true
    end
end

function ISRollAction:stop()
    self:releaseAnimControl()
    ISBaseTimedAction.stop(self);
end

function ISRollAction:perform()
    self:releaseAnimControl()
    ISBaseTimedAction.perform(self);
end

function ISRollAction:new(character)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character;
    o.stopOnWalk = false;
    o.stopOnRun = false;
    o.stopOnAim = false;
    o.isInvalid = false;
    o.maxTime = -1;
    return o
end

function ISRollAction:releaseAnimControl()
    self.character:setRunning(self.isRunning)
    self.character:setSprinting(self.isSprinting)
    self.character:setIgnoreMovement(false)
    if self.callBackCalmDown then
        Events.OnTick.Remove(self.callBackCalmDown)
    end
    if Roll.Verbose then print ('ISRollAction calmDown releaseAnimControl') end
end

--high Endurance cost because Roll is overpowered to escape Zs
function ISRollAction:consumeEndurance()
    local stats = self.character:getStats()
    if not stats then return end

    -- Prefer 0..1 endurance (regenerates reliably across builds)
    if stats.getEndurance and stats.setEndurance then
        local ok, e = pcall(function() return stats:getEndurance() end)
        if ok and e ~= nil then
            local cur = tonumber(e) or 0

            -- Defaults:
            -- Walk - 0.25
            -- Run - 0.28
            -- Sprint - 0.32
            local walkCost   = Roll and Roll.EnduranceCostWalk   or 0.10
            local runCost    = Roll and Roll.EnduranceCostRun    or 0.13
            local sprintCost = Roll and Roll.EnduranceCostSprint or 0.15

            local chunk = self.isSprinting and sprintCost or self.isRunning and runCost or walkCost
            pcall(function() stats:setEndurance(math.max(0, cur - chunk)) end)
            return
        end
    end

    -- Fallback (older/stat-scale builds)
    if stats.remove and CharacterStat and CharacterStat.ENDURANCE and ZomboidGlobals then
        local endCoef = self.isSprinting and 700.0 or self.isRunning and 600.0 or 500.0
        pcall(function() stats:remove(CharacterStat.ENDURANCE, (ZomboidGlobals.RunningEnduranceReduce or 0) * endCoef) end)
    end
end

--removes sprint and run to allow the animation to be played
function ISRollAction:calmDown()
    if self.character:isCurrentState(PlayerFallingState.instance()) then
        self.character:StopAllActionQueue()
        self.character:setIgnoreMovement(false)
        Events.OnTick.Remove(self.callBackCalmDown)
        if Roll.Verbose then print ('ISRollAction calmDown falling.') end
    elseif not self.character:getCharacterActions():isEmpty() then
        if not self.isInvalid then
            self.character:setIgnoreMovement(true)
            self.character:setRunning(false)
            self.character:setSprinting(false)
            self.character:setIsAiming(false)
            self.character:setForwardDirection(self.directionX, self.directionY)
        end
    else
        Events.OnTick.Remove(self.callBackCalmDown)
        self.character:setIgnoreMovement(false)
        if Roll.Verbose then print ('ISRollAction calmDown backup.') end
    end
end

function ISRollAction:updateDistanceAlteration(lastUpdateTime, stopTimeMs, speedX, speedY, speedZ, character)--TODO put this in TchernoLib
    --movement update
    local pendingRollTime = getTimestampMs()
    if pendingRollTime > stopTimeMs then--this is the last update, deactivate callback
        self.isInvalid = true
        pendingRollTime = stopTimeMs;
    end
    if lastUpdateTime == nil then--should not happend
        lastUpdateTime = pendingRollTime
        return
    end
    local pendingRollDtS = (pendingRollTime-lastUpdateTime)/1000;
    lastUpdateTime = pendingRollTime
    
    local deltaX = speedX*pendingRollDtS
    local deltaY = speedY*pendingRollDtS
    local deltaZ = speedZ*pendingRollDtS
    if MovePlayer.canDoMoveTo(character,deltaX,deltaY,deltaZ) then
        MovePlayer.Teleport(character,
            character:getX()+deltaX,
            character:getY()+deltaY,
            character:getZ()+deltaZ)
    end
    return lastUpdateTime
end

