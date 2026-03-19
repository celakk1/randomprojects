local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local player = players.LocalPlayer
local uiTabName = "Bizzare Lineage"

-- config duh
local conf = {
	keepYDefaultLevel = -410,
	keepYMinLevel = -450,
	keepYMaxLevel = -410,
	keepYStep = 1,

	collectFlySpeedDefault = 1000,
	collectFlySpeedMin = 60,
	collectFlySpeedMax = 1200,
	collectFlySpeedStep = 5,

	collectArrivalDistanceDefault = 30,
	collectArrivalDistanceMin = 10,
	collectArrivalDistanceMax = 80,
	collectArrivalDistanceStep = 1,

	collectUnderMapYOffsetDefault = 260,
	collectUnderMapYOffsetMin = 20,
	collectUnderMapYOffsetMax = 260,
	collectUnderMapYOffsetStep = 5,
}

-- runtime duh 
local runtime = {
	keepYMoveRange = 100,
	keepYMoveSpeed = 520,

	itemCacheRefreshInterval = 1, 
	fallbackDeltaTime = 0.016,
	espRainbowSpeed = 0.35,

	notificationCooldown = 0.8,
	maxNotificationQueue = 10,

	collectTeleportHeight = 10,
	collectTeleportCooldown = 0.5,
	collectRetryCooldown = 3.0,
	collectInstantTeleportDistance = 300,

	maxTrackedItems = 30,
	maxRenderedItems = 30,
	addressRetentionSeconds = 240,
	occupiedRecheckInterval = 1.0,
	maxOccupiedQueue = 200,
}

-- data xd lol
local idleCollectPoints = {
	Vector3.new(643, 945, -1396),
	Vector3.new(1352, 997, -1367),
	Vector3.new(2754, 982, 193),
	Vector3.new(1458, 1155, 1389),
	Vector3.new(244, 1065, 471),
}

local trackedItemLookup = {
	["Stone Mask"] = true,
	["Imperfect Aja"] = true,
	["Red Stone of Aja"] = true,
	["Lucky Arrow"] = true,
	["Rokakaka"] = true,
	["Stat Point Essence"] = true,
	["Stand Arrow"] = true,
	["DIO's Diary"] = true,
}

-- states duh
local state = {
	keepY = false,
	itemEsp = false,
	shouldUnload = false,

	cachedReturnPosition = nil,
	keepYLevel = conf.keepYDefaultLevel,
	keepYMotionOrigin = nil,
	keepYOffsetX = 0,
	keepYOffsetZ = 0,
	keepYDirection = 1,

	itemCache = {},
	itemCacheLastRefresh = 0,
	seenItemAddresses = {},
	itemScanInitialized = false,

	espShowBox = true,
	espRainbowBox = true,

	notificationQueue = {},
	lastNotificationAt = 0,

	autoCollect = false,
	collectFlySpeed = conf.collectFlySpeedDefault,
	collectArrivalDistance = conf.collectArrivalDistanceDefault,
	collectUnderMapYOffset = conf.collectUnderMapYOffsetDefault,

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

	keepYWasEnabledBeforeCollect = false,
	frameErrorCount = 0,
	runtimeCooldownUntil = 0,
}

-- i have no fucking clue what this is for probably useless (NVM I DONT THINK THIS IS USELESS NOT LIKE IGAF)
if _G.__bizzareLineageUnload then
	pcall(_G.__bizzareLineageUnload)
	task.wait(0.05)
end

local itemDrawings = {}
local itemWorldPartCache = {}

local uiIds = {
	keepY = "bl_keepY",
	keepYLevel = "bl_keepYLevel",
	itemEsp = "bl_itemEsp",
	espShowBox = "bl_espShowBox",
	espRainbowBox = "bl_espRainbowBox",
	autoCollect = "bl_autoCollect",
	collectFlySpeed = "bl_collectFlySpeed",
	collectArrivalDistance = "bl_collectArrivalDistance",
	collectUnderMapYOffset = "bl_collectUnderMapYOffset",
	autoCollectSkipOccupied = "bl_autoCollectSkipOccupied"
}

-- self explanatory
local function getRootPart()
	local character = player and player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
end

