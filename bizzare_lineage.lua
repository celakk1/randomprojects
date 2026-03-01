loadstring(game:HttpGet('https://raw.githubusercontent.com/catowice/p/main/library.lua'))()
local runServiceVM = loadstring(game:HttpGet('https://pastebin.com/raw/jFXZEJSy'))()

local ui = UILib
if not ui then
    return
end

if type(runServiceVM) ~= "table" then
    runServiceVM = nil
end

local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local player = players.LocalPlayer

local config = {
    defaultLockY = -410,
    lockYMin = -450,
    lockYMax = -410,
    lockMoveRange = 100,
    lockMoveSpeed = 520,
    itemCacheRefreshInterval = 0.75,
    fallbackDeltaTime = 0.016,
    rainbowSpeed = 0.35,
    notificationCooldown = 0.8,
    maxNotificationQueue = 10,
    collectFlySpeedDefault = 1000,
    collectFlySpeedMin = 60,
    collectFlySpeedMax = 1200,
    collectArrivalDistance = 30,
    collectTeleportHeight = 10,
    collectUnderMapYOffset = 260,
    collectTeleportCooldown = 0.35,
    collectPreHoldDelay = 0.2,
    collectHoldDuration = 1.0,
    collectRetryCooldown = 3.0,
    collectSkipPlayerRadiusXZ = 5,
    collectInstantTeleportDistance = 300,
    maxTrackedItems = 300,
    maxRenderedItems = 150,
    addressRetentionSeconds = 240,
    occupiedRecheckInterval = 1.0,
    maxOccupiedQueue = 200,
}

local idleCollectPoints = {
    Vector3.new(643, 945, -1396),
    Vector3.new(1352, 997, -1367),
    Vector3.new(2754, 982, 193),
    Vector3.new(1458, 1155, 1389),
    Vector3.new(244, 1065, 471),
}

local trackedItemNames = {
    "Stone Mask",
    "Imperfect Aja",
    "Red Stone of Aja",
    "Lucky Arrow",
    "Rokakaka",
    "Stat Point Essence",
    "Stand Arrow",
    "DIO's Diary",
    "Stand Skin Essence",
    "Stand Stat Essence",
    "Stand Personality Essence",
    "Stand Conjuration Essence",
    "Motorcycle Tire",
    "Motorcycle Body",
    "Custom Clothing Essence",
    "Lucky Personality Essence",
    "Face Reroll",
}

local trackedItemLookup = {}
for _, itemName in ipairs(trackedItemNames) do
    trackedItemLookup[itemName] = true
end

local state = {
    yLock = false,
    itemESP = false,
    shouldUnload = false,
    cachedReturnPosition = nil,
    lockYValue = config.defaultLockY,
    lockMotionOrigin = nil,
    lockOffsetX = 0,
    lockOffsetZ = 0,
    lockDirection = 1,
    itemCache = {},
    itemCacheLastRefresh = 0,
    seenItemAddresses = {},
    itemScanInitialized = false,
    itemCacheRefreshInterval = config.itemCacheRefreshInterval,
    maxRenderedItems = config.maxRenderedItems,
    spawnNotifications = true,
    espShowBox = true,
    espShowText = true,
    espRainbowBox = true,
    espBoxThickness = 2,
    notificationQueue = {},
    lastNotificationAt = 0,
    autoCollect = false,
    collectFlySpeed = config.collectFlySpeedDefault,
    collectArrivalDistance = config.collectArrivalDistance,
    collectTeleportHeight = config.collectTeleportHeight,
    collectUnderMapYOffset = config.collectUnderMapYOffset,
    collectPreHoldDelay = config.collectPreHoldDelay,
    collectHoldDuration = config.collectHoldDuration,
    collectSkipPlayerRadiusXZ = config.collectSkipPlayerRadiusXZ,
    autoCollectUseIdlePoints = true,
    autoCollectUseUnderMapTravel = true,
    autoCollectSkipOccupied = true,
    collectPauseUntil = 0,
    collectHoldStartAt = 0,
    collectHoldUntil = 0,
    collectTeleportCooldownUntil = 0,
    collectHoldingKey = false,
    collectCooldownByAddress = {},
    collectIdlePointIndex = nil,
    collectIdleAtPoint = false,
    occupiedItemQueue = {},
    occupiedQueueSize = 0,
    lockYWasEnabledBeforeCollect = false,
    frameErrorCount = 0,
    runtimeCooldownUntil = 0,
}

