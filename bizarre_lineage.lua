loadstring(game:HttpGet('https://raw.githubusercontent.com/catowice/p/main/library.lua'))()

local ui = UILib
if not ui then return end

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
	collectRetryCooldown = 3.0,
	collectInstantTeleportDistance = 300,
	maxTrackedItems = 30,
	maxRenderedItems = 30,
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

local keybinds = { yLock = 0xDB, itemESP = 0xDD }
local keyDownState = {}
local itemDrawings = {}

local function getRootPart()
	local character = player and player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
end

local function setLockYPosition(forceExact)
	local root = getRootPart()
	if not root then return end
	local pos = root.Position
	if forceExact or pos.Y < state.lockYValue then
		pcall(function() root.Position = Vector3.new(pos.X, state.lockYValue, pos.Z) end)
		pcall(function()
			local vel = root.AssemblyLinearVelocity
			if vel then
				root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
			end
		end)
	end
end

local function stepSquareLockMovement(deltaTime)
	local root = getRootPart()
	if not root then return end
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
			local step = math.min(math.abs(range - state.lockOffsetX), remainingDistance)
			state.lockOffsetX = state.lockOffsetX + step
			remainingDistance = remainingDistance - step
			if state.lockOffsetX >= range then state.lockDirection = 2 end
		elseif state.lockDirection == 2 then
			local step = math.min(math.abs(range - state.lockOffsetZ), remainingDistance)
			state.lockOffsetZ = state.lockOffsetZ + step
			remainingDistance = remainingDistance - step
			if state.lockOffsetZ >= range then state.lockDirection = 3 end
		elseif state.lockDirection == 3 then
			local step = math.min(math.abs(-range - state.lockOffsetX), remainingDistance)
			state.lockOffsetX = state.lockOffsetX - step
			remainingDistance = remainingDistance - step
			if state.lockOffsetX <= -range then state.lockDirection = 4 end
		else
			local step = math.min(math.abs(-range - state.lockOffsetZ), remainingDistance)
			state.lockOffsetZ = state.lockOffsetZ - step
			remainingDistance = remainingDistance - step
			if state.lockOffsetZ <= -range then state.lockDirection = 1 end
		end
	end
	local origin = state.lockMotionOrigin
	local targetX = origin.X + state.lockOffsetX
	local targetZ = origin.Z + state.lockOffsetZ
	pcall(function()
		root.Position = Vector3.new(targetX, state.lockYValue, targetZ)
		local vel = root.AssemblyLinearVelocity
		if vel then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
	end)
end