-- i doubt this is any useful
local function getInstanceWorldPosition(instance)
	if not instance then
		return nil
	end

	local cachedPart = itemWorldPartCache[instance]
	if cachedPart and cachedPart.Parent then
		return cachedPart.Position
	end

	if instance:IsA("BasePart") then
		itemWorldPartCache[instance] = instance
		return instance.Position
	end

	if instance:IsA("Model") and instance.PrimaryPart then
		local primaryPart = instance.PrimaryPart
		itemWorldPartCache[instance] = primaryPart
		return primaryPart.Position
	end

	local directPart = instance:FindFirstChildWhichIsA("BasePart")
	if directPart then
		itemWorldPartCache[instance] = directPart
		return directPart.Position
	end

	for _, d in ipairs(instance:GetDescendants()) do
		if d:IsA("BasePart") then
			itemWorldPartCache[instance] = d
			return d.Position
		end
	end

	return nil
end

-- self explanatory
local function getItemAddress(instance)
	local okA, addr = pcall(function() return instance.Address end)
	if okA and addr then
		return string.format("0x%X", addr)
	end

	local okF, full = pcall(function() return instance:GetFullName() end)
	if okF and full then
		return full
	end

	return tostring(instance)
end

-- self explanatory
local function moveTowards(current, target, maxStep)
	local dx = target.X - current.X
	local dy = target.Y - current.Y
	local dz = target.Z - current.Z
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

	if dist <= maxStep or dist <= 0.0001 then
		return target, dist
	end

	local s = maxStep / dist

	return Vector3.new(current.X + dx * s, current.Y + dy * s, current.Z + dz * s), dist
end

-- self explanatory
local function getDistance(a, b, ignoreY)
	local dx = a.X - b.X
	local dz = a.Z - b.Z

	if ignoreY then
		return math.sqrt(dx * dx + dz * dz)
	end

	local dy = a.Y - b.Y
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- makes you NOT FUCKING DIE to void
local function applyKeepYPosition(forceExact)
	local root = getRootPart()
	if not root then return end

	local pos = root.Position

	if forceExact or pos.Y < state.keepYLevel then
		pcall(function()
			root.Position = Vector3.new(pos.X, state.keepYLevel, pos.Z)
		end)

		pcall(function()
			local vel = root.AssemblyLinearVelocity

			if vel then
				root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
			end
		end)
	end
end

-- makes the voiding module move in square to dodge attacks
local function stepKeepYSquareMovement(deltaTime)
	local root = getRootPart()
	if not root then return end

	if not state.keepYMotionOrigin then
		local pos = root.Position

		state.keepYMotionOrigin = Vector3.new(pos.X, state.keepYLevel, pos.Z)
		state.keepYOffsetX = 0
		state.keepYOffsetZ = 0
		state.keepYDirection = 1
	end

	local remainingDistance = (deltaTime or runtime.fallbackDeltaTime) * runtime.keepYMoveSpeed

	local range = runtime.keepYMoveRange

	while remainingDistance > 0 do
		if state.keepYDirection == 1 then
			local step = math.min(math.abs(range - state.keepYOffsetX), remainingDistance)

			state.keepYOffsetX = state.keepYOffsetX + step
			remainingDistance = remainingDistance - step

			if state.keepYOffsetX >= range then
				state.keepYDirection = 2
			end
		elseif state.keepYDirection == 2 then
			local step = math.min(math.abs(range - state.keepYOffsetZ), remainingDistance)

			state.keepYOffsetZ = state.keepYOffsetZ + step
			remainingDistance = remainingDistance - step

			if state.keepYOffsetZ >= range then
				state.keepYDirection = 3
			end
		elseif state.keepYDirection == 3 then
			local step = math.min(math.abs(-range - state.keepYOffsetX), remainingDistance)

			state.keepYOffsetX = state.keepYOffsetX - step
			remainingDistance = remainingDistance - step

			if state.keepYOffsetX <= -range then
				state.keepYDirection = 4
			end
		else
			local step = math.min(math.abs(-range - state.keepYOffsetZ), remainingDistance)

			state.keepYOffsetZ = state.keepYOffsetZ - step
			remainingDistance = remainingDistance - step

			if state.keepYOffsetZ <= -range then
				state.keepYDirection = 1
			end
		end
	end

	local origin = state.keepYMotionOrigin
	local targetX = origin.X + state.keepYOffsetX
	local targetZ = origin.Z + state.keepYOffsetZ

	pcall(function()
		root.Position = Vector3.new(targetX, state.keepYLevel, targetZ)

		local vel = root.AssemblyLinearVelocity

		if vel then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
	end)