if _G.__bizzareLineageUnload then
    pcall(_G.__bizzareLineageUnload)
    task.wait(0.05)
end

local keybinds = {
    yLock = 0xDB,   -- [
    itemESP = 0xDD, -- ]
}

local keyDownState = {}
local itemDrawings = {}

local function getRootPart()
    local character = player and player.Character
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
end

local function setLockYPosition(forceExact)
    local root = getRootPart()
    if not root then
        return
    end

    local pos = root.Position
    local needsClamp = forceExact or pos.Y < state.lockYValue
    if needsClamp then
        pcall(function()
            root.Position = Vector3.new(pos.X, state.lockYValue, pos.Z)
        end)
    end

    if pos.Y < state.lockYValue then
        pcall(function()
            local vel = root.AssemblyLinearVelocity
            if vel and vel.Y < 0 then
                root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
            end
        end)
    end
end

local function stepSquareLockMovement(deltaTime)
    local root = getRootPart()
    if not root then
        return
    end

    if not state.lockMotionOrigin then
        local pos = root.Position
        state.lockMotionOrigin = Vector3.new(pos.X, state.lockYValue, pos.Z)
        state.lockOffsetX = 0
        state.lockOffsetZ = 0
        state.lockDirection = 1
    end

    local remainingDistance = (deltaTime or config.fallbackDeltaTime) * config.lockMoveSpeed
    local range = config.lockMoveRange

    while remainingDistance > 0 do
        if state.lockDirection == 1 then
            local needed = range - state.lockOffsetX
            local step = math.min(math.abs(needed), remainingDistance)
            state.lockOffsetX = state.lockOffsetX + step
            remainingDistance = remainingDistance - step
            if state.lockOffsetX >= range then
                state.lockDirection = 2
            end
        elseif state.lockDirection == 2 then
            local needed = range - state.lockOffsetZ
            local step = math.min(math.abs(needed), remainingDistance)
            state.lockOffsetZ = state.lockOffsetZ + step
            remainingDistance = remainingDistance - step
            if state.lockOffsetZ >= range then
                state.lockDirection = 3
            end
        elseif state.lockDirection == 3 then
            local needed = -range - state.lockOffsetX
            local step = math.min(math.abs(needed), remainingDistance)
            state.lockOffsetX = state.lockOffsetX - step
            remainingDistance = remainingDistance - step
            if state.lockOffsetX <= -range then
                state.lockDirection = 4
            end
        else
            local needed = -range - state.lockOffsetZ
            local step = math.min(math.abs(needed), remainingDistance)
            state.lockOffsetZ = state.lockOffsetZ - step
            remainingDistance = remainingDistance - step
            if state.lockOffsetZ <= -range then
                state.lockDirection = 1
            end
        end
    end

    local origin = state.lockMotionOrigin
    pcall(function()
        root.Position = Vector3.new(
            origin.X + state.lockOffsetX,
            state.lockYValue,
            origin.Z + state.lockOffsetZ
        )
    end)
end

local function resolveWorldPosition(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance.Position
    end

    if instance:IsA("Model") then
        local primaryPart = instance.PrimaryPart
        if primaryPart then
            return primaryPart.Position
        end
    end

    local directPart = instance:FindFirstChildWhichIsA("BasePart")
    if directPart then
        return directPart.Position
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant.Position
        end
    end

    return nil
end

local function getItemAddressKey(instance)
    local okAddress, address = pcall(function()
        return instance.Address
    end)
    if okAddress and address then
        return string.format("0x%X", address)
    end

    local okFullName, fullName = pcall(function()
        return instance:GetFullName()
    end)
    if okFullName and fullName then
        return fullName
    end

    return tostring(instance)
end

local function queueNotification(text)
    if #state.notificationQueue >= config.maxNotificationQueue then
        return
    end
    table.insert(state.notificationQueue, text)
end

local function processNotificationQueue()
    if #state.notificationQueue == 0 then
        return
    end

    if os.clock() - state.lastNotificationAt < config.notificationCooldown then
        return
    end

    local nextText = table.remove(state.notificationQueue, 1)
    state.lastNotificationAt = os.clock()
    ui:Notification(nextText, 4)
    ui:Notification(nextText, 4)
    ui:Notification(nextText, 4)
end

local function moveTowards(current, target, maxStep)
    local deltaX = target.X - current.X
    local deltaY = target.Y - current.Y
    local deltaZ = target.Z - current.Z
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)

    if distance <= maxStep or distance <= 0.0001 then
        return target, distance
    end

    local scale = maxStep / distance
    return Vector3.new(
        current.X + deltaX * scale,
        current.Y + deltaY * scale,
        current.Z + deltaZ * scale
    ), distance