local function resolveWorldPosition(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then return instance.Position end
	if instance:IsA("Model") and instance.PrimaryPart then return instance.PrimaryPart.Position end
	local directPart = instance:FindFirstChildWhichIsA("BasePart")
	if directPart then return directPart.Position end
	for _, d in ipairs(instance:GetDescendants()) do
		if d:IsA("BasePart") then return d.Position end
	end
	return nil
end

local function getItemAddressKey(instance)
	local okA, addr = pcall(function() return instance.Address end)
	if okA and addr then return string.format("0x%X", addr) end
	local okF, full = pcall(function() return instance:GetFullName() end)
	if okF and full then return full end
	return tostring(instance)
end

local function processNotificationQueue()
	if #state.notificationQueue == 0 then return end
	if os.clock() - state.lastNotificationAt < config.notificationCooldown then return end
	local text = table.remove(state.notificationQueue, 1)
	state.lastNotificationAt = os.clock()
	ui:Notification(text, 4)
	ui:Notification(text, 4)
	ui:Notification(text, 4)
end

local function moveTowards(current, target, maxStep)
	local dx = target.X - current.X
	local dy = target.Y - current.Y
	local dz = target.Z - current.Z
	local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
	if dist <= maxStep or dist <= 0.0001 then return target, dist end
	local s = maxStep / dist
	return Vector3.new(current.X + dx*s, current.Y + dy*s, current.Z + dz*s), dist
end

local function distanceXZ(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx*dx + dz*dz)
end

local function distance3D(a, b)
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function setCollectKeyState(shouldHold)
	if shouldHold and not state.collectHoldingKey then
		if keypress then pcall(keypress, 0x45) end
		state.collectHoldingKey = true
	elseif not shouldHold and state.collectHoldingKey then
		if keyrelease then pcall(keyrelease, 0x45) end
		state.collectHoldingKey = false
	end
end

local function isOtherPlayerNearItemXZ(itemPos, radius)
	local ok, list = pcall(function() return players:GetPlayers() end)
	if not ok or not list then return false end
	for _, p in ipairs(list) do
		if p ~= player and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
				or p.Character:FindFirstChild("Torso")
				or p.Character:FindFirstChild("UpperTorso")
			if r and distanceXZ(r.Position, itemPos) <= radius then return true end
		end
	end
	return false
end

local function removeOccupiedQueueEntry(key)
	if state.occupiedItemQueue[key] then
		state.occupiedItemQueue[key] = nil
		state.occupiedQueueSize = math.max(0, state.occupiedQueueSize - 1)
	end
end

local function queueOccupiedItem(key, instance, now)
	local entry = state.occupiedItemQueue[key]
	if entry then
		entry.instance = instance
		entry.lastQueuedAt = now
		if entry.nextCheckAt < now then entry.nextCheckAt = now + config.occupiedRecheckInterval end
		return
	end
	if state.occupiedQueueSize >= config.maxOccupiedQueue then return end
	state.occupiedItemQueue[key] = { instance = instance, nextCheckAt = now + config.occupiedRecheckInterval, lastQueuedAt = now }
	state.occupiedQueueSize = state.occupiedQueueSize + 1
end

local function findBestCollectTarget(rootPos)
	local now = os.clock()
	local bestKey, bestInst, bestPos, bestDist = nil, nil, nil, math.huge
	local toRemove = {}

	for key, entry in pairs(state.occupiedItemQueue) do
		if not entry or now - (entry.lastQueuedAt or 0) > config.addressRetentionSeconds then
			toRemove[key] = true
		elseif (entry.nextCheckAt or 0) <= now then
			local cooldown = state.collectCooldownByAddress[key] or 0
			if cooldown > now then
				entry.nextCheckAt = cooldown
			elseif not entry.instance or not entry.instance.Parent then
				toRemove[key] = true
			else
				local ok, wpos = pcall(resolveWorldPosition, entry.instance)
				if not ok or not wpos then
					toRemove[key] = true
				elseif state.autoCollectSkipOccupied and isOtherPlayerNearItemXZ(wpos, 5) then
					entry.nextCheckAt = now + config.occupiedRecheckInterval
					entry.lastQueuedAt = now
				else
					local dx = wpos.X - rootPos.X
					local dy = wpos.Y - rootPos.Y
					local dz = wpos.Z - rootPos.Z
					local d = math.sqrt(dx*dx + dy*dy + dz*dz)
					if d < bestDist then bestDist = d; bestKey = key; bestInst = entry.instance; bestPos = wpos end
				end
			end
		end
	end

	if bestKey then toRemove[bestKey] = true end
	for key in pairs(toRemove) do removeOccupiedQueueEntry(key) end

	if bestInst and bestPos then return bestInst, bestPos end

	bestDist = math.huge
	for _, instance in ipairs(state.itemCache) do
		if instance.Parent then
			local key = getItemAddressKey(instance)
			local cooldown = state.collectCooldownByAddress[key] or 0
			if now >= cooldown then
				local ok, wpos = pcall(resolveWorldPosition, instance)
				if ok and wpos then
					if state.autoCollectSkipOccupied and isOtherPlayerNearItemXZ(wpos, 5) then
						queueOccupiedItem(key, instance, now)
					else
						if state.occupiedItemQueue[key] then removeOccupiedQueueEntry(key) end
						local dx = wpos.X - rootPos.X
						local dy = wpos.Y - rootPos.Y
						local dz = wpos.Z - rootPos.Z
						local d = math.sqrt(dx*dx + dy*dy + dz*dz)
						if d < bestDist then bestDist = d; bestInst = instance; bestPos = wpos end
					end
				end
			end
		end
	end

	return bestInst, bestPos
end

local function runAutoCollect(deltaTime)
	if not state.autoCollect then setCollectKeyState(false); return end
	local root = getRootPart()
	if not root then setCollectKeyState(false); return end

	local function teleportRoot(pos)
		pcall(function()
			root.Position = pos
			local vel = root.AssemblyLinearVelocity
			if vel then root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
		end)
	end

	local now = os.clock()
	if now >= state.collectHoldStartAt and now < state.collectHoldUntil then
		setCollectKeyState(true); return
	end
	if state.collectHoldingKey and state.collectHoldUntil > 0 and state.collectHoldUntil <= now then
		setCollectKeyState(false)
		state.collectHoldStartAt = 0
		state.collectHoldUntil = 0
	end
	if state.collectPauseUntil > now then return end
	if now < state.collectTeleportCooldownUntil then return end

	local rootPos = root.Position
	local targetInst, targetPos = findBestCollectTarget(rootPos)

	if not targetInst or not targetPos then
		setCollectKeyState(false)
		if not state.autoCollectUseIdlePoints then return end

		local bestIdx, bestIdleDist = nil, math.huge
		for i, pt in ipairs(idleCollectPoints) do
			local d = distanceXZ(rootPos, pt)
			if d < bestIdleDist then bestIdleDist = d; bestIdx = i end
		end
		if not bestIdx then return end
		if state.collectIdleAtPoint and state.collectIdlePointIndex == bestIdx then return end

		local idlePt = idleCollectPoints[bestIdx]
		local underY = state.lockYValue + state.collectUnderMapYOffset
		local idleTarget = state.autoCollectUseUnderMapTravel
			and Vector3.new(idlePt.X, underY, idlePt.Z)
			or Vector3.new(idlePt.X, idlePt.Y + state.collectTeleportHeight, idlePt.Z)
		local step = math.max(1, state.collectFlySpeed) * (deltaTime or config.fallbackDeltaTime)
		local nextPos, idleDist = moveTowards(rootPos, idleTarget, step)
		local directIdleDist = distance3D(rootPos, idleTarget)

		if directIdleDist <= config.collectInstantTeleportDistance then
			teleportRoot(Vector3.new(idlePt.X, idlePt.Y + 10, idlePt.Z))
			state.collectIdlePointIndex = bestIdx
			state.collectIdleAtPoint = true
			state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
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
			state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
		end
		return
	end

	state.collectIdlePointIndex = nil
	state.collectIdleAtPoint = false

	local underY = state.lockYValue + state.collectUnderMapYOffset
	local travelTarget = state.autoCollectUseUnderMapTravel
		and Vector3.new(targetPos.X, underY, targetPos.Z)
		or Vector3.new(targetPos.X, targetPos.Y + state.collectTeleportHeight, targetPos.Z)
	local step = math.max(1, state.collectFlySpeed) * (deltaTime or config.fallbackDeltaTime)
	local nextPos, targetDist = moveTowards(rootPos, travelTarget, step)
	local directDist = distance3D(rootPos, travelTarget)

	if directDist <= config.collectInstantTeleportDistance then
		teleportRoot(Vector3.new(targetPos.X, targetPos.Y + state.collectTeleportHeight, targetPos.Z))
		task.wait(0.5)
		local key = getItemAddressKey(targetInst)
		state.collectCooldownByAddress[key] = now + config.collectRetryCooldown
		state.collectPauseUntil = now + 0.3
		state.collectHoldStartAt = state.collectPauseUntil
		state.collectHoldUntil = state.collectHoldStartAt + 1.0
		state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
		return
	end
	if targetDist > state.collectArrivalDistance then
		teleportRoot(Vector3.new(nextPos.X, underY, nextPos.Z))
		return
	end

	teleportRoot(Vector3.new(targetPos.X, targetPos.Y + state.collectTeleportHeight, targetPos.Z))
	local key = getItemAddressKey(targetInst)
	state.collectCooldownByAddress[key] = now + config.collectRetryCooldown
	state.collectPauseUntil = now + 0.3
	state.collectHoldStartAt = state.collectPauseUntil
	state.collectHoldUntil = state.collectHoldStartAt + 1.0
	state.collectTeleportCooldownUntil = now + config.collectTeleportCooldown
end

local function getOrCreateItemDrawBundle(instance)
	local bundle = itemDrawings[instance]
	if bundle then return bundle end
	local box = Drawing.new("Square")
	box.Filled = false; box.Thickness = 2; box.Visible = false; box.ZIndex = 2
	local text = Drawing.new("Text")
	text.Center = true; text.Outline = true; text.Color = Color3.fromRGB(255, 255, 255)
	text.Font = Drawing.Fonts.SystemBold; text.Size = 14; text.Visible = false; text.ZIndex = 3
	text.Text = instance.Name
	bundle = { box = box, text = text }
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
		bundle.box:Remove(); bundle.text:Remove()
		itemDrawings[key] = nil
	end
end

local function refreshItemCache()
	local now = os.clock()
	if now - state.itemCacheLastRefresh < state.itemCacheRefreshInterval then return end
	state.itemCacheLastRefresh = now
	state.itemCache = {}
	local seen = {}
	local ok, children = pcall(function() return workspace:GetChildren() end)
	if not ok or not children then return end
	for _, child in ipairs(children) do
		if child.Name == "Model" then
			local okD, descs = pcall(function() return child:GetDescendants() end)
			if okD and descs then
				for _, obj in ipairs(descs) do
					if trackedItemLookup[obj.Name] then
						local key = getItemAddressKey(obj)
						if not seen[key] then
							seen[key] = true
							table.insert(state.itemCache, obj)
							if state.itemScanInitialized and state.spawnNotifications and not state.seenItemAddresses[key] then
								if #state.notificationQueue < config.maxNotificationQueue then
									table.insert(state.notificationQueue, "Item spawned: " .. obj.Name)
								end
							end
							state.seenItemAddresses[key] = now
							if #state.itemCache >= config.maxTrackedItems then break end
						end
					end
				end
			end
		end
		if #state.itemCache >= config.maxTrackedItems then break end
	end
	for key, lastSeen in pairs(state.seenItemAddresses) do
		if now - lastSeen > config.addressRetentionSeconds then
			state.seenItemAddresses[key] = nil
			state.collectCooldownByAddress[key] = nil
			removeOccupiedQueueEntry(key)
		end
	end
	state.itemScanInitialized = true
end

local function renderItemESP()
	if not state.itemESP then hideAllItemDrawings(); return end
	local boxColor = state.espRainbowBox
		and Color3.fromHSV((os.clock() * config.rainbowSpeed) % 1, 1, 1)
		or Color3.fromRGB(255, 255, 255)
	local camPos
	do
		local ok, cam = pcall(function() return workspace.CurrentCamera end)
		if ok and cam then
			local okP, p = pcall(function() return cam.Position end)
			if okP then camPos = p end
		end
	end
	local seenThisFrame = {}
	local renderedCount = 0
	for _, obj in ipairs(state.itemCache) do
		if renderedCount >= state.maxRenderedItems then break end
		if obj.Parent then
			local okP, wpos = pcall(resolveWorldPosition, obj)
			if okP and wpos then
				local okW, spos, onScreen = pcall(WorldToScreen, wpos)
				if okW and onScreen and spos then
					local bundle = getOrCreateItemDrawBundle(obj)
					seenThisFrame[obj] = true
					renderedCount = renderedCount + 1
					local dist = camPos and distance3D(camPos, wpos) or 80
					local h = math.max(12, math.min(80, 1200 / math.max(dist, 1)))
					local w = h * 0.75
					bundle.box.Color = boxColor
					bundle.box.Thickness = state.espBoxThickness
					bundle.box.Size = Vector2.new(w, h)
					bundle.box.Position = Vector2.new(spos.X - w * 0.5, spos.Y - h * 0.5)
					bundle.box.Visible = state.espShowBox
					bundle.text.Text = obj.Name
					bundle.text.Position = Vector2.new(spos.X, spos.Y - h * 0.5 - 12)
					bundle.text.Visible = state.espShowText
				end
			end
		end
	end
	for instance, bundle in pairs(itemDrawings) do
		if not seenThisFrame[instance] then
			if instance.Parent then
				bundle.box.Visible = false; bundle.text.Visible = false
			else
				bundle.box:Remove(); bundle.text:Remove()
				itemDrawings[instance] = nil
			end
		end
	end
end

local _, settingsSection = ui:CreateSettingsTab("Settings")
local tabInfo 	 = ui:Tab("Info")
local tabCollect = ui:Tab("Collect")
local tabMain    = ui:Tab("Main")
local movementSection    = tabMain:Section("Movement")
local espSection         = tabMain:Section("ESP")
local autoCollectSection = tabCollect:Section("Auto Collect")
local infoSection		 = tabInfo:Section("IMPORTANT")

ui:SetMenuSize(Vector2.new(760, 560))
ui:CenterMenu()
ui:SetMenuTitle("Bizzare Lineage [stable]")
ui:SetWatermarkEnabled(false)

movementSection:Slider("Lock Y", state.lockYValue, 1, config.lockYMin, config.lockYMax, "", function(v)
	state.lockYValue = v
	if state.yLock then setLockYPosition(true) end
end)

local yLockToggle = movementSection:Toggle("Lock Y (VOID DIO)", false, function(enabled)
	state.yLock = enabled
	if state.autoCollect then return end
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
		state.lockOffsetX = 0; state.lockOffsetZ = 0; state.lockDirection = 1
		setLockYPosition(true)
	else
		local root = getRootPart()
		local cached = state.cachedReturnPosition
		if root and cached then pcall(function() root.Position = cached + Vector3.new(0, 10, 0) end) end
		state.cachedReturnPosition = nil; state.lockMotionOrigin = nil
		state.lockOffsetX = 0; state.lockOffsetZ = 0; state.lockDirection = 1
	end
end)

yLockToggle:AddKeybind("lbracket", "Toggle", true, function(k)
	if type(k) == "number" then keybinds.yLock = k; ui:Notification("Y lock bind updated", 3) end
end)

local itemESPToggle = espSection:Toggle("Item ESP", false, function(enabled)
	state.itemESP = enabled
	if enabled then
		state.itemScanInitialized = false; state.itemCacheLastRefresh = 0; state.notificationQueue = {}
	else
		hideAllItemDrawings()
	end
end)

itemESPToggle:AddKeybind("rbracket", "Toggle", true, function(k)
	if type(k) == "number" then keybinds.itemESP = k; ui:Notification("Item ESP bind updated", 3) end
end)

espSection:Toggle("Spawn Notify", state.spawnNotifications, function(v) state.spawnNotifications = v end)
espSection:Toggle("Show Box", state.espShowBox, function(v) state.espShowBox = v end)
espSection:Toggle("Show Text", state.espShowText, function(v) state.espShowText = v end)
espSection:Toggle("Rainbow Box", state.espRainbowBox, function(v) state.espRainbowBox = v end)
espSection:Slider("Box Thick", state.espBoxThickness, 1, 1, 4, "", function(v) state.espBoxThickness = v end)
espSection:Slider("Scan Rate", state.itemCacheRefreshInterval, 0.05, 0.2, 2.0, "s", function(v) state.itemCacheRefreshInterval = v end)
espSection:Slider("Max ESP", state.maxRenderedItems, 1, 5, config.maxTrackedItems, "", function(v) state.maxRenderedItems = v end)

autoCollectSection:Slider("Fly Speed", state.collectFlySpeed, 5, config.collectFlySpeedMin, config.collectFlySpeedMax, "", function(v) state.collectFlySpeed = v end)
autoCollectSection:Slider("Arrival Dist", state.collectArrivalDistance, 1, 10, 80, "", function(v) state.collectArrivalDistance = v end)
autoCollectSection:Slider("Teleport +Y", state.collectTeleportHeight, 1, 5, 25, "", function(v) state.collectTeleportHeight = v end)
autoCollectSection:Slider("UnderMap +Y", state.collectUnderMapYOffset, 5, 20, 260, "", function(v) state.collectUnderMapYOffset = v end)
autoCollectSection:Toggle("Idle Wait Points", state.autoCollectUseIdlePoints, function(v) state.autoCollectUseIdlePoints = v end)
autoCollectSection:Toggle("Travel UnderMap", state.autoCollectUseUnderMapTravel, function(v) state.autoCollectUseUnderMapTravel = v end)
autoCollectSection:Toggle("Skip Occupied", state.autoCollectSkipOccupied, function(v) state.autoCollectSkipOccupied = v end)

autoCollectSection:Toggle("Auto Collect", false, function(enabled)
	state.autoCollect = enabled
	if enabled then
		state.lockYWasEnabledBeforeCollect = state.yLock
		if state.yLock then yLockToggle:Set(false) end
	else
		state.collectPauseUntil = 0; state.collectHoldStartAt = 0; state.collectHoldUntil = 0
		state.collectTeleportCooldownUntil = 0; state.collectIdlePointIndex = nil
		state.collectIdleAtPoint = false; state.occupiedItemQueue = {}; state.occupiedQueueSize = 0
		setCollectKeyState(false)
		if state.lockYWasEnabledBeforeCollect then yLockToggle:Set(true) end
		state.lockYWasEnabledBeforeCollect = false
	end
end)

settingsSection:Button("Unload", function() state.shouldUnload = true end)
_G.__bizzareLineageUnload = function() state.shouldUnload = true end

infoSection:Button("DONT DM LIKETY FOR HELP")
infoSection:Button("-----------------------")
infoSection:Button("FOR ANY HELP REGARDING")
infoSection:Button("THE SCRIPT DM: BigJose42")

ui:Notification("Default binds: '[' = Lock Y | ']' = Item ESP", 6)
ui:Notification("PLEASE: dont dm likety for help with the script", 6)
ui:Notification("for help dm me: BigJose42", 6)

local lastFrameTime = os.clock()

local function updateFrame()
	local now = os.clock()
	local deltaTime = math.min(now - lastFrameTime, 0.1)
	lastFrameTime = now

	local okY, yDown = pcall(function() return iskeypressed and iskeypressed(keybinds.yLock) end)
	if not okY then yDown = false end
	local wasY = keyDownState[keybinds.yLock] == true
	keyDownState[keybinds.yLock] = yDown and true or false
	if yDown and not wasY then yLockToggle:Set(not state.yLock) end

	local okE, eDown = pcall(function() return iskeypressed and iskeypressed(keybinds.itemESP) end)
	if not okE then eDown = false end
	local wasE = keyDownState[keybinds.itemESP] == true
	keyDownState[keybinds.itemESP] = eDown and true or false
	if eDown and not wasE then itemESPToggle:Set(not state.itemESP) end

	if state.yLock and not state.autoCollect then stepSquareLockMovement(deltaTime) end
	if state.itemESP or state.autoCollect then refreshItemCache() end
	if state.autoCollect then runAutoCollect(deltaTime) end
	if state.itemESP then renderItemESP() end
	processNotificationQueue()
end

local frameLoopAlive = true
task.spawn(function()
	while frameLoopAlive and not state.shouldUnload do
		local now = os.clock()
		if now >= state.runtimeCooldownUntil then
			local ok = pcall(updateFrame)
			if ok then
				state.frameErrorCount = math.max(0, state.frameErrorCount - 1)
			else
				state.frameErrorCount = state.frameErrorCount + 1
				if state.frameErrorCount >= 20 then
					state.autoCollect = false; state.itemESP = false
					setCollectKeyState(false); hideAllItemDrawings()
					state.runtimeCooldownUntil = now + 1.5
					state.frameErrorCount = 0
				end
			end
		end
		task.wait()
	end
end)

while not state.shouldUnload do
	UILib:Step()
	task.wait()
end

frameLoopAlive = false
removeAllItemDrawings()
setCollectKeyState(false)
ui:Unload()