end

-- i have no fucking clue what this does
local function setCollectKeyState(shouldHold)
	if shouldHold and not state.collectHoldingKey then
		if keypress then
			pcall(keypress, 0x45)
		end

		state.collectHoldingKey = true
	elseif not shouldHold and state.collectHoldingKey then
		if keyrelease then
			pcall(keyrelease, 0x45)
		end

		state.collectHoldingKey = false
	end
end

-- checks if any player is close to the item 
local function isOtherPlayerNearItem(itemPos, radius)
	local ok, list = pcall(function() return players:GetPlayers() end)
	if not ok or not list then
		return false
	end

	for _, p in ipairs(list) do
		if p ~= player and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
				or p.Character:FindFirstChild("Torso")
				or p.Character:FindFirstChild("UpperTorso")

			if r and getDistance(r.Position, itemPos, true) <= radius then
				return true
			end
		end
	end

	return false
end

-- removes the occupied item from the queue if its collected by script or by somebody
local function removeOccupiedQueueEntry(key)
	if state.occupiedItemQueue[key] then
		state.occupiedItemQueue[key] = nil
		state.occupiedQueueSize = math.max(0, state.occupiedQueueSize - 1)
	end
end

-- queues an item that is "occupied" by other player (if the player doesnt collect that item, the script will collect it)
local function queueOccupiedItem(key, instance, now)
	local entry = state.occupiedItemQueue[key]

	if entry then
		entry.instance = instance
		entry.lastQueuedAt = now

		if entry.nextCheckAt < now then
			entry.nextCheckAt = now + runtime.occupiedRecheckInterval
		end

		return
	end

	if state.occupiedQueueSize >= runtime.maxOccupiedQueue then
		return
	end

	state.occupiedItemQueue[key] = {
		instance = instance,
		nextCheckAt = now + runtime.occupiedRecheckInterval,
		lastQueuedAt = now
	}

	state.occupiedQueueSize = state.occupiedQueueSize + 1
end

-- this is for auto collect, checks whats closest and flies to it
local function findBestCollectTarget(rootPos)
	local now = os.clock()
	local bestKey, bestInst, bestPos, bestDist = nil, nil, nil, math.huge
	local toRemove = {}

	for key, entry in pairs(state.occupiedItemQueue) do
		if not entry or now - (entry.lastQueuedAt or 0) > runtime.addressRetentionSeconds then
			toRemove[key] = true
		elseif (entry.nextCheckAt or 0) <= now then
			local cooldown = state.collectCooldownByAddress[key] or 0
			if cooldown > now then
				entry.nextCheckAt = cooldown
			elseif not entry.instance or not entry.instance.Parent then
				toRemove[key] = true
			else
				local ok, wpos = pcall(getInstanceWorldPosition, entry.instance)
				if not ok or not wpos then
					toRemove[key] = true
				elseif state.autoCollectSkipOccupied and isOtherPlayerNearItem(wpos, 5) then
					entry.nextCheckAt = now + runtime.occupiedRecheckInterval
					entry.lastQueuedAt = now
				else
					local dx = wpos.X - rootPos.X
					local dy = wpos.Y - rootPos.Y
					local dz = wpos.Z - rootPos.Z
					local d = math.sqrt(dx * dx + dy * dy + dz * dz)

					if d < bestDist then
						bestDist = d
						bestKey = key
						bestInst = entry.instance
						bestPos = wpos
					end
				end
			end
		end
	end

	if bestKey then
		toRemove[bestKey] = true
	end

	for key in pairs(toRemove) do
		removeOccupiedQueueEntry(key)
	end

	if bestInst and bestPos then
		return bestInst, bestPos
	end

	bestDist = math.huge

	for _, instance in ipairs(state.itemCache) do
		if instance.Parent then
			local key = getItemAddress(instance)
			local cooldown = state.collectCooldownByAddress[key] or 0

			if now >= cooldown then
				local ok, wpos = pcall(getInstanceWorldPosition, instance)

				if ok and wpos then
					if state.autoCollectSkipOccupied and isOtherPlayerNearItem(wpos, 5) then
						queueOccupiedItem(key, instance, now)
					else
						if state.occupiedItemQueue[key] then
							removeOccupiedQueueEntry(key)
						end

						local dx = wpos.X - rootPos.X
						local dy = wpos.Y - rootPos.Y
						local dz = wpos.Z - rootPos.Z
						local d = math.sqrt(dx * dx + dy * dy + dz * dz)

						if d < bestDist then
							bestDist = d
							bestInst = instance
							bestPos = wpos
						end
					end
				end
			end
		end
	end

	return bestInst, bestPos