end

local function distanceXZ(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function distance3D(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function setCollectKeyState(shouldHold)
    if shouldHold and not state.collectHoldingKey then
        if keypress then
            pcall(keypress, 0x45) -- E
        end
        state.collectHoldingKey = true
    elseif not shouldHold and state.collectHoldingKey then
        if keyrelease then
            pcall(keyrelease, 0x45) -- E
        end
        state.collectHoldingKey = false
    end
end

local function isOtherPlayerNearItemXZ(itemPosition, radius)
    local okPlayers, playerList = pcall(function()
        return players:GetPlayers()
    end)
    if not okPlayers or not playerList then
        return false
    end

    for _, otherPlayer in ipairs(playerList) do
        if otherPlayer ~= player then
            local character = otherPlayer.Character
            if character then
                local otherRoot = character:FindFirstChild("HumanoidRootPart")
                    or character:FindFirstChild("Torso")
                    or character:FindFirstChild("UpperTorso")
                if otherRoot then
                    local horizontalDistance = distanceXZ(otherRoot.Position, itemPosition)
                    if horizontalDistance <= radius then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function findNearestIdlePointIndex(rootPosition)
    local bestIndex = nil
    local bestDistance = math.huge

    for index, point in ipairs(idleCollectPoints) do
        local distance = distanceXZ(rootPosition, point)
        if distance < bestDistance then
            bestDistance = distance
            bestIndex = index
        end
    end

    return bestIndex
end

local function removeOccupiedQueueEntry(addressKey)
    if state.occupiedItemQueue[addressKey] then
        state.occupiedItemQueue[addressKey] = nil
        state.occupiedQueueSize = math.max(0, state.occupiedQueueSize - 1)
    end
end

local function queueOccupiedItem(addressKey, instance, now)
    local entry = state.occupiedItemQueue[addressKey]
    if entry then
        entry.instance = instance
        entry.lastQueuedAt = now
        if entry.nextCheckAt < now then
            entry.nextCheckAt = now + config.occupiedRecheckInterval
        end
        return
    end

    if state.occupiedQueueSize >= config.maxOccupiedQueue then
        return
    end

    state.occupiedItemQueue[addressKey] = {
        instance = instance,
        nextCheckAt = now + config.occupiedRecheckInterval,
        lastQueuedAt = now,
    }
    state.occupiedQueueSize = state.occupiedQueueSize + 1
end

local function findQueuedCollectTarget(rootPosition, now)
    local bestAddress = nil
    local bestInstance = nil
    local bestPosition = nil
    local bestDistance = math.huge
    local pendingRemoval = {}

    local function markForRemoval(addressKey)
        pendingRemoval[addressKey] = true
    end

    for addressKey, entry in pairs(state.occupiedItemQueue) do
        if not entry then
            markForRemoval(addressKey)
        elseif now - (entry.lastQueuedAt or 0) > config.addressRetentionSeconds then
            markForRemoval(addressKey)
        elseif (entry.nextCheckAt or 0) > now then
            -- wait for next check window
        else
            local instance = entry.instance
            local cooldownUntil = state.collectCooldownByAddress[addressKey] or 0
            if cooldownUntil > now then
                entry.nextCheckAt = cooldownUntil
            elseif not instance or not instance.Parent then
                markForRemoval(addressKey)
            else
                local okPos, worldPosition = pcall(resolveWorldPosition, instance)
                if not okPos or not worldPosition then
                    markForRemoval(addressKey)
                else
                    local blockedByPlayer = state.autoCollectSkipOccupied
                        and isOtherPlayerNearItemXZ(worldPosition, state.collectSkipPlayerRadiusXZ)
                    if blockedByPlayer then
                        entry.nextCheckAt = now + config.occupiedRecheckInterval
                        entry.lastQueuedAt = now
                    else
                        local dx = worldPosition.X - rootPosition.X
                        local dy = worldPosition.Y - rootPosition.Y
                        local dz = worldPosition.Z - rootPosition.Z
                        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if distance < bestDistance then
                            bestDistance = distance
                            bestAddress = addressKey
                            bestInstance = instance
                            bestPosition = worldPosition
                        end
                    end
                end
            end
        end
    end

    if bestAddress then
        markForRemoval(bestAddress)
    end

    for addressKey in pairs(pendingRemoval) do
        removeOccupiedQueueEntry(addressKey)
    end

    return bestInstance, bestPosition
end

local function findNearestCollectTarget(rootPosition)
    local bestInstance = nil
    local bestPosition = nil
    local bestDistance = math.huge
    local now = os.clock()

    local queuedInstance, queuedPosition = findQueuedCollectTarget(rootPosition, now)
    if queuedInstance and queuedPosition then
        return queuedInstance, queuedPosition
    end

    for _, instance in ipairs(state.itemCache) do
        if instance.Parent then
            local addressKey = getItemAddressKey(instance)
            local cooldownUntil = state.collectCooldownByAddress[addressKey] or 0
            if now >= cooldownUntil then
                local okPos, worldPosition = pcall(resolveWorldPosition, instance)
                if okPos and worldPosition then
                    local blockedByPlayer = state.autoCollectSkipOccupied
                        and isOtherPlayerNearItemXZ(worldPosition, state.collectSkipPlayerRadiusXZ)
                    if not blockedByPlayer then
                        if state.occupiedItemQueue[addressKey] then
                            removeOccupiedQueueEntry(addressKey)
                        end

                        local dx = worldPosition.X - rootPosition.X
                        local dy = worldPosition.Y - rootPosition.Y
                        local dz = worldPosition.Z - rootPosition.Z
                        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if distance < bestDistance then
                            bestDistance = distance
                            bestInstance = instance
                            bestPosition = worldPosition
                        end
                    else
                        queueOccupiedItem(addressKey, instance, now)
                    end
                end
            end
        end
    end

    return bestInstance, bestPosition
end

local function runAutoCollect(deltaTime)
    if not state.autoCollect then
        setCollectKeyState(false)
        return
    end

    local root = getRootPart()
    if not root then
        setCollectKeyState(false)
        return
    end

    local now = os.clock()
    if now >= state.collectHoldStartAt and now < state.collectHoldUntil then
        setCollectKeyState(true)
        return
    end

    if state.collectHoldingKey and state.collectHoldUntil > 0 and state.collectHoldUntil <= now then
        setCollectKeyState(false)
        state.collectHoldStartAt = 0
        state.collectHoldUntil = 0
    end

    if state.collectPauseUntil > now then
        return
    end

    if now < state.collectTeleportCooldownUntil then
        return
    end

    local rootPosition = root.Position
    local targetInstance, targetPosition = findNearestCollectTarget(rootPosition)
    if not targetInstance or not targetPosition then
        setCollectKeyState(false)

        if not state.autoCollectUseIdlePoints then
            return
        end

        local idleIndex = findNearestIdlePointIndex(rootPosition)
        if not idleIndex then
            return
        end

        if state.collectIdleAtPoint and state.collectIdlePointIndex == idleIndex then
            return
        end

        local idlePoint = idleCollectPoints[idleIndex]
        local underMapTravelY = state.lockYValue + state.collectUnderMapYOffset
        local travelIdleTarget = state.autoCollectUseUnderMapTravel
            and Vector3.new(idlePoint.X, underMapTravelY, idlePoint.Z)
            or Vector3.new(idlePoint.X, idlePoint.Y + state.collectTeleportHeight, idlePoint.Z)
        local moveStep = math.max(1, state.collectFlySpeed) * (deltaTime or config.fallbackDeltaTime)
        local nextPosition, distanceToIdleTarget = moveTowards(rootPosition, travelIdleTarget, moveStep)
        local directIdleDistance = distance3D(rootPosition, travelIdleTarget)

        if directIdleDistance <= config.collectInstantTeleportDistance then
            pcall(function()
                root.Position = Vector3.new(idlePoint.X, idlePoint.Y + 10, idlePoint.Z)
            end)
            state.collectIdlePointIndex = idleIndex
            state.collectIdleAtPoint = true
            state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
            return
        end

        if distanceToIdleTarget > state.collectArrivalDistance then
            state.collectIdlePointIndex = idleIndex
            state.collectIdleAtPoint = false
            pcall(function()
                root.Position = Vector3.new(nextPosition.X, underMapTravelY, nextPosition.Z)
            end)
            return
        end

        if state.autoCollectUseIdlePoints and (not state.collectIdleAtPoint or state.collectIdlePointIndex ~= idleIndex) then
            pcall(function()
                root.Position = Vector3.new(idlePoint.X, idlePoint.Y + 10, idlePoint.Z)
            end)
            state.collectIdlePointIndex = idleIndex
            state.collectIdleAtPoint = true
            state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
        end
        return
    end

    state.collectIdlePointIndex = nil
    state.collectIdleAtPoint = false

    local underMapTravelY = state.lockYValue + state.collectUnderMapYOffset
    local travelTarget = state.autoCollectUseUnderMapTravel
        and Vector3.new(targetPosition.X, underMapTravelY, targetPosition.Z)
        or Vector3.new(targetPosition.X, targetPosition.Y + state.collectTeleportHeight, targetPosition.Z)
    local moveStep = math.max(1, state.collectFlySpeed) * (deltaTime or config.fallbackDeltaTime)
    local nextPosition, distanceToTarget = moveTowards(rootPosition, travelTarget, moveStep)
    local directTargetDistance = distance3D(rootPosition, travelTarget)

    if directTargetDistance <= config.collectInstantTeleportDistance then
        local pickupPositionFast = Vector3.new(targetPosition.X, targetPosition.Y + state.collectTeleportHeight, targetPosition.Z)
        pcall(function()
            root.Position = pickupPositionFast
        end)

        task.wait(0.5)

        local addressKeyFast = getItemAddressKey(targetInstance)
        state.collectCooldownByAddress[addressKeyFast] = now + config.collectRetryCooldown
        state.collectPauseUntil = now + state.collectPreHoldDelay
        state.collectHoldStartAt = state.collectPauseUntil
        state.collectHoldUntil = state.collectHoldStartAt + state.collectHoldDuration
        state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
        return
    end

    if distanceToTarget > state.collectArrivalDistance then
        pcall(function()
            root.Position = Vector3.new(nextPosition.X, underMapTravelY, nextPosition.Z)
        end)
        return
    end

    local pickupPosition = Vector3.new(targetPosition.X, targetPosition.Y + state.collectTeleportHeight, targetPosition.Z)
    pcall(function()
        root.Position = pickupPosition
    end)

    local addressKey = getItemAddressKey(targetInstance)
    state.collectCooldownByAddress[addressKey] = now + config.collectRetryCooldown
    state.collectPauseUntil = now + state.collectPreHoldDelay
    state.collectHoldStartAt = state.collectPauseUntil
    state.collectHoldUntil = state.collectHoldStartAt + state.collectHoldDuration
    state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
end

local function getOrCreateItemDrawBundle(instance)
    local bundle = itemDrawings[instance]
    if bundle then
        return bundle
    end

    local box = Drawing.new("Square")
    box.Filled = false
    box.Thickness = 2
    box.Visible = false
    box.ZIndex = 2

    local text = Drawing.new("Text")
    text.Center = true
    text.Outline = true
    text.Color = Color3.fromRGB(255, 255, 255)
    text.Font = Drawing.Fonts.SystemBold
    text.Size = 14
    text.Visible = false
    text.ZIndex = 3
    text.Text = instance.Name

    bundle = {
        box = box,
        text = text,
    }
    itemDrawings[instance] = bundle
    return bundle
end

local function hideAllItemDrawings()
    for _, bundle in pairs(itemDrawings) do
        bundle.box.Visible = false
        bundle.text.Visible = false
    end
end

local function removeAllItemDrawings()
    for key, bundle in pairs(itemDrawings) do
        bundle.box:Remove()
        bundle.text:Remove()
        itemDrawings[key] = nil
    end
end

local function refreshItemCache()
    local now = os.clock()
    if now - state.itemCacheLastRefresh < state.itemCacheRefreshInterval then
        return
    end

    state.itemCacheLastRefresh = now
    state.itemCache = {}
    local seenAddressesThisScan = {}

    local okChildren, workspaceChildren = pcall(function()
        return workspace:GetChildren()
    end)
    if not okChildren or not workspaceChildren then
        return
    end

    for _, child in ipairs(workspaceChildren) do
        if child.Name == "Model" then
            local okDescendants, descendants = pcall(function()
                return child:GetDescendants()
            end)
            if okDescendants and descendants then
                for _, obj in ipairs(descendants) do
                    if trackedItemLookup[obj.Name] then
                        local addressKey = getItemAddressKey(obj)
                        if not seenAddressesThisScan[addressKey] then
                            seenAddressesThisScan[addressKey] = true
                            table.insert(state.itemCache, obj)

                            if state.itemScanInitialized and state.spawnNotifications and not state.seenItemAddresses[addressKey] then
                                queueNotification("Item spawned: " .. obj.Name)
                            end

                            state.seenItemAddresses[addressKey] = now

                            if #state.itemCache >= config.maxTrackedItems then
                                break
                            end
                        end
                    end
                end
            end
        end

        if #state.itemCache >= config.maxTrackedItems then
            break
        end
    end

    for addressKey, lastSeenAt in pairs(state.seenItemAddresses) do
        if now - lastSeenAt > config.addressRetentionSeconds then
            state.seenItemAddresses[addressKey] = nil
            state.collectCooldownByAddress[addressKey] = nil
            removeOccupiedQueueEntry(addressKey)
        end
    end

    state.itemScanInitialized = true
end

local function renderItemESP()
    if not state.itemESP then
        hideAllItemDrawings()
        return
    end

    local rainbowColor = Color3.fromHSV((os.clock() * config.rainbowSpeed) % 1, 1, 1)
    local boxColor = state.espRainbowBox and rainbowColor or Color3.fromRGB(255, 255, 255)
    local seenThisFrame = {}
    local renderedCount = 0

    for _, obj in ipairs(state.itemCache) do
        if renderedCount >= state.maxRenderedItems then
            break
        end

        if obj.Parent then
            local okPosition, worldPosition = pcall(resolveWorldPosition, obj)
            if okPosition and worldPosition then
                local okW2S, screenPosition, onScreen = pcall(WorldToScreen, worldPosition)
                if okW2S and onScreen and screenPosition then
                    local bundle = getOrCreateItemDrawBundle(obj)
                    seenThisFrame[obj] = true
                    renderedCount = renderedCount + 1

                    local boxHeight = 28
                    local okTop, topScreen, topOnScreen = pcall(WorldToScreen, worldPosition + Vector3.new(0, 2, 0))
                    local okBottom, bottomScreen, bottomOnScreen = pcall(WorldToScreen, worldPosition + Vector3.new(0, -2, 0))
                    if okTop and okBottom and topOnScreen and bottomOnScreen and topScreen and bottomScreen then
                        boxHeight = math.abs(topScreen.Y - bottomScreen.Y)
                    end

                    boxHeight = math.max(18, math.min(120, boxHeight))
                    local boxWidth = math.max(14, boxHeight * 0.8)

                    bundle.box.Color = boxColor
                    bundle.box.Thickness = state.espBoxThickness
                    bundle.box.Size = Vector2.new(boxWidth, boxHeight)
                    bundle.box.Position = Vector2.new(screenPosition.X - boxWidth * 0.5, screenPosition.Y - boxHeight * 0.5)
                    bundle.box.Visible = state.espShowBox

                    bundle.text.Text = obj.Name
                    bundle.text.Position = Vector2.new(screenPosition.X, screenPosition.Y - boxHeight * 0.5 - 12)
                    bundle.text.Visible = state.espShowText
                end
            end
        end
    end

    for instance, bundle in pairs(itemDrawings) do
        if not seenThisFrame[instance] then
            if instance.Parent then
                bundle.box.Visible = false
                bundle.text.Visible = false
            else
                bundle.box:Remove()
                bundle.text:Remove()
                itemDrawings[instance] = nil
            end
        end
    end
end

local function consumePressed(code)
    local okPressed, isPressed = pcall(function()
        return iskeypressed and iskeypressed(code)
    end)
    if not okPressed then
        isPressed = false
    end

    local wasPressed = keyDownState[code] == true
    keyDownState[code] = isPressed and true or false
    return isPressed and not wasPressed
end

local tabMain = ui:Tab("Main")
local movementSection = tabMain:Section("Movement")
local espSection = tabMain:Section("ESP")
local autoCollectSection = tabMain:Section("Auto Collect")
local _, settingsSection = ui:CreateSettingsTab("Settings")

ui:SetMenuSize(Vector2.new(760, 840))
ui:CenterMenu()
ui:SetMenuTitle("Bizzare Lineage")
ui:SetWatermarkEnabled(false)

movementSection:Slider("Lock Y", state.lockYValue, 1, config.lockYMin, config.lockYMax, "", function(newValue)
    state.lockYValue = newValue
    if state.yLock then
        setLockYPosition(true)
    end
end)

local yLockToggle = movementSection:Toggle("Lock Y (VOID DIO)", false, function(enabled)
    state.yLock = enabled

    if state.autoCollect then
        -- Auto collect owns movement/teleports while active.
        return
    end

    if enabled then
        local root = getRootPart()
        if root then
            local pos = root.Position
            state.cachedReturnPosition = Vector3.new(pos.X, pos.Y, pos.Z)
            state.lockMotionOrigin = Vector3.new(pos.X, state.lockYValue, pos.Z)
        else
            state.cachedReturnPosition = nil
            state.lockMotionOrigin = nil
        end
        state.lockOffsetX = 0
        state.lockOffsetZ = 0
        state.lockDirection = 1

        setLockYPosition(true)
    else
        local root = getRootPart()
        local cached = state.cachedReturnPosition
        if root and cached then
            pcall(function()
                root.Position = cached + Vector3.new(0, 10, 0)
            end)
        end

        state.cachedReturnPosition = nil
        state.lockMotionOrigin = nil
        state.lockOffsetX = 0
        state.lockOffsetZ = 0
        state.lockDirection = 1
    end
end)

yLockToggle:AddKeybind("lbracket", "Toggle", true, function(newKeyId)
    if type(newKeyId) == "number" then
        keybinds.yLock = newKeyId
        ui:Notification("Y lock bind updated", 3)
    end
end)

local itemESPToggle = espSection:Toggle("Item ESP", false, function(enabled)
    state.itemESP = enabled
    if enabled then
        state.itemScanInitialized = false
        state.itemCacheLastRefresh = 0
        state.notificationQueue = {}
    else
        hideAllItemDrawings()
    end
end)

itemESPToggle:AddKeybind("rbracket", "Toggle", true, function(newKeyId)
    if type(newKeyId) == "number" then
        keybinds.itemESP = newKeyId
        ui:Notification("Item ESP bind updated", 3)
    end
end)

espSection:Toggle("Spawn Notify", state.spawnNotifications, function(enabled)
    state.spawnNotifications = enabled
end)

espSection:Toggle("Show Box", state.espShowBox, function(enabled)
    state.espShowBox = enabled
end)

espSection:Toggle("Show Text", state.espShowText, function(enabled)
    state.espShowText = enabled
end)

espSection:Toggle("Rainbow Box", state.espRainbowBox, function(enabled)
    state.espRainbowBox = enabled
end)

espSection:Slider("Box Thick", state.espBoxThickness, 1, 1, 4, "", function(newValue)
    state.espBoxThickness = newValue
end)

espSection:Slider("Scan Rate", state.itemCacheRefreshInterval, 0.05, 0.2, 2.0, "s", function(newValue)
    state.itemCacheRefreshInterval = newValue
end)

espSection:Slider("Max ESP", state.maxRenderedItems, 10, 20, config.maxTrackedItems, "", function(newValue)
    state.maxRenderedItems = newValue
end)

autoCollectSection:Slider("Fly Speed", state.collectFlySpeed, 5, config.collectFlySpeedMin, config.collectFlySpeedMax, "", function(newValue)
    state.collectFlySpeed = newValue
end)

autoCollectSection:Slider("Arrival Dist", state.collectArrivalDistance, 1, 10, 80, "", function(newValue)
    state.collectArrivalDistance = newValue
end)

autoCollectSection:Slider("Teleport +Y", state.collectTeleportHeight, 1, 5, 25, "", function(newValue)
    state.collectTeleportHeight = newValue
end)

autoCollectSection:Slider("UnderMap +Y", state.collectUnderMapYOffset, 5, 20, 260, "", function(newValue)
    state.collectUnderMapYOffset = newValue
end)

autoCollectSection:Slider("Hold Delay", state.collectPreHoldDelay, 0.05, 0, 1.0, "s", function(newValue)
    state.collectPreHoldDelay = newValue
end)

autoCollectSection:Slider("Hold Time", state.collectHoldDuration, 0.05, 0.4, 2.5, "s", function(newValue)
    state.collectHoldDuration = newValue
end)

autoCollectSection:Toggle("Idle Wait Points", state.autoCollectUseIdlePoints, function(enabled)
    state.autoCollectUseIdlePoints = enabled
end)

autoCollectSection:Toggle("Travel UnderMap", state.autoCollectUseUnderMapTravel, function(enabled)
    state.autoCollectUseUnderMapTravel = enabled
end)

autoCollectSection:Toggle("Skip Occupied", state.autoCollectSkipOccupied, function(enabled)
    state.autoCollectSkipOccupied = enabled
end)

autoCollectSection:Slider("Skip Radius", state.collectSkipPlayerRadiusXZ, 1, 1, 12, "", function(newValue)
    state.collectSkipPlayerRadiusXZ = newValue
end)

autoCollectSection:Toggle("Auto Collect", false, function(enabled)
    state.autoCollect = enabled
    if enabled then
        state.lockYWasEnabledBeforeCollect = state.yLock
        if state.yLock then
            yLockToggle:Set(false)
        end
    else
        state.collectPauseUntil = 0
        state.collectHoldStartAt = 0
        state.collectHoldUntil = 0
        state.collectTeleportCooldownUntil = 0
        state.collectIdlePointIndex = nil
        state.collectIdleAtPoint = false
        state.occupiedItemQueue = {}
        state.occupiedQueueSize = 0
        setCollectKeyState(false)

        if state.lockYWasEnabledBeforeCollect then
            yLockToggle:Set(true)
        end
        state.lockYWasEnabledBeforeCollect = false
    end
end)

settingsSection:Button("Unload", function()
    state.shouldUnload = true
end)

_G.__bizzareLineageUnload = function()
    state.shouldUnload = true
end

ui:Notification("Lock Y slider range: -450 to -410", 4)
ui:Notification("Default binds: [ = Lock Y, ] = Item ESP", 6)

local renderBindName = "bizzare_lineage_render"
local fallbackLoopAlive = false

local function updateFrame(deltaTime)
    if consumePressed(keybinds.yLock) then
        yLockToggle:Set(not state.yLock)
    end
    if consumePressed(keybinds.itemESP) then
        itemESPToggle:Set(not state.itemESP)
    end

    if state.yLock and not state.autoCollect then
        stepSquareLockMovement(deltaTime)
    end

    if state.itemESP or state.autoCollect then
        refreshItemCache()
    end
    runAutoCollect(deltaTime)
    renderItemESP()
    processNotificationQueue()
end

local function safeUpdateFrame(deltaTime)
    local now = os.clock()
    if now < state.runtimeCooldownUntil then
        return
    end

    local ok = pcall(updateFrame, deltaTime)
    if ok then
        state.frameErrorCount = math.max(0, state.frameErrorCount - 1)
        return
    end

    state.frameErrorCount = state.frameErrorCount + 1
    if state.frameErrorCount >= 20 then
        state.autoCollect = false
        state.itemESP = false
        setCollectKeyState(false)
        hideAllItemDrawings()
        state.runtimeCooldownUntil = now + 1.5
        state.frameErrorCount = 0
    end
end

if runServiceVM and runServiceVM.BindToRenderStep and runServiceVM.UnbindFromRenderStep then
    runServiceVM:BindToRenderStep(renderBindName, 100, function(deltaTime)
        safeUpdateFrame(deltaTime)
    end)
else
    fallbackLoopAlive = true
    task.spawn(function()
        while fallbackLoopAlive and not state.shouldUnload do
            safeUpdateFrame(config.fallbackDeltaTime)
            task.wait()
        end
    end)
end

while not state.shouldUnload do
    ui:Step()
end

fallbackLoopAlive = false

if runServiceVM and runServiceVM.UnbindFromRenderStep then
    runServiceVM:UnbindFromRenderStep(renderBindName)
end

removeAllItemDrawings()
setCollectKeyState(false)
ui:Unload()