end

-- auto collect
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

	local function teleportRoot(pos)
		pcall(function()
			root.Position = pos
			local vel = root.AssemblyLinearVelocity

			if vel then
				root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end
		end)
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

	local rootPos = root.Position
	local targetInst, targetPos = findBestCollectTarget(rootPos)

	if not targetInst or not targetPos then
		setCollectKeyState(false)

		if not state.autoCollectUseIdlePoints then
			return
		end

		local bestIdx, bestIdleDist = nil, math.huge

		for i, pt in ipairs(idleCollectPoints) do
			local d = getDistance(rootPos, pt, true)

			if d < bestIdleDist then
				bestIdleDist = d
				bestIdx = i
			end
		end

		if not bestIdx then
			return
		end

		if state.collectIdleAtPoint and state.collectIdlePointIndex == bestIdx then
			return
		end

		local idlePt = idleCollectPoints[bestIdx]
		local underY = state.keepYLevel + state.collectUnderMapYOffset
		local idleTarget = state.autoCollectUseUnderMapTravel
			and Vector3.new(idlePt.X, underY, idlePt.Z)
			or Vector3.new(idlePt.X, idlePt.Y + runtime.collectTeleportHeight, idlePt.Z)

		local step = math.max(1, state.collectFlySpeed) * (deltaTime or runtime.fallbackDeltaTime)
		local nextPos, idleDist = moveTowards(rootPos, idleTarget, step)
		local directIdleDist = getDistance(rootPos, idleTarget)

		if directIdleDist <= runtime.collectInstantTeleportDistance then
			teleportRoot(Vector3.new(idlePt.X, idlePt.Y + 10, idlePt.Z))
			state.collectIdlePointIndex = bestIdx
			state.collectIdleAtPoint = true
			state.collectTeleportCooldownUntil = now + runtime.collectTeleportCooldown
			return
		end

		if idleDist > state.collectArrivalDistance then
			state.collectIdlePointIndex = bestIdx
			state.collectIdleAtPoint = false
			teleportRoot(Vector3.new(nextPos.X, underY, nextPos.Z))
			return
		end

		if not state.collectIdleAtPoint or state.collectIdlePointIndex ~= bestIdx then
			teleportRoot(Vector3.new(idlePt.X, idlePt.Y + 10, idlePt.Z))
			state.collectIdlePointIndex = bestIdx
			state.collectIdleAtPoint = true
			state.collectTeleportCooldownUntil = now + runtime.collectTeleportCooldown
		end

		return
	end

	state.collectIdlePointIndex = nil
	state.collectIdleAtPoint = false

	local underY = state.keepYLevel + state.collectUnderMapYOffset
	local travelTarget = state.autoCollectUseUnderMapTravel
		and Vector3.new(targetPos.X, underY, targetPos.Z)
		or Vector3.new(targetPos.X, targetPos.Y + runtime.collectTeleportHeight, targetPos.Z)

	local step = math.max(1, state.collectFlySpeed) * (deltaTime or runtime.fallbackDeltaTime)
	local nextPos, targetDist = moveTowards(rootPos, travelTarget, step)
	local directDist = getDistance(rootPos, travelTarget)

	if directDist <= runtime.collectInstantTeleportDistance then
		teleportRoot(Vector3.new(targetPos.X, targetPos.Y + runtime.collectTeleportHeight, targetPos.Z))
		task.wait(0.5)
		local key = getItemAddress(targetInst)
		state.collectCooldownByAddress[key] = now + runtime.collectRetryCooldown
		state.collectPauseUntil = now + 0.3
		state.collectHoldStartAt = state.collectPauseUntil
		state.collectHoldUntil = state.collectHoldStartAt + 1.0
		state.collectTeleportCooldownUntil = now + runtime.collectTeleportCooldown
		return
	end

	if targetDist > state.collectArrivalDistance then
		teleportRoot(Vector3.new(nextPos.X, underY, nextPos.Z))
		return
	end

	teleportRoot(Vector3.new(targetPos.X, targetPos.Y + runtime.collectTeleportHeight, targetPos.Z))
	local key = getItemAddress(targetInst)
	state.collectCooldownByAddress[key] = now + runtime.collectRetryCooldown
	state.collectPauseUntil = now + 0.3
	state.collectHoldStartAt = state.collectPauseUntil
	state.collectHoldUntil = state.collectHoldStartAt + 1.0
	state.collectTeleportCooldownUntil = now + runtime.collectTeleportCooldown
end

-- create esp and cache
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

	bundle = { box = box, text = text }
	itemDrawings[instance] = bundle

	return bundle
end

-- feels useless imo probably needed
local function hideAllItemDrawings()
	for _, bundle in pairs(itemDrawings) do
		bundle.box.Visible = false
		bundle.text.Visible = false
	end
end

-- feels useless imo probably needed
local function removeAllItemDrawings()
	for key, bundle in pairs(itemDrawings) do
		bundle.box:Remove()
		bundle.text:Remove()
		itemDrawings[key] = nil
	end

	for instance in pairs(itemWorldPartCache) do
		itemWorldPartCache[instance] = nil
	end
end

-- self explanatory
local function refreshItemCache()
	local now = os.clock()
	if now - state.itemCacheLastRefresh < runtime.itemCacheRefreshInterval then
		return
	end

	state.itemCacheLastRefresh = now
	state.itemCache = {}

	local seen = {}
	local ok, children = pcall(function() return workspace:GetChildren() end)
	if not ok or not children then
		return
	end

	for _, child in ipairs(children) do
		if child.Name == "Model" then
			local okD, descs = pcall(function() return child:GetDescendants() end)
			if okD and descs then
				for _, obj in ipairs(descs) do
					if trackedItemLookup[obj.Name] then
						local key = getItemAddress(obj)
						if not seen[key] then
							seen[key] = true
							table.insert(state.itemCache, obj)
							if state.itemScanInitialized and not state.seenItemAddresses[key] then
								if #state.notificationQueue < runtime.maxNotificationQueue then
									table.insert(state.notificationQueue, "Item spawned: " .. obj.Name)
								end
							end
							state.seenItemAddresses[key] = now
							if #state.itemCache >= runtime.maxTrackedItems then
								break
							end
						end
					end
				end
			end
		end
		if #state.itemCache >= runtime.maxTrackedItems then
			break
		end
	end

	for key, lastSeen in pairs(state.seenItemAddresses) do
		if now - lastSeen > runtime.addressRetentionSeconds then
			state.seenItemAddresses[key] = nil
			state.collectCooldownByAddress[key] = nil
			removeOccupiedQueueEntry(key)
		end
	end

	for instance, part in pairs(itemWorldPartCache) do
		if (not instance.Parent) or (part and not part.Parent) then
			itemWorldPartCache[instance] = nil
		end
	end

	state.itemScanInitialized = true
end

-- self explanatory
local function renderItemEsp()
	if not state.itemEsp then
		hideAllItemDrawings()
		return
	end

	local boxColor = state.espRainbowBox
		and Color3.fromHSV((os.clock() * runtime.espRainbowSpeed) % 1, 1, 1)
		or Color3.fromRGB(255, 255, 255)

	local cam = workspace.CurrentCamera
	local camPos = cam and cam.Position or nil

	local seenThisFrame = {}
	local renderedCount = 0

	for _, obj in ipairs(state.itemCache) do
		if renderedCount >= runtime.maxRenderedItems then
			break
		end

		if obj.Parent then
			local wpos = getInstanceWorldPosition(obj)
			if wpos then
				local spos, onScreen = WorldToScreen(wpos)
				if onScreen and spos then
					local bundle = getOrCreateItemDrawBundle(obj)
					seenThisFrame[obj] = true
					renderedCount = renderedCount + 1
					local dist = camPos and getDistance(camPos, wpos) or 80
					local h = math.max(12, math.min(80, 1200 / math.max(dist, 1)))
					local w = h * 0.75
					bundle.box.Color = boxColor
					bundle.box.Thickness = 2
					bundle.box.Size = Vector2.new(w, h)
					bundle.box.Position = Vector2.new(spos.X - w * 0.5, spos.Y - h * 0.5)
					bundle.box.Visible = state.espShowBox
					bundle.text.Text = obj.Name
					bundle.text.Position = Vector2.new(spos.X, spos.Y - h * 0.5 - 12)
					bundle.text.Visible = true
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

local function pushNotification(text, duration)
	local ok = pcall(function()
		notify(text, uiTabName, duration or 4)
	end)

	if not ok then
		warn(text)
	end
end

local function setKeepYEnabled(enabled)
	if state.keepY == enabled then
		return
	end

	state.keepY = enabled

	if state.autoCollect then
		return
	end

	if enabled then
		local root = getRootPart()

		if root then
			local pos = root.Position
			state.cachedReturnPosition = Vector3.new(pos.X, pos.Y, pos.Z)
			state.keepYMotionOrigin = Vector3.new(pos.X, state.keepYLevel, pos.Z)
		else
			state.cachedReturnPosition = nil
			state.keepYMotionOrigin = nil
		end

		state.keepYOffsetX = 0
		state.keepYOffsetZ = 0
		state.keepYDirection = 1

		applyKeepYPosition(true)
	else
		local root = getRootPart()
		local cached = state.cachedReturnPosition

		if root and cached then
			pcall(function()
				root.Position = cached + Vector3.new(0, 10, 0)
			end)
		end

		state.cachedReturnPosition = nil
		state.keepYMotionOrigin = nil
		state.keepYOffsetX = 0
		state.keepYOffsetZ = 0
		state.keepYDirection = 1
	end
end

local function setItemEspEnabled(enabled)
	if state.itemEsp == enabled then
		return
	end

	state.itemEsp = enabled

	if enabled then
		state.itemScanInitialized = false
		state.itemCacheLastRefresh = 0
		state.notificationQueue = {}
	else
		hideAllItemDrawings()
	end
end

local function setAutoCollectEnabled(enabled)
	if state.autoCollect == enabled then
		return
	end

	state.autoCollect = enabled

	if enabled then
		state.keepYWasEnabledBeforeCollect = state.keepY

		if state.keepY then
			UI.SetValue(uiIds.keepY, false)
			setKeepYEnabled(false)
		end

		return
	end

	state.collectPauseUntil = 0
	state.collectHoldStartAt = 0
	state.collectHoldUntil = 0
	state.collectTeleportCooldownUntil = 0
	state.collectIdlePointIndex = nil
	state.collectIdleAtPoint = false
	state.occupiedItemQueue = {}
	state.occupiedQueueSize = 0

	setCollectKeyState(false)

	if state.keepYWasEnabledBeforeCollect then
		UI.SetValue(uiIds.keepY, true)
		setKeepYEnabled(true)
	end

	state.keepYWasEnabledBeforeCollect = false
end

local function createUi()
	pcall(function()
		UI.RemoveTab(uiTabName)
	end)

	UI.AddTab(uiTabName, function(tab)
		local movementSection = tab:Section("Movement", "Left")
		movementSection:Toggle(uiIds.keepY, "Keep Y (use this to void dio)", state.keepY, function(enabled)
			setKeepYEnabled(enabled)
		end)
		movementSection:SliderInt(uiIds.keepYLevel, "Y level", conf.keepYMinLevel, conf.keepYMaxLevel, state.keepYLevel, function(value)
			state.keepYLevel = value

			if state.keepY then
				applyKeepYPosition(true)
			end
		end)

		local espSection = tab:Section("ESP", "Left")
		espSection:Toggle(uiIds.itemEsp, "Item ESP", state.itemEsp, function(enabled)
			setItemEspEnabled(enabled)
		end)
		espSection:Toggle(uiIds.espShowBox, "Show Box", state.espShowBox, function(value)
			state.espShowBox = value
		end)
		espSection:Toggle(uiIds.espRainbowBox, "Rainbow Box", state.espRainbowBox, function(value)
			state.espRainbowBox = value
		end)

		local autoCollectSection = tab:Section("Auto Collect", "Right")
		autoCollectSection:Toggle(uiIds.autoCollect, "Auto Collect", state.autoCollect, function(enabled)
			setAutoCollectEnabled(enabled)
		end)
		autoCollectSection:SliderInt(uiIds.collectFlySpeed, "Fly Speed", conf.collectFlySpeedMin, conf.collectFlySpeedMax, state.collectFlySpeed, function(value)
			state.collectFlySpeed = value
		end)
		autoCollectSection:SliderInt(uiIds.collectArrivalDistance, "Arrival Dist", conf.collectArrivalDistanceMin, conf.collectArrivalDistanceMax, state.collectArrivalDistance, function(value)
			state.collectArrivalDistance = value
		end)
		autoCollectSection:SliderInt(uiIds.collectUnderMapYOffset, "UnderMap +Y", conf.collectUnderMapYOffsetMin, conf.collectUnderMapYOffsetMax, state.collectUnderMapYOffset, function(value)
			state.collectUnderMapYOffset = value
		end)
		autoCollectSection:Toggle(uiIds.autoCollectSkipOccupied, "Skip Occupied", state.autoCollectSkipOccupied, function(value)
			state.autoCollectSkipOccupied = value
		end)

		local settingsSection = tab:Section("Settings", "Right")
		settingsSection:Button("Unload", function()
			state.shouldUnload = true
		end)

		local infoSection = tab:Section("Important", "Right")
		infoSection:Text("Please do not DM likety for script help.")
		infoSection:Text("For help regarding this script:")
		infoSection:Text("DM BigJose42.")
	end)

	_G.__bizzareLineageUnload = function() state.shouldUnload = true end

	pushNotification("Please do not DM likety for help with the script.", 6)
	pushNotification("For help with the script, DM BigJose42.", 6)
end

createUi() -- creates ui

-- self explenatory
local lastFrameTime = os.clock()

local function updateFrame()
	local now = os.clock()
	local deltaTime = math.min(now - lastFrameTime, 0.1)
	lastFrameTime = now

	if state.keepY and not state.autoCollect then
		stepKeepYSquareMovement(deltaTime)
	end

	if state.itemEsp or state.autoCollect then
		refreshItemCache()
	end

	if state.autoCollect then
		runAutoCollect(deltaTime)
	end

	if state.itemEsp then
		renderItemEsp()
	end

	if #state.notificationQueue > 0 and os.clock() - state.lastNotificationAt >= runtime.notificationCooldown then
		local text = table.remove(state.notificationQueue, 1)
		state.lastNotificationAt = os.clock()
		pushNotification(text, 4)
	end
end

-- i lowk dont know how to comment this (ai made this)
task.spawn(function()
	while not state.shouldUnload do
		local now = os.clock()
		if now >= state.runtimeCooldownUntil then
			local ok = pcall(updateFrame)
			if ok then
				state.frameErrorCount = math.max(0, state.frameErrorCount - 1)
			else
				state.frameErrorCount = state.frameErrorCount + 1
				if state.frameErrorCount >= 20 then
					state.autoCollect = false
					state.itemEsp = false
					state.keepY = false

					pcall(function()
						UI.SetValue(uiIds.autoCollect, false)
						UI.SetValue(uiIds.itemEsp, false)
						UI.SetValue(uiIds.keepY, false)
					end)

					setCollectKeyState(false)
					hideAllItemDrawings()

					state.runtimeCooldownUntil = now + 1.5
					state.frameErrorCount = 0
				end
			end
		end
		task.wait()
	end
end)

while not state.shouldUnload do
	task.wait() -- removing this will FUCK OVER matcha making it crash 99% of the times
end

removeAllItemDrawings()
setCollectKeyState(false)
pcall(function()
	UI.RemoveTab(uiTabName)
end)
