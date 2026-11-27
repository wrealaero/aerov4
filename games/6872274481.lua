local runDepth, runCount = 0, 0
local run = function(func)
	if runDepth == 0 then
		runCount += 1
		if runCount % 8 == 0 then
			task.wait()
		end
	end
	runDepth += 1
	local ok, err = pcall(func)
	runDepth -= 1
	if not ok then
		warn('[aerov4] module failed to load: ' .. tostring(err))
	end
end
task.wait()
local vapeEvents = setmetatable({}, {
	__index = function(self, index)
		self[index] = Instance.new('BindableEvent')
		return self[index]
	end
})
getgenv().vapeEvents = vapeEvents

local cloneref = cloneref or function(obj)
	return obj
end

local function safeGetProto(func, index)
	if type(func) ~= 'function' then return nil end
	if debug.getproto then
		local ok, proto = pcall(debug.getproto, func, index)
		if ok and type(proto) == 'function' then
			return proto
		end
	end
	return nil
end

local inventoryDebounce = false
local function fireInventoryChanged()
	if inventoryDebounce then return end
	inventoryDebounce = true
	task.spawn(function()
		task.wait()
		vapeEvents.InventoryChanged:Fire()
		inventoryDebounce = false
	end)
end

local playersService = cloneref(game:GetService('Players'))
local collectionService = cloneref(game:GetService('CollectionService'))
local function getLocalKits()
	local raw = playersService.LocalPlayer:GetAttribute('PlayingAsKits')
	local list = {}
	if type(raw) == 'string' then
		for kit in raw:gmatch('[%w_]+') do
			if kit ~= 'none' then
				table.insert(list, kit)
			end
		end
	end
	return list
end
getgenv().aeroTeamColors = {
	[1] = {name = 'blue', color = Color3.fromRGB(85, 150, 255)},
	[2] = {name = 'orange', color = Color3.fromRGB(255, 150, 50)},
	[3] = {name = 'pink', color = Color3.fromRGB(255, 100, 200)},
	[4] = {name = 'yellow', color = Color3.fromRGB(255, 255, 50)},
	[5] = {name = 'brown', color = Color3.fromRGB(139, 69, 19)},
	[6] = {name = 'white', color = Color3.fromRGB(255, 255, 255)},
	[7] = {name = 'cyan', color = Color3.fromRGB(120, 255, 255)},
	[8] = {name = 'purple', color = Color3.fromRGB(180, 90, 255)},
}
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local httpService = cloneref(game:GetService('HttpService'))
local contextActionService = cloneref(game:GetService('ContextActionService'))
local guiService = cloneref(game:GetService('GuiService'))
local coreGui = cloneref(game:GetService('CoreGui'))
local VirtualInputManager = cloneref(game:GetService('VirtualInputManager'))

local isnetworkowner = identifyexecutor and table.find({'Delta', 'Volt'}, ({identifyexecutor()})[1]) and isnetworkowner or function()
	return true
end
local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer

local vape = shared.vape
if not vape.Clean then
	vape.Connections = vape.Connections or {}
	function vape:Clean(obj)
		table.insert(self.Connections, type(obj) == 'function' and {Disconnect = obj} or obj)
	end
end
if not vape.Remove then
	function vape:Remove() end
end

local function wrapModuleFunction(settings)
	local fn = type(settings) == 'table' and settings.Function
	if type(fn) ~= 'function' then return end
	local enableThread
	settings.Function = function(state, ...)
		local current = coroutine.running()
		if state and enableThread and enableThread ~= current and coroutine.status(enableThread) == 'suspended' then
			pcall(task.cancel, enableThread)
		end
		if state then
			enableThread = current
		end
		return fn(state, ...)
	end
end

for _, holder in {vape.Categories or {}, {vape.Legit}} do
	for _, category in holder do
		if type(category) == 'table' and type(category.CreateModule) == 'function' and not category.AeroWrapped then
			local createModule = category.CreateModule
			category.AeroWrapped = true
			category.CreateModule = function(self, settings, ...)
				wrapModuleFunction(settings)
				return createModule(self, settings, ...)
			end
		end
	end
end
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo
local uipallet = vape.Libraries.uipallet
local tween = vape.Libraries.tween
local color = vape.Libraries.color
local whitelist = {get = function() return nil, true end, tag = function() return '' end, customtags = {}}
local prediction = vape.Libraries.prediction
local getfontsize = vape.Libraries.getfontsize
local getcustomasset = vape.Libraries.getcustomasset

local store = {
	attackReach = 0,
	attackReachUpdate = tick(),
	hand = {},
	inventory = {
		inventory = {
			items = {},
			armor = {}
		},
		hotbar = {}
	},
	inventories = setmetatable({}, {__mode = 'k'}),
	matchState = 0,
	queueType = 'bedwars_test',
	tools = {},
	lastToolUpdate = 0,
	lastKrystalUpdateCheck = 0,
	BedAlarmNotifyTick = 0,
	BedAlarmIsTrigged = false,
	BedAlarmHighlightedEnimes = {},
	BedAlarm = {},
	BedAlarmSoundTick = 0,
	silasAbilityTime = 0,
	terraStompTime = 0,
	terraKickTime = 0,
}
getgenv().store = store
local splashParams = RaycastParams.new()
splashParams.FilterType = Enum.RaycastFilterType.Include
local function splashAimPoint(root, hip)
	local map = workspace:FindFirstChild('Map')
	if not map or not root then return nil end
	if math.abs(root.AssemblyLinearVelocity.Y) > 2 then return nil end
	splashParams.FilterDescendantsInstances = {map}
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -((hip or 2) + root.Size.Y / 2 + 0.6), 0), splashParams)
	if hit then
		return Vector3.new(root.Position.X, hit.Position.Y + 0.5, root.Position.Z)
	end
	return nil
end
local function balloonGravity(balloons, char)
	local lift = balloons >= 4 and 1.2 or balloons >= 3 and 1.1 or balloons >= 2 and 0.975 or 0.85
	local root = char and char.PrimaryPart
	local vy = root and root.AssemblyLinearVelocity.Y or 0
	return workspace.Gravity * (1 - lift) + 0.1731 * vy * math.abs(vy)
end
local Reach = {}
local HitBoxes = {}
local TrapDisabler
local TrapSnap, TrapMine, TrapTeleport, TrapPortal = {}, {}, {}, {}
local bedwars, remotes, oldinvrender = {}, {}, nil

local function getReach(tool)
	local itemMeta = tool and bedwars.ItemMeta and bedwars.ItemMeta[tool.Name]
	return itemMeta and itemMeta.sword and itemMeta.sword.attackRange or 14.4
end
getgenv().getReach = getReach

local function addBlur(parent)
	local blur = Instance.new('ImageLabel')
	blur.Name = 'Blur'
	blur.Size = UDim2.new(1, 89, 1, 52)
	blur.Position = UDim2.fromOffset(-48, -31)
	blur.BackgroundTransparency = 1
	blur.Image = getcustomasset('aerov4/assets/new/blur.png')
	blur.ScaleType = Enum.ScaleType.Slice
	blur.SliceCenter = Rect.new(52, 31, 261, 502)
	blur.Parent = parent
	return blur
end

local readyGate = getgenv().aeroReadyGate or {}
getgenv().aeroReadyGate = readyGate

function readyGate.Release()
	if not readyGate.Held then
		return
	end
	readyGate.Held = false
	local heldRemote = readyGate.Remote
	readyGate.Remote = nil
	if heldRemote then
		heldRemote:FireServer()
	end
end

if not readyGate.Hooked and hookmetamethod and not lplr:GetAttribute('PlayerConnected') then
	readyGate.Hooked = true
	readyGate.Held = true
	readyGate.Started = os.clock()
	local wrap = newcclosure or function(f) return f end
	local oldNamecall
	oldNamecall = hookmetamethod(game, '__namecall', wrap(function(...)
		local self = ...
		if readyGate.Held and not checkcaller() and getnamecallmethod() == 'FireServer' and tostring(self) == 'PlayerReady' then
			readyGate.Remote = self
			return
		end
		return oldNamecall(...)
	end))
	task.delay(45, function()
		if not readyGate.Claimed then
			readyGate.Release()
		end
	end)
end
vape:Clean(function()
	readyGate.Release()
end)

local function notif(...)
	return vape:CreateNotification(...)
end

local netManaged
local netPath = {'rbxts_include', 'node_modules', '@rbxts', 'net', 'out', '_NetManaged'}
local function getNetManaged(yield)
	if netManaged and netManaged.Parent then
		return netManaged
	end
	local node = replicatedStorage
	for _, name in netPath do
		node = yield and node:WaitForChild(name, 30) or node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	netManaged = node
	return node
end

local function getNetRemote(name, yield)
	local net = getNetManaged(yield)
	if not net then
		return nil
	end
	return yield and net:WaitForChild(name, 30) or net:FindFirstChild(name)
end

local abilityRemote
local function getAbilityRemote()
	if not (abilityRemote and abilityRemote.Parent) then
		local events = replicatedStorage:FindFirstChild('events-@easy-games/game-core:shared/game-core-networking@getEvents.Events')
		abilityRemote = events and events:FindFirstChild('useAbility')
	end
	return abilityRemote
end

local function collection(tags, module, customadd, customremove)
	tags = typeof(tags) ~= 'table' and {tags} or tags
	local objs, connections = {}, {}
	local fastIndex = #tags == 1 and tags[1] == 'block' and not customadd and not customremove and {} or nil

	for _, tag in tags do
		table.insert(connections, collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if customadd then
				customadd(objs, v, tag)
				return
			end
			if fastIndex and fastIndex[v] then return end
			table.insert(objs, v)
			if fastIndex then fastIndex[v] = #objs end
		end))
		table.insert(connections, collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if customremove then
				customremove(objs, v, tag)
				return
			end
			local idx = fastIndex and fastIndex[v] or (not fastIndex and table.find(objs, v))
			if idx then
				local last = #objs
				local moved = objs[last]
				objs[idx] = moved
				objs[last] = nil
				if fastIndex then
					fastIndex[v] = nil
					if idx ~= last then fastIndex[moved] = idx end
				end
			end
		end))

		for _, v in collectionService:GetTagged(tag) do
			if customadd then
				customadd(objs, v, tag)
				continue
			end
			if not fastIndex or not fastIndex[v] then
				table.insert(objs, v)
				if fastIndex then fastIndex[v] = #objs end
			end
		end
	end

	local cleanFunc = function(self)
		for _, v in connections do
			v:Disconnect()
		end
		table.clear(connections)
		table.clear(objs)
		if fastIndex then table.clear(fastIndex) end
		table.clear(self)
	end
	if module then
		module:Clean(cleanFunc)
	end
	return objs, cleanFunc
end

local function scanDescendants(root, fn, module)
	local state = {cancelled = false}
	if module then
		module:Clean(function() state.cancelled = true end)
	end
	task.spawn(function()
		local stack = {root or workspace}
		local budget = 0
		while #stack > 0 do
			if state.cancelled then return end
			local node = stack[#stack]
			stack[#stack] = nil
			local kids = node:GetChildren()
			for i = 1, #kids do
				local child = kids[i]
				stack[#stack + 1] = child
				fn(child)
			end
			budget += #kids
			if budget >= 700 then
				budget = 0
				task.wait()
				if state.cancelled then return end
			end
		end
	end)
	return state
end

local function cleanThread(module, thread)
	module:Clean(function()
		if thread then
			pcall(task.cancel, thread)
			thread = nil
		end
	end)
	return thread
end

local function invItems()
	local inv = store.inventory
	inv = inv and inv.inventory
	return (inv and inv.items) or {}
end

local function getBow()
	local bestBow, bestBowSlot, bestBowDamage = nil, nil, 0
	for slot, item in invItems() do
		local meta = bedwars.ItemMeta[item.itemType]
		local bowMeta = meta and meta.projectileSource
		if bowMeta and bowMeta.ammoItemTypes and table.find(bowMeta.ammoItemTypes, 'arrow') then
			local projMeta = bedwars.ProjectileMeta and bedwars.ProjectileMeta[bowMeta.projectileType('arrow')]
			local bowDamage = projMeta and projMeta.combat and projMeta.combat.damage or 0
			if bowDamage > bestBowDamage then
				bestBow, bestBowSlot, bestBowDamage = item, slot, bowDamage
			end
		end
	end
	return bestBow, bestBowSlot
end

local function getItem(itemName, inv)
	for slot, item in (inv or invItems()) do
		if item.itemType == itemName then
			return item, slot
		end
	end
	return nil
end

local function getRoactRender(func)
	return debug.getupvalue(debug.getupvalue(debug.getupvalue(func, 3).render, 2).render, 1)
end

local function getSword()
	local bestSword, bestSwordSlot, bestSwordDamage = nil, nil, 0
	for slot, item in invItems() do
		local meta = bedwars.ItemMeta[item.itemType]
		local swordMeta = meta and meta.sword
		if swordMeta then
			local swordDamage = swordMeta.damage or 0
			if swordDamage > bestSwordDamage then
				bestSword, bestSwordSlot, bestSwordDamage = item, slot, swordDamage
			end
		end
	end
	return bestSword, bestSwordSlot
end

local function getTool(breakType)
	local bestTool, bestToolSlot, bestToolDamage = nil, nil, 0
	for slot, item in invItems() do
		local meta = bedwars.ItemMeta[item.itemType]
		local toolMeta = meta and meta.breakBlock
		if toolMeta then
			local toolDamage = toolMeta[breakType] or 0
			if toolDamage > bestToolDamage then
				bestTool, bestToolSlot, bestToolDamage = item, slot, toolDamage
			end
		end
	end
	return bestTool, bestToolSlot
end

local function getWool()
	for _, item in invItems() do
		if item.itemType:find('wool') then
			return item.itemType, item.amount
		end
	end
end

local function getStrength(plr)
	if not plr or not plr.Player then
		return 0
	end
	local strength = 0
	local inv = store.inventories[plr.Player]
	for _, v in (inv and inv.items or {}) do
		local meta = bedwars.ItemMeta[v.itemType]
		if meta and meta.sword and (meta.sword.damage or 0) > strength then
			strength = meta.sword.damage
		end
	end
	return strength
end

local function getPlacedBlock(pos)
	if not pos then
		return
	end
	local roundedPosition = bedwars.BlockController:getBlockPosition(pos)
	return bedwars.BlockController:getStore():getBlockAt(roundedPosition), roundedPosition
end

local function getBlocksInPoints(s, e)
	local blocks, list = bedwars.BlockController:getStore(), {}
	for x = s.X, e.X do
		for y = s.Y, e.Y do
			for z = s.Z, e.Z do
				local vec = Vector3.new(x, y, z)
				if blocks:getBlockAt(vec) then
					table.insert(list, vec * 3)
				end
			end
		end
	end
	return list
end

local itemSkinMetaFn
local function getItemSkinMeta(skin)
	if itemSkinMetaFn == nil then
		itemSkinMetaFn = false
		pcall(function()
			for _, m in replicatedStorage.TS.games.bedwars['item-skin']:GetDescendants() do
				if m:IsA('ModuleScript') then
					local ok, res = pcall(require, m)
					if ok and type(res) == 'table' and type(res.getItemSkinMeta) == 'function' then
						itemSkinMetaFn = res.getItemSkinMeta
						break
					end
				end
			end
		end)
	end
	if not itemSkinMetaFn then return nil end
	local ok, res = pcall(itemSkinMetaFn, skin)
	return ok and res or nil
end

local skinSoundBackup = {}
local function applySkinSounds(itemType, skin)
	local meta = bedwars.ItemMeta and bedwars.ItemMeta[itemType]
	if not meta then return end
	local backup = skinSoundBackup[itemType]
	if backup then
		for _, v in backup do
			v[1][v[2]] = v[3]
		end
		skinSoundBackup[itemType] = nil
	end
	local skinmeta = skin and getItemSkinMeta(skin)
	if type(skinmeta) ~= 'table' then return end
	local saved = {}
	for section, data in skinmeta do
		local target = meta[section]
		if type(data) == 'table' and type(target) == 'table' then
			for key, val in data do
				if type(key) == 'string' and key:lower():find('sound') then
					table.insert(saved, {target, key, target[key]})
					target[key] = val
				end
			end
		end
	end
	if #saved > 0 then
		skinSoundBackup[itemType] = saved
	end
end

local function getShieldAttribute(char)
	local total = char:GetAttribute('TotalShield')
	if type(total) == 'number' then
		return math.max(total, 0)
	end
	local returned = 0
	for name, val in char:GetAttributes() do
		if name:find('Shield') and type(val) == 'number' and val > 0 then
			returned += val
		end
	end
	return returned
end

local function getSpeed()
	local multi, increase = 0, true
	local modifiers = bedwars.SprintController:getMovementStatusModifier():getModifiers()
	for _, v in modifiers do
		if type(v) == 'table' then
			local val = v.constantSpeedMultiplier or 0
			if val > math.max(multi, 1) then
				increase = false
				multi = val - (0.06 * math.round(val))
			end
		end
	end
	for _, v in modifiers do
		if type(v) == 'table' then
			multi += math.max((v.moveSpeedMultiplier or 0) - 1, 0)
		end
	end
	if multi > 0 and increase then
		multi += 0.16 + (0.02 * math.round(multi))
	end
	return 20 * (multi + 1)
end

local function getTableSize(tab)
	local ind = 0
	for _ in tab do
		ind += 1
	end
	return ind
end

local function hotbarSwitch(slot)
	if slot and store.inventory.hotbarSlot ~= slot then
		local changed = false
		local conn = vapeEvents.InventoryChanged.Event:Once(function()
			changed = true
		end)
		bedwars.Store:dispatch({
			type = 'InventorySelectHotbarSlot',
			slot = slot
		})
		local timeout = os.clock() + 0.5
		repeat
			task.wait()
		until changed or os.clock() > timeout
		conn:Disconnect()
		return true
	end
	return false
end

local function getHotbar(tool)
	for i, v in (store.inventory.hotbar or {}) do
		if v.item and v.item.tool == tool then
			return i - 1
		end
	end
	return nil
end
getgenv().getHotbar = getHotbar

local function isFriend(plr, recolor)
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = table.find(vape.Categories.Friends.ListEnabled, plr.Name) and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end

local function isTarget(plr)
	return table.find(vape.Categories.Targets.ListEnabled, plr.Name) and true
end

local function removeTags(str)
	str = str:gsub('<br%s*/>', '\n')
	return (str:gsub('<[^<>]->', ''))
end

local function roundPos(vec)
	return Vector3.new(
		math.round(vec.X / 3) * 3,
		math.round(vec.Y / 3) * 3,
		math.round(vec.Z / 3) * 3
	)
end

local function switchItem(tool, delayTime)
	if not tool or not tool.Parent then return end
	local hand = lplr.Character and lplr.Character:FindFirstChild('HandInvItem')
	if hand and hand.Value ~= tool then
		task.spawn(function()
			bedwars.Client:Get(remotes.EquipItem):CallServerAsync({hand = tool})
		end)
		hand.Value = tool
		delayTime = delayTime or 0.05
		if delayTime > 0 then
			task.wait(delayTime)
		end
		return true
	end
end

local function waitForChildOfType(obj, name, timeout, prop)
	local check, returned = tick() + timeout
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if (returned and returned.Name ~= 'UpperTorso') or check < tick() then
			break
		end
		task.wait()
	until false
	return returned
end

local frictionTable, oldfrict = {}, setmetatable({}, {__mode = 'k'})
local frictionConnection
local frictionState

local function modifyVelocity(v)
	if v:IsA('BasePart') and v.Name ~= 'HumanoidRootPart' and not oldfrict[v] then
		oldfrict[v] = v.CustomPhysicalProperties or 'none'
		v.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0.2, 0.5, 1, 1)
	end
end

local function updateVelocity(force)
	local newState = getTableSize(frictionTable) > 0
	if frictionState ~= newState or force then
		if frictionConnection then
			frictionConnection:Disconnect()
			frictionConnection = nil
		end
		if newState then
			if entitylib.isAlive then
				for _, v in entitylib.character.Character:GetDescendants() do
					modifyVelocity(v)
				end
				frictionConnection = entitylib.character.Character.DescendantAdded:Connect(modifyVelocity)
			end
		else
			for i, v in oldfrict do
				i.CustomPhysicalProperties = v ~= 'none' and v or nil
			end
			table.clear(oldfrict)
		end
	end
	frictionState = newState
end

local function HasSeed(character)
	if not character then return false end
	return character:FindFirstChild('Seed', true) ~= nil
end

local sortmethods = {
	Threat = function(a, b)
		if not a.Entity then return false end
		if not b.Entity then return true end
		return getStrength(a.Entity) > getStrength(b.Entity)
	end,
	Health = function(a, b)
		if not a.Entity then return false end
		if not b.Entity then return true end
		return a.Entity.Health < b.Entity.Health
	end,
	Angle = function(a, b)
		if not a.Entity or not a.Entity.RootPart then return false end
		if not b.Entity or not b.Entity.RootPart then return true end
		local selfrootpos = entitylib.character.RootPart.Position
		local rawFacing = gameCamera.CFrame.LookVector
		local flatFacing = Vector3.new(rawFacing.X, 0, rawFacing.Z)
		if flatFacing.Magnitude < 0.001 then return false end
		local localFacing = flatFacing.Unit
		local deltaA = Vector3.new(a.Entity.RootPart.Position.X - selfrootpos.X, 0, a.Entity.RootPart.Position.Z - selfrootpos.Z)
		local deltaB = Vector3.new(b.Entity.RootPart.Position.X - selfrootpos.X, 0, b.Entity.RootPart.Position.Z - selfrootpos.Z)
		if deltaA.Magnitude < 0.001 or deltaB.Magnitude < 0.001 then return deltaA.Magnitude < deltaB.Magnitude end
		local angle = math.acos(math.clamp(localFacing:Dot(deltaA.Unit), -1, 1))
		local angle2 = math.acos(math.clamp(localFacing:Dot(deltaB.Unit), -1, 1))
		return angle < angle2
	end,
	Distance = function(a, b)
		if not a.Entity or not a.Entity.RootPart then return false end
		if not b.Entity or not b.Entity.RootPart then return true end
		local selfpos = entitylib.character.RootPart.Position
		local distA = (a.Entity.RootPart.Position - selfpos).Magnitude
		local distB = (b.Entity.RootPart.Position - selfpos).Magnitude
		return distA < distB
	end,
	Cursor = function(a, b)
		if not a.Entity or not a.Entity.RootPart then return false end
		if not b.Entity or not b.Entity.RootPart then return true end
		local camera = gameCamera
		local mousePos = inputService:GetMouseLocation()
		local function screenDist(ent)
			local rootPart = ent.RootPart
			if not rootPart then return math.huge end
			local screenPos, onScreen = camera:WorldToScreenPoint(rootPart.Position)
			if not onScreen then return math.huge end
			return (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
		end
		local distA = screenDist(a.Entity)
		local distB = screenDist(b.Entity)
		if distA == math.huge and distB == math.huge then
			local selfpos = entitylib.character.RootPart.Position
			local worldA = (a.Entity.RootPart.Position - selfpos).Magnitude
			local worldB = (b.Entity.RootPart.Position - selfpos).Magnitude
			return worldA < worldB
		end
		return distA < distB
	end,
	Forest = function(a, b)
		if not a.Entity then return false end
		if not b.Entity then return true end
		local aHasSeed = HasSeed(a.Entity.Character)
		local bHasSeed = HasSeed(b.Entity.Character)
		if aHasSeed and not bHasSeed then return true end
		if not aHasSeed and bHasSeed then return false end
		if not a.Entity.RootPart then return false end
		if not b.Entity.RootPart then return true end
		local selfpos = entitylib.character.RootPart.Position
		local distA = (a.Entity.RootPart.Position - selfpos).Magnitude
		local distB = (b.Entity.RootPart.Position - selfpos).Magnitude
		return distA < distB
	end
}

local function getSortList(priority)
	local methods = {}
	for _, v in ipairs(priority or {}) do
		table.insert(methods, v)
	end
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	return methods
end

run(function()
	local inventorySlots = {'ArmorInvItem_0', 'ArmorInvItem_1', 'ArmorInvItem_2', 'HandInvItem'}

	local function readHealth(char)
		return (char:GetAttribute('Health') or 100) + getShieldAttribute(char)
	end

	local function inventoryKey(inv)
		local key = inv.hand and inv.hand.itemType or ''
		for i = 4, 6 do
			local piece = inv.armor and inv.armor[i]
			key ..= '|' .. tostring(type(piece) == 'table' and piece.itemType or '')
		end
		return key
	end

	local function recheckTargets()
		for _, ent in entitylib.List do
			ent.Targetable = entitylib.targetCheck(ent)
			entitylib.Events.EntityUpdated:Fire(ent)
		end
	end

	local function npcTeamCheck(self)
		local team = self.Character:GetAttribute('Team')
		return not team or lplr:GetAttribute('Team') ~= team
	end

	local function addTaggedEntity(ent)
		if playersService:GetPlayerFromCharacter(ent) then return end
		if ent.Parent and collectionService:HasTag(ent.Parent, 'entity') then return end
		entitylib.addEntity(ent, nil, npcTeamCheck)
	end

	local function addDesertPot(pot)
		if pot:IsA('Model') then
			entitylib.addEntity(pot, nil, function() return true end)
		end
	end

	local function trackPlayer(entity, char, plr, hum, conns)
		local alive, pending, lastKey = true, false, nil

		local function syncInventory(force)
			if not alive or not bedwars.getInventory then return end
			local inv = bedwars.getInventory(plr)
			if not inv then return end
			store.inventories[plr] = inv
			local key = inventoryKey(inv)
			if force or key ~= lastKey then
				lastKey = key
				entitylib.Events.EntityUpdated:Fire(entity)
			end
		end

		for _, name in inventorySlots do
			local value = char:FindFirstChild(name)
			if value then
				table.insert(conns, value:GetPropertyChangedSignal('Value'):Connect(function()
					if pending then return end
					pending = true
					task.delay(0.1, function()
						pending = false
						syncInventory(true)
					end)
				end))
			end
		end

		table.insert(conns, hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				entity.JumpTick = tick()
				entity.Jumps += 1
				entity.LandTick = tick() + 1
				entity.Jumping = entity.Jumps > 1
			elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Freefall then
				entity.Jumping = false
			end
		end))

		local poll = task.spawn(function()
			local waitTime = 0.3
			while alive and plr.Parent and char.Parent do
				syncInventory(false)
				task.wait(waitTime)
				waitTime = math.min(1.2, waitTime + 0.15)
			end
		end)

		table.insert(conns, {
			Disconnect = function()
				alive = false
				pcall(task.cancel, poll)
			end
		})
	end

	entitylib.start = function()
		if entitylib.Running then entitylib.stop() end
		local conns = entitylib.Connections

		table.insert(conns, playersService.PlayerAdded:Connect(function(plr)
			entitylib.addPlayer(plr)
		end))
		table.insert(conns, playersService.PlayerRemoving:Connect(function(plr)
			entitylib.removePlayer(plr)
		end))
		for _, plr in playersService:GetPlayers() do
			entitylib.addPlayer(plr)
		end

		for _, ent in collectionService:GetTagged('entity') do
			addTaggedEntity(ent)
		end
		table.insert(conns, collectionService:GetInstanceAddedSignal('entity'):Connect(addTaggedEntity))
		table.insert(conns, collectionService:GetInstanceRemovedSignal('entity'):Connect(function(ent)
			entitylib.removeEntity(ent)
		end))

		for _, pot in collectionService:GetTagged('desert_pot') do
			addDesertPot(pot)
		end
		table.insert(conns, collectionService:GetInstanceAddedSignal('desert_pot'):Connect(addDesertPot))
		table.insert(conns, collectionService:GetInstanceRemovedSignal('desert_pot'):Connect(function(pot)
			entitylib.removeEntity(pot)
		end))

		table.insert(conns, workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
			gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
		end))

		entitylib.Running = true
	end

	entitylib.addPlayer = function(plr)
		local old = entitylib.PlayerConnections[plr]
		if old then
			for _, conn in old do
				conn:Disconnect()
			end
		end

		local teamPending = false
		local function teamChanged()
			if teamPending then return end
			teamPending = true
			task.defer(function()
				teamPending = false
				if plr == lplr then
					recheckTargets()
				elseif plr.Parent then
					entitylib.refreshEntity(plr.Character, plr)
				end
			end)
		end

		if plr.Character then
			entitylib.refreshEntity(plr.Character, plr)
		end
		entitylib.PlayerConnections[plr] = {
			plr.CharacterAdded:Connect(function(char)
				entitylib.refreshEntity(char, plr)
			end),
			plr.CharacterRemoving:Connect(function(char)
				entitylib.removeEntity(char, plr == lplr)
			end),
			plr:GetAttributeChangedSignal('Team'):Connect(teamChanged),
			plr:GetPropertyChangedSignal('Team'):Connect(teamChanged)
		}
	end

	entitylib.removePlayer = function(plr)
		local conns = entitylib.PlayerConnections[plr]
		if conns then
			for _, conn in conns do
				conn:Disconnect()
			end
			entitylib.PlayerConnections[plr] = nil
		end
		if plr.Character then
			entitylib.removeEntity(plr.Character, plr == lplr)
		end
		entitylib.removeEntity(plr)
	end

	entitylib.addEntity = function(char, plr, teamfunc)
		if not char then return end
		entitylib.EntityThreads[char] = task.spawn(function()
			local hum, root, head
			if plr then
				hum = waitForChildOfType(char, 'Humanoid', 10)
				root = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
				head = char:WaitForChild('Head', 10) or root
			else
				hum = {HipHeight = 0.5}
				root = waitForChildOfType(char, 'PrimaryPart', 10, true)
				head = root
			end
			entitylib.EntityThreads[char] = nil
			if not hum or not root then return end
			if plr and not plr.Parent then return end

			local entity = {
				Connections = {},
				Character = char,
				Health = readHealth(char),
				Head = head,
				Humanoid = hum,
				HumanoidRootPart = root,
				HipHeight = hum.HipHeight + (root.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
				Jumps = 0,
				JumpTick = tick(),
				Jumping = false,
				LandTick = tick(),
				MaxHealth = char:GetAttribute('MaxHealth') or 100,
				NPC = plr == nil,
				Player = plr,
				RootPart = root,
				TeamCheck = teamfunc
			}
			local conns = entity.Connections

			if plr == lplr then
				entity.AirTime = tick()
				entitylib.character = entity
				entitylib.isAlive = true
				entitylib.Events.LocalAdded:Fire(entity)
				table.insert(conns, char.AttributeChanged:Connect(function(attr)
					vapeEvents.AttributeChanged:Fire(attr)
				end))
			else
				if entitylib.getEntity(char) then return end
				local stale = plr and entitylib.getEntity(plr)
				if stale then
					entitylib.removeEntity(stale.Character)
				end

				entity.Targetable = entitylib.targetCheck(entity)
				if not plr then
					table.insert(conns, char:GetAttributeChangedSignal('Team'):Connect(function()
						entity.Targetable = entitylib.targetCheck(entity)
						entitylib.Events.EntityUpdated:Fire(entity)
					end))
				end

				for _, signal in entitylib.getUpdateConnections(entity) do
					table.insert(conns, signal:Connect(function()
						entity.Health = readHealth(char)
						entity.MaxHealth = char:GetAttribute('MaxHealth') or 100
						entitylib.Events.EntityUpdated:Fire(entity)
					end))
				end

				if plr then
					trackPlayer(entity, char, plr, hum, conns)
				end
				table.insert(entitylib.List, entity)
				entitylib.Events.EntityAdded:Fire(entity)
			end

			table.insert(conns, char.ChildRemoved:Connect(function(part)
				if part == root or part == hum or part == head then
					if part == root and hum.RootPart then
						root = hum.RootPart
						entity.RootPart = root
						entity.HumanoidRootPart = root
						return
					end
					entitylib.removeEntity(char, plr == lplr)
				end
			end))
		end)
	end

	entitylib.getUpdateConnections = function(ent)
		local char = ent.Character
		ent.Friend = ent.Player and isFriend(ent.Player) or nil
		ent.Target = ent.Player and isTarget(ent.Player) or nil

		local list = {
			char:GetAttributeChangedSignal('Health'),
			char:GetAttributeChangedSignal('MaxHealth'),
			{
				Connect = function(_, func)
					return char.AttributeChanged:Connect(function(attr)
						if attr == 'BlockKickerKit_BlockCount' or attr:find('Shield') then
							func()
						end
					end)
				end
			}
		}
		if ent.Player then
			table.insert(list, ent.Player:GetAttributeChangedSignal('PlayingAsKit'))
			table.insert(list, ent.Player:GetAttributeChangedSignal('PlayingAsKits'))
			table.insert(list, ent.Player:GetAttributeChangedSignal('VoidKnightTier'))
		end
		return list
	end

	entitylib.targetCheck = function(ent)
		local char = ent.Character
		if char and char:HasTag('petrified-player') then return false end
		if ent.TeamCheck then
			return ent:TeamCheck()
		end
		if ent.NPC then
			local npcTeam = char and char:GetAttribute('Team')
			return not npcTeam or lplr:GetAttribute('Team') ~= npcTeam
		end
		if isFriend(ent.Player) then return false end
		return lplr:GetAttribute('Team') ~= ent.Player:GetAttribute('Team')
	end

	vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))
end)
entitylib.start()

run(function()
	local KnitInit, Knit
	repeat
		KnitInit, Knit = pcall(function()
			return debug.getupvalue(require(lplr.PlayerScripts.TS.knit).setup, 9)
		end)
		if not KnitInit then
			task.wait()
		end
	until KnitInit
	while not debug.getupvalue(Knit.Start, 1) do
		task.wait()
	end

	local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
	local InventoryUtil = require(replicatedStorage.TS.inventory['inventory-util']).InventoryUtil
	local Client = require(replicatedStorage.TS.remotes).default.Client
	local OldGet = Client.Get

	local loaders = {
		RankMeta = function() return require(replicatedStorage.TS.rank['rank-meta']).RankMeta end,
		BalanceFile = function() return require(replicatedStorage.TS.balance["balance-file"]).BalanceFile end,
		ClientSyncEvents = function() return require(lplr.PlayerScripts.TS['client-sync-events']).ClientSyncEvents end,
		SyncEventPriority = function() return require(replicatedStorage.rbxts_include.node_modules['@easy-games']['sync-event'].out) end,
		AbilityId = function() return require(replicatedStorage.TS.ability['ability-id']).AbilityId end,
		IdUtil = function() return require(replicatedStorage.TS.util['id-util']).IdUtil end,
		BlockSelector = function() return require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out.client.select["block-selector"]).BlockSelector end,
		KnockbackUtilInstance = function() return replicatedStorage.TS.damage['knockback-util'] end,
		BedwarsKitSkin = function() return require(replicatedStorage.TS.games.bedwars['kit-skin']['bedwars-kit-skin-meta']).BedwarsKitSkinMeta end,
		KitController = function() return Knit.Controllers.KitController end,
		FishermanUtil = function() return require(replicatedStorage.TS.games.bedwars.kit.kits.fisherman['fisherman-util']).FishermanUtil end,
		FishMeta = function() return require(replicatedStorage.TS.games.bedwars.kit.kits.fisherman['fish-meta']) end,
		MatchHistoryApp = function() return require(lplr.PlayerScripts.TS.controllers.global["match-history"].ui["match-history-moderation-app"]).MatchHistoryModerationApp end,
		BlockSelectorMode = function() return require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out.client.select["block-selector"]).BlockSelectorMode end,
		EntityUtil = function() return require(game:GetService("ReplicatedStorage").TS.entity["entity-util"]).EntityUtil end,
		GamePlayer = function() return require(replicatedStorage.TS.player['game-player']) end,
		OfflinePlayerUtil = function() return require(replicatedStorage.TS.player['offline-player-util']) end,
		PlayerUtil = function() return require(replicatedStorage.TS.player['player-util']) end,
		KKKnitController = function() return require(lplr.PlayerScripts.TS.lib.knit['knit-controller']) end,
		AbilityController = function() return Flamework.resolveDependency('@easy-games/game-core:client/controllers/ability/ability-controller@AbilityController') end,
		CooldownController = function() return Flamework.resolveDependency("@easy-games/game-core:client/controllers/cooldown/cooldown-controller@CooldownController") end,
		CooldownIDS = function() return require(replicatedStorage.TS.cooldown["cooldown-id"]).CooldownId end,
		AnimationType = function() return require(replicatedStorage.TS.animation['animation-type']).AnimationType end,
		AnimationUtil = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out['shared'].util['animation-util']).AnimationUtil end,
		AppController = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.controllers['app-controller']).AppController end,
		BedBreakEffectMeta = function() return require(replicatedStorage.TS.locker['bed-break-effect']['bed-break-effect-meta']).BedBreakEffectMeta end,
		BedwarsKitMeta = function() return require(replicatedStorage.TS.games.bedwars.kit['bedwars-kit-meta']).BedwarsKitMeta end,
		BlockBreaker = function() return Knit.Controllers.BlockBreakController.blockBreaker end,
		BlockController = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out).BlockEngine end,
		BlockEngine = function() return require(lplr.PlayerScripts.TS.lib['block-engine']['client-block-engine']).ClientBlockEngine end,
		BlockPlacer = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.client.placement['block-placer']).BlockPlacer end,
		BowConstantsTable = function() return (Knit.Controllers.ProjectileController and Knit.Controllers.ProjectileController.enableBeam) and debug.getupvalue(Knit.Controllers.ProjectileController.enableBeam, 5) or {} end,
		ClickHold = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.ui.lib.util['click-hold']).ClickHold end,
		ClientConstructor = function() return require(replicatedStorage['rbxts_include']['node_modules']['@rbxts'].net.out.client) end,
		ClientDamageBlock = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.shared.remotes).BlockEngineRemotes.Client end,
		CombatConstant = function() return require(replicatedStorage.TS.combat['combat-constant']).CombatConstant end,
		SharedConstants = function() return require(replicatedStorage.TS['shared-constants']).CpsConstants end,
		DamageIndicator = function() return Knit.Controllers.DamageIndicatorController.spawnDamageIndicator end,
		DefaultKillEffect = function() return require(lplr.PlayerScripts.TS.controllers.global.locker['kill-effect'].effects['default-kill-effect']) end,
		EmoteType = function() return require(replicatedStorage.TS.locker.emote['emote-type']).EmoteType end,
		EmoteMeta = function() return require(replicatedStorage.TS.locker.emote['emote-meta']).EmoteMeta end,
		GameAnimationUtil = function() return require(replicatedStorage.TS.animation['animation-util']).GameAnimationUtil end,
		NotificationController = function() return Flamework.resolveDependency('@easy-games/game-core:client/controllers/notification-controller@NotificationController') end,
		MatchHistoryController = function() return require(lplr.PlayerScripts.TS.controllers.global['match-history']['match-history-controller']) end,
		PlayerProfileUIController = function() return require(lplr.PlayerScripts.TS.controllers.global['player-profile']['player-profile-ui-controller']) end,
		HudAliveCount = function() return require(lplr.PlayerScripts.TS.controllers.global['top-bar'].ui.game['hud-alive-player-counts']).HudAlivePlayerCounts end,
		KillEffectMeta = function() return require(replicatedStorage.TS.locker['kill-effect']['kill-effect-meta']).KillEffectMeta end,
		KillFeedController = function() return Flamework.resolveDependency('client/controllers/game/kill-feed/kill-feed-controller@KillFeedController') end,
		KnockbackUtil = function() return require(replicatedStorage.TS.damage['knockback-util']).KnockbackUtil end,
		MageKitUtil = function() return require(replicatedStorage.TS.games.bedwars.kit.kits.mage['mage-kit-util']).MageKitUtil end,
		NametagController = function() return Knit.Controllers.NametagController end,
		PartyController = function() return Flamework.resolveDependency("@easy-games/lobby:client/controllers/party-controller@PartyController") end,
		ProjectileMeta = function() return require(replicatedStorage.TS.projectile['projectile-meta']).ProjectileMeta end,
		QueryUtil = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).GameQueryUtil end,
		QueueCard = function() return require(lplr.PlayerScripts.TS.controllers.global.queue.ui['queue-card']).QueueCard end,
		QueueMeta = function() return require(replicatedStorage.TS.game['queue-meta']).QueueMeta end,
		Roact = function() return require(replicatedStorage['rbxts_include']['node_modules']['@rbxts']['roact'].src) end,
		RuntimeLib = function() return require(replicatedStorage['rbxts_include'].RuntimeLib) end,
		SoundList = function() return require(replicatedStorage.TS.sound['game-sound']).GameSound end,
		SoundManager = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).SoundManager end,
		Store = function() return require(lplr.PlayerScripts.TS.ui.store).ClientStore end,
		TeamUpgradeMeta = function() return debug.getupvalue(require(replicatedStorage.TS.games.bedwars['team-upgrade']['team-upgrade-meta']).getTeamUpgradeMetaForQueue, 2) or {} end,
		UILayers = function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).UILayers end,
		VisualizerUtils = function() return require(lplr.PlayerScripts.TS.lib.visualizer['visualizer-utils']).VisualizerUtils end,
		WeldTable = function() return require(replicatedStorage.TS.util['weld-util']).WeldUtil end,
		WinEffectMeta = function() return require(replicatedStorage.TS.locker['win-effect']['win-effect-meta']).WinEffectMeta end,
		ZapNetworking = function() return require(lplr.PlayerScripts.TS.lib.network) end,
		ItemMeta = function()
			local fn = require(replicatedStorage.TS.item['item-meta']).getItemMeta
			for i = 1, 6 do
				local v = debug.getupvalue(fn, i)
				if type(v) == 'table' and next(v) then return v end
			end
		end,
	}

	local loaded = {}
	for name, loader in loaders do
		local ok, res = pcall(loader)
		if ok then
			loaded[name] = res
		else
			warn('[aerov4] bedwars.' .. name .. ' failed to load: ' .. tostring(res))
		end
	end
	loaded.ItemMeta = loaded.ItemMeta or {}
	loaded.BowConstantsTable = loaded.BowConstantsTable or {}
	loaded.TeamUpgradeMeta = loaded.TeamUpgradeMeta or {}
	loaded.Client = Client
	loaded.Knit = Knit
	loaded.getIcon = function(item, showinv)
		local itemmeta = bedwars.ItemMeta[item.itemType]
		return itemmeta and showinv and itemmeta.image or ''
	end
	loaded.getInventory = function(plr)
		local suc, res = pcall(InventoryUtil.getInventory, plr)
		return suc and res or {
			items = {},
			armor = {}
		}
	end

	bedwars = setmetatable(loaded, {
		__index = function(self, ind)
			rawset(self, ind, Knit.Controllers[ind])
			return rawget(self, ind)
		end
	})
	getgenv().bedwars = bedwars

	prediction.Raycast = function(origin, direction, params)
		return bedwars.QueryUtil:raycast(origin, direction, params)
	end

	local function combatActive()
		local modules = vape.Modules
		if not modules then return false end
		for _, name in {'Killaura', 'SilentAim', 'ProjectileAimbot', 'AimAssist'} do
			local mod = modules[name]
			if mod and mod.Enabled then
				return true
			end
		end
		return false
	end

	local function observeEntities()
		if not entitylib.isAlive then return end
		local here = entitylib.character.RootPart.Position
		for _, v in entitylib.List do
			local root = v.RootPart
			if root and root.Parent and v.Targetable then
				local vel = root.AssemblyLinearVelocity
				local air = (v.Humanoid and v.Humanoid.FloorMaterial == Enum.Material.Air) or math.abs(vel.Y) > 2
				pcall(prediction.Observe, root, root.Position, vel, air, workspace.Gravity, here, v.HipHeight, v.Jumping and 42.6 or nil)
			end
		end
	end

	task.spawn(function()
		repeat
			pcall(observeEntities)
			task.wait(combatActive() and 0.025 or 0.15)
		until vape.Loaded == nil
	end)

	store.ping = store.ping or {total = 0.1, raw = 0.1}
	local statsService = cloneref(game:GetService('Stats'))
	local function readPing()
		local ok, ping = pcall(lplr.GetNetworkPing, lplr)
		if ok and type(ping) == 'number' and ping >= 0 then
			return ping
		end
		local ok2, dataPing = pcall(function()
			return statsService.Network.ServerStatsItem['Data Ping']:GetValue()
		end)
		if ok2 and type(dataPing) == 'number' and dataPing > 0 then
			return dataPing / 2000
		end
		return nil
	end
	task.spawn(function()
		repeat
			local ping = readPing()
			if ping then
				ping = math.clamp(ping, 0.005, 1)
				store.ping.raw = ping
				store.ping.total = store.ping.total * 0.7 + ping * 0.3
			end
			task.wait(0.5)
		until vape.Loaded == nil
	end)

	vape:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
		local character = damageTable.entityInstance
		if typeof(character) ~= 'Instance' then return end
		local root = character:IsA('Model') and character.PrimaryPart or character:IsA('BasePart') and character or nil
		local multiplier = damageTable.knockbackMultiplier
		if not (multiplier and multiplier.disabled) then
			local impulse
			local from = damageTable.fromPosition
			if root and typeof(from) == 'Vector3' then
				pcall(function()
					local direction = bedwars.KnockbackUtil.getDirection(root.Position, from)
					if direction.Magnitude > 0 then
						impulse = bedwars.KnockbackUtil.calculateKnockbackVelocity(direction, 1, multiplier)
					end
				end)
			end
			pcall(prediction.markKnockback, character, multiplier, impulse)
		end
		local attacker = damageTable.fromEntity
		if root and damageTable.damageType ~= 0 and (attacker == lplr.Character or attacker == lplr) then
			pcall(prediction.reportHit, root)
		end
	end))

	local controllers = Knit.Controllers
	local remoteNames = {
		AfkStatus = function() return safeGetProto(controllers.AfkController.KnitStart, 1) end,
		AttackEntity = function() return controllers.SwordController.sendServerRequest end,
		BeePickup = function() return controllers.BeeNetController.trigger end,
		ConsumeItem = function() return safeGetProto(controllers.ConsumeController.onEnable, 1) end,
		ConsumeSoul = function() return controllers.GrimReaperController.consumeSoul end,
		DropItem = function() return controllers.ItemDropController.dropItemInHand end,
		EquipItem = function() return safeGetProto(require(replicatedStorage.TS.entity.entities['inventory-entity']).InventoryEntity.equipItem, 3) end,
		FireProjectile = function() return safeGetProto(controllers.ProjectileController.launchProjectileWithValues, 2) end,
		GuitarHeal = function() return controllers.GuitarController.performHeal end,
		PickupItem = function() return controllers.ItemDropController.checkForPickup end,
		SummonerClawAttack = function() return controllers.SummonerClawHandController.attack end,
		WarlockTarget = function() return safeGetProto(controllers.WarlockStaffController.KnitStart, 2) end
	}

	local preDumped = {
		AfkStatus = 'AfkInfo',
		GuitarHeal = 'PlayGuitar',
		PickupItem = 'PickupItemDrop',
		SummonerClawAttack = 'SummonerClawAttackRequest',
		EquipItem = 'SetInvItem',
		ActivateGravestone = 'ActivateGravestone',
		CollectCollectableEntity = 'CollectCollectableEntity',
		DefenderRequestPlaceBlock = 'DefenderRequestPlaceBlock',
		Harvest = 'CropHarvest',
		DepositCoins = 'DepositCoins',
		BedwarsPurchaseItem = 'BedwarsPurchaseItem',
		BedBreakEffectTriggered = 'BedBreakEffectTriggered',
		BloodAssassinSelectContract = 'BloodAssassinSelectContract',
		Mimic = 'MimicBlock',
		StyxPortal = 'UseStyxPortalFromClient',
		StyxExitPortal = 'StyxOpenExitPortalFromServer',
		StyxSpawnExitPortal = 'StyxSpawnExitPortalFromServer',
		StyxSpawnEntrancePortal = 'StyxSpawnEntrancePortalFromServer',
		TryOpenStyxPortalExit = 'StyxTryOpenExitPortalFromClient',
		TeleportToLobby = 'TeleportToLobby',
		FishCaught = 'FishCaught',
		BountyHunterTargetChanged = 'BountyHunterTargetChanged',
		SpawnRaven = 'SpawnRaven',
		PaladinAbilityRequest = 'PaladinAbilityRequest',
		OwlActionAbilities = 'OwlActionAbilities',
		DrillAttack = 'DrillAttack',
		UpgradeFrostyHammer = 'UpgradeFrostyHammer',
		UpgradeFlamethrower = 'UpgradeFlamethrower',
		TryBlockKick = 'TryBlockKick',
		Ranks = 'FetchRanks',
		ResearchEnchant = 'EnchantTableResearch',
		DropDroneItem = 'DropDroneItem',
		AttemptFireOasisProjectiles = 'AttemptFireOasisProjectiles',
		WinEffectTriggered = 'WinEffectTriggered',
		ExtractFromDrill = 'ExtractFromDrill',
		HannahPromptTrigger = 'HannahPromptTrigger',
		DragonFlap = 'DragonFlap',
		DragonBreath = 'DragonBreath',
		LearnElementTome = 'LearnElementTome',
		RequestMoveSlime = 'RequestMoveSlime',
		SummonOwl = 'SummonOwl',
		RemoveOwl = 'RemoveOwl',
		OwlFireProjectile = 'OwlFireProjectile',
		OwlAiming = 'OwlAiming',
		MimicBlockPickPocketPlayer = 'MimicBlockPickPocketPlayer',
		DestroyPetrifiedPlayer = 'DestroyPetrifiedPlayer',
		FishFound = 'FishFound'
	}
	local knownFixes = {
		FireProjectile = 'ProjectileFire',
		AttackEntity = 'SwordHit'
	}

	local function dumpRemote(func)
		local ok, consts = pcall(debug.getconstants, func)
		if not ok or type(consts) ~= 'table' then return '' end
		local ind = table.find(consts, 'Client')
		local name = ind and consts[ind + 1]
		return type(name) == 'string' and name or ''
	end

	for name, value in preDumped do
		remotes[name] = value
	end
	for name, getter in remoteNames do
		local ok, value = pcall(getter)
		local remote = ''
		if ok and type(value) == 'string' then
			remote = value
		elseif ok and type(value) == 'function' then
			remote = dumpRemote(value)
		end
		remotes[name] = remote ~= '' and remote or preDumped[name] or ''
	end

	local net = getNetManaged(false)
	if net then
		if net:FindFirstChild('SwordHit') then
			remotes.AttackEntity = 'SwordHit'
		end
		for name, value in remotes do
			if value == '' or not net:FindFirstChild(value) then
				local fix = knownFixes[name] or preDumped[name]
				if fix and net:FindFirstChild(fix) then
					remotes[name] = fix
				end
			end
		end
	end
	getgenv().remotes = remotes
	task.spawn(function()
		while shared.vape == vape and not vape.Loaded do
			task.wait(0.1)
		end
		if shared.vape ~= vape then return end
		for name in remoteNames do
			if remotes[name] == '' then
				notif('aerov4', 'couldnt grab remote ' .. name:lower() .. ' so some stuff might not work rn', 10, 'alert')
			end
		end
	end)

	Client.Get = function(self, remoteName, ...)
		local call = OldGet(self, remoteName, ...)

		if remoteName == 'SwordHit' or remoteName == remotes.AttackEntity then
			return {
				instance = call.instance,
				SendToServer = function(_, attackTable, ...)
					if (store.KillauraTarget or tick() - (store.kaTargetAt or 0) < 0.2) and not store.kaSending then
						return
					end
					local validate = type(attackTable) == 'table' and attackTable.validate
					if validate and validate.selfPosition and validate.targetPosition then
						local selfpos = validate.selfPosition.value
						local targetpos = validate.targetPosition.value
						local dist = (selfpos - targetpos).Magnitude
						store.attackReach = (dist * 100) // 1 / 100
						store.attackReachUpdate = tick() + 1

						local serverReach = getReach(attackTable.weapon) - 0.001
						if (Reach.Enabled or HitBoxes.Enabled) and dist > serverReach then
							validate.raycast = validate.raycast or {}
							validate.selfPosition.value += CFrame.lookAt(selfpos, targetpos).LookVector * (dist - serverReach)
						end
					end
					return call:SendToServer(attackTable, ...)
				end
			}
		elseif remoteName == 'OwlAiming' then
			return {
				instance = call.instance,
				SendToServer = function(_, data, ...)
					store.owlAiming = type(data) == 'table' and data.starting == true
					return call:SendToServer(data, ...)
				end
			}
		elseif TrapDisabler and TrapDisabler.Enabled and (
			remoteName == 'StepOnSnapTrap' and TrapSnap.Enabled
			or remoteName == 'TriggerInvisibleLandmine' and TrapMine.Enabled
			or remoteName == 'StepOnTeleportBlock' and TrapTeleport.Enabled
			or remoteName == 'StepOnVoidPortal' and TrapPortal.Enabled
		) then
			return {instance = call.instance, SendToServer = function() end}
		end

		return call
	end

	local blockhealthbar = {blockHealth = -1, breakingBlockPosition = Vector3.zero}
	pcall(function()
		store.blockPlacer = bedwars.BlockPlacer.new(bedwars.BlockEngine, 'wool_white')
	end)
	local function getBlockHealth(block, blockpos)
		local blockdata = bedwars.BlockController:getStore():getBlockData(blockpos)
		local health = blockdata and (blockdata:GetAttribute('1') or blockdata:GetAttribute('Health'))

		if health == nil then
			health = block:GetAttribute('Health')
		end

		if health ~= nil then
			return health
		end

		local meta = bedwars.ItemMeta[block.Name]
		return (meta and meta.block and meta.block.health) or 10
	end

	local function getBreakType(block)
		if not block then return nil end
		if block.Name == 'gumdrop_bounce_pad' then return 'stone' end
		local meta = bedwars.ItemMeta[block.Name]
		return meta and meta.block and meta.block.breakType
	end

	local function getBlockHits(block, blockpos)
		if not block then return 0 end
		local breaktype = getBreakType(block)
		local tool = breaktype and store.tools[breaktype]
		local toolMeta = tool and bedwars.ItemMeta[tool.itemType]
		local dmg = (toolMeta and toolMeta.breakBlock and toolMeta.breakBlock[breaktype]) or 2
		local health = getBlockHealth(block, bedwars.BlockController:getBlockPosition(blockpos)) or 10
		return health / dmg
	end

	local PLAN_FACES = {Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(0, 3, 0), Vector3.new(0, -3, 0), Vector3.new(0, 0, 3), Vector3.new(0, 0, -3)}

	local function planHeapPush(heap, node)
		local i = #heap + 1
		heap[i] = node
		while i > 1 do
			local parent = i // 2
			if heap[parent][1] <= node[1] then break end
			heap[i], heap[parent] = heap[parent], node
			i = parent
		end
	end

	local function planHeapPop(heap)
		local top = heap[1]
		local last = table.remove(heap)
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local child = i * 2
				if child > #heap then break end
				if child < #heap and heap[child + 1][1] < heap[child][1] then
					child += 1
				end
				if heap[i][1] <= heap[child][1] then break end
				heap[i], heap[child] = heap[child], heap[i]
				i = child
			end
		end
		return top
	end

	local function planCells(target)
		local out = {}
		local ok, handler = pcall(function()
			return bedwars.BlockController:getHandlerRegistry():getHandler(target.Name)
		end)
		if ok and handler then
			local ok2, list = pcall(function()
				return handler:getContainedPositions(target)
			end)
			if ok2 and list then
				for _, v in list do
					table.insert(out, v * 3)
				end
			end
		end
		if #out == 0 then
			table.insert(out, bedwars.BlockController:getBlockPosition(target.Position) * 3)
		end
		return out
	end

	local function planBreakRoute(target, opts)
		opts = opts or {}
		local root = entitylib.character and entitylib.character.RootPart
		if not root or not target then return nil end
		local origin = opts.origin or root.Position
		local anchor = opts.anchor or origin
		local nearFirst = opts.nearFirst
		local filter = opts.filter
		local angle = opts.angle or 360
		local cells = opts.cells or planCells(target)
		local targetCells = {}
		for _, cell in cells do
			targetCells[cell] = true
		end

		local airMemo = {}
		local function openAir(cell)
			local known = airMemo[cell]
			if known ~= nil then return known end
			local seen, queue, head, open = {[cell] = true}, {cell}, 1, false
			while queue[head] do
				local cur = queue[head]
				head += 1
				if airMemo[cur] ~= nil then
					open = airMemo[cur]
					break
				end
				if (cur - cell).Magnitude > 15 or head > 250 then
					open = true
					break
				end
				for _, f in PLAN_FACES do
					local nxt = cur + f
					if not seen[nxt] and not getPlacedBlock(nxt) then
						seen[nxt] = true
						table.insert(queue, nxt)
					end
				end
			end
			for c in seen do
				airMemo[c] = open
			end
			return open
		end
		local function exposed(cell)
			for _, f in PLAN_FACES do
				local nxt = cell + f
				if not targetCells[nxt] and not getPlacedBlock(nxt) and openAir(nxt) then
					return true
				end
			end
			return false
		end
		local hitMemo = {}
		local function hits(blk, cell)
			local known = hitMemo[cell]
			if known then return known end
			known = math.max(math.ceil(getBlockHits(blk, cell)), 1)
			hitMemo[cell] = known
			return known
		end

		local direct, directDist
		for _, cell in cells do
			local d = (cell - anchor).Magnitude
			if (cell - origin).Magnitude <= 30 and exposed(cell) and (not direct or d < directDist) then
				direct, directDist = cell, d
			end
		end
		if direct then
			return {direct}, 0
		end

		local camFlat = gameCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
		local useAngle = angle < 360 and camFlat.Magnitude > 0.01
		local halfAngle = math.rad(angle) / 2
		local function passable(blk, cell)
			if (cell - origin).Magnitude > 30 or blk:GetAttribute('NoBreak') then
				return false
			end
			if filter then
				local ok, allowed = pcall(filter, blk)
				if not ok or not allowed then
					return false
				end
			end
			if useAngle then
				local flat = (cell - origin) * Vector3.new(1, 0, 1)
				if flat.Magnitude > 0.01 and math.acos(math.clamp(camFlat.Unit:Dot(flat.Unit), -1, 1)) > halfAngle then
					return false
				end
			end
			return true
		end

		if nearFirst then
			local function bound(index, component, delta)
				if delta == 0 then
					return 0, math.huge, math.huge
				end
				local step = delta > 0 and 1 or -1
				return step, (((index + step * 0.5) * 3) - component) / delta, 3 / math.abs(delta)
			end
			local function traceLine(from, aim)
				local start = bedwars.BlockController:getBlockPosition(from)
				local dir = aim - from
				local x, y, z = start.X, start.Y, start.Z
				local sx, nx, dx = bound(x, from.X, dir.X)
				local sy, ny, dy = bound(y, from.Y, dir.Y)
				local sz, nz, dz = bound(z, from.Z, dir.Z)
				local route, cost = {}, 0
				for _ = 1, 120 do
					local cell = Vector3.new(x, y, z) * 3
					if targetCells[cell] then
						table.insert(route, cell)
						return route, cost
					end
					local blk = getPlacedBlock(cell)
					if blk then
						if blk == target then
							table.insert(route, cell)
							return route, cost
						end
						if not passable(blk, cell) then
							return nil
						end
						cost += hits(blk, cell)
						table.insert(route, cell)
					end
					if nx > 1 and ny > 1 and nz > 1 then
						return nil
					end
					if nx <= ny and nx <= nz then
						x, nx = x + sx, nx + dx
					elseif ny <= nz then
						y, ny = y + sy, ny + dy
					else
						z, nz = z + sz, nz + dz
					end
				end
				return nil
			end
			local eyes = {origin}
			local head = lplr.Character and lplr.Character:FindFirstChild('Head')
			if head then
				table.insert(eyes, head.Position)
			end
			table.insert(eyes, gameCamera.CFrame.Position)
			local bestRoute, bestCost, bestDist
			for _, eye in eyes do
				for _, cell in cells do
					for ox = -1, 1 do
						for oy = -1, 1 do
							for oz = -1, 1 do
								local route, cost = traceLine(eye, cell + Vector3.new(ox, oy, oz) * 1.35)
								if route and route[1] then
									local d = (route[1] - anchor).Magnitude
									if (route[1] - origin).Magnitude <= 30 and (not bestCost or cost < bestCost or (cost == bestCost and d < bestDist)) then
										bestRoute, bestCost, bestDist = route, cost, d
									end
								end
							end
						end
					end
				end
			end
			if bestRoute then
				return bestRoute, bestCost
			end
		end

		local dist, prev, visited, heap = {}, {}, {}, {}
		for _, cell in cells do
			dist[cell] = 0
			planHeapPush(heap, {0, cell})
		end
		local bestEntry, bestScore, bestCost
		local steps = 0
		while #heap > 0 and steps < 6000 do
			steps += 1
			local node = planHeapPop(heap)
			local d, cell = node[1], node[2]
			if visited[cell] then continue end
			visited[cell] = true
			if not nearFirst and bestScore and d >= bestScore then break end
			if not targetCells[cell] and getPlacedBlock(cell) and exposed(cell) then
				local near = (cell - anchor).Magnitude
				local score = nearFirst and (near + d * 0.25) or (d + near * 0.01)
				if not bestScore or score < bestScore then
					bestEntry, bestScore, bestCost = cell, score, d
				end
			end
			for _, f in PLAN_FACES do
				local nxt = cell + f
				if visited[nxt] or targetCells[nxt] then continue end
				local blk = getPlacedBlock(nxt)
				local step
				if blk then
					if blk == target or not passable(blk, nxt) then continue end
					step = hits(blk, nxt)
				else
					if openAir(nxt) then continue end
					step = 0
				end
				local nd = d + step
				if nd < (dist[nxt] or math.huge) then
					dist[nxt], prev[nxt] = nd, cell
					planHeapPush(heap, {nd, nxt})
				end
			end
		end
		if not bestEntry then
			return nil
		end
		local route, cur, guard = {}, bestEntry, 0
		while cur and guard < 128 do
			table.insert(route, cur)
			if targetCells[cur] then break end
			cur = prev[cur]
			guard += 1
		end
		return route, bestCost
	end
	bedwars.planBreakRoute = planBreakRoute

	local function calculatePath(target, blockpos, angle, anchor, weight, blockFilter)
		local route, cost = planBreakRoute(target, {
			cells = {blockpos},
			angle = angle,
			anchor = anchor,
			nearFirst = anchor ~= nil and (not weight or weight >= 1),
			filter = blockFilter
		})
		if not route then return end
		local path = {}
		for i = 1, #route - 1 do
			path[route[i]] = route[i + 1]
		end
		return route[1], cost, path
	end
	bedwars.calculatePath = calculatePath

	bedwars.placeBlock = function(pos, item)
		if store.blockPlacer and getItem(item) then
			store.blockPlacer.blockType = item
			local ok, result = pcall(function()
				return store.blockPlacer:placeBlock(bedwars.BlockController:getBlockPosition(pos))
			end)
			if ok then return result end
		end
	end

	local function playBreakAnimation()
		local animation
		pcall(function()
			animation = bedwars.AnimationUtil:playAnimation(lplr, bedwars.BlockController:getAnimationController():getAssetId(1))
		end)
		pcall(function()
			bedwars.ViewmodelController:playAnimation(15)
		end)
		task.wait(0.3)
		if animation then
			pcall(function()
				animation:Stop()
				animation:Destroy()
			end)
		end
	end

	bedwars.breakBlock = function(block, effects, anim, customHealthbar, visualise, angle, anchor, weight, blockFilter, lockedTarget)
		if lplr:GetAttribute('DenyBlockBreak') or not entitylib.isAlive then return end
		local handler = bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
		local cost, pos, target, mag, path = math.huge, nil, nil, 9e9, nil
		local playerPos = entitylib.character.RootPart.Position

		for _, v in (handler and handler:getContainedPositions(block) or {block.Position / 3}) do
			local worldTarget = v * 3
			if lockedTarget and (worldTarget - lockedTarget).Magnitude > 0.1 then
				continue
			end
			local dpos, dcost, dpath = calculatePath(block, worldTarget, angle or 360, anchor, weight, blockFilter)
			local dmag = dpos and (playerPos - dpos).Magnitude or 9e9
			if dpos and (dcost < cost or (dcost == cost and dmag < mag)) then
				cost, pos, target, path, mag = dcost, dpos, worldTarget, dpath, dmag
			end
		end

		if not pos then return end
		if (entitylib.character.RootPart.Position - pos).Magnitude > 30 then return end
		local dblock, dpos = getPlacedBlock(pos)
		if not dblock and target then
			dblock, dpos = getPlacedBlock(target)
		end
		if not dblock then
			dblock, dpos = block, bedwars.BlockController:getBlockPosition(block.Position)
		end
		if not dblock or not dpos then return end

		if blockFilter then
			local ok, allowed = pcall(blockFilter, dblock)
			if not ok or not allowed then return end
		end

		local hitType = store.hand and store.hand.tool and store.hand.tool.Name
		if (workspace:GetServerTimeNow() - (bedwars.SwordController.lastAttack or 0)) > 0.4 then
			local breaktype = getBreakType(dblock)
			local tool = breaktype and store.tools[breaktype]
			local handMeta = hitType and bedwars.ItemMeta[hitType]
			if tool and visualise and handMeta and handMeta.breakBlock then
				local hotbar = store.inventory and store.inventory.hotbar or {}
				for i, v in hotbar do
					if v.item and v.item.itemType == tool.itemType then
						hotbarSwitch(i - 1)
						hitType = tool.itemType
						break
					end
				end
			end
		end

		if blockhealthbar.blockHealth == -1 or dpos ~= blockhealthbar.breakingBlockPosition then
			blockhealthbar.blockHealth = getBlockHealth(dblock, dpos) or 0
			blockhealthbar.breakingBlockPosition = dpos
		end

		if anim and (tick() - (store.lastBreakerAnimation or 0)) >= 0.18 then
			store.lastBreakerAnimation = tick()
			task.spawn(playBreakAnimation)
		end

		bedwars.ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
			blockRef = {blockPosition = dpos},
			hitPosition = pos,
			hitNormal = Vector3.FromNormalId(Enum.NormalId.Top)
		}):andThen(function(result)
			if result == 'cancelled' or not effects then return end
			local hmeta = hitType and bedwars.ItemMeta[hitType]
			local btype = getBreakType(dblock)
			local hitdmg = (hmeta and hmeta.breakBlock and btype and hmeta.breakBlock[btype]) or 2
			local predicted = math.max(blockhealthbar.blockHealth - hitdmg, 1)
			local nowHealth = result == 'destroyed' and 0 or math.min(getBlockHealth(dblock, dpos) or predicted, predicted)
			local blockdmg = math.max(blockhealthbar.blockHealth - nowHealth, 0)
			local dmeta = bedwars.ItemMeta[dblock.Name]
			local maxHealth = dblock:GetAttribute('MaxHealth') or (dmeta and dmeta.block and dmeta.block.health) or math.max(blockhealthbar.blockHealth, 1)
			pcall(customHealthbar or bedwars.BlockBreaker.updateHealthbar, bedwars.BlockBreaker, {blockPosition = dpos}, blockhealthbar.blockHealth, maxHealth, blockdmg, dblock)
			blockhealthbar.blockHealth = math.max(blockhealthbar.blockHealth - blockdmg, 0)
			pcall(function()
				if blockhealthbar.blockHealth <= 0 then
					bedwars.BlockBreaker.breakEffect:playBreak(dblock.Name, dpos, lplr)
					blockhealthbar.breakingBlockPosition = Vector3.zero
					blockhealthbar.blockHealth = -1
					if bedwars.BlockBreaker.healthbarMaid then
						bedwars.BlockBreaker.healthbarMaid:DoCleaning()
					end
				else
					bedwars.BlockBreaker.breakEffect:playHit(dblock.Name, dpos, lplr)
				end
			end)
		end)

		return pos, path, target
	end

	local toolTypes = {'stone', 'wood', 'wool'}
	local function refreshTools()
		store.lastToolUpdate = tick()
		for _, v in toolTypes do
			store.tools[v] = getTool(v)
		end
	end

	local function updateStore(new, old)
		if new.Bedwars ~= old.Bedwars and new.Bedwars then
			store.equippedKit = new.Bedwars.kit ~= 'none' and new.Bedwars.kit or ''
		end
		if new.Game ~= old.Game and new.Game then
			store.matchState = new.Game.matchState
			store.queueType = new.Game.queueType or 'bedwars_test'
		end
		if new.Inventory == old.Inventory then return end

		local newinv = new.Inventory and new.Inventory.observedInventory or {inventory = {}}
		local oldinv = old.Inventory and old.Inventory.observedInventory or {inventory = {}}
		store.inventory = newinv
		if newinv ~= oldinv then
			fireInventoryChanged()
		end

		if newinv.inventory.items ~= oldinv.inventory.items then
			vapeEvents.InventoryAmountChanged:Fire()
			store.tools.sword = getSword()
			if tick() - (store.lastToolUpdate or 0) > 0.5 then
				refreshTools()
			elseif not store.toolUpdatePending then
				store.toolUpdatePending = true
				task.delay(0.5, function()
					store.toolUpdatePending = false
					refreshTools()
				end)
			end
		end

		if newinv.inventory.hand ~= oldinv.inventory.hand then
			store.tools.sword = getSword()
			refreshTools()
			local currentHand, toolType = newinv.inventory.hand, ''
			if currentHand then
				local handData = bedwars.ItemMeta[currentHand.itemType]
				if handData and handData.sword then
					toolType = 'sword'
				elseif handData and handData.block then
					toolType = 'block'
				elseif tostring(currentHand.itemType):find('bow') then
					toolType = 'bow'
				end
			end
			store.hand = {
				tool = currentHand and currentHand.tool,
				amount = currentHand and currentHand.amount or 0,
				toolType = toolType
			}
		end
	end

	local function safeUpdateStore(new, old)
		local ok, err = pcall(updateStore, new, old)
		if not ok then
			warn('[aerov4] store update failed: ' .. tostring(err))
		end
	end
	local storeChanged = bedwars.Store.changed:connect(safeUpdateStore)
	safeUpdateStore(bedwars.Store:getState(), {})

	for _, event in {'MatchEndEvent', 'BedwarsBedBreak', 'BalloonPopped', 'AngelProgress', 'GrapplingHookFunctions'} do
		bedwars.Client:WaitFor(event):andThen(function(connection)
			vape:Clean(connection:Connect(function(...)
				vapeEvents[event]:Fire(...)
			end))
		end):catch(function(err)
			warn('testing... ' .. event:lower() .. ': ' .. tostring(err))
		end)
	end

	vape:Clean(bedwars.ZapNetworking.EntityDamageEventZap.On(function(...)
		local args = table.pack(...)
		vapeEvents.EntityDamageEvent:Fire({
			entityInstance = args[1],
			damage = args[2],
			damageType = args[3],
			fromPosition = args[4],
			fromEntity = args[5],
			knockbackMultiplier = args[6],
			knockbackId = args[7],
			swingInfo = args[8],
			disableDamageHighlight = args[13]
		})
	end))

	pcall(function()
		local deathZap = bedwars.ZapNetworking and bedwars.ZapNetworking.EntityDeathEventZap
		if deathZap and deathZap.On then
			vape:Clean(deathZap.On(function(data)
				if type(data) == 'table' then
					vapeEvents.EntityDeathEvent:Fire(data)
				else
					local args = table.pack(data, select(2, data))
					vapeEvents.EntityDeathEvent:Fire({entityInstance = args[1], fromEntity = args[2], finalKill = args[3]})
				end
			end))
		end
	end)

	vape:Clean(playersService.PlayerRemoving:Connect(function(plr)
		store.inventories[plr] = nil
	end))

	for _, event in {'PlaceBlockEvent', 'BreakBlockEvent'} do
		vape:Clean(bedwars.ZapNetworking[event .. 'Zap'].On(function(...)
			vapeEvents[event]:Fire({blockRef = {blockPosition = (...)}, player = select(5, ...)})
		end))
	end

	store.blocks = collection('block', vape)
	store.shop = collection({'BedwarsItemShop', 'TeamUpgradeShopkeeper'}, vape, function(tab, obj)
		for _, entry in tab do
			if entry.RootPart == obj then
				entry.Id = obj.Name
				entry.Shop = obj:HasTag('BedwarsItemShop')
				entry.Upgrades = obj:HasTag('TeamUpgradeShopkeeper')
				return
			end
		end
		table.insert(tab, {
			Id = obj.Name,
			RootPart = obj,
			Shop = obj:HasTag('BedwarsItemShop'),
			Upgrades = obj:HasTag('TeamUpgradeShopkeeper')
		})
	end, function(tab, obj)
		local active = obj:IsDescendantOf(game)
		local shop = active and obj:HasTag('BedwarsItemShop')
		local upgrades = active and obj:HasTag('TeamUpgradeShopkeeper')
		for i = #tab, 1, -1 do
			local entry = tab[i]
			if entry.RootPart == obj then
				if shop or upgrades then
					entry.Shop = shop
					entry.Upgrades = upgrades
				else
					table.remove(tab, i)
				end
				break
			end
		end
	end)
	store.enchant = collection({'enchant-table', 'broken-enchant-table'}, vape, nil, function(tab, obj, tag)
		if obj:HasTag('enchant-table') and tag == 'broken-enchant-table' then return end
		local ind = table.find(tab, obj)
		if ind then
			table.remove(tab, ind)
		end
	end)

	local kills = sessioninfo:AddItem('Kills')
	local beds = sessioninfo:AddItem('Beds')
	local wins = sessioninfo:AddItem('Wins')
	local games = sessioninfo:AddItem('Games')

	local mapname = 'unknown'
	sessioninfo:AddItem('Map', 0, function()
		return mapname
	end, false)

	task.delay(1, function()
		games:Increment()
	end)

	task.spawn(function()
		repeat
			task.wait(0.25)
		until store.matchState ~= 0 or vape.Loaded == nil
		if vape.Loaded == nil then return end
		pcall(function()
			local map = workspace:WaitForChild('Map', 30)
			local worlds = map and map:WaitForChild('Worlds', 30)
			local world
			for _ = 1, 40 do
				world = worlds and worlds:GetChildren()[1]
				if world or vape.Loaded == nil then break end
				task.wait(0.25)
			end
			if world then
				mapname = string.gsub(string.split(world.Name, '_')[2] or world.Name, '-', '')
			end
		end)
	end)

	vape:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(bedTable)
		if bedTable.player and bedTable.player.UserId == lplr.UserId then
			beds:Increment()
		end
	end))

	vape:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(winTable)
		if (bedwars.Store:getState().Game.myTeam or {}).id == winTable.winningTeamId or lplr.Neutral then
			wins:Increment()
		end
	end))

	vape:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
		local killer = playersService:GetPlayerFromCharacter(deathTable.fromEntity)
		local killed = playersService:GetPlayerFromCharacter(deathTable.entityInstance)
		if killer == lplr and killed and killed ~= lplr then
			kills:Increment()
		end
	end))

	pcall(function()
		bedwars.Shop = require(replicatedStorage.TS.games.bedwars.shop['bedwars-shop']).BedwarsShop
		bedwars.ShopItems = bedwars.Shop.ShopItems
		bedwars.Shop.getShopItem('iron_sword', lplr)
		store.shopLoaded = true
	end)

	vape:Clean(function()
		Client.Get = OldGet
		pcall(function()
			storeChanged:disconnect()
		end)
		pcall(function()
			store.blockPlacer:disable()
		end)
		for _, v in vapeEvents do
			v:Destroy()
		end
		table.clear(vapeEvents)
		pcall(entitylib.stop)
		if store.blockPlacer then
			table.clear(store.blockPlacer)
		end
		table.clear(bedwars)
		table.clear(store)
		table.clear(remotes)
	end)
end)

for _, v in {'AntiRagdoll', 'TriggerBot','Gravity','SafeWalk','Arrows', 'Invisible', 'Phase', 'Spider', 'Spinbot', 'TargetStrafe', 'GamingChair', 'MotionBlur', 'Tracers', 'ChatSpammer', 'InfiniteJump', 'InfiniteZoom', 'Parkour','WaterAmbient', 'Xray', 'SilentAim', 'AutoRejoin', 'Rejoin', 'Disabler', 'Timer', 'ServerHop', 'MouseTP', 'MurderMystery', 'NameTags', 'Killaura', 'AimAssist', 'AutoClicker', 'Reach', 'AntiFall', 'Fly', 'HitBoxes', 'LongJump', 'Speed', 'Swim', 'PlayerModel', 'Search', 'Waypoints', 'Blink', 'StaffDetector'} do
	vape:Remove(v)
end


local moduleRuns = setmetatable({}, {__mode = 'k'})
local function newRun(module)
	local id = (moduleRuns[module] or 0) + 1
	moduleRuns[module] = id
	return function()
		return module.Enabled and moduleRuns[module] == id
	end
end

local kitImageIds = {
	['none'] = "rbxassetid://16493320215",
	["random"] = "rbxassetid://79773209697352",
	["cowgirl"] = "rbxassetid://9155462968",
	["davey"] = "rbxassetid://9155464612",
	["warlock"] = "rbxassetid://15186338366",
	["ember"] = "rbxassetid://9630017904",
	["black_market_trader"] = "rbxassetid://18922642482",
	["yeti"] = "rbxassetid://9166205917",
	["scarab"] = "rbxassetid://137137517627492",
	["defender"] = "rbxassetid://131690429591874",
	["cactus"] = "rbxassetid://104436517801089",
	["oasis"] = "rbxassetid://120283205213823",
	["berserker"] = "rbxassetid://90258047545241",
	["sword_shield"] = "rbxassetid://131690429591874",
	["airbender"] = "rbxassetid://74712750354593",
	["gun_blade"] = "rbxassetid://138231219644853",
	["frost_hammer_kit"] = "rbxassetid://11838567073",
	["spider_queen"] = "rbxassetid://95237509752482",
	["archer"] = "rbxassetid://9224796984",
	["axolotl"] = "rbxassetid://9155466713",
	["baker"] = "rbxassetid://9155463919",
	["barbarian"] = "rbxassetid://9166207628",
	["builder"] = "rbxassetid://9155463708",
	["necromancer"] = "rbxassetid://11343458097",
	["cyber"] = "rbxassetid://9507126891",
	["sorcerer"] = "rbxassetid://97940108361528",
	["bigman"] = "rbxassetid://9155467211",
	["spirit_assassin"] = "rbxassetid://10406002412",
	["farmer_cletus"] = "rbxassetid://9155466936",
	["ice_queen"] = "rbxassetid://9155466204",
	["grim_reaper"] = "rbxassetid://9155467410",
	["spirit_gardener"] = "rbxassetid://132108376114488",
	["hannah"] = "rbxassetid://10726577232",
	["shielder"] = "rbxassetid://9155464114",
	["summoner"] = "rbxassetid://18922378956",
	["glacial_skater"] = "rbxassetid://84628060516931",
	["dragon_sword"] = "rbxassetid://16215630104",
	["lumen"] = "rbxassetid://9630018371",
	["flower_bee"] = "rbxassetid://101569742252812",
	["jellyfish"] = "rbxassetid://18129974852",
	["melody"] = "rbxassetid://9155464915",
	["mimic"] = "rbxassetid://14783283296",
	["miner"] = "rbxassetid://9166208461",
	["nazar"] = "rbxassetid://18926951849",
	["seahorse"] = "rbxassetid://11902552560",
	["elk_master"] = "rbxassetid://15714972287",
	["rebellion_leader"] = "rbxassetid://18926409564",
	["void_hunter"] = "rbxassetid://122370766273698",
	["taliyah"] = "rbxassetid://13989437601",
	["angel"] = "rbxassetid://9166208240",
	["harpoon"] = "rbxassetid://18250634847",
	["void_walker"] = "rbxassetid://78915127961078",
	["spirit_summoner"] = "rbxassetid://95760990786863",
	["triple_shot"] = "rbxassetid://9166208149",
	["void_knight"] = "rbxassetid://73636326782144",
	["regent"] = "rbxassetid://9166208904",
	["vulcan"] = "rbxassetid://9155465543",
	["owl"] = "rbxassetid://12509401147",
	["dasher"] = "rbxassetid://9155467645",
	["disruptor"] = "rbxassetid://11596993583",
	["wizard"] = "rbxassetid://13353923546",
	["aery"] = "rbxassetid://9155463221",
	["agni"] = "rbxassetid://17024640133",
	["alchemist"] = "rbxassetid://9155462512",
	["spearman"] = "rbxassetid://9166207341",
	["beekeeper"] = "rbxassetid://9312831285",
	["falconer"] = "rbxassetid://17022941869",
	["bounty_hunter"] = "rbxassetid://9166208649",
	["blood_assassin"] = "rbxassetid://12520290159",
	["battery"] = "rbxassetid://10159166528",
	["steam_engineer"] = "rbxassetid://15380413567",
	["vesta"] = "rbxassetid://9568930198",
	["beast"] = "rbxassetid://9155465124",
	["dino_tamer"] = "rbxassetid://9872357009",
	["drill"] = "rbxassetid://12955100280",
	["elektra"] = "rbxassetid://13841413050",
	["fisherman"] = "rbxassetid://9166208359",
	["queen_bee"] = "rbxassetid://12671498918",
	["card"] = "rbxassetid://13841410580",
	["frosty"] = "rbxassetid://9166208762",
	["gingerbread_man"] = "rbxassetid://9155464364",
	["ghost_catcher"] = "rbxassetid://9224802656",
	["tinker"] = "rbxassetid://17025762404",
	["ignis"] = "rbxassetid://13835258938",
	["oil_man"] = "rbxassetid://9166206259",
	["jade"] = "rbxassetid://9166306816",
	["dragon_slayer"] = "rbxassetid://10982192175",
	["paladin"] = "rbxassetid://11202785737",
	["pinata"] = "rbxassetid://10011261147",
	["merchant"] = "rbxassetid://9872356790",
	["metal_detector"] = "rbxassetid://9378298061",
	["slime_tamer"] = "rbxassetid://15379766168",
	["nyoka"] = "rbxassetid://17022941410",
	["midnight"] = "rbxassetid://9155462763",
	["pyro"] = "rbxassetid://9155464770",
	["raven"] = "rbxassetid://9166206554",
	["santa"] = "rbxassetid://9166206101",
	["sheep_herder"] = "rbxassetid://9155465730",
	["smoke"] = "rbxassetid://9155462247",
	["spirit_catcher"] = "rbxassetid://9166207943",
	["star_collector"] = "rbxassetid://9872356516",
	["styx"] = "rbxassetid://17014536631",
	["block_kicker"] = "rbxassetid://15382536098",
	["trapper"] = "rbxassetid://9166206875",
	["hatter"] = "rbxassetid://12509388633",
	["ninja"] = "rbxassetid://15517037848",
	["jailor"] = "rbxassetid://11664116980",
	["warrior"] = "rbxassetid://9166207008",
	["mage"] = "rbxassetid://10982191792",
	["void_dragon"] = "rbxassetid://10982192753",
	["cat"] = "rbxassetid://15350740470",
	["wind_walker"] = "rbxassetid://9872355499",
	['skeleton'] = "rbxassetid://120123419412119",
	['winter_lady'] = "rbxassetid://83274578564074",
	['soul_broker'] = 'rbxassetid://130409166262430'
}

local function isFirstPerson()
	local head = lplr.Character and lplr.Character:FindFirstChild('Head')
	if not head then
		return false
	end
	return (head.Position - gameCamera.CFrame.Position).Magnitude < 2
end

local function isFrozen(entity, threshold)
	threshold = threshold or 10
	local char
	if type(entity) == 'table' and entity.Character then
		char = entity.Character
	elseif typeof(entity) == 'Instance' and entity:IsA('Model') then
		char = entity
	elseif entity == nil then
		if not entitylib.isAlive then return false end
		char = entitylib.character.Character
	else
		return false
	end

	local stacks = char:GetAttribute('ColdStacks') or char:GetAttribute('FrostStacks')
		or char:GetAttribute('FreezeStacks') or char:GetAttribute('FROZEN_STACKS')
	if type(stacks) == 'number' and stacks >= threshold then return true end

	if char:FindFirstChild('IceBlock') or char:FindFirstChild('FrozenBlock') or char:FindFirstChild('IceShell') then
		return true
	end

	local humanoid = char:FindFirstChildOfClass('Humanoid')
	return humanoid ~= nil and humanoid.WalkSpeed <= 2
end

local sharedRaycast = RaycastParams.new()
sharedRaycast.FilterType = Enum.RaycastFilterType.Include
local function updateSharedRaycast()
	sharedRaycast.FilterDescendantsInstances = {workspace:FindFirstChild('Map') or workspace}
end
updateSharedRaycast()
vape:Clean(workspace.ChildAdded:Connect(function(child)
	if child.Name == 'Map' then
		updateSharedRaycast()
	end
end))

local function cloneRaycast()
	local r = RaycastParams.new()
	r.FilterType = sharedRaycast.FilterType
	r.FilterDescendantsInstances = sharedRaycast.FilterDescendantsInstances
	r.RespectCanCollide = sharedRaycast.RespectCanCollide
	return r
end

local aimPeekParts = {'Head', 'UpperTorso', 'HumanoidRootPart', 'LowerTorso', 'LeftUpperArm', 'RightUpperArm', 'LeftUpperLeg', 'RightUpperLeg', 'LeftLowerLeg', 'RightLowerLeg', 'Torso'}
local aimPeekCast = RaycastParams.new()
aimPeekCast.FilterType = Enum.RaycastFilterType.Include

local shotTagService = game:GetService('CollectionService')
local shotPlanCache = setmetatable({}, {__mode = 'k'})
local headshotMetaCache = {}
local shotBodyParts = {
	Head = true, UpperTorso = true, LowerTorso = true, Torso = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true,
	LeftHand = true, RightHand = true, LeftUpperLeg = true, RightUpperLeg = true,
	LeftLowerLeg = true, RightLowerLeg = true, LeftFoot = true, RightFoot = true,
	['Left Arm'] = true, ['Right Arm'] = true, ['Left Leg'] = true, ['Right Leg'] = true
}
local headshotMinChance = 0.2
local splashPad = 3
local projectilePad = 0.25

local function normalCdf(x)
	local sign = x < 0 and -1 or 1
	local z = math.abs(x) / math.sqrt(2)
	local t = 1 / (1 + 0.3275911 * z)
	local y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-z * z)
	return 0.5 * (1 + sign * y)
end

local function bandChance(lo, hi, sigma)
	if hi <= lo then
		return 0
	end
	if sigma <= 1e-6 then
		return (lo <= 0 and hi >= 0) and 1 or 0
	end
	return math.max(normalCdf(hi / sigma) - normalCdf(lo / sigma), 0)
end

local function headshotWord(val)
	if type(val) ~= 'string' then
		return false
	end
	val = val:lower()
	return val:find('headhunter', 1, true) ~= nil or val:find('headshot', 1, true) ~= nil
end

local function metaHasHeadshot(tbl, depth, seen)
	if type(tbl) ~= 'table' or depth > 3 or seen[tbl] then
		return false
	end
	seen[tbl] = true
	for key, val in tbl do
		if headshotWord(tostring(key)) and val and val ~= 0 then
			return true
		end
		if headshotWord(val) then
			return true
		end
		if type(val) == 'table' and metaHasHeadshot(val, depth + 1, seen) then
			return true
		end
	end
	return false
end

local function isHeadshotShot(tool, projType, extraMeta)
	local toolName = typeof(tool) == 'Instance' and tool.Name or tostring(tool or '')
	projType = tostring(projType or '')
	if headshotWord(toolName) or headshotWord(projType) then
		return true
	end

	if typeof(tool) == 'Instance' then
		for key, val in tool:GetAttributes() do
			if (headshotWord(key) and val and val ~= 0) or headshotWord(val) then
				return true
			end
		end
	end

	local me = lplr or game:GetService('Players').LocalPlayer
	local kit = tostring(me and me:GetAttribute('PlayingAsKit') or ''):lower()
	if kit:find('archer', 1, true) then
		return true
	end
	if type(getLocalKits) == 'function' then
		local ok, kits = pcall(getLocalKits)
		if ok and type(kits) == 'table' then
			for _, equipped in kits do
				if tostring(equipped):lower():find('archer', 1, true) then
					return true
				end
			end
		end
	end

	local key = toolName .. '|' .. projType
	local cached = headshotMetaCache[key]
	if cached == nil then
		cached = false
		pcall(function()
			local seen = {}
			local itemMeta = bedwars.ItemMeta and bedwars.ItemMeta[toolName]
			local projMeta = bedwars.ProjectileMeta and bedwars.ProjectileMeta[projType]
			cached = metaHasHeadshot(itemMeta, 0, seen) or metaHasHeadshot(projMeta, 0, seen)
		end)
		headshotMetaCache[key] = cached
	end
	if cached then
		return true
	end

	if extraMeta ~= nil then
		local ok, found = pcall(metaHasHeadshot, extraMeta, 0, {})
		if ok and found then
			return true
		end
	end
	return false
end

local function projectedExtent(part, axis)
	local cf, size = part.CFrame, part.Size
	return math.abs(axis:Dot(cf.RightVector)) * size.X * 0.5
		+ math.abs(axis:Dot(cf.UpVector)) * size.Y * 0.5
		+ math.abs(axis:Dot(cf.LookVector)) * size.Z * 0.5
end

local function partTakesProjectiles(part)
	return part:IsA('BasePart')
		and part:GetAttribute('IgnoreProjectileCollision') ~= true
		and not shotTagService:HasTag(part, 'ProjectilesIgnore')
		and not shotTagService:HasTag(part, 'ProjectilesIgnored')
end

local function shotTrimLead(origin, aim, impact, velocity, flight, speed, gravity, distance, ping)
	if typeof(origin) ~= 'Vector3' or typeof(aim) ~= 'Vector3'
		or typeof(impact) ~= 'Vector3' or typeof(velocity) ~= 'Vector3'
		or type(flight) ~= 'number' or flight <= 0
		or type(speed) ~= 'number' or speed <= 0 then
		return aim, impact, flight, 0
	end

	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local horizontalSpeed = horizontal.Magnitude
	if horizontalSpeed < 3 then
		return aim, impact, flight, 0
	end

	local maxCorrection = distance < 30 and 0.65 or (distance < 80 and 1.3 or 1.6)
	local latency = math.clamp(tonumber(ping) or 0, 0, 0.3)
	local trim = math.min(latency * 0.45, 0.08, maxCorrection / horizontalSpeed)
	if trim <= 0 then
		return aim, impact, flight, 0
	end

	local correctedImpact = impact - horizontal * trim
	local t = flight
	local g = math.max(tonumber(gravity) or 0, 0)

	for _ = 1, 3 do
		local needed = correctedImpact - origin + Vector3.new(0, 0.5 * g * t * t, 0)
		t = math.max(needed.Magnitude / speed, 0.005)
	end

	local needed = correctedImpact - origin + Vector3.new(0, 0.5 * g * t * t, 0)
	if needed.Magnitude < 0.01 then
		return aim, impact, flight, 0
	end

	return origin + needed.Unit * speed, correctedImpact, t, trim
end

local function shotAimCandidates(parts, origin)
	local large, small, result = {}, {}, {}
	for _, part in parts do
		if partTakesProjectiles(part) then
			if part.Name == 'UpperTorso' or part.Name == 'Torso' or part.Name == 'Head' or part.Name == 'LowerTorso' then
				table.insert(large, part)
			else
				table.insert(small, part)
			end
		end
	end
	local function addCenters(group)
		for _, part in group do
			table.insert(result, {part = part, point = part.Position, phase = 'center'})
		end
	end
	local function addSurfaces(group, faceInset, spread, phase, centerOnly)
		local offsets = centerOnly and {{0, 0}} or {
			{-spread, 0}, {spread, 0}, {0, -spread}, {0, spread},
			{-spread, -spread}, {-spread, spread}, {spread, -spread}, {spread, spread}
		}
		if phase == 'inset' and not centerOnly then
			table.insert(offsets, 1, {0, 0})
		end
		for _, part in group do
			local direction = part.CFrame:PointToObjectSpace(origin)
			local dx = math.abs(direction.X / math.max(part.Size.X, 0.01))
			local dy = math.abs(direction.Y / math.max(part.Size.Y, 0.01))
			local dz = math.abs(direction.Z / math.max(part.Size.Z, 0.01))
			local faceY = dy >= dx and dy >= dz
			local faceX = not faceY and dx >= dz
			local axis = faceY and direction.Y or (faceX and direction.X or direction.Z)
			local face = axis >= 0 and faceInset or -faceInset
			for _, uv in offsets do
				local localPoint
				if faceY then
					localPoint = Vector3.new(part.Size.X * uv[1], part.Size.Y * face, part.Size.Z * uv[2])
				elseif faceX then
					localPoint = Vector3.new(part.Size.X * face, part.Size.Y * uv[2], part.Size.Z * uv[1])
				else
					localPoint = Vector3.new(part.Size.X * uv[1], part.Size.Y * uv[2], part.Size.Z * face)
				end
				table.insert(result, {part = part, point = part.CFrame:PointToWorldSpace(localPoint), phase = phase})
			end
		end
	end
	addCenters(large)
	addCenters(small)
	addSurfaces(large, 0.37, 0.33, 'peek', true)
	addSurfaces(small, 0.37, 0.33, 'peek', true)
	addSurfaces(large, 0.37, 0.33, 'peek')
	addSurfaces(small, 0.37, 0.33, 'peek')
	addSurfaces(large, 0.26, 0.22, 'inset')
	addSurfaces(small, 0.26, 0.22, 'inset')
	return result
end

local function shotWithinReturnDistance(origin, aim, speed, gravity, flight, limit)
	if not limit or limit <= 0 then return true end
	if typeof(origin) ~= 'Vector3' or typeof(aim) ~= 'Vector3' or type(flight) ~= 'number' or flight <= 0 then return false end

	local root = entitylib.character and entitylib.character.RootPart
	if not root then return false end

	local delta = aim - origin
	if delta.Magnitude < 0.01 then return false end

	local velocity = delta.Unit * speed
	local selfVelocity = root.AssemblyLinearVelocity or Vector3.zero
	local start = root.Position
	local steps = math.clamp(math.ceil(flight / 0.04), 4, 24)

	for i = 0, steps do
		local t = flight * i / steps
		local projectile = origin + velocity * t - Vector3.new(0, gravity * t * t * 0.5, 0)
		local shooter = start + selfVelocity * t

		if (projectile - shooter).Magnitude >= limit - 1 then
			return false
		end
	end

	return true
end

local function shotPeekSolve(target, origin, solve, speed, gravity, cast, lifetime, headOnly)
	local char = target and target.Character
	if not char then return nil end

	local parts = {}
	for _, part in char:GetChildren() do
		if shotBodyParts[part.Name] and partTakesProjectiles(part)
			and (not headOnly or part.Name == 'Head') then
			table.insert(parts, part)
		end
	end

	if #parts == 0 then return nil end

	local open, blocked = {}, {}
	for index, candidate in shotAimCandidates(parts, origin) do
		candidate.order = index
		local part = candidate.part
		local localPoint = part.CFrame:PointToObjectSpace(candidate.point)
		local half = part.Size * 0.5
		candidate.margin = math.max(0, math.min(
			half.X - math.abs(localPoint.X),
			half.Y - math.abs(localPoint.Y),
			half.Z - math.abs(localPoint.Z)
		))
		local delta = candidate.point - origin
		local visible = delta.Magnitude > 0.01 and not workspace:Raycast(origin, delta, cast)
		table.insert(visible and open or blocked, candidate)
	end

	local torso = {
		UpperTorso = true,
		Torso = true,
		LowerTorso = true
	}

	local function rank(a, b)
		local aPhase = a.phase == 'center' and 0.2 or a.phase == 'inset' and 0.08 or 0
		local bPhase = b.phase == 'center' and 0.2 or b.phase == 'inset' and 0.08 or 0

		local aScore = a.margin + (torso[a.part.Name] and 0.15 or 0) + aPhase
		local bScore = b.margin + (torso[b.part.Name] and 0.15 or 0) + bPhase

		if aScore ~= bScore then
			return aScore > bScore
		end

		return a.order < b.order
	end
	table.sort(open, rank)
	table.sort(blocked, rank)

	for _, group in {open, blocked} do
		local limit = group == open and 24 or (gravity > 0 and 8 or 0)

		for checked = 1, math.min(#group, limit) do
			local candidate = group[checked]
			local aim, flight, start, impact = solve(candidate.point)

			if aim and flight and typeof(start) == 'Vector3' and flight > 0 and flight <= lifetime then
				local direction = aim - start

				if direction.Magnitude > 0.01
					and prediction.IsTrajectoryClear(start, direction.Unit * speed, gravity, flight, cast) then
					return aim, flight, start, impact
				end
			end
		end
	end

	return nil
end

local function shotSafeFlight(origin, aim, impact, speed, gravity, flight, cast)
	if typeof(origin) ~= 'Vector3' or typeof(aim) ~= 'Vector3'
		or type(flight) ~= 'number' or flight <= 0
		or type(speed) ~= 'number' or speed <= 0 then
		return false
	end
	local delta = aim - origin
	if delta.Magnitude < 1e-5 then return false end
	local velocity = delta.Unit * speed
	local endPoint = origin + velocity * flight - Vector3.new(0, 0.5 * gravity * flight * flight, 0)
	if typeof(impact) == 'Vector3' and (endPoint - impact).Magnitude > 0.65 then
		return false
	end
	return prediction.IsTrajectoryClear(origin, velocity, gravity, flight, cast, nil, nil, 0.1)
end

local function shotBodyFovTarget(origin, radius, maxRange, playersEnabled, npcsEnabled)
	if not gameCamera or typeof(origin) ~= 'Vector3' then return nil end

	local cursor = inputService.TouchEnabled
		and gameCamera.ViewportSize / 2
		or inputService:GetMouseLocation()

	local best = nil
	local bestDistance = math.max(tonumber(radius) or 0, 0)

	for _, ent in entitylib.List do
		local root = ent.RootPart
		local char = ent.Character
		local allowed = (ent.Player and playersEnabled)
			or (not ent.Player and npcsEnabled)

		if allowed and ent.Targetable and root and char and char.Parent
			and (root.Position - origin).Magnitude <= maxRange then
			local rootScreen, rootVisible = gameCamera:WorldToViewportPoint(root.Position)
			if rootVisible and rootScreen.Z > 0 then
				local rootDistance = (Vector2.new(rootScreen.X, rootScreen.Y) - cursor).Magnitude
				if rootDistance <= bestDistance then
					best = ent
					bestDistance = rootDistance
				end
			end
			for _, part in char:GetChildren() do
				if shotBodyParts[part.Name] and partTakesProjectiles(part) then
					local screen, visible = gameCamera:WorldToViewportPoint(part.Position)
					if visible and screen.Z > 0 then
						local distance = (Vector2.new(screen.X, screen.Y) - cursor).Magnitude
						if distance <= bestDistance then
							best = ent
							bestDistance = distance
						end
					end
				end
			end
		end
	end

	return best
end

local function growRect(rect, other)
	if not rect then
		return {other[1], other[2], other[3], other[4]}
	end
	rect[1] = math.min(rect[1], other[1])
	rect[2] = math.max(rect[2], other[2])
	rect[3] = math.min(rect[3], other[3])
	rect[4] = math.max(rect[4], other[4])
	return rect
end

local function padRect(rect, pad)
	return rect and {rect[1] - pad, rect[2] + pad, rect[3] - pad, rect[4] + pad} or nil
end

local function overlapRect(a, b)
	if not a or not b then
		return nil
	end
	local rect = {math.max(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.min(a[4], b[4])}
	if rect[2] <= rect[1] or rect[4] <= rect[3] then
		return nil
	end
	return rect
end

local function rectChance(rect, x, y, sh, sv)
	if not rect then
		return 0
	end
	return bandChance(rect[1] - x, rect[2] - x, sh) * bandChance(rect[3] - y, rect[4] - y, sv)
end

local function buildBodyModel(ent, origin)
	local char, root = ent.Character, ent.RootPart
	if not char or not root then return nil end
	local flat = (root.Position - origin) * Vector3.new(1, 0, 1)
	local forward = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local head, body, parts = nil, nil, {}
	for _, part in char:GetChildren() do
		if shotBodyParts[part.Name] and partTakesProjectiles(part) then
			local rel = part.Position - root.Position
			local cx, cy = rel:Dot(right), rel.Y
			local hx = projectedExtent(part, right)
			local hy = projectedExtent(part, Vector3.yAxis)
			local rect = {cx - hx, cx + hx, cy - hy, cy + hy}
			table.insert(parts, {part = part, rect = rect})
			if part.Name == 'Head' then
				head = growRect(head, rect)
			else
				body = growRect(body, rect)
			end
		end
	end
	if not head and not body then return nil end
	return {head = head, body = body, parts = parts, right = right, origin = origin, root = root.Position}
end

local function addSpot(list, x, y)
	for _, spot in list do
		if math.abs(spot.x - x) < 0.15 and math.abs(spot.y - y) < 0.15 then
			return
		end
	end
	table.insert(list, {x = x, y = y})
end

local function bodySpots(model, splash)
	local list = {}
	for _, record in model.parts do
		local part = record.part
		local localDir = part.CFrame:VectorToObjectSpace(model.origin - part.Position)
		local sideX = math.abs(localDir.X) > math.abs(localDir.Z)
		local face = (sideX and localDir.X or localDir.Z) >= 0 and 0.25 or -0.25
		for _, offset in {{0, 0}, {-0.28, 0}, {0.28, 0}, {0, 0.28}, {0, -0.28}, {-0.28, 0.28}, {0.28, 0.28}, {-0.28, -0.28}, {0.28, -0.28}} do
			local localPoint
			if sideX then
				localPoint = Vector3.new(part.Size.X * face, part.Size.Y * offset[2], part.Size.Z * offset[1])
			else
				localPoint = Vector3.new(part.Size.X * offset[1], part.Size.Y * offset[2], part.Size.Z * face)
			end
			local point = part.CFrame:PointToWorldSpace(localPoint)
			local rel = point - model.root
			table.insert(list, {
				x = rel:Dot(model.right), y = rel.Y, point = point, part = part.Name,
				weight = part.Name == 'Head' and 0.75
					or part.Name:find('Foot') and 0.4
					or part.Name:find('LowerLeg') and 0.55
					or part.Name:find('UpperLeg') and 0.8
					or part.Name:find('Hand') and 0.75
					or part.Name:find('Arm') and 0.9
					or 1
			})
		end
	end
	return list
end

local function shotSigmas(lib, root, vel, airborne, flight)
	local lag = type(lib.getlag) == 'function' and lib.getlag() or 0
	local horizon = lag + flight
	local flatSpeed = (vel * Vector3.new(1, 0, 1)).Magnitude
	local missRate = type(lib.GetMissRate) == 'function' and lib.GetMissRate(root) or nil
	local sideErr = (missRate and missRate > 0) and math.max(missRate, 1) or (2 + flatSpeed * 0.3)
	local riseErr = airborne and (4 + math.abs(vel.Y) * 0.2) or (flatSpeed > 4 and 2.5 or 1)
	local sh = math.sqrt(0.04 + (sideErr * horizon) ^ 2)
	local sv = math.min(math.sqrt(0.04 + (riseErr * horizon) ^ 2), 6)
	return sh, sv
end

local function endOcclusion(impact, launch, gravity, flight, from, right, sh, sv, cast, char)
	local arrive = launch + Vector3.new(0, -gravity * flight, 0)
	if arrive.Magnitude < 1e-3 then
		return 1
	end
	local dir = arrive.Unit
	local span = math.clamp((impact - from).Magnitude * 0.5, 1, 8)
	local function open(offset)
		local stop = impact + offset
		local hit = workspace:Raycast(stop - dir * span, dir * span, cast)
		return not hit or (char ~= nil and hit.Instance:IsDescendantOf(char))
	end
	if not open(Vector3.zero) then
		return 0
	end
	local ox = math.clamp(sh, 0.4, 1.5)
	local oy = math.clamp(sv, 0.4, 1.5)
	local count = 2
	for _, offset in {right * ox, right * -ox, Vector3.new(0, oy, 0), Vector3.new(0, -oy, 0)} do
		if open(offset) then
			count += 1
		end
	end
	return count / 6
end

local function planProjectileShot(lib, opts)
	local ent, origin = opts.target, opts.origin
	local root = ent and ent.RootPart
	if not root or not root.Parent or typeof(origin) ~= 'Vector3' then
		return nil
	end
	local speed, gravity = tonumber(opts.speed) or 0, tonumber(opts.gravity) or 0
	if speed <= 0 then
		return nil
	end

	local model = buildBodyModel(ent, origin)
	if not model then
		return nil
	end

	local vel = typeof(opts.velocity) == 'Vector3' and opts.velocity or root.AssemblyLinearVelocity
	local rootPos = root.Position
	local right = model.right
	local pad = opts.splash and splashPad or (opts.radius or projectilePad)
	local head = padRect(model.head, pad)
	if opts.headshot and not head then return nil end
	local headshot = opts.headshot == true
	local cast = opts.cast
	local rects = {}
	for _, record in model.parts do
		table.insert(rects, padRect(record.rect, pad))
	end

	local flightGuess = (rootPos - origin).Magnitude / speed
	if gravity > 0 then flightGuess *= 1.05 end
	local sh, sv = shotSigmas(lib, root, vel, opts.airborne, flightGuess)
	local function hitChance(x, y)
		local best = 0
		for _, rect in rects do
			best = math.max(best, rectChance(rect, x, y, sh, sv))
		end
		return math.clamp(best, 0, 1)
	end

	local spots = bodySpots(model, opts.splash)
	for _, spot in spots do
		spot.head = spot.part == 'Head' and rectChance(head, spot.x, spot.y, sh, sv) or 0
		spot.any = hitChance(spot.x, spot.y) * spot.weight
	end

	local lastSolved
	local function solve(spot)
		lastSolved = spot
		local point = spot.point
		local function run(from)
			return lib.SolveTrajectory(from, speed, gravity, point, vel, opts.playerGravity, opts.hipHeight, opts.jump, cast, opts.airborne, rootPos, root, nil, true)
		end
		local aim, impact, flight = run(origin)
		if not aim or not flight then
			if not tostring(opts.projectile or ''):find('arrow', 1, true) then return nil end
			local lag = math.clamp(type(lib.getlag) == 'function' and lib.getlag() or 0, 0, 0.12)
			local t = math.max((point - origin).Magnitude / speed, 0.01)
			local future = point
			local correction
			for _ = 1, 6 do
				local horizon = t + lag
				local horizontalHorizon = math.max(horizon - 0.04, t)
				local vertical = opts.airborne and (vel.Y * horizon - 0.5 * (tonumber(opts.playerGravity) or workspace.Gravity) * horizon * horizon) or 0
				future = point + Vector3.new(vel.X * horizontalHorizon, vertical, vel.Z * horizontalHorizon)
				correction = future - origin + Vector3.new(0, 0.5 * gravity * t * t, 0)
				t = correction.Magnitude / speed
			end
			if not correction or t <= 0 or t > (opts.lifetime or math.huge) then return nil end
			aim, impact, flight = origin + correction, future, t
			spot.fallback = true
		end
		if opts.spawn then
			local spawn = opts.spawn(origin, aim)
			if typeof(spawn) == 'Vector3' and (spawn - origin).Magnitude > 1e-3 then
				local aim2, impact2, flight2 = run(spawn)
				if not aim2 or not flight2 then
					return nil
				end
				aim, impact, flight = origin + (aim2 - spawn), impact2, flight2
			end
		end
		if flight > (opts.lifetime or math.huge) then
			return nil
		end
		if opts.maxDistance and speed * flight > opts.maxDistance then
			return nil
		end
		local dir = aim - origin
		if dir.Magnitude <= 0.01 then
			return nil
		end
		local launch = dir.Unit * speed
		local from = origin
		if opts.spawn then
			local spawn = opts.spawn(origin, origin + launch)
			if typeof(spawn) == 'Vector3' then
				from = spawn
			end
		end
		return launch, flight, impact, from
	end

	local function inspect(spot)
		if spot.result ~= nil then return spot.result end
		spot.result = false
		local launch, flight, impact, from = solve(spot)
		if not launch then return false end
		if not opts.skipClear then
			local clear = lib.IsTrajectoryClear(from, launch, gravity, flight, cast, ent.Character)
			if not clear then return false end
		end
		local frac = 1
		if typeof(impact) == 'Vector3' and cast then
			frac = endOcclusion(impact, launch, gravity, flight, from, right, sh, sv, cast, ent.Character)
		end
		if frac <= 0 then return false end
		spot.result = {launch = launch, flight = flight, impact = impact, from = from, frac = frac}
		return spot.result
	end

	local checked = 0
	local function pick(metric)
		local order = table.clone(spots)
		table.sort(order, function(a, b)
			return a[metric] > b[metric]
		end)
		local best, bestScore = nil, 0
		for _, spot in order do
			if spot[metric] <= bestScore or checked >= 80 then
				break
			end
			checked += 1
			local result = inspect(spot)
			if result then
				local score = spot[metric] * result.frac
				if score > bestScore then
					best, bestScore = spot, score
				end
			end
		end
		return best, bestScore
	end

	local chosen
	if headshot then
		chosen = pick('head')
	else
		chosen = pick('any')
	end
	if not chosen or not chosen.result then
		return nil
	end

	local result = chosen.result
	return {
		velocity = result.launch,
		flight = result.flight,
		impact = result.impact,
		from = result.from,
		point = chosen.point,
		part = chosen.part,
		fallback = chosen.fallback == true,
		checked = checked,
		chance = chosen.any * result.frac,
		headChance = chosen.head * result.frac,
		headshot = headshot
	}
end

local function projectileSpawnFrom(lib, from, toward, rel)
	local bow = bedwars.BowConstantsTable or {}
	local rx, ry, rz = bow.RelX or 0.8, bow.RelY or -0.6, bow.RelZ or 0
	if type(rel) == 'table' then
		rx, ry, rz = rel.relX or 0, rel.relY or 0, rel.relZ or 0
	end
	return lib.GetSpawnPosition(from, toward, rx, ry, rz)
end

local function observeProjectileTargets(lib, origin, range, gravityOf)
	if type(lib) ~= 'table' or type(lib.Observe) ~= 'function' then
		return
	end
	for _, ent in entitylib.List do
		local root = ent.Targetable and ent.RootPart
		if root and root.Parent and (root.Position - origin).Magnitude <= range then
			local vel = root.AssemblyLinearVelocity
			local inair = (ent.Humanoid and ent.Humanoid.FloorMaterial == Enum.Material.Air) or math.abs(vel.Y) > 0.01
			lib.Observe(root, root.Position, vel, inair, gravityOf(ent), origin, ent.HipHeight, ent.Jumping and 42.6 or nil)
		end
	end
end

local function isSword()
	return store.hand and store.hand.toolType == 'sword'
end

local function hasValidWeapon()
	if not store.hand or not store.hand.tool then return false end
	local toolType = store.hand.toolType
	if store.hand.tool.Name:lower():find('headhunter') then return true end
	return toolType == 'sword' or toolType == 'bow' or toolType == 'crossbow'
end

local function fixPosition(pos)
	if bedwars.BlockController and bedwars.BlockController.getBlockPosition then
		return bedwars.BlockController:getBlockPosition(pos) * 3
	end
	return pos * 3
end

local function isHoldingItem(keywords, includeProjectileSource)
	if not store.hand or not store.hand.tool then return false end
	local toolName = store.hand.tool.Name
	local lowered = toolName:lower()
	for _, kw in keywords do
		if lowered:find(kw) then return true end
	end
	if includeProjectileSource then
		local meta = bedwars.ItemMeta[toolName]
		return meta and meta.projectileSource and true or false
	end
	return false
end

local function isHoldingPickaxe()
	return isHoldingItem({'pickaxe'})
end

local function isEnemy(ent)
	if not ent then return false end
	if ent.Character and ent.Character:HasTag('petrified-player') then return false end
	local myTeam = lplr:GetAttribute('Team')
	if ent.Player then
		local theirTeam = ent.Player:GetAttribute('Team')
		return myTeam ~= nil and theirTeam ~= nil and myTeam ~= theirTeam
	elseif ent.NPC then
		local npcTeam = ent.Character:GetAttribute('Team')
		return not npcTeam or myTeam ~= npcTeam
	end
	return false
end

local blockFaces = {
	Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(0, 3, 0),
	Vector3.new(0, -3, 0), Vector3.new(0, 0, 3), Vector3.new(0, 0, -3)
}
local sideFaces = {Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(0, 0, 3), Vector3.new(0, 0, -3)}

local function checkFaceAdjacent(pos, faces)
	for _, v in (faces or blockFaces) do
		if getPlacedBlock(pos + v) then return true end
	end
	return false
end

local voidParams = RaycastParams.new()
voidParams.FilterType = Enum.RaycastFilterType.Exclude
local function isAboveVoid(position)
	if not entitylib.isAlive then return false end
	voidParams.FilterDescendantsInstances = {entitylib.character.Character}
	return workspace:Raycast(position, Vector3.new(0, -500, 0), voidParams) == nil
end

local function hasFaceBelowOrSide(pos)
	if getPlacedBlock(pos - Vector3.new(0, 3, 0)) then return true end
	return checkFaceAdjacent(pos, sideFaces)
end

local function nearCorner(poscheck, pos)
	local start = poscheck - Vector3.new(3, 3, 3)
	local fin = poscheck + Vector3.new(3, 3, 3)
	local diff = pos - poscheck
	if diff.Magnitude < 0.001 then
		return poscheck
	end
	local check = poscheck + diff.Unit * 100
	return Vector3.new(
		math.clamp(check.X, start.X, fin.X),
		math.clamp(check.Y, start.Y, fin.Y),
		math.clamp(check.Z, start.Z, fin.Z)
	)
end

local function blockProximity(pos, rangeBlocks)
	rangeBlocks = rangeBlocks or 21
	local range = Vector3.new(rangeBlocks, rangeBlocks, rangeBlocks)
	local mag, best = 60, nil
	local blocks = getBlocksInPoints(
		bedwars.BlockController:getBlockPosition(pos - range),
		bedwars.BlockController:getBlockPosition(pos + range)
	)
	for _, v in blocks do
		local bp = nearCorner(v, pos)
		local d = (pos - bp).Magnitude
		if d < mag and hasFaceBelowOrSide(bp) then
			mag, best = d, bp
		end
	end
	return best
end

local function isGUIOpen()
	local app = bedwars.AppController
	local layers = bedwars.UILayers
	if app:isLayerOpen(layers.MAIN) or app:isLayerOpen(layers.DIALOG) or app:isLayerOpen(layers.POPUP) or app:isAppOpen('BedwarsItemShopApp') then
		return true
	end
	local inv = bedwars.Store:getState().Inventory
	return inv and inv.open
end

local isMobile = inputService.TouchEnabled and not inputService.KeyboardEnabled and not inputService.MouseEnabled

local function getTeammates(namesOnly)
	local result = {}
	local myTeam = lplr:GetAttribute('Team')
	if not myTeam then return result end
	for _, player in playersService:GetPlayers() do
		if player ~= lplr and player:GetAttribute('Team') == myTeam then
			if namesOnly then
				table.insert(result, player.Name)
			else
				local hum = player.Character and player.Character:FindFirstChild('Humanoid')
				if hum and hum.Health > 0 then
					table.insert(result, player)
				end
			end
		end
	end
	if namesOnly then
		table.sort(result)
	end
	return result
end

local function getPlayerHealth(player)
	local char = player and player.Character
	if not char then return 0, 100 end
	local hum = char:FindFirstChildOfClass('Humanoid')
	local health = char:GetAttribute('Health') or (hum and hum.Health) or 0
	local maxHealth = char:GetAttribute('MaxHealth') or (hum and hum.MaxHealth) or 100
	return health, maxHealth
end

local function getWorldFolder()
	local map = workspace:FindFirstChild('Map')
	local worlds = map and map:FindFirstChild('Worlds')
	return worlds and worlds:GetChildren()[1] or nil
end

local function getPickaxeSlot()
	for i, v in store.inventory.hotbar do
		local meta = v.item and bedwars.ItemMeta[v.item.itemType]
		if meta and meta.breakBlock then
			return i - 1
		end
	end
	return nil
end

local function getScaffoldBlockForModule(limitItem)
	if limitItem.Enabled then
		if store.hand.toolType == 'block' then
			return store.hand.tool.Name
		end
		return nil
	end
	local wool = getWool()
	if wool then
		return wool
	end
	for _, item in invItems() do
		local meta = bedwars.ItemMeta[item.itemType]
		if meta and meta.block then
			return item.itemType
		end
	end
	return nil
end

run(function()
	local AimAssist
	local Targets
	local Sort
	local AimSpeed
	local Smoothness
	local SmoothnessToggle
	local Distance
	local AngleSlider
	local KillauraTarget
	local ClickAim
	local ShopCheck
	local AimPart
	local ViewMode
	local PriorityMode
	local ShakeToggle
	local ShakeAmount
	local WorkWithProjectiles
	local projRayCheck = RaycastParams.new()
	projRayCheck.FilterType = Enum.RaycastFilterType.Include

	local function getHeldProjectileMeta()
		local tool = store.hand and store.hand.tool
		local itemMeta = tool and bedwars.ItemMeta[tool.Name]
		local source = itemMeta and itemMeta.projectileSource
		if not source or not source.projectileType then return nil end
		local ammo = tool.Name
		if source.ammoItemTypes and #source.ammoItemTypes > 0 then
			ammo = nil
			for _, item in store.inventory.inventory.items do
				if table.find(source.ammoItemTypes, item.itemType) then
					ammo = item.itemType
					break
				end
			end
		end
		if not ammo then return nil end
		local projType = source.projectileType
		local ok = true
		if type(projType) == 'function' then
			ok, projType = pcall(projType, ammo)
		end
		local projMeta = ok and projType and bedwars.ProjectileMeta[projType]
		if projMeta and type(projMeta.launchVelocity) == 'number' then
			return projMeta
		end
		return nil
	end
	local lockedTarget = nil
	local lastValidTarget = nil
	local lastValidTime = 0
	local GRACE_PERIOD = 0.15
	local rng = Random.new()
	local shakeTime = 0
	local shakeSeed = rng:NextNumber() * 1000

	local function getAimAlpha(speedVal, smoothVal, dt)
		local baseAlpha = math.clamp(speedVal * 0.025, 0.005, 0.98)
		if smoothVal then
			local smoothFactor = math.max(1 - ((smoothVal - 1) / 9) * 0.85, 0.05)
			baseAlpha = baseAlpha * smoothFactor
		end
		return 1 - (1 - baseAlpha) ^ (dt * 60)
	end

	local function getClosestPartToCursor(character)
		local mousePos = inputService.TouchEnabled and (gameCamera.ViewportSize / 2) or inputService:GetMouseLocation()
		local mouseRay = gameCamera:ViewportPointToRay(mousePos.X, mousePos.Y, 0)
		local bestAngle = math.huge
		local bestPart = nil
		local partNames = {
			'Head', 'UpperTorso', 'LowerTorso', 'HumanoidRootPart',
			'LeftUpperArm', 'RightUpperArm', 'LeftLowerArm', 'RightLowerArm',
			'LeftUpperLeg', 'RightUpperLeg', 'LeftLowerLeg', 'RightLowerLeg',
			'LeftFoot', 'RightFoot', 'LeftHand', 'RightHand'
		}
		for _, partName in partNames do
			local part = character:FindFirstChild(partName)
			if part then
				local dirToPart = (part.Position - mouseRay.Origin).Unit
				local angle = math.acos(math.clamp(mouseRay.Direction:Dot(dirToPart), -1, 1))
				if angle < bestAngle then
					bestAngle = angle
					bestPart = part
				end
			end
		end
		return bestPart
	end

	local function isEntValid(ent)
		if not ent or not ent.RootPart or not ent.Character or not ent.Character.Parent then return false end
		if not entitylib.isAlive or not entitylib.character or not entitylib.character.RootPart then return false end
		local hum = ent.Character:FindFirstChildOfClass('Humanoid')
		if not hum or hum.Health <= 0 then return false end
		local dist = (ent.RootPart.Position - entitylib.character.RootPart.Position).Magnitude
		if dist > Distance.Value then return false end
		if not isEnemy(ent) then return false end
		return true
	end

	local function isInAngle(ent)
		if not ent or not ent.RootPart then return false end
		if not entitylib.character or not entitylib.character.RootPart then return false end
		local delta = (ent.RootPart.Position - entitylib.character.RootPart.Position)
		local localFacing = ((getgenv().ViewMode and getgenv().ViewMode.Value == 'Third Person') and gameCamera.CFrame.LookVector or entitylib.character.RootPart.CFrame.LookVector) * Vector3.new(1, 0, 1)
		local flatDelta = delta * Vector3.new(1, 0, 1)
		if flatDelta.Magnitude <= 0.001 then return false end
		local angle = math.acos(math.clamp(localFacing:Dot(flatDelta.Unit), -1, 1))
		return angle < math.rad(AngleSlider.Value / 2)
	end

	AimAssist = vape.Categories.Combat:CreateModule({
		Name = 'AimAssist',
		Function = function(callback)
			if callback then
				lockedTarget = nil
				lastValidTarget = nil
				lastValidTime = 0
				shakeTime = 0
				local aimBindName = 'vapeAimAssist'
				AimAssist:Clean(function()
					pcall(function() runService:UnbindFromRenderStep(aimBindName) end)
				end)
				runService:BindToRenderStep(aimBindName, Enum.RenderPriority.Camera.Value + 1, (function(dt)

					if not entitylib.isAlive or not entitylib.character or not entitylib.character.RootPart then
						lockedTarget = nil
						return
					end

					local projMeta
					local validWeapon = store.hand.toolType == 'sword'
					if WorkWithProjectiles and WorkWithProjectiles.Enabled and not validWeapon then
						projMeta = getHeldProjectileMeta()
						validWeapon = projMeta ~= nil
					end
					if not validWeapon then
						lockedTarget = nil
						return
					end

					if ClickAim and ClickAim.Enabled and projMeta then
						if not inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
							return
						end
					elseif ClickAim and ClickAim.Enabled then
						local sc = bedwars.SwordController
						local lastAttack = sc and rawget(sc, 'lastAttack')
						if not lastAttack or (workspace:GetServerTimeNow() - lastAttack) >= 0.4 then
							return
						end
					end

					local inFirstPerson = isFirstPerson()
					if ViewMode.Value == 'First Person' and not inFirstPerson then return end
					if ViewMode.Value == 'Third Person' and inFirstPerson then return end

					if ShopCheck and ShopCheck.Enabled then
						if isGUIOpen() then
							lockedTarget = nil
							return
						end
					end

					local ent = nil

					if KillauraTarget and KillauraTarget.Enabled then
						local ka = store.KillauraTarget
						if ka and ka.RootPart and ka.Character and ka.Character.Parent then
							local hum = ka.Character:FindFirstChildOfClass('Humanoid')
							local dist = ka.RootPart and entitylib.character and entitylib.character.RootPart and (ka.RootPart.Position - entitylib.character.RootPart.Position).Magnitude
							if hum and hum.Health > 0 and dist and dist <= Distance.Value then
								ent = ka
							end
						end
					else
						if PriorityMode and PriorityMode.Enabled and lockedTarget then
							if isEntValid(lockedTarget) and isInAngle(lockedTarget) then
								ent = lockedTarget
							else
								lockedTarget = nil
							end
						end

						if not ent then
							local found = entitylib.EntityPosition({
								Range = Distance.Value,
								Part = 'RootPart',
								Wallcheck = Targets.Walls.Enabled,
								Players = Targets.Players.Enabled,
								NPCs = Targets.NPCs.Enabled,
								Sort = sortmethods[Sort.Value]
							})

							if found then
								lastValidTarget = found
								lastValidTime = tick()
								ent = found
							elseif lastValidTarget and (tick() - lastValidTime) < GRACE_PERIOD then
								local hum = lastValidTarget.Character and lastValidTarget.Character:FindFirstChildOfClass('Humanoid')
								if hum and hum.Health > 0 and lastValidTarget.Character.Parent and isInAngle(lastValidTarget) then
									ent = lastValidTarget
								else
									lastValidTarget = nil
								end
							end

							if ent and PriorityMode and PriorityMode.Enabled then
								lockedTarget = ent
							end
						end
					end	

					if not ent then return end

					if not (KillauraTarget and KillauraTarget.Enabled) then
						if not isEntValid(ent) then
							if PriorityMode and PriorityMode.Enabled then lockedTarget = nil end
							lastValidTarget = nil
							return
						end
						if not isInAngle(ent) then
							if PriorityMode and PriorityMode.Enabled then lockedTarget = nil end
							return
						end
					end

					targetinfo.Targets[ent] = tick() + 1

					local aimPosition
					if AimPart.Value == 'Head' then
						local head = ent.Character and ent.Character:FindFirstChild('Head')
						aimPosition = head and head.Position or ent.RootPart.Position
					elseif AimPart.Value == 'Torso' then
						local torso = ent.Character and (ent.Character:FindFirstChild('UpperTorso') or ent.Character:FindFirstChild('Torso'))
						aimPosition = torso and torso.Position or ent.RootPart.Position
					elseif AimPart.Value == 'Closest' then
						local closest = ent.Character and getClosestPartToCursor(ent.Character)
						aimPosition = closest and closest.Position or ent.RootPart.Position
					else
						aimPosition = ent.RootPart.Position
					end

					if projMeta then
						local heldName = store.hand and store.hand.tool and store.hand.tool.Name or ''
						if heldName:find('fireball') then
							aimPosition = splashAimPoint(ent.RootPart, ent.HipHeight) or aimPosition
						end
						local projSpeed = projMeta.launchVelocity
						local gravity = tonumber(projMeta.gravitationalAcceleration) or 196.2
						if gravity < 1 then gravity = 0 end
						local playerGravity = workspace.Gravity
						local balloons = ent.Character and ent.Character:GetAttribute('InflatedBalloons')
						if balloons and balloons > 0 then
							playerGravity = balloonGravity(balloons, ent.Character)
						end
						local rawVel = ent.RootPart.AssemblyLinearVelocity
						local tHum = ent.Character and ent.Character:FindFirstChildOfClass('Humanoid')
						local airborne = (tHum and tHum.FloorMaterial == Enum.Material.Air) or math.abs(rawVel.Y) > 3
						local map = workspace:FindFirstChild('Map')
						if map then projRayCheck.FilterDescendantsInstances = {map} end
						local bow = bedwars.BowConstantsTable or {}
						local launchPos = entitylib.character.RootPart.Position
						pcall(function()
							local native = bedwars.ProjectileController:getLaunchPosition(store.hand.tool)
							if typeof(native) == 'Vector3' then
								launchPos = native
							end
						end)
						launchPos += Vector3.new(0, 2, 0)
						local spawnPos = prediction.GetSpawnPosition(launchPos, aimPosition, bow.RelX or 0.8, bow.RelY or -0.6, bow.RelZ or 0)
						local calc = prediction.SolveTrajectory(spawnPos, projSpeed, gravity, aimPosition, rawVel, playerGravity, ent.HipHeight, ent.Jumping and 42.6 or nil, projRayCheck, airborne, ent.RootPart.Position, ent.RootPart, nil, true)
						if calc and (calc - spawnPos).Magnitude > 0.01 then
							local shotDir = (calc - spawnPos).Unit
							local camPos = gameCamera.CFrame.Position
							local reach = (camPos - launchPos).Magnitude * (bow.CameraMultiplier or 10)
							local fromCam = launchPos - camPos
							local along = fromCam:Dot(shotDir)
							local disc = along * along - (fromCam:Dot(fromCam) - reach * reach)
							if disc >= 0 then
								local ahead = launchPos + shotDir * (-along + math.sqrt(disc))
								local unit = (ahead - camPos).Unit
								local lift = bow.YTargetOffset or 0.05
								local k = lift * unit.Y
								local scale = k + math.sqrt(math.max(k * k - lift * lift + 1, 0))
								local look = unit * scale - Vector3.new(0, lift, 0)
								if look.Magnitude > 0.01 then
									aimPosition = camPos + look.Unit * 100
								end
							end
						end
					end

					local targetCFrame = CFrame.lookAt(gameCamera.CFrame.Position, aimPosition)
					local smoothVal = (SmoothnessToggle and SmoothnessToggle.Enabled and Smoothness) and Smoothness.Value or nil
					local alpha = getAimAlpha(AimSpeed.Value, smoothVal, dt)
					local cameraResult = gameCamera.CFrame:Lerp(targetCFrame, alpha)
					if ShakeToggle and ShakeToggle.Enabled and ShakeAmount.Value > 0 then
						shakeTime += dt
						local amount = math.clamp(ShakeAmount.Value / 10, 0, 1)
						local x = math.noise(shakeTime * 11, shakeSeed, 0) * amount * 0.008
						local y = math.noise(shakeSeed, shakeTime * 13, 0) * amount * 0.008
						cameraResult *= CFrame.Angles(x, y, 0)
					end
					gameCamera.CFrame = cameraResult
				end))
			else
				lockedTarget = nil
				lastValidTarget = nil
				shakeTime = 0
			end
		end,
		Tooltip = 'aa with smooth tracking'
	})

	Targets = AimAssist:CreateTargets({
		Players = true,
		Walls = true
	})

	Sort = AimAssist:CreateDropdown({
		Name = 'Target Mode',
		List = getSortList({'Damage', 'Distance'}),
		Tooltip = 'prioritize targets'
	})

	AimPart = AimAssist:CreateDropdown({
		Name = 'Aim Part',
		List = {'Torso', 'Head', 'Closest'},
		Default = 'Torso'
	})

	ViewMode = AimAssist:CreateDropdown({
		Name = 'View Mode',
		List = {'First Person', 'Third Person', 'Both'},
		Default = 'Both',
		Tooltip = 'either only aim in first person or third person, or both'
	})
	getgenv().ViewMode = ViewMode

	AimSpeed = AimAssist:CreateSlider({
		Name = 'Aim Speed',
		Min = 1,
		Max = 20,
		Default = 6,
		Tooltip = 'how fast aim assist moves toward the target'
	})

	Distance = AimAssist:CreateSlider({
		Name = 'Distance',
		Min = 1,
		Max = 30,
		Default = 25,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})

	AngleSlider = AimAssist:CreateSlider({
		Name = 'Max Angle',
		Min = 1,
		Max = 360,
		Default = 60,
	})

	SmoothnessToggle = AimAssist:CreateToggle({
		Name = 'Smoothness',
		Default = false,
		Tooltip = 'makes aim assist feels more legit',
		Function = function(callback)
			if Smoothness then Smoothness.Object.Visible = callback end
		end
	})

	Smoothness = AimAssist:CreateSlider({
		Name = 'Smoothness Amount',
		Min = 1,
		Max = 10,
		Default = 5,
		Visible = false
	})

	PriorityMode = AimAssist:CreateToggle({
		Name = 'Priority Mode',
		Default = false,
		Tooltip = 'stays on one target until target is lost'
	})

	ClickAim = AimAssist:CreateToggle({
		Name = 'Click Aim',
		Default = true,
		Tooltip = 'only aims when clicking'
	})

	KillauraTarget = AimAssist:CreateToggle({
		Name = 'Use Killaura Target',
	})

	ShakeToggle = AimAssist:CreateToggle({
		Name = 'Shake',
		Default = false,
		Tooltip = 'shakes your screen for more legitness',
		Function = function(callback)
			if ShakeAmount then ShakeAmount.Object.Visible = callback end
		end
	})

	ShakeAmount = AimAssist:CreateSlider({
		Name = 'Shake Amount',
		Min = 1,
		Max = 10,
		Default = 3,
		Visible = false
	})

	ShopCheck = AimAssist:CreateToggle({
		Name = 'Shop Check',
		Default = false,
	})

	WorkWithProjectiles = AimAssist:CreateToggle({
		Name = 'Work With Projectiles',
		Default = false,
		Tooltip = 'aims where they gonna be when ur holdin a bow or any projectile'
	})

	task.defer(function()
		if Smoothness and Smoothness.Object then
			Smoothness.Object.Visible = SmoothnessToggle and SmoothnessToggle.Enabled or false
		end
		if ShakeAmount and ShakeAmount.Object then
			ShakeAmount.Object.Visible = false
		end
	end)
end)

run(function()
    if isMobile then
        local AutoClicker
        local CPS
        local BlockCPS = {}
        local PlaceBlocksToggle
        local Thread

        local function getSafeCPS()
            if store.hand and store.hand.toolType == 'block' and PlaceBlocksToggle and PlaceBlocksToggle.Enabled and BlockCPS and BlockCPS.GetRandomValue then
                return BlockCPS
            end
            if CPS and CPS.GetRandomValue then
                return CPS
            end
            return nil
        end

        local function AutoClick()
            if Thread then
                task.cancel(Thread)
                Thread = nil
            end

            local initialCPS = getSafeCPS()
            if not initialCPS then return end

            Thread = task.delay(1 / initialCPS.GetRandomValue(), function()
                repeat
                    if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
                        local blockPlacer = bedwars.BlockPlacementController and bedwars.BlockPlacementController.blockPlacer
                        local toolType = store.hand and store.hand.toolType

                        if toolType == 'block' and PlaceBlocksToggle and PlaceBlocksToggle.Enabled and blockPlacer then
                            task.spawn(function()
                                blockPlacer:autoBridge(workspace:GetServerTimeNow() - bedwars.KnockbackController:getLastKnockbackTime() >= 0.2)
                            end)
                        elseif toolType == 'sword' then
                            bedwars.SwordController:swingSwordAtMouse(0.39)
                        end
                    end

                    local currentCPS = getSafeCPS()
                    if not currentCPS then
                        task.wait(0.1)
                    else
                        task.wait(1 / currentCPS.GetRandomValue())
                    end
                until not AutoClicker.Enabled
            end)
        end

        local function StopClick()
            if Thread then
                task.cancel(Thread)
                Thread = nil
            end
        end

        AutoClicker = vape.Categories.Combat:CreateModule({
            Name = 'AutoClicker',
            Function = function(callback)
                if callback then
                    AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            AutoClick()
                        end
                    end))

                    AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            StopClick()
                        end
                    end))

                    for _, v in {'2', '5'} do
                        pcall(function()
                            AutoClicker:Clean(lplr.PlayerGui.MobileUI[v].MouseButton1Down:Connect(AutoClick))
                            AutoClicker:Clean(lplr.PlayerGui.MobileUI[v].MouseButton1Up:Connect(StopClick))
                        end)
                    end
                else
                    StopClick()
                end
            end,
            Tooltip = 'clicks for you'
        })

        CPS = AutoClicker:CreateTwoSlider({
            Name = 'CPS',
            Min = 1,
            Max = 9,
            DefaultMin = 7,
            DefaultMax = 7
        })

        PlaceBlocksToggle = AutoClicker:CreateToggle({
            Name = 'Place Blocks',
            Default = true,
            Function = function(callback)
                if BlockCPS.Object then
                    BlockCPS.Object.Visible = callback
                end
            end
        })

        BlockCPS = AutoClicker:CreateTwoSlider({
            Name = 'Block CPS',
            Min = 1,
            Max = 20,
            DefaultMin = 12,
            DefaultMax = 12,
            Darker = true
        })

        task.defer(function()
            if BlockCPS and BlockCPS.Object then
                BlockCPS.Object.Visible = PlaceBlocksToggle and PlaceBlocksToggle.Enabled
            end
        end)

    else
        local AutoClicker
        local CPS
        local BlockCPS = {}
        local SwordCPS = {}
        local PlaceBlocksToggle
        local SwingSwordToggle
        local Thread

        local task_wait = task.wait
        local task_spawn = task.spawn
        local workspace_GetServerTimeNow = function() return workspace:GetServerTimeNow() end

        local function getSafeCPS()
            local toolType = store.hand and store.hand.toolType or nil
            if toolType == 'block' and PlaceBlocksToggle and PlaceBlocksToggle.Enabled and BlockCPS and BlockCPS.GetRandomValue then
                return BlockCPS
            elseif toolType == 'sword' and SwingSwordToggle and SwingSwordToggle.Enabled and SwordCPS and SwordCPS.GetRandomValue then
                return SwordCPS
            elseif CPS and CPS.GetRandomValue then
                return CPS
            end
            return nil
        end

        local function AutoClickskid()
            if Thread then task.cancel(Thread) end
            Thread = task_spawn(function()
                repeat
                    if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
                        local toolType = store.hand and store.hand.toolType
                        if PlaceBlocksToggle.Enabled and toolType == 'block' then
                            local blockPlacer = bedwars.BlockPlacementController and bedwars.BlockPlacementController.blockPlacer
                            if blockPlacer then
                                if (workspace_GetServerTimeNow() - bedwars.BlockCpsController.lastPlaceTimestamp) >= ((1 / 12) * 0.5) then
                                    local mouseinfo = blockPlacer.clientManager:getBlockSelector():getMouseInfo(0)
                                    if mouseinfo and mouseinfo.placementPosition == mouseinfo.placementPosition then
                                        task_spawn(blockPlacer.placeBlock, blockPlacer, mouseinfo.placementPosition)
                                    end
                                end
                            end
                        elseif SwingSwordToggle.Enabled and toolType == 'sword' then
                            local previousSwing = bedwars.SwordController.lastSwing
                            bedwars.SwordController:swingSwordAtMouse(0.39)
                            local currentSwing = bedwars.SwordController.lastSwing
                            if store.kaSwingOnly and type(currentSwing) == 'number' and currentSwing ~= previousSwing then
                                store.kaAutoSwingSerial = (store.kaAutoSwingSerial or 0) + 1
                                store.kaAutoSwingAt = tick()
                            end
                        end
                    end

                    local currentCPS = getSafeCPS()
                    task_wait(1 / (currentCPS and currentCPS.GetRandomValue() or 7))
                until not AutoClicker.Enabled
            end)
        end

        local function StopAutoClick()
            if Thread then
                task.cancel(Thread)
                Thread = nil
            end
        end

        local MIN_HOLD_TIME = 0.12
        local ActivationScheduled = nil

        AutoClicker = vape.Categories.Combat:CreateModule({
            Name = 'AutoClicker',
            Function = function(callback)
                if callback then
                    AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            ActivationScheduled = task.delay(MIN_HOLD_TIME, function()
                                ActivationScheduled = nil
                                if inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                                    AutoClickskid()
                                end
                            end)
                        end
                    end))
                    AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            if ActivationScheduled then
                                task.cancel(ActivationScheduled)
                                ActivationScheduled = nil
                            end
                            if Thread then
                                task.cancel(Thread)
                                Thread = nil
                            end
                        end
                    end))
                else
                    StopAutoClick()
                end
            end,
            Tooltip = 'clicks for you'
        })

        PlaceBlocksToggle = AutoClicker:CreateToggle({
            Name = 'Place Blocks',
            Default = false,
            Function = function(callback)
                task.defer(function()
                    if BlockCPS and BlockCPS.Object then BlockCPS.Object.Visible = callback end
                end)
            end
        })

        BlockCPS = AutoClicker:CreateTwoSlider({
            Name = 'Block CPS',
            Min = 1,
            Max = 20,
            DefaultMin = 12,
            DefaultMax = 12,
            Darker = true
        })

        SwingSwordToggle = AutoClicker:CreateToggle({
            Name = 'Swing Sword',
            Default = false,
            Function = function(callback)
                if SwordCPS.Object then SwordCPS.Object.Visible = callback end
            end
        })

        SwordCPS = AutoClicker:CreateTwoSlider({
            Name = 'Sword CPS',
            Min = 1,
            Max = 9,
            DefaultMin = 7,
            DefaultMax = 7,
            Darker = true
        })

        task.defer(function()
            if BlockCPS and BlockCPS.Object then
                BlockCPS.Object.Visible = PlaceBlocksToggle and PlaceBlocksToggle.Enabled
            end
            if SwordCPS and SwordCPS.Object then
                SwordCPS.Object.Visible = SwingSwordToggle and SwingSwordToggle.Enabled
            end
        end)
    end
end)  
	
run(function()
	local Attack
	local Mine
	local Place
	local oldAttackReach, oldMineReach, oldPlaceReach
	local oldRegionTarget
	local SwordReach, MineReach
	local AirReach, AirReachChance
	local airReachState = false
	local airReachRolled = false
	local _airReachThread

	Reach = vape.Categories.Combat:CreateModule({
		Name = 'Reach',
		Function = function(callback)
			local aeroAlive = newRun(Reach)
			if callback then
				if bedwars.SwordController and not oldRegionTarget then
					oldRegionTarget = bedwars.SwordController.getTargetInRegion
					bedwars.SwordController.getTargetInRegion = function(self, range, ...)
						local cur = bedwars.CombatConstant and bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE
						if SwordReach.Enabled and type(range) == 'number' and cur and cur > (oldAttackReach or 14.4) then
							range = math.max(range, cur - 2)
						end
						return oldRegionTarget(self, range, ...)
					end
				end
				if SwordReach and SwordReach.Enabled then
					task.spawn(function()
						repeat task.wait(0.1) until (bedwars.CombatConstant and bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE) or not Reach.Enabled
						if not Reach.Enabled or not SwordReach.Enabled then return end
						oldAttackReach = bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE
						bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
					end)
				end
				
				task.spawn(function()
					repeat task.wait(0.1) until bedwars.BlockBreakController or not Reach.Enabled
					if not Reach.Enabled or not MineReach or not MineReach.Enabled then return end
					
					pcall(function()
						local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
						if blockBreaker then
							oldMineReach = oldMineReach or blockBreaker:getRange()
							blockBreaker:setRange(Mine.Value)
						end
					end)
				end)
				
				local _reachLoopThread = task.spawn(function()
					while aeroAlive() do
						task.wait(5)
						if not Reach.Enabled then break end
						if SwordReach.Enabled and not (AirReach and AirReach.Enabled) and bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE ~= Attack.Value + 2 then
							bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
						end
						if MineReach.Enabled then
							pcall(function()
								local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
								if blockBreaker and blockBreaker:getRange() ~= Mine.Value then
									blockBreaker:setRange(Mine.Value)
								end
							end)
						end
					end
				end)
				airReachRolled = false
				_airReachThread = task.spawn(function()
					while aeroAlive() do
						task.wait(0.05)
						if not Reach.Enabled then break end
						if not AirReach or not AirReach.Enabled or not SwordReach.Enabled then
							airReachRolled = false
						else
							local ent = store.KillauraTarget
							local tchar = ent and ent.Character
							local hum = tchar and tchar:FindFirstChildOfClass('Humanoid')
							local inAir = false
							if hum then
								inAir = hum.FloorMaterial == Enum.Material.Air
								if not inAir then
									local st = hum:GetState()
									inAir = st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall
								end
								if not inAir then
									local root = tchar.PrimaryPart
									local vy = root and root.AssemblyLinearVelocity.Y or 0
									inAir = math.abs(vy) > 3
								end
							end
							if not inAir then
								airReachRolled = false
								bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
							else
								if not airReachRolled then
									airReachRolled = true
									airReachState = math.random(1, 100) <= AirReachChance.Value
								end
								bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = airReachState and (Attack.Value + 2) or (oldAttackReach or 14.4)
							end
						end
					end
				end)
				Reach:Clean(function()
					if _airReachThread then
						pcall(task.cancel, _airReachThread)
						_airReachThread = nil
					end
					airReachRolled = false
				end)
				Reach:Clean(function()
					if _reachLoopThread then
						pcall(task.cancel, _reachLoopThread)
						_reachLoopThread = nil
					end
				end)
			else
				if oldRegionTarget then
					bedwars.SwordController.getTargetInRegion = oldRegionTarget
					oldRegionTarget = nil
				end
				if oldAttackReach then
					bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = oldAttackReach
				end
				
				if oldMineReach then
					pcall(function()
						local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
						if blockBreaker then
							blockBreaker:setRange(oldMineReach)
						end
					end)
				end

				oldAttackReach, oldMineReach = nil, nil
			end
		end,
		Tooltip = 'increases reach for attacking, mining'
	})
	
	SwordReach = Reach:CreateToggle({
		Name = 'Sword Reach',
		Default = true,
		Function = function(v)
			if Attack then Attack.Object.Visible = v end
			if Reach.Enabled then
				if v then
					bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
				else
					bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = oldAttackReach or 14.4
				end
			end
		end
	})

	Attack = Reach:CreateSlider({
		Name = 'Attack Range',
		Darker = true,
		Visible = true,
		Min = 0,
		Max = 20,
		Default = 18,
		Function = function(val)
			if Reach.Enabled then
				bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = val + 2
			end
		end,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	
	AirReach = Reach:CreateToggle({
		Name = 'Air Reach',
		Default = false,
		Tooltip = 'puts ur reach back to normal when they in the air so it looks legit',
		Function = function(v)
			if AirReachChance then AirReachChance.Object.Visible = v end
			if not v and Reach.Enabled and SwordReach and SwordReach.Enabled then
				bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
			end
		end
	})

	AirReachChance = Reach:CreateSlider({
		Name = 'Air Reach Chance',
		Min = 0,
		Max = 100,
		Default = 50,
		Suffix = '%',
		Darker = true,
		Visible = false,
		Tooltip = 'how often u still get reach while they jumpin'
	})

	MineReach = Reach:CreateToggle({
		Name = 'Mine Reach',
		Default = false,
		Function = function(v)
			if Mine then Mine.Object.Visible = v end
		end
	})

	Mine = Reach:CreateSlider({
		Name = 'Mine Range',
		Darker = true,
		Visible = false,
		Min = 0,
		Max = 30,
		Default = 18,
		Function = function(val)
			if Reach.Enabled then
				pcall(function()
					local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
					if blockBreaker then
						blockBreaker:setRange(val)
					end
				end)
			end
		end,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local Sprint
	local old
	local sprintSession = 0
	
	Sprint = vape.Categories.Combat:CreateModule({
		Name = 'Sprint',
		Function = function(callback)
			if callback ~= Sprint.Enabled then return end
			sprintSession = sprintSession + 1
			local session = sprintSession
			local controller = bedwars.SprintController
			if callback then
				if inputService.TouchEnabled then 
					pcall(function() 
						lplr.PlayerGui.MobileUI['4'].Visible = false 
					end) 
				end
				old = nil
				task.spawn(function()
					while Sprint.Enabled and sprintSession == session do
						if entitylib.isAlive then
							pcall(function()
								if not controller:isSprinting() then
									controller:startSprinting()
								end
							end)
						end
						task.wait(0.12)
					end
				end)
			else
				if inputService.TouchEnabled then 
					pcall(function() 
						lplr.PlayerGui.MobileUI['4'].Visible = true 
					end) 
				end
				pcall(function()
					controller:stopSprinting()
				end)
			end
		end,
	})
end)

run(function()
	local Velocity
	local Vertical
	local Horizontal
	local Mode
	local DelayGround
	local DelayAir
	local Targetting
	local Chance
	local old = nil
	local rand = Random.new()

	Velocity = vape.Categories.Combat:CreateModule({
		Name = 'Velocity',
		Tooltip = 'control you to edit ur knockback',
		Function = function(callback)
			if callback then
				old = bedwars.KnockbackUtil.applyKnockback
				Velocity:Clean(vapeEvents.TakeKnockback.Event:Connect(function(root, mass, dir, knockback, ...)
					local args = {...}
					local clone = table.clone(knockback)

					local air, ground = false, false
					task.delay(DelayAir.Value / 1000, function()
						clone.horizontal = knockback.horizontal or 1
						air = true
					end)
					task.delay(DelayGround.Value / 1000, function()
						clone.vertical = knockback.vertical or 1
						ground = true
					end)
					repeat task.wait(0.1) until air
					repeat task.wait(0.05) until ground
					old(root, mass, dir, clone, unpack(args))
				end))

				bedwars.KnockbackUtil.applyKnockback = function(root, mass, dir, knockback, ...)
					local check = (not Targetting.Enabled) or entitylib.EntityPosition({
						Range = 50,
						Part = 'RootPart',
						Players = true
					})

					local chance = rand:NextNumber(0, 100)
					chance = math.floor(chance)
					if Mode.Value == 'Default' then
						if chance >= Chance.Value then return old(root, mass, dir, knockback, ...) end
					end

					if check then
						knockback = knockback or {}
						if Mode.Value == 'Lag' then
							if chance < Chance.Value then
								return vapeEvents.TakeKnockback:Fire(root, mass, dir, knockback, ...)
							end
						else
							if Horizontal.Value == 0 and Vertical.Value == 0 then return end
							knockback.horizontal = (knockback.horizontal or 1) * (Horizontal.Value / 100)
							knockback.vertical = (knockback.vertical or 1) * (Vertical.Value / 100)
						end
					end

					return old(root, mass, dir, knockback, ...)
				end
			else
				bedwars.KnockbackUtil.applyKnockback = old
				old = nil
			end
		end
	})
	Mode = Velocity:CreateDropdown({
		Name = "Mode",
		List = {'Lag','Default'},
		Function = function(val)
			local isDefault = val == 'Default'
			if Horizontal then Horizontal.Object.Visible = isDefault end
			if Vertical then Vertical.Object.Visible = isDefault end
			if DelayGround then DelayGround.Object.Visible = not isDefault end
			if DelayAir then DelayAir.Object.Visible = not isDefault end
		end
	})
	Vertical = Velocity:CreateSlider({
		Name = "Vertical",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Visible = (Mode.Value == 'Default')
	})
	Horizontal = Velocity:CreateSlider({
		Name = "Horizontal",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Visible = (Mode.Value == 'Default')
	})
	DelayGround = Velocity:CreateSlider({
		Name = "Delay Ground",
		Min = 0,
		Max = 3000,
		Default = 1000,
		Suffix = 'ms',
		Decimal = 1,
		Visible = (Mode.Value == 'Lag')
	})
	DelayAir = Velocity:CreateSlider({
		Name = "Delay Air",
		Min = 0,
		Max = 3000,
		Default = 1000,
		Suffix = 'ms',
		Decimal = 1,
		Visible = (Mode.Value == 'Lag')
	})
	Targetting = Velocity:CreateToggle({
		Name = 'Only when targetting',
		Default = false
	})
	Chance = Velocity:CreateSlider({
		Name = "Chance",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Suffix = '%',
		Tooltip = 'how often it actually changes ur knockback, 100 means every hit'
	})
end)


local function watchTargets()
	return runService.Heartbeat:Connect(function()
		if not entitylib.isAlive or not prediction.Observe then return end
		local here = entitylib.character.RootPart.Position
		for _, ent in entitylib.List do
			local root = ent.RootPart
			if root and root.Parent and (root.Position - here).Magnitude < 250 then
				local vel = root.AssemblyLinearVelocity
				local air = (ent.Humanoid and ent.Humanoid.FloorMaterial == Enum.Material.Air) or math.abs(vel.Y) > 2
				pcall(prediction.Observe, root, root.Position, vel, air, workspace.Gravity, here, ent.HipHeight, ent.Jumping and 42.6 or nil)
			end
		end
	end)
end

run(function()
	local SilentAim
	local Targets
	local TargetPart
	local SortMethod
	local Range
	local FOV
	local SAFOVCircle
	local RandomHeadPercent
	local RandomTorsoPercent
	local OtherProjectiles
	local Blacklist
	local AutoCharge
	local skidChargePercent

	local rayCheck = RaycastParams.new()
	rayCheck.FilterType = Enum.RaycastFilterType.Include
	rayCheck.FilterDescendantsInstances = {workspace:FindFirstChild('Map')}

	local namecall
	local namecallHooked = false
	local lockedRandomPart
	local _saVelHistory = {}
	local _saVelStamp = {}
	local fovConn

	local function getMousePosition()
		if inputService.TouchEnabled then
			return gameCamera.ViewportSize / 2
		end
		return inputService:GetMouseLocation()
	end

	local function getClosestPart(char, mousePos)
		local magnitude, part = 9e9, nil
		for _, v in char:GetChildren() do
			if v:IsA('BasePart') then
				local position, vis = gameCamera:WorldToViewportPoint(v.Position)
				if vis then
					local mag = (mousePos - Vector2.new(position.X, position.Y)).Magnitude
					if mag < magnitude then
						magnitude = mag
						part = v
					end
				end
			end
		end
		return part
	end

	local function pickRandomPart(char)
		local roll = math.random(1, 100)
		local head = char:FindFirstChild('Head')
		local torso = char:FindFirstChild('HumanoidRootPart') or char.PrimaryPart
		if head and roll <= RandomHeadPercent.Value then
			return head
		elseif torso and roll <= (RandomHeadPercent.Value + RandomTorsoPercent.Value) then
			return torso
		end
		return torso or head
	end

	local shotTool, shotProj
	local function getTargetPart(plr)
		local val = TargetPart.Value
		if val == 'Dynamic' then
			local tool = (typeof(shotTool) == 'Instance' and shotTool) or (store.hand and store.hand.tool)
			local itemType = tostring(tool and tool.Name or ''):lower()
			if (itemType:find('headhunter') or tostring(shotProj or ''):find('headhunter')) and plr.Character and plr.Character:FindFirstChild('Head') then
				return plr.Character.Head
			end
			return plr.RootPart
		elseif val == 'Head' then
			return (plr.Character and plr.Character:FindFirstChild('Head')) or plr.RootPart
		elseif val == 'Closest' then
			return (plr.Character and getClosestPart(plr.Character, getMousePosition())) or plr.RootPart
		elseif val == 'Randomize' then
			if lockedRandomPart and lockedRandomPart.Parent ~= plr.Character then
				lockedRandomPart = nil
			end
			if plr.Character and (not lockedRandomPart or not lockedRandomPart.Parent) then
				lockedRandomPart = pickRandomPart(plr.Character)
			end
			return lockedRandomPart or plr.RootPart
		end
		return plr.RootPart
	end

	local function isBlacklisted(projType)
		local key = (projType == 'glue_trap' or projType == 'glue_projectile') and 'gloop' or projType
		if Blacklist and table.find(Blacklist.ListEnabled or Blacklist.Value or {}, key) then
			return true
		end
		return false
	end

	local fovDrawing
	local function isHoldingProjectile()
		local tool = store.hand and store.hand.tool
		local itemType = tool and tool.Name or ''
		local itemMeta = bedwars.ItemMeta and bedwars.ItemMeta[itemType]
		if not (itemMeta and itemMeta.projectileSource) then return false end
		local src = itemMeta.projectileSource
		local isArrow = src.ammoItemTypes and table.find(src.ammoItemTypes, 'arrow')
		local isHeadhunter = itemType:find('headhunter')
		if isArrow or isHeadhunter then return true end
		if OtherProjectiles and OtherProjectiles.Enabled then
			local projectileType = src.projectileType and (type(src.projectileType) == 'function' and src.projectileType('arrow') or src.projectileType) or ''
			for _, black in ipairs(Blacklist and Blacklist.ListEnabled or {}) do
				if tostring(projectileType):find(black) then return false end
			end
			return true
		end
		return false
	end
	local function runFOVCircle(state)
		if fovConn then fovConn:Disconnect() fovConn = nil end
		if fovDrawing then fovDrawing:Destroy() fovDrawing = nil end
		if not state then return end
		fovDrawing = Instance.new('Frame')
		fovDrawing.Name = 'SAFOVCircle'
		fovDrawing.BackgroundTransparency = 1
		fovDrawing.AnchorPoint = Vector2.new(0.5, 0.5)
		fovDrawing.Visible = false
		local stroke = Instance.new('UIStroke')
		stroke.Thickness = 1
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Parent = fovDrawing
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = fovDrawing
		fovDrawing.Parent = vape.gui
		fovConn = runService.RenderStepped:Connect(function()
			if not fovDrawing or not FOV or not FOV.Value then return end
			local shouldShow = SilentAim and SilentAim.Enabled and SAFOVCircle and SAFOVCircle.Enabled and isHoldingProjectile()
			fovDrawing.Visible = shouldShow
			if shouldShow then
				local mousePos
				if inputService.TouchEnabled then
					mousePos = gameCamera.ViewportSize / 2
				else
					local mp = inputService:GetMouseLocation()
					mousePos = Vector2.new(mp.X, mp.Y)
				end
				fovDrawing.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)
				fovDrawing.Size = UDim2.fromOffset(FOV.Value * 2, FOV.Value * 2)
			end
		end)
	end

	local function solveSilent(args)
		local origin, velocity, projType = args[4], args[6], args[3]
		shotTool, shotProj = args[1], projType
		if typeof(origin) ~= 'Vector3' then
			origin = args[5]
		end
		if typeof(origin) ~= 'Vector3' or typeof(velocity) ~= 'Vector3' or type(projType) ~= 'string' then
			return
		end

		if (not OtherProjectiles.Enabled) and not projType:find('arrow') then
			return
		end
		if isBlacklisted(projType) then return end

		local meta = bedwars.ProjectileMeta[projType]
		if not meta then return end

		local projSpeed = velocity.Magnitude
		if projSpeed <= 0 then return end

		if AutoCharge and AutoCharge.Enabled then
			local sourceTool = args[1]
			local itemMeta = sourceTool and bedwars.ItemMeta[sourceTool.Name]
			local sourceMeta = itemMeta and itemMeta.projectileSource
			local overrides

			if meta.getProjectileOverridesFunction then
				pcall(function()
					overrides = meta.getProjectileOverridesFunction(lplr)
				end)
			end

			overrides = type(overrides) == 'table' and overrides or {}

			local baseSpeed = tonumber(overrides.launchVelocityOverride) or tonumber(meta.launchVelocity) or projSpeed
			local minScalar = tonumber(sourceMeta and sourceMeta.minStrengthScalar) or 1
			local chargeRatio = math.clamp(skidChargePercent.Value / 100, 0, 1)

			projSpeed = baseSpeed * (minScalar + (1 - minScalar) * chargeRatio)
		end

		local gravity = tonumber(meta.gravitationalAcceleration)
		if gravity == nil then gravity = 196.2 end
		if gravity < 1 then gravity = 0 end

		local plr = entitylib.EntityMouse({
			Part = 'RootPart',
			Range = FOV.Value,
			Players = Targets.Players.Enabled,
			NPCs = (Targets.NPCs and Targets.NPCs.Enabled) or false,
			Wallcheck = false,
			Sort = sortmethods[SortMethod.Value or 'Cursor'],
			Origin = origin,
		})
		if not plr then return end

		local targetBodyPart = getTargetPart(plr)
		if not targetBodyPart then return end

		local dist = (targetBodyPart.Position - origin).Magnitude
		if dist > Range.Value then return end

		local playerGravity = workspace.Gravity
		local balloons = plr.Character and plr.Character:GetAttribute('InflatedBalloons')
		if balloons and balloons > 0 then
			playerGravity = balloonGravity(balloons, plr.Character)
		end
		if plr.Character and plr.Character.PrimaryPart and plr.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
			playerGravity = 6
		end

		local pearl = projType == 'telepearl'
		local rawVel = pearl and Vector3.zero or (plr.RootPart.AssemblyLinearVelocity or plr.RootPart.Velocity or Vector3.zero)
		local _velKey = tostring(plr)
		_saVelHistory[_velKey] = rawVel
		_saVelStamp[_velKey] = tick()

		local aimTarget = targetBodyPart.Position
		if tostring(projType):find('fireball') then
			aimTarget = splashAimPoint(plr.RootPart, plr.HipHeight) or aimTarget
		end
		local _map = workspace:FindFirstChild('Map')
		if _map then rayCheck.FilterDescendantsInstances = {_map} end
		local lifetime = tonumber(meta.predictionLifetimeSec) or tonumber(meta.lifetimeSec) or (projSpeed > 0 and math.min(3, 120 / projSpeed) or 3)
		local spawnPos = origin
		local bow = bedwars.BowConstantsTable or {}
		local rx, ry, rz = bow.RelX or 0.8, bow.RelY or -0.6, bow.RelZ or 0
		local srcMeta = typeof(args[1]) == 'Instance' and bedwars.ItemMeta[args[1].Name]
		local rel = srcMeta and srcMeta.projectileSource and srcMeta.projectileSource.relativeOverride
		if type(rel) == 'table' then
			rx, ry, rz = rel.relX or 0, rel.relY or 0, rel.relZ or 0
		end
		local airFlag = (plr.Humanoid and plr.Humanoid.FloorMaterial == Enum.Material.Air) or math.abs(rawVel.Y) > 0.01
		local function aimAt(point)
			local c1, i1, f1 = prediction.SolveTrajectory(spawnPos, projSpeed, gravity, point, _saVelHistory[_velKey] or rawVel, playerGravity, plr.HipHeight, plr.Jumping and 42.6 or nil, rayCheck, airFlag, plr.RootPart.Position, plr.RootPart, nil, true)
			if not c1 then return nil end
			local s1 = prediction.GetSpawnPosition(spawnPos, c1, rx, ry, rz)
			local c2, i2, f2 = prediction.SolveTrajectory(s1, projSpeed, gravity, point, _saVelHistory[_velKey] or rawVel, playerGravity, plr.HipHeight, plr.Jumping and 42.6 or nil, rayCheck, airFlag, plr.RootPart.Position, plr.RootPart, nil, true)
			if c2 and f2 then
				c1, i1, f1 = spawnPos + (c2 - s1), i2, f2
				s1 = prediction.GetSpawnPosition(spawnPos, c1, rx, ry, rz)
			end
			return c1, f1, s1, i1
		end
		local headOnly = tostring(projType):lower():find('headhunter', 1, true) ~= nil
			or (typeof(args[1]) == 'Instance' and args[1].Name:lower():find('headhunter', 1, true) ~= nil)
		local body = plr.Character
		local preferred = targetBodyPart
		if not preferred:IsA('BasePart') or not shotBodyParts[preferred.Name] then
			preferred = body and (body:FindFirstChild('UpperTorso') or body:FindFirstChild('Torso') or body:FindFirstChild('Head'))
		end
		local names = headOnly and {'Head'} or {
			'Head', 'UpperTorso', 'Torso',
			'LeftUpperArm', 'RightUpperArm',
			'LeftLowerArm', 'RightLowerArm',
			'LeftHand', 'RightHand',
			'Left Arm', 'Right Arm'
		}
		local parts, seen = {}, {}
		local function addPart(part)
			if part and not seen[part] and partTakesProjectiles(part) then
				seen[part] = true
				table.insert(parts, part)
			end
		end
		if headOnly then
			addPart(body and body:FindFirstChild('Head'))
		else
			if preferred and table.find(names, preferred.Name) then
				addPart(preferred)
			end
			for _, name in names do
				addPart(body and body:FindFirstChild(name))
			end
		end
		local calc, flightTime, impact
		local checks, solves = 0, 0
		local function tryPoint(point)
			if checks >= 220 or solves >= 48 then return false end
			checks += 1
			if workspace:Raycast(spawnPos, point - spawnPos, rayCheck) then return false end
			solves += 1
			local c, f, shotStart, i = aimAt(point)
			if not c or not f or f <= 0 or f > lifetime then return false end
			local delta = c - spawnPos
			if delta.Magnitude <= 0.01 then return false end
			if not prediction.IsTrajectoryClear(shotStart, delta.Unit * projSpeed, gravity, f, rayCheck) then
				return false
			end
			calc, flightTime, impact = c, f, i
			return true
		end
		for _, part in parts do
			if tryPoint(part.Position) then break end
		end
		if not calc then
			local passes = {
				{{0, 0}, {-0.46, 0}, {0.46, 0}, {0, -0.46}, {0, 0.46}},
				{{-0.46, -0.46}, {-0.46, 0.46}, {0.46, -0.46}, {0.46, 0.46}},
				{{-0.23, 0}, {0.23, 0}, {0, -0.23}, {0, 0.23},
				 {-0.23, -0.46}, {0.23, -0.46}, {-0.23, 0.46}, {0.23, 0.46},
				 {-0.46, -0.23}, {-0.46, 0.23}, {0.46, -0.23}, {0.46, 0.23}}
			}
			for _, offsets in passes do
				if calc or checks >= 220 or solves >= 48 then break end
				for _, part in parts do
					if calc or checks >= 220 or solves >= 48 then break end
					local direction = part.CFrame:PointToObjectSpace(spawnPos)
					local faceX = math.abs(direction.X / math.max(part.Size.X, 0.01))
						> math.abs(direction.Z / math.max(part.Size.Z, 0.01))
					local face = (faceX and direction.X or direction.Z) >= 0 and 0.48 or -0.48
					for _, offset in offsets do
						local localPoint = faceX
							and Vector3.new(part.Size.X * face, part.Size.Y * offset[2], part.Size.Z * offset[1])
							or Vector3.new(part.Size.X * offset[1], part.Size.Y * offset[2], part.Size.Z * face)
						if tryPoint(part.CFrame:PointToWorldSpace(localPoint)) then break end
						if checks >= 220 or solves >= 48 then break end
					end
				end
			end
		end
		if not calc or not flightTime then return end

		if targetinfo and targetinfo.Targets then
			targetinfo.Targets[plr] = tick() + 1
		end

		return (calc - spawnPos).Unit * projSpeed
	end

	SilentAim = vape.Categories.Blatant:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			if callback then
				if SAFOVCircle and SAFOVCircle.Enabled then
					runFOVCircle(true)
				end
				SilentAim:Clean(watchTargets())
				if not namecallHooked then
					namecallHooked = true
					namecall = hookmetamethod(game, '__namecall', newcclosure(function(...)
						if not SilentAim.Enabled or checkcaller() or getnamecallmethod() ~= 'InvokeServer' then
							return namecall(...)
						end
						local remote = ...
						if typeof(remote) == 'Instance' and remote.Name == 'ProjectileFire' then
							local args = table.pack(select(2, ...))
							local ok, newVelocity = pcall(solveSilent, args)
							if ok and typeof(newVelocity) == 'Vector3' then
								args[6] = newVelocity
								if AutoCharge.Enabled and typeof(args[8]) == 'table' then
									local sourceTool = args[1]
									local itemMeta = sourceTool and bedwars.ItemMeta[sourceTool.Name]
									local sourceMeta = itemMeta and itemMeta.projectileSource
									local maxCharge = tonumber(sourceMeta and sourceMeta.maxStrengthChargeSec)
										or tonumber(sourceMeta and sourceMeta.maxDrawDurationSeconds)

									if maxCharge then
										args[8].drawDurationSec = maxCharge * math.clamp(skidChargePercent.Value / 100, 0, 1)
									end
								end
							end
							local self = ...
							return self.InvokeServer(self, table.unpack(args, 1, args.n))
						end
						return namecall(...)
					end))
				end
			else
				lockedRandomPart = nil
				table.clear(_saVelHistory)
				table.clear(_saVelStamp)
				runFOVCircle(false)
			end
		end,
		Tooltip = 'hooks the projectile remote n sends diff args so it hits em where u aim on ur screen'
	})

	Targets = SilentAim:CreateTargets({
		Players = true,
		NPCs = true,
		Walls = true
	})

	TargetPart = SilentAim:CreateDropdown({
		Name = 'Part',
		List = {'Dynamic', 'RootPart', 'Head', 'Closest', 'Randomize'},
		Default = 'Dynamic',
		Function = function()
			lockedRandomPart = nil
		end
	})

	SortMethod = SilentAim:CreateDropdown({
		Name = 'Sort Method',
		List = getSortList({'Distance', 'Damage', 'Cursor'}),
		Default = 'Cursor',
	})

	Range = SilentAim:CreateSlider({
		Name = 'Range',
		Min = 10,
		Max = 500,
		Default = 100,
	})

	FOV = SilentAim:CreateSlider({
		Name = 'FOV',
		Min = 1,
		Max = 1000,
		Default = 300,
	})

	SAFOVCircle = SilentAim:CreateToggle({
		Name = 'FOV Circle',
		Function = function(call)
			if SilentAim.Enabled then
				runFOVCircle(call)
			end
		end
	})

	RandomHeadPercent = SilentAim:CreateSlider({
		Name = 'Head Chance',
		Min = 0,
		Max = 100,
		Default = 50,
		Darker = true,
		Visible = false
	})

	RandomTorsoPercent = SilentAim:CreateSlider({
		Name = 'Torso Chance',
		Min = 0,
		Max = 100,
		Default = 50,
		Darker = true,
		Visible = false,
		Function = function(val)
			if RandomHeadPercent and (RandomHeadPercent.Value + val) > 100 then
				notif('SilentAim', 'head or torso chance is more than 100% so root part will never be picked..', 3)
			end
		end
	})

	local function updateRandomizeVisibility()
		local vis = (TargetPart.Value == 'Randomize')
		RandomHeadPercent.Object.Visible = vis
		RandomTorsoPercent.Object.Visible = vis
	end
	if TargetPart.AddHook then
		TargetPart:AddHook(updateRandomizeVisibility)
	end
	updateRandomizeVisibility()

	OtherProjectiles = SilentAim:CreateToggle({
		Name = 'Other Projectiles',
		Default = true,
		Function = function(call)
			if Blacklist then Blacklist.Object.Visible = call end
		end
	})
	Blacklist = SilentAim:CreateTextList({
		Name = 'Blacklist',
		Darker = true,
		Default = {'telepearl'},
		Visible = OtherProjectiles.Enabled
	})
	AutoCharge = SilentAim:CreateToggle({
		Name = 'AutoCharge',
		Default = true,
		Function = function(v)
			if skidChargePercent and skidChargePercent.Object then skidChargePercent.Object.Visible = v end
		end
	})
	skidChargePercent = SilentAim:CreateSlider({
		Name = 'Charge Percent',
		Min = 1,
		Max = 100,
		Default = 100,
	})
end)

run(function()
    local _sharedHitBlock = nil
    local _hitBlockPatchers = {}

    getgenv().registerHitBlockPatch = function(key, fn)
        _hitBlockPatchers[key] = fn
        if not _sharedHitBlock and bedwars.BlockBreaker then
            _sharedHitBlock = bedwars.BlockBreaker.hitBlock
        end
        if not bedwars.BlockBreaker then return end
        bedwars.BlockBreaker.hitBlock = function(self, maid, raycastparams, ...)
            for _, patcher in _hitBlockPatchers do
                local result = patcher(self, maid, raycastparams, ...)
                if result ~= nil then return result end
            end
            if _sharedHitBlock then return _sharedHitBlock(self, maid, raycastparams, ...) end
        end
    end

    getgenv().unregisterHitBlockPatch = function(key)
        _hitBlockPatchers[key] = nil
        if not next(_hitBlockPatchers) then
            if bedwars.BlockBreaker then
                bedwars.BlockBreaker.hitBlock = _sharedHitBlock
            end
            _sharedHitBlock = nil
        end
    end

    local FastBreak
    local Time
    local BedCheck
    local Blacklist
    local blocks
    local string_lower = string.lower
    local string_find = string.find
    local task_wait = task.wait
    local currentBlock = nil
    local oldHitBlock = nil
    local lastHotbarSlot = nil
    local bedCache = {}
    local blacklistCache = {}
    local lastCacheClean = 0
    local cacheCleanInterval = 5 
    
    local function isBed(block)
        if not block then return false end
        local cached = bedCache[block]
        if cached ~= nil then return cached end
        
        local result = false
        pcall(function()
            if collectionService:HasTag(block, 'bed') or (block.Parent and collectionService:HasTag(block.Parent, 'bed')) then
                result = true
            elseif string_find(string_lower(block.Name), 'bed', 1, true) then
                result = true
            end
        end)
        
        if result then bedCache[block] = true end
        return result
    end
    
    local cachedBlacklistLower = {}
    local function updateBlacklistCache()
        if not blocks or not blocks.ListEnabled then return end
        
        cachedBlacklistLower = {}
        for _, v in pairs(blocks.ListEnabled) do
            table.insert(cachedBlacklistLower, string_lower(v))
        end
    end
    
    local function isBlacklisted(block)
        if not block or #cachedBlacklistLower == 0 then return false end
        local cached = blacklistCache[block]
        if cached ~= nil then return cached end
        
        local name = string_lower(block.Name)
        local result = false
        for i = 1, #cachedBlacklistLower do
            if string_find(name, cachedBlacklistLower[i], 1, true) then
                result = true
                break
            end
        end
        
        blacklistCache[block] = result
        return result
    end
    
    local function shouldSkip(block)
        if not block then return false end
        if BedCheck and BedCheck.Enabled and isBed(block) then return true end
        if Blacklist and Blacklist.Enabled and isBlacklisted(block) then return true end
        return false
    end
    
    local lastBreakUpdate = 0
    local breakUpdateCooldown = 0.05
    local pendingUpdate = false
    
    local function updateBreakSpeed()
        if not FastBreak or not FastBreak.Enabled then return end
        local now = tick()
        if now - lastBreakUpdate < breakUpdateCooldown then
            pendingUpdate = true
            return
        end
        lastBreakUpdate = now
        pendingUpdate = false
        
        pcall(function()
            local cooldown = (shouldSkip(currentBlock)) and 0.3 or Time.Value
            bedwars.BlockBreakController.blockBreaker:setCooldown(cooldown)
        end)
    end
    
    FastBreak = vape.Categories.Blatant:CreateModule({
        Name = 'FastBreak',
        Function = function(callback)
            local aeroAlive = newRun(FastBreak)
            if callback then
                lastHotbarSlot = nil

				getgenv().registerHitBlockPatch('FastBreak', function(self, maid, raycastparams, ...)
					local block = nil
					pcall(function()
						local blockInfo = self.clientManager:getBlockSelector():getMouseInfo(1, {ray = raycastparams})
						if blockInfo and blockInfo.target and blockInfo.target.blockInstance then
							block = blockInfo.target.blockInstance
						end
					end)
					
					local currentSlot = store.inventory and store.inventory.hotbarSlot
					local slotChanged = currentSlot ~= lastHotbarSlot
					if slotChanged then
						lastHotbarSlot = currentSlot
					end

					if block ~= currentBlock or slotChanged then
						currentBlock = block
						updateBreakSpeed()
					end
					end)
                
                updateBlacklistCache()
                
                task.spawn(function()
                    while aeroAlive() do
                        if tick() - lastCacheClean > cacheCleanInterval then
                            lastCacheClean = tick()
                            bedCache = {}
                            blacklistCache = {}
                        end
                        if pendingUpdate then updateBreakSpeed() end
                        task_wait(0.05) 
                    end
                end)
			else
				pcall(function() bedwars.BlockBreakController.blockBreaker:setCooldown(0.3) end)
				getgenv().unregisterHitBlockPatch('FastBreak')
				currentBlock = nil
				lastHotbarSlot = nil
				bedCache, blacklistCache, cachedBlacklistLower = {}, {}, {}
			end
        end,
        Tooltip = 'mine faster'
    })
    
    Time = FastBreak:CreateSlider({
        Name = 'Break speed',
        Min = 0, Max = 0.3, Default = 0.25, Decimal = 100, Suffix = 'seconds',
        Function = function() updateBreakSpeed() end
    })
    
    BedCheck = FastBreak:CreateToggle({
        Name = 'Bed Check',
        Default = false,
        Tooltip = 'mining is normal when breaking beds',
        Function = function() bedCache = {}; updateBreakSpeed() end
    })
    
    Blacklist = FastBreak:CreateToggle({
        Name = 'Blacklist Blocks',
        Default = false,
        Tooltip = 'mining is normal for blacklisted blocks',
        Function = function(v)
            if blocks then blocks.Object.Visible = v end
            blacklistCache = {}
            if v then updateBlacklistCache() end
            updateBreakSpeed()
        end
    })
    
    blocks = FastBreak:CreateTextList({
        Name = 'Blacklisted Blocks',
        Placeholder = 'bed',
        Visible = false,
        Function = function()
            updateBlacklistCache()
            blacklistCache = {}
            updateBreakSpeed()
        end
    })
end)

run(function()
	local NoSlowdown
	local SophiaCheck
	local modifier
	local originalAdd
	local patchedAdd
	local savedSlow = setmetatable({}, {__mode = 'k'})

	local function respectFrozen()
		return SophiaCheck and SophiaCheck.Enabled and isFrozen(nil, 10)
	end

	local function removeSlow(data)
		if type(data) ~= 'table' then return false end

		local speed = tonumber(data.moveSpeedMultiplier)
		if not speed or speed >= 1 then return false end

		if savedSlow[data] == nil then
			savedSlow[data] = data.moveSpeedMultiplier
		end

		data.moveSpeedMultiplier = 1
		return true
	end

	local function restoreSlow()
		for data, speed in savedSlow do
			data.moveSpeedMultiplier = speed
		end

		table.clear(savedSlow)

		if modifier and type(modifier.updateModifiers) == 'function' then
			pcall(modifier.updateModifiers, modifier)
		end
	end

	NoSlowdown = vape.Categories.Blatant:CreateModule({
		Name = 'NoSlowdown',
		Function = function(enabled)
			if enabled then
				local sprint = bedwars.SprintController
				if not sprint then return end

				modifier = sprint:getMovementStatusModifier()
				if not modifier or type(modifier.addModifier) ~= 'function' then
					return
				end

				originalAdd = modifier.addModifier
				local savedAdd = originalAdd

				patchedAdd = function(self, data)
					if not respectFrozen() then
						removeSlow(data)
					end
					return savedAdd(self, data)
				end

				modifier.addModifier = patchedAdd

				if not respectFrozen() then
					local changed = false

					for key, value in modifier.modifiers or {} do
						local data = type(value) == 'table' and value or (type(key) == 'table' and key or nil)

						if data and removeSlow(data) then
							changed = true
						end
					end

					if changed and type(modifier.updateModifiers) == 'function' then
						pcall(modifier.updateModifiers, modifier)
					end
				end
			else
				if modifier and modifier.addModifier == patchedAdd then
					modifier.addModifier = originalAdd
				end

				restoreSlow()
				modifier = nil
				originalAdd = nil
				patchedAdd = nil
			end
		end,
		Tooltip = 'prevents slowing down when using items.'
	})

	SophiaCheck = NoSlowdown:CreateToggle({
		Name = 'Sophia Check',
		Default = false
	})
end)

run(function()
	local DamageBoost
	local stack
	local knockbackSpeed, knockbackBoost
	
	DamageBoost = vape.Categories.Blatant:CreateModule({
		Name = 'DamageBoost',
		Function = function(callback)
			if callback then
				DamageBoost:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
					if entitylib.isAlive and tick() > (stack or 0) and damageTable.entityInstance == lplr.Character and not (vape.Modules.LongJump and vape.Modules.LongJump.Enabled) then
						local horizontal = (damageTable.knockbackMultiplier and damageTable.knockbackMultiplier.horizontal or 0)
						knockbackSpeed = bedwars.KnockbackUtil.calculateKnockbackVelocity(Vector3.one, 1, {
							vertical = 0,
							horizontal = horizontal,
						}).Magnitude * (0.9 + (store.ping and store.ping.total or 0))
						stack = tick() + (knockbackSpeed / 45)
						knockbackBoost = tick() + (horizontal / 3.5)
					end
				end))
			end
		end,
		Tooltip = 'makes you go slightly faster when damaged'
	})
end)

run(function()
	local NoFall
	local Chance
	local voidParams = RaycastParams.new()
	voidParams.FilterType = Enum.RaycastFilterType.Exclude
	voidParams.IgnoreWater = true
	local lastVoidCheck = 0
	local cachedVoid = false

	local voidOffsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(2, 0, 0),
		Vector3.new(-2, 0, 0),
		Vector3.new(0, 0, 2),
		Vector3.new(0, 0, -2)
	}

	local function nearVoid(position)
		if not entitylib.isAlive then return false end
		local now = tick()
		if (now - lastVoidCheck) < 0.1 then
			return cachedVoid
		end
		lastVoidCheck = now
		voidParams.FilterDescendantsInstances = {entitylib.character.Character, gameCamera}

		local down = Vector3.new(0, -600, 0)
		for _, off in voidOffsets do
			if workspace:Raycast(position + off, down, voidParams) then
				cachedVoid = false
				return false
			end
		end

		cachedVoid = true
		return true
	end

	NoFall = vape.Categories.Blatant:CreateModule({
		Name = 'NoFall',
		Function = function(callback)
			if callback then
				NoFall:Clean(runService.Heartbeat:Connect(function(dt)
					if entitylib.isAlive and store.matchState == 1 then
						local root = entitylib.character.RootPart
						local v = root.Velocity

						if root.Velocity.Y < -35 and not nearVoid(root.Position) then
							if math.random(1, 100) <= Chance.Value then
								root.Velocity = Vector3.new(0,2.5,0)
								entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Landed)
								runService.PreRender:Wait()
								root.Velocity = v
							end
						end
					end
				end))

				NoFall:Clean(entitylib.Events.LocalAdded:Connect(function(char)
					local animator = char.Humanoid:WaitForChild('Animator', 1)
					if animator and NoFall.Enabled then
						task.wait(.5)
						NoFall:Toggle()
						NoFall:Toggle()
					end
				end))
			end
		end,
		Tooltip = 'take no fall damage'
	})

	Chance = NoFall:CreateSlider({
		Name = 'Chance',
		Min = 1,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
end)

run(function()
	local ProjectileAimbot
	local TargetPart
	local Targets
	local FOV
	local Range
	local OtherProjectiles
	local Blacklist
	local SortMethod
	local skidPAChargePercent
	local RandomHeadPercent
	local RandomTorsoPercent
	local DesirePAWorkMode
	local DesirePAHideCursor
	local DesirePACursorViewMode
	local DesirePACursorLimitBow
	local DesirePACursorShowGUI
	local cursorRenderConnection
	local lastGUIState = false
	local rayCheck = RaycastParams.new()
	rayCheck.FilterType = Enum.RaycastFilterType.Include
	local _rayMap = nil
	local function refreshRayCheck()
		local map = workspace:FindFirstChild('Map')
		if map ~= _rayMap or not map or not map.Parent then
			_rayMap = map
			if map and map.Parent then
				rayCheck.FilterDescendantsInstances = {map}
			else
				rayCheck.FilterType = Enum.RaycastFilterType.Exclude
				rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
				return
			end
			rayCheck.FilterType = Enum.RaycastFilterType.Include
		end
	end
	refreshRayCheck()
	local old
	local math_sqrt = math.sqrt
	local math_rad = math.rad
	local math_cos = math.cos
	local math_clamp = math.clamp
	local math_min = math.min
	local math_max = math.max
	local lockedRandomPart = nil
	local wasHovering = false
	local _paVelHistory = {}
	local CustomPredictions
	local PredictHorizontal
	local PredictVertical
	local PAFOVCircle
	local paFOVCircleDrawing = nil
	local AutoCharge
	local paFOVCircleConnection = nil

	local paFOVCircleDrawing = nil 
	local paFOVCircleConnection = nil

	local function runPAFOVCircle(call)
		if paFOVCircleConnection then
			paFOVCircleConnection:Disconnect()
			paFOVCircleConnection = nil
		end
		if paFOVCircleDrawing then
			paFOVCircleDrawing:Destroy()
			paFOVCircleDrawing = nil
		end
		if not call then return end

		paFOVCircleDrawing = Instance.new('Frame')
		paFOVCircleDrawing.Name = 'PAFOVCircle'
		paFOVCircleDrawing.BackgroundTransparency = 1
		paFOVCircleDrawing.AnchorPoint = Vector2.new(0.5, 0.5)
		paFOVCircleDrawing.Visible = false
		local stroke = Instance.new('UIStroke')
		stroke.Thickness = 1
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Parent = paFOVCircleDrawing
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = paFOVCircleDrawing
		paFOVCircleDrawing.Parent = vape.gui

		paFOVCircleConnection = runService.RenderStepped:Connect(function()
			if not paFOVCircleDrawing or not FOV or not FOV.Value then
				paFOVCircleDrawing.Visible = false
				return
			end

			local shouldShow = false
			if PAFOVCircle and PAFOVCircle.Enabled and ProjectileAimbot and ProjectileAimbot.Enabled then
				local tool = store.hand and store.hand.tool
				local itemType = tool and tool.Name or ""
				local itemMeta = bedwars.ItemMeta and bedwars.ItemMeta[itemType]
				if store.owlAiming or itemType == 'owl_orb' then
					shouldShow = true
				elseif itemMeta and itemMeta.projectileSource then
					local src = itemMeta.projectileSource
					local isArrow = src.ammoItemTypes and table.find(src.ammoItemTypes, 'arrow')
					local isHeadhunter = itemType:find('headhunter')
					if isArrow or isHeadhunter then
						shouldShow = true
					elseif OtherProjectiles and OtherProjectiles.Enabled then
						local projectileType = src.projectileType and (type(src.projectileType) == 'function' and src.projectileType('arrow') or src.projectileType) or ""
						local blacklisted = false
						for _, black in ipairs(Blacklist and Blacklist.ListEnabled or {}) do
							if tostring(projectileType):find(black) then
								blacklisted = true
								break
							end
						end
						if not blacklisted then
							shouldShow = true
						end
					end
				end
			end

			paFOVCircleDrawing.Visible = shouldShow

			if shouldShow then
				local mousePos
				if inputService.TouchEnabled then
					mousePos = gameCamera.ViewportSize / 2
				else
					local mp = inputService:GetMouseLocation()
					mousePos = Vector2.new(mp.X, mp.Y)
				end
				paFOVCircleDrawing.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)
				paFOVCircleDrawing.Size = UDim2.fromOffset(FOV.Value * 2, FOV.Value * 2)
			end
		end)
	end

	local function hasBowEquipped()
		if not store.hand or not store.hand.toolType then return false end
		return store.hand.toolType == 'bow' or store.hand.toolType == 'crossbow'
	end

	local function shouldHideCursor()
		if not DesirePAHideCursor or not DesirePAHideCursor.Enabled then return false end
		if DesirePACursorShowGUI and DesirePACursorShowGUI.Enabled and isGUIOpen() then return false end
		if DesirePACursorLimitBow and DesirePACursorLimitBow.Enabled and not hasBowEquipped() then return false end
		local inFirstPerson = isFirstPerson()
		if DesirePACursorViewMode then
			if DesirePACursorViewMode.Value == 'First Person' then return inFirstPerson
			elseif DesirePACursorViewMode.Value == 'Third Person' then return not inFirstPerson
			end
		end
		return true
	end

	local function updateCursor()
		pcall(function() inputService.MouseIconEnabled = not shouldHideCursor() end)
	end

	local function checkGUIState()
		local currentGUIState = isGUIOpen()
		if lastGUIState ~= currentGUIState then
			updateCursor()
			lastGUIState = currentGUIState
		end
	end

	local paLockedTarget = nil
	local paLockTime = 0
	local paLeadStart = 0
	local paVelSmooth = setmetatable({}, {__mode = 'k'})

	local function paValidLock(originPos)
		local t = paLockedTarget
		if not t then return nil end
		if tick() - paLockTime > 0.4 then return nil end
		if not t.Character or not t.Character.Parent then return nil end
		if not t.RootPart or not t.RootPart.Parent then return nil end
		local hp = t.Humanoid and t.Humanoid.Health or t.Health
		if type(hp) == 'number' and hp <= 0 then return nil end
		if (t.RootPart.Position - originPos).Magnitude > Range.Value then return nil end
		local _, visible = gameCamera:WorldToViewportPoint(t.RootPart.Position)
		if not visible then return nil end
		return t
	end

	local function shouldPAWork()
		if not DesirePAWorkMode then return true end
		local inFirstPerson = isFirstPerson()
		if DesirePAWorkMode.Value == 'First Person' then return inFirstPerson
		elseif DesirePAWorkMode.Value == 'Third Person' then return not inFirstPerson
		end
		return true
	end

	local function isBlacklisted(projectileName)
		if not OtherProjectiles or not OtherProjectiles.Enabled then
			local isTurret = projectileName:find('turret') ~= nil or projectileName:find('vulcan') ~= nil
			return not projectileName:find('arrow') and not isTurret and not projectileName:find('owl')
		end
		for _, black in ipairs(Blacklist and Blacklist.ListEnabled or {}) do
			if projectileName:find(black) then
				return true
			end
		end
		return false
	end

	local function pickRandomPart(character)
		local roll = math.random(1, 100)
		local headChance = RandomHeadPercent.Value
		local torsoChance = RandomTorsoPercent.Value
		if roll <= headChance then
			return character:FindFirstChild('Head') or character:FindFirstChild('HumanoidRootPart')
		elseif roll <= headChance + torsoChance then
			return character:FindFirstChild('UpperTorso') or character:FindFirstChild('HumanoidRootPart')
		else
			return character:FindFirstChild('HumanoidRootPart')
		end
	end

	local function getClosestPart(character, mousePos)
		local parts = {
			'HumanoidRootPart', 'Head', 'LeftHand', 'RightHand',
			'LeftLowerArm', 'RightLowerArm', 'LeftUpperArm', 'RightUpperArm',
			'LeftFoot', 'RightFoot', 'LeftLowerLeg', 'RightLowerLeg',
			'LeftUpperLeg', 'RightUpperLeg', 'LowerTorso', 'UpperTorso'
		}
		local camera = gameCamera
		local rayOrigin = camera.CFrame.Position
		local rayDir = camera:ScreenPointToRay(mousePos.X, mousePos.Y, 0).Direction
		local bestAngle = math.huge
		local bestPart = nil

		for _, partName in ipairs(parts) do
			local part = character:FindFirstChild(partName)
			if part then
				local dirToPart = (part.Position - rayOrigin).Unit
				local angle = math.acos(math_clamp(rayDir:Dot(dirToPart), -1, 1))
				if angle < bestAngle then
					bestAngle = angle
					bestPart = part
				end
			end
		end
		return bestPart or character:FindFirstChild('HumanoidRootPart')
	end

	ProjectileAimbot = vape.Categories.Blatant:CreateModule({
		Name = 'ProjectileAimbot',
		Function = function(callback)
			if callback then
				if SilentAim and SilentAim.Enabled then
					SilentAim:Toggle(false)
					notif('ProjectileAimbot', 'turned off SilentAim, they cant both run at once gng', 4)
				end
				if PAFOVCircle then
					runPAFOVCircle(PAFOVCircle.Enabled)
				end
				ProjectileAimbot:Clean(watchTargets())
				if DesirePAHideCursor and DesirePAHideCursor.Enabled and not cursorRenderConnection then
					cursorRenderConnection = runService.RenderStepped:Connect(function()
						checkGUIState()
						updateCursor()
					end)
					ProjectileAimbot:Clean(cursorRenderConnection)
				end

				old = bedwars.ProjectileController.calculateImportantLaunchValues
				bedwars.ProjectileController.calculateImportantLaunchValues = function(...)
					local self, projmeta, worldmeta, origin, shootpos = ...
					local originPos = entitylib.isAlive and (shootpos or (entitylib.character and entitylib.character.RootPart and entitylib.character.RootPart.Position)) or Vector3.zero
					if not originPos then return old(...) end

					local plr = entitylib.EntityMouse({
						Part = 'RootPart',
						Range = FOV.Value,
						Players = Targets.Players.Enabled,
						NPCs = (Targets.NPCs and Targets.NPCs.Enabled) or false,
						Wallcheck = Targets.Walls.Enabled,
						Sort = sortmethods[SortMethod.Value or 'Cursor'],
						Origin = originPos
					})
					if plr and plr ~= paLockedTarget then
						paLeadStart = tick()
					end
					if plr then
						paLockedTarget = plr
						paLockTime = tick()
					end

					if not plr then
						paLockedTarget = nil
						paLeadStart = 0
						wasHovering = false
						return old(...)
					end
					
					if not shouldPAWork() then
						wasHovering = false
						return old(...)
					end

					local targetBodyPart = nil
					if TargetPart.Value == 'Dynamic' then
						local tool = (typeof(origin) == 'Instance' and origin) or (store.hand and store.hand.tool)
						local itemType = tostring(tool and tool.Name or ""):lower()
						local isHH = itemType:find("headhunter") or tostring(projmeta.projectile or ""):find("headhunter")
						targetBodyPart = (isHH and plr.Character and plr.Character:FindFirstChild("Head")) or plr.RootPart
					elseif TargetPart.Value == 'RootPart' then
						targetBodyPart = plr.RootPart
					elseif TargetPart.Value == 'Head' then
						targetBodyPart = (plr.Character and plr.Character:FindFirstChild('Head')) or plr.RootPart
					elseif TargetPart.Value == 'Closest' then
						local mousePos = inputService.TouchEnabled and (gameCamera.ViewportSize / 2) or inputService:GetMouseLocation()
						targetBodyPart = plr.Character and getClosestPart(plr.Character, mousePos) or plr.RootPart
					elseif TargetPart.Value == 'Randomize' then
						if lockedRandomPart and lockedRandomPart.Parent ~= plr.Character then
							lockedRandomPart = nil
						end
						if plr.Character and (not lockedRandomPart or not lockedRandomPart.Parent) then
							lockedRandomPart = pickRandomPart(plr.Character)
						end
						targetBodyPart = lockedRandomPart or plr.RootPart
					else
						targetBodyPart = plr.RootPart
					end
					if not targetBodyPart then
						wasHovering = false
						return old(...)
					end
					local dist = (targetBodyPart.Position - originPos).Magnitude
					if dist > Range.Value then
						wasHovering = false
						return old(...)
					end
					local pos = shootpos or self:getLaunchPosition(origin)
					if not pos then
						wasHovering = false
						return old(...)
					end
					local projectileName = projmeta.projectile or ""
					if isBlacklisted(projectileName) then
						wasHovering = false
						return old(...)
					end
					refreshRayCheck()
					local meta = projmeta:getProjectileMeta()
					local overrides

					if meta.getProjectileOverridesFunction then
						pcall(function()
							overrides = meta.getProjectileOverridesFunction(lplr)
						end)
					end

					overrides = type(overrides) == 'table' and overrides or {}

					local predictionLifetime = tonumber(overrides.predictionLifetimeOverride) or tonumber(meta.predictionLifetimeSec)
					local normalLifetime = tonumber(overrides.lifetimeOverride) or tonumber(meta.lifetimeSec) or 3
					local lifetime = worldmeta and (predictionLifetime or normalLifetime) or normalLifetime
					local gravityMultiplier = tonumber(projmeta.gravityMultiplier) or 1
					local gravity = (tonumber(meta.gravitationalAcceleration) or 196.2) * gravityMultiplier

					local toolMeta = origin and bedwars.ItemMeta[origin.Name]
					local sourceMeta = toolMeta and toolMeta.projectileSource
					local maxDraw = tonumber(sourceMeta and sourceMeta.maxStrengthChargeSec)
						or tonumber(sourceMeta and sourceMeta.maxDrawDurationSeconds)
						or (tostring(projmeta.projectile):find('arrow') and 0.65 or 0.8)

					local paMinScalar = tonumber(sourceMeta and sourceMeta.minStrengthScalar) or 1
					local baseSpeed = tonumber(overrides.launchVelocityOverride) or tonumber(meta.launchVelocity) or 100
					local nativeValues = old(...)
					local projSpeed
					local customDrawDuration
					local offsetpos

					if nativeValues and typeof(nativeValues.positionFrom) == 'Vector3' then
						offsetpos = nativeValues.positionFrom
					else
						local safeOffset = projmeta.fromPositionOffset

						if typeof(safeOffset) ~= 'Vector3' then
							safeOffset = Vector3.new(0, 2, 0)
						end

						offsetpos = pos + safeOffset
					end

					if nativeValues and type(nativeValues.gravitationalAcceleration) == 'number' then
						gravity = nativeValues.gravitationalAcceleration
					end

					if AutoCharge.Enabled then
						local drawPct = math.clamp(skidPAChargePercent.Value / 100, 0, 1)

						projSpeed = baseSpeed * (paMinScalar + (1 - paMinScalar) * drawPct)
						customDrawDuration = maxDraw * drawPct
					else
						if nativeValues
							and typeof(nativeValues.initialVelocity) == 'Vector3'
							and nativeValues.initialVelocity.Magnitude > 0 then

							projSpeed = nativeValues.initialVelocity.Magnitude
						else
							local liveDraw = tonumber(projmeta.drawDurationSeconds) or 0
							local livePct = maxDraw > 0 and math.clamp(liveDraw / maxDraw, 0, 1) or 0

							projSpeed = baseSpeed * (paMinScalar + (1 - paMinScalar) * livePct)
						end

						customDrawDuration = nativeValues
							and tonumber(nativeValues.drawDurationSeconds)
							or tonumber(projmeta.drawDurationSeconds)
							or 0
					end
					local balloons = plr.Character and plr.Character:GetAttribute('InflatedBalloons')
					local playerGravity = workspace.Gravity
					if balloons and balloons > 0 then
						playerGravity = balloonGravity(balloons, plr.Character)
					end
					if plr.Character and plr.Character.PrimaryPart and plr.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
						playerGravity = 6
					end
					if plr.Player and plr.Player:GetAttribute('IsOwlTarget') then
						for _, owl in ipairs(collectionService:GetTagged('Owl')) do
							if owl:GetAttribute('Target') == plr.Player.UserId and owl:GetAttribute('Status') == 2 then
								playerGravity = 0
								break
							end
						end
					end
					local rawVel = plr.RootPart.AssemblyLinearVelocity or plr.RootPart.Velocity or Vector3.zero
					local aimTarget = targetBodyPart.Position
					if tostring(projmeta.projectile):find('fireball') then
						aimTarget = splashAimPoint(plr.RootPart, plr.HipHeight) or aimTarget
					end
					local solverVelocity = projmeta.projectile == 'telepearl' and Vector3.zero or rawVel
					local tAirborne = (plr.Humanoid and plr.Humanoid.FloorMaterial == Enum.Material.Air) or math.abs(rawVel.Y) > 0.01
					local tJump = plr.Jumping and 42.6 or nil
					local horizLead = 1
					local vertLead = 1
					if CustomPredictions and CustomPredictions.Enabled and projmeta.projectile ~= 'telepearl' then
						horizLead = PredictHorizontal.Value / 100
						vertLead = PredictVertical.Value / 100
					end
					if horizLead ~= 1 or vertLead ~= 1 then
						solverVelocity = Vector3.new(
							solverVelocity.X * horizLead,
							solverVelocity.Y * vertLead,
							solverVelocity.Z * horizLead
						)
					end

					local leadAlpha = nil
					local launchOrigin = offsetpos
					local solveOrigin = offsetpos
					local calc, _, flightTime = prediction.SolveTrajectory(
						solveOrigin, projSpeed, gravity,
						aimTarget,
						solverVelocity,
						playerGravity, plr.HipHeight,
						tJump,
						rayCheck,
						tAirborne,
						plr.RootPart.Position,
						plr.RootPart,
						nil,
						true,
						leadAlpha
					)

					if calc then
						local bow = bedwars.BowConstantsTable or {}
						local rel = sourceMeta and sourceMeta.relativeOverride
						local rx, ry, rz = bow.RelX or 0.8, bow.RelY or -0.6, bow.RelZ or 0
						if type(rel) == 'table' then
							rx, ry, rz = rel.relX or 0, rel.relY or 0, rel.relZ or 0
						end
						local function aimFrom(offset)
							local point = aimTarget + (typeof(offset) == 'Vector3' and offset or Vector3.new(0, offset, 0))
							local c1, _, f1 = prediction.SolveTrajectory(solveOrigin, projSpeed, gravity, point, solverVelocity, playerGravity, plr.HipHeight, tJump, rayCheck, tAirborne, plr.RootPart.Position, plr.RootPart, nil, true, leadAlpha)
							if not c1 then return nil end
							local s1 = prediction.GetSpawnPosition(solveOrigin, c1, rx, ry, rz)
							local c2, _, f2 = prediction.SolveTrajectory(s1, projSpeed, gravity, point, solverVelocity, playerGravity, plr.HipHeight, tJump, rayCheck, tAirborne, plr.RootPart.Position, plr.RootPart, nil, true, leadAlpha)
							if c2 and f2 then
								c1 = solveOrigin + (c2 - s1)
								f1 = f2
								s1 = prediction.GetSpawnPosition(solveOrigin, c1, rx, ry, rz)
							end
							return c1, f1, s1
						end
						local c0, f0, s0 = aimFrom(0)
						if c0 and f0 then
							calc, flightTime = c0, f0
							if not worldmeta and not prediction.IsTrajectoryClear(s0, (c0 - solveOrigin).Unit * projSpeed, gravity, f0 * 0.97, rayCheck) then
								local los = (aimTarget - solveOrigin) * Vector3.new(1, 0, 1)
								local side = los.Magnitude > 0.01 and Vector3.new(-los.Z, 0, los.X).Unit or Vector3.new(1, 0, 0)
								local up = Vector3.new(0, 1, 0)
								for _, offset in {up * 0.8, up * -0.8, side * 0.9, side * -0.9, up * 1.6, up * -1.6, side * 0.9 + up * 1.2, side * -0.9 + up * 1.2, up * 2.1, up * -2.4, side * 0.9 - up * 1.2, side * -0.9 - up * 1.2} do
									local c3, f3, s3 = aimFrom(offset)
									if c3 and f3 and prediction.IsTrajectoryClear(s3, (c3 - solveOrigin).Unit * projSpeed, gravity, f3 * 0.97, rayCheck) then
										calc, flightTime = c3, f3
										break
									end
								end
							end
						end
					end
					local returnDist = tonumber(overrides.returnDistanceOverride) or tonumber(meta.returnDistance)
					if calc and flightTime and flightTime <= lifetime and (not returnDist or projSpeed * flightTime <= returnDist - 2) then
						paLockedTarget = plr
						paLockTime = tick()

						if targetinfo and targetinfo.Targets then
							targetinfo.Targets[plr] = tick() + 1
						end

						wasHovering = false
						return {
							initialVelocity = CFrame.lookAt(solveOrigin, calc).LookVector * projSpeed,
							positionFrom = launchOrigin,
							deltaT = lifetime,
							gravitationalAcceleration = gravity,
							drawDurationSeconds = customDrawDuration
						}
					end
					wasHovering = false
					return old(...)
				end
			else
				bedwars.ProjectileController.calculateImportantLaunchValues = old
				paLockedTarget = nil
				paLeadStart = 0
				wasHovering = false
				lockedRandomPart = nil
				table.clear(_paVelHistory)
				if cursorRenderConnection then
					cursorRenderConnection:Disconnect()
					cursorRenderConnection = nil
				end
				runPAFOVCircle(false)
				pcall(function() inputService.MouseIconEnabled = true end)
				task.defer(function()
					pcall(function() inputService.MouseIconEnabled = true end)
					pcall(function() game:GetService('UserInputService').MouseIconEnabled = true end)
				end)
			end
		end,
		Tooltip = 'helps your shitty ass aim'
	})

	Targets = ProjectileAimbot:CreateTargets({
		Players = true,
		NPCs = true,
		Walls = true
	})

	TargetPart = ProjectileAimbot:CreateDropdown({
		Name = 'Part',
		List = {'Dynamic', 'RootPart', 'Head', 'Closest', 'Randomize'},
		Default = 'RootPart',
		Function = function()
			lockedRandomPart = nil
			wasHovering = false
		end
	})

	SortMethod = ProjectileAimbot:CreateDropdown({
		Name = 'Sort Method',
		List = getSortList({'Distance', 'Damage', 'Cursor'}),
		Default = 'Cursor',
	})

	DesirePAWorkMode = ProjectileAimbot:CreateDropdown({
		Name = 'PA Work Mode',
		List = {'First Person', 'Third Person', 'Both'},
		Default = 'Both',
	})

	Range = ProjectileAimbot:CreateSlider({
		Name = 'Range',
		Min = 10,
		Max = 500,
		Default = 100,
	})

	FOV = ProjectileAimbot:CreateSlider({
		Name = 'FOV',
		Min = 1,
		Max = 1000,
		Default = 300,
	})

	PAFOVCircle = ProjectileAimbot:CreateToggle({
		Name = 'FOV Circle',
		Function = function(call)
			runPAFOVCircle(call)
		end
	})

	RandomHeadPercent = ProjectileAimbot:CreateSlider({
		Name = 'Head Chance',
		Min = 0,
		Max = 100,
		Default = 50,
		Darker = true,
		Visible = false
	})

	RandomTorsoPercent = ProjectileAimbot:CreateSlider({
		Name = 'Torso Chance',
		Min = 0,
		Max = 100,
		Default = 50,
		Darker = true,
		Visible = false,
		Function = function(val)
			if RandomHeadPercent and (RandomHeadPercent.Value + val) > 100 then
				notif('ProjectileAimbot', 'head or torso chance is more than 100% so root part will never be picked..', 3)
			end
		end
	})

	local function updateRandomizeVisibility()
		local vis = (TargetPart.Value == 'Randomize')
		RandomHeadPercent.Object.Visible = vis
		RandomTorsoPercent.Object.Visible = vis
	end
	if TargetPart.AddHook then
		TargetPart:AddHook(updateRandomizeVisibility)
	end
	updateRandomizeVisibility()

	DesirePAHideCursor = ProjectileAimbot:CreateToggle({
		Name = 'Hide Cursor',
		Default = false,
		Tooltip = 'Hides the cursor while aiming',
		Function = function(callback)
			if DesirePACursorViewMode then DesirePACursorViewMode.Object.Visible = callback end
			if DesirePACursorLimitBow then DesirePACursorLimitBow.Object.Visible = callback end
			if DesirePACursorShowGUI then DesirePACursorShowGUI.Object.Visible = callback end
			if callback and ProjectileAimbot.Enabled then
				if not cursorRenderConnection then
					cursorRenderConnection = runService.RenderStepped:Connect(function()
						checkGUIState()
						updateCursor()
					end)
				end
				updateCursor()
			else
				if cursorRenderConnection then
					cursorRenderConnection:Disconnect()
					cursorRenderConnection = nil
				end
				pcall(function() inputService.MouseIconEnabled = true end)
				task.defer(function()
					pcall(function() inputService.MouseIconEnabled = true end)
					pcall(function() game:GetService('UserInputService').MouseIconEnabled = true end)
				end)
			end
		end
	})

	DesirePACursorViewMode = ProjectileAimbot:CreateDropdown({
		Name = 'Cursor View Mode',
		List = {'First Person', 'Third Person', 'Both'},
		Default = 'First Person',
		Darker = true,
		Visible = false,
		Function = function()
			if ProjectileAimbot.Enabled and DesirePAHideCursor.Enabled then
				updateCursor()
			end
		end
	})

	DesirePACursorLimitBow = ProjectileAimbot:CreateToggle({
		Name = 'Limit to Bow',
		Darker = true,
		Visible = false,
		Function = function()
			if ProjectileAimbot.Enabled and DesirePAHideCursor.Enabled then
				updateCursor()
			end
		end
	})

	DesirePACursorShowGUI = ProjectileAimbot:CreateToggle({
		Name = 'Show on GUI',
		Darker = true,
		Visible = false,
		Function = function()
			if ProjectileAimbot.Enabled and DesirePAHideCursor.Enabled then
				updateCursor()
			end
		end
	})

	OtherProjectiles = ProjectileAimbot:CreateToggle({
		Name = 'Other Projectiles',
		Default = true,
		Function = function(call)
			if Blacklist then Blacklist.Object.Visible = call end
		end
	})

	Blacklist = ProjectileAimbot:CreateTextList({
		Name = 'Blacklist',
		Darker = true,
		Default = {'telepearl'},
		Visible = OtherProjectiles.Enabled
	})

	CustomPredictions = ProjectileAimbot:CreateToggle({
		Name = 'Custom Predictions',
		Default = false,
		Tooltip = 'lets u control how much it leads the target urself',
		Function = function(callback)
			if PredictHorizontal then PredictHorizontal.Object.Visible = callback end
			if PredictVertical then PredictVertical.Object.Visible = callback end
		end
	})
	PredictHorizontal = ProjectileAimbot:CreateSlider({
		Name = 'Horizontal',
		Min = 0,
		Max = 300,
		Default = 100,
		Suffix = '%',
		Darker = true,
		Visible = false
	})
	PredictVertical = ProjectileAimbot:CreateSlider({
		Name = 'Vertical',
		Min = 0,
		Max = 300,
		Default = 100,
		Suffix = '%',
		Darker = true,
		Visible = false
	})
	AutoCharge = ProjectileAimbot:CreateToggle({
		Name = "AutoCharge",
		Default = true,
		Function = function(v)
			if skidPAChargePercent and skidPAChargePercent.Object then skidPAChargePercent.Object.Visible = v end
		end
	})
	skidPAChargePercent = ProjectileAimbot:CreateSlider({
		Name = 'Charge Percent',
		Min = 1,
		Max = 100,
		Default = 100,
	})
end)

local Attacking
run(function()
	local Killaura
	local Targets
	local Sort
	local SwingRange
	local AttackRange
	local AngleSlider
	local Swing
	local ContinueSwinging
	local ContinueSwingTime
	local GUI
	local Limit
	local LegitAura
	local FaceTarget
	local AttackCheck
	local kitChecks
	local AttackRemote
	local MouseOnly
	local lastTargetTime = 0
	local AnimDelay = tick()
	local FROZEN_THRESHOLD = 10
	local SERVER_REACH = 14.399
	local HIT_PERIOD = 0.296
	local preciseRemainder = 0
	local preciseTimestamp = tick()
	local SwordTiming = {
		SafeSpacing = 0.295,
		HighSpacing = 0.2855,
		HitFloor = 0.292,
		GapFloor = 0.2945,
		CooldownCorrection = (0.017999999225139618 / 10) + 0.013412,
	}
	local WeaponSpacing = {
		[0.21] = 0.229,
		[0.25] = 0.249,
		[0.35] = 0.345,
		[0.4] = 0.341,
		[0.6] = 0.63,
	}
	local function quantize240(value)
		return math.ceil(value / (1 / 240)) * (1 / 240)
	end
	local function updatePreciseClock()
		local now = tick()
		if now - preciseTimestamp >= 0.25 then
			preciseRemainder = 0
			preciseTimestamp = now
		end
		local elapsed = now - preciseTimestamp
		local steps = math.floor(elapsed / (1 / 240))
		preciseRemainder = math.max(preciseRemainder, steps * (1 / 240))
		return preciseRemainder
	end
	function SwordTiming.Calculate(Speed, HighMode, DynamicDelay, Budget, Hits)
		local Stock = Speed == 0.3
		local Normal = (HighMode == 'Advanced Mode' or HighMode == 'Dynamic') and SwordTiming.HighSpacing or SwordTiming.SafeSpacing
		local Spacing = Stock and Normal or WeaponSpacing[Speed] or Speed + 0.03
		if HighMode == 'Dynamic' and DynamicDelay then
			Spacing = math.max(Spacing * (DynamicDelay / 100), Budget or 0)
		end
		if Hits and Hits ~= 35 then Spacing = math.max(Spacing, 10 / math.max(Hits - 1, 1)) end
		Spacing = math.max(Spacing, Budget or 0)
		local Scale = Spacing / (Stock and Normal or SwordTiming.SafeSpacing)
		local Gap = (Scale < 1 and SwordTiming.GapFloor or SwordTiming.HitFloor) * Scale
		if Stock and (HighMode == 'Advanced Mode' or HighMode == 'Dynamic') then
			Gap = math.max(Gap, SwordTiming.GapFloor, Budget or 0)
		end
		return Spacing, Scale, Gap, math.max(Speed - SwordTiming.CooldownCorrection, 0), Stock
	end
	local kaPeriod = 0.296
	local kaLastSrv = 0
	local oldSwingBuffer
	task.spawn(function()
		task.wait()
		local _remotes = getgenv().remotes or remotes
		pcall(function()
			AttackRemote = bedwars.Client:Get(_remotes.AttackEntity).instance
		end)
	end)

	local furyUtil = {}
	task.spawn(function()
		pcall(function()
			local ts = replicatedStorage.TS
			furyUtil.status = require(ts['status-effect']['status-effect-util']).StatusEffectUtil
			furyUtil.kind = require(ts['status-effect']['status-effect-type']).StatusEffectType
			furyUtil.mult = require(ts.balance['black-marketeer-balance']).BlackMarketeerBalance.FURY_POTION_ATTACK_SPEED_MULTIPLIER
		end)
	end)

    local function furyMultiplier()
        if furyUtil.status then
            local ok, active = pcall(function()
                return furyUtil.status:isActive(lplr.Character, furyUtil.kind.FURY_POTION)
            end)
            if ok and active and type(furyUtil.mult) == 'number' and furyUtil.mult > 0 then
                return furyUtil.mult > 1 and (1 / furyUtil.mult) or furyUtil.mult
            end
        end
        local char = lplr.Character
        if char and (char:GetAttribute("FuryPotion") or char:GetAttribute("Fury")) then
            return 0.5
        end
        return 1
    end

    local function getAttackDelay(meta)
        local Speed = meta.sword and meta.sword.attackSpeed or 0.3
        local Spacing = SwordTiming.Calculate(Speed, 'Dynamic', 50, 0, 35)
        return quantize240(Spacing * furyMultiplier())
    end

	local function playSwingEffect(info)
		local fury = furyMultiplier()
		local effectSpeed = (info.sword.respectAttackSpeedForEffects and info.sword.attackSpeed or 0.11) * fury
		local minDelay = fury < 1 and 0.25 or 0.1111111111111111
		AnimDelay = tick() + math.max(effectSpeed, minDelay)
		pcall(function()
			bedwars.SwordController:playSwordEffect(info, false)
			if info.displayName and info.displayName:find(' Scythe') then
				bedwars.ScytheController:playLocalAnimation()
			end
		end)
	end

	local function shouldContinueSwinging()
		if not ContinueSwinging or not ContinueSwinging.Enabled then return false end
		if not ContinueSwingTime or lastTargetTime <= 0 then return false end
		return tick() - lastTargetTime <= ContinueSwingTime.Value
	end

	local function FireAttackRemote(weapon, entityInstance, selfPos, targetPos)
		if not AttackRemote then return false end

		local delta = (targetPos - selfPos).Magnitude
		if delta < 0.01 then return false end

		local dir = CFrame.lookAt(selfPos, targetPos).LookVector
		local pos = selfPos + dir * math.max(delta - SERVER_REACH, 0)

		AttackRemote:FireServer({
			weapon = weapon,
			chargedAttack = {chargeRatio = 0},
			entityInstance = entityInstance,
			validate = {
				raycast = {
					cameraPosition = {value = pos},
					cursorDirection = {value = dir}
				},
				targetPosition = {value = targetPos},
				selfPosition = {value = pos}
			}
		})
		return true
	end

	local _adCacheSword = nil
	local _adCacheMeta = nil
	local _adCacheTime = 0

	local function isMeleeWeapon(toolName)
		if not toolName then return false end
		local lower = toolName:lower()
		if lower:find('hammer') or lower:find('tinker') or lower:find('chainsaw') or lower:find('sword') or lower:find('blade') or lower:find('scythe') or lower:find('dagger') or lower:find('axe') then
			return true
		end
		local meta = bedwars.ItemMeta and bedwars.ItemMeta[toolName]
		return meta and meta.sword ~= nil
	end

	local function computeAttackData()
		if not entitylib.isAlive then return false end

		if MouseOnly and MouseOnly.Enabled and not inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return false end

		local casting = lplr:GetAttribute('IsCasting')
		if casting ~= nil and casting ~= false and casting ~= 0 and casting ~= '' then
			if casting == true then return false end
			if type(casting) == 'number' and casting > workspace:GetServerTimeNow() then return false end
		end

		if bedwars.SwordController and bedwars.SwordController.disableSwingState then return false end

		local stunned = lplr.Character and lplr.Character:GetAttribute('StunnedUntilTime')
		if stunned and stunned > workspace:GetServerTimeNow() then return false end

		if AttackCheck and AttackCheck.Enabled then
			if kitChecks then
				for _, check in pairs(kitChecks) do
					local ok, res = pcall(check)
					if ok and res then return false end
				end
			end

			if tick() - (store.silasAbilityTime or 0) < 2.2 then return false end
			if tick() - (store.terraStompTime or 0) < 0.7 then return false end
			if tick() - (store.terraKickTime or 0) < 0.5 then return false end
		end

		if GUI and GUI.Enabled then
			if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then return false end
			if vape.IsGuiOpen and vape:IsGuiOpen() then return false end
		end

		local sword = store.hand
		if not sword or not sword.tool or not isMeleeWeapon(sword.tool.Name) then
			if not (Limit and Limit.Enabled) then
				sword = store.tools.sword
			else
				sword = nil
			end
		end
		if not sword or not sword.tool then return false end

		local meta = bedwars.ItemMeta[sword.tool.Name]
		if not meta then return false end

		if Limit and Limit.Enabled then
			if not isMeleeWeapon(sword.tool.Name) or (bedwars.DaoController and bedwars.DaoController.chargingMaid) then
				return false
			end
		end

		if LegitAura and LegitAura.Enabled then
			local lastSwing = bedwars.SwordController and bedwars.SwordController.lastSwing
			if not lastSwing or (tick() - lastSwing) > 0.25 then return false end
		end

		return sword, meta
	end

	local function getAttackData()
		local now = os.clock()
		if now - _adCacheTime < 0.02 and _adCacheSword then
			return _adCacheSword, _adCacheMeta
		end
		_adCacheTime = now
		local sword, meta = computeAttackData()
		_adCacheSword = sword
		_adCacheMeta = meta
		return sword, meta
	end

	local function resetSwordCooldown()
		if bedwars.SwordController then
			bedwars.SwordController.lastAttack = 0
			bedwars.SwordController.lastSwing = 0
			if bedwars.SwordController.lastChargedAttackTimeMap then
				for weaponName in pairs(bedwars.SwordController.lastChargedAttackTimeMap) do
					bedwars.SwordController.lastChargedAttackTimeMap[weaponName] = 0
				end
			end
		end
	end

	local function setSwingBuffer(on)
		pcall(function()
			local consts = require(replicatedStorage.TS.combat['combat-constant']).SwordsConstants
			if table.isfrozen(consts) and setreadonly then
				setreadonly(consts, false)
			end
			if on then
				if oldSwingBuffer == nil then
					oldSwingBuffer = consts.swordSwingBufferMultiplier
				end
				consts.swordSwingBufferMultiplier = 0
			elseif oldSwingBuffer ~= nil then
				consts.swordSwingBufferMultiplier = oldSwingBuffer
				oldSwingBuffer = nil
			end
		end)
	end

	local _graceTarget = nil
	local _graceUntil = 0
	local _fastAcqTime = 0
	local _fastAcqRes = nil

	local function withinAngle(v)
		if not AngleSlider or AngleSlider.Value >= 360 then return true end
		if not v or not v.RootPart then return false end
		local root = entitylib.character and entitylib.character.RootPart
		if not root then return true end
		local flatLV = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local facing = flatLV.Magnitude > 0.001 and flatLV.Unit or root.CFrame.RightVector
		local flat = (v.RootPart.Position - root.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= 1 then return true end
		return math.acos(math.clamp(facing:Dot(flat.Unit), -1, 1)) <= math.rad(AngleSlider.Value) / 2
	end

	local function inReach(v)
		local root = entitylib.character and entitylib.character.RootPart
		if not root or not v or not v.RootPart then return false end
		return (v.RootPart.Position - root.Position).Magnitude <= AttackRange.Value
	end

	local function aliveTarget(v)
		if not v or not v.RootPart then return false end
		local char = v.Character
		if not char or not char.Parent then return false end
		if v.Health ~= nil and v.Health <= 0 then return false end
		return true
	end

	local function resolveTarget()
		local v = store.KillauraTarget
		if aliveTarget(v) and withinAngle(v) and inReach(v) then
			_graceTarget = v
			_graceUntil = tick() + 0.4
			return v
		end
		if _graceTarget and tick() < _graceUntil then
			local g = _graceTarget
			if aliveTarget(g) and inReach(g) then
				return g
			end
		end
		local now = tick()
		if (now - _fastAcqTime) < 0.03 and _fastAcqRes then
			if not (aliveTarget(_fastAcqRes) and withinAngle(_fastAcqRes) and inReach(_fastAcqRes)) then return nil end
			return _fastAcqRes
		end
		_fastAcqTime = now
		_fastAcqRes = nil
		local list = entitylib.AllPosition({
			Range = AttackRange.Value,
			Wallcheck = Targets.Walls.Enabled or nil,
			Part = 'RootPart',
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled,
			Limit = 5,
			Sort = sortmethods[Sort.Value] or sortmethods['Distance']
		})
		for _, ent in list do
			if withinAngle(ent) then
				_fastAcqRes = ent
				break
			end
		end
		return _fastAcqRes
	end

	local function attemptFire()
		local v = resolveTarget()
		if not v then return false end

		local sword, meta = getAttackData()
		if not sword or not meta then return false end

		local weaponInst = sword.tool
		pcall(function()
			local inv = replicatedStorage:FindFirstChild('Inventories')
			local mine = inv and inv:FindFirstChild(lplr.Name)
			local w = mine and mine:FindFirstChild(sword.tool.Name)
			if w then weaponInst = w end
		end)

		local char = lplr.Character
		if not char or not char.PrimaryPart then return false end
		local tchar = v.Character
		if not tchar or not tchar.PrimaryPart then return false end
		local selfPos = entitylib.character.RootPart.Position
		local targetPos = tchar.PrimaryPart.Position
		local dist = (targetPos - selfPos).Magnitude
		if dist > AttackRange.Value then return false end

		if sword.tool.Name:find('summoner_claw') then
			pcall(function() KaidaController:request(tchar) end)
			return false
		end

		if not FireAttackRemote(weaponInst, tchar, selfPos, targetPos) then
			return false
		end

		local srvNow = workspace:GetServerTimeNow()
		store.attackReach = (dist * 100) // 1 / 100
		store.attackReachUpdate = tick() + 1

		if kaLastSrv > 0 then
			kaLastSrv = kaLastSrv + kaPeriod
			if kaLastSrv < srvNow then
				kaLastSrv = srvNow
			end
		else
			kaLastSrv = srvNow
		end

		if bedwars.SwordController then
			bedwars.SwordController.lastAttack = srvNow
		end
		return true
	end

	local killauraFireLoop

	local function startKillauraFireLoop()
		if killauraFireLoop then return end
		kaPeriod = HIT_PERIOD
		kaLastSrv = workspace:GetServerTimeNow() - kaPeriod
		killauraFireLoop = task.spawn(function()
			while Killaura and Killaura.Enabled do
				runService.Heartbeat:Wait()
				local sword, meta = getAttackData()
				if sword and meta then
					kaPeriod = getAttackDelay(meta)
				else
					kaPeriod = HIT_PERIOD
				end
				updatePreciseClock()
				local heartbeatDt = 1 / 60
				local target = kaPeriod - math.min(heartbeatDt * 0.5, kaPeriod * 0.06)
				if (workspace:GetServerTimeNow() - kaLastSrv) >= target then
					pcall(attemptFire)
				end
			end
		end)
	end

	local function stopKillauraFireLoop()
		if killauraFireLoop then
			pcall(task.cancel, killauraFireLoop)
			killauraFireLoop = nil
		end
		_graceTarget = nil
		_graceUntil = 0
		_fastAcqTime = 0
		_fastAcqRes = nil
	end

	Killaura = vape.Categories.Blatant:CreateModule({
		Name = 'Killaura',
		Function = function(callback)
			local originalMobileVisible = true
			if callback then
				if inputService.TouchEnabled then
					originalMobileVisible = lplr.PlayerGui.MobileUI['2'].Visible
				end
				resetSwordCooldown()
				lastTargetTime = 0
				startKillauraFireLoop()
				if inputService.TouchEnabled then
					pcall(function()
						lplr.PlayerGui.MobileUI['2'].Visible = Limit.Enabled
					end)
				end

				setSwingBuffer(true)
				local _gatherCache = nil
				local _gatherCacheTime = 0
				local function gatherTargets()
					if _gatherCache and (tick() - _gatherCacheTime) < 0.05 then
						return _gatherCache[1], _gatherCache[2]
					end

					local walls = Targets.Walls.Enabled or nil
					local players = Targets.Players.Enabled
					local npcs = Targets.NPCs.Enabled
					local sort = sortmethods[Sort.Value]

					local function buildList(range)
						return entitylib.AllPosition({Range = range, Wallcheck = walls, Part = 'RootPart', Players = players, NPCs = npcs, Limit = 1, Sort = sort})
					end

					local attackPlrs = buildList(AttackRange.Value)
					local swingPlrs = AttackRange.Value == SwingRange.Value and attackPlrs or buildList(SwingRange.Value)
					_gatherCache = {swingPlrs, attackPlrs}
					_gatherCacheTime = tick()
					return swingPlrs, attackPlrs
				end

				local _cachedSwordType

				repeat
					updatePreciseClock()

					if AttackCheck and AttackCheck.Enabled then
						local triggered = false
						local stunTime = lplr.Character and lplr.Character:GetAttribute('StunnedUntilTime')
						if stunTime and stunTime > workspace:GetServerTimeNow() then triggered = true end
						if not triggered and kitChecks then
							for _, check in pairs(kitChecks) do
								local ok, res = pcall(check)
								if ok and res then triggered = true break end
							end
						end
						if triggered then
							Attacking = false
							getgenv().Attacking = false
							store.KillauraTarget = nil
							_graceUntil = 0
							task.wait(0.3)
							continue
						end
					end

					local blade, info = getAttackData()
					if not blade then
						if Attacking then
							Attacking = false
							getgenv().Attacking = false
							store.KillauraTarget = nil
						end
						task.wait(0.05)
						continue
					end

					local marked = {}
					if blade and entitylib.isAlive then
						local swordName = blade.tool.Name
						if swordName ~= _cachedSwordType then
							_cachedSwordType = swordName
							resetSwordCooldown()
							AnimDelay = 0
						end

						local selfpos = entitylib.character.RootPart.Position
						local flatLV = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
						local localfacing = flatLV.Magnitude > 0.001 and flatLV.Unit or entitylib.character.RootPart.CFrame.RightVector
						local maxAngle = math.rad(AngleSlider.Value) / 2
						local swingPlrs, attackPlrs = gatherTargets()
						local hasValidSwingTargets = false
						local hasValidAttackTargets = false
						local chosen = nil

						for _, v in swingPlrs do
							if withinAngle(v) then
								hasValidSwingTargets = true
								table.insert(marked, v)
							end
						end

						for _, v in attackPlrs do
							if withinAngle(v) then
								hasValidAttackTargets = true
								if not chosen then chosen = v end
								if not table.find(marked, v) then
									table.insert(marked, v)
								end
							end
						end

						if hasValidSwingTargets or hasValidAttackTargets then
							lastTargetTime = tick()
						end

						if not hasValidSwingTargets and not hasValidAttackTargets and Attacking then
							Attacking = false
							getgenv().Attacking = false
							store.KillauraTarget = nil
						end

						local shouldSwing = hasValidSwingTargets or hasValidAttackTargets
						local isLegitAura = LegitAura and LegitAura.Enabled

						if shouldSwing or isLegitAura then
							if chosen then
								if not Attacking then
									Attacking = true
									getgenv().Attacking = true
								end
								store.KillauraTarget = chosen
								store.kaTargetAt = tick()
								targetinfo.Targets[chosen] = tick() + 1
							end

							if not Swing.Enabled and AnimDelay < tick() and store.hand and store.hand.tool == blade.tool then
								playSwingEffect(info)
								if vape.ThreadFix then
									setthreadidentity(8)
								end
							end
						end
					end

					if not Attacking and blade and info and shouldContinueSwinging() then
						Attacking = true
						getgenv().Attacking = true
						if not Swing.Enabled and AnimDelay < tick() then
							playSwingEffect(info)
						end
					end

					if FaceTarget.Enabled and marked[1] then
						local look = marked[1].RootPart.Position * Vector3.new(1, 0, 1)
						local myRoot = entitylib.character.RootPart
						myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(look.X, myRoot.Position.Y + 0.001, look.Z))
					end
                    runService.Heartbeat:Wait()
                until not Killaura.Enabled
			else
				stopKillauraFireLoop()
				setSwingBuffer(false)
				store.kaSwingOnly = false
				lastTargetTime = 0
				store.KillauraTarget = nil
				if inputService.TouchEnabled then
					pcall(function()
						lplr.PlayerGui.MobileUI['2'].Visible = originalMobileVisible
					end)
				end
				Attacking = false
				getgenv().Attacking = false
			end
		end,
		Tooltip = 'hits ppl around u without aimin at em'
	})

	Targets = Killaura:CreateTargets({
		Players = true,
		NPCs = true
	})
	local modes = {'Damage', 'Distance'}
	for name in sortmethods do
		if not table.find(modes, name) then
			table.insert(modes, name)
		end
	end
	SwingRange = Killaura:CreateSlider({
		Name = 'swing range',
		Min = 1,
		Max = 24,
		Default = 20,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Killaura.ExtraText = function()
		local range = AttackRange and AttackRange.Value or 0
		local target = store.KillauraTarget
		local root = entitylib.isAlive and entitylib.character and entitylib.character.RootPart

		if root and target and target.RootPart then
			local distance = (target.RootPart.Position - root.Position).Magnitude
			return string.format('%s  %.1f studs', tostring(range), distance)
		end

		return tostring(range)
	end
	AttackRange = Killaura:CreateSlider({
		Name = 'attack range',
		Min = 1,
		Max = 22,
		Default = 22,
		Function = function()
			pcall(function() vape:UpdateTextGUI() end)
		end,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	AngleSlider = Killaura:CreateSlider({
		Name = 'max angle',
		Min = 1,
		Max = 360,
		Default = 360
	})
	Sort = Killaura:CreateDropdown({
		Name = 'target mode',
		List = modes
	})
	MouseOnly = Killaura:CreateToggle({
		Name = 'need mouse down',
		Tooltip = 'only hits while u holdin click'
	})
	Swing = Killaura:CreateToggle({
		Name = 'no swing',
		Tooltip = 'hides ur sword swing'
	})
	GUI = Killaura:CreateToggle({
		Name = 'gui check',
		Tooltip = 'wont hit while a menu is open'
	})
	FaceTarget = Killaura:CreateToggle({
		Name = 'face target',
		Tooltip = 'turns ur body to who ur hittin'
	})
	Limit = Killaura:CreateToggle({
		Name = 'limit to items',
		Function = function(callback)
			if inputService.TouchEnabled and Killaura.Enabled then
				pcall(function()
					lplr.PlayerGui.MobileUI['2'].Visible = callback
				end)
			end
		end,
		Tooltip = 'only hits when ur holdin ur sword'
	})
	LegitAura = Killaura:CreateToggle({
		Name = 'swing only',
		Tooltip = 'only hits when u swing it urself'
	})
	ContinueSwinging = Killaura:CreateToggle({
		Name = 'continue swinging',
		Tooltip = 'keeps swingin for a lil after they leave ur range',
		Function = function(callback)
			if ContinueSwingTime then
				ContinueSwingTime.Object.Visible = callback
			end
		end
	})
	ContinueSwingTime = Killaura:CreateSlider({
		Name = 'swing duration',
		Min = 0.1,
		Max = 3,
		Default = 1,
		Decimal = 10,
		Suffix = 's',
		Darker = true,
		Visible = false
	})

	task.spawn(function()
		local wasAvailable = false
		local availSince = 0

		while vape.Loaded do
			task.wait(0.05)
			if not (Killaura.Enabled and AttackCheck and AttackCheck.Enabled) then
				wasAvailable = false
				availSince = 0
				continue
			end

			if bedwars.AbilityController then
				local ok, nowAvailable = pcall(
					bedwars.AbilityController.canUseAbility,
					bedwars.AbilityController,
					'rebellion_shield'
				)

				if ok then
					nowAvailable = nowAvailable == true

					if nowAvailable and not wasAvailable then
						availSince = tick()
					end

					if wasAvailable
						and not nowAvailable
						and availSince > 0
						and tick() - availSince > 1 then

						store.silasAbilityTime = tick()
					end

					wasAvailable = nowAvailable
				end
			end
		end
	end)

	task.spawn(function()
		local wasStomp = false
		local wasKick = false
		local stompSince = 0
		local kickSince = 0

		while vape.Loaded do
			task.wait(0.05)
			if not (Killaura.Enabled and AttackCheck and AttackCheck.Enabled) then
				wasStomp = false
				wasKick = false
				stompSince = 0
				kickSince = 0
				continue
			end

			if bedwars.AbilityController then
				local ok1, nowStomp = pcall(
					bedwars.AbilityController.canUseAbility,
					bedwars.AbilityController,
					'BLOCK_STOMP'
				)

				local ok2, nowKick = pcall(
					bedwars.AbilityController.canUseAbility,
					bedwars.AbilityController,
					'BLOCK_KICK'
				)

				if ok1 then
					nowStomp = nowStomp == true

					if nowStomp and not wasStomp then
						stompSince = tick()
					end

					if wasStomp
						and not nowStomp
						and stompSince > 0
						and tick() - stompSince > 1 then

						store.terraStompTime = tick()
					end

					wasStomp = nowStomp
				end

				if ok2 then
					nowKick = nowKick == true

					if nowKick and not wasKick then
						kickSince = tick()
					end

					if wasKick
						and not nowKick
						and kickSince > 0
						and tick() - kickSince > 1 then

						store.terraKickTime = tick()
					end

					wasKick = nowKick
				end
			end
		end
	end)

	kitChecks = {
		['Sophia'] = function()
			return isFrozen(nil, FROZEN_THRESHOLD)
		end,
		['Sigrid'] = function()
			return entitylib.isAlive
				and lplr.Character
				and lplr.Character:FindFirstChild('elk') ~= nil
		end
	}

	AttackCheck = Killaura:CreateToggle({
		Name = 'attack check',
		Tooltip = 'stops ka when ur kit shouldnt be attacking',
		Default = false
	})
end)

run(function()
	local Speed
	local Mode
	local Value
	local WallCheck
	local AutoJump
	local AlwaysJump
	local savedImpulseTime
	local rayCheck = cloneRaycast()
	rayCheck.RespectCanCollide = true
	rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
	
	Speed = vape.Categories.Blatant:CreateModule({
		Name = 'Speed',
		Function = function(callback)
			frictionTable.Speed = callback or nil
			updateVelocity()
			pcall(function()
				debug.setconstant(bedwars.WindWalkerController.updateSpeed, 7, callback and 'constantSpeedMultiplier' or 'moveSpeedMultiplier')
			end)
	
			if callback then
				if savedImpulseTime == nil then
					savedImpulseTime = bedwars.StatefulEntityKnockbackController.lastImpulseTime
				end
				Speed:Clean(function()
					pcall(function()
						bedwars.StatefulEntityKnockbackController.lastImpulseTime = (savedImpulseTime ~= nil and savedImpulseTime ~= math.huge) and savedImpulseTime or time()
					end)
					savedImpulseTime = nil
					pcall(function()
						if entitylib.isAlive then
							local root = entitylib.character.RootPart
							root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
						end
					end)
					pcall(function()
						bedwars.SprintController:setSpeed(bedwars.SprintController:isSprinting() and 20 or 14)
					end)
				end)
				Speed:Clean(runService.PreSimulation:Connect(function(dt)
					if not Speed.Enabled then return end
					bedwars.StatefulEntityKnockbackController.lastImpulseTime = math.huge
					if entitylib.isAlive then
						if not (vape.Modules.Fly and vape.Modules.Fly.Enabled) and not (vape.Modules.LongJump and vape.Modules.LongJump.Enabled) then
							bedwars.SprintController:setSpeed(Mode.Value == 'CFrame' and 20 or Value.Value)
							if Mode.Value == 'CFrame' then
								local state = entitylib.character.Humanoid:GetState()
								if state == Enum.HumanoidStateType.Climbing then return end
			
								local root, velo = entitylib.character.RootPart, getSpeed()
								local moveDirection = entitylib.character.Humanoid.MoveDirection
								local destination = (moveDirection * math.max(Value.Value - velo, 0) * dt)
			
								if WallCheck.Enabled then
									rayCheck.CollisionGroup = root.CollisionGroup
									local ray = workspace:Raycast(root.Position, destination, rayCheck)
									if ray then
										destination = ((ray.Position + ray.Normal) - root.Position)
									end
								end
			
								root.CFrame += destination
								root.AssemblyLinearVelocity = (moveDirection * velo) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
								if AutoJump.Enabled and (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed) and moveDirection ~= Vector3.zero and (Attacking or AlwaysJump.Enabled) then
									entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
								end
							end
						end
					end
				end))
			else
				pcall(function()
					bedwars.StatefulEntityKnockbackController.lastImpulseTime = (savedImpulseTime ~= nil and savedImpulseTime ~= math.huge) and savedImpulseTime or time()
				end)
				savedImpulseTime = nil
				pcall(function()
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
					end
				end)
				pcall(function()
					bedwars.SprintController:setSpeed(bedwars.SprintController:isSprinting() and 20 or 14)
				end)
			end
		end,
		ExtraText = function()
			return 'Heatseeker'
		end,
		Tooltip = 'increases your movement with various methods.'
	})
	Mode = Speed:CreateDropdown({
		Name = 'Method',
		List = {'Bedwars', 'CFrame'},
		Default = 'CFrame'
	})
	Value = Speed:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 23,
		Default = 23,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	WallCheck = Speed:CreateToggle({
		Name = 'Wall Check',
		Default = true
	})
	AutoJump = Speed:CreateToggle({
		Name = 'AutoJump',
		Function = function(callback)
			AlwaysJump.Object.Visible = callback
		end
	})
	AlwaysJump = Speed:CreateToggle({
		Name = 'Always Jump',
		Visible = false,
		Darker = true
	})
end)

run(function()
    local FastPlace
    local Value
    local CpsConstants = nil
    
    FastPlace = vape.Categories.Blatant:CreateModule({
        Name = "FastPlace",
        Function = function(callback)
            local aeroAlive = newRun(FastPlace)
            
            if callback then
                task.wait(1)
                
                pcall(function()
                    CpsConstants = require(replicatedStorage.TS['shared-constants']).CpsConstants
                end)
                
                if not CpsConstants then
                    pcall(function()
                        CpsConstants = bedwars.CpsConstants
                    end)
                end
                
                if CpsConstants then
                    local newCPS = Value.Value == 0 and 1000 or Value.Value
                    CpsConstants.BLOCK_PLACE_CPS = newCPS
                    
                    if isMobile then
                        for _, v in {'2', '5'} do
                            pcall(function()
                                FastPlace:Clean(lplr.PlayerGui.MobileUI[v].MouseButton1Down:Connect(function()
                                    if CpsConstants then
                                        local currentValue = Value.Value == 0 and 1000 or Value.Value
                                        CpsConstants.BLOCK_PLACE_CPS = currentValue
                                    end
                                end))
                            end)
                        end
                    end
                    
                    task.spawn(function()
                        while aeroAlive() do
                            local currentValue = Value.Value == 0 and 1000 or Value.Value
                            if CpsConstants.BLOCK_PLACE_CPS ~= currentValue then
                                CpsConstants.BLOCK_PLACE_CPS = currentValue
                            end
                            task.wait(0.3)
                        end
                    end)
                end
                
            else
                if CpsConstants then
                    CpsConstants.BLOCK_PLACE_CPS = 12
                end
            end
        end,
        Tooltip = 'place blocks faster'
    })
    
    Value = FastPlace:CreateSlider({
        Name = "Place Speed",
        Default = 12,
        Min = 12,
        Max = 20,
        Function = function()
            if FastPlace.Enabled and CpsConstants then
                local newCPS = Value.Value == 0 and 1000 or Value.Value
                CpsConstants.BLOCK_PLACE_CPS = newCPS
            end
        end,
    })
end)

run(function()
	local BedESP
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	
	local function Added(bed)
		if not BedESP.Enabled then return end
		local BedFolder = Instance.new('Folder')
		BedFolder.Parent = Folder
		Reference[bed] = BedFolder
		local parts = bed:GetChildren()
		table.sort(parts, function(a, b)
			return a.Name > b.Name
		end)
	
		for _, part in parts do
			if part:IsA('BasePart') and part.Name ~= 'Blanket' then
				local handle = Instance.new('BoxHandleAdornment')
				handle.Size = part.Size + Vector3.new(.01, .01, .01)
				handle.AlwaysOnTop = true
				handle.ZIndex = 2
				handle.Visible = true
				handle.Adornee = part
				handle.Color3 = part.Color
				if part.Name == 'Legs' then
					handle.Color3 = Color3.fromRGB(167, 112, 64)
					handle.Size = part.Size + Vector3.new(.01, -1, .01)
					handle.CFrame = CFrame.new(0, -0.4, 0)
					handle.ZIndex = 0
				end
				handle.Parent = BedFolder
			end
		end
	
		table.clear(parts)
	end
	
	BedESP = vape.Categories.Render:CreateModule({
		Name = 'BedESP',
		Function = function(callback)
			if callback then
				BedESP:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(function(bed)
					task.delay(0.2, Added, bed)
				end))
				BedESP:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(bed)
					if Reference[bed] then
						Reference[bed]:Destroy()
						Reference[bed] = nil
					end
				end))
				for _, bed in collectionService:GetTagged('bed') do
					Added(bed)
				end
			else
				Folder:ClearAllChildren()
				table.clear(Reference)
			end
		end,
		Tooltip = 'render beds through walls'
	})
end)

run(function()
	local LootESP
	local IronToggle
	local DiamondToggle
	local EmeraldToggle
	local GeneratorToggle
	local ScaleToggle
	local ScaleSlider
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui	
	local CollectionService = collectionService
	
	local lootTypes = {
		iron = {
			keywords = {'iron'},
			color = Color3.fromRGB(200, 200, 200),
			icon = 'iron',
			displayName = 'IRON'
		},
		diamond = {
			keywords = {'diamond'},
			color = Color3.fromRGB(85, 200, 255),
			icon = 'diamond',
			displayName = 'DIAMOND'
		},
		emerald = {
			keywords = {'emerald'},
			color = Color3.fromRGB(0, 255, 100),
			icon = 'emerald',
			displayName = 'EMERALD'
		}
	}
	
	local function getLootType(itemName)
		local nameLower = itemName:lower()
		for lootType, config in pairs(lootTypes) do
			for _, keyword in ipairs(config.keywords) do
				if nameLower:find(keyword, 1, true) then 
					return lootType, config
				end
			end
		end
		return nil
	end
	
	local function isLootEnabled(lootType)
		if lootType == 'iron' then
			return IronToggle.Enabled
		elseif lootType == 'diamond' then
			return DiamondToggle.Enabled
		elseif lootType == 'emerald' then
			return EmeraldToggle.Enabled
		end
		return false
	end
	
	local function readDropAttr(handle, attr)
		if not handle then return nil end
		local val = handle:GetAttribute(attr)
		if val == nil and handle.Parent then
			val = handle.Parent:GetAttribute(attr)
		end
		return val
	end
	
	local function isGeneratorDrop(handle)
		return readDropAttr(handle, 'OreGenDrop') == true
	end
	
	local function getDropAmount(handle)
		local amt = readDropAttr(handle, 'Amount')
		if type(amt) ~= 'number' then return 1 end
		return amt
	end
	
	local function getProperIcon(lootType)
		local icon = bedwars.getIcon({itemType = lootType}, true)
		
		if not icon or icon == "" then
			return nil
		end
		
		return icon
	end
	
	local function Added(lootHandle, lootType, config)
		if not isLootEnabled(lootType) then return end
		if Reference[lootHandle] then return end 
		local dropRoot = lootHandle.Parent
		if dropRoot and dropRoot:GetAttribute('AeroBanked') then return end
		if dropRoot then
			local bankedConn
			bankedConn = dropRoot:GetAttributeChangedSignal('AeroBanked'):Connect(function()
				if dropRoot:GetAttribute('AeroBanked') and Reference[lootHandle] then
					Reference[lootHandle]:Destroy()
					Reference[lootHandle] = nil
				end
				bankedConn:Disconnect()
			end)
		end 
		if isGeneratorDrop(lootHandle) and not (GeneratorToggle and GeneratorToggle.Enabled) then return end 
		
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = lootType
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		local ls = (ScaleToggle and ScaleToggle.Enabled and ScaleSlider) and ScaleSlider.Value or 1
		billboard.Size = UDim2.fromOffset(40 * ls, 40 * ls)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = lootHandle
		
		local blur = addBlur(billboard)
		blur.Visible = true 
		
		local iconImage = getProperIcon(config.icon)
		
		if iconImage then
			local image = Instance.new('ImageLabel')
			image.Size = UDim2.fromOffset(40, 40)
			image.Position = UDim2.fromScale(0.5, 0.5)
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.BackgroundColor3 = Color3.new(0, 0, 0) 
			image.BackgroundTransparency = 0.3 
			image.BorderSizePixel = 0
			image.Image = iconImage
			image.Parent = billboard
			
			local uicorner = Instance.new('UICorner')
			uicorner.CornerRadius = UDim.new(0, 4)
			uicorner.Parent = image
			
			local amt = Instance.new('TextLabel')
			amt.Name = 'Amt'
			amt.AnchorPoint = Vector2.new(1, 1)
			amt.Position = UDim2.new(1, -1, 1, -1)
			amt.Size = UDim2.fromOffset(40, 14)
			amt.BackgroundTransparency = 1
			amt.Text = tostring(getDropAmount(lootHandle))
			amt.TextColor3 = Color3.fromRGB(255, 255, 255)
			amt.TextStrokeTransparency = 0.4
			amt.TextSize = 13
			amt.Font = Enum.Font.GothamBold
			amt.TextXAlignment = Enum.TextXAlignment.Right
			amt.TextYAlignment = Enum.TextYAlignment.Bottom
			amt.Parent = image
		else
			local frame = Instance.new('Frame')
			frame.Size = UDim2.fromOffset(40, 40)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.BackgroundColor3 = Color3.new(0, 0, 0) 
			frame.BackgroundTransparency = 0.3 
			frame.BorderSizePixel = 0
			frame.Parent = billboard
			
			local uicorner = Instance.new('UICorner')
			uicorner.CornerRadius = UDim.new(0, 4)
			uicorner.Parent = frame
			
			local textLabel = Instance.new('TextLabel')
			textLabel.Size = UDim2.fromScale(1, 1)
			textLabel.Position = UDim2.fromScale(0.5, 0.5)
			textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			textLabel.BackgroundTransparency = 1
			textLabel.Text = config.displayName
			textLabel.TextColor3 = config.color
			textLabel.TextScaled = true
			textLabel.Font = Enum.Font.GothamBold
			textLabel.TextStrokeTransparency = 0.5
			textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			textLabel.Parent = frame
			
			local amt = Instance.new('TextLabel')
			amt.Name = 'Amt'
			amt.AnchorPoint = Vector2.new(1, 1)
			amt.Position = UDim2.new(1, -1, 1, -1)
			amt.Size = UDim2.fromOffset(40, 14)
			amt.BackgroundTransparency = 1
			amt.Text = tostring(getDropAmount(lootHandle))
			amt.TextColor3 = Color3.fromRGB(255, 255, 255)
			amt.TextStrokeTransparency = 0.4
			amt.TextSize = 13
			amt.Font = Enum.Font.GothamBold
			amt.TextXAlignment = Enum.TextXAlignment.Right
			amt.TextYAlignment = Enum.TextYAlignment.Bottom
			amt.Parent = frame
		end
		
		local content = billboard:FindFirstChild('ImageLabel') or billboard:FindFirstChild('Frame')
		if content then
			local sc = Instance.new('UIScale')
			sc.Name = 'LootScale'
			sc.Scale = ls
			sc.Parent = content
		end

		local amtLabel = billboard:FindFirstChild('Amt', true)
		if amtLabel then
			local src = lootHandle:GetAttribute('Amount') ~= nil and lootHandle or lootHandle.Parent
			if src then
				local conn = src:GetAttributeChangedSignal('Amount'):Connect(function()
					if amtLabel.Parent then
						amtLabel.Text = tostring(getDropAmount(lootHandle))
					end
				end)
				billboard.AncestryChanged:Connect(function()
					if not billboard.Parent then conn:Disconnect() end
				end)
			end
		end
		
		Reference[lootHandle] = billboard
	end
	
	local function Removed(lootHandle)
		if Reference[lootHandle] then
			Reference[lootHandle]:Destroy()
			Reference[lootHandle] = nil
		end
	end
	
	local function findExistingLoot()
		local tagged = CollectionService:GetTagged('ItemDrop')
		for _, drop in ipairs(tagged) do
			local handle = drop:FindFirstChild('Handle')
			if handle then
				local lootType, config = getLootType(drop.Name)
				if lootType and isLootEnabled(lootType) then
					if not Reference[handle] then
						Added(handle, lootType, config)
					end
				end
			end
		end
	end
	
	local function refreshLootType(lootType)
		if not LootESP.Enabled then return end
		
		local enabled = isLootEnabled(lootType)
		
		if not (GeneratorToggle and GeneratorToggle.Enabled) then
			for handle, billboard in pairs(Reference) do
				if isGeneratorDrop(handle) then
					billboard:Destroy()
					Reference[handle] = nil
				end
			end
		end
		
		if not enabled then
			for handle, billboard in pairs(Reference) do
				if billboard.Name == lootType then
					billboard:Destroy()
					Reference[handle] = nil
				end
			end
		else
			local tagged = CollectionService:GetTagged('ItemDrop')
			for _, drop in ipairs(tagged) do
				local handle = drop:FindFirstChild('Handle')
				if handle then
					local dropLootType, config = getLootType(drop.Name)
					if dropLootType == lootType and not Reference[handle] then
						Added(handle, lootType, config)
					end
				end
			end
		end
	end
	
	LootESP = vape.Categories.Render:CreateModule({
		Name = 'LootESP',
		Function = function(callback)
			if callback then
				findExistingLoot()
				
				LootESP:Clean(CollectionService:GetInstanceAddedSignal('ItemDrop'):Connect(function(drop)
					if not LootESP.Enabled then return end
					
					task.defer(function()
						local handle = drop:FindFirstChild('Handle')
						if not handle then return end
						
						local lootType, config = getLootType(drop.Name)
						if lootType and isLootEnabled(lootType) then
							Added(handle, lootType, config)
						end
					end)
				end))
				
				LootESP:Clean(CollectionService:GetInstanceRemovedSignal('ItemDrop'):Connect(function(drop)
					local handle = drop:FindFirstChild('Handle')
					if handle then
						Removed(handle)
					end
				end))
				
			else
				for handle, billboard in pairs(Reference) do
					billboard:Destroy()
				end
				table.clear(Reference)
			end
		end,
		Tooltip = 'esp for loot (iron, emerald, diamonds)'
	})
	
	IronToggle = LootESP:CreateToggle({
		Name = 'Iron',
		Function = function(callback)
			refreshLootType('iron')
		end,
		Default = true
	})
	
	DiamondToggle = LootESP:CreateToggle({
		Name = 'Diamond',
		Function = function(callback)
			refreshLootType('diamond')
		end,
		Default = true
	})
	
	EmeraldToggle = LootESP:CreateToggle({
		Name = 'Emerald',
		Function = function(callback)
			refreshLootType('emerald')
		end,
		Default = true
	})
	
	GeneratorToggle = LootESP:CreateToggle({
		Name = 'Generators',
		Function = function(callback)
			if not LootESP.Enabled then return end
			refreshLootType('iron')
			refreshLootType('diamond')
			refreshLootType('emerald')
		end,
		Tooltip = 'off = loot sittin on a gen gets hidden, only shows stuff ppl dropped. flip it on if u wanna see gen loot too gng'
	})

	local function applyLootScale()
		local val = (ScaleToggle and ScaleToggle.Enabled and ScaleSlider) and ScaleSlider.Value or 1
		for _, billboard in pairs(Reference) do
			billboard.Size = UDim2.fromOffset(40 * val, 40 * val)
			local sc = billboard:FindFirstChild('LootScale', true)
			if sc then sc.Scale = val end
		end
	end

	ScaleToggle = LootESP:CreateToggle({
		Name = 'Custom Scale',
		Function = function(callback)
			if ScaleSlider then ScaleSlider.Object.Visible = callback end
			applyLootScale()
		end,
		Tooltip = 'turn on to pick ur own size for the loot icons'
	})

	ScaleSlider = LootESP:CreateSlider({
		Name = 'Scale',
		Min = 0.5,
		Max = 3,
		Default = 1,
		Decimal = 10,
		Darker = true,
		Visible = false,
		Function = function()
			applyLootScale()
		end,
		Tooltip = 'makes the loot icons bigger or smaller gng'
	})
end)

run(function()
	local StorageESP
	local List
	local Background
	local Color = {}
	local Reference = {}
	local ChestContents = {} 
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	
	local function getEnabledItemsSet()
		local set = {}
		for _, v in ipairs(List.ListEnabled) do
			set[v] = true
		end
		return set
	end
	
	local function nearStorageItem(item, enabledSet)
		for itemName in pairs(enabledSet) do
			if item:find(itemName, 1, true) then return itemName end
		end
		return nil
	end
	
	local function refreshAdornee(billboard)
		local chestPart = billboard.Adornee
		local folderValue = chestPart and chestPart:FindFirstChild('ChestFolderValue')
		local chest = folderValue and folderValue.Value or nil

		if not chest then
			ChestContents[chestPart] = nil
			billboard.Enabled = false
			return
		end

		local chestitems = chest:GetChildren()
		local enabledSet = getEnabledItemsSet()
		local listIsEmpty = next(enabledSet) == nil

		local matchedItems = {}
		local amounts = {}
		for _, item in ipairs(chestitems) do
			if item:IsA('Accessory') then
				if listIsEmpty or enabledSet[item.Name] or nearStorageItem(item.Name, enabledSet) then
					if amounts[item.Name] == nil then
						amounts[item.Name] = 0
						table.insert(matchedItems, item.Name)
					end
					amounts[item.Name] = amounts[item.Name] + (item:GetAttribute('Amount') or 1)
				end
			end
		end

		local count = #matchedItems
		if count == 0 then
			billboard.Enabled = false
			return
		end

		local signatureParts = {}
		for _, itemName in ipairs(matchedItems) do
			table.insert(signatureParts, itemName .. '=' .. tostring(amounts[itemName]))
		end
		local signature = table.concat(signatureParts, '\0')
		local previous = ChestContents[chestPart]
		billboard.Enabled = true
		if previous and previous.chest == chest and previous.signature == signature then return end
		ChestContents[chestPart] = {chest = chest, signature = signature}
		for _, obj in ipairs(billboard:GetChildren()) do
			if obj:IsA('ImageLabel') and obj.Name == 'Icon' then
				obj:Destroy()
			end
		end
		local iconSize = 36
		local padding = 2
		local totalWidth = count * iconSize + (count - 1) * padding
		billboard.Size = UDim2.fromOffset(totalWidth, iconSize)

		for i, itemName in ipairs(matchedItems) do
			local icon = Instance.new('ImageLabel')
			icon.Name = 'Icon'
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
			icon.Position = UDim2.fromOffset((i - 1) * (iconSize + padding), 0)
			icon.AnchorPoint = Vector2.new(0, 0)
			icon.BackgroundColor3 = Color3.new(0, 0, 0)
			icon.BackgroundTransparency = 0.3
			icon.BorderSizePixel = 0
			icon.Image = bedwars.getIcon({itemType = itemName}, true)
			icon.Parent = billboard

			local uicorner = Instance.new('UICorner')
			uicorner.CornerRadius = UDim.new(0, 4)
			uicorner.Parent = icon

			local amt = Instance.new('TextLabel')
			amt.Name = 'Amt'
			amt.AnchorPoint = Vector2.new(1, 1)
			amt.Position = UDim2.new(1, -1, 1, -1)
			amt.Size = UDim2.fromOffset(iconSize, 14)
			amt.BackgroundTransparency = 1
			amt.Text = tostring(amounts[itemName] or 0)
			amt.TextColor3 = Color3.fromRGB(255, 255, 255)
			amt.TextStrokeTransparency = 0.4
			amt.TextSize = 13
			amt.Font = Enum.Font.GothamBold
			amt.TextXAlignment = Enum.TextXAlignment.Right
			amt.TextYAlignment = Enum.TextYAlignment.Bottom
			amt.Parent = icon
		end
	end
	
	local function Added(v)
		if Reference[v] then return end

		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'chest'
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		billboard.Enabled = false

		local blur = addBlur(billboard)

		Reference[v] = billboard

		refreshAdornee(billboard)

		task.defer(function()
			local folderValue = v:FindFirstChild('ChestFolderValue')
			local chest = folderValue and folderValue.Value or nil
			if chest and Reference[v] then
				local conn1 = chest.ChildAdded:Connect(function()
					if Reference[v] then refreshAdornee(Reference[v]) end
				end)
				local conn2 = chest.ChildRemoved:Connect(function()
					if Reference[v] then refreshAdornee(Reference[v]) end
				end)
				billboard.AncestryChanged:Connect(function()
					conn1:Disconnect()
					conn2:Disconnect()
				end)
			end
		end)
	end
	
	local function Removed(v)
		if Reference[v] then
			Reference[v]:Destroy()
			Reference[v] = nil
			ChestContents[v] = nil
		end
	end
	
	StorageESP = vape.Categories.Render:CreateModule({
		Name = 'StorageESP',
		Function = function(callback)
			local aeroAlive = newRun(StorageESP)
			if callback then
				local tagged = collectionService:GetTagged('chest')
				for _, v in ipairs(tagged) do
					Added(v)
				end
				
				StorageESP:Clean(collectionService:GetInstanceAddedSignal('chest'):Connect(Added))
				StorageESP:Clean(collectionService:GetInstanceRemovedSignal('chest'):Connect(Removed))
				cleanThread(StorageESP, task.spawn(function()
					while aeroAlive() do
						task.wait(0.5)
						if not StorageESP.Enabled then break end
						for chest, billboard in pairs(Reference) do
							if not chest or not chest.Parent then
								Removed(chest)
							else
								refreshAdornee(billboard)
							end
						end
					end
				end))
			else
				for chest in pairs(Reference) do
					Removed(chest)
				end
			end
		end,
		Tooltip = 'shows what items are in a chest'
	})
	
	List = StorageESP:CreateTextList({
		Name = 'Item',
		Function = function()
			table.clear(ChestContents)
			for _, v in pairs(Reference) do
				refreshAdornee(v)
			end
		end
	})
	
	Background = StorageESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then Color.Object.Visible = callback end
			for _, v in pairs(Reference) do
				local icon = v:FindFirstChild('Icon')
				if icon then
					icon.BackgroundTransparency = callback and 0.3 or 1
				end
			end
		end,
		Default = true
	})
	
    Color = StorageESP:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in pairs(Reference) do
                v.Frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                v.Frame.BackgroundTransparency = 1 - opacity
            end
        end,
        Darker = true
    })

    task.defer(function()
        if Color and Color.Object then
            Color.Object.Visible = Background.Enabled  
        end
    end)
end)

run(function()
	local TrapESP
	local Background = {}
	local Color = {}
	local Snap, Venom, Explosive, Landmine, Tesla, Gloop
	local Reference = {}
	local Watch = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui

	local Tags = {
		'snap_trap',
		'trapper_trap',
		'invisible-landmine',
		'invisible_landmine',
		'tesla-trap',
		'tesla_trap',
		'glue_trap',
		'GlueTrap'
	}

	local function getToggle(kind)
		return kind == 'snap' and Snap
			or kind == 'venom' and Venom
			or kind == 'explosive' and Explosive
			or kind == 'landmine' and Landmine
			or kind == 'tesla' and Tesla
			or kind == 'gloop' and Gloop
	end

	local function getTrap(v, tag)
		if tag == 'trapper_trap' then
			local trapType = tostring(
				v:GetAttribute('trapType')
				or v:GetAttribute('TrapType')
				or v:GetAttribute('Type')
				or ''
			):lower()

			if trapType:find('venom', 1, true)
				or v.Name:lower():find('venom', 1, true)
				or v:FindFirstChild('venom_trap', true) then
				return 'venom', 'venom_trap'
			end

			if trapType:find('explosive', 1, true)
				or v.Name:lower():find('explosive', 1, true)
				or v:FindFirstChild('explosive_trap', true) then
				return 'explosive', 'explosive_trap'
			end

			if trapType:find('snap', 1, true)
				or v.Name:lower():find('snap', 1, true)
				or v:FindFirstChild('snap_trap', true) then
				return 'snap', 'snap_trap'
			end

			return
		elseif tag == 'snap_trap' then
			return 'snap', 'snap_trap'
		elseif tag == 'invisible-landmine' or tag == 'invisible_landmine' then
			return 'landmine', 'invisible_landmine'
		elseif tag == 'tesla-trap' or tag == 'tesla_trap' then
			return 'tesla', 'tesla_trap'
		elseif tag == 'glue_trap' or tag == 'GlueTrap' or v.Name == 'GlueTrap' then
			return 'gloop', 'glue_projectile'
		end
	end

	local function isFriendly(v)
		local owner = tonumber(v:GetAttribute('PlacedByUserId') or v:GetAttribute('ownerId'))
		if owner and owner == lplr.UserId then
			return true
		end

		local teamName = lplr.Team and lplr.Team.Name
		local teamId = lplr:GetAttribute('Team')

		for _, attribute in {'SnapTrapTeamId', 'TrapperTeamId', 'LandmineTeam', 'TeamId'} do
			local value = v:GetAttribute(attribute)
			if value ~= nil then
				if typeof(value) == 'Instance' then
					value = value.Name
				end
				value = tostring(value)

				if (teamName and value == tostring(teamName))
					or (teamId ~= nil and value == tostring(teamId)) then
					return true
				end
			end
		end

		return false
	end

	local function remove(v)
		if Reference[v] then
			Reference[v]:Destroy()
			Reference[v] = nil
		end
		if Watch[v] then
			for _, conn in Watch[v] do
				conn:Disconnect()
			end
			Watch[v] = nil
		end
	end

	local function clearAll()
		for v in Watch do
			remove(v)
		end
		for v in Reference do
			remove(v)
		end
		Folder:ClearAllChildren()
	end

	local function pickAdornee(v)
		if v:IsA('BasePart') then return v end
		if v:IsA('Model') and v.PrimaryPart then return v.PrimaryPart end
		local best, size = nil, -1
		for _, part in v:GetDescendants() do
			if part:IsA('BasePart') and part.Transparency < 1 then
				local vol = part.Size.X * part.Size.Y * part.Size.Z
				if vol > size then
					best, size = part, vol
				end
			end
		end
		return best or v:FindFirstChildWhichIsA('BasePart', true)
	end

	local function added(v, icon, kind)
		if Reference[v] or isFriendly(v) then return end

		local toggle = getToggle(kind)
		if not toggle or not toggle.Enabled then return end

		local adornee = pickAdornee(v)

		if not adornee then return end

		Watch[v] = {
			v.AncestryChanged:Connect(function(_, parent)
				if not parent then
					remove(v)
				end
			end),
			v.AttributeChanged:Connect(function()
				if isFriendly(v) then
					remove(v)
				end
			end)
		}

		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = icon
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = adornee

		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled

		local image = Instance.new('ImageLabel')
		image.Name = 'ImageLabel'
		image.Size = UDim2.fromOffset(36, 36)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		image.BorderSizePixel = 0
		image.Image = bedwars.getIcon({itemType = icon}, true)
		image.Parent = billboard

		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = image

		Reference[v] = billboard
	end

	local function isHeld(v)
		if v:IsDescendantOf(gameCamera) then return true end
		local inv = replicatedStorage:FindFirstChild('Inventories')
		if inv and v:IsDescendantOf(inv) then return true end
		if v:FindFirstAncestorWhichIsA('Tool') or v:FindFirstAncestorWhichIsA('Accessory') then return true end
		local model = v:FindFirstAncestorOfClass('Model')
		while model do
			if model:FindFirstChildOfClass('Humanoid') then return true end
			model = model:FindFirstAncestorOfClass('Model')
		end
		return false
	end

	local function addByTag(v, tag)
		if isHeld(v) then return end
		local kind, icon = getTrap(v, tag)
		if kind then
			added(v, icon, kind)
		end
	end

	local function addGloop(v)
		if v.Name ~= 'GlueTrap' then return end

		task.spawn(function()
			for _ = 1, 12 do
				if not TrapESP.Enabled or not v.Parent then return end

				addByTag(v, 'GlueTrap')

				if Reference[v] then
					return
				end

				task.wait(0.05)
			end
		end)
	end

	local function refresh()
		clearAll()

		if not TrapESP.Enabled then return end

		for _, tag in Tags do
			for _, v in collectionService:GetTagged(tag) do
				addByTag(v, tag)
			end
		end
	end

	TrapESP = vape.Categories.Render:CreateModule({
		Name = 'TrapESP',
		Function = function(callback)
			if callback then
				TrapESP:Clean(workspace.DescendantAdded:Connect(function(v)
					if v.Name == 'GlueTrap' then
						addGloop(v)
					end
				end))

				for _, v in workspace:GetDescendants() do
					if v.Name == 'GlueTrap' then
						addGloop(v)
					end
				end
				for _, tag in Tags do
					TrapESP:Clean(collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
						addByTag(v, tag)
					end))

					TrapESP:Clean(collectionService:GetInstanceRemovedSignal(tag):Connect(remove))
				end

				refresh()
				local heldCheck = 0
				TrapESP:Clean(runService.Heartbeat:Connect(function()
					local checkHeld = tick() - heldCheck > 0.25
					if checkHeld then heldCheck = tick() end
					for v, bb in Reference do
						if not v.Parent or not bb.Adornee or not bb.Adornee.Parent or (checkHeld and isHeld(v)) then
							remove(v)
						end
					end
				end))
			else
				clearAll()
			end
		end,
		Tooltip = 'shows the traps u choose through walls'
	})

	local function trapToggle(name)
		return TrapESP:CreateToggle({
			Name = name,
			Default = true,
			Function = refresh
		})
	end

	Snap = trapToggle('Snap traps')
	Venom = trapToggle('Venom traps')
	Explosive = trapToggle('Explosive traps')
	Landmine = trapToggle('Landmines')
	Tesla = trapToggle('Tesla traps')
	Gloop = trapToggle('Gloops')

	Background = TrapESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then Color.Object.Visible = callback end

			for _, v in Reference do
				v.ImageLabel.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
				v.Blur.Visible = callback
			end
		end,
		Default = true,
		Visible = true
	})

	Color = TrapESP:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			for _, v in Reference do
				v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
				v.ImageLabel.BackgroundTransparency = 1 - opacity
			end
		end,
		Darker = true
	})
end)

run(function()
	local StreamerMode
	local NameBox
	local restored = setmetatable({}, {__mode = 'k'})
	local hooked = setmetatable({}, {__mode = 'k'})
	local textClasses = {TextLabel = true, TextButton = true, TextBox = true}
	local needles = {}
	local minLength = math.huge
	local alias = 'hidden'
	local writing
	local playerClass
	local savedUsername, savedDisplay, savedTag, savedLevel
	local queued = false

	local function readAlias()
		local value = NameBox and NameBox.Value
		if type(value) == 'string' and value ~= '' then
			return value
		end
		return 'hidden'
	end

	local function buildNeedles()
		table.clear(needles)
		minLength = math.huge
		local seen = {}
		for _, name in {lplr.Name, lplr.DisplayName} do
			if type(name) == 'string' and name ~= '' and not seen[name] then
				seen[name] = true
				minLength = math.min(minLength, #name)
				table.insert(needles, {
					plain = name:lower(),
					forms = {name, name:lower(), name:upper()}
				})
			end
		end
	end

	local function maskText(text)
		local out = text
		for _, needle in needles do
			for _, form in needle.forms do
				if form ~= '' and out:find(form, 1, true) then
					out = out:gsub((form:gsub('%W', '%%%0')), alias)
				end
			end
		end
		return out
	end

	local function keepText(object, value)
		writing = object
		object.Text = value
		writing = nil
	end

	local function watchText(object, apply)
		if hooked[object] then return end
		hooked[object] = object:GetPropertyChangedSignal('Text'):Connect(apply)
	end

	local function nearbyName(object)
		local parent = object.Parent
		for _ = 1, 3 do
			if not parent then return nil end
			local label = parent:FindFirstChild('PlayerName', true)
			if label then return label end
			parent = parent.Parent
		end
		return nil
	end

	local function blankLevel(object)
		if writing == object or not textClasses[object.ClassName] then return end
		if not object.Name:lower():find('level', 1, true) then return end
		local owner = nearbyName(object)
		if not owner or not owner.Text:find(alias, 1, true) then return end

		local function apply()
			if writing == object or not object.Parent then return end
			local text = object.Text
			if type(text) ~= 'string' or text == '' then return end
			if restored[object] == nil then
				restored[object] = text
			end
			keepText(object, '')
		end

		apply()
		watchText(object, apply)
	end

	local function sweepLevels(object)
		if not object then return end
		for _, child in object:GetDescendants() do
			blankLevel(child)
		end
	end

	local function maskObject(object)
		if not textClasses[object.ClassName] then return end

		local function apply()
			if writing == object or not object.Parent then return end
			local text = object.Text
			if type(text) ~= 'string' or #text < minLength then return end

			local lower = text:lower()
			local found = false
			for _, needle in needles do
				if lower:find(needle.plain, 1, true) then
					found = true
					break
				end
			end
			if not found then return end

			local masked = maskText(text)
			if masked == text then return end

			if restored[object] == nil then
				restored[object] = text
			end
			keepText(object, masked)
			watchText(object, apply)
			sweepLevels(object.Parent)
		end

		apply()
	end

	local function sweep(root)
		if not root then return end
		if vape.ThreadFix and setthreadidentity then
			pcall(setthreadidentity, 8)
		end

		StreamerMode:Clean(root.DescendantAdded:Connect(function(object)
			if not StreamerMode.Enabled then return end
			maskObject(object)
			blankLevel(object)
		end))

		local clock = os.clock()
		for _, object in root:GetDescendants() do
			maskObject(object)
			blankLevel(object)
			if os.clock() - clock > 0.002 then
				task.wait()
				if not StreamerMode.Enabled then return end
				clock = os.clock()
				if vape.ThreadFix and setthreadidentity then
					pcall(setthreadidentity, 8)
				end
			end
		end
	end

	local function findPlayerClass()
		if playerClass then return playerClass end
		pcall(function()
			local util = bedwars.GamePlayerUtil
			if not util then
				for _, module in replicatedStorage.TS:GetDescendants() do
					if module:IsA('ModuleScript') and module.Name:lower():find('game%-player%-util') then
						local ok, res = pcall(require, module)
						if ok and type(res) == 'table' and type(res.GamePlayerUtil) == 'table' then
							util = res.GamePlayerUtil
							break
						end
					end
				end
			end
			local holder = util and util.getGamePlayer and util.getGamePlayer(lplr)
			local meta = holder and getmetatable(holder)
			playerClass = meta and meta.__index or nil
		end)
		return playerClass
	end

	local function isMe(holder)
		local ok, player = pcall(function()
			return holder:getPlayer()
		end)
		return ok and player ~= nil and player.UserId == lplr.UserId
	end

	local function hookClass()
		local class = findPlayerClass()
		if not class or savedUsername then return end

		savedUsername, savedDisplay = class.getUsername, class.getDisplayName
		savedTag, savedLevel = class.getClanTag, class.getLevel

		class.getUsername = function(self, ...)
			return isMe(self) and alias or savedUsername(self, ...)
		end
		class.getDisplayName = function(self, ...)
			return isMe(self) and alias or savedDisplay(self, ...)
		end
		class.getClanTag = function(self, ...)
			return isMe(self) and '' or savedTag(self, ...)
		end
		class.getLevel = function(self, ...)
			return isMe(self) and -1 or savedLevel(self, ...)
		end
	end

	local function unhookClass()
		local class = playerClass
		if not class or not savedUsername then return end
		class.getUsername, class.getDisplayName = savedUsername, savedDisplay
		class.getClanTag, class.getLevel = savedTag, savedLevel
		savedUsername, savedDisplay, savedTag, savedLevel = nil, nil, nil, nil
	end

	local function reload()
		if queued or not StreamerMode or not StreamerMode.Enabled then return end
		queued = true
		task.delay(0.3, function()
			queued = false
			if StreamerMode.Enabled then
				StreamerMode:Toggle()
				StreamerMode:Toggle()
			end
		end)
	end

	StreamerMode = vape.Categories.Render:CreateModule({
		Name = 'StreamerMode',
		Function = function(callback)
			if callback then
				buildNeedles()
				alias = readAlias()
				for _, needle in needles do
					for _, form in needle.forms do
						if form ~= '' and alias:find(form, 1, true) then
							alias = 'hidden'
						end
					end
				end

				hookClass()

				for _, root in {lplr:FindFirstChildOfClass('PlayerGui'), coreGui, gethui and gethui() or nil, lplr.Character} do
					sweep(root)
				end

				StreamerMode:Clean(lplr.CharacterAdded:Connect(function(char)
					if StreamerMode.Enabled then
						sweep(char)
					end
				end))
			else
				unhookClass()

				if vape.ThreadFix and setthreadidentity then
					pcall(setthreadidentity, 8)
				end

				for object, conn in hooked do
					pcall(function()
						conn:Disconnect()
					end)
				end
				table.clear(hooked)

				for object, text in restored do
					if object.Parent then
						keepText(object, text)
					end
				end
				writing = nil
				table.clear(restored)
			end
		end,
		Tooltip = 'changes ur name everywhere on ur screen so u can screenshare and etc without leaking it',
		ExtraText = function()
			return readAlias()
		end
	})

	NameBox = StreamerMode:CreateTextBox({
		Name = 'name',
		Default = 'aerov4 is so tuff',
		Placeholder = 'type a name...',
		Function = reload
	})
end)

local function resolvePlayerKitImage(player)
	local kit = player:GetAttribute('PlayingAsKits')
	if type(kit) ~= 'string' then
		return kitImageIds.none
	end

	kit = kit:lower()
	local meta = bedwars.BedwarsKitMeta and bedwars.BedwarsKitMeta[kit]
	return (meta and meta.renderImage) or kitImageIds[kit] or kitImageIds.none
end

run(function()
	local desirebs
	local Opacity
	local images = {}
	local outlines = {}
	local layer

	local function clear()
		if layer then
			layer:Destroy()
			layer = nil
		end
		table.clear(images)
		table.clear(outlines)
	end

	desirebs = vape.Categories.Render:CreateModule({
		Name = 'desirebs',
		Function = function(enabled)
			if enabled then
				local alive = newRun(desirebs)

				layer = Instance.new('ScreenGui')
				layer.Name = 'desirebsLayer'
				layer.IgnoreGuiInset = true
				layer.ResetOnSpawn = false
				layer.DisplayOrder = 70
				layer.ZIndexBehavior = Enum.ZIndexBehavior.Global
				layer.Parent = vape.gui and vape.gui.Parent or coreGui

				desirebs:Clean(runService.RenderStepped:Connect(function()
					if not alive() then return end

					local seen = {}

					for _, ent in entitylib.List do
						if not ent.Player or ent.Player == lplr then
							continue
						end

						seen[ent] = true

						local image = images[ent]
						if not image then
							image = Instance.new('ImageLabel')
							image.Name = 'KitImage'
							image.BackgroundTransparency = 1
							image.BorderSizePixel = 0
							image.ScaleType = Enum.ScaleType.Fit
							image.ZIndex = 2
							image.Visible = false
							image.Parent = layer
							images[ent] = image
						end

						local outline = outlines[ent]
						if not outline and ent.Character then
							outline = Instance.new('Highlight')
							outline.Name = 'KitOutline'
							outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							outline.FillTransparency = 1
							outline.OutlineTransparency = 0.45
							outline.OutlineColor = Color3.new(1, 1, 1)
							outline.Parent = layer
							outlines[ent] = outline
						end

						if outline then
							outline.Adornee = ent.Character
							outline.Enabled = ent.Health == nil or ent.Health > 0
						end

						local root = ent.RootPart
						image.Visible = false

						if root and root.Parent and (not ent.Health or ent.Health > 0) then
							local rootPos, visible = gameCamera:WorldToViewportPoint(root.Position)

							if visible then
								local facing = CFrame.lookAlong(root.Position, gameCamera.CFrame.LookVector)
								local topPos = gameCamera:WorldToViewportPoint((facing * CFrame.new(1.4, 2.6, 0)).Position)
								local bottomPos = gameCamera:WorldToViewportPoint((facing * CFrame.new(-1.4, -3.2, 0)).Position)

								local height = math.abs(topPos.Y - bottomPos.Y)
								local size = math.clamp(math.floor(height * 0.85), 45, 150)

								image.Position = UDim2.fromOffset(
									math.floor(rootPos.X - size / 2),
									math.floor(rootPos.Y - size * 0.8)
								)
								image.Size = UDim2.fromOffset(size, size)
								image.ImageTransparency = 1 - Opacity.Value / 100
								image.Image = resolvePlayerKitImage(ent.Player)
								image.Visible = true
							end
						end
					end

					for ent, image in images do
						if not seen[ent] then
							image:Destroy()
							images[ent] = nil

							if outlines[ent] then
								outlines[ent]:Destroy()
								outlines[ent] = nil
							end
						end
					end
				end))
			else
				clear()
			end
		end,
		Tooltip = 'shows see through kit images on players'
	})

	Opacity = desirebs:CreateSlider({
		Name = 'opacity',
		Min = 0,
		Max = 100,
		Default = 45,
		Suffix = '%'
	})
end)

run(function()
	local NameTags
	local Loop
	local nameTagRun = 0
	local StreamProof
	local Targets
	local Color
	local Background
	local DisplayName
	local Health
	local HealthColorToggle
	local HealthColorFull
	local HealthColorMid
	local HealthColorLow
	local Distance
	local Equipment
	local Loot
	local NTBedBreak
	local Potions
	local function getBedBreakCounts(inv)
		local tnt, siege = 0, 0
		for _, it in (inv and inv.items) or {} do
			if it.itemType == 'siege_tnt' then
				siege += (it.amount or 0)
			elseif it.itemType == 'tnt' then
				tnt += (it.amount or 0)
			end
		end
		return tnt, siege
	end
	local function kCount(n)
		if n >= 10000 then
			return math.floor(n / 1000) .. 'k'
		elseif n >= 1000 then
			local v = math.floor(n / 100) / 10
			return (v == math.floor(v) and tostring(math.floor(v)) or tostring(v)) .. 'k'
		end
		return tostring(n)
	end
	local function setCountSlot(ic, itemType, count)
		if not ic then return end
		ic.Image = count > 0 and bedwars.getIcon({ itemType = itemType }, true) or ''
		local amt = ic:FindFirstChild('Amt')
		if amt then amt.Text = count > 0 and kCount(count) or '' end
	end
	local function applyBedBreakIcon(ent, nametag)
		if not (nametag and ent.Player) then return end
		local inv = store.inventories[ent.Player]
		if not inv and bedwars.getInventory then
			inv = bedwars.getInventory(ent.Player)
			if inv then store.inventories[ent.Player] = inv end
		end
		local tnt, siege = getBedBreakCounts(inv)
		setCountSlot(nametag:FindFirstChild('LootTnt'), 'tnt', tnt)
		setCountSlot(nametag:FindFirstChild('LootSiege'), 'siege_tnt', siege)
	end
	local function makeCountSlot(nametag, name, x, y, sc)
		local Icon = Instance.new('ImageLabel')
		Icon.Name = name
		Icon.Size = UDim2.fromOffset(26 * sc, 26 * sc)
		Icon.Position = UDim2.fromOffset(x * sc, y * sc)
		Icon.BackgroundTransparency = 1
		Icon.Image = ''
		Icon.Parent = nametag
		local amt = Instance.new('TextLabel')
		amt.Name = 'Amt'
		amt.AnchorPoint = Vector2.new(0.5, 1)
		amt.Position = UDim2.new(0.5, 0, 1, 3 * sc)
		amt.Size = UDim2.fromOffset(34 * sc, 13 * sc)
		amt.BackgroundTransparency = 1
		amt.Text = ''
		amt.TextColor3 = Color3.fromRGB(255, 255, 255)
		amt.TextStrokeColor3 = Color3.new(0, 0, 0)
		amt.TextStrokeTransparency = 0
		amt.TextSize = 13 * sc
		amt.Font = Enum.Font.GothamBlack
		amt.TextXAlignment = Enum.TextXAlignment.Center
		amt.TextYAlignment = Enum.TextYAlignment.Bottom
		amt.ZIndex = Icon.ZIndex + 1
		amt.Parent = Icon
		return Icon
	end
	local potionDefs = {
		{name = 'PotSerpent', attr = 'StatusEffect_serpents_touch_potion', item = 'serpents_touch_potion', timed = true},
		{name = 'PotFury', attr = 'StatusEffect_fury_potion', item = 'fury_potion', timed = true},
		{name = 'PotInvis', attr = 'StatusEffect_invisibility', item = 'invisibility_potion', timed = true},
		{name = 'PotJump', attr = 'JumpBoost', item = 'jump_potion', timed = false},
		{name = 'PotPie', attr = 'SpeedPieBuff', item = 'speed_pie', timed = false}
	}
	local function potionActive(char, def)
		if not char then return false end
		local val = char:GetAttribute(def.attr)
		if val == nil then return false end
		if def.timed then
			return type(val) == 'number' and val > workspace:GetServerTimeNow()
		end
		return val ~= false and val ~= 0
	end
	local Boss
	local ShowKits
	local KitTracker
	local Rank
	local DeviceIcon
	local GloopIndicator
	local Enchant
	local Scale
	local FontOption
	local Teammates
	local DistanceCheck
	local DistanceLimit
	local Strings, Sizes, Reference = {}, {}, {}
	local bossNametags = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local methodused
	local Removed
	local lastUpdate = {}
	local kitCache = {}
	local lootCache = {}
	local equipmentCache = {}
	local enchantCache = {}
	local healthCache = {}
	local charCache = {}
	local enchantConnections = {}
	local gloopConnections = {}
	local kitTrackerConnections = {}
	local billboardCache = {}
	local tick = tick
	local math_floor = math.floor
	local math_round = math.round
	local math_clamp = math.clamp
	local math_huge = math.huge
	local string_format = string.format
	local vector2new = Vector2.new
	local vector3new = Vector3.new
	local color3fromHSV = Color3.fromHSV
	local color3new = Color3.new
	
	local function getTeamColor(ent)
		local plr = ent and ent.Player
		if not plr then return nil end
		local theirTeam = tonumber(plr:GetAttribute('Team'))
		if not theirTeam then return nil end
		local entry = getgenv().aeroTeamColors[theirTeam]
		return entry and entry.color
	end
	local udim2fromOffset = UDim2.fromOffset

	local function getChainsawImage(level)
		if not level or level < 1 or level > 5 then return '' end
		local success, img = pcall(function()
			local imageModule = require(game:GetService("ReplicatedStorage"):WaitForChild("TS"):WaitForChild("image"):WaitForChild("image-id"))
			local ids = {
				[1] = imageModule.BedwarsImageId.WOOD_TINKER_MECH,
				[2] = imageModule.BedwarsImageId.IRON_TINKER_MECH,
				[3] = imageModule.BedwarsImageId.DIAMOND_TINKER_MECH,
				[4] = imageModule.BedwarsImageId.EMERALD_TINKER_MECH,
				[5] = imageModule.BedwarsImageId.VOID_TINKER_MECH,
			}
			return ids[level]
		end)
		if success and img then
			return img
		end
		local fallback = {
			[1] = "rbxassetid://1234567890", 
			[2] = "rbxassetid://1234567891", 
			[3] = "rbxassetid://1234567892", 
			[4] = "rbxassetid://1234567893", 
			[5] = "rbxassetid://1234567894", 
		}
		return fallback[level] or ''
	end

	local function splitHealth(ent)
		local shield = ent.Character and getShieldAttribute(ent.Character) or 0
		return math.round((ent.Health or 0) - shield), math.round(shield)
	end

	local function getHealthColor(ent)
		local hp = splitHealth(ent)
		local ratio = math.clamp(hp / (ent.MaxHealth and ent.MaxHealth > 0 and ent.MaxHealth or 1), 0, 1)
		if HealthColorToggle and HealthColorToggle.Enabled then
			local fullC = Color3.fromHSV(HealthColorFull.Hue, HealthColorFull.Sat, HealthColorFull.Value)
			local midC  = Color3.fromHSV(HealthColorMid.Hue,  HealthColorMid.Sat,  HealthColorMid.Value)
			local lowC  = Color3.fromHSV(HealthColorLow.Hue,  HealthColorLow.Sat,  HealthColorLow.Value)
			if ratio >= 0.5 then
				return fullC:Lerp(midC, (1 - ratio) / 0.5)
			else
				return midC:Lerp(lowC, (0.5 - ratio) / 0.5)
			end
		else
			if ratio >= 0.7 then
				return Color3.fromRGB(0, 255, 0)
			elseif ratio >= 0.3 then
				return Color3.fromRGB(255, 255, 0)
			elseif ratio >= 0.1 then
				return Color3.fromRGB(255, 165, 0)
			else
				return Color3.fromRGB(255, 0, 0)
			end
		end
	end

	local function getHealthColorStr(ent)
		local c = getHealthColor(ent)
		return 'rgb('..math.floor(c.R*255)..','..math.floor(c.G*255)..','..math.floor(c.B*255)..')'
	end

	local function healthRich(ent)
		local hp, shield = splitHealth(ent)
		local text = '<font color="'..getHealthColorStr(ent)..'">'..hp..'</font>'
		if shield > 0 then
			text = text..' <font color="rgb(255,255,255)">'..shield..'</font>'
		end
		return text
	end

	local function healthPlain(ent)
		local hp, shield = splitHealth(ent)
		return shield > 0 and (hp..' +'..shield) or tostring(hp)
	end

	local enchantImageMap = nil
	local function buildEnchantMap()
		if enchantImageMap then return enchantImageMap end
		enchantImageMap = {}
		task.spawn(function()
			if vape.ThreadFix then setthreadidentity(8) end
			local ok, meta = pcall(function()
				return require(game:GetService('ReplicatedStorage').TS.enchant['enchant-meta'])
			end)
			if not ok or not meta then return end
			for _, subMeta in pairs({meta.EnchantMeta, meta.ToolEnchantMeta, meta.ArmorEnchantMeta}) do
				if type(subMeta) == 'table' then
					for _, v in pairs(subMeta) do
						if type(v) == 'table' and v.statusEffect and v.image then
							enchantImageMap[v.statusEffect] = v.image
						end
					end
				end
			end
		end)
		return enchantImageMap
	end

	local function getActiveEnchantImage(char)
		if not char then return '' end
		local map = buildEnchantMap()
		for attr, val in pairs(char:GetAttributes()) do
			if attr:sub(1, 13) == 'StatusEffect_' and type(val) == 'number' and val < 0 then
				local effectName = attr:sub(14)
				if not effectName:find('stacks') then
					local img = map[effectName]
					if img and img ~= '' then return img end
				end
			end
		end
		return ''
	end

	local function getBossDisplayName(ent)
		if not ent.NPC or not ent.Character then return nil end
		local char = ent.Character
		if char:GetAttribute("BossType") == "Bhaa" then
			return "Bhaa"
		end
		if char.Name:lower() == "bhaa" then
			return "Bhaa"
		end
		if char:FindFirstChild("BhaaModel") or char:FindFirstChild("BhaaHead") then
			return "Bhaa"
		end
		if char.Name == "Titan" then
			return "Titan"
		end
		return nil
	end

	local function shouldShow(ent)
		if not Targets.Players.Enabled and ent.Player then return false end
		local isBoss = ent.NPC and ent.Character and getBossDisplayName(ent) ~= nil
		if isBoss then
			if not Boss.Enabled then return false end
		else
			if not Targets.NPCs.Enabled and ent.NPC then return false end
			if Teammates.Enabled and (ent.Player and lplr:GetAttribute('Team') and ent.Player:GetAttribute('Team') == lplr:GetAttribute('Team')) and (not ent.Friend) then return false end
		end
		return true
	end

	local Added = {
		Normal = function(ent)
			if Reference[ent] then Removed.Normal(ent) end
			for oldEnt in Reference do
				if oldEnt ~= ent and (not oldEnt.Character or not oldEnt.Character.Parent or (oldEnt.Player and ent.Player and oldEnt.Player == ent.Player)) then
					Removed.Normal(oldEnt)
				end
			end
			if not Targets.Players.Enabled and ent.Player then return end
			local bossDisplayName = ent.NPC and ent.Character and getBossDisplayName(ent) or nil
			local isBoss = bossDisplayName ~= nil
			if isBoss then
				if not Boss.Enabled then return end
			else
				if not Targets.NPCs.Enabled and ent.NPC then return end
				if Teammates.Enabled and (ent.Player and lplr:GetAttribute('Team') and ent.Player:GetAttribute('Team') == lplr:GetAttribute('Team')) and (not ent.Friend) then return end
			end

			local entityName = bossDisplayName or (ent.Player and nil) or ent.Character.Name
			Strings[ent] = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or entityName

			if Health.Enabled then
				Strings[ent] = Strings[ent]..' '..healthRich(ent)
			end

			if Distance.Enabled then
				Strings[ent] = '[%s] ' .. Strings[ent]
			end
			local textSize = 14 * Scale.Value
			local fontFace = FontOption.Value
			local size = getfontsize(removeTags(Strings[ent]), textSize, fontFace, vector2new(100000, 100000))
			local nametag = Instance.new('TextLabel')
			nametag.Name = ent.Player and ent.Player.Name or ent.Character.Name
			nametag.Size = udim2fromOffset(size.X + 8, size.Y + 7)
			nametag.AnchorPoint = vector2new(0.5, 1)
			nametag.BackgroundColor3 = color3new()
			nametag.BackgroundTransparency = Background.Value
			nametag.BorderSizePixel = 0
			nametag.Visible = false
			nametag.Text = Strings[ent]
			nametag.TextColor3 = getTeamColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
			nametag.RichText = true
			nametag.TextSize = textSize
			nametag.FontFace = fontFace
			nametag.Parent = Folder

			if KitTracker and KitTracker.Enabled and ent.Player then
			  pcall(function()
				local vkRoman = {'I','II','III','IV','V'}
				local ktLabel = Instance.new('TextLabel')
				ktLabel.Name = 'KitTrackerLabel'
				ktLabel.BackgroundTransparency = 1
				ktLabel.TextScaled = false
				ktLabel.TextSize = 13
				ktLabel.FontFace = FontOption.Value
				ktLabel.RichText = true
				ktLabel.AnchorPoint = Vector2.new(1, 0.5)
				ktLabel.Position = UDim2.new(0, -2, 0.5, 0)
				ktLabel.Size = UDim2.new(0, 40, 1, 0)
				ktLabel.ZIndex = 2
				ktLabel.Parent = nametag

				local stroke = Instance.new('UIStroke')
				stroke.Color = Color3.new(0, 0, 0)
				stroke.Thickness = 1.5
				stroke.Parent = ktLabel

				local ktEventsBound = false
				local function updateKtLabel()
					if not KitTracker.Enabled then ktLabel.Text = '' return end
					local playerKit = ent.Player:GetAttribute('PlayingAsKits') or 'none'
					if playerKit == 'void_knight' then
						local tier = ent.Player:GetAttribute('VoidKnightTier') or 0
						if tier > 0 then
							ktLabel.Text = '【' .. (vkRoman[tier] or tostring(tier)) .. '】'
							ktLabel.TextColor3 = Color3.fromRGB(180, 80, 255)
						else
							ktLabel.Text = ''
						end
					elseif playerKit == 'block_kicker' then
						local char = ent.Character
						local count = (char and char:GetAttribute('BlockKickerKit_BlockCount')) or ent.Player:GetAttribute('BlockKickerKit_BlockCount') or 0
						ktLabel.Text = count > 0 and '【' .. tostring(count) .. '】' or ''
						ktLabel.TextColor3 = Color3.fromRGB(100, 210, 100)
					elseif playerKit == 'elk_master' then
						local char = ent.Character
						local isMounted = char and char:FindFirstChild('elk') ~= nil
						if isMounted then
							ktLabel.Text = '【🦌】'
							ktLabel.TextColor3 = Color3.fromRGB(160, 220, 80)
						else
							ktLabel.Text = ''
						end
					elseif playerKit == 'summoner' then
						local tier = ent.Player:GetAttribute("Summoner_ClawLevel") or 0
						if not tier or tier == 0 then ktLabel.Text = '' return end
						ktLabel.Text = '【 ' .. (vkRoman[tier] or tostring(tier)) .. ' 】'
						ktLabel.TextColor3 = Color3.fromRGB(191, 0, 255)
					elseif playerKit == 'paladin' then
						ktLabel.Text = '【 🪽 】'
						ktLabel.TextColor3 = Color3.fromRGB(255, 242, 150)
					elseif playerKit == 'davey' then
						local tier = ent.Character and ent.Character:GetAttribute('StatusEffect_powdered_stacks') or 0
						if tier > 0 then
							ktLabel.Text = '【 ' .. tostring(tier) .. ' 】'
						else
							ktLabel.Text = ''
						end
						ktLabel.TextColor3 = Color3.fromRGB(255, 105, 130)
					elseif playerKit == 'airbender' then
						ktLabel.Text = ''
						ktLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
						if not ktEventsBound then
							ktEventsBound = true
							if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
							task.spawn(function()
								table.insert(kitTrackerConnections[ent], bedwars.Client:Get("Airbender_UseTornadoFromServer"):Connect(function(p12)
									if not KitTracker.Enabled then ktLabel.Text = '' return end
									if p12.tornadoData.owner == ent.Player then
										ktLabel.Text = '【 🌪️ 】'
									end
								end))
								table.insert(kitTrackerConnections[ent], bedwars.Client:Get("Airbender_EndTornadoFromServer"):Connect(function(p13)
									if not KitTracker.Enabled then ktLabel.Text = '' return end
									if p13.tornadoData.owner == ent.Player then
										ktLabel.Text = ''
									end
								end))
							end)
						end
					elseif playerKit == 'hatter' then
						ktLabel.Text = ''
						ktLabel.TextColor3 = Color3.fromRGB(45, 15, 80)
						if not ktEventsBound then
							ktEventsBound = true
							if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
							task.spawn(function()
								if vape.ThreadFix then setthreadidentity(8) end
								table.insert(kitTrackerConnections[ent], bedwars.Client:OnEvent("HatterUseTeleport", function(p14)
									if vape.ThreadFix then setthreadidentity(8) end
									if not KitTracker.Enabled then ktLabel.Text = '' return end
									local dtc = p14.arriveTime - workspace:GetServerTimeNow() + 0.05
									if p14.hatterPlayer == ent.Player then
										ktLabel.Text = '【 🎩 】'
										task.wait(dtc)
										if vape.ThreadFix then setthreadidentity(8) end
										ktLabel.Text = ''
									else
										ktLabel.Text = ''
									end
								end))
							end)
						end
					elseif playerKit == 'black_market_trader' then
						ktLabel.Text = ''
						ktLabel.TextColor3 = Color3.fromRGB(30, 10, 60)
						if not ktEventsBound then
							ktEventsBound = true
							if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
							task.spawn(function()
								table.insert(kitTrackerConnections[ent], bedwars.Client:Get("BlackMarketPlaceShop"):Connect(function(p15)
									if not KitTracker.Enabled then ktLabel.Text = '' return end
									if p15.shopOwnerUserId == ent.Player.UserId then
										ktLabel.Text = '【 🏪 】'
									end
								end))
								local worldFolder = getWorldFolder()
								local blocks = worldFolder:WaitForChild("Blocks", math.huge)
								table.insert(kitTrackerConnections[ent], blocks.ChildAdded:Connect(function(obj)
									if obj.Name == 'black_market_shop' and obj:GetAttribute('PlacedByUserId') == ent.Player.UserId then
									local billboard = Instance.new('BillboardGui')
									billboard.Parent = obj
									billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
									billboard.Size = UDim2.fromOffset(36, 36)
									billboard.AlwaysOnTop = true
									billboard.ClipsDescendants = false
									local blur = addBlur(billboard)
									blur.Visible = Background.Enabled
									local image = Instance.new('ImageLabel')
									image.Size = UDim2.fromOffset(36, 36)
									image.Position = UDim2.fromScale(0.5, 0.5)
									image.AnchorPoint = Vector2.new(0.5, 0.5)
									image.BackgroundColor3 = Color3.fromHSV(0, 0, 0)
									image.BackgroundTransparency = 0.85
									image.BorderSizePixel = 0
									image.Image = bedwars.getIcon({itemType = 'shadow_coin'}, true)
									image.Parent = billboard
									local uicorner = Instance.new('UICorner')
									uicorner.CornerRadius = UDim.new(0, 4)
									uicorner.Parent = image
									if not billboardCache[ent] then billboardCache[ent] = {} end
									table.insert(billboardCache[ent], billboard)
									end
								end))
							end)
						end
					elseif playerKit == 'wizard' then
						ktLabel.TextColor3 = Color3.fromRGB(100, 70, 220)
						local function getStaffTier(v)
							local inv = store.inventories[v] and store.inventories[v].items or {}
							for _, item in inv do
								local nowstr = string.lower(item.itemType or '')
								if string.find(nowstr, 'wizard_staff') then
									return tonumber(item.itemType:sub(#item.itemType, #item.itemType)) or 1
								end
							end
						end
						local tier = getStaffTier(ent.Player)
						if not tier or tier < 0 then ktLabel.Text = '' return end
						ktLabel.Text = '【' .. (vkRoman[tier] or tostring(tier)) .. '】'
					elseif playerKit == 'aery' then
						ktLabel.TextColor3 = Color3.fromRGB(130, 210, 255)
						local stacks = ent.Player:GetAttribute('AeryStacks') or 0
						ktLabel.Text = '【' .. tostring(stacks) .. '】'
					elseif playerKit == 'mimic' then
						ktLabel.TextColor3 = Color3.fromRGB(180, 210, 60)
						ktLabel.Text = ''
						if not ktEventsBound then
							ktEventsBound = true
							if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
							task.spawn(function()
								if vape.ThreadFix then setthreadidentity(8) end
								table.insert(kitTrackerConnections[ent], bedwars.Client:OnEvent("ValidatedMimicBlock", function(p14)
									if not KitTracker.Enabled then ktLabel.Text = '' return end
									if vape.ThreadFix then setthreadidentity(8) end
									if p14.player == ent.Player then
										ktLabel.Text = '【 👔 】'
									else
										ktLabel.Text = ''
									end
								end))
								local val = workspace:FindFirstChild('DisguisedPlayerBlock_' .. ent.Player.UserId) ~= nil
								if val then ktLabel.Text = '【 👔 】' end
							end)
						end
					elseif playerKit == 'disruptor' then
						ktLabel.TextColor3 = Color3.fromRGB(40, 180, 140)
						if not ktEventsBound then
							ktEventsBound = true
							if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
							task.spawn(function()
								local worldFolder = getWorldFolder()
								local blocks = worldFolder:WaitForChild("Blocks", math.huge)
								table.insert(kitTrackerConnections[ent], blocks.ChildAdded:Connect(function(obj)
									if obj.Name == 'satellite_dish' and obj:GetAttribute('PlacedByUserId') == ent.Player.UserId then
									local billboard = Instance.new('BillboardGui')
									billboard.Parent = obj
									billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
									billboard.Size = UDim2.fromOffset(36, 36)
									billboard.AlwaysOnTop = true
									billboard.ClipsDescendants = false
									local blur = addBlur(billboard)
									blur.Visible = Background.Enabled
									local image = Instance.new('ImageLabel')
									image.Size = UDim2.fromOffset(36, 36)
									image.Position = UDim2.fromScale(0.5, 0.5)
									image.AnchorPoint = Vector2.new(0.5, 0.5)
									image.BackgroundColor3 = Color3.fromHSV(0, 0, 0)
									image.BackgroundTransparency = 0.85
									image.BorderSizePixel = 0
									image.Image = bedwars.getIcon({itemType = 'satellite_dish'}, true)
									image.Parent = billboard
									local uicorner = Instance.new('UICorner')
									uicorner.CornerRadius = UDim.new(0, 4)
									uicorner.Parent = image
									if not billboardCache[ent] then billboardCache[ent] = {} end
									table.insert(billboardCache[ent], billboard)
									end
								end))
							end)
						end
						ktLabel.Text = '【 ' .. (ent.Player:GetAttribute('DisruptorTarget') and ent.Player:GetAttribute('DisruptorTarget') .. ' Team' or 'Unknown Team') .. ' 】'
					elseif playerKit == 'winter_lady' then
						ktLabel.TextColor3 = Color3.fromRGB(200, 225, 255)
						local function getWandTier(v)
							local inv = store.inventories[v] and store.inventories[v].items or {}
							for _, item in inv do
								local nowstr = string.lower(item.itemType or '')
								if string.find(nowstr, 'frost_staff') then
									return tonumber(item.itemType:sub(#item.itemType, #item.itemType)) or 1
								end
							end
						end
						local tier = getWandTier(ent.Player)
						if not tier or tier < 0 then ktLabel.Text = '' return end
						ktLabel.Text = '【' .. (vkRoman[tier] or tostring(tier)) .. '】'
					elseif playerKit == 'warrior' then
						ktLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
						local grit = ent.Player:GetAttribute('Grit') or 0
						ktLabel.Text = '【 ' .. tostring(grit) .. '/100】'
					else
						ktLabel.Text = ''
					end
				end

				updateKtLabel()

				if ent.Character then
					if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
					table.insert(kitTrackerConnections[ent], ent.Character.AttributeChanged:Connect(function(attr)
						if attr == 'BlockKickerKit_BlockCount' or attr == 'StatusEffect_powdered_stacks' then
							updateKtLabel()
						end
					end))
					table.insert(kitTrackerConnections[ent], ent.Player.AttributeChanged:Connect(function(attr)
						if attr == 'DisruptorTarget' or attr == 'DisruptorActivation'
						or attr == 'AeryStacks' or attr == 'VoidKnightTier'
						or attr == 'PaladinStartTime' or attr == 'Summoner_ClawLevel'
						or attr == 'Grit' then
							updateKtLabel()
						end
					end))
					table.insert(kitTrackerConnections[ent], ent.Character.ChildAdded:Connect(function(child)
						if child.Name == 'elk' or string.find(child.Name, "wizard_staff") or string.find(child.Name, "frost_staff") then
							updateKtLabel()
						end
					end))
					table.insert(kitTrackerConnections[ent], ent.Character.ChildRemoved:Connect(function(child)
						if child and (child.Name == 'elk' or string.find(child.Name, "wizard_staff") or string.find(child.Name, "frost_staff")) then
							updateKtLabel()
						end
					end))
					table.insert(kitTrackerConnections[ent], workspace.ChildAdded:Connect(function(child)
						if child and child.Name:sub(1, 20) == 'DisguisedPlayerBlock' then
							updateKtLabel()
						end
					end))
					table.insert(kitTrackerConnections[ent], workspace.ChildRemoved:Connect(function(child)
						if child and child.Name:sub(1, 20) == 'DisguisedPlayerBlock' then
							updateKtLabel()
						end
					end))
				end
				if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
				table.insert(kitTrackerConnections[ent], ent.Player:GetAttributeChangedSignal('PlayingAsKits'):Connect(updateKtLabel))
			  end)
			end

			if Potions.Enabled then
				local baseX = -39 + ((Loot.Enabled and 3 or 0) + (NTBedBreak.Enabled and 2 or 0)) * 34
				for i, def in potionDefs do
					local iconSc = Scale.Value
					local Icon = Instance.new('ImageLabel')
					Icon.Name = def.name
					Icon.Size = udim2fromOffset(26 * iconSc, 26 * iconSc)
					Icon.Position = udim2fromOffset((baseX + ((i - 1) * 28)) * iconSc, (Equipment.Enabled and -58 or -30) * iconSc)
					Icon.BackgroundTransparency = 1
					Icon.Image = ''
					Icon.Parent = nametag
				end
			end

			if Loot.Enabled then
				local lootDefs = { LootIron = 'iron', LootDiamond = 'diamond', LootEmerald = 'emerald' }
				for i, v in { 'LootIron', 'LootDiamond', 'LootEmerald' } do
					makeCountSlot(nametag, v, -39 + ((i - 1) * 34), Equipment.Enabled and -58 or -30, Scale.Value)
				end

				local function applyLootIcons()
					if not (NameTags.Enabled and Loot.Enabled and nametag and nametag.Parent and ent.Player) then return end
					local inventory = store.inventories[ent.Player]
					if not inventory and bedwars.getInventory then
						inventory = bedwars.getInventory(ent.Player)
						if inventory then store.inventories[ent.Player] = inventory end
					end
					if not inventory then return end
					local counts = { iron = 0, diamond = 0, emerald = 0 }
					for _, it in inventory.items or {} do
						if counts[it.itemType] ~= nil then
							counts[it.itemType] = counts[it.itemType] + (it.amount or 0)
						end
					end
					for slot, nm in lootDefs do
						local ic = nametag:FindFirstChild(slot)
						if ic then
							local c = counts[nm]
							if c > 0 then
								ic.Image = bedwars.getIcon({ itemType = nm }, true)
								if ic.Amt then ic.Amt.Text = kCount(c) end
							else
								ic.Image = ''
								if ic.Amt then ic.Amt.Text = '' end
							end
						end
					end
				end

				applyLootIcons()
				if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
				table.insert(kitTrackerConnections[ent], vapeEvents.InventoryChanged.Event:Connect(function()
					if nametag and nametag.Parent then applyLootIcons() end
				end))
			end

			if NTBedBreak.Enabled and ent.Player then
				local bbX = Loot.Enabled and 63 or -39
				local bbY = Equipment.Enabled and -58 or -30
				makeCountSlot(nametag, 'LootTnt', bbX, bbY, Scale.Value)
				makeCountSlot(nametag, 'LootSiege', bbX + 34, bbY, Scale.Value)
				applyBedBreakIcon(ent, nametag)
				if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
				table.insert(kitTrackerConnections[ent], vapeEvents.InventoryChanged.Event:Connect(function()
					if NameTags.Enabled and nametag and nametag.Parent then applyBedBreakIcon(ent, nametag) end
				end))
			end

			if Equipment.Enabled then
				for i, v in { 'Hand', 'Helmet', 'Chestplate', 'Boots' } do
					local Icon = Instance.new('ImageLabel')
					Icon.Name = v
					local iconSc = Scale.Value
					Icon.Size = udim2fromOffset(30 * iconSc, 30 * iconSc)
					Icon.Position = udim2fromOffset((-60 + (i * 30)) * iconSc, -30 * iconSc)
					Icon.BackgroundTransparency = 1
					Icon.Image = ''
					Icon.Parent = nametag
					if v == 'Hand' then
						local amt = Instance.new('TextLabel')
						amt.Name = 'Amt'
						amt.AnchorPoint = Vector2.new(0, 1)
						amt.Position = UDim2.new(0, 0, 1, 0)
						amt.Size = UDim2.new(0, 14 * iconSc, 0, 10 * iconSc)
						amt.BackgroundTransparency = 1
						amt.Text = ''
						amt.TextColor3 = Color3.fromRGB(255, 255, 255)
						amt.TextStrokeTransparency = 0.4
						amt.TextSize = 10 * iconSc
						amt.Font = Enum.Font.GothamBold
						amt.TextXAlignment = Enum.TextXAlignment.Left
						amt.TextYAlignment = Enum.TextYAlignment.Bottom
						amt.Parent = Icon
					end
				end

				local equipRetry = nil
				local function applyEquipmentIcons(attempt)
					if not ent.Player then return end
					if not (NameTags.Enabled and Equipment.Enabled and nametag and nametag.Parent) then return end
					local inventory = store.inventories[ent.Player]
					if not inventory and bedwars.getInventory then
						inventory = bedwars.getInventory(ent.Player)
						if inventory then store.inventories[ent.Player] = inventory end
					end
					if not inventory then
						if equipRetry then task.cancel(equipRetry) end
						local wait = math.min(0.1 * (attempt or 1), 1)
						equipRetry = task.delay(wait, function()
							equipRetry = nil
							applyEquipmentIcons((attempt or 1) + 1)
						end)
						return
					end
					local handItem = inventory.hand
					local kit = ent.Player:GetAttribute('PlayingAsKits')
					local handImage = bedwars.getIcon(handItem or { itemType = '' }, true)
					if nametag.Hand then
						nametag.Hand.Image = handImage
						if nametag.Hand.Amt then
							local a = handItem and handItem.amount
							nametag.Hand.Amt.Text = (a and a > 1) and tostring(a) or ''
						end
					end
					if nametag.Helmet then nametag.Helmet.Image = bedwars.getIcon(inventory.armor and inventory.armor[4] or { itemType = '' }, true) end
					local chestImage = bedwars.getIcon(inventory.armor and inventory.armor[5] or { itemType = '' }, true)
					if kit == 'tinker' then
						local level = ent.Player:GetAttribute('TinkerMachineLevel')
						if level and level >= 1 and level <= 5 then
							local mechImg = getChainsawImage(level)
							if mechImg and mechImg ~= '' then
								chestImage = mechImg
							end
						end
					end
					if nametag.Chestplate then nametag.Chestplate.Image = chestImage end
					if nametag.Boots then nametag.Boots.Image = bedwars.getIcon(inventory.armor and inventory.armor[6] or { itemType = '' }, true) end
				end
				applyEquipmentIcons()
				if not kitTrackerConnections[ent] then kitTrackerConnections[ent] = {} end
				table.insert(kitTrackerConnections[ent], vapeEvents.InventoryChanged.Event:Connect(function()
					if nametag and nametag.Parent then
						applyEquipmentIcons()
					end
				end))

				if ent.Player then
					local attrConn = ent.Player:GetAttributeChangedSignal('TinkerMachineLevel'):Connect(function()
						if Equipment.Enabled and nametag and nametag.Parent then
							applyEquipmentIcons()
						end
					end)
					if not kitTrackerConnections[ent] then
						kitTrackerConnections[ent] = {}
					end
					table.insert(kitTrackerConnections[ent], attrConn)
				end
			end

			if ShowKits.Enabled and ent.Player then
				local kitIcon = Instance.new('ImageLabel')
				kitIcon.Name = 'KitIcon'
				kitIcon.Size = udim2fromOffset(30, 30)
				kitIcon.AnchorPoint = vector2new(0.5, 0)
				kitIcon.BackgroundTransparency = 1
				kitIcon.Image = ''

				if Equipment.Enabled then
					kitIcon.Position = udim2fromOffset(110, -30)
				else
					kitIcon.Position = UDim2.new(0.5, 0, 0, -35)
				end

				kitIcon.Parent = nametag

				local kit = ent.Player:GetAttribute('PlayingAsKits')
				if kit then
					local kitImage = kitImageIds[kit:lower()]
					kitIcon.Image = kitImage or kitImageIds["none"]
					kitCache[ent] = kitImage or kitImageIds["none"]
				else
					kitIcon.Image = kitImageIds["none"]
					kitCache[ent] = kitImageIds["none"]
				end
			end

			if DeviceIcon and DeviceIcon.Enabled and ent.Player then
				local deviceIcon = Instance.new('Frame')
				deviceIcon.Name = 'DeviceIcon'
				deviceIcon.Size = UDim2.fromOffset(24, 24)
				deviceIcon.Position = UDim2.new(1, 10, 0, 4)
				deviceIcon.BackgroundTransparency = 1
				deviceIcon.BorderSizePixel = 0
				deviceIcon.Parent = nametag

				local iconScale = Instance.new('UIScale')
				iconScale.Scale = 0.6
				iconScale.Parent = deviceIcon

				local function getPlayerDevice()
					local value = tostring(ent.Player:GetAttribute('UserInputType') or ''):lower()

					if value:find('mobile') or value:find('touch') then
						return 'Mobile'
					elseif value:find('gamepad') or value:find('controller') or value:find('console') then
						return 'Controller'
					elseif value:find('pc') or value:find('keyboard') or value:find('mouse') then
						return 'PC'
					end

					return 'Unknown'
				end

				local function drawPart(x, y, width, height, color, radius)
					local part = Instance.new('Frame')
					part.Size = UDim2.fromOffset(width, height)
					part.Position = UDim2.fromOffset(x, y)
					part.BackgroundColor3 = color
					part.BackgroundTransparency = 0
					part.BorderSizePixel = 0
					part.ZIndex = 2
					part.Parent = deviceIcon

					if radius and radius > 0 then
						local corner = Instance.new('UICorner')
						corner.CornerRadius = UDim.new(0, radius)
						corner.Parent = part
					end

					return part
				end

				local function updateDeviceIcon()
					for _, child in deviceIcon:GetChildren() do
						if child:IsA('GuiObject') then
							child:Destroy()
						end
					end

					local deviceType = getPlayerDevice()
					local white = Color3.fromRGB(240, 245, 255)

					if deviceType == 'Mobile' then
						drawPart(6, 1, 12, 21, white, 3)
						drawPart(8, 4, 8, 13, Color3.fromRGB(40, 160, 240), 1)
						drawPart(10, 2, 4, 1, Color3.fromRGB(70, 80, 100), 1)
						drawPart(11, 19, 2, 2, Color3.fromRGB(70, 80, 100), 1)

					elseif deviceType == 'PC' then
						drawPart(2, 2, 20, 14, white, 2)
						drawPart(4, 4, 16, 10, Color3.fromRGB(55, 160, 240), 1)
						drawPart(10, 16, 4, 3, white, 0)
						drawPart(6, 19, 12, 2, white, 1)

					elseif deviceType == 'Controller' then
						drawPart(1, 6, 22, 13, Color3.fromRGB(155, 100, 245), 6)
						drawPart(5, 11, 7, 2, white, 1)
						drawPart(7, 9, 2, 6, white, 1)
						drawPart(16, 10, 3, 3, Color3.fromRGB(80, 220, 255), 2)
						drawPart(19, 13, 3, 3, Color3.fromRGB(255, 190, 90), 2)

					else
						local unknown = Instance.new('TextLabel')
						unknown.Size = UDim2.fromScale(1, 1)
						unknown.BackgroundTransparency = 1
						unknown.Text = '?'
						unknown.TextColor3 = white
						unknown.TextSize = 18
						unknown.Font = Enum.Font.GothamBold
						unknown.ZIndex = 2
						unknown.Parent = deviceIcon
					end
				end

				updateDeviceIcon()

				if not kitTrackerConnections[ent] then
					kitTrackerConnections[ent] = {}
				end

				table.insert(kitTrackerConnections[ent],
					ent.Player:GetAttributeChangedSignal('UserInputType'):Connect(function()
						if deviceIcon.Parent then
							updateDeviceIcon()
						end
					end)
				)
			end

			if Rank.Enabled and ent.Player then
				local rankIcon = Instance.new('ImageLabel')
				rankIcon.Name = 'RankIcon'
				rankIcon.Size = udim2fromOffset(30, 30)
				rankIcon.Position = UDim2.new(1, (DeviceIcon and DeviceIcon.Enabled and 42 or 10), 0, -4)
				rankIcon.BackgroundTransparency = 1
				rankIcon.Image = ''
				rankIcon.Parent = nametag

				task.spawn(function()
					task.wait(math.random() * 0.5)
					if not NameTags.Enabled then return end
					if vape.ThreadFix then setthreadidentity(8) end
					local plr = playersService:GetPlayerFromCharacter(ent.Character)
					if not plr then return end
					if not rankIcon or not rankIcon.Parent then return end

					local ok, success, data = pcall(function()
						return bedwars.Client:Get(remotes.Ranks):CallServerAsync({ plr.UserId }):await()
					end)

					if vape.ThreadFix then setthreadidentity(8) end

					if ok and success and type(data) == "table" then
						local division = data[1] and data[1].rankDivision
						if division and bedwars.RankMeta and bedwars.RankMeta[division] then
							if rankIcon and rankIcon.Parent then
								rankIcon.Image = bedwars.RankMeta[division].image
							end
						end
					end
				end)
			end

			if GloopIndicator and GloopIndicator.Enabled and ent.Character then
				local gloopIcon = Instance.new('ImageLabel')
				gloopIcon.Name = 'GloopIcon'
				gloopIcon.Size = udim2fromOffset(24, 24)
				gloopIcon.BackgroundTransparency = 1
				gloopIcon.Image = bedwars.getIcon({itemType = 'glue_projectile'}, true)
				gloopIcon.Visible = false
				if Rank.Enabled and DeviceIcon and DeviceIcon.Enabled then
					gloopIcon.Position = UDim2.new(1, 74, 0, -2)
				elseif Rank.Enabled or (DeviceIcon and DeviceIcon.Enabled) then
					gloopIcon.Position = UDim2.new(1, 42, 0, -2)
				else
					gloopIcon.Position = UDim2.new(1, 10, 0, -2)
				end
				gloopIcon.Parent = nametag
				local gloopTimer = nil
				if gloopConnections[ent] then gloopConnections[ent]:Disconnect() end
				gloopConnections[ent] = ent.Character.AttributeChanged:Connect(function(attr)
					if attr ~= 'GlueSlow' then return end
					local val = ent.Character:GetAttribute('GlueSlow')
					if val ~= nil and val ~= 0 then
						gloopIcon.Visible = true
						if gloopTimer then task.cancel(gloopTimer) end
						gloopTimer = task.delay(10, function()
							gloopIcon.Visible = false
							gloopTimer = nil
						end)
					end
				end)
			end

			if Enchant.Enabled and ent.Player and ent.Character then
				local Icon = Instance.new('ImageLabel')
				Icon.Name = 'EnchantIcon'
				Icon.Size = udim2fromOffset(30, 30)
				Icon.Position = udim2fromOffset(-30, -4)
				Icon.BackgroundTransparency = 1
				Icon.Image = getActiveEnchantImage(ent.Character)
				Icon.Parent = nametag
				enchantCache[ent] = Icon.Image
				if enchantConnections[ent] then enchantConnections[ent]:Disconnect() end
				enchantConnections[ent] = ent.Character.AttributeChanged:Connect(function(attr)
					if attr:sub(1, 13) ~= 'StatusEffect_' then return end
					local val = ent.Character:GetAttribute(attr)
					if type(val) ~= 'number' then return end
					local newImage = getActiveEnchantImage(ent.Character)
					if enchantCache[ent] ~= newImage then
						Icon.Image = newImage
						enchantCache[ent] = newImage
					end
				end)
			end

			Reference[ent] = nametag
			charCache[ent] = ent.Character
			lastUpdate[ent] = 0
		end,

		Drawing = function(ent)
			if not shouldShow(ent) then return end
			if Reference[ent] then return end

			local bg = Drawing.new('Square')
			bg.Filled = true
			bg.Thickness = 0
			bg.Color = color3new(0, 0, 0)
			bg.Transparency = 1 - Background.Value
			bg.ZIndex = 1
			bg.Visible = false

			local text = Drawing.new('Text')
			text.Center = false
			text.Outline = true
			text.OutlineColor = color3new(0, 0, 0)
			text.Size = math_round(14 * Scale.Value)
			text.Font = 2
			text.Color = getTeamColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
			text.ZIndex = 2
			text.Visible = false

			local baseName = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or (getBossDisplayName(ent) or (ent.Character and ent.Character.Name)) or ''
			local built = baseName
			if Health.Enabled then built = built .. ' ' .. healthPlain(ent) end
			if ShowKits.Enabled and ent.Player then
				local kit = ent.Player:GetAttribute('PlayingAsKits')
				if kit then
					built = built .. ' (' .. (kit:gsub('_', ' '):gsub('^%l', string.upper)) .. ')'
				end
			end
			if Distance.Enabled then
				Strings[ent] = '[%s] ' .. built
			else
				Strings[ent] = built
				text.Text = built
				bg.Size = vector2new(text.TextBounds.X + 8, text.TextBounds.Y + 7)
			end

			Reference[ent] = {Text = text, BG = bg}
			charCache[ent] = ent.Character
		end
	}

	Removed = {
		Normal = function(ent)
			local v = Reference[ent]
			if v then
				Reference[ent] = nil
				Strings[ent] = nil
				Sizes[ent] = nil
				lastUpdate[ent] = nil
				kitCache = {}
				equipmentCache = {}
				lootCache = {}
				enchantCache = {}
				healthCache[ent] = nil
				charCache[ent] = nil
				if enchantConnections[ent] then
					enchantConnections[ent]:Disconnect()
					enchantConnections[ent] = nil
				end
				if gloopConnections[ent] then
					gloopConnections[ent]:Disconnect()
					gloopConnections[ent] = nil
				end
				if kitTrackerConnections[ent] then
					for _, c in ipairs(kitTrackerConnections[ent]) do
						pcall(function() c:Disconnect() end)
					end
					kitTrackerConnections[ent] = nil
				end
				if billboardCache[ent] then
					for _, b in ipairs(billboardCache[ent]) do
						pcall(function() b:Destroy() end)
					end
					billboardCache[ent] = nil
				end
				v:Destroy()
			end
		end,
		Drawing = function(ent)
			local v = Reference[ent]
			if v then
				Reference[ent] = nil
				Strings[ent] = nil
				Sizes[ent] = nil
				lastUpdate[ent] = nil
				kitCache[ent] = nil
				healthCache[ent] = nil
				if enchantConnections[ent] then
					enchantConnections[ent]:Disconnect()
					enchantConnections[ent] = nil
				end
				if gloopConnections[ent] then
					gloopConnections[ent]:Disconnect()
					gloopConnections[ent] = nil
				end
				if billboardCache[ent] then
					for _, b in ipairs(billboardCache[ent]) do
						pcall(function() b:Destroy() end)
					end
					billboardCache[ent] = nil
				end
				for _, obj in v do
					pcall(function()
						obj.Visible = false
						obj:Remove()
					end)
				end
			end
		end
	}

	local Updated = {
		Normal = function(ent)
			local nametag = Reference[ent]
			if not nametag then return end

			local now = tick()
			if lastUpdate[ent] and (now - lastUpdate[ent]) < 0.2 then return end
			lastUpdate[ent] = now

			Sizes[ent] = nil
			local bossDisplayName = ent.NPC and ent.Character and getBossDisplayName(ent) or nil
			local entityName = bossDisplayName or (ent.Player and nil) or ent.Character.Name
			Strings[ent] = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or entityName

			if Health.Enabled then
				Strings[ent] = Strings[ent]..' '..healthRich(ent)
			end

			if Distance.Enabled then
				Strings[ent] = '[%s] ' .. Strings[ent]
			end

			if Equipment.Enabled and ent.Player then
				if not store.inventories[ent.Player] and bedwars.getInventory then
					local fetched = bedwars.getInventory(ent.Player)
					if fetched then store.inventories[ent.Player] = fetched end
				end
				local inventory = store.inventories[ent.Player] or {hand = nil, armor = {}}
				local handItem = inventory.hand
				local kit = ent.Player:GetAttribute('PlayingAsKits')
				local handImage = bedwars.getIcon(handItem or { itemType = '' }, true)
				local chestImage = bedwars.getIcon(inventory.armor and inventory.armor[5] or { itemType = '' }, true)
				if kit == 'tinker' then
					local level = ent.Player:GetAttribute('TinkerMachineLevel')
					if level and level >= 1 and level <= 5 then
						local mechImg = getChainsawImage(level)
						if mechImg and mechImg ~= '' then
							chestImage = mechImg
						end
					end
				end
				local currentEquip = {
					tostring(handItem and handItem.itemType or ''),
					tostring((inventory.armor and inventory.armor[4] and inventory.armor[4].itemType) or ''),
					tostring((inventory.armor and inventory.armor[5] and inventory.armor[5].itemType) or ''),
					tostring((inventory.armor and inventory.armor[6] and inventory.armor[6].itemType) or '')
				}
				local equipKey = table.concat(currentEquip, "|")
				if equipmentCache[ent] ~= equipKey then
					equipmentCache[ent] = equipKey
					if nametag.Hand then
						nametag.Hand.Image = handImage
						if nametag.Hand.Amt then
							local a = handItem and handItem.amount
							nametag.Hand.Amt.Text = (a and a > 1) and tostring(a) or ''
						end
					end
					if nametag.Helmet then
						nametag.Helmet.Image = bedwars.getIcon(inventory.armor and inventory.armor[4] or { itemType = '' }, true)
					end
					if nametag.Chestplate then
						nametag.Chestplate.Image = chestImage
					end
					if nametag.Boots then
						nametag.Boots.Image = bedwars.getIcon(inventory.armor and inventory.armor[6] or { itemType = '' }, true)
					end
				end
			end

			local size = getfontsize(removeTags(Strings[ent]), nametag.TextSize, nametag.FontFace, vector2new(100000, 100000))
			nametag.Size = udim2fromOffset(size.X + 8, size.Y + 7)
			nametag.Text = Strings[ent]
			nametag.TextColor3 = getTeamColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
		end,

		Drawing = function(ent)
			local nametag = Reference[ent]
			if nametag then
				if vape.ThreadFix then setthreadidentity(8) end
				Sizes[ent] = nil
				local bossDisplayName = ent.NPC and ent.Character and getBossDisplayName(ent) or nil
				local entityName = bossDisplayName or (ent.Player and nil) or ent.Character.Name
				Strings[ent] = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or entityName

				if Health.Enabled then
					Strings[ent] = Strings[ent]..' '..healthPlain(ent)
					nametag.Text.Color = getHealthColor(ent)
				end

				if Distance.Enabled then
					Strings[ent] = '[%s] ' .. Strings[ent]
					nametag.Text.Text = entitylib.isAlive and string_format(Strings[ent], math_floor((entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude)) or Strings[ent]
				else
					nametag.Text.Text = Strings[ent]
				end

				if ShowKits.Enabled and ent.Player then
					local kit = ent.Player:GetAttribute('PlayingAsKits')
					if kit then
						local kitName = kit:gsub("_", " "):gsub("^%l", string.upper)
						nametag.Text.Text = nametag.Text.Text .. ' (' .. kitName .. ')'
					end
				end

				nametag.BG.Size = vector2new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
				if not Health.Enabled then
					nametag.Text.Color = getTeamColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
				end
			end
		end
	}

	local ColorFunc = {
		Normal = function(hue, sat, val)
			local color = color3fromHSV(hue, sat, val)
			for i, v in Reference do
				v.TextColor3 = getTeamColor(i) or color
			end
		end,
		Drawing = function(hue, sat, val)
			local color = color3fromHSV(hue, sat, val)
			for i, v in Reference do
				if not Health.Enabled then
					v.Text.Color = getTeamColor(i) or color
				end
			end
		end
	}

	local frameCounter = 0
	Loop = {
		Normal = function()
			frameCounter = frameCounter + 1
			local skipVisCheck = frameCounter % 2 ~= 0
			local updateDistText = frameCounter % 3 == 0
			local updateEquipment = frameCounter % 30 == 0
			local forceEquip = frameCounter % 150 == 0
			local updateKit = frameCounter % 30 == 0
			local updateDistanceText = frameCounter % 6 == 0
			local myPos = entitylib.isAlive and entitylib.character.RootPart and entitylib.character.RootPart.Position

			for ent, nametag in Reference do
				if not ent.RootPart or not ent.Character or not ent.Character.Parent or (ent.Health ~= nil and ent.Health <= 0) then
					nametag.Visible = false
					continue
				end
				if DistanceCheck.Enabled then
					local distance = myPos and (myPos - ent.RootPart.Position).Magnitude or math_huge
					if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
						nametag.Visible = false
						continue
					end
				end

				local headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + vector3new(0, ent.HipHeight + 1, 0))
				if not skipVisCheck then
					nametag.Visible = headVis
				end
				if not nametag.Visible or not headVis then continue end
				nametag.Position = udim2fromOffset(headPos.X, headPos.Y)

				if Health.Enabled and (frameCounter % 2 == 0) then
					local hp = healthRich(ent)
					if healthCache[ent] ~= hp then
						healthCache[ent] = hp
						local baseName = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or (getBossDisplayName(ent) or (ent.Character and ent.Character.Name)) or ''
						Strings[ent] = baseName..' '..hp
						if Distance.Enabled then
							Strings[ent] = '[%s] ' .. Strings[ent]
						else
							nametag.Text = Strings[ent]
							local size = getfontsize(removeTags(nametag.Text), nametag.TextSize, nametag.FontFace, vector2new(100000, 100000))
							nametag.Size = udim2fromOffset(size.X + 8, size.Y + 7)
						end
						Sizes[ent] = nil
					end
				end

				if Distance.Enabled and updateDistText then
					local mag = myPos and math_floor((myPos - ent.RootPart.Position).Magnitude) or 0
					if Sizes[ent] ~= mag then
						nametag.Text = string_format(Strings[ent], mag)
						if updateDistanceText then
							local size = getfontsize(removeTags(nametag.Text), nametag.TextSize, nametag.FontFace, vector2new(100000, 100000))
							nametag.Size = udim2fromOffset(size.X + 8, size.Y + 7)
						end
						Sizes[ent] = mag
					end
				end

				if Equipment.Enabled and (updateEquipment or forceEquip) then
					if ent.Player and not store.inventories[ent.Player] and bedwars.getInventory then
						local fetched = bedwars.getInventory(ent.Player)
						if fetched then store.inventories[ent.Player] = fetched end
					end
					if ent.Player and store.inventories[ent.Player] then
						local inventory = store.inventories[ent.Player]
						local handItem = inventory.hand
						local currentEquip = {
							(handItem and handItem.itemType) or '',
							(inventory.armor and inventory.armor[4] and inventory.armor[4].itemType) or '',
							(inventory.armor and inventory.armor[5] and inventory.armor[5].itemType) or '',
							(inventory.armor and inventory.armor[6] and inventory.armor[6].itemType) or ''
						}
						local equipKey = table.concat(currentEquip, "|")
						local iconsBlank = nametag.Hand and (nametag.Hand.Image == '' or nametag.Hand.Image == nil)
						if equipmentCache[ent] ~= equipKey or forceEquip or (iconsBlank and equipKey ~= "|||") then
							local kit = ent.Player:GetAttribute('PlayingAsKits')
							local handImage = bedwars.getIcon(handItem or { itemType = '' }, true)
							local chestImage = bedwars.getIcon(inventory.armor and inventory.armor[5] or { itemType = '' }, true)
							if kit == 'tinker' then
								local level = ent.Player:GetAttribute('TinkerMachineLevel')
								if level and level >= 1 and level <= 5 then
									local mechImg = getChainsawImage(level)
									if mechImg and mechImg ~= '' then
										chestImage = mechImg
									end
								end
							end
							equipmentCache[ent] = equipKey
							if nametag.Hand then
								nametag.Hand.Image = handImage
								if nametag.Hand.Amt then
									local a = handItem and handItem.amount
									nametag.Hand.Amt.Text = (a and a > 1) and tostring(a) or ''
								end
							end
							if nametag.Helmet then
								nametag.Helmet.Image = bedwars.getIcon(inventory.armor and inventory.armor[4] or { itemType = '' }, true)
							end
							if nametag.Chestplate then
								nametag.Chestplate.Image = chestImage
							end
							if nametag.Boots then
								nametag.Boots.Image = bedwars.getIcon(inventory.armor and inventory.armor[6] or { itemType = '' }, true)
							end
						end
					elseif ent.Player then
						equipmentCache[ent] = nil
					end
				end

				if Loot.Enabled and (updateEquipment or forceEquip) and ent.Player and nametag.LootIron then
					local inv = store.inventories[ent.Player]
					if not inv and bedwars.getInventory then
						inv = bedwars.getInventory(ent.Player)
						if inv then store.inventories[ent.Player] = inv end
					end
					if inv and inv.items then
						local counts = { iron = 0, diamond = 0, emerald = 0 }
						for _, it in inv.items do
							local c = counts[it.itemType]
							if c then
								counts[it.itemType] = c + (it.amount or 0)
							end
						end
						local lootKey = counts.iron .. '|' .. counts.diamond .. '|' .. counts.emerald
						if lootCache[ent] ~= lootKey or forceEquip then
							lootCache[ent] = lootKey
							for slot, nm in { LootIron = 'iron', LootDiamond = 'diamond', LootEmerald = 'emerald' } do
								local ic = nametag:FindFirstChild(slot)
								if ic then
									local c = counts[nm]
									if c > 0 then
										ic.Image = bedwars.getIcon({ itemType = nm }, true)
										if ic.Amt then ic.Amt.Text = kCount(c) end
									else
										ic.Image = ''
										if ic.Amt then ic.Amt.Text = '' end
									end
								end
							end
						end
					end
				end

				if NTBedBreak.Enabled and (updateEquipment or forceEquip) and ent.Player then
					applyBedBreakIcon(ent, nametag)
				end

				if Potions.Enabled and (updateEquipment or forceEquip) then
					local char = ent.Character
					for _, def in potionDefs do
						local ic = nametag:FindFirstChild(def.name)
						if ic then
							local want = potionActive(char, def) and bedwars.getIcon({itemType = def.item}, true) or ''
							if ic.Image ~= want then
								ic.Image = want
							end
						end
					end
				end

				if ShowKits.Enabled and updateKit then
					local kitIcon = nametag:FindFirstChild('KitIcon')
					if kitIcon and ent.Player then
						local kit = ent.Player:GetAttribute('PlayingAsKits')
						local meta = bedwars.BedwarsKitMeta and kit and bedwars.BedwarsKitMeta[kit]
						local newKitImage = (meta and meta.renderImage) or kitImageIds[kit] or kitImageIds['none']
						if kitCache[ent] ~= newKitImage then
							kitIcon.Image = newKitImage
							kitCache[ent] = newKitImage
						end
					end
				end
			end
		end,

		Drawing = function()
			frameCounter = frameCounter + 1
			local skipFrame = frameCounter % 2 ~= 0

			for ent, nametag in Reference do
				if not ent.RootPart or (ent.Health ~= nil and ent.Health <= 0) then
					if not nametag:GetAttribute('DeadHidden') then
						nametag:SetAttribute('DeadHidden', true)
						for _, child in nametag:GetChildren() do
							if child:IsA('GuiObject') then child.Visible = false end
						end
					end
					continue
				end
				if nametag:GetAttribute('DeadHidden') then
					nametag:SetAttribute('DeadHidden', nil)
					for _, child in nametag:GetChildren() do
						if child:IsA('GuiObject') then child.Visible = true end
					end
				end
				if DistanceCheck.Enabled then
					local distance = entitylib.isAlive and (entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude or math_huge
					if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
						nametag.Text.Visible = false
						nametag.BG.Visible = false
						continue
					end
				end

				local headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + vector3new(0, ent.HipHeight + 1, 0))
				nametag.Text.Visible = headVis
				nametag.BG.Visible = headVis
				if not headVis then continue end
				if skipFrame then continue end

				if Health.Enabled then
					nametag.Text.Color = getHealthColor(ent)
					local hp = healthPlain(ent)
					if healthCache[ent] ~= hp then
						healthCache[ent] = hp
						local baseName = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or (getBossDisplayName(ent) or (ent.Character and ent.Character.Name)) or ''
						local built = baseName..' '..hp
						if ShowKits.Enabled and ent.Player then
							local kit = ent.Player:GetAttribute('PlayingAsKits')
							if kit then
								built = built..' ('..(kit:gsub('_', ' '):gsub('^%l', string.upper))..')'
							end
						end
						if Distance.Enabled then
							Strings[ent] = '[%s] '..built
						else
							Strings[ent] = built
							nametag.Text.Text = built
							nametag.BG.Size = vector2new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
						end
						Sizes[ent] = nil
					end
				end

				if Distance.Enabled then
					local mag = entitylib.isAlive and math_floor((entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude) or 0
					if Sizes[ent] ~= mag then
						nametag.Text.Text = string_format(Strings[ent], mag)
						nametag.BG.Size = vector2new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
						Sizes[ent] = mag
					end
				end

				nametag.BG.Position = vector2new(headPos.X - (nametag.BG.Size.X / 2), headPos.Y - nametag.BG.Size.Y)
				nametag.Text.Position = nametag.BG.Position + vector2new(4, 3)
			end
		end
	}

	NameTags = vape.Categories.Render:CreateModule({
		Name = 'NameTags',
		Function = function(callback)
			nameTagRun += 1
			local myRun = nameTagRun
			if callback then
				methodused = StreamProof.Enabled and 'Drawing' or 'Normal'
				frameCounter = 0

				if Removed[methodused] then
					NameTags:Clean(entitylib.Events.EntityRemoved:Connect(Removed[methodused]))
				end

				if Added[methodused] then
					for _, v in entitylib.List do
						if Reference[v] then Removed[methodused](v) end
						pcall(Added[methodused], v)
					end
					task.spawn(function()
						task.wait(1)
						if not NameTags.Enabled or myRun ~= nameTagRun then return end
						for _, v in entitylib.List do
							if Reference[v] then Removed[methodused](v) end
							pcall(Added[methodused], v)
						end
					end)
					NameTags:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
						task.spawn(function()
							task.wait(0.5)
							if not NameTags.Enabled or myRun ~= nameTagRun then return end
							if not ent.Character or not ent.Character.Parent then
								if Reference[ent] then Removed[methodused](ent) end
								return
							end
							if Reference[ent] then Removed[methodused](ent) end
							pcall(Added[methodused], ent)
						end)
					end))
					NameTags:Clean(playersService.PlayerAdded:Connect(function(p)
						NameTags:Clean(p.CharacterAdded:Connect(function()
							task.delay(0.3, function()
								if not NameTags.Enabled or myRun ~= nameTagRun then return end
								for _, v in entitylib.List do
									if v.Player == p and not Reference[v] then
										pcall(Added[methodused], v)
									end
								end
							end)
						end))
					end))
				end

				if Updated[methodused] then
					NameTags:Clean(entitylib.Events.EntityUpdated:Connect(function(ent)
						local show = shouldShow(ent)
						if show and not Reference[ent] then
							pcall(Added[methodused], ent)
							return
						elseif not show and Reference[ent] then
							Removed[methodused](ent)
							return
						end
						if Reference[ent] and charCache[ent] ~= ent.Character then
							Removed[methodused](ent)
							pcall(Added[methodused], ent)
							return
						end
						Updated[methodused](ent)
					end))
					for _, v in entitylib.List do
						pcall(Updated[methodused], v)
					end
				end

				if ColorFunc[methodused] then
					NameTags:Clean(vape.Categories.Friends.ColorUpdate.Event:Connect(function()
						ColorFunc[methodused](Color.Hue, Color.Sat, Color.Value)
					end))
				end

				if Loop[methodused] then
					NameTags:Clean(runService.RenderStepped:Connect(Loop[methodused]))
				end

				if Added[methodused] then
					task.spawn(function()
						while NameTags.Enabled and myRun == nameTagRun do
							task.wait(0.5)
							if not NameTags.Enabled or myRun ~= nameTagRun then break end
							local tracked = {}
							for _, v in entitylib.List do
								tracked[v] = true
							end
							for v in Reference do
								if not tracked[v] or not v.Character or not v.Character.Parent then
									pcall(Removed[methodused], v)
								end
							end
							for _, v in entitylib.List do
								if v.Character and v.Character.Parent and shouldShow(v) then
									if not Reference[v] then
										pcall(Added[methodused], v)
									elseif charCache[v] ~= v.Character then
										Removed[methodused](v)
										pcall(Added[methodused], v)
									end
								end
							end
						end
					end)
				end
			else
				if Removed[methodused] then
					for i in Reference do
						Removed[methodused](i)
					end
				end
				lastUpdate = {}
				kitCache = {}
				equipmentCache = {}
				enchantCache = {}
				healthCache = {}
				enchantConnections = {}
				gloopConnections = {}
				kitTrackerConnections = {}
				for _, list in pairs(billboardCache) do
					for _, b in ipairs(list) do
						pcall(function() b:Destroy() end)
					end
				end
				billboardCache = {}
			end
		end,
		Tooltip = 'renders nametags on entities through walls.'
	})

	Targets = NameTags:CreateTargets({
		Players = true,
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	FontOption = NameTags:CreateFont({
		Name = 'Font',
		Blacklist = 'Arial',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	Color = NameTags:CreateColorSlider({
		Name = 'Player Color',
		Function = function(hue, sat, val)
			if NameTags.Enabled and ColorFunc[methodused] then
				ColorFunc[methodused](hue, sat, val)
			end
		end
	})

	Scale = NameTags:CreateSlider({
		Name = 'Scale',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end,
		Default = 1,
		Min = 0.1,
		Max = 1.5,
		Decimal = 10
	})

	Background = NameTags:CreateSlider({
		Name = 'Transparency',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end,
		Default = 0.5,
		Min = 0,
		Max = 1,
		Decimal = 10
	})

	Health = NameTags:CreateToggle({
		Name = 'Health',
		Function = function(callback)
			HealthColorToggle.Object.Visible = callback
			HealthColorFull.Object.Visible = callback and HealthColorToggle.Enabled
			HealthColorMid.Object.Visible = callback and HealthColorToggle.Enabled
			HealthColorLow.Object.Visible = callback and HealthColorToggle.Enabled
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	HealthColorToggle = NameTags:CreateToggle({
		Name = 'Custom Health Colors',
		Darker = true,
		Visible = false,
		Function = function(callback)
			HealthColorFull.Object.Visible = callback
			HealthColorMid.Object.Visible = callback
			HealthColorLow.Object.Visible = callback
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	HealthColorFull = NameTags:CreateColorSlider({
		Name = 'Full HP Color',
		Darker = true,
		Visible = false,
		DefaultHue = 0.4,
		DefaultSat = 0.89,
		DefaultValue = 0.75,
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	HealthColorMid = NameTags:CreateColorSlider({
		Name = 'Mid HP Color',
		Darker = true,
		Visible = false,
		DefaultHue = 0.15,
		DefaultSat = 0.89,
		DefaultValue = 0.75,
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	HealthColorLow = NameTags:CreateColorSlider({
		Name = 'Low HP Color',
		Darker = true,
		Visible = false,
		DefaultHue = 0,
		DefaultSat = 0.89,
		DefaultValue = 0.75,
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	Distance = NameTags:CreateToggle({
		Name = 'Distance',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	Loot = NameTags:CreateToggle({
		Name = 'Loot',
		Tooltip = 'shows how much iron/diamond/emerald they got',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})
	NTBedBreak = NameTags:CreateToggle({
		Name = 'Bed Break',
		Tooltip = 'shows if they got tnt or siege tnt on em so u know they tryna break ur bed',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})
	Potions = NameTags:CreateToggle({
		Name = 'Potions',
		Tooltip = 'shows if they popped serpent, fury, invis, jump or speed pie',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})
	Equipment = NameTags:CreateToggle({
		Name = 'Equipment',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	ShowKits = NameTags:CreateToggle({
		Name = 'Show Kits',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end,
	})

	KitTracker = NameTags:CreateToggle({
		Name = 'Kit Tracker',
		Tooltip = 'shows stats for certain kits on a player',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	Rank = NameTags:CreateToggle({
		Name = 'Rank',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	DeviceIcon = NameTags:CreateToggle({
		Name = 'Device Icon',
		Tooltip = 'shows what device the player is using',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	GloopIndicator = NameTags:CreateToggle({
		Name = 'Gloop',
		Default = true,
		Tooltip = 'shows when a player is glooped and not glooped anymore',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	Enchant = NameTags:CreateToggle({
		Name = 'Enchant',
		Tooltip = 'shows the player current enchant',
		Default = true,
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	DisplayName = NameTags:CreateToggle({
		Name = 'Use Displayname',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end,
		Default = true
	})

	Teammates = NameTags:CreateToggle({
		Name = 'Priority Only',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end,
		Default = true
	})

	StreamProof = NameTags:CreateToggle({
		Name = 'Stream Proof',
		Default = false,
		Tooltip = 'uses drawing api so its stream proof if u record within roblox (text only, no icons)',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	Boss = NameTags:CreateToggle({
		Name = 'Boss',
		Tooltip = 'nametags for titan and bhaa (really good if u use health too!!)',
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})

	DistanceCheck = NameTags:CreateToggle({
		Name = 'Distance Check',
		Function = function(callback)
			DistanceLimit.Object.Visible = callback
		end
	})

	DistanceLimit = NameTags:CreateTwoSlider({
		Name = 'Player Distance',
		Min = 0,
		Max = 256,
		DefaultMin = 0,
		DefaultMax = 64,
		Darker = true,
		Visible = false
	})

	task.defer(function()
		if DistanceLimit and DistanceLimit.Object then
			DistanceLimit.Object.Visible = false
		end
		if HealthColorToggle and HealthColorToggle.Object then
			HealthColorToggle.Object.Visible = false
		end
		if HealthColorFull and HealthColorFull.Object then
			HealthColorFull.Object.Visible = false
		end
		if HealthColorMid and HealthColorMid.Object then
			HealthColorMid.Object.Visible = false
		end
		if HealthColorLow and HealthColorLow.Object then
			HealthColorLow.Object.Visible = false
		end
	end)
end)

run(function()
	local GeneratorESP
	local DiamondToggle
	local EmeraldToggle
	local TeamGenToggle
	local ShowOwnTeamGen
	local ShowEnemyTeamGen
	local UIStyle
	local CompactDiamondToggle
	local CompactEmeraldToggle
	local CollectionService = collectionService
	local RunService = runService
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local CompactFolder = Instance.new('Folder')
	CompactFolder.Parent = vape.gui
	local teamColors = getgenv().aeroTeamColors

	local generatorTypes = {
		diamond = {
			keywords = {'diamond'},
			color = Color3.fromRGB(85, 200, 255),
			icon = 'diamond',
			displayName = 'Diamond',
			isTeamGen = false
		},
		emerald = {
			keywords = {'emerald'},
			color = Color3.fromRGB(0, 255, 100),
			icon = 'emerald',
			displayName = 'Emerald',
			isTeamGen = false
		}
	}

	local compactUI = Instance.new('ScreenGui')
	compactUI.Name = 'GeneratorCompactUI'
	compactUI.Parent = vape.gui
	compactUI.Enabled = false
	compactUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	compactUI.DisplayOrder = 10
	compactUI.ResetOnSpawn = false

	local mainFrame = Instance.new('Frame')
	mainFrame.Name = 'MainFrame'
	mainFrame.Parent = compactUI
	mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	mainFrame.BackgroundTransparency = 0.3
	mainFrame.BorderSizePixel = 0
	mainFrame.Position = UDim2.new(1, -8, 1, -8)
	mainFrame.Size = UDim2.new(0, 120, 0, 100)
	mainFrame.AnchorPoint = Vector2.new(1, 1)

	local uicorner = Instance.new('UICorner')
	uicorner.CornerRadius = UDim.new(0, 8)
	uicorner.Parent = mainFrame

	local title = Instance.new('TextLabel')
	title.Name = 'Title'
	title.Parent = mainFrame
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 25)
	title.Position = UDim2.new(0, 0, 0, 5)
	title.Text = "GEN ESP"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.TextStrokeTransparency = 0.5
	title.TextStrokeColor3 = Color3.new(0, 0, 0)

	local diamondFrame = Instance.new('Frame')
	diamondFrame.Name = 'DiamondFrame'
	diamondFrame.Parent = mainFrame
	diamondFrame.BackgroundTransparency = 1
	diamondFrame.Size = UDim2.new(1, -20, 0, 25)
	diamondFrame.Position = UDim2.new(0, 10, 0, 35)

	local diamondIcon = Instance.new('ImageLabel')
	diamondIcon.Name = 'DiamondIcon'
	diamondIcon.Parent = diamondFrame
	diamondIcon.BackgroundTransparency = 1
	diamondIcon.Size = UDim2.new(0, 18, 0, 18)
	diamondIcon.Position = UDim2.new(0, 0, 0.5, -9)
	diamondIcon.Image = bedwars.getIcon({itemType = 'diamond'}, true)

	local diamondTimer = Instance.new('TextLabel')
	diamondTimer.Name = 'DiamondTimer'
	diamondTimer.Parent = diamondFrame
	diamondTimer.BackgroundTransparency = 1
	diamondTimer.Size = UDim2.new(1, -25, 1, 0)
	diamondTimer.Position = UDim2.new(0, 25, 0, 0)
	diamondTimer.Text = "00"
	diamondTimer.TextColor3 = Color3.fromRGB(85, 200, 255)
	diamondTimer.TextSize = 18
	diamondTimer.Font = Enum.Font.GothamBold
	diamondTimer.TextXAlignment = Enum.TextXAlignment.Left

	local emeraldFrame = Instance.new('Frame')
	emeraldFrame.Name = 'EmeraldFrame'
	emeraldFrame.Parent = mainFrame
	emeraldFrame.BackgroundTransparency = 1
	emeraldFrame.Size = UDim2.new(1, -20, 0, 25)
	emeraldFrame.Position = UDim2.new(0, 10, 0, 65)

	local emeraldIcon = Instance.new('ImageLabel')
	emeraldIcon.Name = 'EmeraldIcon'
	emeraldIcon.Parent = emeraldFrame
	emeraldIcon.BackgroundTransparency = 1
	emeraldIcon.Size = UDim2.new(0, 18, 0, 18)
	emeraldIcon.Position = UDim2.new(0, 0, 0.5, -9)
	emeraldIcon.Image = bedwars.getIcon({itemType = 'emerald'}, true)

	local emeraldTimer = Instance.new('TextLabel')
	emeraldTimer.Name = 'EmeraldTimer'
	emeraldTimer.Parent = emeraldFrame
	emeraldTimer.BackgroundTransparency = 1
	emeraldTimer.Size = UDim2.new(1, -25, 1, 0)
	emeraldTimer.Position = UDim2.new(0, 25, 0, 0)
	emeraldTimer.Text = "00"
	emeraldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
	emeraldTimer.TextSize = 18
	emeraldTimer.Font = Enum.Font.GothamBold
	emeraldTimer.TextXAlignment = Enum.TextXAlignment.Left

	local diamondTimes = {}
	local emeraldTimes = {}

	local function getMyTeamId()
		local myTeam = lplr:GetAttribute('Team')
		if myTeam == nil then return nil end
		return tonumber(myTeam)
	end

	local function getGeneratorTeamId(generatorId)
		local teamNum = string.match(generatorId, "^(%d+)_generator")
		if teamNum then
			return tonumber(teamNum)
		end
		return nil
	end

	local function isTeamGenerator(generatorId)
		return string.match(generatorId, "^%d+_generator") ~= nil
	end

	local function getGeneratorType(generatorId)
		local idLower = string.lower(generatorId)

		if isTeamGenerator(generatorId) then
			return 'teamgen', {
				color = Color3.fromRGB(200, 200, 200),
				icon = 'iron',
				displayName = 'Team Gen',
				isTeamGen = true
			}
		end

		for genType, config in pairs(generatorTypes) do
			for _, keyword in ipairs(config.keywords) do
				if idLower:find(keyword) then
					return genType, config
				end
			end
		end
		return nil, nil
	end

	local function isGeneratorEnabled(genType, teamId)
		if genType == 'diamond' then
			return DiamondToggle.Enabled
		elseif genType == 'emerald' then
			return EmeraldToggle.Enabled
		elseif genType == 'teamgen' then
			if not TeamGenToggle.Enabled then return false end
			local myTeamId = getMyTeamId()
			if not myTeamId or not teamId then return TeamGenToggle.Enabled end
			if teamId == myTeamId then
				return ShowOwnTeamGen.Enabled
			else
				return ShowEnemyTeamGen.Enabled
			end
		end
		return false
	end

	local function getProperIcon(iconType)
		local icon = bedwars.getIcon({itemType = iconType}, true)
		if not icon or icon == "" then return nil end
		return icon
	end

	local function getTierText(generatorAdornee)
		if not generatorAdornee then return nil end
		if generatorAdornee.Name ~= 'GeneratorAdornee' then return nil end
		local reactTree = generatorAdornee:FindFirstChild('RoactTree')
		if not reactTree then return nil end
		local teamApp = reactTree:FindFirstChild('TeamOreGeneratorApp')
		if not teamApp then return nil end
		local globalGen = teamApp:FindFirstChild('GlobalOreGenerator')
		if globalGen then
			for _, child in pairs(globalGen:GetDescendants()) do
				if child:IsA('TextLabel') then
					local text = child.Text
					if text:find("Tier") or text:match("^[IVX]+$") or text == "0" then
						return child
					end
				end
			end
		end
		local teamGenMain = teamApp:FindFirstChild('TeamGenMain')
		if teamGenMain then
			for _, child in pairs(teamGenMain:GetDescendants()) do
				if child:IsA('TextLabel') then
					local text = child.Text
					if text:find("Tier") or text:match("^[IVX]+$") or text == "0" then
						return child
					end
				end
			end
		end
		return nil
	end

	local function extractTierLevel(tierText)
		if not tierText or tierText == "" then return "0" end
		if tierText == "0" then return "0" end
		local tierMatch = tierText:match("Tier%s+([IVX]+)")
		if tierMatch then return tierMatch end
		if tierText:match("^[IVX]+$") then return tierText end
		local numTier = tierText:match("Tier%s+(%d+)")
		if numTier then
			local num = tonumber(numTier)
			if num == 0 then return "0"
			elseif num == 1 then return "I"
			elseif num == 2 then return "II"
			elseif num == 3 then return "III"
			end
		end
		return "0"
	end

	local function getCountdownText(generatorAdornee)
		if not generatorAdornee then return nil end
		if generatorAdornee.Name ~= 'GeneratorAdornee' then return nil end
		local reactTree = generatorAdornee:FindFirstChild('RoactTree')
		if not reactTree then return nil end
		local teamApp = reactTree:FindFirstChild('TeamOreGeneratorApp')
		if not teamApp then return nil end
		local globalGen = teamApp:FindFirstChild('GlobalOreGenerator')
		if not globalGen then return nil end
		local countdown = globalGen:FindFirstChild('Countdown')
		if not countdown then return nil end
		local textLabel = countdown:FindFirstChild('Text')
		if not textLabel then
			if countdown:IsA('TextLabel') then return countdown end
			return nil
		end
		return textLabel
	end

	local function extractSecondsFromText(text)
		if not text or text == "" then return 0 end
		local seconds = text:match("%[(%d+)%]")
		if seconds then return tonumber(seconds) or 0 end
		local justNumber = text:match("(%d+)")
		if justNumber then return tonumber(justNumber) or 0 end
		return 0
	end

	local resourceDrops = {}
	local function getResourceCount(position, resourceType)
		local count = 0
		for _, drop in pairs(resourceDrops) do
			if drop:FindFirstChild('Handle') then
				local dropName = drop.Name:lower()
				if dropName:find(resourceType) then
					local dist = (drop.Handle.Position - position).Magnitude
					if dist <= 10 then
						local amount = drop:GetAttribute('Amount') or 1
						count = count + amount
					end
				end
			end
		end
		return count
	end

	local CompactGenerators = {}

	local function rebuildCompactGenerators()
		table.clear(CompactGenerators)
		scanDescendants(workspace, function(obj)
			if obj.Name == 'GeneratorAdornee' then
				local ok, generatorId = pcall(function() return obj:GetAttribute('Id') end)
				if ok and generatorId and type(generatorId) == 'string' and generatorId ~= '' then
					local genType = getGeneratorType(generatorId)
					if genType == 'diamond' or genType == 'emerald' then
						table.insert(CompactGenerators, {obj = obj, genType = genType})
					end
				end
			end
		end, GeneratorESP)
	end

	local function updateCompactUI()
		if not GeneratorESP.Enabled or UIStyle.Value ~= 'Compact' then
			compactUI.Enabled = false
			return
		end
		compactUI.Enabled = true
		local bestDiamondTime = math.huge
		local bestEmeraldTime = math.huge
		for i = #CompactGenerators, 1, -1 do
			local entry = CompactGenerators[i]
			if not entry.obj or not entry.obj.Parent then
				table.remove(CompactGenerators, i)
				continue
			end
			local countdownText = getCountdownText(entry.obj)
			if countdownText and countdownText.Text then
				local timeLeft = extractSecondsFromText(countdownText.Text)
				if entry.genType == 'diamond' and timeLeft > 0 and timeLeft < bestDiamondTime then
					bestDiamondTime = timeLeft
				elseif entry.genType == 'emerald' and timeLeft > 0 and timeLeft < bestEmeraldTime then
					bestEmeraldTime = timeLeft
				end
			end
		end
		local showDiamond = CompactDiamondToggle and CompactDiamondToggle.Enabled
		local showEmerald = CompactEmeraldToggle and CompactEmeraldToggle.Enabled

		if not showDiamond and not showEmerald then
			compactUI.Enabled = false
			return
		end

		diamondFrame.Visible = showDiamond
		emeraldFrame.Visible = showEmerald

		if showDiamond then
			diamondFrame.Position = UDim2.new(0, 10, 0, 35)
		end
		if showEmerald then
			emeraldFrame.Position = UDim2.new(0, 10, 0, showDiamond and 65 or 35)
		end

		diamondTimes[1] = bestDiamondTime ~= math.huge and bestDiamondTime or 0
		emeraldTimes[1] = bestEmeraldTime ~= math.huge and bestEmeraldTime or 0
		if bestDiamondTime == math.huge then
			diamondTimer.Text = "00"
		else
			diamondTimer.Text = string.format("%02d", bestDiamondTime)
			if bestDiamondTime <= 5 then
				diamondTimer.TextColor3 = Color3.fromRGB(255, 50, 50)
			elseif bestDiamondTime <= 10 then
				diamondTimer.TextColor3 = Color3.fromRGB(255, 165, 0)
			else
				diamondTimer.TextColor3 = Color3.fromRGB(85, 200, 255)
			end
		end
		if bestEmeraldTime == math.huge then
			emeraldTimer.Text = "00"
		else
			emeraldTimer.Text = string.format("%02d", bestEmeraldTime)
			if bestEmeraldTime <= 5 then
				emeraldTimer.TextColor3 = Color3.fromRGB(255, 50, 50)
			elseif bestEmeraldTime <= 10 then
				emeraldTimer.TextColor3 = Color3.fromRGB(255, 165, 0)
			else
				emeraldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
			end
		end
	end

	local function clearAllESP()
		Folder:ClearAllChildren()
		table.clear(Reference)
		compactUI.Enabled = false
	end

	local function createESP(generatorAdornee, genType, config, position, teamId)
		if not isGeneratorEnabled(genType, teamId) then return end
		if Reference[generatorAdornee] then return end

		if UIStyle.Value == 'Compact' then
			Reference[generatorAdornee] = {
				genType = genType,
				position = position,
				teamId = teamId,
				isTeamGen = config.isTeamGen
			}
			return
		end
		if not generatorAdornee or not generatorAdornee.Parent then return end

		local displayColor = config.color
		local teamName = nil
		if config.isTeamGen and teamId and teamColors[teamId] then
			displayColor = teamColors[teamId].color
			teamName = teamColors[teamId].name
		end

		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'generator-esp-' .. genType
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = generatorAdornee
		billboard.Enabled = true  

		if config.isTeamGen then
			billboard.Size = UDim2.fromOffset(180, 55)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		else
			billboard.Size = UDim2.fromOffset(80, 30)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		end

		local blurOk, blur = pcall(addBlur, billboard)
		if blurOk and blur then
			blur.Visible = true
		end

		if config.isTeamGen and teamName then
			local dot = Instance.new('Frame')
			dot.Name = 'TeamDot'
			dot.Parent = billboard
			dot.Size = UDim2.fromOffset(8, 8)
			dot.Position = UDim2.new(0, 10, 0, 5)
			dot.BackgroundColor3 = displayColor
			dot.BorderSizePixel = 0
			local dotCorner = Instance.new('UICorner')
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot

			local teamLabel = Instance.new('TextLabel')
			teamLabel.Name = 'TeamLabel'
			teamLabel.Parent = billboard
			teamLabel.BackgroundTransparency = 1
			teamLabel.Size = UDim2.new(1, 0, 0, 18)
			teamLabel.Position = UDim2.new(0, 0, 0, 0)
			teamLabel.Text = teamName
			teamLabel.TextColor3 = displayColor
			teamLabel.TextSize = 13
			teamLabel.Font = Enum.Font.GothamBold
			teamLabel.TextStrokeTransparency = 0.4
			teamLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			teamLabel.TextXAlignment = Enum.TextXAlignment.Center
		end

		local frame = Instance.new('Frame')
		frame.Size = config.isTeamGen and UDim2.new(1, 0, 0, 35) or UDim2.fromScale(1, 1)
		frame.Position = config.isTeamGen and UDim2.new(0, 0, 0, 20) or UDim2.new(0, 0, 0, 0)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BackgroundTransparency = 0.3
		frame.BorderSizePixel = 0
		frame.Parent = billboard

		if config.isTeamGen and teamId and teamColors[teamId] then
			local stripe = Instance.new('Frame')
			stripe.Name = 'TeamStripe'
			stripe.Parent = frame
			stripe.Size = UDim2.new(0, 3, 1, 0)
			stripe.Position = UDim2.new(0, 0, 0, 0)
			stripe.BackgroundColor3 = displayColor
			stripe.BorderSizePixel = 0
			local stripeCorner = Instance.new('UICorner')
			stripeCorner.CornerRadius = UDim.new(0, 3)
			stripeCorner.Parent = stripe
		end

		local uicorner2 = Instance.new('UICorner')
		uicorner2.CornerRadius = UDim.new(0, 6)
		uicorner2.Parent = frame

		if config.isTeamGen then
			local tierLabel = Instance.new('TextLabel')
			tierLabel.Name = 'Tier'
			tierLabel.Size = UDim2.new(0, 25, 1, 0)
			tierLabel.Position = UDim2.new(0, 8, 0, 0)
			tierLabel.BackgroundTransparency = 1
			tierLabel.Text = "0"
			tierLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
			tierLabel.TextSize = 16
			tierLabel.Font = Enum.Font.GothamBold
			tierLabel.TextStrokeTransparency = 0.5
			tierLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			tierLabel.Parent = frame

			local resources = {
				{name = 'iron',    color = Color3.fromRGB(200, 200, 200), icon = 'iron',    xOffset = 35},
				{name = 'diamond', color = Color3.fromRGB(85, 200, 255),  icon = 'diamond', xOffset = 85},
				{name = 'emerald', color = Color3.fromRGB(0, 255, 100),   icon = 'emerald', xOffset = 135}
			}

			local resourceLabels = {}
			for _, resource in ipairs(resources) do
				local iconImage = getProperIcon(resource.icon)
				if iconImage then
					local image = Instance.new('ImageLabel')
					image.Size = UDim2.fromOffset(18, 18)
					image.Position = UDim2.new(0, resource.xOffset, 0.5, 0)
					image.AnchorPoint = Vector2.new(0, 0.5)
					image.BackgroundTransparency = 1
					image.Image = iconImage
					image.Parent = frame
				end
				local countLabel = Instance.new('TextLabel')
				countLabel.Name = resource.name .. '_count'
				countLabel.Size = UDim2.new(0, 25, 1, 0)
				countLabel.Position = UDim2.new(0, resource.xOffset + 20, 0, 0)
				countLabel.BackgroundTransparency = 1
				countLabel.Text = "0"
				countLabel.TextColor3 = resource.color
				countLabel.TextSize = 16
				countLabel.Font = Enum.Font.GothamBold
				countLabel.TextStrokeTransparency = 0.5
				countLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
				countLabel.TextXAlignment = Enum.TextXAlignment.Left
				countLabel.Parent = frame
				resourceLabels[resource.name] = countLabel
			end

			Reference[generatorAdornee] = {
				billboard = billboard,
				tierLabel = tierLabel,
				ironLabel = resourceLabels.iron,
				diamondLabel = resourceLabels.diamond,
				emeraldLabel = resourceLabels.emerald,
				genType = genType,
				position = position,
				teamId = teamId,
				isTeamGen = true
			}
		else
			local iconImage = getProperIcon(config.icon)
			if iconImage then
				local image = Instance.new('ImageLabel')
				image.Size = UDim2.fromOffset(20, 20)
				image.Position = UDim2.new(0, 5, 0.5, 0)
				image.AnchorPoint = Vector2.new(0, 0.5)
				image.BackgroundTransparency = 1
				image.Image = iconImage
				image.Parent = frame
			end
			local timerLabel = Instance.new('TextLabel')
			timerLabel.Name = 'Timer'
			timerLabel.Size = UDim2.new(0, 30, 1, 0)
			timerLabel.Position = UDim2.new(0.5, 0, 0, 0)
			timerLabel.AnchorPoint = Vector2.new(0.5, 0)
			timerLabel.BackgroundTransparency = 1
			timerLabel.Text = "00"
			timerLabel.TextColor3 = displayColor
			timerLabel.TextSize = 18
			timerLabel.Font = Enum.Font.GothamBold
			timerLabel.TextStrokeTransparency = 0.5
			timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			timerLabel.Parent = frame
			local amountLabel = Instance.new('TextLabel')
			amountLabel.Name = 'Amount'
			amountLabel.Size = UDim2.new(0, 20, 1, 0)
			amountLabel.Position = UDim2.new(1, -20, 0, 0)
			amountLabel.BackgroundTransparency = 1
			amountLabel.Text = "0"
			amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			amountLabel.TextSize = 16
			amountLabel.Font = Enum.Font.GothamBold
			amountLabel.TextStrokeTransparency = 0.5
			amountLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			amountLabel.Parent = frame
			Reference[generatorAdornee] = {
				billboard = billboard,
				timerLabel = timerLabel,
				amountLabel = amountLabel,
				genType = genType,
				position = position,
				teamId = teamId,
				isTeamGen = false
			}
		end
		billboard.Enabled = true
	end

	local function updateESP(generatorAdornee)
		local ref = Reference[generatorAdornee]
		if not ref then return end
		if UIStyle.Value == 'Compact' then return end

		if ref.isTeamGen then
			if ref.tierLabel then
				local tierTextLabel = getTierText(generatorAdornee)
				if tierTextLabel and tierTextLabel.Text then
					ref.tierLabel.Text = extractTierLevel(tierTextLabel.Text)
				else
					ref.tierLabel.Text = "0"
				end
			end
			if ref.ironLabel then
				ref.ironLabel.Text = tostring(getResourceCount(ref.position, 'iron'))
			end
			if ref.diamondLabel then
				ref.diamondLabel.Text = tostring(getResourceCount(ref.position, 'diamond'))
			end
			if ref.emeraldLabel then
				ref.emeraldLabel.Text = tostring(getResourceCount(ref.position, 'emerald'))
			end
		else
			local countdownText = getCountdownText(generatorAdornee)
			if countdownText and countdownText.Text then
				local timeLeft = extractSecondsFromText(countdownText.Text)
				if ref.timerLabel then
					ref.timerLabel.Text = string.format("%02d", timeLeft)
					if timeLeft <= 5 then
						ref.timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
					elseif timeLeft <= 10 then
						ref.timerLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
					else
						ref.timerLabel.TextColor3 = generatorTypes[ref.genType].color
					end
				end
			else
				if ref.timerLabel then
					ref.timerLabel.Text = "00"
					ref.timerLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
				end
			end
			if ref.amountLabel then
				ref.amountLabel.Text = tostring(getResourceCount(ref.position, ref.genType))
			end
		end
	end

	local function processGeneratorAdornee(obj)
		if obj.Name ~= 'GeneratorAdornee' then return end
		local ok, generatorId = pcall(function() return obj:GetAttribute('Id') end)
		if not ok then return end
		if generatorId == nil then return end
		if type(generatorId) ~= 'string' then return end
		if generatorId == '' then return end

		local position = obj:GetPivot().Position
		local genType, config = getGeneratorType(generatorId)
		if not genType or not config then return end

		local teamId = getGeneratorTeamId(generatorId)
		if isGeneratorEnabled(genType, teamId) then
			createESP(obj, genType, config, position, teamId)
		end
	end

	local function findAllGenerators()
		scanDescendants(workspace, function(obj)
			pcall(processGeneratorAdornee, obj)
		end, GeneratorESP)
	end

	local function refreshESP()
		clearAllESP()
		if GeneratorESP.Enabled then
			findAllGenerators()
		end
	end

	local updateTimer = 0

	GeneratorESP = vape.Categories.Render:CreateModule({
		Name = 'GeneratorESP',
		Function = function(callback)
			if callback then
				findAllGenerators()
				rebuildCompactGenerators()

				GeneratorESP:Clean(workspace.DescendantAdded:Connect(function(obj)
					if not GeneratorESP.Enabled or obj.Name ~= 'GeneratorAdornee' then return end
					task.wait(0.2)
					if not GeneratorESP.Enabled or not obj.Parent then return end
					pcall(processGeneratorAdornee, obj)
					rebuildCompactGenerators()
				end))

				GeneratorESP:Clean(runService.Heartbeat:Connect(function(dt)
					if not GeneratorESP.Enabled then return end
					updateTimer = updateTimer + dt
					if updateTimer < 0.2 then return end
					updateTimer = 0
					if UIStyle.Value ~= 'Compact' then
						resourceDrops = CollectionService:GetTagged('ItemDrop')
					end
					for generatorAdornee, ref in pairs(Reference) do
						if generatorAdornee and generatorAdornee.Parent then
							updateESP(generatorAdornee)
						else
							if ref.billboard then ref.billboard:Destroy() end
							Reference[generatorAdornee] = nil
						end
					end
					updateCompactUI()
				end))

				GeneratorESP:Clean(workspace.DescendantRemoving:Connect(function(obj)
					if not GeneratorESP.Enabled then return end
					if Reference[obj] then
						if Reference[obj].billboard then Reference[obj].billboard:Destroy() end
						Reference[obj] = nil
					end
				end))
			else
				clearAllESP()
			end
		end,
		Tooltip = 'esp for generators showing timer and items count'
	})

	UIStyle = GeneratorESP:CreateDropdown({
		Name = 'UI Style',
		List = {'Original', 'Compact'},
		Default = 'Original',
		Function = function(val)
			local isOriginal = val == 'Original'
			if DiamondToggle then DiamondToggle.Object.Visible = isOriginal end
			if EmeraldToggle then EmeraldToggle.Object.Visible = isOriginal end
			if TeamGenToggle then TeamGenToggle.Object.Visible = isOriginal end
			if ShowOwnTeamGen then ShowOwnTeamGen.Object.Visible = isOriginal and TeamGenToggle.Enabled end
			if ShowEnemyTeamGen then ShowEnemyTeamGen.Object.Visible = isOriginal and TeamGenToggle.Enabled end
			if CompactDiamondToggle then CompactDiamondToggle.Object.Visible = not isOriginal end
			if CompactEmeraldToggle then CompactEmeraldToggle.Object.Visible = not isOriginal end
			refreshESP()
		end,
		Tooltip = 'pick between the norm billboard esp on generators or a ui with timers for generators '
	})

	DiamondToggle = GeneratorESP:CreateToggle({
		Name = 'Diamond',
		Function = function() refreshESP() end,
		Default = false,
		Visible = true
	})

	EmeraldToggle = GeneratorESP:CreateToggle({
		Name = 'Emerald',
		Function = function() refreshESP() end,
		Default = false,
		Visible = true
	})

	CompactDiamondToggle = GeneratorESP:CreateToggle({
		Name = 'Compact Diamond',
		Default = false,
		Visible = false,
		Function = function()
			refreshESP()
		end
	})

	CompactEmeraldToggle = GeneratorESP:CreateToggle({
		Name = 'Compact Emerald',
		Default = false,
		Visible = false,
		Function = function()
			refreshESP()
		end
	})

	TeamGenToggle = GeneratorESP:CreateToggle({
		Name = 'Team Generators',
		Function = function(callback)
			if ShowOwnTeamGen then ShowOwnTeamGen.Object.Visible = callback end
			if ShowEnemyTeamGen then ShowEnemyTeamGen.Object.Visible = callback end
			refreshESP()
		end,
		Default = true
	})

	ShowOwnTeamGen = GeneratorESP:CreateToggle({
		Name = 'Show Own Team',
		Function = function() refreshESP() end,
		Default = false,
		Visible = true
	})

	ShowEnemyTeamGen = GeneratorESP:CreateToggle({
		Name = 'Show Enemy Teams',
		Function = function() refreshESP() end,
		Default = true,
		Visible = true
	})
end)

run(function()
	local VictoriousKitSkins
	local ItemSkinDropdown
	local SkinTypeDropdown
	local RS = game:GetService('ReplicatedStorage')
	local LocalPlayer = lplr
	local RESKIN_NAME = 'LOCAL_ITEM_RESKIN'
	local state = {
		itemSkin = 'Victorious Lyla',
		skinType = 'Nightmare',
	}
	local ok1, ItemType = pcall(function()
		return require(RS.TS.item['item-type']).ItemType
	end)
	if not ok1 then ItemType = {} end
	local ok2, ItemSkinType = pcall(function()
		return require(RS.TS.games.bedwars['item-skin']['item-skin-types']).ItemSkinType
	end)
	if not ok2 then ItemSkinType = {} end
	local KitSkinCtrl
	pcall(function()
		local KC = require(RS.rbxts_include.node_modules['@easy-games'].knit.src).KnitClient
		KitSkinCtrl = KC.Controllers.KitSkinController
	end)

	local VICTORIOUS_ARCHER_BOW_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, -52, math.rad(90))
	local VICTORIOUS_ARCHER_CROSSBOW_ROT = CFrame.new(0.00, 0.00, 0.00) * CFrame.Angles(math.rad(0), math.rad(80), math.rad(0.00))
	local VICTORIOUS_ARCHER_HEADHUNTER_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(0), 0)
	local STAFF_ROT = CFrame.Angles(0, math.rad(90), 0)
	local VIC_ROT = CFrame.new(0, -1.9, 0) * CFrame.Angles(0, math.rad(360), 0)
	local TRIDENT_ROT = CFrame.new(0, 0.5, 0.05) * CFrame.Angles(0, math.rad(180), 0)
	local LYLA_BOW_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(30, -30, 183.56)
	local LYLA_CROSSBOW_ROT = CFrame.Angles(math.rad(0), math.rad(180), math.rad(0))
	local LYLA_HEADHUNTER_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(0), 0)
	local CANNON_HAND_SCALE = 0.34
	local CANNON_PLACED_OFFSET = CFrame.new(0, -1.0, 0)
	local CANNON_TOOL_NAME = "cannon"

	local CANNON_SKIN_NAMES = {
		["Victorious Cannon"] = {
			Gold = "cannon_gold_victorious",
			Platinum = "cannon_platinum_victorious",
			Diamond = "cannon_diamond_victorious",
			Emerald = "cannon_emerald_victorious",
			Nightmare = "cannon_nightmare_victorious",
		},
	}
	local CANNON_SOUND_NAMES = {
		Gold = "CANNON_FIRE_VICTORIOUS_NIGHTMARE",
		Platinum = "CANNON_FIRE_VICTORIOUS_NIGHTMARE",
		Diamond = "CANNON_FIRE_VICTORIOUS_DIAMOND",
		Emerald = "CANNON_FIRE_VICTORIOUS_EMERALD",
		Nightmare = "CANNON_FIRE_VICTORIOUS_NIGHTMARE",
	}
	local SKIN_OFFSETS = {
		["nightmare_victorious_flower_bow"] = LYLA_BOW_ROT,
		["emerald_victorious_flower_bow"] = LYLA_BOW_ROT,
		["diamond_victorious_flower_bow"] = LYLA_BOW_ROT,
		["platinum_victorious_flower_bow"] = LYLA_BOW_ROT,
		["gold_victorious_flower_bow"] = LYLA_BOW_ROT,
		["nightmare_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["emerald_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["diamond_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["platinum_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["gold_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["nightmare_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["emerald_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["diamond_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["platinum_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["gold_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_nightmare"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_emerald"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_diamond"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_platinum"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_gold"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["wood_bow_victorious_nightmare"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_emerald"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_diamond"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_platinum"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_gold"] = VICTORIOUS_ARCHER_BOW_ROT,
		["tactical_crossbow_victorious_nightmare"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_emerald"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_diamond"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_platinum"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_gold"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["victorious_gold_triton"] = TRIDENT_ROT,
		["victorious_platinum_triton"] = TRIDENT_ROT,
		["victorious_diamond_triton"] = TRIDENT_ROT,
		["victorious_emerald_triton"] = TRIDENT_ROT,
		["victorious_nightmare_triton"] = TRIDENT_ROT,
		["gold_victorious_wizard_staff"] = STAFF_ROT,
		["gold_victorious_wizard_staff_2"] = STAFF_ROT,
		["gold_victorious_wizard_staff_3"] = STAFF_ROT,
		["platinum_victorious_wizard_staff"] = STAFF_ROT,
		["platinum_victorious_wizard_staff_2"] = STAFF_ROT,
		["platinum_victorious_wizard_staff_3"] = STAFF_ROT,
		["diamond_victorious_wizard_staff"] = STAFF_ROT,
		["diamond_victorious_wizard_staff_2"] = STAFF_ROT,
		["diamond_victorious_wizard_staff_3"] = STAFF_ROT,
		["emerald_victorious_wizard_staff"] = STAFF_ROT,
		["emerald_victorious_wizard_staff_2"] = STAFF_ROT,
		["emerald_victorious_wizard_staff_3"] = STAFF_ROT,
		["nightmare_victorious_wizard_staff"] = STAFF_ROT,
		["nightmare_victorious_wizard_staff_2"] = STAFF_ROT,
		["nightmare_victorious_wizard_staff_3"] = STAFF_ROT,
		["wood_dao_victorious"] = VIC_ROT,
		["stone_dao_victorious"] = VIC_ROT,
		["iron_dao_victorious"] = VIC_ROT,
		["diamond_dao_victorious"] = VIC_ROT,
		["emerald_dao_victorious"] = VIC_ROT,
	}
	local KIT_SKIN_MAP = {
		["Victorious Lyla"] = { Gold = "gold_victorious_lyla", Platinum = "platinum_victorious_lyla", Diamond = "diamond_victorious_lyla", Emerald = "emerald_victorious_lyla", Nightmare = "nightmare_victorious_lyla" },
		["Victorious Archer"] = { Gold = "archer_victorious_gold", Platinum = "archer_victorious_platinum", Diamond = "archer_victorious_diamond", Emerald = "archer_victorious_emerald", Nightmare = "archer_victorious_nightmare" },
		["Victorious Yuzi"] = { Default = "yuzi_victorious" },
		["Victorious Zeno"] = { Gold = "gold_victorious_wizard", Platinum = "platinum_victorious_wizard", Diamond = "diamond_victorious_wizard", Emerald = "emerald_victorious_wizard", Nightmare = "nightmare_victorious_wizard" },
		["Victorious Triton"] = { Gold = "victorious_gold_triton", Platinum = "victorious_platinum_triton", Diamond = "victorious_diamond_triton", Emerald = "victorious_emerald_triton", Nightmare = "victorious_nightmare_triton" },
		["Victorious Cannon"] = { Gold = "gold_victorious_davey", Platinum = "platinum_victorious_davey", Diamond = "diamond_victorious_davey", Emerald = "emerald_victorious_davey", Nightmare = "nightmare_victorious_davey" },
	}
	local function yuziDaoMap(suffix)
		return {
			wood_dao = "wood_dao_" .. suffix,
			stone_dao = "stone_dao_" .. suffix,
			iron_dao = "iron_dao_" .. suffix,
			diamond_dao = "diamond_dao_" .. suffix,
			emerald_dao = "emerald_dao_" .. suffix,
		}
	end
	local SKIN_DATA = {
		["Victorious Lyla"] = function(t)
			local lt = t:lower()
			return {
				flower_bow = lt .. "_victorious_flower_bow",
				flower_crossbow = lt .. "_victorious_flower_crossbow",
				flower_headhunter = lt .. "_victorious_flower_headhunter",
			}
		end,
		["Victorious Archer"] = function(t)
			local lt = t:lower()
			return {
				wood_bow = "wood_bow_victorious_" .. lt,
				tactical_crossbow = "tactical_crossbow_victorious_" .. lt,
				tactical_headhunter = "tactical_headhunter_victorious_" .. lt,
			}
		end,
		["Victorious Triton"] = function(t)
			return { harpoon = "victorious_" .. t:lower() .. "_triton" }
		end,
		["Victorious Yuzi"] = function() return yuziDaoMap("victorious") end,
		["Victorious Zeno"] = function(t)
			local lt = t:lower()
			return {
				wizard_staff = lt .. "_victorious_wizard_staff",
				wizard_staff_2 = lt .. "_victorious_wizard_staff_2",
				wizard_staff_3 = lt .. "_victorious_wizard_staff_3",
			}
		end,
	}
	local TIERED_SKINS = {
		["Victorious Lyla"] = true,
		["Victorious Archer"] = true,
		["Victorious Zeno"] = true,
		["Victorious Triton"] = true,
		["Victorious Cannon"] = true,
	}

	local active = {}
	local hideList = {}
	local hookConns = {}
	local renderConn
	local oldGetKitSkin
	local oldFireCannon
	local oldLaunchSelf
	local soundsHooked = false
	local refreshVersion = 0

	local function normalizeName(s)
		return s:lower():gsub('[_%s%-]', '')
	end

	local function isCannonSkin()
		return CANNON_SKIN_NAMES[state.itemSkin] ~= nil
	end

	local function getCannonSkinName()
		local tbl = CANNON_SKIN_NAMES[state.itemSkin]
		if not tbl then return nil end
		return tbl[state.skinType] or tbl.Default
	end

	local function getCurrentMappings()
		local fn = SKIN_DATA[state.itemSkin]
		if not fn then return {} end
		local ok, res = pcall(fn, state.skinType)
		if ok and type(res) == 'table' then return res end
		return {}
	end

	local function getKitSkinValue()
		local m = KIT_SKIN_MAP[state.itemSkin]
		if not m then return nil end
		return m[state.skinType] or m.Default
	end

	local function itemsFolder()
		return RS:FindFirstChild('Items')
	end

	local function blocksFolder()
		local assets = RS:FindFirstChild('Assets')
		return assets and assets:FindFirstChild('Blocks')
	end

	local function firstBasePart(root)
		if root:IsA('BasePart') then return root end
		for _, d in root:GetDescendants() do
			if d:IsA('BasePart') then return d end
		end
		return nil
	end

	local function setNoCollide(model)
		local function strip(p)
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			p.Anchored = false
		end
		if model:IsA('BasePart') then strip(model) end
		for _, d in model:GetDescendants() do
			if d:IsA('BasePart') then strip(d) end
		end
	end

	local function weldAllTo(anchor, container)
		for _, d in container:GetDescendants() do
			if d:IsA('BasePart') and d ~= anchor then
				local wc = Instance.new('WeldConstraint')
				wc.Part0 = anchor
				wc.Part1 = d
				wc.Parent = anchor
			end
		end
	end

	local function getRigScale(root)
		local node = root
		local hum
		for _ = 1, 6 do
			if not node or node == workspace then break end
			hum = node:FindFirstChildOfClass('Humanoid')
			if hum then break end
			node = node.Parent
		end
		if not hum then return 1 end
		local total, count = 0, 0
		for _, name in {'BodyHeightScale', 'BodyWidthScale', 'BodyDepthScale'} do
			local v = hum:FindFirstChild(name)
			if v and v:IsA('NumberValue') and v.Value > 0 then
				total = total + v.Value
				count = count + 1
			end
		end
		if count == 0 then return 1 end
		return math.clamp(total / count, 0.3, 3)
	end

	local function startRenderLoop()
		if renderConn then return end
		renderConn = runService.RenderStepped:Connect(function()
			for i = #hideList, 1, -1 do
				local p = hideList[i]
				if p and p.Parent then
					p.LocalTransparencyModifier = 1
				else
					table.remove(hideList, i)
				end
			end
		end)
	end

	local function stopRenderLoop()
		if renderConn then
			pcall(function() renderConn:Disconnect() end)
			renderConn = nil
		end
	end

	local function hideDescendant(entry, d)
		if d:IsA('BasePart') then
			entry.parts[#entry.parts + 1] = {d, d.Transparency}
			d.Transparency = 1
			d.LocalTransparencyModifier = 1
			hideList[#hideList + 1] = d
		elseif d:IsA('Decal') or d:IsA('Texture') then
			entry.decals[#entry.decals + 1] = {d, d.Transparency}
			d.Transparency = 1
		end
	end

	local function hideOriginal(entry, root)
		for _, d in root:GetDescendants() do
			if not d:IsDescendantOf(entry.clone) then
				hideDescendant(entry, d)
			end
		end
	end

	local function detach(root)
		local entry = active[root]
		if not entry then return end
		active[root] = nil
		for _, c in entry.conns do
			pcall(function() c:Disconnect() end)
		end
		if entry.clone then
			pcall(function() entry.clone:Destroy() end)
		end
		for _, rec in entry.parts do
			local p = rec[1]
			local idx = table.find(hideList, p)
			if idx then table.remove(hideList, idx) end
			pcall(function()
				if p.Parent then
					p.Transparency = rec[2]
					p.LocalTransparencyModifier = 0
				end
			end)
		end
		for _, rec in entry.decals do
			local d = rec[1]
			pcall(function()
				if d.Parent then d.Transparency = rec[2] end
			end)
		end
	end

	local function detachAll()
		for root in active do
			detach(root)
		end
		table.clear(active)
		table.clear(hideList)
	end

	local function attachReskin(root, skinName, source, opts)
		if not root or not root.Parent then return end
		if active[root] or not source then return end
		opts = opts or {}

		local origHandle = root:FindFirstChild('Handle')
		if not (origHandle and origHandle:IsA('BasePart')) then
			origHandle = firstBasePart(root)
		end
		if not origHandle then return end

		local clone = source:Clone()
		clone.Name = RESKIN_NAME
		for _, d in clone:GetDescendants() do
			if d:IsA('LuaSourceContainer') then
				pcall(function() d:Destroy() end)
			end
		end
		setNoCollide(clone)

		local anchor
		local alignByPivot = false
		if clone:IsA('BasePart') then
			anchor = clone
		else
			local handle = clone:FindFirstChild('Handle')
			if handle and handle:IsA('BasePart') then
				anchor = handle
			else
				alignByPivot = true
				anchor = clone:IsA('Model') and clone.PrimaryPart or nil
				anchor = anchor or firstBasePart(clone)
			end
		end
		if not anchor then
			pcall(function() clone:Destroy() end)
			return
		end
		if clone:IsA('Model') and not clone.PrimaryPart then
			pcall(function() clone.PrimaryPart = anchor end)
		end

		local scale = (opts.scale or 1) * getRigScale(root)
		if clone:IsA('Model') and math.abs(scale - 1) > 0.001 then
			pcall(function() clone:ScaleTo(scale) end)
		end

		local entry = {clone = clone, parts = {}, decals = {}, conns = {}}
		active[root] = entry
		clone.Parent = root

		local offset = (SKIN_OFFSETS[skinName] or CFrame.identity) * (opts.offset or CFrame.identity)
		local target = origHandle.CFrame * offset
		pcall(function()
			if not clone:IsA('Model') then
				anchor.CFrame = target
			elseif alignByPivot then
				clone:PivotTo(target)
			else
				clone:PivotTo(target * anchor.CFrame:ToObjectSpace(clone:GetPivot()))
			end
		end)

		weldAllTo(anchor, clone)

		local weld = Instance.new('WeldConstraint')
		weld.Part0 = origHandle
		weld.Part1 = anchor
		weld.Parent = anchor

		hideOriginal(entry, root)
		startRenderLoop()

		entry.conns[#entry.conns + 1] = root.DescendantAdded:Connect(function(d)
			if entry.clone and entry.clone.Parent and d:IsDescendantOf(entry.clone) then return end
			hideDescendant(entry, d)
		end)
		entry.conns[#entry.conns + 1] = root.AncestryChanged:Connect(function(_, parent)
			if not parent then detach(root) end
		end)
	end

	local function track(conn)
		hookConns[#hookConns + 1] = conn
		return conn
	end

	local function clearHooks()
		for _, c in hookConns do
			pcall(function() c:Disconnect() end)
		end
		table.clear(hookConns)
	end

	local function deferCall(fn, ...)
		local args = table.pack(...)
		task.spawn(function()
			task.wait()
			fn(table.unpack(args, 1, args.n))
		end)
	end

	local function skinNameForChild(childName)
		local mappings = getCurrentMappings()
		local skinName = mappings[childName:lower()]
		if not skinName then
			local norm = normalizeName(childName)
			for k, v in mappings do
				if normalizeName(k) == norm then
					skinName = v
					break
				end
			end
		end
		return skinName
	end

	local function applyItem(child)
		if not (VictoriousKitSkins and VictoriousKitSkins.Enabled) then return end
		if isCannonSkin() or not child or not child.Parent then return end
		local skinName = skinNameForChild(child.Name)
		if not skinName then return end
		local folder = itemsFolder()
		if not folder then return end
		attachReskin(child, skinName, folder:FindFirstChild(skinName))
	end

	local function applyCannon(child, placed)
		if not (VictoriousKitSkins and VictoriousKitSkins.Enabled) then return end
		if not isCannonSkin() or not child or not child.Parent then return end
		if child.Name ~= CANNON_TOOL_NAME then return end
		local skinName = getCannonSkinName()
		if not skinName then return end
		local folder = blocksFolder()
		if not folder then return end
		attachReskin(child, skinName, folder:FindFirstChild(skinName), {
			offset = placed and CANNON_PLACED_OFFSET or CFrame.identity,
			scale = placed and 1 or CANNON_HAND_SCALE,
		})
	end

	local function applyProjectile(inst)
		if not (VictoriousKitSkins and VictoriousKitSkins.Enabled) then return end
		if isCannonSkin() or not inst or not inst.Parent then return end
		if not inst:IsA('Model') or inst.Name ~= 'harpoon_projectile' then return end
		local shooter = inst:GetAttribute('ProjectileShooter')
		if not shooter or tostring(shooter) ~= tostring(LocalPlayer.UserId) then return end
		local skinName = getCurrentMappings().harpoon
		if not skinName then return end
		local folder = itemsFolder()
		if not folder then return end
		attachReskin(inst, skinName, folder:FindFirstChild(skinName))
	end

	local function hookItemContainer(container)
		if not container then return end
		for _, child in container:GetChildren() do
			deferCall(applyItem, child)
		end
		track(container.ChildAdded:Connect(function(child)
			deferCall(applyItem, child)
		end))
	end

	local function hookCannonContainer(container, placed)
		if not container then return end
		for _, child in container:GetChildren() do
			deferCall(applyCannon, child, placed)
		end
		track(container.ChildAdded:Connect(function(child)
			deferCall(applyCannon, child, placed)
		end))
	end

	local function hookViewmodel(vm)
		if not vm then return end
		if isCannonSkin() then
			hookCannonContainer(vm, false)
		else
			hookItemContainer(vm)
		end
	end

	local function hookCamera(cam)
		if not cam then return end
		local vm = cam:FindFirstChild('Viewmodel')
		if vm then hookViewmodel(vm) end
		track(cam.ChildAdded:Connect(function(child)
			if child.Name == 'Viewmodel' then
				deferCall(hookViewmodel, child)
			end
		end))
	end

	local function hookWorldCannons()
		local map = workspace:FindFirstChild('Map')
		if not map then return end
		local worlds = map:FindFirstChild('Worlds')
		if not worlds then return end
		local function hookWorld(world)
			local blocks = world:FindFirstChild('Blocks')
			if blocks then hookCannonContainer(blocks, true) end
		end
		for _, world in worlds:GetChildren() do
			hookWorld(world)
		end
		track(worlds.ChildAdded:Connect(function(world)
			deferCall(hookWorld, world)
		end))
	end

	local function hookProjectiles()
		track(workspace.DescendantAdded:Connect(function(inst)
			if inst.Name == 'harpoon_projectile' then
				deferCall(applyProjectile, inst)
			end
		end))
	end

	local function applyKitSkinHook()
		if not KitSkinCtrl then return end
		local val = getKitSkinValue()
		if not val then return end
		if not oldGetKitSkin then oldGetKitSkin = KitSkinCtrl.getKitSkin end
		local base = oldGetKitSkin
		KitSkinCtrl.getKitSkin = function(self, char)
			if char == LocalPlayer.Character then return val end
			return base(self, char)
		end
	end

	local function removeKitSkinHook()
		if KitSkinCtrl and oldGetKitSkin then
			KitSkinCtrl.getKitSkin = oldGetKitSkin
			oldGetKitSkin = nil
		end
	end

	local function hookCannonSounds()
		if soundsHooked then return end
		if not (bedwars and bedwars.CannonHandController) then return end
		soundsHooked = true
		oldFireCannon = bedwars.CannonHandController.fireCannon
		oldLaunchSelf = bedwars.CannonHandController.launchSelf

		local function replaceSound()
			pcall(function()
				local pool = workspace:FindFirstChild('SoundPool')
				if pool then
					for _, v in pool:GetChildren() do
						if v:IsA('Sound') and v.SoundId == 'rbxassetid://7121064180' then
							v:Destroy()
						end
					end
				end
				local key = CANNON_SOUND_NAMES[state.skinType] or CANNON_SOUND_NAMES.Nightmare
				if bedwars.SoundManager and bedwars.SoundList and bedwars.SoundList[key] then
					bedwars.SoundManager:playSound(bedwars.SoundList[key])
				end
			end)
		end

		if oldFireCannon then
			bedwars.CannonHandController.fireCannon = function(...)
				replaceSound()
				return oldFireCannon(...)
			end
		end
		if oldLaunchSelf then
			bedwars.CannonHandController.launchSelf = function(...)
				replaceSound()
				return oldLaunchSelf(...)
			end
		end
	end

	local function unhookCannonSounds()
		if soundsHooked and bedwars and bedwars.CannonHandController then
			if oldFireCannon then bedwars.CannonHandController.fireCannon = oldFireCannon end
			if oldLaunchSelf then bedwars.CannonHandController.launchSelf = oldLaunchSelf end
		end
		oldFireCannon = nil
		oldLaunchSelf = nil
		soundsHooked = false
	end

	local function hookCharacter(char)
		if not char then return end
		local backpack = LocalPlayer:FindFirstChildOfClass('Backpack')
		if isCannonSkin() then
			hookCannonContainer(char, false)
			hookCannonContainer(backpack, false)
		else
			hookItemContainer(char)
			hookItemContainer(backpack)
		end
	end

	local soundItems = {}

	local function applyKitSounds()
		for base, skin in getCurrentMappings() do
			applySkinSounds(base, skin)
			soundItems[base] = true
		end
	end

	local function clearKitSounds()
		for base in soundItems do
			applySkinSounds(base, nil)
		end
		table.clear(soundItems)
	end

	local function setup()
		if not (VictoriousKitSkins and VictoriousKitSkins.Enabled) then return end
		applyKitSkinHook()
		applyKitSounds()
		hookCamera(workspace.CurrentCamera)
		track(workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
			if VictoriousKitSkins.Enabled then hookCamera(workspace.CurrentCamera) end
		end))
		if isCannonSkin() then
			hookCannonSounds()
			hookWorldCannons()
		else
			hookProjectiles()
		end
		hookCharacter(LocalPlayer.Character)
		track(LocalPlayer.CharacterAdded:Connect(function(char)
			task.spawn(function()
				task.wait(0.25)
				if not VictoriousKitSkins.Enabled then return end
				applyKitSkinHook()
				hookCharacter(char)
			end)
		end))
	end

	local function teardown()
		clearHooks()
		detachAll()
		stopRenderLoop()
		removeKitSkinHook()
		clearKitSounds()
		unhookCannonSounds()
	end

	local function refresh()
		if not (VictoriousKitSkins and VictoriousKitSkins.Enabled) then return end
		refreshVersion = refreshVersion + 1
		local version = refreshVersion
		teardown()
		task.defer(function()
			if version ~= refreshVersion then return end
			if VictoriousKitSkins.Enabled then setup() end
		end)
	end

	local function syncSkinTypeVisibility()
		if SkinTypeDropdown and SkinTypeDropdown.Object then
			SkinTypeDropdown.Object.Visible = TIERED_SKINS[state.itemSkin] == true
		end
	end

	local skinNames = {}
	local seenNames = {}
	for name in SKIN_DATA do
		if not seenNames[name] then
			seenNames[name] = true
			skinNames[#skinNames + 1] = name
		end
	end
	for name in CANNON_SKIN_NAMES do
		if not seenNames[name] then
			seenNames[name] = true
			skinNames[#skinNames + 1] = name
		end
	end
	table.sort(skinNames)

	VictoriousKitSkins = vape.Categories.Render:CreateModule({
		Name = 'VictoriousKitSkins',
		Function = function(enabled)
			if enabled then
				setup()
			else
				teardown()
			end
		end,
		Tooltip = 'gives u the victorious kit skins with the sounds, only u can see it so dont trip'
	})

	vape:Clean(function() teardown() end)

	ItemSkinDropdown = VictoriousKitSkins:CreateDropdown({
		Name = 'item skin',
		List = skinNames,
		Tooltip = 'which victorious kit u want the skins from',
		Default = state.itemSkin,
		Function = function(val)
			state.itemSkin = val
			if TIERED_SKINS[val] then
				state.skinType = SkinTypeDropdown and SkinTypeDropdown.Value or state.skinType
			else
				state.skinType = 'Default'
			end
			syncSkinTypeVisibility()
			refresh()
		end,
	})

	SkinTypeDropdown = VictoriousKitSkins:CreateDropdown({
		Name = 'skin type',
		List = {'Gold', 'Platinum', 'Diamond', 'Emerald', 'Nightmare', 'Default'},
		Tooltip = 'which tier of the skin u want, nightmare is the hardest one',
		Default = state.skinType,
		Visible = false,
		Function = function(val)
			if not TIERED_SKINS[state.itemSkin] then return end
			state.skinType = val
			refresh()
		end,
	})

	task.spawn(function()
		for _ = 1, 24 do
			syncSkinTypeVisibility()
			task.wait(0.25)
		end
	end)
end)

run(function()
	local SkinChanger
	local Options = {}
	local CategoryToggles = {}
	local skins, families, groups, order = {}, {}, {}, {}
	local names, familyCategory = {}, {}
	local sounds = {}
	local added = setmetatable({}, {__mode = 'k'})
	local watching, lasthand, queued
	local tiers = {leather = true, chainmail = true, wood = true, stone = true, gold = true, iron = true, diamond = true, emerald = true}
	local categories = {'swords', 'projectiles', 'tools', 'misc'}

	local ItemSkinType = {}
	pcall(function()
		ItemSkinType = require(replicatedStorage.TS.games.bedwars['item-skin']['item-skin-types']).ItemSkinType
	end)

	local viewmodelCtrl
	pcall(function()
		viewmodelCtrl = require(replicatedStorage.rbxts_include.node_modules['@easy-games'].knit.src).KnitClient.Controllers.InventoryViewmodelController
	end)

	local function prettyName(text)
		return (tostring(text):gsub('_', ' '):lower())
	end

	local function itemCategory(itemType)
		local meta = bedwars.ItemMeta[itemType]
		if not meta then return 'misc' end
		if meta.sword then return 'swords' end
		if meta.projectileSource then return 'projectiles' end
		if meta.breakBlock then return 'tools' end
		return 'misc'
	end

	for _, v in ItemSkinType do
		local meta = getItemSkinMeta(v)
		local item = meta and meta.itemType and bedwars.ItemMeta[meta.itemType]
		if item and not item.block then
			local label = `_{v}_`
			for i in meta.itemType:gmatch('[^_]+') do
				label = label:gsub(`_{i}_`, '_')
			end
			label = label:gsub('^_+', ''):gsub('_+$', '')
			label = prettyName(label ~= '' and label or v)
			skins[meta.itemType] = skins[meta.itemType] or {}
			skins[meta.itemType][label] = v
		end
	end

	for i in skins do
		local family = i:gsub('_%d+$', '')
		local tier, base = family:match('^([^_]+)_(.+)$')
		family = tier and tiers[tier] and base or family
		if not groups[family] then
			groups[family] = {}
			table.insert(order, family)
			familyCategory[family] = itemCategory(i)
		end
		families[i] = family
		table.insert(groups[family], i)
	end

	for i, v in groups do
		names[i] = prettyName(#v > 1 and i or v[1])
	end
	table.sort(order, function(a, b)
		return names[a] < names[b]
	end)

	local function pickedSkin(itemType)
		local family = SkinChanger.Enabled and families[itemType]
		local option = family and Options[family]
		local label = option and option.Value
		return label and skins[itemType] and skins[itemType][label] or nil
	end

	local function clearModel(accessory)
		local record = added[accessory]
		if not record then return end
		local handle = accessory:FindFirstChild('Handle')
		local template = replicatedStorage.Items:FindFirstChild(accessory.Name)
		for _, v in record.Parts do
			v:Destroy()
		end
		for _, v in handle and handle:GetChildren() or {} do
			local transparency = v:GetAttribute('SkinHidden')
			if transparency then
				v.Transparency = transparency
				v:SetAttribute('SkinHidden', nil)
			end
		end
		added[accessory] = nil
		if handle then
			if template and handle:IsA('MeshPart') and template.Handle:IsA('MeshPart') then
				handle:ApplyMesh(template.Handle)
			end
			handle.Size = record.Size
			local grip = handle:FindFirstChild('RightGripAttachment')
			if grip and record.Grip then
				grip.CFrame = record.Grip
			end
		end
	end

	local function applyModel(accessory)
		local model = pickedSkin(accessory.Name)
		local handle = accessory:FindFirstChild('Handle')
		local template = replicatedStorage.Items:FindFirstChild(model or '')
		if not handle or not template or added[accessory] then return end

		local grip = handle:FindFirstChild('RightGripAttachment')
		local templategrip = template.Handle:FindFirstChild('RightGripAttachment')
		local record = {Parts = {}, Size = handle.Size, Grip = grip and grip.CFrame or nil}
		added[accessory] = record

		for _, v in handle:GetChildren() do
			if v:IsA('BasePart') and v:GetAttribute('SkinHidden') == nil then
				v:SetAttribute('SkinHidden', v.Transparency)
				v.Transparency = 1
			end
		end

		if handle:IsA('MeshPart') and template.Handle:IsA('MeshPart') then
			handle:ApplyMesh(template.Handle)
		end
		handle.Size = template.Handle.Size
		if grip and templategrip then
			grip.CFrame = templategrip.CFrame
		end

		for _, v in template.Handle:GetChildren() do
			if v:IsA('BasePart') then
				local part = v:Clone()
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Massless = true
				part.CFrame = handle.CFrame * (template.Handle.CFrame:Inverse() * v.CFrame)
				part.Parent = handle
				local weld = Instance.new('WeldConstraint')
				weld.Part0 = handle
				weld.Part1 = part
				weld.Parent = part
				table.insert(record.Parts, part)
			end
		end
	end

	local function applySounds()
		for i in skins do
			local skin = pickedSkin(i) or false
			if sounds[i] ~= skin then
				sounds[i] = skin
				applySkinSounds(i, skin or nil)
			end
		end
	end

	local function applySkins()
		applySounds()

		local inventory = store.inventory.inventory
		local changed = false
		for _, v in inventory.items do
			local skin = pickedSkin(v.itemType)
			if v.itemSkin ~= skin then
				v.itemSkin = skin
				changed = true
			end
		end
		if inventory.hand then
			local skin = pickedSkin(inventory.hand.itemType)
			if inventory.hand.itemSkin ~= skin then
				inventory.hand.itemSkin = skin
				changed = true
			end
		end

		local hand = inventory.hand and inventory.hand.itemType
		if not changed and hand == lasthand then return end
		lasthand = hand

		if viewmodelCtrl then
			pcall(function()
				viewmodelCtrl:handleStore(bedwars.Store:getState())
			end)
		end
		if not lplr.Character then return end

		for _, v in lplr.Character:GetChildren() do
			if v:IsA('Accessory') then
				clearModel(v)
				applyModel(v)
			end
		end
	end

	local function queueSkins()
		if queued then return end
		queued = true
		task.defer(function()
			queued = false
			applySkins()
		end)
	end

	local function watchCharacter(char)
		if watching then
			watching:Disconnect()
		end
		watching = char.ChildAdded:Connect(function(v)
			if v:IsA('Accessory') and v:WaitForChild('Handle', 3) and SkinChanger.Enabled then
				applyModel(v)
			end
		end)
	end

	SkinChanger = vape.Categories.Render:CreateModule({
		Name = 'SkinChanger',
		Function = function(callback)
			if callback then
				SkinChanger:Clean(vapeEvents.InventoryChanged.Event:Connect(queueSkins))
				SkinChanger:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(queueSkins))
				SkinChanger:Clean(lplr.CharacterAdded:Connect(function(char)
					lasthand = nil
					watchCharacter(char)
					task.spawn(function()
						for _ = 1, 10 do
							task.wait(0.4)
							if not SkinChanger.Enabled then return end
							applySkins()
						end
					end)
				end))
				if lplr.Character then
					watchCharacter(lplr.Character)
				end
			elseif watching then
				watching:Disconnect()
				watching = nil
			end
			lasthand = nil
			applySkins()
		end,
		Tooltip = 'pick a skin for every item u got, sounds too, only u can see it tho'
	})

	for _, category in categories do
		CategoryToggles[category] = SkinChanger:CreateToggle({
			Name = category,
			Default = false,
			Tooltip = 'shows the skins for ur ' .. category,
			Function = function(callback)
				for family, option in Options do
					if familyCategory[family] == category then
						option.Object.Visible = callback
					end
				end
			end
		})

		for _, family in order do
			if familyCategory[family] == category then
				local list, seen = {}, {}
				for _, itemType in groups[family] do
					for label in skins[itemType] do
						if not seen[label] then
							seen[label] = true
							table.insert(list, label)
						end
					end
				end
				table.sort(list)
				table.insert(list, 1, 'none')
				Options[family] = SkinChanger:CreateDropdown({
					Name = names[family],
					List = list,
					Darker = true,
					Visible = false,
					Function = function()
						if SkinChanger.Enabled then
							lasthand = nil
							applySkins()
						end
					end
				})
			end
		end
	end

	task.defer(function()
		for family, option in Options do
			local toggle = CategoryToggles[familyCategory[family]]
			option.Object.Visible = toggle and toggle.Enabled or false
		end
	end)
end)

run(function()
	local PotESP
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local tracked = {}
	local function getSandIcon()
		local ok, icon = pcall(function() return bedwars.getIcon({itemType = 'sand'}, true) end)
		return ok and icon or 'rbxassetid://0'
	end
	local function createESP(obj)
		if tracked[obj] then return end
		if obj.Name:lower() ~= 'desert_pot' then return end
		local bill = Instance.new('BillboardGui')
		bill.Size = UDim2.fromOffset(40, 40)
		bill.Adornee = obj
		bill.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		bill.AlwaysOnTop = true
		bill.Parent = Folder
		local frame = Instance.new('Frame')
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.BackgroundTransparency = 0.4
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.Parent = bill
		local uic = Instance.new('UICorner')
		uic.CornerRadius = UDim.new(0, 4)
		uic.Parent = frame
		local image = Instance.new('ImageLabel')
		image.Size = UDim2.new(1, -6, 1, -6)
		image.Position = UDim2.new(0.5, 0, 0.5, 0)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundTransparency = 1
		image.Image = getSandIcon()
		image.Parent = frame
		tracked[obj] = bill
	end
	local function removeESP(obj)
		if tracked[obj] then
			tracked[obj]:Destroy()
			tracked[obj] = nil
		end
	end
	local function scanAll()
		scanDescendants(workspace, function(obj)
			createESP(obj)
		end, PotESP)
	end
	local function cleanup()
		for _, bill in pairs(tracked) do
			bill:Destroy()
		end
		table.clear(tracked)
	end
	PotESP = vape.Categories.Render:CreateModule({
		Name = 'PotESP',
		Function = function(callback)
			if callback then
				scanAll()
				PotESP:Clean(workspace.DescendantAdded:Connect(function(obj)
					if obj.Name:lower() ~= 'desert_pot' then return end
					task.wait(0.1)
					if PotESP.Enabled and obj.Parent then
						createESP(obj)
					end
				end))
				PotESP:Clean(workspace.DescendantRemoving:Connect(function(obj)
					if tracked[obj] then
						removeESP(obj)
					end
				end))
			else
				cleanup()
			end
		end,
		Tooltip = 'shows a sand block icon above each desert pot'
	})
end)

run(function()
    local ProximityPromptDuration
    local moduleData = {
        Connection = nil,
        CurrentDuration = 1,
        CachedPrompts = {}
    }
    
    local function updatePrompt(prompt, duration)
        if prompt and prompt:IsA("ProximityPrompt") then
            prompt.HoldDuration = duration
        end
    end
    
    local function updateAllPrompts(duration)
        for prompt in pairs(moduleData.CachedPrompts) do
            if prompt and prompt.Parent then
                prompt.HoldDuration = duration
            else
                moduleData.CachedPrompts[prompt] = nil
            end
        end
    end
    
    local function cacheExistingPrompts()
        moduleData.CachedPrompts = {}
        
        scanDescendants(workspace, function(descendant)
            if descendant:IsA("ProximityPrompt") then
                moduleData.CachedPrompts[descendant] = true
                descendant.HoldDuration = moduleData.CurrentDuration
            end
        end, ProximityPromptDuration)
    end
    
	ProximityPromptDuration = vape.Categories.Utility:CreateModule({
		Name = 'ProximityPromptDuration',
		Function = function(callback)
			if callback then
				cacheExistingPrompts()
				ProximityPromptDuration:Clean(workspace.DescendantAdded:Connect(function(descendant)
					if descendant:IsA("ProximityPrompt") then
						moduleData.CachedPrompts[descendant] = true
						descendant.HoldDuration = moduleData.CurrentDuration
					end
				end))
			else
				moduleData.CachedPrompts = {}
			end
		end,
		Tooltip = 'customize proximity prompts'
	})
    
    local ProximityDurationSlider = ProximityPromptDuration:CreateSlider({
        Name = 'Duration',
        Min = 0,
        Max = 10,
        Default = 1,
        Decimal = 100,
        Suffix = 's',
        Function = function(value)
            moduleData.CurrentDuration = value
            if ProximityPromptDuration.Enabled then
                updateAllPrompts(value)
            end
        end
    })
end)

run(function()
	local AutoPlay
	local Random
	
	local function isEveryoneDead()
		return #bedwars.Store:getState().Party.members <= 0
	end
	
	local function joinQueue()
		if not bedwars.Store:getState().Game.customMatch and bedwars.Store:getState().Party.leader.userId == lplr.UserId and bedwars.Store:getState().Party.queueState == 0 then
			if Random.Enabled then
				local listofmodes = {}
				for i, v in bedwars.QueueMeta do
					if not v.disabled and not v.voiceChatOnly and not v.rankCategory then 
						table.insert(listofmodes, i) 
					end
				end
				bedwars.QueueController:joinQueue(listofmodes[math.random(1, #listofmodes)])
			else
				bedwars.QueueController:joinQueue(store.queueType)
			end
		end
	end
	
	AutoPlay = vape.Categories.Utility:CreateModule({
		Name = 'AutoPlay',
		Function = function(callback)
			if callback then
				AutoPlay:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
					if deathTable.finalKill and deathTable.entityInstance == lplr.Character and isEveryoneDead() and store.matchState ~= 2 then
						joinQueue()
					end
				end))
				AutoPlay:Clean(vapeEvents.MatchEndEvent.Event:Connect(function()
					task.wait(1)
					joinQueue()
				end))
			end
		end,
		Tooltip = 'auto queues after the match ends.'
	})
	Random = AutoPlay:CreateToggle({
		Name = 'Random',
	})
end)

run(function()
	local AutoVoidDrop
	local OwlCheck
	local PearlCheck
	local AutoReset
	local pearlLastInHandTickVoid = 0
	local DropToggles = {
		iron = nil,
		diamond = nil,
		emerald = nil,
		gold = nil
	}
	local cachedLowestPoint
	
	AutoVoidDrop = vape.Categories.Utility:CreateModule({
		Name = 'AutoVoidDrop',
		Function = function(callback)
			local aeroAlive = newRun(AutoVoidDrop)
			if callback then
				repeat task.wait() until store.matchState ~= 0 or (not AutoVoidDrop.Enabled)
				if not AutoVoidDrop.Enabled then return end

				cachedLowestPoint = nil
				local worldFolder = getWorldFolder()
				local blocksFolder = worldFolder and worldFolder:FindFirstChild('Blocks')
				for _, v in (blocksFolder and blocksFolder:GetChildren() or store.blocks or {}) do
					if v:IsA('BasePart') then
						local point = v.Position.Y - (v.Size.Y / 2)
						if not cachedLowestPoint or point < cachedLowestPoint then
							cachedLowestPoint = point
						end
					end
				end

				local droppedThisLife = false
				local learnedDeathY, lastVoidY
				repeat
					if entitylib.isAlive then
						local root = entitylib.character.RootPart

						local handItem = store.inventory and store.inventory.inventory and store.inventory.inventory.hand
						if handItem and handItem.itemType == 'telepearl' then
							pearlLastInHandTickVoid = tick()
						end

						local vy = root.AssemblyLinearVelocity.Y
						if vy < -50 and isAboveVoid(root.Position) then
							lastVoidY = root.Position.Y
						else
							lastVoidY = nil
						end

						if droppedThisLife then
							if not isAboveVoid(root.Position) and root.AssemblyLinearVelocity.Y > -5 then
								droppedThisLife = false
							end
						else
							local deathLine = learnedDeathY or (cachedLowestPoint and cachedLowestPoint - 25) or (workspace.FallenPartsDestroyHeight + 20)
							if lastVoidY and (root.Position.Y + vy * 0.3) < deathLine + 5 and (lplr.Character:GetAttribute('InflatedBalloons') or 0) <= 0 and not getItem('balloon') then
								local pearlBlock = PearlCheck.Enabled and (tick() - pearlLastInHandTickVoid) < 4
								if (not OwlCheck.Enabled or not root:FindFirstChild('OwlLiftForce')) and not pearlBlock then
									droppedThisLife = true
									for _, item in pairs(store.inventory.inventory.items) do
										local toggle = item and DropToggles[item.itemType]
										if toggle and toggle.Enabled and item.tool then
											task.spawn(function()
												local dropped = bedwars.Client:Get(remotes.DropItem):CallServer({
													item = item.tool,
													amount = item.amount
												})
												if dropped then
													dropped:SetAttribute('ClientDropTime', tick() + 100)
												end
											end)
										end
									end
									if AutoReset.Enabled then
										task.delay(0.2, function()
											local hum = root.Parent and root.Parent:FindFirstChildOfClass('Humanoid')
											if hum then
												hum.Health = 0
											end
										end)
									end
								end
							end
						end
					else
						if lastVoidY and (not cachedLowestPoint or lastVoidY < cachedLowestPoint) then
							learnedDeathY = lastVoidY
						end
						lastVoidY = nil
						droppedThisLife = false
					end

					task.wait(0.05)
				until not aeroAlive()
			end
		end,
		Tooltip = 'drops ur loot right before u die to the void'
	})
	
	OwlCheck = AutoVoidDrop:CreateToggle({
		Name = 'Owl check',
		Default = true,
		Tooltip = 'doesnt drop items if being picked up by an owl'
	})
	PearlCheck = AutoVoidDrop:CreateToggle({
		Name = 'Pearl check',
		Default = false,
		Tooltip = 'does not drop if holding a pearl or recently threw one (4 sec cooldown)'
	})
	AutoReset = AutoVoidDrop:CreateToggle({
		Name = 'Auto Reset',
		Default = false,
		Tooltip = 'resets ur character right after dropping all the loot gng'
	})
	DropToggles.iron = AutoVoidDrop:CreateToggle({
		Name = 'Drop Iron',
		Default = true
	})
	DropToggles.diamond = AutoVoidDrop:CreateToggle({
		Name = 'Drop Diamond',
		Default = true
	})
	DropToggles.emerald = AutoVoidDrop:CreateToggle({
		Name = 'Drop Emerald',
		Default = true
	})
	DropToggles.gold = AutoVoidDrop:CreateToggle({
		Name = 'Drop Gold',
		Default = true
	})
end)

run(function()
	local Scaffold
	local Expand
	local Tower
	local Downwards
	local Diagonal
	local LimitItem
	local Mouse
	local PlaceDelay
	local adjacent, lastpos = {}, Vector3.zero
	local lastPlaceTime = 0
	
	for x = -3, 3, 3 do
		for y = -3, 3, 3 do
			for z = -3, 3, 3 do
				local vec = Vector3.new(x, y, z)
				if vec ~= Vector3.zero then
					table.insert(adjacent, vec)
				end
			end
		end
	end
	
	local function checkAdjacent(pos)
		for _, v in adjacent do
			if getPlacedBlock(pos + v) then
				return true
			end
		end
		return false
	end
	
	local function getScaffoldBlock()
		if store.hand.toolType == 'block' then
			return store.hand.tool.Name, store.hand.amount
		elseif (not LimitItem.Enabled) then
			local isHoldingSwordOrTool = store.hand.toolType == 'sword' or (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].sword)
			if not isHoldingSwordOrTool then
				local wool, amount = getWool()
				if wool then
					return wool, amount
				else
					for _, item in invItems() do
						if bedwars.ItemMeta[item.itemType].block then
							return item.itemType, item.amount
						end
					end
				end
			end
		end
	
		return nil, 0
	end
	
	Scaffold = vape.Categories.Utility:CreateModule({
		Name = 'Scaffold',
		Function = function(callback)
			local aeroAlive = newRun(Scaffold)
			if callback then
				lastPlaceTime = 0
				repeat
					if entitylib.isAlive then
						local wool, amount = getScaffoldBlock()

						if Mouse.Enabled then
							if not inputService:IsMouseButtonPressed(0) then
								wool = nil
							end
						end

						if wool then
							local root = entitylib.character.RootPart
							if Tower.Enabled and inputService:IsKeyDown(Enum.KeyCode.Space) and (not inputService:GetFocusedTextBox()) then
								root.Velocity = Vector3.new(root.Velocity.X, 38, root.Velocity.Z)
							end

							for i = Expand.Value, 1, -1 do
								local currentpos = roundPos(root.Position - Vector3.new(0, entitylib.character.HipHeight + (Downwards.Enabled and inputService:IsKeyDown(Enum.KeyCode.LeftShift) and 4.5 or 1.5), 0) + entitylib.character.Humanoid.MoveDirection * (i * 3))
								if Diagonal.Enabled then
									if math.abs(math.round(math.deg(math.atan2(-entitylib.character.Humanoid.MoveDirection.X, -entitylib.character.Humanoid.MoveDirection.Z)) / 45) * 45) % 90 == 45 then
										local dt = (lastpos - currentpos)
										if ((dt.X == 0 and dt.Z ~= 0) or (dt.X ~= 0 and dt.Z == 0)) and ((lastpos - root.Position) * Vector3.new(1, 0, 1)).Magnitude < 2.5 then
											currentpos = lastpos
										end
									end
								end

								local block, blockpos = getPlacedBlock(currentpos)
								if not block then
									if tick() - lastPlaceTime >= (PlaceDelay.Value / 1000) then
										blockpos = checkAdjacent(blockpos * 3) and blockpos * 3 or blockProximity(currentpos)
										if blockpos then
											task.spawn(bedwars.placeBlock, blockpos, wool, false)
											lastPlaceTime = tick()
										end
									end
								end
								lastpos = currentpos
							end
						end
					end

					task.wait(0.03)
				until not aeroAlive()
			else
				lastPlaceTime = 0
			end
		end,
		Tooltip = 'helps u make bridges/scaffold walk'
	})
	Expand = Scaffold:CreateSlider({
		Name = 'Expand',
		Min = 1,
		Max = 6
	})
	Tower = Scaffold:CreateToggle({
		Name = 'Tower',
		Default = true
	})
	Downwards = Scaffold:CreateToggle({
		Name = 'Downwards',
		Default = true
	})
	Diagonal = Scaffold:CreateToggle({
		Name = 'Diagonal',
		Default = true
	})
	LimitItem = Scaffold:CreateToggle({Name = 'Limit to items'})
	Mouse = Scaffold:CreateToggle({Name = 'Require mouse down'})
	PlaceDelay = Scaffold:CreateSlider({
		Name = 'Place Delay',
		Min = 0,
		Max = 200,
		Default = 0,
		Suffix = "ms"
	})
end)

run(function()
	local ViewMatchHistory

	ViewMatchHistory = vape.Categories.Utility:CreateModule({
		Name = "ViewMatchHistory",
		Function = function(callback)
			if callback then
				ViewMatchHistory:Toggle(false)
				local d = nil
				bedwars.MatchHistoryController:requestMatchHistory(lplr.Name):andThen(function(Data)
					if Data then
						bedwars.AppController:openApp({app = bedwars.MatchHistoryApp,appId = "MatchHistoryApp",},Data)
					end
				end)
			else
				return
			end
		end,
	})																								
end)

run(function()
	local KitRender
	local LastKitToggle
	local LastKitCount
	local LevelToggle
	local PartyToggle
	local Players = playersService
	local player = Players.LocalPlayer
	local PlayerGui = player:WaitForChild("PlayerGui")
	local scanThread = nil
	local retryThread = nil
	local currentDraft = nil
	local lastKitCache = {}
	local lastKitPending = {}
	local lastKitRetry = {}
	local partyCache = {}
	local currentPartyNumbers = {}

	local function resolveKitImage(kit)
		kit = kit or "none"
		local meta = bedwars.BedwarsKitMeta and (bedwars.BedwarsKitMeta[kit] or bedwars.BedwarsKitMeta.none)
		return (meta and meta.renderImage) or kitImageIds[kit] or kitImageIds["none"] or ""
	end

	local function clearLastKitCache()
		table.clear(lastKitCache)
		table.clear(lastKitPending)
		table.clear(lastKitRetry)
		table.clear(partyCache)
		table.clear(currentPartyNumbers)
	end

	local function destroyNamed(root, name)
		if not root then return end
		for _, obj in root:GetDescendants() do
			if obj.Name == name then
				obj:Destroy()
			end
		end
	end

	local function cleanupVisuals()
		destroyNamed(PlayerGui, "aerov4KitRender")
		destroyNamed(PlayerGui, "aerov4KitIcon")
		destroyNamed(PlayerGui, "aerov4KitLevel")
		destroyNamed(PlayerGui, "aerov4LastKit")
	end

	local function cleanupLastMatch()
		destroyNamed(PlayerGui, "aerov4LastKit")
	end

	local function extractHistory(payload)
		if type(payload) ~= "table" then return nil end

		if type(payload.matchHistory) == "table" then
			return payload.matchHistory
		end

		if type(payload.data) == "table" then
			if type(payload.data.matchHistory) == "table" then
				return payload.data.matchHistory
			end
			if type(payload.data.history) == "table" then
				return payload.data.history
			end
			if next(payload.data) ~= nil then
				return payload.data
			end
		end

		if type(payload.history) == "table" then
			return payload.history
		end

		return payload
	end

	local function getMatchEntry(match, uid)
		if type(match) ~= "table" or type(match.players) ~= "table" then return nil end
		for _, entry in match.players do
			local info = entry and entry.playerInfo
			if info and tostring(info.userId) == tostring(uid) then
				return entry
			end
		end
		return nil
	end

	local function readLastCompletedKit(history, uid)
		if type(history) ~= "table" then return nil end

		local matches = {}
		local order = 0

		if history[1] ~= nil then
			for index, match in ipairs(history) do
				if type(match) == "table" then
					order += 1
					table.insert(matches, {
						match = match,
						time = tonumber(match.matchStartTime) or tonumber(match.startTime) or 0,
						order = order,
						index = index
					})
				end
			end
		else
			for index, match in pairs(history) do
				if type(match) == "table" then
					order += 1
					table.insert(matches, {
						match = match,
						time = tonumber(match.matchStartTime) or tonumber(match.startTime) or 0,
						order = order,
						index = tonumber(index) or order
					})
				end
			end
		end

		table.sort(matches, function(a, b)
			if a.time ~= b.time then
				return a.time > b.time
			end
			if a.index ~= b.index then
				return a.index < b.index
			end
			return a.order < b.order
		end)

		local kits = {}
		local loose = {}

		for _, record in matches do
			local entry = getMatchEntry(record.match, uid)
			if entry then
				local kit = entry.bedwars and entry.bedwars.kit
				if type(kit) == "string" and kit ~= "" then
					local outcome = entry.generic and string.lower(tostring(entry.generic.matchOutcome or "")) or ""
					if outcome == "win"
						or outcome == "loss"
						or outcome == "lose"
						or outcome == "lost"
						or outcome == "defeat"
						or outcome == "victory" then
						table.insert(kits, kit)
						if #kits >= 5 then break end
					elseif #loose < 5 then
						table.insert(loose, kit)
					end
				end
			end
		end

		if #kits == 0 then
			kits = loose
		end

		return #kits > 0 and kits or nil
	end

	local function readTeammates(history, uid)
		local found = {}
		if type(history) ~= "table" then return found end
		local matches = {}
		for _, match in pairs(history) do
			if type(match) == "table" and type(match.players) == "table" then
				table.insert(matches, match)
			end
		end
		table.sort(matches, function(a, b)
			return (tonumber(a.matchStartTime) or 0) > (tonumber(b.matchStartTime) or 0)
		end)
		local decided = {}
		for i = 1, math.min(5, #matches) do
			local match = matches[i]
			local me = getMatchEntry(match, uid)
			local myTeam = me and (me.teamId or (me.generic and me.generic.team))
			local myParty = me and me.partyId
			if me then
				for _, entry in match.players do
					local info = entry and entry.playerInfo
					local key = info and tonumber(info.userId)
					if key and not entry.observer and tostring(info.userId) ~= tostring(uid) and not decided[key] then
						if myParty ~= nil and entry.partyId ~= nil then
							decided[key] = true
							found[key] = tostring(entry.partyId) == tostring(myParty) and 2 or nil
						elseif myTeam then
							local otherTeam = entry.teamId or (entry.generic and entry.generic.team)
							if tostring(otherTeam) == tostring(myTeam) then
								found[key] = (found[key] or 0) + 1
							end
						end
					end
				end
			end
		end
		return found
	end

	local function finishLastKit(uid, payload)
		local history = extractHistory(payload)
		local kit = readLastCompletedKit(history, uid)
		lastKitCache[uid] = kit or false
		partyCache[uid] = readTeammates(history, uid)
		lastKitPending[uid] = nil
		lastKitRetry[uid] = nil
	end

	local function failLastKit(uid)
		lastKitPending[uid] = nil
		lastKitRetry[uid] = tick() + 1.5
	end

	local function consumeHistoryRequest(uid, request)
		if type(request) == "table" and type(request.andThen) == "function" then
			local chained = pcall(function()
				request:andThen(function(data)
					finishLastKit(uid, data)
				end):catch(function()
					failLastKit(uid)
				end)
			end)
			if not chained then
				failLastKit(uid)
			end
			return
		end

		if type(request) == "table" then
			finishLastKit(uid, request)
		else
			failLastKit(uid)
		end
	end

	local function fetchLastKit(plr)
		if not plr then return end
		local uid = plr.UserId
		if lastKitCache[uid] ~= nil or lastKitPending[uid] then return end
		if lastKitRetry[uid] and tick() < lastKitRetry[uid] then return end

		lastKitPending[uid] = true

		task.spawn(function()
			local controllers = (bedwars.KnitClient and bedwars.KnitClient.Controllers)
				or (bedwars.Knit and bedwars.Knit.Controllers)
			local controller = bedwars.MatchHistoryController
				or (controllers and controllers.MatchHistoryController)
				or bedwars.MatchHistoryController

			local request = nil

			if controller and type(controller.requestMatchHistory) == "function" then
				local ok, result = pcall(function()
					return controller:requestMatchHistory(plr.Name)
				end)
				if ok then
					request = result
				end
			end

			if not request then
				pcall(function()
					request = bedwars.Client:Get("RequestMatchHistory"):CallServerAsync(plr.Name)
				end)
			end

			if not request then
				local _remotes = getgenv().remotes or remotes
				pcall(function()
					local remoteName = _remotes and (_remotes.RequestMatchHistory or "RequestMatchHistory") or "RequestMatchHistory"
					request = bedwars.Client:Get(remoteName):CallServerAsync(plr.Name)
				end)
			end

			if not request then
				pcall(function()
					local client = require(replicatedStorage.TS.remotes).default.Client
					request = client:Get("RequestMatchHistory"):CallServerAsync(plr.Name)
				end)
			end

			if not request then
				failLastKit(uid)
				return
			end

			consumeHistoryRequest(uid, request)
		end)
	end

	local function unclip(inst)
		local node = inst
		for _ = 1, 7 do
			if not node then break end
			pcall(function()
				node.ClipsDescendants = false
			end)
			node = node.Parent
		end
	end

	local function findPlayerFromRender(render)
		if not render then return nil end

		local image = tostring(render.Image or "")
		local userId = image:match("id=(%d+)")
			or image:match("userId=(%d+)")
			or image:match("(%d+)")

		if userId then
			local plr = Players:GetPlayerByUserId(tonumber(userId))
			if plr then return plr end
		end

		local node = render.Parent
		for _ = 1, 6 do
			if not node then break end
			local label = node:FindFirstChild("PlayerName", true)
			if label and label:IsA("TextLabel") then
				local text = label.Text
				for _, plr in Players:GetPlayers() do
					if plr.Name == text or plr.DisplayName == text or plr:GetAttribute("DisguiseDisplayName") == text then
						return plr
					end
					local smName = nil
					pcall(function()
						smName = bedwars.KnitClient.Controllers.StreamerModeController:getDisplayName(plr)
					end)
					if smName and smName == text then
						return plr
					end
				end
			end
			node = node.Parent
		end

		return nil
	end

	local function findHost(render)
		local node = render
		local fallback = nil

		for _ = 1, 8 do
			node = node and node.Parent
			if not node then break end

			if node.Name == "MatchDraftPlayerCard" then
				return node
			end

			if not fallback and node:FindFirstChild("PlayerName", true) and node:FindFirstChild("PlayerRender", true) then
				fallback = node
			end
		end

		return fallback or render.Parent
	end

	local function isEnemy(plr)
		if not plr or plr == player then return false end
		local myTeam = player:GetAttribute("Team")
		local theirTeam = plr:GetAttribute("Team")
		if not myTeam or not theirTeam then return false end
		return myTeam ~= theirTeam
	end

	local function ensureCurrentKit(host, plr)
		if not host or not host.Parent then return end
		unclip(host)

		local icon = host:FindFirstChild("aerov4KitRender")
		if not icon then
			icon = Instance.new("ImageLabel")
			icon.Name = "aerov4KitRender"
			icon.AnchorPoint = Vector2.new(1, 0.5)
			icon.Position = UDim2.new(1.05, 0, 0.5, 0)
			icon.Size = UDim2.new(1.5, 0, 1.5, 0)
			icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
			icon.BackgroundTransparency = 1
			icon.BorderSizePixel = 0
			icon.ImageTransparency = 0.4
			icon.ScaleType = Enum.ScaleType.Crop
			icon.ZIndex = 5

			local ratio = Instance.new("UIAspectRatioConstraint")
			ratio.AspectRatio = 1
			ratio.AspectType = Enum.AspectType.FitWithinMaxSize
			ratio.DominantAxis = Enum.DominantAxis.Width
			ratio.Parent = icon

			icon.Parent = host
		end

		local kit = plr:GetAttribute("PlayingAsKits") or "none"
		local image = resolveKitImage(kit)
		if icon.Image ~= image then
			icon.Image = image
		end
	end

	local function ensureLevel(host, plr)
		if not host or not host.Parent then return end
		local nameLabel = host:FindFirstChild("PlayerName", true)
		if not nameLabel then return end
		unclip(nameLabel)

		local levelLabel = nameLabel:FindFirstChild("aerov4KitLevel")
		if not levelLabel then
			levelLabel = Instance.new("TextLabel")
			levelLabel.Name = "aerov4KitLevel"
			levelLabel.AnchorPoint = Vector2.new(0, 0.5)
			levelLabel.Position = UDim2.new(1, 5, 0.5, 0)
			levelLabel.Size = UDim2.fromOffset(44, 15)
			levelLabel.BackgroundTransparency = 1
			levelLabel.TextColor3 = Color3.fromRGB(255, 214, 51)
			levelLabel.TextSize = 12
			levelLabel.Font = Enum.Font.GothamBold
			levelLabel.TextStrokeTransparency = 0.25
			levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			levelLabel.TextXAlignment = Enum.TextXAlignment.Left
			levelLabel.TextYAlignment = Enum.TextYAlignment.Center
			levelLabel.ZIndex = 10001
			levelLabel.Parent = nameLabel
		end

		local level = plr:GetAttribute("PlayerLevel") or 0
		local text = "[" .. tostring(level) .. "]"
		if levelLabel.Text ~= text then
			levelLabel.Text = text
		end
	end

	local function createLastMatchBadge(host, plr, slot)
		slot = slot or 1
		local badge = Instance.new("Frame")
		badge.Name = "aerov4LastKit"
		badge:SetAttribute("UserId", plr.UserId)
		badge:SetAttribute("Slot", slot)
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(0.41, (slot - 1) * 58, 0.5, 0)
		badge.Size = UDim2.fromOffset(54, 56)
		badge.BackgroundTransparency = 1
		badge.BorderSizePixel = 0
		badge.ClipsDescendants = false
		badge.ZIndex = 10000
		badge.Visible = false

		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.AnchorPoint = Vector2.new(0.5, 0)
		tag.Position = UDim2.new(0.5, 0, 0, -1)
		tag.Size = UDim2.new(1.1, 0, 0, 14)
		tag.BackgroundTransparency = 1
		tag.Text = slot == 1 and "last game" or (slot .. " games ago")
		tag.TextColor3 = Color3.fromRGB(255, 64, 64)
		tag.TextSize = 10
		tag.Font = Enum.Font.FredokaOne
		tag.TextStrokeTransparency = 0.35
		tag.TextStrokeColor3 = Color3.new(0, 0, 0)
		tag.TextXAlignment = Enum.TextXAlignment.Center
		tag.ZIndex = 10002
		tag.Parent = badge

		local img = Instance.new("ImageLabel")
		img.Name = "Render"
		img.AnchorPoint = Vector2.new(0.5, 1)
		img.Position = UDim2.new(0.5, 0, 1, 1)
		img.Size = UDim2.fromOffset(44, 41)
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.ImageTransparency = 0.05
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 10001
		img.Parent = badge

		badge.Parent = host
		return badge
	end

	local function ensureLastMatch(host, plr)
		if not host or not host.Parent then return end

		if not (LastKitToggle and LastKitToggle.Enabled) then
			for _, old in host:GetChildren() do
				if old.Name == "aerov4LastKit" then
					old:Destroy()
				end
			end
			return
		end

		unclip(host)

		local count = LastKitCount and LastKitCount.Value or 1
		local badges = {}
		for _, obj in host:GetChildren() do
			if obj.Name == "aerov4LastKit" then
				local slot = obj:GetAttribute("Slot") or 1
				if slot > count or badges[slot] then
					obj:Destroy()
				else
					badges[slot] = obj
				end
			end
		end

		local cached = lastKitCache[plr.UserId]
		if cached == nil then
			fetchLastKit(plr)
		end

		for slot = 1, count do
			local badge = badges[slot] or createLastMatchBadge(host, plr, slot)
			local kit = type(cached) == "table" and cached[slot]
			if kit then
				local img = badge:FindFirstChild("Render")
				local image = resolveKitImage(kit)
				if img and img.Image ~= image then
					img.Image = image
				end
				badge.Visible = true
			else
				badge.Visible = false
			end
		end
	end

	local function getPartyNumbers()
		local list = {}
		for _, plr in Players:GetPlayers() do
			if partyCache[plr.UserId] then
				table.insert(list, plr)
			end
		end
		table.sort(list, function(a, b)
			return a.UserId < b.UserId
		end)
		local parent = {}
		local function find(x)
			while parent[x] ~= x do
				x = parent[x]
			end
			return x
		end
		for _, plr in list do
			parent[plr.UserId] = plr.UserId
		end
		for i, a in list do
			for j = i + 1, #list do
				local b = list[j]
				if a:GetAttribute("Team") == b:GetAttribute("Team") then
					local ab = partyCache[a.UserId][b.UserId] or 0
					local ba = partyCache[b.UserId][a.UserId] or 0
					if math.max(ab, ba) >= 2 then
						parent[find(b.UserId)] = find(a.UserId)
					end
				end
			end
		end
		local groups, order = {}, {}
		for _, plr in list do
			local root = find(plr.UserId)
			if not groups[root] then
				groups[root] = {}
				table.insert(order, root)
			end
			table.insert(groups[root], plr.UserId)
		end
		local numbers = {}
		local n = 0
		for _, root in order do
			if #groups[root] >= 2 then
				n += 1
				for _, id in groups[root] do
					numbers[id] = n
				end
			end
		end
		return numbers
	end

	local function ensureParty(host, plr)
		local icon = host and host:FindFirstChild("aerov4KitRender")
		if not icon then return end
		local badge = icon:FindFirstChild("aerov4Party")
		local num = PartyToggle and PartyToggle.Enabled and currentPartyNumbers[plr.UserId]
		if not num then
			if badge then
				badge.Visible = false
			end
			return
		end
		if not badge then
			badge = Instance.new("TextLabel")
			badge.Name = "aerov4Party"
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 2, 0, -2)
			badge.Size = UDim2.fromOffset(16, 16)
			badge.BackgroundColor3 = Color3.fromRGB(40, 120, 255)
			badge.BorderSizePixel = 0
			badge.TextColor3 = Color3.new(1, 1, 1)
			badge.TextSize = 11
			badge.Font = Enum.Font.GothamBold
			badge.ZIndex = 10003
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = badge
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 1
			stroke.Color = Color3.new(0, 0, 0)
			stroke.Parent = badge
			badge.Parent = icon
		end
		local text = tostring(num)
		if badge.Text ~= text then
			badge.Text = text
		end
		badge.Visible = true
	end

	local function processRender(render)
		if not KitRender.Enabled or not render or not render.Parent then return end
		if render.Name ~= "PlayerRender" or not render:IsA("ImageLabel") then return end

		local plr = findPlayerFromRender(render)
		if not plr then return end
		if not isEnemy(plr) then
			local mine, theirs = player:GetAttribute("Team"), plr:GetAttribute("Team")
			if mine and theirs and mine == theirs then
				local mateHost = findHost(render)
				destroyNamed(mateHost, "aerov4KitRender")
				destroyNamed(mateHost, "aerov4KitLevel")
				destroyNamed(mateHost, "aerov4LastKit")
			end
			return
		end

		local host = findHost(render)
		if not host or not host.Parent then return end

		ensureCurrentKit(host, plr)
		if LevelToggle and LevelToggle.Enabled then
			ensureLevel(host, plr)
		else
			destroyNamed(host, "aerov4KitLevel")
		end
		ensureLastMatch(host, plr)
		if PartyToggle and PartyToggle.Enabled and lastKitCache[plr.UserId] == nil then
			fetchLastKit(plr)
		end
		ensureParty(host, plr)
	end

	local function scanDraft(app)
		if not app or not app.Parent then return end
		currentPartyNumbers = getPartyNumbers()
		for _, obj in app:GetDescendants() do
			if obj.Name == "PlayerRender" and obj:IsA("ImageLabel") then
				pcall(processRender, obj)
			end
		end
	end

	local function startScanner()
		if scanThread then return end

		scanThread = task.spawn(function()
			while KitRender and KitRender.Enabled do
				local app = PlayerGui:FindFirstChild("MatchDraftApp")

				if app ~= currentDraft then
					cleanupVisuals()
					clearLastKitCache()
					currentDraft = app
				end

				if app then
					pcall(scanDraft, app)
				end

				task.wait(0.25)
			end

			scanThread = nil
		end)
	end

	local function stopScanner()
		if scanThread then
			pcall(task.cancel, scanThread)
			scanThread = nil
		end

		if retryThread then
			pcall(task.cancel, retryThread)
			retryThread = nil
		end

		currentDraft = nil
		clearLastKitCache()
		cleanupVisuals()
	end

	KitRender = vape.Categories.Utility:CreateModule({
		Name = "KitRender",
		Tooltip = "renders enemy kits during draft and shows their last match kit",
		Function = function(callback)
			if callback then
				cleanupVisuals()
				clearLastKitCache()
				startScanner()

				if not PlayerGui:FindFirstChild("MatchDraftApp") then
					retryThread = task.spawn(function()
						while KitRender.Enabled and not PlayerGui:FindFirstChild("MatchDraftApp") do
							task.wait(0.25)
						end
						if KitRender.Enabled then
							startScanner()
						end
						retryThread = nil
					end)
				end
			else
				stopScanner()
			end
		end
	})

	LastKitToggle = KitRender:CreateToggle({
		Name = "Show Last Match",
		Default = true,
		Tooltip = "shows the kit they used in their last completed match",
		Function = function(callback)
			if LastKitCount then
				LastKitCount.Object.Visible = callback
			end

			if not callback then
				cleanupLastMatch()
				return
			end

			clearLastKitCache()
			if KitRender and KitRender.Enabled then
				local app = PlayerGui:FindFirstChild("MatchDraftApp")
				if app then
					pcall(scanDraft, app)
				end
			end
		end
	})

	LastKitCount = KitRender:CreateSlider({
		Name = "last match count",
		Min = 1,
		Max = 5,
		Default = 1,
		Tooltip = "how many of they old kits u tryna see gng, 1 is they last game and 5 is 5 games ago",
		Function = function()
			if KitRender and KitRender.Enabled then
				local app = PlayerGui:FindFirstChild("MatchDraftApp")
				if app then
					pcall(scanDraft, app)
				end
			end
		end
	})
	LastKitCount.Object.Visible = LastKitToggle.Enabled

	LevelToggle = KitRender:CreateToggle({
		Name = "show level",
		Default = true,
		Tooltip = "shows they level next to they name so u know if they a sweat or not",
		Function = function()
			if KitRender and KitRender.Enabled then
				local app = PlayerGui:FindFirstChild("MatchDraftApp")
				if app then
					pcall(scanDraft, app)
				end
			end
		end
	})

	PartyToggle = KitRender:CreateToggle({
		Name = "show party",
		Default = true,
		Tooltip = "puts a number on ppl who queue together, same number means same party",
		Function = function()
			if KitRender and KitRender.Enabled then
				local app = PlayerGui:FindFirstChild("MatchDraftApp")
				if app then
					pcall(scanDraft, app)
				end
			end
		end
	})
end)

run(function()
	local StaffDetector
	local ClosetDetect
	local Mode
	local Clans
	local Party
	local Profile
	local Users
	local AlertDuration
	local blacklistedclans = {'gg', 'gg2', 'DV', 'DV2', 'nwr'}
	local blacklisteduserids = {1502104539, 3826146717, 4531785383, 1049767300, 4926350670, 653085195, 184655415, 2752307430, 5087196317, 5744061325, 1536265275}
	local apiModNames = {}
	local teamNameMap = { [1] = 'Blue', [2] = 'Orange', [3] = 'Pink', [4] = 'Yellow' }
	local joined = {}
	local detectedPlayers = {}
	local processing = {}
	for _, name in ipairs({'chasemaser','IllIlllIIIllllIIIll','7SlyR','DoordashRP','OrionYeets','lIllllllllllIllIIlll','AUW345678','the2ndtestaccount','IllIIIIlllIlllIIIIIl','IllIIIIlllIlllIlIIII','ProSurferGamer1','22willow_place','celisnix','G_TP56','celisnix_3','nwrkr','lIIlIlIllllllIIlI','IllIIIIIIlllllIIlIlI','GorillaWithASuit','liilliilliiiliill','IllIllIllllIIIIIIlIl','Typhoon_Kang','VictoryForLife2468','IlIIIlllllIIIIlIIIIl','Erin_Ireland22','IIIIllIIIIIIlllIlIII','IIIIIlllIlllllIlII','Ghostwxstaken','wvwvwvwwvwvvwvw','lllIIllIllIIllIllII','TheAwkwardSponge','TotallyKoaIa','YT_GoraPlays','LegendaryToragon','appleapplelllllll','Yo_johnny67','llIIllIIllllIlIl','PoopFarm_1','llIIIllIIIIIllllIII','Lemon01204','HugeMudOtter','AGameMasterHD','krustykrab204','kevinchuey','IllIIIIlIllIlIIIlI','YoZevStar','pzlican','Deevicus','Blackprincess1','yhpro1230','eple_147','whoisdv2_erin','whoisdv4_erin','whoisdv3_erin','VicForLife14','SleeplessSoulmate','Jsquire07','DVwastaken','pxIican','devzebu','FunFamilyKids177','Artan3333','3MEWMTS5LJCB','Zengoulen','GloriousConfigB2','heywasupsir','c6chisa'}) do
		apiModNames[name:lower()] = true
	end
	local listsLoaded = true

	getgenv()._onnation_staffCounts = {spec=0, mod=0, impossible=0}
	local function refreshStaffCounts()
		local c = {spec=0, mod=0, impossible=0}
		for _, data in pairs(detectedPlayers) do
			local ct = data.checktype
			if ct == 'spectator' then c.spec += 1
			elseif ct == 'impossible_join' then c.impossible += 1
			elseif ct == 'unverified' then c.impossible += 1
			else c.mod += 1 end
		end
		getgenv()._aerov4_staffCounts = c
		vapeEvents.StaffCountUpdate:Fire()
	end

	local function staffFunction(plr, checktype)
		if detectedPlayers[plr.UserId] then return end
		if not vape.Loaded then repeat task.wait() until vape.Loaded end
		local duration = AlertDuration.Value
		local playerName = plr.Name
		local playerId = plr.UserId
		detectedPlayers[playerId] = {name=playerName, checktype=checktype, detectedTime=tick()}
		notif('StaffDetector', 'staff detected (' .. checktype .. '): ' .. playerName .. ' (' .. playerId .. ')', duration, 'alert')
		whitelist.customtags[playerName] = {{text='GAME STAFF', color=Color3.new(1,0,0)}}
		local isClanCheck = checktype:find('clan')
		if Party.Enabled and not isClanCheck then pcall(bedwars.PartyController.leaveParty) end
		local modeValue = Mode.Value
		if modeValue == 'Uninject' then
			task.spawn(function() vape:Uninject() end)
			game:GetService('StarterGui'):SetCore('SendNotification', {Title='StaffDetector',Text='Staff Detected ('..checktype..')\n'..playerName..' ('..playerId..')',Duration=duration})
		elseif modeValue == 'Requeue' then
			pcall(bedwars.QueueController.leaveQueue)
			bedwars.QueueController:joinQueue(store.queueType)
		elseif modeValue == 'Profile' then
			if checktype == 'known_mod' or checktype == 'blacklisted_user' then
				vape.Save = function() end
				if vape.Profile ~= Profile.Value then vape:Load(true, Profile.Value) end
			end
		elseif modeValue == 'AutoConfig' then
			local safe = {AutoClicker=true,Reach=true,Sprint=true,HitFix=true,StaffDetector=true}
			vape.Save = function() end
			for i, v in vape.Modules do
				if not (safe[i] or v.Category == 'Render') then
					if v.Enabled then v:Toggle() end
					v:SetBind('')
				end
			end
		end
		refreshStaffCounts()
	end

	local function playerAdded(plr)
		joined[plr.UserId] = plr.Name
		if plr == lplr then return end
		if processing[plr.UserId] then return end
		processing[plr.UserId] = true

		if not listsLoaded then
			local t = tick()
			repeat task.wait(0.1) until listsLoaded or (tick()-t > 3)
		end

		if table.find(blacklisteduserids, plr.UserId) or (Users and table.find(Users.ListEnabled, tostring(plr.UserId))) then
			staffFunction(plr, 'blacklisted_user')
			processing[plr.UserId] = nil
			return
		end

		if apiModNames[plr.Name:lower()] then
			staffFunction(plr, 'known_mod')
			processing[plr.UserId] = nil
			return
		end

		local function spectatorFunction(plr)
			if detectedPlayers[plr.UserId] then return end
			if not vape.Loaded then repeat task.wait() until vape.Loaded end
			detectedPlayers[plr.UserId] = {name=plr.Name, checktype='spectator', detectedTime=tick()}
			notif('StaffDetector', 'spectator: '..plr.Name..' ('..tostring(plr.UserId)..') [has friend(s) in server]', AlertDuration.Value, 'warning')
			refreshStaffCounts()
		end

		local function unverifiedFunction(plr, failed, checked)
			if detectedPlayers[plr.UserId] then return end
			if not vape.Loaded then repeat task.wait() until vape.Loaded end
			detectedPlayers[plr.UserId] = {name=plr.Name, checktype='unverified', detectedTime=tick()}
			notif('StaffDetector', 'cant check '..plr.Name..' ('..tostring(plr.UserId)..') friends list gng, could be staff. couldnt check '..tostring(failed)..'/'..tostring(checked)..' ppl', AlertDuration.Value, 'warning')
			refreshStaffCounts()
		end

		local function checkJoin()
			if not plr:GetAttribute('Team') and plr:GetAttribute('Spectator') then
				local hasFriend = false
				local failed = 0
				local checked = 0
				for _, sp in ipairs(playersService:GetPlayers()) do
					if sp ~= plr then
						checked = checked + 1
						local ok, res = pcall(function() return plr:IsFriendsWith(sp.UserId) end)
						if not ok then failed = failed + 1 end
						if ok and res then hasFriend = true break end
					end
				end
				if hasFriend then
					spectatorFunction(plr)
				elseif failed > 0 or checked == 0 then
					unverifiedFunction(plr, failed, checked)
				else
					staffFunction(plr, 'impossible_join')
				end
				return true
			end
			return false
		end

		local spectatorConnection
		spectatorConnection = plr:GetAttributeChangedSignal('Spectator'):Connect(function()
			if checkJoin() then spectatorConnection:Disconnect() processing[plr.UserId] = nil end
		end)
		StaffDetector:Clean(spectatorConnection)

		if checkJoin() then processing[plr.UserId] = nil return end

		if Clans.Enabled then
			local function checkClanTag()
				local clanTag = plr:GetAttribute('ClanTag')
				if clanTag and table.find(blacklistedclans, clanTag) then
					staffFunction(plr, 'blacklisted_clan_' .. clanTag:lower())
				end
			end
			if plr:GetAttribute('ClanTag') then
				checkClanTag()
			else
				local clanConnection
				clanConnection = plr:GetAttributeChangedSignal('ClanTag'):Connect(function()
					clanConnection:Disconnect()
					checkClanTag()
				end)
				StaffDetector:Clean(clanConnection)
				task.delay(5, function() if clanConnection then clanConnection:Disconnect() end end)
			end
		end

		processing[plr.UserId] = nil
	end

	local function playerRemoving(plr)
		local userId = plr.UserId
		joined[userId] = nil
		processing[userId] = nil
		if detectedPlayers[userId] then
			local data = detectedPlayers[userId]
			notif('StaffDetector', data.name .. ' (' .. data.checktype .. ') has left the server', AlertDuration.Value, 'warning')
			if whitelist.customtags[data.name] then whitelist.customtags[data.name] = nil end
			detectedPlayers[userId] = nil
			refreshStaffCounts()
		end
	end

	StaffDetector = vape.Categories.Utility:CreateModule({
		Name = 'StaffDetector',
		Function = function(callback)
			if callback then
				StaffDetector:Clean(playersService.PlayerAdded:Connect(playerAdded))
				StaffDetector:Clean(playersService.PlayerRemoving:Connect(playerRemoving))
				for _, v in playersService:GetPlayers() do task.spawn(playerAdded, v) end
			else
				table.clear(joined) table.clear(processing) table.clear(detectedPlayers)
				refreshStaffCounts()
			end
		end,
		Tooltip = 'detects people with staff role and etc'
	})

	Mode = StaffDetector:CreateDropdown({Name='Mode',List={'Uninject','Profile','Requeue','AutoConfig','Notify'},Function=function(val) if Profile.Object then Profile.Object.Visible = val=='Profile' end end})
	AlertDuration = StaffDetector:CreateSlider({Name='Alert Duration',Min=5,Max=120,Default=60,Suffix='s',})
	Clans = StaffDetector:CreateToggle({Name='Blacklist clans',Default=true})
	ClosetDetect = StaffDetector:CreateToggle({Name='Closet Cheaters',Default=true,Tooltip='tells u if a known closet cheater is in ur game so u know who to watch out for gng'})
	Party = StaffDetector:CreateToggle({Name='Leave party'})
	Profile = StaffDetector:CreateTextBox({Name='Profile',Default='default',Darker=true,Visible=false})
	Users = StaffDetector:CreateTextList({Name='Users',Placeholder='player (userid)',Function=function() end})
	task.defer(function() if Profile and Profile.Object then Profile.Object.Visible = (Mode.Value=='Profile') end end)
end)

run(function()
	TrapDisabler = vape.Categories.Utility:CreateModule({
		Name = 'AntiTrap',
		Tooltip = 'stops traps that rely on ur client reporting them'
	})

	TrapSnap = TrapDisabler:CreateToggle({
		Name = 'Snap traps',
		Default = true,
		Tooltip = 'stops snap traps from freezing u'
	})

	TrapMine = TrapDisabler:CreateToggle({
		Name = 'Landmines',
		Default = true,
		Tooltip = 'stops invisible landmines from going off on u'
	})

	TrapTeleport = TrapDisabler:CreateToggle({
		Name = 'Teleport blocks',
		Default = true,
		Tooltip = 'stops teleport blocks from moving u'
	})

	TrapPortal = TrapDisabler:CreateToggle({
		Name = 'Void portals',
		Default = true,
		Tooltip = 'stops void portals from moving u, also blocks ur own'
	})
end)

run(function()
	local BedProtector
	local LimitItem
	local AutoSwitch
	local RangeSlider
	local LayerSlider
	local currentLayer = 0
	local buildingComplete = false
	local heldBlockType = nil
	local previousSlot = nil
	local lastPlaceTime = 0

	local ALLOWED_BLOCKS = {
		obsidian = true,
		wood_plank_oak = true,
		wood_oak_plank = true,
		ceramic = true,
		stone_brick = true
	}

	local function isAllowedBlock(itemType)
		if ALLOWED_BLOCKS[itemType] then return true end
		return itemType:find('wool') ~= nil
	end

	local pyramidCache = {}
	local function getPyramid(size, grid)
		local key = size .. ':' .. grid
		if pyramidCache[key] then return pyramidCache[key] end
		local positions = {}
		for h = size, 0, -1 do
			for w = h, 0, -1 do
				table.insert(positions, Vector3.new(w, (size - h), ((h + 1) - w)) * grid)
				table.insert(positions, Vector3.new(w * -1, (size - h), ((h + 1) - w)) * grid)
				table.insert(positions, Vector3.new(w, (size - h), (h - w) * -1) * grid)
				table.insert(positions, Vector3.new(w * -1, (size - h), (h - w) * -1) * grid)
			end
		end
		pyramidCache[key] = positions
		return positions
	end

	local function getMyBed()
		local myTeam = lplr:GetAttribute('Team')
		if not myTeam then return nil end
		local root = entitylib.character and entitylib.character.RootPart
		if not root then return nil end
		for _, bed in collectionService:GetTagged('bed') do
			if bed and bed.Parent and bed:GetAttribute('Team'..myTeam..'NoBreak') then
				local bedPos = bed:IsA('BasePart') and bed.Position or (bed.PrimaryPart and bed.PrimaryPart.Position or bed:GetPivot().Position)
				if (root.Position - bedPos).Magnitude < 40 then
					return bed
				end
			end
		end
		return nil
	end

	local function getBlocks()
		local blocks = {}
		for _, item in invItems() do
			local meta = bedwars.ItemMeta[item.itemType]
			if meta and meta.block and not meta.block.seeThrough and (item.amount or 0) > 0 and isAllowedBlock(item.itemType) then
				table.insert(blocks, {itemType = item.itemType, tool = item.tool, health = meta.block.health or 0})
			end
		end
		table.sort(blocks, function(a, b) return a.health > b.health end)
		return blocks
	end

	local function getBlockTypeForLayer(_, blocks)
		if #blocks == 0 then return nil end
		return blocks[1]
	end

	local function getSlotFor(itemType)
		for i, v in store.inventory.hotbar do
			if v.item and v.item.itemType == itemType then
				return i - 1
			end
		end
		return nil
	end

	local function restorePreviousSlot()
		if heldBlockType then
			if previousSlot then hotbarSwitch(previousSlot) end
			heldBlockType = nil
			previousSlot = nil
		end
	end

	local function switchToBlock(itemType)
		if LimitItem.Enabled then return end
		if not AutoSwitch.Enabled then return end
		if heldBlockType == itemType then return end
		local slot = getSlotFor(itemType)
		if slot then
			previousSlot = previousSlot or store.inventory.hotbarSlot
			hotbarSwitch(slot)
			heldBlockType = itemType
		end
	end

	local function isPositionInRange(worldPos)
		local root = entitylib.character and entitylib.character.RootPart
		if not root then return false end
		return (root.Position - worldPos).Magnitude <= RangeSlider.Value
	end

	local function repairAll(bedCFrame, blocks, upto)
		if upto <= 0 then return end

		local block = getBlockTypeForLayer(0, blocks) or blocks[1]
		if LimitItem.Enabled then
			if store.hand.toolType ~= 'block' then return end
			if not isAllowedBlock(store.hand.tool.Name) then return end
			block = {itemType = store.hand.tool.Name}
		end
		if not block then return end

		local switched = false
		for layer = 0, upto - 1 do
			local positions = getPyramid(layer + 1, 3)
			for _, pos in positions do
				if not BedProtector.Enabled then return end
				local worldPos = (bedCFrame * CFrame.new(pos)).Position
				if isPositionInRange(worldPos) and not getPlacedBlock(worldPos) then
					if not switched then
						switchToBlock(block.itemType)
						switched = true
					end
					task.spawn(bedwars.placeBlock, worldPos, block.itemType, false)
				end
			end
		end
	end

	local function buildLayer(bedCFrame, blocks)
		if buildingComplete then return false end

		local block = getBlockTypeForLayer(currentLayer, blocks) or blocks[1]
		if not block then return false end

		if LimitItem.Enabled then
			if store.hand.toolType ~= 'block' then return false end
			if not isAllowedBlock(store.hand.tool.Name) then return false end
			block = {itemType = store.hand.tool.Name}
		end

		local positions = getPyramid(currentLayer + 1, 3)
		local allPlaced = true
		local hasMissingInRange = false

		for _, pos in positions do
			local worldPos = (bedCFrame * CFrame.new(pos)).Position
			if not getPlacedBlock(worldPos) then
				allPlaced = false
				if isPositionInRange(worldPos) then
					hasMissingInRange = true
				end
			end
		end

		if allPlaced then
			currentLayer += 1
			if currentLayer >= LayerSlider.Value then
				buildingComplete = true
				restorePreviousSlot()
				notif('BedProtector', 'bed is fully walled gng ur good', 4)
			end
			return false
		end

		if not hasMissingInRange then return false end

		for _, pos in positions do
			if not BedProtector.Enabled then break end
			local worldPos = (bedCFrame * CFrame.new(pos)).Position
			if isPositionInRange(worldPos) and not getPlacedBlock(worldPos) then
				if tick() - lastPlaceTime >= 0.05 then
					switchToBlock(block.itemType)
					task.spawn(bedwars.placeBlock, worldPos, block.itemType, false)
					lastPlaceTime = tick()
					task.wait(0.05)
				end
			end
		end
		return true
	end

	BedProtector = vape.Categories.World:CreateModule({
		Name = 'BedProtector',
		Function = function(callback)
			local aeroAlive = newRun(BedProtector)
			if callback then
				currentLayer = 0
				buildingComplete = false
				heldBlockType = nil
				previousSlot = nil
				repeat
					pcall(function()
						if not entitylib.isAlive then return end
						local bed = getMyBed()
						if not bed then
							restorePreviousSlot()
							return
						end
						local bedCFrame = bed:IsA('BasePart') and bed.CFrame or (bed.PrimaryPart and bed.PrimaryPart.CFrame or bed:GetPivot())
						local blocks = getBlocks()
						if #blocks == 0 and not LimitItem.Enabled then return end
						repairAll(bedCFrame, blocks, currentLayer)
						if not buildingComplete then
							buildLayer(bedCFrame, blocks)
						end
					end)
					task.wait(0.05)
				until not aeroAlive()
				restorePreviousSlot()
			end
		end,
		Tooltip = 'stacks a pyramid over ur bed w ur strongest block'
	})

	LimitItem = BedProtector:CreateToggle({
		Name = 'Limit to items',
		Tooltip = 'only builds while ur already holdin a block'
	})
	AutoSwitch = BedProtector:CreateToggle({
		Name = 'Auto Switch',
		Default = true,
		Tooltip = 'swaps ur hotbar to the block by itself then swaps back after. ignored if limit to items is on'
	})
	RangeSlider = BedProtector:CreateSlider({
		Name = 'Place Range',
		Min = 1,
		Max = 30,
		Default = 15,
		Suffix = ' studs'
	})
	LayerSlider = BedProtector:CreateSlider({
		Name = 'Layers',
		Min = 1,
		Max = 10,
		Default = 3,
		Suffix = ' layers'
	})
end)

run(function()
    local anim
    local asset
    local trackingConnection
    local lastPosition
    local NightmareEmote
    local cachedRootPart
    local cachedHumanoid
    local lastValidationCheck = 0
    
    NightmareEmote = vape.Categories.World:CreateModule({
        Name = "NightmareEmote",
        Function = function(call)
            if call then
                local l__GameQueryUtil__8
                if (not shared.CheatEngineMode) then 
                    l__GameQueryUtil__8 = require(game:GetService("ReplicatedStorage")['rbxts_include']['node_modules']['@easy-games']['game-core'].out).GameQueryUtil 
                else
                    local backup = {}; function backup:setQueryIgnored() end; l__GameQueryUtil__8 = backup;
                end
                local l__TweenService__9 = tweenService
                local player = playersService.LocalPlayer
                local character = player.Character
                
                if not character then 
                    NightmareEmote:Toggle() 
                    return 
                end
                
                local humanoid = character:WaitForChild("Humanoid")
                local rootPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
                
                if not rootPart then 
                    NightmareEmote:Toggle() 
                    return 
                end
                
                cachedRootPart = rootPart
                cachedHumanoid = humanoid
                lastPosition = rootPart.Position
                lastValidationCheck = 0
                
                local v10 = game:GetService("ReplicatedStorage"):WaitForChild("Assets"):WaitForChild("Effects"):WaitForChild("NightmareEmote"):Clone()
                asset = v10
                v10.Parent = game.Workspace
                
                local descendants = v10:GetDescendants()
                for _, part in ipairs(descendants) do
                    if part:IsA("BasePart") then
                        l__GameQueryUtil__8:setQueryIgnored(part, true)
                        part.CanCollide = false
                        part.Anchored = true
                    end
                end
                
                local l__Outer__15 = v10:FindFirstChild("Outer")
                if l__Outer__15 then
                    l__TweenService__9:Create(l__Outer__15, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
                        Orientation = l__Outer__15.Orientation + Vector3.new(0, 360, 0)
                    }):Play()
                end
                
                local l__Middle__16 = v10:FindFirstChild("Middle")
                if l__Middle__16 then
                    l__TweenService__9:Create(l__Middle__16, TweenInfo.new(12.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
                        Orientation = l__Middle__16.Orientation + Vector3.new(0, -360, 0)
                    }):Play()
                end
                
                anim = Instance.new("Animation")
                anim.AnimationId = "rbxassetid://9191822700"
                anim = humanoid:LoadAnimation(anim)
                anim:Play()
                
                local movementThresholdSq = 0.1 * 0.1
                
                trackingConnection = runService.RenderStepped:Connect(function()
                    if not asset or not asset.Parent then 
                        if trackingConnection then
                            trackingConnection:Disconnect()
                        end
                        return 
                    end
                    
                    local currentTime = tick()
                    
                    if (currentTime - lastValidationCheck) > 0.5 then
                        if not character or not character.Parent then
                            asset:Destroy()
                            asset = nil
                            if trackingConnection then
                                trackingConnection:Disconnect()
                            end
                            NightmareEmote:Toggle()
                            return
                        end
                        
                        if not cachedRootPart or not cachedRootPart.Parent then
                            cachedRootPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
                        end
                        
                        if not cachedHumanoid or not cachedHumanoid.Parent then
                            cachedHumanoid = character:FindFirstChildOfClass("Humanoid")
                        end
                        
                        if not cachedRootPart or not cachedHumanoid or cachedHumanoid.Health <= 0 then
                            asset:Destroy()
                            asset = nil
                            if trackingConnection then
                                trackingConnection:Disconnect()
                            end
                            NightmareEmote:Toggle()
                            return
                        end
                        
                        lastValidationCheck = currentTime
                    end
                    
                    if lastPosition and cachedRootPart then
                        local currentPosition = cachedRootPart.Position
                        local dx = currentPosition.X - lastPosition.X
                        local dy = currentPosition.Y - lastPosition.Y
                        local dz = currentPosition.Z - lastPosition.Z
                        local distanceMovedSq = dx * dx + dy * dy + dz * dz
                        
                        if distanceMovedSq > movementThresholdSq then
                            asset:Destroy()
                            asset = nil
                            if trackingConnection then
                                trackingConnection:Disconnect()
                            end
                            NightmareEmote:Toggle()
                            return
                        end
                        
                        lastPosition = currentPosition
                    end
                    
                    if cachedRootPart then
                        v10:SetPrimaryPartCFrame(cachedRootPart.CFrame * CFrame.new(0, -3, 0))
                    end
                end)
                
                NightmareEmote:Clean(trackingConnection)
                
            else 
                if trackingConnection then
                    trackingConnection:Disconnect()
                    trackingConnection = nil
                end
                
                if anim then 
                    anim:Stop()
                    anim = nil
                end
                
                if asset then
                    asset:Destroy() 
                    asset = nil
                end
                
                lastPosition = nil
                cachedRootPart = nil
                cachedHumanoid = nil
                lastValidationCheck = 0
            end
        end
    })
end)

run(function()
    local AutoTool
    local old, event
    
    local function switchHotbarItem(block)
        if store.hand and store.hand.toolType == 'block' then return end
        if block and not block:GetAttribute('NoBreak') and not block:GetAttribute('Team'..(lplr:GetAttribute('Team') or 0)..'NoBreak') then
            local meta = bedwars.ItemMeta and bedwars.ItemMeta[block.Name]
			if not meta or not meta.block then return end
			local tool, slot = store.tools and store.tools[meta.block.breakType], nil
            if tool then
                for i, v in store.inventory.hotbar do
                    if v.item and v.item.itemType == tool.itemType then slot = i - 1 break end
                end
    
                if hotbarSwitch(slot) then
                    if inputService:IsMouseButtonPressed(0) then 
                        event:Fire() 
                    end
                    return true
                end
            end
        end
    end
    
    AutoTool = vape.Categories.World:CreateModule({
        Name = 'AutoTool',
        Function = function(callback)
            if callback then
                event = Instance.new('BindableEvent')
                AutoTool:Clean(event)
                AutoTool:Clean(event.Event:Connect(function()
                    contextActionService:CallFunction('block-break', Enum.UserInputState.Begin, newproxy(true))
                end))
                getgenv().registerHitBlockPatch('AutoTool', function(self, maid, raycastparams, ...)
                    local ok, block = pcall(function()
                        return self.clientManager:getBlockSelector():getMouseInfo(1, {ray = raycastparams})
                    end)
                    if not ok then return nil end
                    local inst = block and block.target and block.target.blockInstance or nil
                    local switched = false
                    pcall(function() switched = switchHotbarItem(inst) == true end)
                    if switched then return false end
                    return nil
                end)
            else
                getgenv().unregisterHitBlockPatch('AutoTool')
                old = nil
            end
        end,
        Tooltip = 'auto selects the correct tool'
    })
end)
	
store.chestTeamCache = setmetatable({}, {__mode = 'k'})
function store.getChestTeam(chest)
	if not chest then return nil end
	local cached = store.chestTeamCache[chest]
	if cached then return cached end
	local pos = chest:IsA('BasePart') and chest.Position or (chest:IsA('Model') and chest:GetPivot().Position)
	if not pos then return nil end
	local best, bestDist
	for _, tag in {'bed', 'BedwarsItemShop', 'TeamUpgradeShopkeeper'} do
		for _, thing in collectionService:GetTagged(tag) do
			local part = thing:IsA('BasePart') and thing or thing:FindFirstChildWhichIsA('BasePart', true)
			local team = thing:GetAttribute('TeamId') or thing:GetAttribute('Team')
			if part and team ~= nil and team ~= '' then
				local dist = (part.Position - pos).Magnitude
				if not bestDist or dist < bestDist then
					best, bestDist = tostring(team), dist
				end
			end
		end
	end
	if best and bestDist <= 150 then
		store.chestTeamCache[chest] = best
		return best
	end
	return nil
end
function store.isMyTeamChest(chest)
	local team = store.getChestTeam(chest)
	local mine = lplr:GetAttribute('Team')
	return team ~= nil and mine ~= nil and team == tostring(mine)
end

run(function()
	local ChestSteal
	local Range
	local Open
	local Skywars
	local DelayToggle
	local DelaySlider
	local TeamFilter
	local Delays = setmetatable({}, {__mode = 'k'})
	
	local function isTeamChest(chest)
		store.getChestTeam(chest)
		if not TeamFilter.Enabled then return false end
		return store.isMyTeamChest(chest)
	end
	
	local function lootChest(chest)
		chest = chest and chest.Value or nil
		if not chest then return end
		
		local chestitems = chest and chest:GetChildren() or {}
		if #chestitems > 1 and (Delays[chest] or 0) < tick() then
			Delays[chest] = tick() + (DelayToggle.Enabled and DelaySlider.Value or 0.2)
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(chest)
	
			for _, v in chestitems do
				if v:IsA('Accessory') then
					if DelayToggle.Enabled then
						task.wait(DelaySlider.Value / #chestitems) 
					end
					
					task.spawn(function()
						pcall(function()
							bedwars.Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(chest, v)
						end)
					end)
				end
			end
	
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(nil)
		end
	end
	
	local chestRun = 0
	ChestSteal = vape.Categories.World:CreateModule({
		Name = 'ChestSteal',
		Function = function(callback)
			chestRun += 1
			local myRun = chestRun
			if callback then
				local chests = collection('chest', ChestSteal)
				repeat task.wait() until store.queueType ~= 'bedwars_test' or not ChestSteal.Enabled or myRun ~= chestRun
				if not ChestSteal.Enabled or myRun ~= chestRun then return end
				if (not Skywars.Enabled) or store.queueType:find('skywars') then
					repeat
						if entitylib.isAlive and store.matchState ~= 2 then
							if Open.Enabled then
								if bedwars.AppController:isAppOpen('ChestApp') then
									lootChest(lplr.Character:FindFirstChild('ObservedChestFolder'))
								end
							else
								local localPosition = entitylib.character.RootPart.Position
								for _, v in chests do
									if (localPosition - v.Position).Magnitude <= Range.Value then
										if isTeamChest(v) then continue end
										lootChest(v:FindFirstChild('ChestFolderValue'))
									end
								end
							end
						end
						task.wait(0.1)
					until not ChestSteal.Enabled or myRun ~= chestRun
				end
			end
		end,
		Tooltip = 'takes items from near chests'
	})
	Range = ChestSteal:CreateSlider({
		Name = 'Range',
		Min = 0,
		Max = 18,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Open = ChestSteal:CreateToggle({Name = 'GUI Check'})
	Skywars = ChestSteal:CreateToggle({
		Name = 'Only Skywars',
		Function = function()
			if ChestSteal.Enabled then
				ChestSteal:Toggle()
				ChestSteal:Toggle()
			end
		end
	})
	TeamFilter = ChestSteal:CreateToggle({
		Name = 'Team Check',
		Default = false
	})
	DelayToggle = ChestSteal:CreateToggle({
		Name = 'Delay',
		Function = function(callback)
			DelaySlider.Object.Visible = callback
			if ChestSteal.Enabled then
				ChestSteal:Toggle()
				ChestSteal:Toggle()
			end
		end
	})
    DelaySlider = ChestSteal:CreateSlider({
        Name = 'Delay Time',
        Min = 0.1,
        Max = 5,
        Default = 1,
        Decimal = 10,
        Suffix = 's',
        Visible = false
    })

    task.defer(function()
        if DelaySlider and DelaySlider.Object then
            DelaySlider.Object.Visible = false  
        end
    end)
end)


run(function()
	local FPSBoost
	local Kill
	local Visualizer
	local Shadows
	local Neon
	local Potato
	local Textures

	local savedEffects = {}
	local savedUtils = {}
	local savedParts = {}
	local savedTextures = {}

	local killActive = false
	local visualizerActive = false
	local generation = 0
	local descendantConnection
	local unloading = false

	local rgb = Color3.fromRGB

	local blockColors = {
		wool_white = rgb(255, 255, 255),
		wool_red = rgb(255, 50, 50),
		wool_green = rgb(50, 255, 50),
		wool_blue = rgb(50, 100, 255),
		wool_yellow = rgb(255, 255, 50),
		wool_orange = rgb(255, 150, 50),
		wool_purple = rgb(180, 50, 255),
		wool_pink = rgb(255, 100, 200),
		wool_black = rgb(50, 50, 50),
		wool_cyan = rgb(50, 255, 255),
		wool_magenta = rgb(255, 50, 150),
		wool_lime = rgb(150, 255, 50),
		wool_brown = rgb(150, 75, 0),
		wool_light_blue = rgb(100, 200, 255),
		wool_gray = rgb(150, 150, 150),
		wool_builder = rgb(200, 200, 200),
		wool_shear = rgb(200, 200, 200),
		wool = rgb(200, 200, 200),
		clay_white = rgb(255, 255, 255),
		clay_black = rgb(50, 50, 50),
		clay_blue = rgb(50, 100, 255),
		clay_dark_brown = rgb(100, 60, 30),
		clay_dark_green = rgb(30, 100, 30),
		clay_gray = rgb(150, 150, 150),
		clay_green = rgb(50, 255, 50),
		clay_light_brown = rgb(200, 170, 120),
		clay_light_green = rgb(150, 255, 150),
		clay_orange = rgb(255, 150, 50),
		clay_pink = rgb(255, 100, 200),
		clay_purple = rgb(180, 50, 255),
		clay_red = rgb(255, 50, 50),
		clay_tan = rgb(210, 180, 140),
		clay_yellow = rgb(255, 255, 50),
		clay = rgb(220, 180, 140),
		wood_plank_spruce = rgb(222, 184, 135),
		wood_plank_birch = rgb(230, 220, 190),
		wood_plank_maple = rgb(200, 140, 90),
		wood_plank_oak = rgb(180, 140, 100),
		wood_plank_oak_builder = rgb(180, 140, 100),
		oak_log = rgb(120, 90, 60),
		birch_log = rgb(220, 210, 180),
		spruce_log = rgb(100, 75, 50),
		hickory_log = rgb(140, 100, 60),
		wood = rgb(180, 140, 100),
		stone = rgb(150, 150, 150),
		stone_brick = rgb(140, 140, 140),
		stone_brick_builder = rgb(140, 140, 140),
		stone_slab = rgb(160, 160, 160),
		stone_pillar = rgb(160, 160, 160),
		stone_tiles = rgb(160, 160, 160),
		stone_player_block = rgb(150, 150, 150),
		andesite = rgb(150, 150, 150),
		andesite_polished = rgb(160, 160, 160),
		diorite = rgb(220, 220, 220),
		diorite_polished = rgb(230, 230, 230),
		granite = rgb(180, 100, 80),
		granite_polished = rgb(190, 110, 90),
		cobblestone = rgb(150, 150, 150),
		limestone = rgb(210, 200, 180),
		marble = rgb(235, 235, 235),
		marble_pillar = rgb(235, 235, 235),
		slate_brick = rgb(90, 95, 100),
		slate_tiles = rgb(90, 95, 100),
		volatile_stone = rgb(150, 150, 150),
		obsidian = rgb(50, 30, 80),
		bedrock = rgb(80, 80, 80),
		tnt = rgb(255, 50, 50),
		sandstone = rgb(220, 200, 150),
		sandstone_polished = rgb(225, 205, 155),
		sandstone_smooth = rgb(225, 205, 155),
		red_sandstone = rgb(190, 110, 60),
		red_sandstone_polished = rgb(195, 115, 65),
		red_sandstone_smooth = rgb(195, 115, 65),
		sand = rgb(220, 200, 150),
		red_sand = rgb(190, 110, 60),
		glass = rgb(200, 230, 230),
		magic_glass = rgb(150, 200, 255),
		diamond = rgb(100, 220, 220),
		diamond_block = rgb(100, 220, 220),
		diamond_ore = rgb(100, 220, 220),
		emerald = rgb(50, 255, 50),
		emerald_block = rgb(50, 255, 50),
		emerald_ore = rgb(50, 255, 50),
		iron = rgb(220, 220, 220),
		iron_block = rgb(220, 220, 220),
		iron_ore = rgb(200, 200, 200),
		iron_ore_mesh_block = rgb(200, 200, 200),
		gold = rgb(255, 215, 0),
		gold_block = rgb(255, 215, 0),
		copper_block = rgb(184, 115, 51),
		steel_block = rgb(170, 170, 180),
		galactite = rgb(100, 80, 160),
		galactite_brick = rgb(100, 80, 160),
		crystal_ore = rgb(180, 150, 255),
		guilded_iron = rgb(230, 200, 100),
		ceramic = rgb(230, 140, 60),
		aquamarine_lantern = rgb(80, 220, 200),
		barrel = rgb(140, 95, 55),
		bookshelf = rgb(150, 100, 60),
		brick = rgb(160, 80, 60),
		grass = rgb(50, 255, 50),
		moss_block = rgb(50, 150, 50),
		dirt = rgb(120, 80, 50),
		void_dirt = rgb(60, 40, 25),
		void_grass = rgb(25, 80, 25),
		ice = rgb(180, 220, 255),
		snow = rgb(255, 255, 255),
		snow_pile = rgb(255, 255, 255),
		glowstone = rgb(255, 240, 150),
		magma_block = rgb(200, 80, 30),
		slime_block = rgb(120, 230, 120),
		gum_block = rgb(255, 150, 200),
		invisible_block = rgb(255, 255, 255),
		void_block = rgb(20, 20, 20),
		smoke_block = rgb(130, 130, 130),
		cotton_candy_block = rgb(255, 200, 230),
		cotton_candy_block_blue = rgb(150, 200, 255),
		cotton_candy_block_orange = rgb(255, 180, 120),
		cotton_candy_block_pink = rgb(255, 150, 200),
		cotton_candy_block_yellow = rgb(255, 240, 150),
		blue_tile = rgb(50, 100, 255),
		concrete_green = rgb(50, 180, 50),
		concrete = rgb(180, 180, 180),
		bed = rgb(200, 50, 50),
		og_bed = rgb(200, 50, 50),
		royale_bed = rgb(200, 50, 50),
		fake_bed = rgb(200, 50, 50),
		barrier = rgb(255, 0, 0),
		ladder = rgb(150, 100, 50),
		vine_ladder = rgb(60, 120, 60),
		scaffold = rgb(180, 140, 100),
		christmas_scaffold = rgb(180, 140, 100),
		drawbridge = rgb(150, 110, 70),
		christmas_drawbridge = rgb(150, 110, 70),
		haybale = rgb(230, 200, 100),
		purple_hay_bale = rgb(180, 50, 255)
	}

	local colorCache = {}
	local blockTerms = {
		'wool', 'clay', 'wood', 'log', 'stone', 'brick',
		'glass', 'plank', 'bed', 'obsidian', 'sand',
		'tnt', 'barrier', 'magic', 'concrete',
		'diamond', 'emerald', 'iron', 'gold',
		'copper', 'steel', 'ore', 'marble', 'slate',
		'granite', 'andesite', 'diorite',
		'grass', 'dirt', 'ice', 'snow', 'moss',
		'slime', 'scaffold', 'ladder', 'tile',
		'cotton_candy', '_block'
	}

	local function getBlockColor(name)
		local cached = colorCache[name]
		if cached then return cached end

		local lower = name:lower()
		local result = blockColors[lower]

		if not result then
			for key, value in blockColors do
				if lower:find(key, 1, true) then
					result = value
					break
				end
			end
		end

		result = result or rgb(150, 150, 150)
		colorCache[name] = result

		return result
	end

	local function isTargetBlock(part)
		if not part:IsA('BasePart') then return false end

		if blockColors[part.Name:lower()] then
			return true
		end

		if part:IsA('Seat') then
			return true
		end

		local name = part.Name:lower()

		for _, term in blockTerms do
			if name:find(term, 1, true) then
				return true
			end
		end

		return false
	end

	local function mapRoot()
		return store.map or workspace:FindFirstChild('Map')
	end

	local function inMap(object, parent)
		local map = mapRoot()
		if not map then return false end

		local target = parent or object
		return target ~= nil and (target == map or target:IsDescendantOf(map))
	end

	local function savePart(part)
		local saved = savedParts[part]
		if saved then return saved end

		saved = {
			Material = part.Material,
			Color = part.Color,
			Reflectance = part.Reflectance,
			CastShadow = part.CastShadow,
			TextureID = part:IsA('MeshPart') and part.TextureID or nil
		}

		savedParts[part] = saved
		return saved
	end

	local function applyPart(part)
		if not part:IsA('BasePart') or not part.Parent then return end

		local enabled = FPSBoost.Enabled and not unloading
		local shadow = enabled and Shadows.Enabled
		local potato = enabled and Potato.Enabled and isTargetBlock(part)
		local textures = enabled and Textures.Enabled and inMap(part)
		local existing = savedParts[part]
		local neon = enabled and Neon.Enabled and (
			existing and existing.Material == Enum.Material.Neon or part.Material == Enum.Material.Neon
		)

		local needed = shadow or potato or neon or (textures and part:IsA('MeshPart'))

		if not needed and not existing then return end

		local saved = existing or savePart(part)

		pcall(function()
			part.Material = saved.Material
			part.Color = saved.Color
			part.Reflectance = saved.Reflectance
			part.CastShadow = saved.CastShadow

			if part:IsA('MeshPart') and saved.TextureID ~= nil then
				part.TextureID = saved.TextureID
			end

			if neon then
				part.Material = Enum.Material.Plastic
				part.Reflectance = 0
			end

			if potato then
				part.Material = Enum.Material.SmoothPlastic
				part.Color = getBlockColor(part.Name)
			end

			if shadow then
				part.CastShadow = false
			end

			if part:IsA('MeshPart') and (textures or potato) then
				part.TextureID = ''
			end
		end)

		if not needed then
			savedParts[part] = nil
		end
	end

	local function isTextureObject(object)
		return object:IsA('Decal')
			or object:IsA('Texture')
			or object:IsA('SpecialMesh')
			or object:IsA('SurfaceAppearance')
	end

	local function applyTexture(object)
		if not isTextureObject(object) then return end

		local saved = savedTextures[object]
		local parent = saved and saved.Parent or object.Parent

		if not parent then return end

		local enabled = FPSBoost.Enabled and not unloading
		local hide = false

		if enabled then
			if Textures.Enabled and inMap(object, parent) then
				hide = true
			elseif Potato.Enabled and parent:IsA('BasePart') and isTargetBlock(parent) then
				hide = true
			end
		end

		if not hide and not saved then return end

		if not saved then
			saved = {Parent = parent}

			if object:IsA('Decal') or object:IsA('Texture') then
				saved.Transparency = object.Transparency
			elseif object:IsA('SpecialMesh') then
				saved.TextureId = object.TextureId
			end

			savedTextures[object] = saved
		end

		pcall(function()
			if hide then
				if object:IsA('Decal') or object:IsA('Texture') then
					object.Transparency = 1
				elseif object:IsA('SpecialMesh') then
					object.TextureId = ''
				elseif object:IsA('SurfaceAppearance') then
					object.Parent = nil
				end
			else
				if object:IsA('Decal') or object:IsA('Texture') then
					object.Transparency = saved.Transparency
				elseif object:IsA('SpecialMesh') then
					object.TextureId = saved.TextureId
				elseif object:IsA('SurfaceAppearance') then
					object.Parent = saved.Parent
				end
			end
		end)

		if not hide then
			savedTextures[object] = nil
		end
	end

	local function processObject(object)
		if object:IsA('BasePart') then
			applyPart(object)
		elseif isTextureObject(object) then
			applyTexture(object)
		end
	end

	local function updateKillEffects()
		local enabled = FPSBoost.Enabled and Kill.Enabled and not unloading

		if enabled == killActive then return end
		killActive = enabled

		local controller = bedwars.KillEffectController
		local registry = controller and controller.killEffects
		if not registry then return end

		if enabled then
			for name, effect in registry do
				if type(name) == 'string' and not name:find('Custom', 1, true) then
					savedEffects[name] = effect
					registry[name] = {
						new = function()
							return {
								onKill = function() end,
								isPlayDefaultKillEffect = function()
									return true
								end
							}
						end
					}
				end
			end
		else
			for name, effect in savedEffects do
				registry[name] = effect
			end
			table.clear(savedEffects)
		end
	end

	local function updateVisualizer()
		local enabled = FPSBoost.Enabled and Visualizer.Enabled and not unloading

		if enabled == visualizerActive then return end
		visualizerActive = enabled

		local registry = bedwars.VisualizerUtils
		if not registry then return end

		if enabled then
			local keep = {
				'beam', 'projectile', 'draw',
				'line', 'ray', 'arc'
			}

			for name, method in registry do
				if type(method) == 'function' then
					local lower = tostring(name):lower()
					local preserve = false

					for _, word in keep do
						if lower:find(word, 1, true) then
							preserve = true
							break
						end
					end

					if not preserve then
						savedUtils[name] = method
						registry[name] = function() end
					end
				end
			end
		else
			for name, method in savedUtils do
				registry[name] = method
			end
			table.clear(savedUtils)
		end
	end

	local function stopScan()
		generation += 1

		if descendantConnection then
			descendantConnection:Disconnect()
			descendantConnection = nil
		end

		return generation
	end

	local function refresh()
		if not FPSBoost or not Kill or not Visualizer or not Shadows or not Neon or not Potato or not Textures then
			return
		end

		updateKillEffects()
		updateVisualizer()

		local current = stopScan()

		local active = FPSBoost.Enabled and (
			Shadows.Enabled
			or Neon.Enabled
			or Potato.Enabled
			or Textures.Enabled
		)

		if active then
			descendantConnection = workspace.DescendantAdded:Connect(function(object)
				if generation == current and not unloading then
					processObject(object)
				end
			end)
		end

		task.spawn(function()
			local processed = 0

			for part in savedParts do
				if generation ~= current then return end
				if part.Parent then
					applyPart(part)
				else
					savedParts[part] = nil
				end

				processed += 1
				if processed % 250 == 0 then
					task.wait()
				end
			end

			for object in savedTextures do
				if generation ~= current then return end
				applyTexture(object)

				processed += 1
				if processed % 250 == 0 then
					task.wait()
				end
			end

			if not active then return end

			local stack = {workspace}

			while #stack > 0 do
				if generation ~= current or unloading then return end

				local node = stack[#stack]
				stack[#stack] = nil

				local children = node:GetChildren()

				for _, child in children do
					if generation ~= current or unloading then return end

					processObject(child)
					stack[#stack + 1] = child

					processed += 1
					if processed % 300 == 0 then
						task.wait()
					end
				end
			end
		end)
	end

	local function cleanup()
		unloading = true
		stopScan()

		updateKillEffects()
		updateVisualizer()

		for part, saved in savedParts do
			if part.Parent then
				pcall(function()
					part.Material = saved.Material
					part.Color = saved.Color
					part.Reflectance = saved.Reflectance
					part.CastShadow = saved.CastShadow

					if part:IsA('MeshPart') and saved.TextureID ~= nil then
						part.TextureID = saved.TextureID
					end
				end)
			end
		end

		for object, saved in savedTextures do
			pcall(function()
				if object:IsA('Decal') or object:IsA('Texture') then
					object.Transparency = saved.Transparency
				elseif object:IsA('SpecialMesh') then
					object.TextureId = saved.TextureId
				elseif object:IsA('SurfaceAppearance') then
					object.Parent = saved.Parent
				end
			end)
		end

		table.clear(savedParts)
		table.clear(savedTextures)
		table.clear(colorCache)
	end

	FPSBoost = vape.Categories.World:CreateModule({
		Name = 'FPSBoost',
		Tooltip = 'improves game performance',
		Function = refresh
	})

	Kill = FPSBoost:CreateToggle({
		Name = 'Kill Effects',
		Default = true,
		Function = refresh
	})

	Visualizer = FPSBoost:CreateToggle({
		Name = 'Visualizer',
		Default = true,
		Function = refresh
	})

	Shadows = FPSBoost:CreateToggle({
		Name = 'Remove Shadows',
		Default = false,
		Function = refresh
	})

	Neon = FPSBoost:CreateToggle({
		Name = 'Remove Neon',
		Default = false,
		Function = refresh
	})

	Potato = FPSBoost:CreateToggle({
		Name = 'Potato Mode',
		Default = false,
		Function = refresh
	})

	Textures = FPSBoost:CreateToggle({
		Name = 'Remove Textures',
		Default = false,
		Function = refresh
	})

	vape:Clean(cleanup)
end)


run(function()
	local PhaseMine
	local connections = {}
	local trackedParts = {}
	local lastWeaponState = nil
	local weaponCheckCounter = 0
	
	local function removeCollision(character)
		if not character then return end
		
		local charParts = trackedParts[character]
		if not charParts then
			charParts = {}
			trackedParts[character] = charParts
			
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(charParts, {part = part, origCollide = part.CanCollide, origQuery = part.CanQuery})
					part.CanCollide = false
					part.CanQuery = false
				end
			end
		else
			for _, entry in charParts do
				if entry.part and entry.part.Parent then
					entry.part.CanCollide = false
					entry.part.CanQuery = false
				end
			end
		end
	end
	
	local function restoreCollision(character)
		if not character then return end
		
		local charParts = trackedParts[character]
		if charParts then
			for _, entry in charParts do
				if entry.part and entry.part.Parent then
					entry.part.CanCollide = entry.origCollide
					entry.part.CanQuery = entry.origQuery
				end
			end
		end
	end

	local function updateAllCollisions(forceUpdate)
		weaponCheckCounter = weaponCheckCounter + 1
		local shouldCheck = forceUpdate or (weaponCheckCounter % 3 == 0)
		
		if not shouldCheck then return end
		
		local isWeaponEquipped = hasValidWeapon()
		
		if not forceUpdate and lastWeaponState == isWeaponEquipped then
			return
		end
		
		lastWeaponState = isWeaponEquipped
		
		for _, entity in entitylib.List do
			if entity.Character and entity.Character.Parent then
				if isWeaponEquipped then
					restoreCollision(entity.Character)
				else
					removeCollision(entity.Character)
				end
			end
		end
	end
	
	local motorParts = {}
	local function updateMotorParts()
		for _, entity in entitylib.List do
			if entity.Character then
				local charMotors = motorParts[entity.Character]
				
				if not charMotors then
					charMotors = {}
					motorParts[entity.Character] = charMotors
					
					for _, part in entity.Character:GetChildren() do
						if part:IsA("BasePart") and part.Name == "Part" and part:FindFirstChildOfClass("Motor6D") then
							table.insert(charMotors, part)
						end
					end
				end
				
				for _, part in charMotors do
					if part and part.Parent then
						part.CanCollide = false
					end
				end
			end
		end
	end
	
	local tracked = {}
	local descConnections = {}

	PhaseMine = vape.Categories.World:CreateModule({
		Name = 'PhaseMine',
		Function = function(callback)
			if callback then

				local function ignorePart(part)
					pcall(function()
						bedwars.QueryUtil:setQueryIgnored(part, true)
					end)
				end

				local function onPartAdded(char, part)
					if not PhaseMine.Enabled or not char or char == lplr.Character then return end
					if not part:IsA('BasePart') then return end
					local list = tracked[char]
					if not list then
						list = {}
						tracked[char] = list
					end
					if not list[part] then
						list[part] = true
						ignorePart(part)
					end
				end

				local function applyToChar(char)
					if not char or char == lplr.Character then return end
					for _, part in char:GetDescendants() do
						onPartAdded(char, part)
					end
				end

				local function setupCharacter(char)
					if not char then return end
					if char == lplr.Character then return end
					if descConnections[char] then
						descConnections[char]:Disconnect()
						descConnections[char] = nil
					end
					applyToChar(char)
					local conn = char.DescendantAdded:Connect(function(part)
						onPartAdded(char, part)
					end)
					descConnections[char] = conn
				end

				local function cleanupCharacter(char)
					if descConnections[char] then
						descConnections[char]:Disconnect()
						descConnections[char] = nil
					end
					tracked[char] = nil
				end

				local function applyToAll(remove)
					for _, entity in ipairs(entitylib.List) do
						if entity.Character then
							applyToChar(entity.Character, remove)
						end
					end
					for _, obj in ipairs(workspace:GetChildren()) do
						if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
							if obj ~= lplr.Character then
								applyToChar(obj, remove)
							end
						end
					end
				end

				local function updateCollision()
					if not PhaseMine.Enabled then return end
					applyToAll()
				end

				local function setupAllCharacters()
					for _, entity in ipairs(entitylib.List) do
						if entity.Character then
							setupCharacter(entity.Character)
						end
					end
					for _, obj in ipairs(workspace:GetChildren()) do
						if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
							if obj ~= lplr.Character then
								setupCharacter(obj)
							end
						end
					end
				end

				task.wait(0.2)
				if not PhaseMine.Enabled then return end

				setupAllCharacters()
				updateCollision()
				updateAllCollisions(true)

				table.insert(connections, runService.Heartbeat:Connect(function()
					if PhaseMine.Enabled then
						updateAllCollisions(false)
					end
				end))

				local entityAdded = entitylib.Events.EntityAdded:Connect(function(entity)
					if entity.Character then
						task.wait(0.1)
						if not PhaseMine.Enabled then return end
						setupCharacter(entity.Character)
						updateAllCollisions(true)
					end
				end)
				table.insert(connections, entityAdded)

				local workspaceChildAdded = workspace.ChildAdded:Connect(function(obj)
					if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
						if obj ~= lplr.Character then
							task.wait(0.1)
							setupCharacter(obj)
						end
					end
				end)
				table.insert(connections, workspaceChildAdded)

				local entityRemoved = entitylib.Events.EntityRemoved:Connect(function(entity)
					if entity.Character then
						cleanupCharacter(entity.Character)
					end
				end)
				table.insert(connections, entityRemoved)

				local workspaceChildRemoved = workspace.ChildRemoved:Connect(function(obj)
					if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
						if obj ~= lplr.Character then
							cleanupCharacter(obj)
						end
					end
				end)
				table.insert(connections, workspaceChildRemoved)

				local localAdded = lplr.CharacterAdded:Connect(function(char)
					if PhaseMine.Enabled then
						if lplr.Character and lplr.Character ~= char then
							cleanupCharacter(lplr.Character)
						end
						task.wait(0.2)
						updateCollision()
						setupAllCharacters()
					end
				end)
				table.insert(connections, localAdded)

			else
				for _, conn in ipairs(connections) do
					conn:Disconnect()
				end
				table.clear(connections)

				for char, conn in pairs(descConnections) do
					conn:Disconnect()
				end
				table.clear(descConnections)

				for char, list in pairs(tracked) do
					for part in pairs(list) do
						if part.Parent then
							pcall(function()
								bedwars.QueryUtil:setQueryIgnored(part, false)
							end)
						end
					end
				end
				table.clear(tracked)

				for character in trackedParts do
					restoreCollision(character)
				end

				table.clear(trackedParts)
				table.clear(motorParts)
				lastWeaponState = nil
				weaponCheckCounter = 0
			end
		end,
		Tooltip = 'mine or build through players and npcs'
	})
end)


run(function()
	local AntiEffects
	local AntiDizzy
	local AntiSleep
	local AntiTrap
	local AntiFear
	local AntiMagna
	local originalPickup
	local originalAdd
	local sleepModifier
	local heartbeat
	local magmaConnection
	local magmaScan
	local magmaParts = {}
	local dizzyActive = false
	local fearActive = false
	local magmaActive = false
	local elapsed = 0

	local function setDizzy(enabled)
		if dizzyActive == enabled then return end
		dizzyActive = enabled

		local controller = bedwars.ForestEnvironmentCollectibleEntityController
		if not controller then return end

		if enabled then
			if not originalPickup then
				originalPickup = controller.canPickupEntity
			end

			if not originalPickup then return end

			controller.canPickupEntity = function(...)
				local count = select('#', ...)
				local mushroom = select(count, ...)

				if typeof(mushroom) == 'Instance' then
					local kind = mushroom:GetAttribute('MushroomType')

					if kind == 'Dizzy' then
						return false
					end

					if kind then
						return true
					end
				end

				return originalPickup(...)
			end

			runService:BindToRenderStep('antieffects_dizzy', Enum.RenderPriority.Character.Value + 2, function()
				runService:UnbindFromRenderStep('dizzy-status')
			end)
		else
			if originalPickup then
				controller.canPickupEntity = originalPickup
				originalPickup = nil
			end

			runService:UnbindFromRenderStep('antieffects_dizzy')
		end
	end

	local function restoreSleep()
		if sleepModifier and originalAdd then
			sleepModifier.addModifier = originalAdd
		end

		sleepModifier = nil
		originalAdd = nil
	end

	local function updateSleep()
		if not AntiEffects.Enabled or not AntiSleep.Enabled then
			restoreSleep()
			return
		end

		local controller = bedwars.SprintController
		if not controller then return end

		local modifier = controller:getMovementStatusModifier()
		if not modifier then return end

		if modifier ~= sleepModifier then
			restoreSleep()

			sleepModifier = modifier
			originalAdd = modifier.addModifier

			if type(originalAdd) == 'function' then
				local savedAdd = originalAdd
				modifier.addModifier = function(self, data)
					if data and type(data.moveSpeedMultiplier) == 'number' and data.moveSpeedMultiplier <= 0 then
						local updated = table.clone(data)
						updated.moveSpeedMultiplier = 1
						return savedAdd(self, updated)
					end

					return savedAdd(self, data)
				end
			end
		end

		local character = lplr.Character
		if not character then return end

		local stunned = character:GetAttribute('StunnedUntilTime')

		if type(stunned) == 'number' and stunned > workspace:GetServerTimeNow() then
			character:SetAttribute('StunnedUntilTime', -1)
		end

		if type(modifier.modifiers) == 'table' then
			for entry in modifier.modifiers do
				if type(entry) == 'table' and type(entry.moveSpeedMultiplier) == 'number' and entry.moveSpeedMultiplier <= 0 then
					modifier:removeModifier(entry)
				end
			end
		end

		local humanoid = character:FindFirstChildOfClass('Humanoid')
		if humanoid then
			if humanoid.JumpPower == 0 then
				humanoid.JumpPower = 50
			end

			if humanoid.JumpHeight == 0 then
				humanoid.JumpHeight = 7.2
			end
		end
	end

	local function updateTrap()
		if not AntiEffects.Enabled or not AntiTrap.Enabled then return end

		local character = lplr.Character
		if not character then return end

		if character:GetAttribute('SnapTrapMarked') then
			character:SetAttribute('SnapTrapMarked', nil)
		end

		local humanoid = character:FindFirstChildOfClass('Humanoid')
		if not humanoid then return end

		if humanoid.JumpPower == 0 then
			humanoid.JumpPower = 50
		end

		if humanoid.JumpHeight == 0 then
			humanoid.JumpHeight = 7.2
		end

		if humanoid.WalkSpeed < 10 then
			humanoid.WalkSpeed = 16
		end
	end

	local function setFear(enabled)
		if fearActive == enabled then return end
		fearActive = enabled

		if enabled then
			runService:UnbindFromRenderStep('werewolf-fear-status')

			runService:BindToRenderStep('antieffects_fear', Enum.RenderPriority.Character.Value + 2, function()
				runService:UnbindFromRenderStep('werewolf-fear-status')
			end)
		else
			runService:UnbindFromRenderStep('antieffects_fear')
		end
	end

	local function processMagma(object)
		if not magmaActive then return end

		local part = object:IsA('BasePart') and object or object.Parent

		if not part or not part:IsA('BasePart') then return end
		if not part.Name:lower():find('magma', 1, true) then return end

		if magmaParts[part] == nil then
			magmaParts[part] = part.CanTouch
		end

		part.CanTouch = false

		for _, descendant in part:GetDescendants() do
			if descendant:IsA('TouchTransmitter') then
				pcall(function()
					descendant:Destroy()
				end)
			end
		end
	end

	local function setMagna(enabled)
		if magmaActive == enabled then return end
		magmaActive = enabled

		if enabled then
			magmaScan = scanDescendants(workspace, processMagma)

			magmaConnection = workspace.DescendantAdded:Connect(function(object)
				if magmaActive then
					processMagma(object)
				end
			end)
		else
			if magmaScan then
				magmaScan.cancelled = true
				magmaScan = nil
			end

			if magmaConnection then
				magmaConnection:Disconnect()
				magmaConnection = nil
			end

			for part, value in magmaParts do
				if part.Parent then
					part.CanTouch = value
				end
			end

			table.clear(magmaParts)
		end
	end

	local function refresh()
		if not AntiEffects then return end

		local enabled = AntiEffects.Enabled

		setDizzy(enabled and AntiDizzy and AntiDizzy.Enabled or false)
		setFear(enabled and AntiFear and AntiFear.Enabled or false)
		setMagna(enabled and AntiMagna and AntiMagna.Enabled or false)

		if enabled then
			if not heartbeat then
				heartbeat = runService.Heartbeat:Connect(function(dt)
					elapsed += dt
					if elapsed < 0.1 then return end
					elapsed = 0

					if AntiSleep.Enabled then
						updateSleep()
					end

					if AntiTrap.Enabled then
						updateTrap()
					end
				end)
			end

			if AntiSleep and AntiSleep.Enabled then
				updateSleep()
			else
				restoreSleep()
			end
		else
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end

			restoreSleep()
			elapsed = 0
		end
	end

	AntiEffects = vape.Categories.World:CreateModule({
		Name = 'AntiEffects',
		Tooltip = 'blocks negative effects',
		Function = refresh
	})

	AntiDizzy = AntiEffects:CreateToggle({
		Name = 'Dizzy',
		Default = true,
		Tooltip = 'blocks dizzy mushrooms n toads',
		Function = refresh
	})

	AntiSleep = AntiEffects:CreateToggle({
		Name = 'Sleep',
		Default = true,
		Tooltip = 'blocks sleep effects',
		Function = refresh
	})

	AntiTrap = AntiEffects:CreateToggle({
		Name = 'Trap',
		Default = true,
		Tooltip = 'helps u move when trapped',
		Function = refresh
	})

	AntiFear = AntiEffects:CreateToggle({
		Name = 'Fear',
		Default = true,
		Tooltip = 'blocks werewolf fear movement',
		Function = refresh
	})

	AntiMagna = AntiEffects:CreateToggle({
		Name = 'AntiMagna',
		Default = true,
		Tooltip = 'blocks magma touches so u dont die cuh',
		Function = refresh
	})

	vape:Clean(function()
		setDizzy(false)
		setFear(false)
		setMagna(false)

		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end

		restoreSleep()
	end)
end)

run(function()
	local AutoBank
	local UIToggle
	local GUICheck
	local UI
	local Chests
	local Items = {}
	local BankToggles = {
		iron = nil,
		diamond = nil,
		emerald = nil
	}
	local cachedChest
	local lastChestCheck = 0
	local function getPersonalChest()
		local gui = lplr:FindFirstChildOfClass('PlayerGui')
		local priv = gui and gui:FindFirstChild('PrivateInventory')
		local folder = priv and priv:FindFirstChild(lplr.Name .. '_personal')
		if folder then return folder end
		local inv = replicatedStorage:FindFirstChild('Inventories')
		return inv and inv:FindFirstChild(lplr.Name .. '_personal')
	end
	local lastHotbarUpdate = 0
	local Spectators
	local TeamCheck
	local BankOnLeave
	local lastBaseDist
	local baseChestCache, baseChestCheck = nil, 0

	local function getSpectator()
		local myTeam = lplr:GetAttribute('Team')
		for _, plr in playersService:GetPlayers() do
			if plr ~= lplr and (plr:GetAttribute('Spectator') or (plr.Team and plr.Team.Name == 'Spectators')) then
				if not myTeam or plr:GetAttribute('Team') ~= myTeam then
					return plr
				end
			end
		end
		return nil
	end

	local function getBaseChest()
		if baseChestCache and baseChestCache.Parent and tick() - baseChestCheck < 2 then
			return baseChestCache
		end
		baseChestCheck = tick()
		baseChestCache = nil
		local root = entitylib.isAlive and entitylib.character.RootPart
		local best, bestDist
		local myTeam = lplr:GetAttribute('Team')
		for _, chest in pairs(Chests or {}) do
			local personal = chest.Parent and (chest.Name == 'personal_chest' or chest.Name == 'og_personal_chest')
			local team = personal and store.getChestTeam(chest)
			if personal and (team == nil or myTeam == nil or team == tostring(myTeam)) then
				local dist = root and (chest.Position - root.Position).Magnitude or 0
				if not bestDist or dist < bestDist then
					best, bestDist = chest, dist
				end
			end
		end
		baseChestCache = best
		return best
	end

	local lastWithdraw = 0
	local function getOwnShop()
		local root = entitylib.isAlive and entitylib.character.RootPart
		if not root then return nil end
		local myTeam = lplr:GetAttribute('Team')
		local best, bestDist
		for _, v in store.shop do
			local keeper = v.RootPart
			if keeper and keeper.Parent and (v.Shop or v.Upgrades) then
				local team = keeper:GetAttribute('TeamId') or store.getChestTeam(keeper)
				if team == nil or myTeam == nil or tostring(team) == tostring(myTeam) then
					local pos = keeper:IsA('BasePart') and keeper.Position or keeper:GetPivot().Position
					local dist = (pos - root.Position).Magnitude
					if not bestDist or dist < bestDist then
						best, bestDist = pos, dist
					end
				end
			end
		end
		return best
	end

	local bankSeq = 0
	local preconditionFn
	local function getPreconditionFn()
		if preconditionFn == nil then
			preconditionFn = false
			pcall(function()
				preconditionFn = require(replicatedStorage.TS.inventory['inventory-slot-preconditions']).getInventorySlotPreconditions
			end)
		end
		return preconditionFn or nil
	end

	local function getSnapshot(folder)
		local ok, success, snap = pcall(function()
			return bedwars.Client:GetNamespace('Inventory'):Get('GetSlotState'):CallServerAsync(folder):timeout(2):await()
		end)
		if ok and success and type(snap) == 'table' then
			return snap
		end
		return nil
	end

	local draggingController

	local function getDraggingController()
		if draggingController and type(draggingController.sendTransaction) == 'function' then
			return draggingController
		end

		local ok, controller = pcall(function()
			local framework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
			return framework.resolveDependency('client/controllers/global/inventory/inventory-dragging-controller@InventoryDraggingController')
		end)

		if ok and controller and type(controller.sendTransaction) == 'function' then
			draggingController = controller
		end

		return draggingController
	end

	local function transact(folder, snapshot, request)
		if not folder or not snapshot then return false end

		local controller = getDraggingController()
		if controller then
			local previousChest = controller.openedChest
			local changedChest = previousChest ~= folder

			if changedChest then
				local opened = pcall(controller.setOpenedChest, controller, folder)
				if not opened then return false, nil end
			end

			local ok, fulfilled, accepted = pcall(function()
				return controller:sendTransaction(request, folder):timeout(2):await()
			end)

			if changedChest then
				pcall(controller.setOpenedChest, controller, previousChest)
			end

			local state = getSnapshot(folder)
			if ok and fulfilled and accepted == true then
				return true, state
			end

			return false, state
		end

		bankSeq += 1
		local transaction = {}
		for k, v in request do transaction[k] = v end

		transaction.chestFolder = folder
		transaction.expectedPlayerRevision = snapshot.player and snapshot.player.revision
		transaction.expectedChestRevision = snapshot.chest and snapshot.chest.revision
		transaction.seq = bankSeq

		local precon = getPreconditionFn()
		if precon then
			local ok, state = pcall(precon, request, snapshot)
			if ok then transaction.expectedState = state end
		end

		local ok, fulfilled, result = pcall(function()
			return bedwars.Client:GetNamespace('Inventory'):Get('TransactSlots'):CallServerAsync(transaction):timeout(2):await()
		end)

		if ok and fulfilled and type(result) == 'table' then
			return result.ok == true, result.state
		end

		return false, nil
	end

	local function findSlot(snapshot, container, itemType)
		if not snapshot then return nil end
		local side = container == 'chest' and snapshot.chest or snapshot.player
		local slots = side and side.slots
		if not slots then return nil end
		for _, slot in slots do
			if slot.container == container and (not itemType or slot.itemType == itemType) then
				return slot
			end
		end
		return nil
	end

	local function withdrawBank()
		if not cachedChest or tick() - lastWithdraw < 0.5 then return end
		lastWithdraw = tick()
		pcall(function()
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(cachedChest)
		end)
		local snapshot = getSnapshot(cachedChest)
		for itemType, toggle in BankToggles do
			if toggle and toggle.Enabled then
				if not snapshot then snapshot = getSnapshot(cachedChest) end
				local slot = snapshot and findSlot(snapshot, 'chest', itemType)
				if slot then
					local ok, newState = transact(cachedChest, snapshot, {
						operation = 'quick_move',
						slot = {index = slot.index, container = 'chest'}
					})
					snapshot = (ok and newState) or nil
				end
			end
		end
	end

	local function addItem(itemType, shop)
		local item = Instance.new('ImageLabel')
		item.Image = bedwars.getIcon({itemType = itemType}, true)
		item.Size = UDim2.fromOffset(32, 32)
		item.Name = itemType
		item.BackgroundTransparency = 1
		item.LayoutOrder = #UI:GetChildren()
		item.Parent = UI
		local itemtext = Instance.new('TextLabel')
		itemtext.Name = 'Amount'
		itemtext.Size = UDim2.fromScale(1, 1)
		itemtext.BackgroundTransparency = 1
		itemtext.Text = ''
		itemtext.TextColor3 = Color3.new(1, 1, 1)
		itemtext.TextSize = 16
		itemtext.TextStrokeTransparency = 0.3
		itemtext.Font = Enum.Font.Arial
		itemtext.Parent = item
		Items[itemType] = {Object = itemtext, Type = shop}
	end

	local function refreshBank(echest)
		for i, v in pairs(Items) do
			local item = echest:FindFirstChild(i)
			v.Object.Text = item and item:GetAttribute('Amount') or ''
		end
	end

	local function nearChest(teamOnly)
		if not entitylib.isAlive then return false end

		local pos = entitylib.character.RootPart.Position
		local maxDistanceSq = 22 * 22

		for _, chest in pairs(Chests) do
			if chest.Parent then
				store.getChestTeam(chest)
				local offset = chest.Position - pos
				local distanceSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
				if distanceSq < maxDistanceSq and (not teamOnly or store.isMyTeamChest(chest)) then
					return true
				end
			end
		end

		return false
	end

	local lastDeposit = 0

	local function handleState()
		local now = tick()
		if now - lastDeposit < 0.4 then return end

		if not cachedChest or not cachedChest.Parent or now - lastChestCheck > 1 then
			cachedChest = getPersonalChest()
			lastChestCheck = now
		end

		local chest = cachedChest
		if not chest then return end
		if not nearChest(TeamCheck and TeamCheck.Enabled) and not GUICheck.Enabled then
			return
		end

		lastDeposit = now

		pcall(function()
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(chest)
		end)

		local snapshot = getSnapshot(chest)
		if not snapshot or not snapshot.player then return end

		local moved = false

		for itemType, toggle in BankToggles do
			if toggle and toggle.Enabled then
				local slot = findSlot(snapshot, 'hotbar', itemType)
					or findSlot(snapshot, 'inventory', itemType)

				if slot and (tonumber(slot.amount) or 1) > 0 then
					local ok, newState = transact(chest, snapshot, {
						operation = 'quick_move',
						slot = {index = slot.index, container = slot.container}
					})

					if ok then moved = true end
					snapshot = newState or getSnapshot(chest)
					if not snapshot then break end
				end
			end
		end

		if moved and UIToggle.Enabled and UI then
			task.defer(function()
				if cachedChest == chest and chest.Parent then
					refreshBank(chest)
				end
			end)
		end
	end


	AutoBank = vape.Categories.Inventory:CreateModule({
		Name = 'AutoBank',
		Function = function(callback)
			if callback then
				Chests = collection('chest', AutoBank)
				cachedChest = nil
				lastChestCheck = 0
				lastHotbarUpdate = 0
				UI = Instance.new('Frame')
				UI.Size = UDim2.new(1, 0, 0, 44)
				UI.Position = UDim2.fromOffset(0, -256)
				UI.BackgroundTransparency = 1
				UI.Visible = UIToggle.Enabled
				UI.Parent = vape.gui
				AutoBank:Clean(UI)

				local Sort = Instance.new('UIListLayout')
				Sort.FillDirection = Enum.FillDirection.Horizontal
				Sort.HorizontalAlignment = Enum.HorizontalAlignment.Center
				Sort.SortOrder = Enum.SortOrder.LayoutOrder
				Sort.Parent = UI

				addItem('iron', true)
				addItem('diamond', false)
				addItem('emerald', true)
				addItem('serpents_touch_potion', false)
				addItem('jump_potion', false)
				addItem('mini_shield', false)

				local cachedHotbar
				local guiInset = guiService:GetGuiInset().Y

				repeat
					local currentTime = tick()

					if (currentTime - lastHotbarUpdate) > 0.5 then
						local playerGui = lplr.PlayerGui
						if playerGui then
							local hotbar = playerGui:FindFirstChild('hotbar')
							if hotbar then
								local container = hotbar['1']:FindFirstChild('HotbarHealthbarContainer')
								if container then
									cachedHotbar = container
									UI.Position = UDim2.fromOffset(0, (container.AbsolutePosition.Y + guiInset) - 40)
									lastHotbarUpdate = currentTime
								end
							end
						end
					end

					if not cachedChest or not cachedChest.Parent or (currentTime - lastChestCheck) > 1 then
						cachedChest = getPersonalChest()
						lastChestCheck = currentTime
					end
					if UIToggle.Enabled and UI and cachedChest then
						refreshBank(cachedChest)
					end

					local spectated = Spectators.Enabled and getSpectator()

					if BankOnLeave.Enabled then
						local shop = getOwnShop()
						local root = entitylib.isAlive and entitylib.character.RootPart
						if shop and root and cachedChest and not spectated then
							local offset = root.Position - shop
							local dist = offset.Magnitude
							local flat = Vector3.new(offset.X, 0, offset.Z)
							local vel = root.AssemblyLinearVelocity
							local outward = flat.Magnitude > 0.5 and Vector3.new(vel.X, 0, vel.Z):Dot(flat.Unit) or 0
							if dist <= 40 then
								if outward > 4 and dist >= 12 then
									handleState()
								elseif outward <= 1 and dist <= 30 and not entitylib.EntityPosition({Origin = shop, Range = 40, Part = 'RootPart', Players = true}) then
									withdrawBank()
								end
							end
						end
					else
						local shouldBank = false

						if GUICheck.Enabled then
							shouldBank = bedwars.AppController:isAppOpen('ChestApp') or
							             bedwars.AppController:isAppOpen('BedwarsAppIds.CHEST_INVENTORY')
						else
							shouldBank = nearChest()
						end

						if shouldBank and not spectated and (not (TeamCheck and TeamCheck.Enabled) or nearChest(true)) then
							handleState()
						end
					end

					task.wait(0.1)
				until (not AutoBank.Enabled)
			else
				table.clear(Items)
				cachedChest = nil
			end
		end,
		Tooltip = 'automatically puts resources in pchest'
	})

	UIToggle = AutoBank:CreateToggle({
		Name = 'UI',
		Function = function(callback)
			if AutoBank.Enabled and UI then
				UI.Visible = callback
			end
		end,
		Default = true
	})

	GUICheck = AutoBank:CreateToggle({
		Name = 'GUI Check',
	})

	BankToggles.iron = AutoBank:CreateToggle({
		Name = 'Bank Iron',
		Default = true
	})

	BankToggles.diamond = AutoBank:CreateToggle({
		Name = 'Bank Diamond',
		Default = true
	})

	BankToggles.emerald = AutoBank:CreateToggle({
		Name = 'Bank Emerald',
		Default = true
	})

	BankToggles.serpents_touch_potion = AutoBank:CreateToggle({
		Name = 'Bank Serpent Potion',
		Default = false
	})

	BankToggles.jump_potion = AutoBank:CreateToggle({
		Name = 'Bank Jump Potion',
		Default = false
	})

	BankToggles.mini_shield = AutoBank:CreateToggle({
		Name = 'Bank Shield Potion',
		Default = false
	})

	TeamCheck = AutoBank:CreateToggle({
		Name = 'Team Check',
		Default = false,
		Tooltip = 'only banks at ur own base'
	})
	Spectators = AutoBank:CreateToggle({
		Name = 'Spectator Check',
		Tooltip = 'wont bank or take stuff out while an enemy is spectating'
	})
	BankOnLeave = AutoBank:CreateToggle({
		Name = 'Bank On Leave',
		Tooltip = 'keeps ur loot on u at base, banks it right before u leave the bank range and takes it back out when u come home',
		Function = function()
			lastBaseDist = nil
		end
	})
end)

run(function()
	local AutoConsume
	local Health
	local SpeedPotion
	local Apple
	local ShieldPotion
	local SerpentsTouch
	local JumpPotion
	local LimitToItem
	local Delay
	local NoSlow
	local GoldenApple
	local GoldenAppleHealth
	local SpeedPie
	local FuryPotion
	local busy = false
	local retryAt = {}
	local status = {started = 0, finished = 0, lastError = nil, currentItem = nil}
	getgenv().aeroConsumeStatus = status

	local furyUtil, furyType
	pcall(function()
		local folder = replicatedStorage.TS['status-effect']
		furyUtil = require(folder['status-effect-util']).StatusEffectUtil
		furyType = require(folder['status-effect-type']).StatusEffectType.FURY_POTION
	end)

	local function effectActive(attribute)
		local char = lplr.Character
		local value = char and char:GetAttribute(attribute)
		return value ~= nil and value ~= false and value ~= 0
	end

	local function furyActive()
		local char = lplr.Character
		if not char then return false end
		if furyUtil and furyType then
			local ok, active = pcall(function()
				return furyUtil:isActive(char, furyType)
			end)
			if ok then return active == true end
		end
		return effectActive('StatusEffect_fury_potion')
	end

	local function inventoryItem(name)
		local item = getItem(name)
		if item and item.tool and item.tool.Parent then return item end
		local gui = lplr:FindFirstChild('PlayerGui')
		local inventory = gui and gui:FindFirstChild('PrivateInventory')
		local folder = inventory and inventory:FindFirstChild(lplr.Name)
		local tool = folder and folder:FindFirstChild(name)
		return tool and {itemType = name, tool = tool} or nil
	end

	local function consumeTool(item)
		if busy or not AutoConsume or not AutoConsume.Enabled then return false end
		local tool = typeof(item) == 'Instance' and item or (item and item.tool)
		local itemType = typeof(item) == 'Instance' and item.Name or (item and item.itemType)
		if not tool or not tool.Parent or not itemType or tick() < (retryAt[itemType] or 0) then return false end
		local meta = bedwars.ItemMeta and bedwars.ItemMeta[itemType]
		if not meta or not meta.consumable then return false end
		local char = lplr.Character
		local hand = char and char:FindFirstChild('HandInvItem')
		local start = getNetRemote('StartConsume')
		local finish = getNetRemote('ConsumeItem')
		if not hand or not start or not finish then
			status.lastError = 'missing hand or consume remote'
			return false
		end
		busy = true
		status.currentItem = itemType
		task.spawn(function()
			local previous = hand.Value
			local switched = not previous or previous.Name ~= itemType
			local ok, err = pcall(function()
				local controller = bedwars.ConsumeController
				if controller and type(controller.isConsumeDisabled) == 'function' then
					local checked, disabled = pcall(controller.isConsumeDisabled, controller, itemType, false)
					if checked and disabled then error('item consumption disabled') end
				end
				if switched then
					local equip = bedwars.Client:Get(remotes.EquipItem)
					if not equip then error('equip remote missing') end
					local promise = equip:CallServerAsync({hand = tool})
					if promise and type(promise.timeout) == 'function' and type(promise.await) == 'function' then
						local success, value = promise:timeout(0.8):await()
						if not success or value == false then error('equip rejected') end
					else
						task.wait(0.12)
					end
				end
				local deadline = os.clock() + 0.35
				while hand.Parent and (not hand.Value or hand.Value.Name ~= itemType) and os.clock() < deadline do
					task.wait(0.03)
				end
				if not hand.Value or hand.Value.Name ~= itemType then error('item not equipped') end
				tool = hand.Value
				start:FireServer({item = tool})
				status.started += 1
				local duration = tonumber(meta.consumable.consumeTime) or 1
				local modifier = bedwars.ClientSyncEvents and bedwars.ClientSyncEvents.ConsumableConsumeTimeModifierCheck
				if modifier and type(modifier.fire) == 'function' then
					local worked, event = pcall(function() return modifier:fire(duration) end)
					if worked and event and tonumber(event.consumeTime) then
						duration = tonumber(event.consumeTime)
					end
				end
				local remaining = math.max(duration, 0.05)
				local untilTime = os.clock() + remaining
				local humanoid = char and char:FindFirstChildOfClass('Humanoid')
				local walkSpeed = humanoid and humanoid.WalkSpeed
				while os.clock() < untilTime do
					if not AutoConsume.Enabled or not tool.Parent or not hand.Parent then return end
					if NoSlow.Enabled and humanoid and humanoid.Parent then
						humanoid.WalkSpeed = walkSpeed
					end
					task.wait(math.min(0.07, math.max(untilTime - os.clock(), 0.01)))
				end
				if not AutoConsume.Enabled or hand.Value ~= tool then return end
				local response = finish:InvokeServer({item = tool})
				status.finished += 1
				if response == false then error('server rejected consumption') end
			end)
			if switched and previous and previous.Parent and hand.Parent and hand.Value and hand.Value.Name == itemType then
				pcall(function()
					bedwars.Client:Get(remotes.EquipItem):CallServerAsync({hand = previous})
				end)
			end
			retryAt[itemType] = tick() + (itemType == 'fury_potion' and 8 or (itemType == 'pie' or itemType == 'jump_potion' or itemType == 'serpents_touch_potion') and 10 or 1.2)
			status.currentItem = nil
			busy = false
			status.lastError = ok and nil or tostring(err)
		end)
		return true
	end

	local function tryItem(name)
		local item = inventoryItem(name)
		return item and consumeTool(item) or false
	end

	local function speedPieActive()
		local gui = lplr:FindFirstChild('PlayerGui')
		local screen = gui and gui:FindFirstChild('StatusEffectHudScreen')
		local hud = screen and screen:FindFirstChild('StatusEffectHud')
		local frame = hud and hud:FindFirstChild('Speed Pie')
		local label = frame and frame:FindFirstChild('4')
		return label and label:IsA('TextLabel') and (tonumber(label.Text) or 0) > 0
	end

	local function checkAutomatic()
		if busy or not entitylib.isAlive or not lplr.Character then return end
		local char = lplr.Character
		local hum = char:FindFirstChildOfClass('Humanoid')
		local hp = tonumber(char:GetAttribute('Health')) or (hum and hum.Health)
		local maxHp = tonumber(char:GetAttribute('MaxHealth')) or (hum and hum.MaxHealth)
		local hpPercent = hp and maxHp and maxHp > 0 and hp / maxHp * 100 or 100

		if GoldenApple.Enabled and hpPercent <= GoldenAppleHealth.Value and tryItem('golden_apple') then return end
		if Apple.Enabled and hpPercent <= Health.Value then
			if tryItem('orange') or tryItem('apple') then return end
		end
		if ShieldPotion.Enabled and (tonumber(char:GetAttribute('Shield_POTION')) or 0) <= 0 then
			if tryItem('big_shield') or tryItem('mini_shield') then return end
		end
		if FuryPotion.Enabled and not furyActive() and tryItem('fury_potion') then return end
		if SpeedPotion.Enabled and not effectActive('StatusEffect_speed') and tryItem('speed_potion') then return end
		if SpeedPie.Enabled and not speedPieActive() and tryItem('pie') then return end
		if JumpPotion.Enabled and not effectActive('StatusEffect_jump') and tryItem('jump_potion') then return end
		if SerpentsTouch.Enabled and not effectActive('StatusEffect_serpents_touch') then
			tryItem('serpents_touch_potion')
		end
	end

	AutoConsume = vape.Categories.Inventory:CreateModule({
		Name = 'AutoConsume',
		Function = function(callback)
			local alive = newRun(AutoConsume)
			if not callback then return end
			task.spawn(function()
				local lastHeld, heldSince, heldStarted
				while alive() do
					if LimitToItem.Enabled then
						local hand = lplr.Character and lplr.Character:FindFirstChild('HandInvItem')
						local tool = hand and hand.Value
						if tool ~= lastHeld then
							lastHeld, heldSince, heldStarted = tool, tick(), false
						end
						if tool and not heldStarted and tick() - heldSince >= Delay.Value then
							heldStarted = consumeTool(tool) or false
						end
					else
						lastHeld = nil
						checkAutomatic()
					end
					task.wait(0.2)
				end
			end)
		end,
		Tooltip = 'automatically consumes selected items'
	})
	SpeedPotion = AutoConsume:CreateToggle({Name = 'Speed Potions', Default = true})
	Apple = AutoConsume:CreateToggle({Name = 'Apple', Default = true, Function = function(state)
		if Health then Health.Object.Visible = state end
	end})
	Health = AutoConsume:CreateSlider({Name = 'Health Percent', Min = 1, Max = 99, Default = 70, Suffix = '%', Visible = false})
	ShieldPotion = AutoConsume:CreateToggle({Name = 'Shield Potions', Default = true})
	GoldenApple = AutoConsume:CreateToggle({Name = 'Golden Apple', Default = false, Function = function(state)
		if GoldenAppleHealth then GoldenAppleHealth.Object.Visible = state end
	end})
	GoldenAppleHealth = AutoConsume:CreateSlider({Name = 'Eat At HP%', Min = 1, Max = 99, Default = 50, Suffix = '%', Visible = false})
	SpeedPie = AutoConsume:CreateToggle({Name = 'Speed Pie', Default = false})
	SerpentsTouch = AutoConsume:CreateToggle({Name = 'Serpents Potion', Default = true})
	JumpPotion = AutoConsume:CreateToggle({Name = 'Jump Potion', Default = true})
	FuryPotion = AutoConsume:CreateToggle({Name = 'Fury Potion', Default = false})
	LimitToItem = AutoConsume:CreateToggle({Name = 'Limit To Item', Default = false, Function = function(state)
		if Delay then Delay.Object.Visible = state end
	end})
	Delay = AutoConsume:CreateSlider({Name = 'Delay', Min = 0, Max = 3, Default = 1, Suffix = 's', Visible = false})
	NoSlow = AutoConsume:CreateToggle({Name = 'No Slow', Default = false})
end)

run(function()
	local oldStart
	local wrappedStart
	local savedDurations = setmetatable({}, {__mode = 'k'})
	local FastConsume

	local function getRatio()
		return 0.67
	end

	FastConsume = vape.Categories.Inventory:CreateModule({
		Name = 'FastConsume',
		Function = function(callback)
			if callback then
				if oldStart then return end
				local class = bedwars.ClickHold
				if not class or type(class.startClick) ~= 'function' then return end
				oldStart = class.startClick
				getgenv().aeroFastConsumeRatio = getRatio()
				wrappedStart = function(self, ...)
					local hand = lplr.Character and lplr.Character:FindFirstChild('HandInvItem')
					local tool = (hand and hand.Value) or (store.hand and store.hand.tool)
					local meta = tool and bedwars.ItemMeta and bedwars.ItemMeta[tool.Name]
					if meta and meta.consumable and type(self.durationSeconds) == 'number' then
						local original = savedDurations[self] or self.durationSeconds
						savedDurations[self] = original
						self.durationSeconds = math.max(original * getRatio(), 0.05)
					end
					return oldStart(self, ...)
				end
				class.startClick = wrappedStart
			else
				getgenv().aeroFastConsumeRatio = nil
				if oldStart and bedwars.ClickHold and bedwars.ClickHold.startClick == wrappedStart then
					bedwars.ClickHold.startClick = oldStart
				end
				oldStart = nil
				wrappedStart = nil
				for obj, original in pairs(savedDurations) do
					obj.durationSeconds = original
					savedDurations[obj] = nil
				end
			end
		end,
		Tooltip = 'shortens the client consume hold; server timing still applies'
	})
end)

run(function()
    local BedPlates
    local Background
    local TeamColor
    local Color = {}
    local Reference = {}
    local BlockCache = {}
	local LayerCounter
	local LayerColor
	local UIStyle
	local PositionDropdown
	local IgnoreTeam
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local compactUI = Instance.new('ScreenGui')
    compactUI.Name = 'BedPlatesCompactUI'
    compactUI.Parent = vape.gui
    compactUI.Enabled = false
    compactUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    compactUI.DisplayOrder = 10
    compactUI.ResetOnSpawn = false
    local compactMainFrame = Instance.new('Frame')
    compactMainFrame.Name = 'MainFrame'
    compactMainFrame.Parent = compactUI
    compactMainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    compactMainFrame.BackgroundTransparency = 0.3
    compactMainFrame.BorderSizePixel = 0
    compactMainFrame.Position = UDim2.new(1, -8, 1, -8)
    compactMainFrame.Size = UDim2.new(0, 150, 0, 0)
    compactMainFrame.AutomaticSize = Enum.AutomaticSize.Y
    compactMainFrame.AnchorPoint = Vector2.new(1, 1)
    local compactCorner = Instance.new('UICorner')
    compactCorner.CornerRadius = UDim.new(0, 8)
    compactCorner.Parent = compactMainFrame
    local compactListLayout = Instance.new('UIListLayout')
    compactListLayout.Padding = UDim.new(0, 4)
    compactListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    compactListLayout.Parent = compactMainFrame
    local compactPadding = Instance.new('UIPadding')
    compactPadding.PaddingTop = UDim.new(0, 6)
    compactPadding.PaddingBottom = UDim.new(0, 6)
    compactPadding.PaddingLeft = UDim.new(0, 6)
    compactPadding.PaddingRight = UDim.new(0, 6)
    compactPadding.Parent = compactMainFrame
    
	local teamColors = getgenv().aeroTeamColors
    
    local function getBedTeamColor(bed)
        local teamId = bed:GetAttribute('TeamID') or bed:GetAttribute('Team') or bed:GetAttribute('TeamId')
        teamId = tonumber(teamId)
        if teamId and teamColors[teamId] then
            return teamColors[teamId]
        end
        return {name = 'Enemy', color = Color3.new(1, 1, 1)}
    end
    
    local function isMyBed(bed)
        local myTeam = lplr.Character and (lplr.Character:GetAttribute('Team') or lplr.Character:GetAttribute('TeamId'))
        local bedTeam = bed:GetAttribute('TeamID') or bed:GetAttribute('Team') or bed:GetAttribute('TeamId')
        if not myTeam or not bedTeam then return false end
        return tonumber(myTeam) == tonumber(bedTeam)
    end
    
	local function updateLayerTextColor()
		local textColor = LayerColor and Color3.fromHSV(LayerColor.Hue, LayerColor.Sat, LayerColor.Value) or Color3.fromRGB(250, 250, 250)
		for _, ref in pairs(Reference) do
			for _, holder in {ref.billboard.Frame, ref.compactRow and ref.compactRow.iconsFrame} do
				for _, img in holder:GetChildren() do
					if img:IsA('ImageLabel') then
						local txt = img:FindFirstChild('Amount')
						if txt then
							txt.TextColor3 = textColor
						end
					end
				end
			end
		end
	end

	local layerDirs = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
		Vector3.new(0, 1, 0),
	}

	local function getBedCells(bed)
		local ok, cells = pcall(function()
			local handler = bedwars.BlockController:getHandlerRegistry():getHandler(bed.Name)
			return handler and handler:getContainedPositions(bed)
		end)
		if ok and type(cells) == 'table' and #cells > 0 then
			return cells
		end
		local start = bedwars.BlockController:getBlockPosition(bed.Position)
		return {start, start + Vector3.new(0, 0, 1)}
	end
    
	local cellParams = OverlapParams.new()
	cellParams.FilterType = Enum.RaycastFilterType.Include
	local cellSize = Vector3.new(1, 1, 1)

	local function getBedLayers(bed)
		local store = bedwars.BlockController:getStore()
		local world = getWorldFolder()
		local blocksFolder = world and world:FindFirstChild('Blocks')
		if blocksFolder then
			cellParams.FilterDescendantsInstances = {blocksFolder}
		end
		local function blockAt(n)
			local known = store:getBlockAt(n)
			if typeof(known) == 'Instance' and known.Parent then
				return known
			end
			if not blocksFolder then return nil end
			for _, part in workspace:GetPartBoundsInBox(CFrame.new(n * 3), cellSize, cellParams) do
				local inst = part
				while inst.Parent and inst.Parent ~= blocksFolder do
					inst = inst.Parent
				end
				if inst.Parent == blocksFolder then
					return inst
				end
			end
			return nil
		end

		local seen, frontier = {}, {}
		for _, cell in getBedCells(bed) do
			seen[cell] = true
			table.insert(frontier, cell)
		end

		local entries, byBlock = {}, {}
		local layerCount = 0
		for ring = 1, 8 do
			local nextFrontier, total, filled, counts = {}, 0, 0, {}
			for _, cell in frontier do
				for _, dir in layerDirs do
					local n = cell + dir
					if not seen[n] then
						seen[n] = true
						table.insert(nextFrontier, n)
						total += 1
						local blk = blockAt(n)
						if blk and blk.Name ~= 'bed' and not blk:GetAttribute('NoBreak') then
							filled += 1
							counts[blk.Name] = (counts[blk.Name] or 0) + 1
						end
					end
				end
			end
			frontier = nextFrontier

			local main, mainCount = nil, 0
			for name, count in counts do
				if count > mainCount or (count == mainCount and main and name < main) then
					main, mainCount = name, count
				end
			end

			if ring == 1 then
				if not main then break end
			elseif filled < total * 0.5 then
				break
			end

			layerCount = ring

			for name in counts do
				local entry = byBlock[name]
				if entry then
					entry.amt += 1
				else
					entry = {block = name, amt = 1}
					byBlock[name] = entry
					table.insert(entries, entry)
				end

				if ring == 1 and filled < total and name == main then
					entry.text = filled..'/'..total
				end
			end
		end

		table.sort(entries, function(a, b)
			return a.block < b.block
		end)
		return entries, layerCount
	end

	local function renderLayers(frame, entries)
		for _, obj in frame:GetChildren() do
			if obj and ((obj:IsA('ImageLabel') and obj.Name ~= 'Blur') or obj.Name == 'Fraction') then
				obj:Destroy()
			end
		end
		for i, e in entries do
			local image = Instance.new('ImageLabel')
			image.LayoutOrder = i
			image.Size = UDim2.fromOffset(32, 32)
			image.BackgroundTransparency = 1
			image.Image = bedwars.getIcon({itemType = e.block}, true)
			image.Parent = frame
			local label = e.text or (e.amt and e.amt >= 2 and (not LayerCounter or LayerCounter.Enabled) and tostring(e.amt)) or nil
			if label then
				local txt = Instance.new('TextLabel')
				txt.Name = 'Amount'
				txt.Size = UDim2.fromScale(1, 1)
				txt.BackgroundTransparency = 1
				txt.Text = label
				txt.TextColor3 = LayerColor and Color3.fromHSV(LayerColor.Hue, LayerColor.Sat, LayerColor.Value) or Color3.fromRGB(250, 250, 250)
				txt.TextSize = e.text and 16 or 24
				txt.TextStrokeTransparency = 0.3
				txt.Font = e.text and Enum.Font.GothamBold or Enum.Font.Arial
				txt.Parent = image
			end
		end
	end

	local function refreshAdornee(v)
		local bed = v.Adornee
		local entries, layers = getBedLayers(bed)
		local sig = (LayerCounter and LayerCounter.Enabled) and '1' or '0'
		for _, e in entries do
			sig ..= e.block..(e.amt or '')..(e.text or '')..','
		end
		local changed = BlockCache[bed] ~= sig
		BlockCache[bed] = sig
		local mine = isMyBed(bed)
		local hasPlates = #entries > 0
		v.Enabled = hasPlates and UIStyle.Value == 'Original' and not mine
		if changed then
			renderLayers(v.Frame, entries)
		end
		if Reference[bed] and Reference[bed].compactRow then
			if changed then
				renderLayers(Reference[bed].compactRow.iconsFrame, entries)
			end
			Reference[bed].compactRow.countLabel.Text = tostring(layers)
			Reference[bed].compactRow.frame.Visible = hasPlates and not (mine and IgnoreTeam and IgnoreTeam.Enabled)
		end
	end
    
    local function Added(v)
        if Reference[v] then return end
        local _bpUserId = v:GetAttribute('PlacedByUserId')
        if _bpUserId then
            local _bpOk, _bpOwner = pcall(function() return playersService:GetPlayerByUserId(_bpUserId) end)
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'bed'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, TeamColor.Enabled and 50 or 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        billboard.Enabled = UIStyle.Value == 'Original'
        
        local blur = addBlur(billboard)
        blur.Visible = Background.Enabled
        
        local frame = Instance.new('Frame')
        frame.Size = TeamColor.Enabled and UDim2.new(1, 0, 1, -16) or UDim2.fromScale(1, 1)
        frame.Position = TeamColor.Enabled and UDim2.new(0, 0, 0, 16) or UDim2.new(0, 0, 0, 0)
        frame.BackgroundColor3 = TeamColor.Enabled and getBedTeamColor(v).color or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
        frame.BackgroundTransparency = 1 - (Background.Enabled and (TeamColor.Enabled and 0.5 or Color.Opacity) or 0)
        frame.Parent = billboard

        local teamLabel = Instance.new('TextLabel')
        teamLabel.Name = 'TeamLabel'
        teamLabel.Size = UDim2.new(1, 0, 0, 14)
        teamLabel.Position = UDim2.new(0, 0, 0, 0)
        teamLabel.BackgroundTransparency = 1
        teamLabel.Text = getBedTeamColor(v).name
        teamLabel.TextColor3 = getBedTeamColor(v).color
        teamLabel.TextSize = 13
        teamLabel.Font = Enum.Font.GothamBold
        teamLabel.TextStrokeTransparency = 0.4
        teamLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        teamLabel.Visible = TeamColor.Enabled
        teamLabel.Parent = billboard
        
        local layout = Instance.new('UIListLayout')
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.Padding = UDim.new(0, 4)
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            billboard.Size = UDim2.fromOffset(math.max(layout.AbsoluteContentSize.X + 4, 36), TeamColor.Enabled and 50 or 36)
        end)
        layout.Parent = frame
        
        local corner = Instance.new('UICorner')
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = frame

        local rowFrame = Instance.new('Frame')
        rowFrame.BackgroundTransparency = 1
        rowFrame.Size = UDim2.new(1, 0, 0, 50)
        rowFrame.AutomaticSize = Enum.AutomaticSize.Y
        rowFrame.LayoutOrder = #compactMainFrame:GetChildren()
        rowFrame.Visible = false
        rowFrame.Parent = compactMainFrame

        local rowTeamLabel = Instance.new('TextLabel')
        rowTeamLabel.Size = UDim2.new(1, 0, 0, 14)
        rowTeamLabel.BackgroundTransparency = 1
        rowTeamLabel.Text = getBedTeamColor(v).name
        rowTeamLabel.TextColor3 = getBedTeamColor(v).color
        rowTeamLabel.TextSize = 13
        rowTeamLabel.Font = Enum.Font.GothamBold
        rowTeamLabel.TextStrokeTransparency = 0.4
        rowTeamLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        rowTeamLabel.Parent = rowFrame

        local rowBG = Instance.new('Frame')
        rowBG.Position = UDim2.new(0, 0, 0, 16)
        rowBG.Size = UDim2.new(1, 0, 0, 34)
        rowBG.AutomaticSize = Enum.AutomaticSize.Y
        rowBG.BackgroundColor3 = Color3.new(0, 0, 0)
        rowBG.BackgroundTransparency = 0.3
        rowBG.Parent = rowFrame

        local rowCorner = Instance.new('UICorner')
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = rowBG

        local rowIcons = Instance.new('Frame')
        rowIcons.BackgroundTransparency = 1
        rowIcons.Size = UDim2.new(1, -30, 0, 34)
        rowIcons.AutomaticSize = Enum.AutomaticSize.Y
        rowIcons.Parent = rowBG

        local rowIconLayout = Instance.new('UIListLayout')
        rowIconLayout.FillDirection = Enum.FillDirection.Horizontal
        rowIconLayout.SortOrder = Enum.SortOrder.LayoutOrder
        rowIconLayout.Padding = UDim.new(0, 2)
        rowIconLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        rowIconLayout.Wraps = true
        rowIconLayout.Parent = rowIcons

        local rowCount = Instance.new('TextLabel')
        rowCount.Size = UDim2.new(0, 28, 1, 0)
        rowCount.Position = UDim2.new(1, -28, 0, 0)
        rowCount.BackgroundTransparency = 1
        rowCount.Text = "0"
        rowCount.TextColor3 = Color3.fromRGB(255, 255, 255)
        rowCount.TextSize = 14
        rowCount.Font = Enum.Font.GothamBold
        rowCount.Parent = rowBG

        Reference[v] = {
            billboard = billboard,
            compactRow = {
                frame = rowFrame,
                iconsFrame = rowIcons,
                countLabel = rowCount
            }
        }
        BlockCache[v] = ""
        refreshAdornee(billboard)
    end
    
	local pendingBeds = {}
	local _refreshNearPending = false
	local function refreshNear(data)
		local blockPos = data and data.blockRef and data.blockRef.blockPosition
		if not blockPos then return end
		blockPos *= 3
		for bed in pairs(Reference) do
			if bed.Parent and (blockPos - bed.Position).Magnitude <= 30 then
				pendingBeds[bed] = true
			end
		end
		if _refreshNearPending or not next(pendingBeds) then return end
		_refreshNearPending = true
		task.delay(0.1, function()
			_refreshNearPending = false
			local done = {}
			for bed in pairs(pendingBeds) do
				pendingBeds[bed] = nil
				local ref = Reference[bed]
				if ref and bed.Parent then
					refreshAdornee(ref.billboard)
					table.insert(done, bed)
				end
			end
			task.delay(0.5, function()
				for _, bed in done do
					local ref = Reference[bed]
					if ref and bed.Parent then
						refreshAdornee(ref.billboard)
					end
				end
			end)
		end)
	end

    local currentCorner = 'Bottom Right'

    local function updateCompactPosition()
        local genUI = vape.gui:FindFirstChild('GeneratorCompactUI')
        local offset = 8
        if genUI and genUI.Enabled and currentCorner == 'Bottom Right' then
            offset = offset + 128
        end
        local invHost = (gethui and gethui()) or game:GetService('CoreGui')
        if invHost:FindFirstChild('InventoryESP') and (currentCorner == 'Bottom Right' or currentCorner == 'Top Right') then
            offset = offset + 200
        end
        if currentCorner == 'Top Right' then
            compactMainFrame.AnchorPoint = Vector2.new(1, 0)
            compactMainFrame.Position = UDim2.new(1, -offset, 0, 8)
        elseif currentCorner == 'Top Left' then
            compactMainFrame.AnchorPoint = Vector2.new(0, 0)
            compactMainFrame.Position = UDim2.new(0, 8, 0, 8)
        elseif currentCorner == 'Bottom Left' then
            compactMainFrame.AnchorPoint = Vector2.new(0, 1)
            compactMainFrame.Position = UDim2.new(0, 8, 1, -8)
        else
            compactMainFrame.AnchorPoint = Vector2.new(1, 1)
            compactMainFrame.Position = UDim2.new(1, -offset, 1, -8)
        end
    end
    
    BedPlates = vape.Categories.Minigames:CreateModule({
        Name = 'BedPlates',
        Function = function(callback)
            if callback then
                table.clear(BlockCache)
                compactUI.Enabled = UIStyle.Value == 'Compact'
                
                local tagged = collectionService:GetTagged('bed')
                for _, v in ipairs(tagged) do 
                    Added(v)
                end
                
                BedPlates:Clean(vapeEvents.PlaceBlockEvent.Event:Connect(refreshNear))
                BedPlates:Clean(vapeEvents.BreakBlockEvent.Event:Connect(refreshNear))
                BedPlates:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(Added))

                local worldFolder = getWorldFolder()
                local blocksFolder = worldFolder and worldFolder:FindFirstChild('Blocks')
                if blocksFolder then
                    local function onBlockChange(obj)
                        local part = obj:IsA('BasePart') and obj or (obj:IsA('Model') and obj:FindFirstChildWhichIsA('BasePart', true))
                        if not part then return end
                        refreshNear({blockRef = {blockPosition = part.Position / 3}})
                    end
                    BedPlates:Clean(blocksFolder.DescendantAdded:Connect(onBlockChange))
                    BedPlates:Clean(blocksFolder.DescendantRemoving:Connect(onBlockChange))
                end
                BedPlates:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(v)
                    if Reference[v] then
                        Reference[v].billboard:Destroy()
                        Reference[v].compactRow.frame:Destroy()
                        Reference[v] = nil
                        BlockCache[v] = nil
                    end
                end))
				local lastCompact = 0
				BedPlates:Clean(runService.Heartbeat:Connect(function()
					if compactUI.Enabled and tick() - lastCompact > 0.5 then
						lastCompact = tick()
						updateCompactPosition()
					end
				end))
            else
                for _, v in pairs(Reference) do
                    v.billboard:Destroy()
                    v.compactRow.frame:Destroy()
                end
                table.clear(Reference)
                table.clear(BlockCache)
                compactUI.Enabled = false
            end
        end,
        Tooltip = 'shows enemys bed defence'
    })

    UIStyle = BedPlates:CreateDropdown({
        Name = 'UI Style',
        List = {'Original', 'Compact'},
        Default = 'Original',
        Function = function(val)
            local isOriginal = val == 'Original'
            compactUI.Enabled = BedPlates.Enabled and not isOriginal
            for bed, ref in pairs(Reference) do
                ref.billboard.Enabled = isOriginal
                refreshAdornee(ref.billboard)
            end
            if PositionDropdown.Object then
                PositionDropdown.Object.Visible = not isOriginal
            end
            if IgnoreTeam and IgnoreTeam.Object then
                IgnoreTeam.Object.Visible = not isOriginal
            end
        end,
        Tooltip = 'pick between the floating world esp or a corner panel'
    })

    PositionDropdown = BedPlates:CreateDropdown({
        Name = 'Position',
        List = {'Top Right', 'Top Left', 'Bottom Left', 'Bottom Right'},
        Default = 'Bottom Right',
        Function = function(val)
            currentCorner = val
            updateCompactPosition()
        end,
        Tooltip = 'pick w corner u want the panel chillin in'
    })

    task.defer(function()
        if PositionDropdown and PositionDropdown.Object then
            PositionDropdown.Object.Visible = (UIStyle.Value == 'Compact')
        end
        if IgnoreTeam and IgnoreTeam.Object then
            IgnoreTeam.Object.Visible = (UIStyle.Value == 'Compact')
        end
    end)
    
    IgnoreTeam = BedPlates:CreateToggle({
        Name = 'Ignore Team',
        Default = false,
        Function = function(callback)
            for bed, ref in pairs(Reference) do
                refreshAdornee(ref.billboard)
            end
        end,
        Tooltip = 'wont show ur own team bed on the compact panel'
    })
    
    Background = BedPlates:CreateToggle({
        Name = 'Background',
        Function = function(callback)
            if Color.Object then 
                Color.Object.Visible = callback and not TeamColor.Enabled
            end
            for _, v in pairs(Reference) do
                v.billboard.Frame.BackgroundTransparency = 1 - (callback and (TeamColor.Enabled and 0.5 or Color.Opacity) or 0)
                local blur = v.billboard:FindFirstChild('Blur')
                if blur then
                    blur.Visible = callback
                end
            end
        end,
        Default = true
    })

    Color = BedPlates:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for bed, v in pairs(Reference) do
                if not TeamColor.Enabled then
                    v.billboard.Frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                end
                if Background.Enabled and not TeamColor.Enabled then
                    v.billboard.Frame.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Visible = false,
        Darker = true
    })
    
    TeamColor = BedPlates:CreateToggle({
        Name = 'Team Color',
        Default = true,
        Function = function(callback)
            if Color.Object then
                Color.Object.Visible = Background.Enabled and not callback
            end
            for bed, ref in pairs(Reference) do
                ref.billboard.Frame.BackgroundColor3 = callback and getBedTeamColor(bed).color or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
                ref.billboard.Frame.BackgroundTransparency = 1 - (Background.Enabled and (callback and 0.5 or Color.Opacity) or 0)
            end
        end
    })

	LayerCounter = BedPlates:CreateToggle({
		Name = 'Layer Counter',
		Function = function(callback)
			if LayerColor and LayerColor.Object then
				LayerColor.Object.Visible = callback
			end
			for _, ref in pairs(Reference) do
				refreshAdornee(ref.billboard)
			end
		end,
		Default = true
	})
	LayerColor = BedPlates:CreateColorSlider({
		Name = 'Counter Text Color',
		DefaultSat = 1,
		DefaultValue = 1,
		Function = function()
			updateLayerTextColor()
		end,
		Visible = LayerCounter.Enabled
	})	
end)

run(function()
	local Nuker
	local TargetMode
	local BreakType
	local Mode
	local Range
	local BreakSpeed
	local UpdateRate
	local Bed
	local BedCheck
	local LuckyBlock
	local IronOre
	local Tesla
	local Hive
	local Pinata
	local Crops
	local Snow
	local Effect
	local CustomHealth = {}
	local Animation
	local SelfBreak
	local LimitItem
	local AutoTool
	local MouseDown
	local YetiBreaker
	local RagnarBreaker
	local ShowPath
	local BlockHighlight
	local BreakerHighlightColor
	local BreakerAngle
	local FACES = {Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(0, 3, 0), Vector3.new(0, -3, 0), Vector3.new(0, 0, 3), Vector3.new(0, 0, -3)}
	local parts = {}
	local highlightBox
	local plan
	local lastHit = 0
	local lastYetiUse = 0
	local breakableCache = setmetatable({}, {__mode = 'k'})
	local hbMounted, hbPart, hbRef, hbBlock, hbMax, hbLast, hbPercent = nil, nil, nil, nil, 1, 0, -1

	local function cleanupHealthbar()
		if hbMounted then
			pcall(bedwars.Roact.unmount, hbMounted)
			hbMounted = nil
		end
		if hbPart then
			pcall(function() hbPart:Destroy() end)
			hbPart = nil
		end
		hbRef, hbBlock, hbPercent = nil, nil, -1
	end

	local function setHealthbarPercent(percent)
		percent = math.clamp(percent, 0, 1)
		if math.abs(percent - hbPercent) < 0.001 then return end
		hbPercent = percent
		local bar = hbRef and hbRef:getValue()
		if bar then
			tweenService:Create(bar, TweenInfo.new(0.15), {
				Size = UDim2.fromScale(percent, 1),
				BackgroundColor3 = Color3.fromHSV(math.clamp(percent / 2.5, 0, 1), 0.89, 0.75)
			}):Play()
		end
		if percent <= 0 then
			local mine = hbBlock
			task.delay(0.25, function()
				if hbBlock == mine then
					cleanupHealthbar()
				end
			end)
		end
	end

	local function customHealthbar(_, blockRef, health, maxHealth, changeHealth, block)
		if not Nuker or not Nuker.Enabled or not block then return end
		health = math.max((tonumber(health) or 0) - (tonumber(changeHealth) or 0), 0)
		maxHealth = math.max(tonumber(block:GetAttribute('MaxHealth') or maxHealth) or 1, 1)
		if hbBlock ~= block then
			cleanupHealthbar()
			hbBlock = block
			local create = bedwars.Roact.createElement
			local percent = math.clamp((health + (tonumber(changeHealth) or 0)) / maxHealth, 0, 1)
			local name = (bedwars.ItemMeta[block.Name] and bedwars.ItemMeta[block.Name].displayName) or block.Name
			hbRef = bedwars.Roact.createRef()
			local part = Instance.new('Part')
			part.Name = 'AeroNukerHB'
			part.Size = Vector3.one
			part.CFrame = CFrame.new(bedwars.BlockController:getWorldPosition(blockRef.blockPosition))
			part.Transparency = 1
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.Parent = workspace
			hbPart = part
			pcall(function() bedwars.QueryUtil:setQueryIgnored(part, true) end)
			hbMounted = bedwars.Roact.mount(create('BillboardGui', {
				Size = UDim2.fromOffset(249, 102),
				StudsOffset = Vector3.new(0, 2.5, 0),
				Adornee = part,
				MaxDistance = 40,
				AlwaysOnTop = true
			}, {
				create('Frame', {
					Size = UDim2.fromOffset(160, 50),
					Position = UDim2.fromOffset(44, 32),
					BackgroundColor3 = Color3.new(),
					BackgroundTransparency = 0.5
				}, {
					create('UICorner', {CornerRadius = UDim.new(0, 5)}),
					create('ImageLabel', {
						Size = UDim2.new(1, 89, 1, 52),
						Position = UDim2.fromOffset(-48, -31),
						BackgroundTransparency = 1,
						Image = getcustomasset('aerov4/assets/new/blur.png'),
						ScaleType = Enum.ScaleType.Slice,
						SliceCenter = Rect.new(52, 31, 261, 502)
					}),
					create('TextLabel', {
						Size = UDim2.fromOffset(145, 14),
						Position = UDim2.fromOffset(13, 12),
						BackgroundTransparency = 1,
						Text = name,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextColor3 = Color3.new(),
						TextScaled = true,
						Font = Enum.Font.Arial
					}),
					create('TextLabel', {
						Size = UDim2.fromOffset(145, 14),
						Position = UDim2.fromOffset(12, 11),
						BackgroundTransparency = 1,
						Text = name,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextColor3 = color.Dark(uipallet.Text, 0.16),
						TextScaled = true,
						Font = Enum.Font.Arial
					}),
					create('Frame', {
						Size = UDim2.fromOffset(138, 4),
						Position = UDim2.fromOffset(12, 32),
						BackgroundColor3 = uipallet.Main
					}, {
						create('UICorner', {CornerRadius = UDim.new(1, 0)}),
						create('Frame', {
							[bedwars.Roact.Ref] = hbRef,
							Size = UDim2.fromScale(percent, 1),
							BackgroundColor3 = Color3.fromHSV(math.clamp(percent / 2.5, 0, 1), 0.89, 0.75)
						}, {create('UICorner', {CornerRadius = UDim.new(1, 0)})})
					})
				})
			}), part)
			hbPercent = percent
		end
		hbMax = maxHealth
		hbLast = tick()
		setHealthbarPercent(health / hbMax)
	end

	local function refreshHealthbar()
		if not hbBlock then return end
		if not hbBlock.Parent or tick() - hbLast > 1.5 then
			cleanupHealthbar()
			return
		end
		local live = hbBlock:GetAttribute('Health')
		if live and live / hbMax < hbPercent then
			setHealthbarPercent(live / hbMax)
		end
	end

	local function teamKey(value)
		if value == nil then return nil end
		if typeof(value) == 'Instance' then
			return tostring(value.Name)
		end
		return tostring(value)
	end

	local function playerTeamKey(plr)
		if not plr then return nil end
		return teamKey(plr:GetAttribute('Team') or plr:GetAttribute('TeamId') or plr:GetAttribute('TeamID') or plr.Team)
	end

	local function isOwnTeamBlock(v)
		local mine = playerTeamKey(lplr)
		local blockTeam = teamKey(v:GetAttribute('Team') or v:GetAttribute('TeamId') or v:GetAttribute('TeamID'))
		if mine and blockTeam and mine == blockTeam then
			return true
		end
		local placedBy = tonumber(v:GetAttribute('PlacedByUserId'))
		if placedBy == lplr.UserId then
			return true
		end
		local placer = placedBy and playersService:GetPlayerByUserId(placedBy)
		local theirs = placer and playerTeamKey(placer)
		return mine ~= nil and theirs ~= nil and mine == theirs
	end

	local function blockAllowed(v)
		if not v or not v.Parent or v:GetAttribute('NoBreak') then
			return false
		end
		local mine = lplr:GetAttribute('Team')
		if mine and v:GetAttribute('Team'..tostring(mine)..'NoBreak') then
			return false
		end
		return SelfBreak.Enabled or not isOwnTeamBlock(v)
	end

	local function isBreakable(v)
		local cached = breakableCache[v]
		if cached and tick() - cached.t < 0.5 then
			return cached.v
		end
		local ok, result = pcall(function()
			return bedwars.BlockController:isBlockBreakable({blockPosition = bedwars.BlockController:getBlockPosition(v.Position)}, lplr)
		end)
		breakableCache[v] = {v = ok and result or false, t = tick()}
		return ok and result or false
	end

	local function holdingBreakTool()
		local hand = store.hand and store.hand.tool
		local meta = hand and bedwars.ItemMeta[hand.Name]
		return meta ~= nil and meta.breakBlock ~= nil
	end

	local function getBreakType(block)
		if block.Name == 'gumdrop_bounce_pad' then return 'stone' end
		local meta = bedwars.ItemMeta[block.Name]
		return meta and meta.block and meta.block.breakType
	end

	local function blockHealth(block, blockPos)
		local data = bedwars.BlockController:getStore():getBlockData(blockPos)
		local health = data and (data:GetAttribute('1') or data:GetAttribute('Health'))
		if health == nil then
			health = block:GetAttribute('Health')
		end
		if health ~= nil then
			return health
		end
		local meta = bedwars.ItemMeta[block.Name]
		return meta and meta.block and meta.block.health or 10
	end

	local function toolDamage(itemType, breakType)
		local meta = itemType and bedwars.ItemMeta[itemType]
		return meta and meta.breakBlock and breakType and meta.breakBlock[breakType] or 2
	end

	local function containedCells(block)
		local out = {}
		local ok, handler = pcall(function()
			return bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
		end)
		if ok and handler then
			local ok2, cells = pcall(function()
				return handler:getContainedPositions(block)
			end)
			if ok2 and cells then
				for _, v in cells do
					table.insert(out, v * 3)
				end
			end
		end
		if #out == 0 then
			table.insert(out, bedwars.BlockController:getBlockPosition(block.Position) * 3)
		end
		return out
	end

	local function nearestCellDistance(block, origin)
		local best = math.huge
		for _, cell in containedCells(block) do
			best = math.min(best, (cell - origin).Magnitude)
		end
		return best
	end

	local function planRoute(target, origin, nearFirst)
		return bedwars.planBreakRoute(target, {
			origin = origin,
			anchor = origin,
			nearFirst = nearFirst,
			angle = BreakerAngle.Value,
			filter = blockAllowed
		})
	end

	local function frontOf(current)
		for _, cell in current.route do
			local blk = getPlacedBlock(cell)
			if blk then
				if blk == current.target then
					return cell, blk
				end
				if not blockAllowed(blk) then
					return nil
				end
				return cell, blk
			end
		end
		return nil
	end

	local function ensureParts(count)
		while #parts < count do
			local part = Instance.new('Part')
			part.Anchored = true
			part.CanQuery = false
			part.CanCollide = false
			part.Transparency = 1
			part.Position = Vector3.zero
			part.Parent = gameCamera
			local adorn = Instance.new('BoxHandleAdornment')
			adorn.Size = Vector3.one
			adorn.AlwaysOnTop = true
			adorn.ZIndex = 1
			adorn.Transparency = 0.5
			adorn.Adornee = part
			adorn.Parent = part
			table.insert(parts, part)
		end
	end

	local function hideParts()
		for _, p in parts do
			p.Position = Vector3.zero
		end
	end

	local function destroyParts()
		for _, p in parts do
			pcall(function() p:Destroy() end)
		end
		table.clear(parts)
	end

	local function drawRoute(route, active)
		if not ShowPath.Enabled or not route then
			hideParts()
			return
		end
		local index = 1
		for _, cell in route do
			if index > #parts then break end
			if getPlacedBlock(cell) then
				local part = parts[index]
				part.Position = cell
				part.BoxHandleAdornment.Color3 = cell == active and Color3.new(1, 0.2, 0.2) or Color3.new(0.2, 1, 0.2)
				index += 1
			end
		end
		for i = index, #parts do
			parts[i].Position = Vector3.zero
		end
	end

	local function setHighlight(block)
		if not BlockHighlight.Enabled or not block or not block.Parent then
			if highlightBox then highlightBox.Adornee = nil end
			return
		end
		if not highlightBox then
			highlightBox = Instance.new('BoxHandleAdornment')
			highlightBox.AlwaysOnTop = true
			highlightBox.ZIndex = 10
			highlightBox.Transparency = 0.3
			highlightBox.Parent = gameCamera
		end
		highlightBox.Color3 = Color3.fromHSV(BreakerHighlightColor.Hue, BreakerHighlightColor.Sat, BreakerHighlightColor.Value)
		highlightBox.Size = block.Size + Vector3.new(0.05, 0.05, 0.05)
		highlightBox.Adornee = block
	end

	local function clearVisuals()
		hideParts()
		setHighlight(nil)
	end

	local function cleanupAll()
		plan = nil
		table.clear(breakableCache)
		if highlightBox then
			pcall(function() highlightBox:Destroy() end)
			highlightBox = nil
		end
		destroyParts()
		cleanupHealthbar()
	end

	local function useKitAbilities()
		if RagnarBreaker.Enabled and store.equippedKit == 'berserker' then
			pcall(function()
				if bedwars.AbilityController and bedwars.AbilityController:canUseAbility('berserker_rage') then
					replicatedStorage:WaitForChild('events-@easy-games/game-core:shared/game-core-networking@getEvents.Events'):WaitForChild('useAbility'):FireServer('berserker_rage')
				end
			end)
		end
		if YetiBreaker.Enabled and store.equippedKit == 'yeti' and tick() - lastYetiUse > 1 then
			lastYetiUse = tick()
			task.spawn(function()
				pcall(function()
					if bedwars.AbilityController and bedwars.AbilityController:canUseAbility('yeti_glacial_roar') then
						replicatedStorage:WaitForChild('events-@easy-games/game-core:shared/game-core-networking@getEvents.Events'):WaitForChild('useAbility'):FireServer('yeti_glacial_roar')
					end
				end)
			end)
		end
	end

	local function holdingCorrectTool(block)
		if AutoTool.Enabled then return true end
		local breakType = getBreakType(block)
		local correct = breakType and store.tools[breakType]
		if not correct then return true end
		local hand = store.hand and store.hand.tool
		return hand ~= nil and hand.Name == correct.tool.Name
	end

	local function faceNormal(cell, origin)
		local d = origin - cell
		local ax, ay, az = math.abs(d.X), math.abs(d.Y), math.abs(d.Z)
		if ay >= ax and ay >= az then
			return Vector3.new(0, d.Y >= 0 and 1 or -1, 0)
		elseif ax >= az then
			return Vector3.new(d.X >= 0 and 1 or -1, 0, 0)
		end
		return Vector3.new(0, 0, d.Z >= 0 and 1 or -1)
	end

	local function hitCell(cell, block, origin)
		local blockPos = bedwars.BlockController:getBlockPosition(cell)
		local breakType = getBreakType(block)
		local hand = store.hand and store.hand.tool
		local hitType = hand and hand.Name
		if AutoTool.Enabled and holdingBreakTool() and (workspace:GetServerTimeNow() - (bedwars.SwordController.lastAttack or 0)) > 0.4 then
			local tool = breakType and store.tools[breakType]
			if tool and tool.itemType ~= hitType then
				for i, v in store.inventory.hotbar or {} do
					if v.item and v.item.itemType == tool.itemType then
						hotbarSwitch(i - 1)
						hitType = tool.itemType
						break
					end
				end
			end
		end
		if Animation.Enabled and tick() - (store.lastBreakerAnimation or 0) >= 0.18 then
			store.lastBreakerAnimation = tick()
			task.spawn(function()
				local animation
				pcall(function()
					animation = bedwars.AnimationUtil:playAnimation(lplr, bedwars.BlockController:getAnimationController():getAssetId(1))
				end)
				pcall(function()
					bedwars.ViewmodelController:playAnimation(15)
				end)
				task.wait(0.3)
				if animation then
					pcall(function()
						animation:Stop()
						animation:Destroy()
					end)
				end
			end)
		end
		local before = blockHealth(block, blockPos)
		local dmg = toolDamage(hitType, breakType)
		bedwars.ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
			blockRef = {blockPosition = blockPos},
			hitPosition = cell,
			hitNormal = faceNormal(cell, origin)
		}):andThen(function(result)
			if result == 'cancelled' then
				plan = nil
				return
			end
			if not Effect.Enabled then return end
			local predicted = math.max(before - dmg, 0)
			local after = result == 'destroyed' and 0 or math.min(blockHealth(block, blockPos) or predicted, predicted)
			local meta = bedwars.ItemMeta[block.Name]
			local maxHealth = block:GetAttribute('MaxHealth') or (meta and meta.block and meta.block.health) or math.max(before, 1)
			local show = CustomHealth.Enabled and customHealthbar or bedwars.BlockBreaker.updateHealthbar
			pcall(show, bedwars.BlockBreaker, {blockPosition = blockPos}, before, maxHealth, math.max(before - after, 0), block)
			pcall(function()
				if after <= 0 then
					bedwars.BlockBreaker.breakEffect:playBreak(block.Name, blockPos, lplr)
				else
					bedwars.BlockBreaker.breakEffect:playHit(block.Name, blockPos, lplr)
				end
			end)
		end)
	end

	local ignoreList = {}
	local cursorParams = RaycastParams.new()
	cursorParams.FilterType = Enum.RaycastFilterType.Exclude
	local function cursorBlock()
		local point = inputService.TouchEnabled and gameCamera.ViewportSize / 2 or inputService:GetMouseLocation()
		local unit = gameCamera:ViewportPointToRay(point.X, point.Y, 0)
		table.clear(ignoreList)
		for _, plr in playersService:GetPlayers() do
			if plr.Character then
				table.insert(ignoreList, plr.Character)
			end
		end
		cursorParams.FilterDescendantsInstances = ignoreList
		local result = workspace:Raycast(unit.Origin, unit.Direction * 999, cursorParams)
		return result and result.Instance, result and result.Position
	end

	Nuker = vape.Categories.Minigames:CreateModule({
		Name = 'Nuker',
		Function = function(callback)
			local aeroAlive = newRun(Nuker)
			if callback then
				local beds = {}
				local function bedAdd(obj)
					if obj.Name == 'bed' and obj:IsA('BasePart') and not table.find(beds, obj) then
						table.insert(beds, obj)
					end
				end
				local function bedRemove(obj)
					local i = table.find(beds, obj)
					if i then table.remove(beds, i) end
				end
				for _, obj in workspace:GetChildren() do
					bedAdd(obj)
				end
				Nuker:Clean(workspace.ChildAdded:Connect(bedAdd))
				Nuker:Clean(workspace.ChildRemoved:Connect(bedRemove))
				local luckyblock = collection('LuckyBlock', Nuker)
				local ironores = collection('iron_ore_mesh_block', Nuker)
				local tracked = {tesla_trap = {}, beehive = {}, pinata = {}, carrot = {}, melon = {}, pumpkin = {}, snow_pile = {}}
				local function trackAdd(obj)
					local t = tracked[obj.Name]
					if not t then return end
					local part = obj:IsA('BasePart') and obj or obj:IsA('Model') and (obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart'))
					if part and not table.find(t, part) then
						table.insert(t, part)
					end
				end
				local function trackRemove(obj)
					local t = tracked[obj.Name]
					if not t then return end
					local part = obj:IsA('Model') and (obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart')) or obj
					local i = part and table.find(t, part)
					if i then table.remove(t, i) end
					breakableCache[obj] = nil
				end
				ensureParts(24)
				scanDescendants(workspace, trackAdd, Nuker)
				Nuker:Clean(workspace.DescendantAdded:Connect(trackAdd))
				Nuker:Clean(workspace.DescendantRemoving:Connect(trackRemove))

				local function candidateLists()
					local lists = {}
					if Bed.Enabled then table.insert(lists, beds) end
					if Tesla.Enabled then table.insert(lists, tracked.tesla_trap) end
					if Hive.Enabled then table.insert(lists, tracked.beehive) end
					if LuckyBlock.Enabled then table.insert(lists, luckyblock) end
					if IronOre.Enabled then table.insert(lists, ironores) end
					if Snow.Enabled then table.insert(lists, tracked.snow_pile) end
					if Pinata.Enabled then table.insert(lists, tracked.pinata) end
					if Crops.Enabled then
						table.insert(lists, tracked.carrot)
						table.insert(lists, tracked.melon)
						table.insert(lists, tracked.pumpkin)
					end
					return lists
				end

				local function valid(v, origin)
					if not v or not v.Parent then return false end
					if (v:GetAttribute('BedShieldEndTime') or 0) > workspace:GetServerTimeNow() then return false end
					if nearestCellDistance(v, origin) >= Range.Value then return false end
					return blockAllowed(v) and isBreakable(v)
				end

				local function pickTarget(origin)
					if plan and plan.blatant and valid(plan.target, origin) then
						return plan.target
					end
					if Bed.Enabled then
						local bestBed, bestBedDist
						for _, v in beds do
							if valid(v, origin) then
								local d = nearestCellDistance(v, origin)
								if not bestBedDist or d < bestBedDist then
									bestBed, bestBedDist = v, d
								end
							end
						end
						if bestBed then return bestBed end
					end
					local best, bestValue
					local byHealth = Mode.Value ~= 'Legit' and TargetMode.Value == 'Health'
					for _, list in candidateLists() do
						for _, v in list do
							if valid(v, origin) then
								local value = byHealth and (v:GetAttribute('Health') or 0) or nearestCellDistance(v, origin)
								if not bestValue or value < bestValue then
									best, bestValue = v, value
								end
							end
						end
					end
					return best
				end

				repeat
					task.wait(1 / UpdateRate.Value)
					if not Nuker.Enabled then break end
					refreshHealthbar()
					local root = entitylib.isAlive and entitylib.character.RootPart
					local blocked = not root
						or (MouseDown.Enabled and not inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
						or (LimitItem.Enabled and not holdingBreakTool())
						or lplr:GetAttribute('DenyBlockBreak')
					if blocked then
						clearVisuals()
						continue
					end
					local ok = pcall(function()
						local origin = root.Position
						local target = pickTarget(origin)
						if not target then
							plan = nil
							clearVisuals()
							return
						end
						local cursorMode = Mode.Value == 'Legit'
						local nearFirst = cursorMode or TargetMode.Value == 'Distance'
						local blatant = not cursorMode and nearFirst and BreakType.Value == 'Blatant'
						local stale = not plan or plan.target ~= target or plan.blatant ~= blatant
						if not stale and not blatant and ((plan.anchor - origin).Magnitude > 3 or tick() - plan.time > 1) then
							stale = true
						end
						local front, frontBlock
						if not stale then
							front, frontBlock = frontOf(plan)
							stale = front == nil
						end
						if stale then
							local route = planRoute(target, origin, nearFirst)
							if not route then
								plan = nil
								clearVisuals()
								return
							end
							plan = {target = target, route = route, anchor = origin, time = tick(), blatant = blatant}
							front, frontBlock = frontOf(plan)
							if not front then
								plan = nil
								clearVisuals()
								return
							end
						end
						if (front - origin).Magnitude > 30 then
							plan = nil
							clearVisuals()
							return
						end
						drawRoute(plan.route, front)
						if cursorMode then
							local raw, hitPos = cursorBlock()
							local aimed = raw and (raw == frontBlock or raw:IsDescendantOf(frontBlock)) or (hitPos and (hitPos - front).Magnitude <= 2.6)
							if not aimed then
								setHighlight(nil)
								return
							end
						end
						setHighlight(frontBlock)
						local gap = BreakSpeed.Value
						if BedCheck.Enabled and frontBlock == target and target.Name == 'bed' then
							gap = math.max(gap, 0.3)
						end
						if tick() - lastHit >= gap and holdingCorrectTool(frontBlock) then
							lastHit = tick()
							useKitAbilities()
							hitCell(front, frontBlock, origin)
						end
					end)
					if not ok then
						plan = nil
						table.clear(breakableCache)
					end
				until not aeroAlive()
			else
				cleanupAll()
			end
		end,
		Tooltip = 'breaks beds and other stuff around u for u'
	})
	vape:Clean(cleanupAll)
	Mode = Nuker:CreateDropdown({
		Name = 'Mode',
		List = {'Normal', 'Legit'},
		Default = 'Normal',
		Tooltip = 'normal digs to the block on its own, legit only breaks what ur cursor is on',
		Function = function(val)
			if TargetMode and TargetMode.Object then
				TargetMode.Object.Visible = val ~= 'Legit'
			end
			if BreakType and BreakType.Object and TargetMode then
				BreakType.Object.Visible = val ~= 'Legit' and TargetMode.Value == 'Distance'
			end
			plan = nil
		end
	})
	TargetMode = Nuker:CreateDropdown({
		Name = 'Target Mode',
		List = {'Distance', 'Health'},
		Default = 'Distance',
		Tooltip = 'distance digs in from the side closest to u, health digs thru the weakest blocks',
		Function = function(val)
			if BreakType and BreakType.Object then
				BreakType.Object.Visible = val == 'Distance' and (not Mode or Mode.Value ~= 'Legit')
			end
			plan = nil
		end
	})
	BreakType = Nuker:CreateDropdown({
		Name = 'Break Type',
		List = {'Legit', 'Blatant'},
		Default = 'Legit',
		Darker = true,
		Tooltip = 'legit picks the best path near u and changes it as u move, blatant picks it once and sticks to it',
		Function = function()
			plan = nil
		end
	})
	Range = Nuker:CreateSlider({
		Name = 'Break range',
		Min = 1,
		Max = 30,
		Default = 30,
		Tooltip = 'how far away a block can be for u to hit it'
	})
	BreakerAngle = Nuker:CreateSlider({
		Name = 'Break Angle',
		Min = 0,
		Max = 360,
		Default = 360,
		Tooltip = 'only digs thru blocks inside this cone in front of ur cam'
	})
	BreakSpeed = Nuker:CreateSlider({
		Name = 'Break speed',
		Min = 0,
		Max = 0.3,
		Default = 0.25,
		Decimal = 100,
		Tooltip = 'wait between each hit, lower is faster'
	})
	UpdateRate = Nuker:CreateSlider({
		Name = 'Update rate',
		Min = 1,
		Max = 120,
		Default = 60,
		Tooltip = 'how often it checks for blocks'
	})
	Bed = Nuker:CreateToggle({
		Name = 'Break Bed',
		Default = true,
		Function = function(callback)
			if BedCheck and BedCheck.Object then
				BedCheck.Object.Visible = callback
			end
		end
	})
	BedCheck = Nuker:CreateToggle({
		Name = 'Bed Check',
		Darker = true,
		Tooltip = 'slows down to normal speed once ur actually hittin the bed'
	})
	LuckyBlock = Nuker:CreateToggle({
		Name = 'Break Lucky Block',
		Default = true
	})
	IronOre = Nuker:CreateToggle({
		Name = 'Break Iron Ore',
		Default = true
	})
	Snow = Nuker:CreateToggle({
		Name = 'Break Snow'
	})
	Tesla = Nuker:CreateToggle({
		Name = 'Break Tesla',
		Default = true
	})
	Hive = Nuker:CreateToggle({
		Name = 'Break Hive',
		Default = true
	})
	Pinata = Nuker:CreateToggle({
		Name = 'Break Pinata'
	})
	Crops = Nuker:CreateToggle({
		Name = 'Break Crops',
		Tooltip = 'breaks farmer cletus crops (carrot and etc)'
	})
	Effect = Nuker:CreateToggle({
		Name = 'Show Healthbar & Effects',
		Default = true,
		Function = function(callback)
			if CustomHealth and CustomHealth.Object then
				CustomHealth.Object.Visible = callback
			end
		end
	})
	CustomHealth = Nuker:CreateToggle({
		Name = 'Custom Healthbar',
		Default = true,
		Darker = true
	})
	Animation = Nuker:CreateToggle({
		Name = 'Animation',
		Tooltip = 'plays the swing animation while u dig'
	})
	SelfBreak = Nuker:CreateToggle({
		Name = 'Self Break',
		Tooltip = 'lets it break ur own bed and blocks u or ur team placed',
		Function = function()
			table.clear(breakableCache)
			plan = nil
		end
	})
	AutoTool = Nuker:CreateToggle({
		Name = 'Auto Tool',
		Default = true,
		Tooltip = 'swaps to the right tool while ur holdin a tool, off means it waits till ur holdin the right one'
	})
	LimitItem = Nuker:CreateToggle({
		Name = 'Limit to items',
		Tooltip = 'only works while ur holdin sum that can break blocks'
	})
	MouseDown = Nuker:CreateToggle({
		Name = 'Require Mouse Down',
		Tooltip = 'only digs while u hold left click'
	})
	YetiBreaker = Nuker:CreateToggle({
		Name = 'Yeti Breaker',
		Tooltip = 'pops the yeti roar whenever ur nuking'
	})
	RagnarBreaker = Nuker:CreateToggle({
		Name = 'Ragnar',
		Tooltip = 'pops the ragnar rage whenever ur nuking'
	})
	ShowPath = Nuker:CreateToggle({
		Name = 'Show Path',
		Default = true,
		Tooltip = 'shows u the blocks its diggin thru'
	})
	BlockHighlight = Nuker:CreateToggle({
		Name = 'Block Highlight',
		Function = function(callback)
			if BreakerHighlightColor and BreakerHighlightColor.Object then
				BreakerHighlightColor.Object.Visible = callback
			end
			if not callback and highlightBox then
				highlightBox.Adornee = nil
			end
		end,
		Tooltip = 'boxes the block its hittin rn'
	})
	BreakerHighlightColor = Nuker:CreateColorSlider({
		Name = 'Highlight Color',
		DefaultHue = 0.16,
		Darker = true,
		Visible = false
	})
	task.defer(function()
		CustomHealth.Object.Visible = Effect.Enabled
		BedCheck.Object.Visible = Bed.Enabled
		BreakerHighlightColor.Object.Visible = BlockHighlight.Enabled
		TargetMode.Object.Visible = Mode.Value ~= 'Legit'
		BreakType.Object.Visible = Mode.Value ~= 'Legit' and TargetMode.Value == 'Distance'
	end)
end)

run(function()
	local HitColor
	local Color
	local done = setmetatable({}, {__mode = 'k'})
	
	HitColor = vape.Categories.Legit:CreateModule({
		Name = 'HitColor',
		Function = function(callback)
			if callback then
				local function hookHighlight(v)
					local highlight = v.Character and v.Character:FindFirstChild('_DamageHighlight_')
					if highlight and not done[highlight] then
						highlight.FillColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
						highlight.FillTransparency = Color.Opacity
						done[highlight] = true
					end
				end
				for _, v in entitylib.List do hookHighlight(v) end
				HitColor:Clean(entitylib.Events.EntityAdded:Connect(hookHighlight))
			else
				for highlight in pairs(done) do
					if highlight and highlight.Parent then
						pcall(function()
							highlight.FillColor = Color3.new(1, 0, 0)
							highlight.FillTransparency = 0.4
						end)
					end
				end
				table.clear(done)
			end
		end,
		Tooltip = 'customize hit color'
	})
	Color = HitColor:CreateColorSlider({
		Name = 'Color',
		DefaultOpacity = 0.4
	})
end)

run(function()
	local HitFix

    HitFix = vape.Categories.Legit:CreateModule({
        Name = 'HitFix',
        Function = function(callback)
            local func = bedwars.SwordController.swingSwordAtMouse
            if not func then return end
            local foundIndex = nil
            pcall(function()
                for i = 1, 50 do
                    local constant = debug.getconstant(func, i)
                    if constant == 'Raycast' or constant == 'raycast' then
                        foundIndex = i
                        break
                    end
                end
            end)
            
            if foundIndex then
                pcall(function()
                    debug.setconstant(func, foundIndex, callback and 'raycast' or 'Raycast')
                end)
            end
            
            pcall(function()
                debug.setupvalue(func, 4, callback and bedwars.QueryUtil or workspace)
            end)
        end,
    })
end)

run(function()
	local DamageIndicator
	local FontOption
	local Color
	local Size
	local Anchor
	local Stroke

	local fn = bedwars.DamageIndicator

	local suc, tab = pcall(function()
		return debug.getupvalue(fn, 2)
	end)
	tab = suc and tab or {}

	local fontIndices = {}
	local strokeIndex
	do
		local ok, consts = pcall(debug.getconstants, fn)
		if ok and consts then
			for i, v in consts do
				if typeof(v) == 'EnumItem' and v.EnumType == Enum.Font then
					table.insert(fontIndices, i)
				elseif v == 'Thickness' or v == 'Enabled' then
					strokeIndex = i
				end
			end
		end
	end
	if #fontIndices == 0 then fontIndices = {86} end
	if not strokeIndex then strokeIndex = 119 end

	local oldvalues = {}
	local oldfonts = {}

	local function applyFont(fontName)
		local font = Enum.Font[fontName]
		if not font then return end
		for _, i in fontIndices do
			pcall(debug.setconstant, fn, i, font)
		end
	end

	local function applyStroke(on)
		pcall(debug.setconstant, fn, strokeIndex, on and 'Thickness' or 'Enabled')
		tab.strokeThickness = on and 1 or false
	end
	
	DamageIndicator = vape.Categories.Legit:CreateModule({
		Name = 'DamageIndicator',
		Function = function(callback)
			if callback then
				oldvalues = table.clone(tab)
				oldfonts = {}
				for _, i in fontIndices do
					oldfonts[i] = debug.getconstant(fn, i)
				end
				applyFont(FontOption.Value)
				applyStroke(Stroke.Enabled)
				tab.textSize = Size.Value
				tab.blowUpSize = Size.Value
				tab.blowUpDuration = 0
				tab.baseColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
				tab.blowUpCompleteDuration = 0
				tab.anchoredDuration = Anchor.Value
			else
				for i, v in oldvalues do
					tab[i] = v
				end
				for i, v in oldfonts do
					pcall(debug.setconstant, fn, i, v)
				end
				pcall(debug.setconstant, fn, strokeIndex, 'Thickness')
			end
		end,
		Tooltip = 'customize the damage indicator'
	})
	local fontitems = {'GothamBlack'}
	for _, v in Enum.Font:GetEnumItems() do
		if v.Name ~= 'GothamBlack' then
			table.insert(fontitems, v.Name)
		end
	end
	FontOption = DamageIndicator:CreateDropdown({
		Name = 'Font',
		List = fontitems,
		Function = function(val)
			if DamageIndicator.Enabled then
				applyFont(val)
			end
		end
	})
	Color = DamageIndicator:CreateColorSlider({
		Name = 'Color',
		DefaultHue = 0,
		Function = function(hue, sat, val)
			if DamageIndicator.Enabled then
				tab.baseColor = Color3.fromHSV(hue, sat, val)
			end
		end
	})
	Size = DamageIndicator:CreateSlider({
		Name = 'Size',
		Min = 1,
		Max = 32,
		Default = 32,
		Function = function(val)
			if DamageIndicator.Enabled then
				tab.textSize = val
				tab.blowUpSize = val
			end
		end
	})
	Anchor = DamageIndicator:CreateSlider({
		Name = 'Anchor',
		Min = 0,
		Max = 1,
		Decimal = 10,
		Function = function(val)
			if DamageIndicator.Enabled then
				tab.anchoredDuration = val
			end
		end
	})
	Stroke = DamageIndicator:CreateToggle({
		Name = 'Stroke',
		Function = function(callback)
			if DamageIndicator.Enabled then
				applyStroke(callback)
			end
		end
	})
end)

run(function()
    local DisableStreamer
    local old = {}
    local oldLevels = {}
    local oldUsernames = {}
    local levelMap = {}
    local updaterThread = nil

    DisableStreamer = vape.Categories.Legit:CreateModule({
        Name = 'DisableStreamer',
        Function = function(callback)
            if callback then
                for _, plrs in playersService:GetPlayers() do
                    if plrs == lplr then continue end
                    
                    local disguiseName = plrs:GetAttribute("DisguiseDisplayName")
                    if disguiseName and disguiseName ~= "" then
                        old[plrs] = disguiseName
                        plrs:SetAttribute("DisguiseDisplayName", "")
                    end

                    local disguiseUsername = plrs:GetAttribute("DisguiseUsername")
                    if disguiseUsername and disguiseUsername ~= "" then
                        oldUsernames[plrs] = disguiseUsername
                        plrs:SetAttribute("DisguiseUsername", "")
                    end

                    local playerLevel = plrs:GetAttribute("PlayerLevel")
                    if playerLevel then
                        oldLevels[plrs] = playerLevel
                        levelMap[plrs.Name] = playerLevel
                    end
                end

                pcall(function()
                    bedwars.StreamerModeController:updateNametags(true)
                end)

                local running = true
                updaterThread = task.spawn(function()
                    while running do
                        local tabList = lplr.PlayerGui:FindFirstChild("TabListScreenGui")
                        if tabList then
                            for _, desc in tabList:GetDescendants() do
                                if desc:IsA("TextLabel") and desc.Name == "PlayerLevel" then
                                    local text = desc.Text
                                    if text:find("%[%?%]") then
                                        local siblingName = desc.Parent:FindFirstChild("PlayerName")
                                        if siblingName then
                                            local currentNameText = siblingName.Text
                                            local cleanName = currentNameText:gsub("^@", ""):match("^%s*(.-)%s*$")
                                            
                                            local matchedPlayer = nil
                                            for _, plr in playersService:GetPlayers() do
                                                if plr == lplr then continue end
                                                if cleanName == plr.Name or cleanName == plr.DisplayName then
                                                    matchedPlayer = plr
                                                    break
                                                end
                                            end
                                            
                                            if matchedPlayer then
                                                local realLevel = levelMap[matchedPlayer.Name]
                                                if realLevel then
                                                    desc.Text = '<font color="rgb(255,255,255)">[' .. tostring(realLevel) .. ']</font>'
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        task.wait(0.3)
                    end
                end)

            else
                if updaterThread then
                    task.cancel(updaterThread)
                    updaterThread = nil
                end
                
                for _, plrs in playersService:GetPlayers() do
                    if plrs == lplr then continue end
                    
                    if old[plrs] then
                        plrs:SetAttribute("DisguiseDisplayName", old[plrs])
                        old[plrs] = nil
                    end
                    
                    if oldUsernames[plrs] then
                        plrs:SetAttribute("DisguiseUsername", oldUsernames[plrs])
                        oldUsernames[plrs] = nil
                    end
                    
                    if oldLevels[plrs] then
                        plrs:SetAttribute("PlayerLevel", oldLevels[plrs])
                        oldLevels[plrs] = nil
                    end
                end
                
                pcall(function()
                    bedwars.StreamerModeController:updateNametags(true)
                end)
                
                task.spawn(function()
                    local tabList = lplr.PlayerGui:FindFirstChild("TabListScreenGui")
                    if tabList then
                        tabList.Enabled = false
                        task.wait()
                        tabList.Enabled = true
                    end
                end)
            end
        end,
        Tooltip = 'sisable people streamer mode'
    })
end)

run(function()
	local WhiteHits
	WhiteHits = vape.Categories.Legit:CreateModule({
		Name = "WhiteHits",
		Function = function(callback)
			if callback then
				local function killHighlight(obj)
					if obj and obj.Name == '_DamageHighlight_' then
						pcall(function()
							obj.Enabled = false
							obj:Destroy()
						end)
					end
				end
				local function sweep(model)
					if not model then return end
					for _, obj in model:GetDescendants() do
						killHighlight(obj)
					end
				end
				WhiteHits:Clean(workspace.DescendantAdded:Connect(killHighlight))
				for _, plr in playersService:GetPlayers() do
					sweep(plr.Character)
				end
				for _, v in entitylib.List do
					sweep(v.Character)
				end
			end
		end,
		Tooltip = 'stops that red flash when ppl get hit so hits stay "white"'
	})
end)


run(function()
	local ContractKits
	local icons = {}

	local function clear()
		for label, icon in icons do
			icon:Destroy()
			icons[label] = nil
		end
	end

	local function getNameLabel(card)
		for _, section in card:GetChildren() do
			if section:IsA('GuiObject') and section.LayoutOrder == 1 then
				local nameLabel
				local teamLabel

				for _, child in section:GetChildren() do
					if child:IsA('TextLabel') then
						if child.LayoutOrder == 0 then
							nameLabel = child
						elseif child.LayoutOrder == 1 then
							teamLabel = child
						end
					end
				end

				if nameLabel then
					return section, nameLabel, teamLabel
				end
			end
		end
	end

	local function getSwordIcon(card, section)
		local best
		local bestDistance = math.huge

		for _, child in card:GetDescendants() do
			if child:IsA('ImageLabel') and child.Name ~= 'ContractKitIcon' and child.Visible then
				local size = child.AbsoluteSize
				if size.X >= 12 and size.X <= 40 and size.Y >= 12 and size.Y <= 40 then
					local dx = section.AbsolutePosition.X - child.AbsolutePosition.X
					if dx >= 0 and dx < bestDistance then
						bestDistance = dx
						best = child
					end
				end
			end
		end

		return best
	end

	local function update()
		local state = bedwars.Store and bedwars.Store:getState()
		local kitState = state and state.Kit
		if not kitState then return end

		local seen = {}
		local available = kitState.availableContracts or {}

		for _, header in lplr.PlayerGui:GetDescendants() do
			if not header:IsA('TextLabel') then continue end

			local active = header.Text == 'ACTIVE CONTRACT'
			local picking = header.Text:find('CONTRACTS <font', 1, true) == 1

			if not active and not picking then continue end

			local container = header.Parent
			if not container then continue end

			for _, card in container:GetChildren() do
				if not card:IsA('Frame') or card.LayoutOrder < 2 then
					continue
				end

				local contract = active and kitState.activeContract or available[card.LayoutOrder - 1]
				local target = contract and contract.target

				if typeof(target) ~= 'Instance' or not target:IsA('Player') then
					continue
				end

				local section, nameLabel, teamLabel = getNameLabel(card)
				if not nameLabel then continue end

				seen[nameLabel] = true

				local icon = icons[nameLabel]
				if not icon or not icon.Parent then
					icon = Instance.new('ImageLabel')
					icon.Name = 'ContractKitIcon'
					icon.Size = UDim2.fromOffset(24, 24)
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.BackgroundTransparency = 1
					icon.BorderSizePixel = 0
					icon.ImageTransparency = 0.1
					icon.ScaleType = Enum.ScaleType.Fit
					icon.ZIndex = nameLabel.ZIndex + 3
					icon.Parent = card
					icons[nameLabel] = icon
				end

				local swordIcon = getSwordIcon(card, section)

				if swordIcon then
					local cardPos = card.AbsolutePosition
					local swordPos = swordIcon.AbsolutePosition
					local swordSize = swordIcon.AbsoluteSize
					local size = math.max(swordSize.X, swordSize.Y) + 4

					icon.Size = UDim2.fromOffset(size, size)
					icon.Position = UDim2.fromOffset(
						math.floor(swordPos.X - cardPos.X + swordSize.X / 2),
						math.floor(swordPos.Y - cardPos.Y + swordSize.Y / 2)
					)
				else
					local targetLabel = teamLabel or nameLabel
					local y = targetLabel.AbsolutePosition.Y - card.AbsolutePosition.Y
					y += targetLabel.AbsoluteSize.Y / 2

					icon.Size = UDim2.fromOffset(24, 24)
					icon.Position = UDim2.fromOffset(18, math.floor(y))
				end

				icon.Image = resolvePlayerKitImage(target)
				icon.Visible = true
			end
		end

		for label, icon in icons do
			if not seen[label] then
				icon:Destroy()
				icons[label] = nil
			end
		end
	end

	ContractKits = vape.Categories.Kits:CreateModule({
		Name = 'ContractKitRender',
		Function = function(enabled)
			local alive = newRun(ContractKits)

			if enabled then
				task.spawn(function()
					while alive() do
						update()
						task.wait(0.25)
					end
				end)
			else
				clear()
			end
		end,
		Tooltip = 'shows player kits in caitlyn contracts'
	})
end)

run(function()
    local Caitlyn
    local MethodDropdown
    local LowHealthSlider
    local ExecuteRangeSlider
    local HitRangeSlider
    local ProximityRangeSlider
    local connections = {}
    local Players = playersService
    local lplr = Players.LocalPlayer
    local currentTarget = nil
    local lastHitTime = 0
    local lastContractSelect = 0
    
    local function selectContract(targetPlayer)
        if not entitylib.isAlive then return false end
        if tick() - lastContractSelect < 0.1 then return false end
        
        local storeState = bedwars.Store:getState()
        local activeContract = storeState.Kit.activeContract
        local availableContracts = storeState.Kit.availableContracts or {}
        
        if activeContract then return false end
        if #availableContracts == 0 then return false end
        
        for _, contract in pairs(availableContracts) do
            if contract.target == targetPlayer then
                bedwars.Client:Get(remotes.BloodAssassinSelectContract):SendToServer({
                    contractId = contract.id
                })
                lastContractSelect = tick()
                return true
            end
        end
        return false
    end
    
    local function executeOnLowHealth()
        if not currentTarget or tick() - lastHitTime > 3 then
            currentTarget = nil
            return
        end
        
        if not currentTarget.Character then return end
        
        local humanoid = currentTarget.Character:FindFirstChild("Humanoid")
        local rootPart = currentTarget.Character:FindFirstChild("HumanoidRootPart")
        
        if humanoid and rootPart and lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") then
            local health = humanoid.Health
            local distance = (lplr.Character.HumanoidRootPart.Position - rootPart.Position).Magnitude
            
            if health > 0 and health <= LowHealthSlider.Value and distance <= ExecuteRangeSlider.Value then
                selectContract(currentTarget)
            end
        end
    end
    
    local function contractOnHit()
        if not currentTarget or tick() - lastHitTime > 0.5 then
            currentTarget = nil
            return
        end
        
        if not currentTarget.Character then return end
        
        local rootPart = currentTarget.Character:FindFirstChild("HumanoidRootPart")
        
        if rootPart and lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (lplr.Character.HumanoidRootPart.Position - rootPart.Position).Magnitude
            
            if distance <= HitRangeSlider.Value then
                selectContract(currentTarget)
            end
        end
    end
    
    local function proximityContract()
        if not entitylib.isAlive then return end
        
        local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end
        
        local closestPlayer = nil
        local closestDistance = ProximityRangeSlider.Value
        
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= lplr and player.Character then
                local theirRoot = player.Character:FindFirstChild("HumanoidRootPart")
                local humanoid = player.Character:FindFirstChild("Humanoid")
                
                if theirRoot and humanoid and humanoid.Health > 0 then
                    local distance = (myRoot.Position - theirRoot.Position).Magnitude
                    
                    if distance < closestDistance then
                        closestDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
        
        if closestPlayer then
            selectContract(closestPlayer)
        end
    end
    
    Caitlyn = vape.Categories.Kits:CreateModule({
        Name = 'AutoCaitlyn',
        Function = function(callback)
            local aeroAlive = newRun(Caitlyn)
            if callback then
                local damageConnection = vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
                    if not entitylib.isAlive then return end
                    
                    local attacker = playersService:GetPlayerFromCharacter(damageTable.fromEntity)
                    local victim = playersService:GetPlayerFromCharacter(damageTable.entityInstance)
                
                    if attacker == lplr and victim and victim ~= lplr then
                        currentTarget = victim
                        lastHitTime = tick()
                    end
                end)
                table.insert(connections, damageConnection)
                
                task.spawn(function()
                    repeat
                        if entitylib.isAlive then
                            local method = MethodDropdown.Value
                            
                            if method == "Execute on Low HP" then
                                executeOnLowHealth()
                            elseif method == "Contract on Hit" then
                                contractOnHit()
                            elseif method == "Proximity Select" then
                                proximityContract()
                            end
                        end
                        task.wait(0.1)
                    until not aeroAlive()
                end)
            else
                for _, conn in pairs(connections) do
                    if typeof(conn) == "RBXScriptConnection" then
                        conn:Disconnect()
                    end
                end
                table.clear(connections)
                
                currentTarget = nil
                lastHitTime = 0
            end
        end,
        Tooltip = 'auto contract selection for caitlyn'
    })
    
    MethodDropdown = Caitlyn:CreateDropdown({
        Name = 'Method',
        List = {"Execute on Low HP", "Contract on Hit", "Proximity Select"},
        Default = "Execute on Low HP",
        Tooltip = 'contract selection method',
        Function = function(value)
            LowHealthSlider.Object.Visible = (value == "Execute on Low HP")
            ExecuteRangeSlider.Object.Visible = (value == "Execute on Low HP")
            HitRangeSlider.Object.Visible = (value == "Contract on Hit")
            ProximityRangeSlider.Object.Visible = (value == "Proximity Select")
        end
    })
    
    LowHealthSlider = Caitlyn:CreateSlider({
        Name = 'Select HP',
        Min = 10,
        Max = 100,
        Default = 30,
        Tooltip = 'hp value to execute contract'
    })
    
    ExecuteRangeSlider = Caitlyn:CreateSlider({
        Name = 'Select Range',
        Min = 5,
        Max = 50,
        Default = 20,
        Suffix = ' studs',
        Tooltip = 'range to select contract'
    })
    
    HitRangeSlider = Caitlyn:CreateSlider({
        Name = 'Hit Range',
        Min = 10,
        Max = 200,
        Default = 100,
        Suffix = ' studs',
        Tooltip = 'max range to select a contract when hitting the player'
    })
    
    ProximityRangeSlider = Caitlyn:CreateSlider({
        Name = 'Proximity Range',
        Min = 10,
        Max = 200,
        Default = 50,
        Suffix = ' studs',
        Tooltip = 'range to auto select nearby players'
    })
    
    LowHealthSlider.Object.Visible = true
    ExecuteRangeSlider.Object.Visible = true
    HitRangeSlider.Object.Visible = false
    ProximityRangeSlider.Object.Visible = false
end)

run(function()
    local AutoMetal
    local CollectionToggle
    local LimitToItem
    local Animation
    local CollectionDelay
    local DelaySlider
    local RangeSlider
    local ESPToggle
    local ESPNotify
    local ESPBackground
    local ESPColor
    local HoldingCheck
    local DistanceCheck
    local DistanceLimit
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local Reference = {}
    local lastNotification = 0
    local notificationPending = false
    local spawnQueue = {}
    local notificationCooldown = 1
    local collectionActive = false
    local collectedMetals = {}
    local animationDebounce = {}

    local function isHoldingAutoMetal()
        if not store.hand or not store.hand.tool then return false end
        return store.hand.tool.Name == 'metal_detector'
    end

    local function sendNotification(count)
        notif("Metal ESP", string.format("%d metals spawned", count), 3)
    end

    local function processSpawnQueue()
        if #spawnQueue == 0 then return end
        local currentTime = tick()
        local remaining = notificationCooldown - (currentTime - lastNotification)
        if remaining <= 0 then
            sendNotification(#spawnQueue)
            lastNotification = currentTime
            spawnQueue = {}
            notificationPending = false
        elseif not notificationPending then
            notificationPending = true
            task.delay(remaining, function()
                if #spawnQueue > 0 then
                    sendNotification(#spawnQueue)
                    lastNotification = tick()
                    spawnQueue = {}
                end
                notificationPending = false
            end)
        end
    end

    local function getProperImage()
        return bedwars.getIcon({itemType = 'iron'}, true)
    end

    local function Added(v)
        if Reference[v] then return end
        local _bpUserId = v:GetAttribute('PlacedByUserId')
        if _bpUserId then
            local _bpOk, _bpOwner = pcall(function() return playersService:GetPlayerByUserId(_bpUserId) end)
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'hidden-metal'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = ESPBackground.Enabled
        
        local image = Instance.new('ImageLabel')
        image.Size = UDim2.fromOffset(36, 36)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.BackgroundColor3 = Color3.fromHSV(ESPColor.Hue, ESPColor.Sat, ESPColor.Value)
        image.BackgroundTransparency = 1 - (ESPBackground.Enabled and ESPColor.Opacity or 0)
        image.BorderSizePixel = 0
        image.Image = getProperImage()
        image.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = image
        
        Reference[v] = billboard
        
        if ESPNotify.Enabled then
            table.insert(spawnQueue, {item = 'metal', time = tick()})
            processSpawnQueue()
        end
    end

    local function Removed(v)
        if Reference[v] then
            Reference[v]:Destroy()
            Reference[v] = nil
        end
    end

    local function setupESP()
        for _, v in collectionService:GetTagged('hidden-metal') do
            if v:IsA("Model") and v.PrimaryPart then
                Added(v.PrimaryPart)
            end
        end

        AutoMetal:Clean(collectionService:GetInstanceAddedSignal('hidden-metal'):Connect(function(v)
            if v:IsA("Model") and v.PrimaryPart then
                Added(v.PrimaryPart)
            end
        end))

        AutoMetal:Clean(collectionService:GetInstanceRemovedSignal('hidden-metal'):Connect(function(v)
            if v.PrimaryPart then
                Removed(v.PrimaryPart)
            end
        end))

        local _mdLastUpdate = 0
        AutoMetal:Clean(runService.RenderStepped:Connect(function()
            if not ESPToggle.Enabled then return end
            local _now = tick()
            if _now - _mdLastUpdate < 0.1 then return end
            _mdLastUpdate = _now
            
            for v, billboard in pairs(Reference) do
                if not v or not v.Parent then
                    Removed(v)
                    continue
                end

                local shouldShow = true

                if HoldingCheck.Enabled and not isHoldingAutoMetal() then
                    shouldShow = false
                end

                if shouldShow and DistanceCheck.Enabled and entitylib.isAlive then
                    local distance = (entitylib.character.RootPart.Position - v.Position).Magnitude
                    if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
                        shouldShow = false
                    end
                end

                billboard.Enabled = shouldShow
            end
        end))
    end

    local function collectMetal(metalModel)
        local metalId = metalModel:GetAttribute('Id')
        if not metalId then return false end
        if collectedMetals[metalId] then return false end

        collectedMetals[metalId] = true

        local success = pcall(function()
            bedwars.Client:Get(remotes.CollectCollectableEntity).instance:FireServer({ id = metalId })
        end)

        if Animation.Enabled then
            local currentTick = tick()
            if not animationDebounce[metalId] or (currentTick - animationDebounce[metalId]) >= 0.5 then
                animationDebounce[metalId] = currentTick
                pcall(function()
                    bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.SHOVEL_DIG)
                    bedwars.SoundManager:playSound(bedwars.SoundList.SNAP_TRAP_CONSUME_MARK)
                end)
            end
        end

        task.delay(2, function()
            collectedMetals[metalId] = nil
            animationDebounce[metalId] = nil
        end)
        
        return success
    end

    local function startAutoCollect()
        if collectionActive then return end
        collectionActive = true
        
        task.spawn(function()
            while AutoMetal.Enabled and CollectionToggle.Enabled and collectionActive do
                if not entitylib.isAlive then 
                    task.wait(0.5)
                    continue 
                end
                
                if LimitToItem.Enabled and not isHoldingAutoMetal() then 
                    task.wait(0.5)
                    continue 
                end
                
                local localPosition = entitylib.character.RootPart.Position
                local range = RangeSlider.Value
                local collectedThisCycle = false
								
				for _, v in collectionService:GetTagged('hidden-metal') do
					if not AutoMetal.Enabled or not CollectionToggle.Enabled or not collectionActive then 
						break 
					end
					
					if v:IsA("Model") and v.PrimaryPart then
						local distance = (localPosition - v.PrimaryPart.Position).Magnitude
						
						if distance <= range then
							if CollectionDelay.Enabled and DelaySlider.Value > 0 then
								task.wait(DelaySlider.Value)
							end
							if collectMetal(v) then
								collectedThisCycle = true
								if Animation.Enabled then
									task.wait(0.15)
								end
							end
						end
					end
				end
                
                task.wait(collectedThisCycle and (Animation.Enabled and 0.3 or 0.05) or 0.5)
            end
            
            collectionActive = false
        end)
    end

    local function stopAutoCollect()
        collectionActive = false
        table.clear(collectedMetals)
        table.clear(animationDebounce)
    end

    AutoMetal = vape.Categories.Kits:CreateModule({
        Name = 'AutoMetal',
        Function = function(callback)
            if callback then
                if ESPToggle.Enabled then 
                    setupESP() 
                end
                if CollectionToggle.Enabled then
                    startAutoCollect()
                end
            else
                stopAutoCollect()
                Folder:ClearAllChildren()
                table.clear(Reference)
                spawnQueue = {}
                lastNotification = 0
                notificationPending = false
            end
        end,
        Tooltip = 'automatically collects metal loot and esp'
    })
    
    CollectionToggle = AutoMetal:CreateToggle({
        Name = 'Auto Collect',
        Default = true,
        Function = function(callback)
            if LimitToItem and LimitToItem.Object then LimitToItem.Object.Visible = callback end
            if Animation and Animation.Object then Animation.Object.Visible = callback end
            if CollectionDelay and CollectionDelay.Object then CollectionDelay.Object.Visible = callback end
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback and CollectionDelay and CollectionDelay.Enabled
            end
            
            if AutoMetal.Enabled then
                if callback then
                    startAutoCollect()
                else
                    stopAutoCollect()
                end
            end
        end
    })
    
    LimitToItem = AutoMetal:CreateToggle({
        Name = 'Limit to Items',
        Default = true,
    })
    
    Animation = AutoMetal:CreateToggle({
        Name = 'Animation',
        Default = true,
    })
    
    CollectionDelay = AutoMetal:CreateToggle({
        Name = 'Collection Delay',
        Default = false,
        Function = function(callback)
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback
            end
        end
    })
    
    DelaySlider = AutoMetal:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
        Visible = false,
    })
    
    RangeSlider = AutoMetal:CreateSlider({
        Name = 'Range',
        Min = 1, 
        Max = 10,
        Default = 10,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    ESPToggle = AutoMetal:CreateToggle({
        Name = 'Metal ESP',
        Default = false,
        Function = function(callback)
            if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = callback end
            if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = callback end
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            if HoldingCheck and HoldingCheck.Object then HoldingCheck.Object.Visible = callback end
            if DistanceCheck and DistanceCheck.Object then DistanceCheck.Object.Visible = callback end
            if DistanceLimit and DistanceLimit.Object then
                DistanceLimit.Object.Visible = (callback and DistanceCheck.Enabled)
            end

            if not callback then
                if ESPColor and ESPColor.Object then
                    ESPColor.Object.Visible = false
                end
                if DistanceLimit and DistanceLimit.Object then
                    DistanceLimit.Object.Visible = false
                end
            else
                if ESPBackground and ESPBackground.Enabled then
                    if ESPColor and ESPColor.Object then
                        ESPColor.Object.Visible = true
                    end
                end
                if DistanceCheck and DistanceCheck.Enabled then
                    if DistanceLimit and DistanceLimit.Object then
                        DistanceLimit.Object.Visible = true
                    end
                end
            end
            
            if AutoMetal.Enabled then
                if callback then setupESP() else
                    Folder:ClearAllChildren()
                    table.clear(Reference)
                end
            end
        end
    })
    
    ESPNotify = AutoMetal:CreateToggle({
        Name = 'Notify',
        Default = false,
    })
    
    ESPBackground = AutoMetal:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    local blur = v:FindFirstChild("Blur")
                    if blur then blur.Visible = callback end
                    v.ImageLabel.BackgroundTransparency = 1 - (callback and ESPColor.Opacity or 0)
                end
            end
        end
    })
    
    ESPColor = AutoMetal:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    v.ImageLabel.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Darker = true
    })
    
    HoldingCheck = AutoMetal:CreateToggle({
        Name = 'Holding Detector',
        Default = false,
    })
    
    DistanceCheck = AutoMetal:CreateToggle({
        Name = 'Distance Check',
        Default = false,
        Function = function(callback)
            if DistanceLimit and DistanceLimit.Object then
                DistanceLimit.Object.Visible = callback
            end
        end
    })
    
    DistanceLimit = AutoMetal:CreateTwoSlider({
        Name = 'Metal Distance',
        Min = 0,
        Max = 256,
        DefaultMin = 0,
        DefaultMax = 64,
        Darker = true,
    })

    task.defer(function()
        if DelaySlider and DelaySlider.Object then
            DelaySlider.Object.Visible = CollectionDelay.Enabled  
        end
        local espOn = ESPToggle and ESPToggle.Enabled
        if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = espOn end
        if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = espOn end
        if ESPColor and ESPColor.Object then ESPColor.Object.Visible = (espOn and ESPBackground.Enabled) end
        if HoldingCheck and HoldingCheck.Object then HoldingCheck.Object.Visible = espOn end
        if DistanceCheck and DistanceCheck.Object then DistanceCheck.Object.Visible = espOn end
        if DistanceLimit and DistanceLimit.Object then DistanceLimit.Object.Visible = (espOn and DistanceCheck.Enabled) end
    end)
end)

run(function()
	local InfStamina
	local dismountRemote

	task.spawn(function()
		local net = getNetManaged(true)
		dismountRemote = net:WaitForChild('CatWallClimbDismount')
	end)

	InfStamina = vape.Categories.Kits:CreateModule({
		Name = 'InfStamina',
		Function = function(callback)
			local aeroAlive = newRun(InfStamina)
			if callback then
				cleanThread(InfStamina, task.spawn(function()
					repeat
						if entitylib.isAlive and dismountRemote then
							pcall(function()
								dismountRemote:FireServer({direction = vector.create(-0, -0, -1)})
							end)
						end
						task.wait(0.25)
					until not aeroAlive()
				end))
			end
		end,
		Tooltip = 'infinite stamina with yamini kit'
	})
end)

run(function()
	local KitSpy
	local BeehiveToggle, BeehiveBackground, BeehiveColor
	local LuciaToggle, LuciaIgnoreTeammates, LuciaDisplayName
	local FishermanToggle, FishermanIgnoreTeammates
	local BountyHunterToggle, BountyTargetToggle, BountyLootToggle
	local DrillToggle, DrillNotify, DrillESPToggle
	local beeFolder = Instance.new('Folder')
	local drillFolder = Instance.new('Folder')
	beeFolder.Name = 'KitSpyBeehives'
	drillFolder.Name = 'KitSpyDrills'
	beeFolder.Parent = vape.gui
	drillFolder.Parent = vape.gui
	local hiveRefs = {}
	local hiveConnections = {}
	local pinataConnections = {}
	local fishConnections = {}
	local bountyConnections = {}
	local drillConnections = {}
	local pinatas = {}
	local bounties = {}
	local drills = {}
	local hiveScan, pinataScan, drillScan
	local fishGeneration, bountyGeneration = 0, 0
	local names = {
		beehive = true,
		beekeeper_chroma_beehive = true,
		beekeeper_meadow_beehive = true
	}
	local fishNames = {
		fish_iron = 'Iron Fish',
		fish_diamond = 'Diamond Fish',
		fish_emerald = 'Emerald Fish',
		fish_special = 'Special Fish',
		fish_gold = 'Gold Fish'
	}

	local function bind(group, signal, callback)
		local connection = signal:Connect(callback)
		table.insert(group, connection)
		return connection
	end

	local function disconnect(group)
		for _, connection in group do
			connection:Disconnect()
		end
		table.clear(group)
	end

	local function displayName(player)
		if not player then return 'Unknown' end
		return LuciaDisplayName and LuciaDisplayName.Enabled and player.DisplayName or player.Name
	end

	local function teamName(player)
		return player and player.Team and player.Team.Name or 'Unknown'
	end

	local function ownerId(object)
		if not object then return nil end

		local id = object:GetAttribute('PlacedByUserId') or object:GetAttribute('PlacerId')

		if id == nil and object:IsA('Model') and object.PrimaryPart then
			id = object.PrimaryPart:GetAttribute('PlacedByUserId') or object.PrimaryPart:GetAttribute('PlacerId')
		end

		if id == nil and object.Parent and object.Parent:IsA('Model') then
			id = object.Parent:GetAttribute('PlacedByUserId') or object.Parent:GetAttribute('PlacerId')
		end

		return tonumber(id)
	end

	local function isOwnHive(hive)
		return ownerId(hive) == lplr.UserId
	end

	local function hivePart(hive)
		if hive:IsA('BasePart') then return hive end

		if hive:IsA('Model') then
			return hive.PrimaryPart or hive:FindFirstChildWhichIsA('BasePart', true)
		end

		return nil
	end

	local function isHive(hive)
		if not hive:IsA('Model') and not hive:IsA('BasePart') then return false end
		return names[hive.Name:lower()] == true or collectionService:HasTag(hive, 'beehive')
	end

	local function canonicalHive(hive)
		local parent = hive.Parent

		if hive:IsA('BasePart') and parent and parent:IsA('Model') and names[parent.Name:lower()] then
			return parent
		end

		return hive
	end

	local function removeHive(hive)
		local ref = hiveRefs[hive]
		if not ref then return end

		hiveRefs[hive] = nil
		disconnect(ref.connections)
		ref.gui:Destroy()
	end

	local function updateHive(hive)
		local ref = hiveRefs[hive]
		if not ref then return end

		if not hive:IsDescendantOf(workspace) or isOwnHive(hive) then
			removeHive(hive)
			return
		end

		local part = hivePart(hive)
		if part then ref.gui.Adornee = part end

		local id = ownerId(hive)
		local player = id and playersService:GetPlayerByUserId(id)

		ref.owner.Text = player and player.Name or (id and 'Player' or 'Unknown')

		local level = hive:GetAttribute('Level')
		if level == nil and part then
			level = part:GetAttribute('Level')
		end

		ref.level.Text = tostring(level or 0)
	end

	local function addHive(hive)
		hive = canonicalHive(hive)

		if not KitSpy.Enabled or not BeehiveToggle.Enabled then return end
		if not hive:IsDescendantOf(workspace) or not isHive(hive) or isOwnHive(hive) then return end

		if hiveRefs[hive] then
			updateHive(hive)
			return
		end

		local part = hivePart(hive)

		if not part then
			task.delay(0.2, function()
				if KitSpy.Enabled and BeehiveToggle.Enabled and hive.Parent then
					addHive(hive)
				end
			end)
			return
		end

		local gui = Instance.new('BillboardGui')
		gui.Name = 'beehive-spy'
		gui.Size = UDim2.fromOffset(120, 40)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = part
		gui.Parent = beeFolder

		local frame = Instance.new('Frame')
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.fromHSV(
			BeehiveColor and BeehiveColor.Hue or 0,
			BeehiveColor and BeehiveColor.Sat or 0,
			BeehiveColor and BeehiveColor.Value or 1
		)
		frame.BackgroundTransparency = BeehiveBackground and BeehiveBackground.Enabled
			and (1 - (BeehiveColor and BeehiveColor.Opacity or 0.5)) or 1
		frame.Parent = gui

		Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 6)

		local owner = Instance.new('TextLabel')
		owner.Name = 'OwnerName'
		owner.Position = UDim2.fromOffset(0, -17)
		owner.Size = UDim2.new(1, 0, 0, 17)
		owner.BackgroundTransparency = 1
		owner.Font = Enum.Font.GothamBold
		owner.TextColor3 = Color3.new(1, 1, 1)
		owner.TextStrokeTransparency = 0.4
		owner.TextSize = 12
		owner.Parent = gui

		local icon = Instance.new('ImageLabel')
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(22, 22)
		icon.Position = UDim2.new(0, 6, 0.5, -11)

		local ok, asset = pcall(function()
			return bedwars.getIcon({itemType = 'beehive'}, true)
		end)

		icon.Image = ok and asset or ''
		icon.Parent = frame

		local level = Instance.new('TextLabel')
		level.Name = 'Level'
		level.Size = UDim2.new(0, 35, 1, 0)
		level.Position = UDim2.new(1, -38, 0, 0)
		level.BackgroundTransparency = 1
		level.Font = Enum.Font.GothamBold
		level.TextColor3 = Color3.new(1, 1, 1)
		level.TextStrokeTransparency = 0.4
		level.TextSize = 16
		level.Parent = frame

		local ref = {
			gui = gui,
			frame = frame,
			owner = owner,
			level = level,
			connections = {}
		}

		hiveRefs[hive] = ref

		local function changed()
			if hiveRefs[hive] == ref then
				updateHive(hive)
			end
		end

		for _, attr in {'Level', 'PlacedByUserId', 'PlacerId'} do
			bind(ref.connections, hive:GetAttributeChangedSignal(attr), changed)

			if part ~= hive then
				bind(ref.connections, part:GetAttributeChangedSignal(attr), changed)
			end
		end

		bind(ref.connections, hive.AncestryChanged, changed)
		changed()
	end

	local function styleHives()
		local visible = BeehiveBackground and BeehiveBackground.Enabled
		local hue = BeehiveColor and BeehiveColor.Hue or 0
		local sat = BeehiveColor and BeehiveColor.Sat or 0
		local val = BeehiveColor and BeehiveColor.Value or 1
		local opacity = BeehiveColor and BeehiveColor.Opacity or 0.5

		for _, ref in hiveRefs do
			ref.frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
			ref.frame.BackgroundTransparency = visible and 1 - opacity or 1
		end
	end

	local function stopHives()
		if hiveScan then
			hiveScan.cancelled = true
			hiveScan = nil
		end

		disconnect(hiveConnections)

		for hive in hiveRefs do
			removeHive(hive)
		end
	end

	local function startHives()
		stopHives()

		local function check(object)
			if KitSpy.Enabled and BeehiveToggle.Enabled and isHive(object) then
				addHive(object)
			end
		end

		for _, object in collectionService:GetTagged('beehive') do
			check(object)
		end

		hiveScan = scanDescendants(workspace, check)

		bind(hiveConnections, collectionService:GetInstanceAddedSignal('beehive'), function(object)
			task.defer(check, object)
		end)

		bind(hiveConnections, collectionService:GetInstanceRemovedSignal('beehive'), function(object)
			if not object:IsDescendantOf(workspace) then
				removeHive(canonicalHive(object))
			end
		end)

		bind(hiveConnections, workspace.DescendantAdded, function(object)
			if names[object.Name:lower()] then
				task.defer(check, object)
			end
		end)

		bind(hiveConnections, workspace.DescendantRemoving, function(object)
			if hiveRefs[object] then
				removeHive(object)
			end
		end)

		bind(hiveConnections, playersService.PlayerAdded, function()
			for hive in hiveRefs do
				updateHive(hive)
			end
		end)

		styleHives()
	end

	local function candy(pinata)
		return tonumber(pinata:GetAttribute('Coin')) or 0
	end

	local function pinataOwner(pinata)
		local id = ownerId(pinata) or ownerId(pinata.Parent)
		return id and playersService:GetPlayerByUserId(id) or nil
	end

	local function ignorePinata(pinata)
		if not LuciaIgnoreTeammates.Enabled then return false end

		local id = ownerId(pinata) or ownerId(pinata.Parent)
		local owner = id and playersService:GetPlayerByUserId(id)

		return id == lplr.UserId or owner ~= nil and owner.Team == lplr.Team
	end

	local function addPinata(object)
		if not object:IsA('BasePart') or object.Name ~= 'pinata' or pinatas[object] then return end
		if ignorePinata(object) then return end

		pinatas[object] = {
			amount = candy(object),
			placed = tick(),
			owner = pinataOwner(object)
		}
	end

	local function stopLucia()
		if pinataScan then
			pinataScan.cancelled = true
			pinataScan = nil
		end

		disconnect(pinataConnections)
		table.clear(pinatas)
	end

	local function startLucia()
		stopLucia()

		pinataScan = scanDescendants(workspace, addPinata)

		bind(pinataConnections, workspace.DescendantAdded, function(object)
			if object:IsA('BasePart') and object.Name == 'pinata' then
				task.delay(0.2, function()
					if KitSpy.Enabled and LuciaToggle.Enabled and object.Parent then
						addPinata(object)
					end
				end)
			end
		end)

		local ok, remote = pcall(function()
			return bedwars.Client:Get('PiggyBankPop')
		end)

		if ok and remote then
			local connected, event = pcall(function()
				return remote:Connect(function(data)
					if not KitSpy.Enabled or not LuciaToggle.Enabled then return end

					local player = data.awardedPlayer

					if not player or LuciaIgnoreTeammates.Enabled and (player == lplr or player.Team == lplr.Team) then
						return
					end

					local success, rewards = pcall(function()
						local util = require(
							replicatedStorage.TS.games.bedwars.kit.kits['piggy-bank']['piggy-bank-util']
						).PiggyBankUtil

						return util:getRewardsFromCoins(data.coins)
					end)

					if not success or type(rewards) ~= 'table' then return end

					local amounts = {iron = 0, diamond = 0, emerald = 0}

					for _, reward in rewards do
						if amounts[reward.itemType] then
							amounts[reward.itemType] += reward.amount or 0
						end
					end

					notif('KitSpy', string.format(
						'%s (%s) opened their pinata: %d iron, %d diamond, %d emerald',
						displayName(player),
						teamName(player),
						amounts.iron,
						amounts.diamond,
						amounts.emerald
					), 8)

					for part, entry in pinatas do
						if entry.owner == player then
							pinatas[part] = nil
						end
					end
				end)
			end)

			if connected and event then
				table.insert(pinataConnections, event)
			end
		end

		local elapsed = 0

		bind(pinataConnections, runService.Heartbeat, function(dt)
			elapsed += dt
			if elapsed < 0.1 then return end
			elapsed = 0

			for part, entry in pinatas do
				if not part.Parent then
					if entry.owner and tick() - entry.placed > 2 then
						notif('KitSpy', displayName(entry.owner) .. ' (' .. teamName(entry.owner) .. ') broke their pinata', 5)
					end

					pinatas[part] = nil
				else
					if not entry.owner then
						entry.owner = pinataOwner(part)
					end

					if ignorePinata(part) then
						pinatas[part] = nil
						continue
					end

					local amount = candy(part)

					if amount > entry.amount and entry.owner then
						notif('KitSpy', string.format(
							'%s deposited %d candy (now %d)',
							displayName(entry.owner),
							amount - entry.amount,
							amount
						), 5)
					end

					entry.amount = amount
				end
			end
		end)
	end

	local function stopFisherman()
		fishGeneration += 1
		disconnect(fishConnections)
	end

	local function startFisherman()
		stopFisherman()
		local generation = fishGeneration

		bedwars.Client:WaitFor(remotes.FishCaught):andThen(function(remote)
			if generation ~= fishGeneration or not KitSpy.Enabled or not FishermanToggle.Enabled then return end

			bind(fishConnections, remote, function(data)
				if not KitSpy.Enabled or not FishermanToggle.Enabled then return end

				local player = data.catchingPlayer
				if not player then return end

				if FishermanIgnoreTeammates.Enabled and player.Team == lplr.Team then
					return
				end

				local fish = fishNames[tostring(data.dropData and data.dropData.fishModel)] or 'Unknown Fish'
				local totals, order = {}, {}

				for _, item in data.dropData and data.dropData.drops or {} do
					local name = tostring(item.itemType or 'unknown')

					if totals[name] == nil then
						totals[name] = 0
						table.insert(order, name)
					end

					totals[name] += tonumber(item.amount) or 0
				end

				local items = {}

				for _, name in order do
					table.insert(items, name .. ' x' .. math.ceil(totals[name] * 1.4))
				end

				notif('KitSpy', displayName(player) .. ' caught ' .. fish .. (
					#items > 0 and ' | Loot: ' .. table.concat(items, ', ') or ''
				), 8)
			end)
		end)
	end

	local function stopBounty()
		bountyGeneration += 1
		disconnect(bountyConnections)
		table.clear(bounties)
	end

	local function startBounty()
		stopBounty()
		local generation = bountyGeneration

		bedwars.Client:WaitFor(remotes.BountyHunterTargetChanged):andThen(function(remote)
			if generation ~= bountyGeneration or not KitSpy.Enabled or not BountyHunterToggle.Enabled then return end

			bind(bountyConnections, remote, function(data)
				if not KitSpy.Enabled or not BountyHunterToggle.Enabled then return end

				local hunter = data.hunter
				if not hunter then return end

				bounties[hunter] = {
					target = data.newTargetUserId,
					reward = data.reward
				}

				if not BountyTargetToggle.Enabled then return end

				local target = data.newTargetUserId and playersService:GetPlayerByUserId(data.newTargetUserId)

				notif('KitSpy', displayName(hunter) .. (
					target and ' is hunting ' .. displayName(target) or ' lost their target'
				), 8)
			end)
		end)

		bind(bountyConnections, vapeEvents.EntityDeathEvent.Event, function(data)
			if not KitSpy.Enabled or not BountyHunterToggle.Enabled or not BountyLootToggle.Enabled then return end

			local killer = playersService:GetPlayerFromCharacter(data.fromEntity)
			local victim = playersService:GetPlayerFromCharacter(data.entityInstance)
			local record = killer and bounties[killer]

			if not record or not victim or record.target ~= victim.UserId then return end

			local reward = record.reward or {}

			notif('KitSpy', string.format(
				'%s bounty killed %s | Loot: iron x%d, emerald x%d',
				displayName(killer),
				displayName(victim),
				reward.iron or 0,
				reward.emerald or 0
			), 8)

			bounties[killer] = nil
		end)
	end

	local function drillOwner(drill)
		local id = ownerId(drill)
		return id and playersService:GetPlayerByUserId(id) or nil
	end

	local function ignoreDrill(drill)
		local owner = drillOwner(drill)
		return owner == lplr or owner ~= nil and owner.Team == lplr.Team
	end

	local function drillInfo(drill)
		local typeName = drill:GetAttribute('ItemType')
		return typeName, typeName and tonumber(drill:GetAttribute(typeName)) or 0
	end

	local function updateDrill(drill)
		local entry = drills[drill]
		if not entry then return end

		if ignoreDrill(drill) or not DrillESPToggle.Enabled then
			if entry.gui then
				entry.gui:Destroy()
				entry.gui = nil
			end
			return
		end

		local part = drill:FindFirstChild('Head') or drill.PrimaryPart or drill:FindFirstChildWhichIsA('BasePart', true)
		if not part then return end

		if not entry.gui then
			local gui = Instance.new('BillboardGui')
			gui.Name = 'drill-spy'
			gui.Size = UDim2.fromOffset(210, 24)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
			gui.AlwaysOnTop = true
			gui.Adornee = part
			gui.Parent = drillFolder

			local label = Instance.new('TextLabel')
			label.Name = 'Label'
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.new(0, 0, 0)
			label.BackgroundTransparency = 0.45
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.4
			label.TextSize = 13
			label.Font = Enum.Font.GothamBold
			label.Parent = gui

			Instance.new('UICorner', label).CornerRadius = UDim.new(0, 4)
			entry.gui = gui
		end

		local typeName, amount = drillInfo(drill)

		entry.gui.Label.Text = displayName(drillOwner(drill))
			.. ' | ' .. tostring(amount)
			.. ' ' .. tostring(typeName or 'loot'):gsub('_', ' ')
			.. ' | ' .. math.floor(drill:GetAttribute('Health') or 0) .. ' hp'
	end

	local function removeDrill(drill)
		local entry = drills[drill]
		if not entry then return end

		drills[drill] = nil

		if entry.connection then
			entry.connection:Disconnect()
		end

		if entry.gui then
			entry.gui:Destroy()
		end
	end

	local function addDrill(drill, fresh)
		if not drill:IsA('Model') or drill.Name ~= 'Drill' or drills[drill] then return end

		local _, amount = drillInfo(drill)
		local entry = {amount = amount}
		drills[drill] = entry

		if fresh and DrillNotify.Enabled and not ignoreDrill(drill) then
			notif('KitSpy', displayName(drillOwner(drill)) .. ' placed a drill', 4)
		end

		entry.connection = drill.AttributeChanged:Connect(function()
			if drills[drill] ~= entry then return end

			local typeName, newAmount = drillInfo(drill)

			if newAmount < entry.amount and DrillNotify.Enabled and not ignoreDrill(drill) then
				notif('KitSpy', string.format(
					'%s took %d %s from their drill',
					displayName(drillOwner(drill)),
					entry.amount - newAmount,
					tostring(typeName or 'loot'):gsub('_', ' ')
				), 4)
			end

			entry.amount = newAmount
			updateDrill(drill)
		end)

		updateDrill(drill)
	end

	local function stopDrill()
		if drillScan then
			drillScan.cancelled = true
			drillScan = nil
		end

		disconnect(drillConnections)

		for drill in drills do
			removeDrill(drill)
		end
	end

	local function startDrill()
		stopDrill()

		drillScan = scanDescendants(workspace, function(object)
			if KitSpy.Enabled and DrillToggle.Enabled then
				addDrill(object, false)
			end
		end)

		bind(drillConnections, workspace.DescendantAdded, function(object)
			if object:IsA('Model') and object.Name == 'Drill' then
				task.delay(0.2, function()
					if KitSpy.Enabled and DrillToggle.Enabled and object.Parent then
						addDrill(object, true)
					end
				end)
			end
		end)

		bind(drillConnections, workspace.DescendantRemoving, function(object)
			if drills[object] then
				removeDrill(object)
			end
		end)
	end

	local function stopAll()
		stopHives()
		stopLucia()
		stopFisherman()
		stopBounty()
		stopDrill()
	end

	KitSpy = vape.Categories.Kits:CreateModule({
		Name = 'KitSpy',
		Tooltip = 'shows information about other players using certain kits',
		Function = function(enabled)
			if enabled then
				if BeehiveToggle.Enabled then startHives() end
				if LuciaToggle.Enabled then startLucia() end
				if FishermanToggle.Enabled then startFisherman() end
				if BountyHunterToggle.Enabled then startBounty() end
				if DrillToggle.Enabled then startDrill() end
			else
				stopAll()
			end
		end
	})

	BeehiveToggle = KitSpy:CreateToggle({
		Name = 'Beehive',
		Function = function(enabled)
			if BeehiveBackground and BeehiveBackground.Object then
				BeehiveBackground.Object.Visible = enabled
			end

			if BeehiveColor and BeehiveColor.Object then
				BeehiveColor.Object.Visible = enabled and BeehiveBackground.Enabled
			end

			if KitSpy.Enabled then
				if enabled then startHives() else stopHives() end
			end
		end
	})

	BeehiveBackground = KitSpy:CreateToggle({
		Name = 'Beehive Background',
		Default = true,
		Darker = true,
		Visible = false,
		Function = function(enabled)
			if BeehiveColor and BeehiveColor.Object then
				BeehiveColor.Object.Visible = enabled and BeehiveToggle.Enabled
			end
			styleHives()
		end
	})

	BeehiveColor = KitSpy:CreateColorSlider({
		Name = 'Beehive Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Darker = true,
		Visible = false,
		Function = styleHives
	})

	LuciaToggle = KitSpy:CreateToggle({
		Name = 'Lucia',
		Function = function(enabled)
			if LuciaIgnoreTeammates and LuciaIgnoreTeammates.Object then
				LuciaIgnoreTeammates.Object.Visible = enabled
			end

			if LuciaDisplayName and LuciaDisplayName.Object then
				LuciaDisplayName.Object.Visible = enabled
			end

			if KitSpy.Enabled then
				if enabled then startLucia() else stopLucia() end
			end
		end
	})

	LuciaIgnoreTeammates = KitSpy:CreateToggle({
		Name = 'Lucia Ignore Teammates',
		Default = true,
		Darker = true,
		Visible = false
	})

	LuciaDisplayName = KitSpy:CreateToggle({
		Name = 'Lucia Display Name',
		Default = false,
		Darker = true,
		Visible = false
	})

	FishermanToggle = KitSpy:CreateToggle({
		Name = 'Fisherman',
		Function = function(enabled)
			if FishermanIgnoreTeammates and FishermanIgnoreTeammates.Object then
				FishermanIgnoreTeammates.Object.Visible = enabled
			end

			if KitSpy.Enabled then
				if enabled then startFisherman() else stopFisherman() end
			end
		end
	})

	FishermanIgnoreTeammates = KitSpy:CreateToggle({
		Name = 'Fisherman Ignore Teammates',
		Default = true,
		Darker = true,
		Visible = false
	})

	BountyHunterToggle = KitSpy:CreateToggle({
		Name = 'Bounty Hunter',
		Function = function(enabled)
			if BountyTargetToggle and BountyTargetToggle.Object then
				BountyTargetToggle.Object.Visible = enabled
			end

			if BountyLootToggle and BountyLootToggle.Object then
				BountyLootToggle.Object.Visible = enabled
			end

			if KitSpy.Enabled then
				if enabled then startBounty() else stopBounty() end
			end
		end
	})

	BountyTargetToggle = KitSpy:CreateToggle({
		Name = 'Bounty Hunter Target',
		Default = true,
		Darker = true,
		Visible = false
	})

	BountyLootToggle = KitSpy:CreateToggle({
		Name = 'Bounty Hunter Loot',
		Default = true,
		Darker = true,
		Visible = false
	})

	DrillToggle = KitSpy:CreateToggle({
		Name = 'Drill',
		Function = function(enabled)
			if DrillNotify and DrillNotify.Object then
				DrillNotify.Object.Visible = enabled
			end

			if DrillESPToggle and DrillESPToggle.Object then
				DrillESPToggle.Object.Visible = enabled
			end

			if KitSpy.Enabled then
				if enabled then startDrill() else stopDrill() end
			end
		end
	})

	DrillNotify = KitSpy:CreateToggle({
		Name = 'Drill Notifications',
		Default = true,
		Darker = true,
		Visible = false
	})

	DrillESPToggle = KitSpy:CreateToggle({
		Name = 'Drill ESP',
		Darker = true,
		Visible = false,
		Function = function()
			for drill in drills do
				updateDrill(drill)
			end
		end
	})

	task.defer(function()
		if not KitSpy then return end

		for _, values in {
			{BeehiveToggle, BeehiveBackground, BeehiveColor},
			{LuciaToggle, LuciaIgnoreTeammates, LuciaDisplayName},
			{FishermanToggle, FishermanIgnoreTeammates},
			{BountyHunterToggle, BountyTargetToggle, BountyLootToggle},
			{DrillToggle, DrillNotify, DrillESPToggle}
		} do
			for index = 2, #values do
				local child = values[index]

				if child and child.Object then
					child.Object.Visible = values[1].Enabled
						and (child ~= BeehiveColor or BeehiveBackground.Enabled)
				end
			end
		end
	end)

	vape:Clean(function()
		stopAll()
		beeFolder:Destroy()
		drillFolder:Destroy()
	end)
end)


run(function()
    local StarCollector
    local CollectionToggle
    local Animation
    local RangeSlider
    local ESPToggle
    local ESPNotify
    local ESPBackground
    local ESPColor
    local SwordCheck
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local Reference = {}
    local starCooldowns = {}
    local COOLDOWN_TIME = 0.5
    local lastNotification = 0
    local spawnQueue = {}
    local notificationCooldown = 1
    local collectionRunning = false

    local function sendNotification(count)
        notif("Star ESP", string.format("%d stars spawned", count), 3)
    end

    local function processSpawnQueue()
        if #spawnQueue > 0 then
            local currentTime = tick()
            if currentTime - lastNotification >= notificationCooldown then
                sendNotification(#spawnQueue)
                lastNotification = currentTime
                spawnQueue = {}
            else
                task.delay(notificationCooldown - (currentTime - lastNotification), function()
                    if #spawnQueue > 0 then
                        sendNotification(#spawnQueue)
                        spawnQueue = {}
                    end
                end)
            end
        end
    end

    local function getProperImage(v)
        local parent = v.Parent
        if parent and parent:IsA("Model") then
            local modelName = parent.Name
            if modelName == "CritStar" then
                return bedwars.getIcon({itemType = 'crit_star'}, true)
            elseif modelName == "VitalityStar" then
                return bedwars.getIcon({itemType = 'vitality_star'}, true)
            elseif modelName:find("vitality") or modelName:lower():find("vitality") then
                return bedwars.getIcon({itemType = 'vitality_star'}, true)
            elseif modelName:find("crit") or modelName:lower():find("crit") then
                return bedwars.getIcon({itemType = 'crit_star'}, true)
            end
        end
        return bedwars.getIcon({itemType = 'crit_star'}, true)
    end

    local function Added(v)
        if Reference[v] then return end
        local _bpUserId = v:GetAttribute('PlacedByUserId')
        if _bpUserId then
            local _bpOk, _bpOwner = pcall(function() return playersService:GetPlayerByUserId(_bpUserId) end)
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'stars'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = ESPBackground.Enabled
        
        local image = Instance.new('ImageLabel')
        image.Size = UDim2.fromOffset(36, 36)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.BackgroundColor3 = Color3.fromHSV(ESPColor.Hue, ESPColor.Sat, ESPColor.Value)
        image.BackgroundTransparency = 1 - (ESPBackground.Enabled and ESPColor.Opacity or 0)
        image.BorderSizePixel = 0
        image.Image = getProperImage(v)
        image.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = image
        
        Reference[v] = billboard
        
        if ESPNotify.Enabled then
            table.insert(spawnQueue, {item = 'star', time = tick()})
            processSpawnQueue()
        end
    end

    local function Removed(v)
        if Reference[v] then
            Reference[v]:Destroy()
            Reference[v] = nil
        end
        starCooldowns[v] = nil
    end

    local function setupESP()
        for _, v in collectionService:GetTagged('stars') do
            if v:IsA("Model") and v.PrimaryPart then
                Added(v.PrimaryPart)
            end
        end

        StarCollector:Clean(collectionService:GetInstanceAddedSignal('stars'):Connect(function(v)
            if v:IsA("Model") and v.PrimaryPart then
                task.wait(0.1)
                Added(v.PrimaryPart)
            end
        end))

        StarCollector:Clean(collectionService:GetInstanceRemovedSignal('stars'):Connect(function(v)
            if v.PrimaryPart then
                Removed(v.PrimaryPart)
            end
        end))
        
        local _scLastUpdate = 0
        StarCollector:Clean(runService.RenderStepped:Connect(function()
            if not ESPToggle.Enabled then return end
            local _now = tick()
            if _now - _scLastUpdate < 0.1 then return end
            _scLastUpdate = _now
            
            for v, billboard in pairs(Reference) do
                if not v or not v.Parent then
                    Removed(v)
                    continue
                end

                local shouldShow = true

                if SwordCheck.Enabled and isSword() then
                    shouldShow = false
                end

                billboard.Enabled = shouldShow
            end
        end))
    end

    local function collectStar(star)
        if not star or not star.Parent then return end
        
        if Animation.Enabled and entitylib.isAlive then
            bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.PUNCH)
            bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
        end
        
        bedwars.StarCollectorController:collectEntity(lplr, star, star.Name)
    end

	local function startCollection()
		collectionRunning = true
		task.spawn(function()
			while collectionRunning and StarCollector.Enabled and CollectionToggle.Enabled do
				if not entitylib.isAlive then
					task.wait(0.1)
					continue
				end

				local localPosition = entitylib.character.RootPart.Position
				local range = RangeSlider.Value
				local collected = false

				for _, v in collectionService:GetTagged('stars') do
					if not collectionRunning or not StarCollector.Enabled or not CollectionToggle.Enabled then
						break
					end

					if v:IsA("Model") and v.PrimaryPart then
						local starPos = v.PrimaryPart.Position
						local distance = (localPosition - starPos).Magnitude

						if distance <= range then
							local lastAttempt = starCooldowns[v]
							if lastAttempt and tick() - lastAttempt < COOLDOWN_TIME then
								continue
							end
							starCooldowns[v] = tick()
							collectStar(v)
							collected = true
							break
						end
					end
				end

				task.wait(collected and 0.1 or 0.2)
			end
			collectionRunning = false
		end)
	end

    StarCollector = vape.Categories.Kits:CreateModule({
        Name = 'AutoStar',
        Function = function(callback)
            if callback then
                if ESPToggle.Enabled then 
                    setupESP() 
                end
                
                if CollectionToggle.Enabled then
                    startCollection()
                end
            else
                collectionRunning = false
                Folder:ClearAllChildren()
                table.clear(Reference)
                table.clear(spawnQueue)
                table.clear(starCooldowns)
                lastNotification = 0
            end
        end,
    })
    
    CollectionToggle = StarCollector:CreateToggle({
        Name = 'Auto Collect',
        Default = true,
        Function = function(callback)
            if Animation and Animation.Object then Animation.Object.Visible = callback end
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            
            if callback and StarCollector.Enabled then
                startCollection()
            else
                collectionRunning = false
            end
        end
    })
    
    Animation = StarCollector:CreateToggle({
        Name = 'Animation',
        Default = true,
    })
    
    RangeSlider = StarCollector:CreateSlider({
        Name = 'Range',
        Min = 1, 
        Max = 18,
        Default = 10,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    ESPToggle = StarCollector:CreateToggle({
        Name = 'Star ESP',
        Default = false,
        Function = function(callback)
            if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = callback end
            if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = callback end
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            if SwordCheck and SwordCheck.Object then SwordCheck.Object.Visible = callback end
            
            if StarCollector.Enabled then
                if callback then 
                    setupESP() 
                else
                    Folder:ClearAllChildren()
                    table.clear(Reference)
                end
            end
        end
    })
    
    ESPNotify = StarCollector:CreateToggle({
        Name = 'Notify',
        Default = false,
    })
    
    ESPBackground = StarCollector:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundTransparency = 1 - (callback and ESPColor.Opacity or 0)
                    if v:FindFirstChild("Blur") then
                        v.Blur.Visible = callback
                    end
                end
            end
        end
    })
    
    ESPColor = StarCollector:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    v.ImageLabel.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Darker = true
    })
    SwordCheck = StarCollector:CreateToggle({
        Name = 'Sword Check',
        Default = false,
    })

    task.defer(function()
        local espOn = ESPToggle and ESPToggle.Enabled
        if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = espOn end
        if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = espOn end
        if ESPColor and ESPColor.Object then ESPColor.Object.Visible = espOn end
        if SwordCheck and SwordCheck.Object then SwordCheck.Object.Visible = espOn end
    end)
end)

run(function()
    local autoZenoModule
    local targetSettings
    local targetSelectionMode
    local itemLimitToggle
    local shockwaveToggle
    local shockwaveRadius
    local lightningStrikeToggle
    local lightningStormToggle
    local attackRange
    local actionDelay

    local function fetchAttackItem()
        if itemLimitToggle.Enabled then
            local wizardStaff = (store.hand.tool and store.hand.tool.Name:find('wizard_staff')) and store.hand.tool or nil
            return wizardStaff, wizardStaff and getHotbar(wizardStaff) or nil, wizardStaff and (tonumber(wizardStaff.Name:sub(#wizardStaff.Name, #wizardStaff.Name)) or 1) or nil
        end

        if store.hand.tool and store.hand.tool.Name:find('wizard_staff') then
            local item = store.hand.tool
            return item, getHotbar(item), tonumber(item.Name:sub(#item.Name, #item.Name)) or 1
        end

        for index, item in pairs(store.inventory.inventory.items) do
            if item.itemType:find('wizard_staff') then
                switchItem(item, 0)
                return item, index, tonumber(item.itemType:sub(#item.itemType, #item.itemType)) or 1
            end
        end

        return nil
    end

    autoZenoModule = vape.Categories.Kits:CreateModule({
        Name = 'AutoZeno',
        Function = function(callback)
            local aeroAlive = newRun(autoZenoModule)
            if callback then
                repeat
                    if entitylib.isAlive then
                        local staff, _, level = fetchAttackItem()

                        if staff then
                            local playerPosition = entitylib.character.RootPart.Position
                            local nearestEntity = entitylib.EntityPosition({
                                Origin = playerPosition,
                                Range = (attackRange.Value < 6 and shockwaveToggle.Enabled and 7) or attackRange.Value,
                                Part = 'RootPart',
                                Players = targetSettings.Players.Enabled,
                                NPCs = targetSettings.NPCs.Enabled,
                                Sort = sortmethods[targetSelectionMode.Value]
                            })

                            if nearestEntity then
                                if shockwaveToggle.Enabled and level > 2 then
                                    if bedwars.AbilityController:canUseAbility('SHOCKWAVE') and (playerPosition - nearestEntity.RootPart.Position).Magnitude <= shockwaveRadius.Value then
                                        bedwars.AbilityController:useAbility('SHOCKWAVE', newproxy(true), {
                                            target = CFrame.lookAt(playerPosition, nearestEntity.RootPart.Position).LookVector
                                        })
                                        task.wait(actionDelay.Value)
                                    end
                                end

                                if lightningStrikeToggle.Enabled and bedwars.AbilityController:canUseAbility('LIGHTNING_STRIKE') then
                                    bedwars.AbilityController:useAbility('LIGHTNING_STRIKE', newproxy(true), {
                                        target = nearestEntity.RootPart.Position + ((nearestEntity.Humanoid.MoveDirection or Vector3.zero) * (1 + lplr:GetNetworkPing()))
                                    })
                                    task.wait(actionDelay.Value)
                                end

                                if lightningStormToggle.Enabled and level > 1 then
                                    if bedwars.AbilityController:canUseAbility('LIGHTNING_STORM') then
                                        bedwars.AbilityController:useAbility('LIGHTNING_STORM', newproxy(true), {
                                            target = nearestEntity.RootPart.Position + ((nearestEntity.Humanoid.MoveDirection or Vector3.zero) * (1 + lplr:GetNetworkPing()))
                                        })
                                        task.wait(actionDelay.Value)
                                    end
                                end
                            end
                        end
                    end
                    task.wait(0.1)
                until not aeroAlive()
            end
        end,
    })

    targetSettings = autoZenoModule:CreateTargets({
        Players = true,
        NPCs = false
    })

    local availableSortingMethods = {'Damage', 'Distance'}
    for method in sortmethods do
        if not table.find(availableSortingMethods, method) then
            table.insert(availableSortingMethods, method)
        end
    end

    targetSelectionMode = autoZenoModule:CreateDropdown({
        Name = 'Target Mode',
        List = availableSortingMethods,
        Default = 'Distance'
    })

    itemLimitToggle = autoZenoModule:CreateToggle({
        Name = 'Limit to item',
        Default = true
    })

    lightningStrikeToggle = autoZenoModule:CreateToggle({
        Name = 'Use Lightning Strike',
        Default = true
    })

    lightningStormToggle = autoZenoModule:CreateToggle({
        Name = 'Use Lightning Storm'
    })

    shockwaveRadius = autoZenoModule:CreateSlider({
        Name = 'Shockwave Range',
        Visible = false,
        Darker = true,
        Min = 1,
        Max = 12,
        Suffix = function(value)
            return value > 1 and 'studs' or 'stud'
        end,
        Decimal = 5,
        Default = 12
    })

    shockwaveToggle = autoZenoModule:CreateToggle({
        Name = 'Auto Shockwave',
        Function = function(enabled)
            pcall(function()
                shockwaveRadius.Object.Visible = enabled
            end)
        end
    })

    attackRange = autoZenoModule:CreateSlider({
        Name = 'Attack Range',
        Min = 1,
        Max = 60,
        Default = 35,
        Suffix = function(value)
            return value > 1 and 'studs' or 'stud'
        end,
        Decimal = 5
    })

    actionDelay = autoZenoModule:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 10,
        Default = 0.5,
        Decimal = 5,
        Suffix = function(value)
            return value > 1 and 'secs' or 'sec'
        end
    })
end)

run(function()
    local Beekeeper
    local isRealBee
    local CollectionToggle
	local LimitToNet
	local HiveLimit
	local function maxHiveLevel()
		return HiveLimit and HiveLimit.Value or 12
	end
    local maxedBeehives = {}
    local maxedNotificationSent = {}
    local CollectionDelay
    local DelaySlider
    local RangeSlider
    local ESPToggle
    local BeesESP
    local BeesNotify
    local BeesBackground
    local BeesColor
    local BeehiveESP
    local ShowOtherBeehives
    local BeehiveBackground
    local BeehiveColor
    local AutoDeposit
    local DepositDelay
    local DepositDelaySlider
    local DepositRange
    local ESPLimitToNet  
    local collectionRunning = false
    local depositRunning = false
    local BeesFolder = Instance.new('Folder')
    BeesFolder.Parent = vape.gui
    local BeehiveFolder = Instance.new('Folder')
    BeehiveFolder.Parent = vape.gui
    local BeesReference = {}
    local BeehiveReference = {}
    local lastNotification = 0
    local spawnQueue = {}
    local notificationCooldown = 1

    local function sendNotification(count)
        notif("Bee ESP", string.format("%d bees spawned", count), 3)
    end

    local function processSpawnQueue()
        if #spawnQueue > 0 then
            local currentTime = tick()
            if currentTime - lastNotification >= notificationCooldown then
                sendNotification(#spawnQueue)
                lastNotification = currentTime
                spawnQueue = {}
            else
                task.delay(notificationCooldown - (currentTime - lastNotification), function()
                    if #spawnQueue > 0 then
                        sendNotification(#spawnQueue)
                        spawnQueue = {}
                    end
                end)
            end
        end
    end

    local function getBeeIcon()
        return bedwars.getIcon({itemType = 'bee'}, true)
    end

    local function AddedBee(v)
        if BeesReference[v] then return end
        local model = v.Parent
        if model and not isRealBee(model) then
            return
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = BeesFolder
        billboard.Name = 'bee'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = BeesBackground.Enabled
        
        local image = Instance.new('ImageLabel')
        image.Size = UDim2.fromOffset(36, 36)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.BackgroundColor3 = Color3.fromHSV(BeesColor.Hue, BeesColor.Sat, BeesColor.Value)
        image.BackgroundTransparency = 1 - (BeesBackground.Enabled and BeesColor.Opacity or 0)
        image.BorderSizePixel = 0
        image.Image = getBeeIcon()
        image.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = image
        
        BeesReference[v] = billboard
        
        if BeesNotify.Enabled then
            table.insert(spawnQueue, {item = 'bee', time = tick()})
            processSpawnQueue()
        end
    end

    local function RemovedBee(v)
        if BeesReference[v] then
            BeesReference[v]:Destroy()
            BeesReference[v] = nil
        end
    end

    local function isMyBeehive(beehive)
        if not beehive then return false end
        local placedBy = beehive:GetAttribute("PlacedByUserId")
        return placedBy and placedBy == lplr.UserId
    end
    
    local function getBeehiveOwnerName(beehive)
        if not beehive then return "Unknown" end
        local placedBy = beehive:GetAttribute("PlacedByUserId")
        if not placedBy then return "Unknown" end
        
        local player = game.Players:GetPlayerByUserId(placedBy)
        if player then
            return player.Name
        end
        
        return "Player"
    end

    local function AddedBeehive(beehive)
        local isOwn = isMyBeehive(beehive)
        
        if not isOwn and not (ShowOtherBeehives and ShowOtherBeehives.Enabled) then 
            return 
        end
        
        if BeehiveReference[beehive] then return end
        
        local level = beehive:GetAttribute("Level") or 0
        local isMaxed = level >= maxHiveLevel() and isOwn
        
        if isMaxed and isOwn then
            maxedBeehives[beehive] = true
        end
        
        local ownerName = isOwn and nil or getBeehiveOwnerName(beehive)
        local hasOwnerName = ownerName ~= nil
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = BeehiveFolder
        billboard.Name = 'beehive-esp'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
        billboard.Size = isMaxed and UDim2.fromOffset(90, 40) or (hasOwnerName and UDim2.fromOffset(120, 40) or UDim2.fromOffset(80, 30))
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = beehive
        
        local blur = addBlur(billboard)
        blur.Visible = BeehiveBackground.Enabled
        
        local frame = Instance.new('Frame')
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = isMaxed and Color3.fromRGB(255, 50, 50) or Color3.fromHSV(BeehiveColor.Hue, BeehiveColor.Sat, BeehiveColor.Value)
        frame.BackgroundTransparency = 1 - (BeehiveBackground.Enabled and (isMaxed and 0.5 or BeehiveColor.Opacity) or 0)
        frame.BorderSizePixel = 0
        frame.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 6)
        uicorner.Parent = frame
        
        if hasOwnerName then
            local nameLabel = Instance.new('TextLabel')
            nameLabel.Name = 'OwnerName'
            nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
            nameLabel.Position = UDim2.new(0, 0, 0, -20)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = ownerName
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLabel.TextSize = 12
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextStrokeTransparency = 0.5
            nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            nameLabel.Parent = billboard
        end
        
        local homeImage = Instance.new('ImageLabel')
		homeImage.Size = UDim2.fromOffset(20, 20)
		homeImage.Position = UDim2.new(0, 5, 0.5, 0)
		homeImage.AnchorPoint = Vector2.new(0, 0.5)
		homeImage.BackgroundTransparency = 1
		homeImage.BorderSizePixel = 0
		homeImage.Image = bedwars.getIcon({itemType = 'beehive'}, true)
		homeImage.Parent = frame
        
        local beeImage = Instance.new('ImageLabel')
        beeImage.Size = UDim2.fromOffset(18, 18)
        beeImage.Position = UDim2.new(0.5, -5, 0.5, 0)
        beeImage.AnchorPoint = Vector2.new(0, 0.5)
        beeImage.BackgroundTransparency = 1
        beeImage.Image = getBeeIcon()
        beeImage.Parent = frame
        
        local levelLabel = Instance.new('TextLabel')
        levelLabel.Name = 'Level'
        levelLabel.Size = UDim2.new(0, 25, 1, 0)
        levelLabel.Position = UDim2.new(1, -30, 0, 0)
        levelLabel.BackgroundTransparency = 1
        levelLabel.Text = tostring(level)
        levelLabel.TextColor3 = isMaxed and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 255, 255)
        levelLabel.TextSize = 16
        levelLabel.Font = Enum.Font.GothamBold
        levelLabel.TextStrokeTransparency = 0.5
        levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        levelLabel.Parent = frame
        
        if isMaxed and isOwn then
            local maxText = Instance.new('TextLabel')
            maxText.Name = 'MaxText'
            maxText.Size = UDim2.new(1, 0, 0.4, 0)
            maxText.Position = UDim2.new(0, 0, 0, hasOwnerName and -40 or -20)
            maxText.BackgroundTransparency = 1
            maxText.Text = "MAX"
            maxText.TextColor3 = Color3.fromRGB(255, 50, 50)
            maxText.TextSize = 12
            maxText.Font = Enum.Font.GothamBold
            maxText.TextStrokeTransparency = 0.5
            maxText.TextStrokeColor3 = Color3.new(0, 0, 0)
            maxText.Parent = billboard
        end
        
        BeehiveReference[beehive] = {
            billboard = billboard,
            levelLabel = levelLabel,
            beehive = beehive,
            isMaxed = isMaxed,
            isOwn = isOwn
        }
        
        local function updateLevel()
            local level = beehive:GetAttribute("Level") or 0
            local isMaxed = level >= maxHiveLevel() and isOwn
            
            if isMaxed and isOwn then
                maxedBeehives[beehive] = true
                
                if not maxedNotificationSent[beehive] then
                    notif("Bee Keeper", "beehive is full (max)", 3)
                    maxedNotificationSent[beehive] = true
                end
                
                if BeehiveReference[beehive] and BeehiveReference[beehive].billboard then
                    local maxText = BeehiveReference[beehive].billboard:FindFirstChild("MaxText")
                    if not maxText then
                        maxText = Instance.new('TextLabel')
                        maxText.Name = 'MaxText'
                        maxText.Size = UDim2.new(1, 0, 0.4, 0)
                        maxText.Position = UDim2.new(0, 0, 0, hasOwnerName and -40 or -20)
                        maxText.BackgroundTransparency = 1
                        maxText.Text = "MAX"
                        maxText.TextColor3 = Color3.fromRGB(255, 50, 50)
                        maxText.TextSize = 12
                        maxText.Font = Enum.Font.GothamBold
                        maxText.TextStrokeTransparency = 0.5
                        maxText.TextStrokeColor3 = Color3.new(0, 0, 0)
                        maxText.Parent = BeehiveReference[beehive].billboard
                    end
                    
                    local frame = BeehiveReference[beehive].billboard:FindFirstChild("Frame")
                    if frame then
                        frame.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
                        frame.BackgroundTransparency = 1 - (BeehiveBackground.Enabled and 0.5 or 0)
                    end
                end
            else
                if isOwn then
                    maxedBeehives[beehive] = nil
                    maxedNotificationSent[beehive] = nil
                end
                
                if BeehiveReference[beehive] and BeehiveReference[beehive].billboard then
                    local maxText = BeehiveReference[beehive].billboard:FindFirstChild("MaxText")
                    if maxText then
                        maxText:Destroy()
                    end
                    
                    local frame = BeehiveReference[beehive].billboard:FindFirstChild("Frame")
                    if frame then
                        frame.BackgroundColor3 = Color3.fromHSV(BeehiveColor.Hue, BeehiveColor.Sat, BeehiveColor.Value)
                        frame.BackgroundTransparency = 1 - (BeehiveBackground.Enabled and BeehiveColor.Opacity or 0)
                    end
                end
            end
            
            if BeehiveReference[beehive] and BeehiveReference[beehive].levelLabel then
                BeehiveReference[beehive].levelLabel.Text = tostring(level)
            end
            
            if BeehiveReference[beehive] then
                BeehiveReference[beehive].isMaxed = isMaxed
            end
        end
        
        updateLevel()
        
        if isOwn then
            Beekeeper:Clean(beehive:GetAttributeChangedSignal("Level"):Connect(updateLevel))
        else
            Beekeeper:Clean(beehive:GetAttributeChangedSignal("Level"):Connect(function()
                local level = beehive:GetAttribute("Level") or 0
                if BeehiveReference[beehive] and BeehiveReference[beehive].levelLabel then
                    BeehiveReference[beehive].levelLabel.Text = tostring(level)
                end
            end))
        end
    end


    local function RemovedBeehive(beehive)
        if BeehiveReference[beehive] then
            BeehiveReference[beehive].billboard:Destroy()
            BeehiveReference[beehive] = nil
        end
    end

    local function getBeeId(v)
        if not v then return nil end

        local beeId = v:GetAttribute('BeeId')
        if beeId ~= nil then
            return beeId
        end

        local part = v.PrimaryPart or v:FindFirstChildWhichIsA('BasePart', true)
        return part and part:GetAttribute('BeeId')
    end

    isRealBee = function(v)
        local beeId = getBeeId(v)
        return beeId ~= nil and beeId > -1
    end

    local function setupBeesESP()
        for _, tagName in {'bee', 'MeadowBee', 'ChromaBee'} do
            for _, v in collectionService:GetTagged(tagName) do
                if v:IsA("Model") and v.PrimaryPart then
                    if isRealBee(v) then
                        AddedBee(v.PrimaryPart)
                    end
                end
            end

            Beekeeper:Clean(collectionService:GetInstanceAddedSignal(tagName):Connect(function(v)
                if v:IsA("Model") and v.PrimaryPart then
                    task.wait(0.1)
                    if isRealBee(v) then
                        AddedBee(v.PrimaryPart)
                    end
                end
            end))

            Beekeeper:Clean(collectionService:GetInstanceRemovedSignal(tagName):Connect(function(v)
                if v.PrimaryPart then
                    RemovedBee(v.PrimaryPart)
                end
            end))
        end
    end

    local function setupBeehiveESP()
        for _, beehive in collectionService:GetTagged('beehive') do
            AddedBeehive(beehive)
        end

        Beekeeper:Clean(collectionService:GetInstanceAddedSignal('beehive'):Connect(function(beehive)
            task.wait(0.1)
            AddedBeehive(beehive)
        end))

        Beekeeper:Clean(collectionService:GetInstanceRemovedSignal('beehive'):Connect(function(beehive)
            RemovedBeehive(beehive)
        end))
    end

    local function isHoldingBeeNet()
        if not store.hand or not store.hand.tool then return false end

        local name = store.hand.tool.Name

        return name == 'bee_net'
            or name == 'bee-net'
            or name == 'beekeeper_chroma_bee_net'
            or name == 'beekeeper_meadow_bee_net'
    end

	local function kitCollection(id, func, range, specific)
		repeat
			if entitylib.isAlive then
				local objs = type(id) == 'table' and id or collection(id, Beekeeper)
				local localPosition = entitylib.character.RootPart.Position
				for _, v in objs do
					if not Beekeeper.Enabled then break end
					local part = not v:IsA('Model') and v or v.PrimaryPart
					if part and (part.Position - localPosition).Magnitude <= range then
						local success, err = pcall(func, v)
						task.wait(0.02)
					end
				end
			end
			task.wait(0.05)
		until not Beekeeper.Enabled
	end

    local collectionThreads = {}

    local function startCollection()
        collectionRunning = true
        for _, tagName in {'bee', 'MeadowBee', 'ChromaBee'} do
            local thread = task.spawn(function()
                kitCollection(tagName, function(v)
                    if not isRealBee(v) then return end
                    if LimitToNet.Enabled and not isHoldingBeeNet() then return end
                    bedwars.Client:Get(remotes.BeePickup):SendToServer({beeId = getBeeId(v)})
                end, RangeSlider.Value, false)
            end)
            table.insert(collectionThreads, thread)
        end
        Beekeeper:Clean(function()
            for _, thread in collectionThreads do
                task.cancel(thread)
            end
            table.clear(collectionThreads)
        end)
    end

    local function startDeposit()
        depositRunning = true
        task.spawn(function()
            while depositRunning and Beekeeper.Enabled and AutoDeposit.Enabled do
                if not entitylib.isAlive then 
                    task.wait(0.1) 
                    continue 
                end
                
                local currentTool = store.hand and store.hand.tool
                if not currentTool or currentTool.Name ~= 'bee' then
                    task.wait(0.1)
                    continue
                end
                
                local localPosition = entitylib.character.RootPart.Position
                local range = DepositRange.Value
                local depositedThisCycle = false
                
                local availableBeehives = {}
                for _, beehive in collectionService:GetTagged('beehive') do
                    if isMyBeehive(beehive) and not maxedBeehives[beehive] then
                        local beehivePos = beehive.Position
                        local distance = (localPosition - beehivePos).Magnitude
                        
                        if distance <= range then
                            table.insert(availableBeehives, {
                                beehive = beehive,
                                distance = distance
                            })
                        end
                    end
                end
                
                table.sort(availableBeehives, function(a, b)
                    return a.distance < b.distance
                end)
                
                for _, beehiveData in ipairs(availableBeehives) do
                    if not depositRunning or not Beekeeper.Enabled or not AutoDeposit.Enabled then 
                        break 
                    end
                    local beehive = beehiveData.beehive
                    if maxedBeehives[beehive] then
                        continue
                    end
                    
                    local prompt = beehive:FindFirstChildOfClass("ProximityPrompt")
                    
                    if prompt and prompt.Enabled then
                        if DepositDelay.Enabled and DepositDelaySlider.Value > 0 then
                            local originalDuration = prompt.HoldDuration
                            prompt.HoldDuration = DepositDelaySlider.Value
                            
                            if fireproximityprompt then
                                fireproximityprompt(prompt)
                            else
                                prompt:InputHoldBegin()
                                task.wait(DepositDelaySlider.Value)
                                prompt:InputHoldEnd()
                            end
                            
                            task.wait(DepositDelaySlider.Value + 0.1)
                            prompt.HoldDuration = originalDuration
                        else
                            if fireproximityprompt then
                                fireproximityprompt(prompt)
                            else
                                prompt:InputHoldBegin()
                                prompt:InputHoldEnd()
                            end
                            task.wait(0.1)
                        end
                        
                        depositedThisCycle = true
                        break 
                    end
                end
                
                if not depositedThisCycle and #availableBeehives > 0 then
                    local allMaxed = true
                    for _, beehiveData in ipairs(availableBeehives) do
                        if not maxedBeehives[beehiveData.beehive] then
                            allMaxed = false
                            break
                        end
                    end
                    
                    if allMaxed then
                        notif("Bee Keeper", "all nearby beehives are full", 3)
                    end
                end
                
                task.wait(depositedThisCycle and 0.3 or 0.2)
            end
            depositRunning = false
        end)
    end

    Beekeeper = vape.Categories.Kits:CreateModule({
        Name = 'AutoBeekeeper',
        Function = function(callback)
            if callback then
                if ESPToggle.Enabled then
                    if BeesESP.Enabled then
                        setupBeesESP()
                    end
                    if BeehiveESP.Enabled then
                        setupBeehiveESP()
                    end
                end
                
                if CollectionToggle.Enabled then
                    startCollection()
                end
                
                if AutoDeposit.Enabled then
                    startDeposit()
                end
                
                local _bkLastUpdate = 0
                Beekeeper:Clean(runService.RenderStepped:Connect(function()
                    if not ESPToggle.Enabled then return end
                    local _now = tick()
                    if _now - _bkLastUpdate < 0.1 then return end
                    _bkLastUpdate = _now
                    
                    for v, billboard in pairs(BeesReference) do
                        if not v or not v.Parent then
                            RemovedBee(v)
                            continue
                        end

                        local shouldShow = true

                        if ESPLimitToNet.Enabled and not isHoldingBeeNet() then
                            shouldShow = false
                        end

                        billboard.Enabled = shouldShow
                    end
                    
                    for beehive, ref in pairs(BeehiveReference) do
                        if not beehive or not beehive.Parent then
                            RemovedBeehive(beehive)
                            continue
                        end

                        local shouldShow = true

                        if ESPLimitToNet.Enabled and not isHoldingBeeNet() then
                            shouldShow = false
                        end

                        if ref.billboard then
                            ref.billboard.Enabled = shouldShow
                        end
                    end
                end))
            else
                collectionRunning = false
                depositRunning = false
                BeesFolder:ClearAllChildren()
                BeehiveFolder:ClearAllChildren()
                table.clear(BeesReference)
                table.clear(BeehiveReference)
                table.clear(spawnQueue)
                lastNotification = 0
            end
        end,
    })
    
    CollectionToggle = Beekeeper:CreateToggle({
        Name = 'Auto Collect',
        Default = true,
        Function = function(callback)
            if LimitToNet and LimitToNet.Object then LimitToNet.Object.Visible = callback end
            if CollectionDelay and CollectionDelay.Object then CollectionDelay.Object.Visible = callback end
            if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = (callback and CollectionDelay.Enabled) end
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            
            if callback and Beekeeper.Enabled then
                startCollection()
            else
                collectionRunning = false
            end
        end
    })
    
    LimitToNet = Beekeeper:CreateToggle({
        Name = 'Limit to Net',
        Default = false,
    })
    
    CollectionDelay = Beekeeper:CreateToggle({
        Name = 'Collection Delay',
        Default = false,
        Function = function(callback)
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback
            end
        end
    })
    
    DelaySlider = Beekeeper:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
    })
    
    RangeSlider = Beekeeper:CreateSlider({
        Name = 'Range',
        Min = 1, 
        Max = 10,
        Default = 10,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    ESPToggle = Beekeeper:CreateToggle({
        Name = 'ESP',
        Default = true,
		Function = function(callback)
			if BeesESP and BeesESP.Object then BeesESP.Object.Visible = callback end
			if BeehiveESP and BeehiveESP.Object then BeehiveESP.Object.Visible = callback end
			if ESPLimitToNet and ESPLimitToNet.Object then ESPLimitToNet.Object.Visible = callback end

			if not callback then
				if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = false end
				if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = false end
				if BeesColor and BeesColor.Object then BeesColor.Object.Visible = false end
				if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = false end
				if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = false end
				if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = false end
			else
				if BeesESP and BeesESP.Enabled then
					if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = true end
					if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = true end
					if BeesColor and BeesColor.Object then BeesColor.Object.Visible = BeesBackground.Enabled end
				end
				if BeehiveESP and BeehiveESP.Enabled then
					if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = true end
					if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = true end
					if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = BeehiveBackground.Enabled end
				end
			end

			if Beekeeper.Enabled then
				if callback then
					if BeesESP.Enabled then setupBeesESP() end
					if BeehiveESP.Enabled then setupBeehiveESP() end
				else
					BeesFolder:ClearAllChildren()
					BeehiveFolder:ClearAllChildren()
					table.clear(BeesReference)
					table.clear(BeehiveReference)
				end
			end
		end
    })
    
    ESPLimitToNet = Beekeeper:CreateToggle({
        Name = 'Limit to Net',
        Default = false,
    })
    
    BeesESP = Beekeeper:CreateToggle({
        Name = 'Bees',
        Default = false,
        Function = function(callback)
            if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = callback end
            if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = callback end
            if BeesColor and BeesColor.Object then BeesColor.Object.Visible = callback end
            
            if Beekeeper.Enabled and ESPToggle.Enabled then
                if callback then setupBeesESP() else
                    BeesFolder:ClearAllChildren()
                    table.clear(BeesReference)
                end
            end
        end
    })
    
    BeesNotify = Beekeeper:CreateToggle({
        Name = 'Notify',
        Default = false,
    })
    
    BeesBackground = Beekeeper:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if BeesColor and BeesColor.Object then BeesColor.Object.Visible = callback end
            for _, v in BeesReference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundTransparency = 1 - (callback and BeesColor.Opacity or 0)
                    if v:FindFirstChild("Blur") then
                        v.Blur.Visible = callback
                    end
                end
            end
        end
    })
    
	BeesColor = Beekeeper:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			for _, v in BeesReference do
				if v and v:FindFirstChild("ImageLabel") then
					v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
					v.ImageLabel.BackgroundTransparency = 1 - opacity
				end
			end
		end,
		Darker = true
	})
    
    BeehiveESP = Beekeeper:CreateToggle({
        Name = 'Beehives',
        Default = false,
        Function = function(callback)
            if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = callback end
            if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = callback end
            if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = callback end
            
            if Beekeeper.Enabled and ESPToggle.Enabled then
                if callback then setupBeehiveESP() else
                    BeehiveFolder:ClearAllChildren()
                    table.clear(BeehiveReference)
                end
            end
        end
    })
    
    ShowOtherBeehives = Beekeeper:CreateToggle({
        Name = 'Show Others',
        Default = false,
        Function = function(callback)
            if Beekeeper.Enabled and ESPToggle.Enabled and BeehiveESP.Enabled then
                BeehiveFolder:ClearAllChildren()
                table.clear(BeehiveReference)
                setupBeehiveESP()
            end
        end
    })
    
    BeehiveBackground = Beekeeper:CreateToggle({
        Name = 'Beehive Background',
        Default = true,
        Function = function(callback)
            if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = callback end
            for _, ref in BeehiveReference do
                if ref and ref.billboard then
                    local frame = ref.billboard:FindFirstChild("Frame")
                    if frame then
                        if ref.isMaxed and ref.isOwn then
                            frame.BackgroundTransparency = 1 - (callback and 0.5 or 0)
                        else
                            frame.BackgroundTransparency = 1 - (callback and BeehiveColor.Opacity or 0)
                        end
                    end
                    if ref.billboard:FindFirstChild("Blur") then
                        ref.billboard.Blur.Visible = callback
                    end
                end
            end
        end
    })
    
    BeehiveColor = Beekeeper:CreateColorSlider({
        Name = 'Beehive Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, ref in BeehiveReference do
                if ref and ref.billboard then
                    local frame = ref.billboard:FindFirstChild("Frame")
                    if frame and not (ref.isMaxed and ref.isOwn) then
                        frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                        frame.BackgroundTransparency = 1 - opacity
                    end
                end
            end
        end,
        Darker = true
    })
    
    AutoDeposit = Beekeeper:CreateToggle({
        Name = 'Auto Deposit',
        Default = false,
		Function = function(callback)
			if DepositDelay and DepositDelay.Object then DepositDelay.Object.Visible = callback end
			if DepositDelaySlider and DepositDelaySlider.Object then DepositDelaySlider.Object.Visible = (callback and DepositDelay.Enabled) end
			if DepositRange and DepositRange.Object then DepositRange.Object.Visible = callback end
			if HiveLimit and HiveLimit.Object then HiveLimit.Object.Visible = callback end
			
			if not callback then
				if DepositDelaySlider and DepositDelaySlider.Object then DepositDelaySlider.Object.Visible = false end
			end

			if callback and Beekeeper.Enabled then
				startDeposit()
			else
				depositRunning = false
			end
		end
    })
    
    DepositDelay = Beekeeper:CreateToggle({
        Name = 'Deposit Delay',
        Default = false,
        Function = function(callback)
            if DepositDelaySlider and DepositDelaySlider.Object then
                DepositDelaySlider.Object.Visible = callback
            end
        end
    })
    
    DepositDelaySlider = Beekeeper:CreateSlider({
        Name = 'Deposit Delay',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
    })
    
    DepositRange = Beekeeper:CreateSlider({
        Name = 'Deposit Range',
        Min = 1,
        Max = 10,
        Default = 10,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    HiveLimit = Beekeeper:CreateSlider({
        Name = 'Hive Limit',
        Min = 1,
        Max = 20,
        Default = 12,
        Decimal = 1,
        Suffix = ' bees',
        Function = function()
            table.clear(maxedBeehives)
            table.clear(maxedNotificationSent)
        end
    })
	task.defer(function()
		if HiveLimit and HiveLimit.Object then HiveLimit.Object.Visible = AutoDeposit.Enabled end
		if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = CollectionDelay.Enabled end
		if not ESPToggle.Enabled or not BeesESP.Enabled then
			if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = false end
			if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = false end
			if BeesColor and BeesColor.Object then BeesColor.Object.Visible = false end
		else
			if BeesColor and BeesColor.Object then BeesColor.Object.Visible = BeesBackground.Enabled end
		end

		if not ESPToggle.Enabled or not BeehiveESP.Enabled then
			if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = false end
			if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = false end
			if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = false end
		else
			if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = BeehiveBackground.Enabled end
		end

		if AutoDeposit and not AutoDeposit.Enabled then
			if DepositDelay and DepositDelay.Object then DepositDelay.Object.Visible = false end
			if DepositDelaySlider and DepositDelaySlider.Object then DepositDelaySlider.Object.Visible = false end
			if DepositRange and DepositRange.Object then DepositRange.Object.Visible = false end
		end

		if DepositDelaySlider and DepositDelaySlider.Object then
			DepositDelaySlider.Object.Visible = (AutoDeposit.Enabled and DepositDelay.Enabled)
		end
	end)
end)

run(function()
	local KitESP
	local Sizeable
	local SizeSlider
	local Notify
	local Background
	local Color = {}
	local Reference = {}
	local Folder = Instance.new('Folder')
    local currentSize = 36
	Folder.Parent = vape.gui
	
	local ESPKits = {
		alchemist = {'alchemist_ingedients', 'thorns'},
		beekeeper = {'bee', 'bee'},
		bigman = {'treeOrb', 'natures_essence_1'},
		ghost_catcher = {'ghost', 'ghost_orb'},
		metal_detector = {'hidden-metal', 'iron'},
		sheep_herder = {'SheepModel', 'purple_hay_bale'},
		sorcerer = {'alchemy_crystal', 'wild_flower'},
		star_collector = {'stars', 'crit_star'},
		black_market_trader = {'shadow_coin', 'shadow_coin'},
		miner = {'petrified-player', 'large_rock'},
		trapper = {'snap_trap', 'snap_trap'},
		mage = {'ElementTome', 'mage_spellbook'},
	}
	local NONTaggedKits = {
		necromancer = {'Gravestone', true},
		battery = {'Open', true},
	}
	local DescendantKits = {
		['farmer_cletus'] = {
			{'carrot', 'carrot_seeds'},
			{'melon', 'melon_seeds'},
			{'pumpkin', 'pumpkin_seeds'},
		},
	}

	local function isMineOnMyTeam(part)
		local teamAttr = part:GetAttribute('Team') or part:GetAttribute('TeamId') or part:GetAttribute('TeamID')
		if teamAttr then
			local myTeam = lplr:GetAttribute('Team') or lplr:GetAttribute('TeamId') or lplr:GetAttribute('TeamID')
			if myTeam and tostring(teamAttr) == tostring(myTeam) then
				return true
			end
		end
		local placedBy = part:GetAttribute('PlacedByUserId')
		if placedBy then
			local player = playersService:GetPlayerByUserId(placedBy)
			if player then
				local myTeam = lplr:GetAttribute('Team')
				if myTeam and player:GetAttribute('Team') == myTeam then
					return true
				end
			end
		end
		return false
	end

	local function getAlchemistImage(v)
		local name = v and v.Name or ''
		if name == 'Mushrooms' then
			return bedwars.getIcon({itemType = 'mushrooms'}, true)
		elseif name == 'Thorns' then
			return bedwars.getIcon({itemType = 'thorns'}, true)
		else
			return bedwars.getIcon({itemType = 'wild_flower'}, true)
		end
	end

	local function getStarImage(v)
		local parent = v and v.Parent
		if parent and parent:IsA("Model") then
			local modelName = parent.Name
			if modelName == "CritStar" or modelName:lower():find("crit") then
				return bedwars.getIcon({itemType = 'crit_star'}, true)
			elseif modelName == "VitalityStar" or modelName:lower():find("vitality") then
				return bedwars.getIcon({itemType = 'vitality_star'}, true)
			end
		end
		return bedwars.getIcon({itemType = 'crit_star'}, true)
	end

	local function Added(v, icon, non)
		if Reference[v] then return end
		if Notify.Enabled then
			vape:CreateNotification("KitESP", `New object is added {v.Name}`, 2)
		end
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = icon
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(currentSize, currentSize)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local image = Instance.new('ImageLabel')
		image.Size = UDim2.fromOffset(currentSize, currentSize)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		image.BorderSizePixel = 0
		if non then
			image.Image = icon
		else
			image.Image = bedwars.getIcon({itemType = icon}, true)
		end
		image.Parent = billboard
		local uicorner = Instance.new('UICorner')
		uicorner.CornerRadius = UDim.new(0, 4)
		uicorner.Parent = image
		Reference[v] = billboard
	end

	local function AddedStar(v)
		if not v or not v.Parent then return end
		if Reference[v] then return end

		if Notify.Enabled then
			vape:CreateNotification("KitESP", `New object is added {v.Name}`, 2)
		end
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'star'
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(currentSize, currentSize)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local image = Instance.new('ImageLabel')
		image.Size = UDim2.fromOffset(currentSize, currentSize)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		image.BorderSizePixel = 0
		image.Image = getStarImage(v)
		image.Parent = billboard
		local uicorner = Instance.new('UICorner')
		uicorner.CornerRadius = UDim.new(0, 4)
		uicorner.Parent = image
		Reference[v] = billboard
	end
	
	local currentConnections = {}
	local currentKit = nil

	local function disconnectAll()
		for _, conn in ipairs(currentConnections) do
			conn:Disconnect()
		end
		table.clear(currentConnections)
	end

	local function isRealBee(v)
		if not v then return false end

		local beeId = v:GetAttribute('BeeId')

		if beeId == nil then
			local part = v.PrimaryPart or v:FindFirstChildWhichIsA('BasePart', true)
			beeId = part and part:GetAttribute('BeeId')
		end

		return beeId ~= nil and beeId > -1
	end

	local function addKit(tag, icon)
		if tag == 'bee' then
			local beeIcon = bedwars.getIcon({itemType = 'bee'}, true)
			for _, tagName in {'bee', 'MeadowBee', 'ChromaBee'} do
				local connAdded = collectionService:GetInstanceAddedSignal(tagName):Connect(function(v)
					if v:IsA("Model") and v.PrimaryPart then
						task.wait(0.1)
						if isRealBee(v) then
							Added(v.PrimaryPart, beeIcon, true)
						end
					end
				end)
				table.insert(currentConnections, connAdded)
				local connRemoved = collectionService:GetInstanceRemovedSignal(tagName):Connect(function(v)
					if v.PrimaryPart and Reference[v.PrimaryPart] then
						Reference[v.PrimaryPart]:Destroy()
						Reference[v.PrimaryPart] = nil
					end
				end)
				table.insert(currentConnections, connRemoved)
				for _, v in collectionService:GetTagged(tagName) do
					if v:IsA("Model") and v.PrimaryPart and isRealBee(v) then
						Added(v.PrimaryPart, beeIcon, true)
					end
				end
			end
			return
		end
		if tag == 'alchemist_ingedients' then
			local connAdded = collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
				if v.PrimaryPart then
					task.wait(0.1)
					if Reference[v.PrimaryPart] then return end
					local billboard = Instance.new('BillboardGui')
					billboard.Parent = Folder
					billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
					billboard.Size = UDim2.fromOffset(currentSize, currentSize)
					billboard.AlwaysOnTop = true
					billboard.ClipsDescendants = false
					billboard.Adornee = v.PrimaryPart
					local blur = addBlur(billboard)
					blur.Visible = Background.Enabled
					local image = Instance.new('ImageLabel')
					image.Size = UDim2.fromOffset(currentSize, currentSize)
					image.Position = UDim2.fromScale(0.5, 0.5)
					image.AnchorPoint = Vector2.new(0.5, 0.5)
					image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
					image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
					image.BorderSizePixel = 0
					image.Image = getAlchemistImage(v)
					image.Parent = billboard
					local uicorner = Instance.new('UICorner')
					uicorner.CornerRadius = UDim.new(0, 4)
					uicorner.Parent = image
					Reference[v.PrimaryPart] = billboard
				end
			end)
			table.insert(currentConnections, connAdded)
			local connRemoved = collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
				if v.PrimaryPart and Reference[v.PrimaryPart] then
					Reference[v.PrimaryPart]:Destroy()
					Reference[v.PrimaryPart] = nil
				end
			end)
			table.insert(currentConnections, connRemoved)
			for _, v in collectionService:GetTagged(tag) do
				if v.PrimaryPart and not Reference[v.PrimaryPart] then
					local billboard = Instance.new('BillboardGui')
					billboard.Parent = Folder
					billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
					billboard.Size = UDim2.fromOffset(currentSize, currentSize)
					billboard.AlwaysOnTop = true
					billboard.ClipsDescendants = false
					billboard.Adornee = v.PrimaryPart
					local blur = addBlur(billboard)
					blur.Visible = Background.Enabled
					local image = Instance.new('ImageLabel')
					image.Size = UDim2.fromOffset(currentSize, currentSize)
					image.Position = UDim2.fromScale(0.5, 0.5)
					image.AnchorPoint = Vector2.new(0.5, 0.5)
					image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
					image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
					image.BorderSizePixel = 0
					image.Image = getAlchemistImage(v)
					image.Parent = billboard
					local uicorner = Instance.new('UICorner')
					uicorner.CornerRadius = UDim.new(0, 4)
					uicorner.Parent = image
					Reference[v.PrimaryPart] = billboard
				end
			end
			return
		end
		if tag == 'stars' then
			local connAdded = collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
				if v:IsA("Model") and v.PrimaryPart then
					task.wait(0.1)
					AddedStar(v.PrimaryPart)
				end
			end)
			table.insert(currentConnections, connAdded)
			local connRemoved = collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
				if v.PrimaryPart and Reference[v.PrimaryPart] then
					Reference[v.PrimaryPart]:Destroy()
					Reference[v.PrimaryPart] = nil
				end
			end)
			table.insert(currentConnections, connRemoved)
			for _, v in collectionService:GetTagged(tag) do
				if v:IsA("Model") and v.PrimaryPart then
					AddedStar(v.PrimaryPart)
				end
			end
			return
		end

		if tag == 'petrified-player' then
			local connAdded = collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
				if v.PrimaryPart and not isMineOnMyTeam(v.PrimaryPart) then
					Added(v.PrimaryPart, icon, false)
				end
			end)
			table.insert(currentConnections, connAdded)
			local connRemoved = collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
				if v.PrimaryPart and Reference[v.PrimaryPart] then
					Reference[v.PrimaryPart]:Destroy()
					Reference[v.PrimaryPart] = nil
				end
			end)
			table.insert(currentConnections, connRemoved)
			for _, v in collectionService:GetTagged(tag) do
				if v.PrimaryPart and not isMineOnMyTeam(v.PrimaryPart) then
					Added(v.PrimaryPart, icon, false)
				end
			end
			return
		end

		local connAdded = collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if tag == 'bee' and (v.Name:find('TamedBee') or v:FindFirstChild('TamedBee')) then return end
			Added(v.PrimaryPart, icon, false)
		end)
		table.insert(currentConnections, connAdded)
		local connRemoved = collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if Reference[v.PrimaryPart] then
				Reference[v.PrimaryPart]:Destroy()
				Reference[v.PrimaryPart] = nil
			end
		end)
		table.insert(currentConnections, connRemoved)
		for _, v in collectionService:GetTagged(tag) do
			if tag == 'bee' and (v.Name:find('TamedBee') or v:FindFirstChild('TamedBee')) then continue end
			Added(v.PrimaryPart, icon, false)
		end
	end

	local function addKitNon(objName, icon)
		if typeof(icon) == "boolean" then
			if objName == "Gravestone" then
				icon = "rbxassetid://6307844310"
			elseif objName == "Open" then
				icon = "rbxassetid://10159166528"
			else
				icon = bedwars.getIcon({itemType = icon}, true) or ''
			end
		else
			icon = bedwars.getIcon({itemType = icon}, true)
		end
		local connAdded = workspace.ChildAdded:Connect(function(child)
			if child:IsA("Model") and child.Name == objName then
				task.wait(0.1)
				if child.PrimaryPart then
					Added(child, icon, true)
				end
			end
		end)
		table.insert(currentConnections, connAdded)
		local connRemoved = workspace.ChildRemoved:Connect(function(child)
			if child:IsA("Model") and child.Name == objName then
				if Reference[child] then
					Reference[child]:Destroy()
					Reference[child] = nil
				end
			end
		end)
		table.insert(currentConnections, connRemoved)
	end

	local function addKitDescendant(partName, icon)
		local resolvedIcon = bedwars.getIcon({itemType = icon}, true)
		
		local function shouldSkip(obj)
			local p = obj.Parent
			while p and p ~= workspace do
				if p.Name == partName then return true end
				p = p.Parent
			end
			return false
		end

		scanDescendants(workspace, function(obj)
			if obj:IsA("BasePart") and obj.Name == partName and not shouldSkip(obj) then
				if not Reference[obj] then
					Added(obj, resolvedIcon, true)
				end
			end
		end)
		local connAdded = workspace.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") and obj.Name == partName and not shouldSkip(obj) then
				task.wait(0.1)
				if not Reference[obj] then
					Added(obj, resolvedIcon, true)
				end
			end
		end)
		table.insert(currentConnections, connAdded)
		local connRemoved = workspace.DescendantRemoving:Connect(function(obj)
			if obj:IsA("BasePart") and obj.Name == partName and Reference[obj] then
				Reference[obj]:Destroy()
				Reference[obj] = nil
			end
		end)
		table.insert(currentConnections, connRemoved)
	end

	local function setupKit(kitName)
		local kit = ESPKits[kitName]
		local nontag = NONTaggedKits[kitName]
		local desctag = DescendantKits[kitName]
		if kit then
			addKit(kit[1], kit[2])
		end
		if nontag then
			addKitNon(nontag[1], nontag[2])
		end
		if desctag then
			for _, entry in ipairs(desctag) do
				addKitDescendant(entry[1], entry[2])
			end
		end
	end

	KitESP = vape.Categories.Kits:CreateModule({
		Name = 'KitESP',
		Function = function(callback)
			local aeroAlive = newRun(KitESP)
			if callback then
				task.spawn(function()
					while aeroAlive() do
						if not currentKit then
							repeat
								task.wait()
							until store.equippedKit ~= '' or not KitESP.Enabled
							if not KitESP.Enabled then break end
						end
						local newKit = table.concat(getLocalKits(), ',')
						if newKit ~= currentKit then
							disconnectAll()
							Folder:ClearAllChildren()
							table.clear(Reference)
							for _, kit in ipairs(getLocalKits()) do
								setupKit(kit)
							end
							currentKit = newKit
						end
						task.wait(1)
					end
					disconnectAll()
					Folder:ClearAllChildren()
					table.clear(Reference)
					currentKit = nil
				end)
			else
				disconnectAll()
				Folder:ClearAllChildren()
				table.clear(Reference)
				currentKit = nil
			end
		end,
		Tooltip = 'esp for kits'
	})
	Notify = KitESP:CreateToggle({
		Name = "Notify",
		Default = false
	})
	Background = KitESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then Color.Object.Visible = callback end
			for _, v in Reference do
				v.ImageLabel.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
				v.Blur.Visible = callback
			end
		end,
		Default = true
	})
    Color = KitESP:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in Reference do
                v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                v.ImageLabel.BackgroundTransparency = 1 - opacity
            end
        end,
        Darker = true
    })
    Sizeable = KitESP:CreateToggle({
        Name = "Sizeable",
        Default = false,
        Function = function(callback)
            if callback then
                SizeSlider.Object.Visible = true
                currentSize = SizeSlider.Value or 36
                for _, v in Reference do
                    v.Size = UDim2.fromOffset(currentSize, currentSize)
                    v.ImageLabel.Size = UDim2.fromOffset(currentSize, currentSize)
                end
            else
                SizeSlider.Object.Visible = false
                currentSize = 36
                for _, v in Reference do
                    v.Size = UDim2.fromOffset(currentSize, currentSize)
                    v.ImageLabel.Size = UDim2.fromOffset(currentSize, currentSize)
                end
            end
        end
    })
    SizeSlider = KitESP:CreateSlider({
        Name = "Size",
        Default = 36,
        Min = 10,
        Max = 80,
        Visible = false,
        Function = function(value)
            if not Sizeable.Enabled then return end
            currentSize = value
            for _, v in Reference do
                v.Size = UDim2.fromOffset(value, value)
                v.ImageLabel.Size = UDim2.fromOffset(value, value)
            end
        end
    })

    task.defer(function()
        if Color and Color.Object then
            Color.Object.Visible = Background.Enabled  
        end
    end)
end)

run(function()
	local AutoKit
	local Legit
	local Targets
	local Toggles = {}
	local Running = {}
	local netFolder, abilityRemote

	local function getNet(name)
		if not netFolder then
			pcall(function()
				netFolder = getNetManaged()
			end)
		end
		return netFolder and netFolder:FindFirstChild(name)
	end

	local function useAbility(name, data)
		if not abilityRemote then
			pcall(function()
				abilityRemote = replicatedStorage['events-@easy-games/game-core:shared/game-core-networking@getEvents.Events'].useAbility
			end)
		end
		if abilityRemote then
			pcall(function()
				if data ~= nil then
					abilityRemote:FireServer(name, data)
				else
					abilityRemote:FireServer(name)
				end
			end)
		end
	end

	local function range(legit, blatant)
		return Legit.Enabled and legit or blatant
	end

	local function NewSession()
		local Session = {Tasks = {}, Active = true}

		function Session:Clean(Task)
			table.insert(self.Tasks, Task)
			return Task
		end

		function Session:Stop()
			self.Active = false
			if self.Thread and coroutine.status(self.Thread) ~= 'dead' then
				pcall(task.cancel, self.Thread)
			end
			for i = #self.Tasks, 1, -1 do
				local Task = self.Tasks[i]
				pcall(function()
					if type(Task) == 'function' then
						Task()
					elseif typeof(Task) == 'RBXScriptConnection' then
						Task:Disconnect()
					elseif typeof(Task) == 'Instance' then
						Task:Destroy()
					elseif type(Task) == 'table' then
						if Task.Disconnect then Task:Disconnect() elseif Task.Destroy then Task:Destroy() end
					end
				end)
			end
			table.clear(self.Tasks)
		end

		return Session
	end

	local function findTarget(dist, extra)
		if not entitylib.isAlive then return nil end
		local options = {
			Range = dist,
			Part = 'RootPart',
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled,
			Wallcheck = Targets.Walls.Enabled or nil,
			Sort = sortmethods.Distance
		}
		for k, v in extra or {} do
			options[k] = v
		end
		return entitylib.EntityPosition(options)
	end

	local function KitCollection(Session, Tag, Range, Callback)
		local Objects = type(Tag) == 'table' and Tag or collection(Tag, Session)
		repeat
			if entitylib.isAlive then
				local here = entitylib.character.RootPart.Position
				for _, v in Objects do
					if not Session.Active then break end
					local part = typeof(v) == 'Instance' and (v:IsA('BasePart') and v or (v:IsA('Model') and (v.PrimaryPart or v:FindFirstChildWhichIsA('BasePart', true))))
					if part and part.Parent and (part.Position - here).Magnitude <= Range() then
						pcall(Callback, v, part)
					end
				end
			end
			task.wait(0.1)
		until not Session.Active
	end

	local function sameTeam(plr)
		local mine, theirs = lplr:GetAttribute('Team'), plr:GetAttribute('Team')
		if mine ~= nil and theirs ~= nil then
			return mine == theirs
		end
		return lplr.Team ~= nil and plr.Team == lplr.Team
	end

	local AutoKitFunctions = {
		trapper = function(Session)
			local traps = setmetatable({}, {__mode = 'k'})
			local nextBoom = 0
			local function isExplosive(trap)
				local kind = tostring(trap:GetAttribute('trapType') or trap:GetAttribute('TrapType') or trap:GetAttribute('Type') or ''):lower()
				return kind:find('explosive', 1, true) or trap.Name:lower():find('explosive', 1, true) or trap:FindFirstChild('explosive_trap', true)
			end
			local function isMine(trap)
				local owner = tonumber(trap:GetAttribute('PlacedByUserId') or trap:GetAttribute('OwnerUserId') or trap:GetAttribute('PlayerUserId') or trap:GetAttribute('ownerId'))
				if owner then return owner == lplr.UserId end
				local team = trap:GetAttribute('TrapperTeamId') or trap:GetAttribute('TeamId')
				return team ~= nil and tostring(team) == tostring(lplr:GetAttribute('Team'))
			end
			local function radiusOf(trap)
				for _, name in {'TriggerRadius', 'DetonationRadius', 'ExplosionRadius', 'ActivationRadius', 'Radius'} do
					local value = tonumber(trap:GetAttribute(name))
					if value and value > 0 then return value end
				end
				local best = 0
				for _, part in trap:GetDescendants() do
					if part:IsA('BasePart') then
						local name = part.Name:lower()
						if name:find('radius', 1, true) or name:find('range', 1, true) or name:find('circle', 1, true) or name:find('trigger', 1, true) or name:find('hitbox', 1, true) then
							best = math.max(best, math.max(part.Size.X, part.Size.Z) / 2)
						end
					end
				end
				return best > 0 and best or 8
			end
			local function track(trap)
				task.wait()
				if trap.Parent and isExplosive(trap) and isMine(trap) then
					traps[trap] = true
				end
			end
			Session:Clean(collectionService:GetInstanceAddedSignal('trapper_trap'):Connect(track))
			Session:Clean(collectionService:GetInstanceRemovedSignal('trapper_trap'):Connect(function(trap)
				traps[trap] = nil
			end))
			for _, trap in collectionService:GetTagged('trapper_trap') do
				task.spawn(track, trap)
			end
			repeat
				if tick() >= nextBoom then
					for trap in traps do
						local part = trap.Parent and (trap:IsA('BasePart') and trap or trap.PrimaryPart or trap:FindFirstChildWhichIsA('BasePart', true))
						if not part then
							traps[trap] = nil
							continue
						end
						local reach = radiusOf(trap)
						for _, plr in playersService:GetPlayers() do
							local root = plr ~= lplr and not sameTeam(plr) and plr.Character and plr.Character:FindFirstChild('HumanoidRootPart')
							local hum = root and plr.Character:FindFirstChildOfClass('Humanoid')
							if hum and hum.Health > 0 and (root.Position - part.Position).Magnitude <= reach then
								nextBoom = tick() + 0.25
								useAbility('trapper_detonate')
								break
							end
						end
						if tick() < nextBoom then break end
					end
				end
				task.wait(0.03)
			until not Session.Active
		end,

		jellyfish = function(Session)
			local jellies = collection('jellyfish', Session, function(list, obj)
				task.delay(0, function()
					if obj:GetAttribute('PlacedByUserId') == lplr.UserId then
						table.insert(list, obj)
					end
				end)
			end)
			repeat
				if entitylib.isAlive and bedwars.AbilityController:canUseAbility('electrify_jellyfish') then
					for _, jelly in jellies do
						if jelly.PrimaryPart and findTarget(range(14, 18), {Origin = jelly.PrimaryPart.Position, Wallcheck = nil}) then
							bedwars.AbilityController:useAbility('electrify_jellyfish')
							break
						end
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		tinker = function(Session)
			local abilityNames = {
				'hephaestus_self_repair', 'tinker_self_repair', 'hephaestus_repair', 'tinker_repair',
				'HEPHAESTUS_SELF_REPAIR', 'TINKER_SELF_REPAIR', 'HEPHAESTUS_REPAIR', 'TINKER_REPAIR',
				'self_repair', 'SELF_REPAIR', 'shield_repair', 'SHIELD_REPAIR', 'kit_repair', 'KIT_REPAIR'
			}
			local repairingUntil = 0
			local function kitShield(char)
				local best = 0
				for name, value in char:GetAttributes() do
					if name:find('Shield') and type(value) == 'number' and value > best and name ~= 'Shield_POTION' and name ~= 'TotalShield' then
						best = value
					end
				end
				return best
			end
			local function repair()
				local names = table.clone(abilityNames)
				for _, obj in {lplr.Character, lplr} do
					if obj then
						for _, value in obj:GetAttributes() do
							if type(value) == 'string' and value:lower():find('repair') and not table.find(names, value) then
								table.insert(names, 1, value)
							end
						end
					end
				end
				for _, name in names do
					local ok, can = pcall(bedwars.AbilityController.canUseAbility, bedwars.AbilityController, name)
					if ok and can then
						pcall(bedwars.AbilityController.useAbility, bedwars.AbilityController, name)
						return true
					end
				end
				return false
			end
			local function attackUnlocked()
				return not Legit.Enabled and tick() < repairingUntil
			end
			local oldClicking = bedwars.SwordController.isClickingTooFast
			bedwars.SwordController.isClickingTooFast = function(self, ...)
				if attackUnlocked() then
					return false
				end
				return oldClicking(self, ...)
			end
			Session:Clean(function()
				bedwars.SwordController.isClickingTooFast = oldClicking
			end)
			local function watchStun(char)
				if not char then return end
				Session:Clean(char:GetAttributeChangedSignal('StunnedUntilTime'):Connect(function()
					local value = char:GetAttribute('StunnedUntilTime')
					if attackUnlocked() and value and value > workspace:GetServerTimeNow() then
						pcall(function() char:SetAttribute('StunnedUntilTime', 0) end)
					end
				end))
			end
			watchStun(lplr.Character)
			Session:Clean(lplr.CharacterAdded:Connect(watchStun))
			local maxShield, lastRepair, wasAlive = 0, 0, false
			repeat
				task.wait(0.1)
				local char = entitylib.isAlive and lplr.Character
				if not char then
					maxShield, wasAlive = 0, false
					continue
				end
				local current = kitShield(char)
				if not wasAlive or current > maxShield then
					maxShield = current
				end
				wasAlive = true
				if maxShield > 0 and current <= maxShield * 0.5 and tick() - lastRepair >= 6 and repair() then
					lastRepair = tick()
					repairingUntil = tick() + 2
				end
			until not Session.Active
		end,

		soul_broker = function(Session)
			local linked = {}
			repeat
				local ent = findTarget(range(14, 60))
				local count = 0
				for _ in linked do count += 1 end
				if ent and ent.Character and count < 8 and not linked[ent.Character] then
					local char = ent.Character
					useAbility('soul_link')
					task.wait(0.1)
					local remote = getNet('AttemptSoulLink')
					local ok, result = pcall(function() return remote:InvokeServer(char) end)
					if ok and type(result) == 'table' and result.result then
						linked[char] = true
						Session:Clean(char.AncestryChanged:Connect(function()
							if not char.Parent then linked[char] = nil end
						end))
					end
				end
				task.wait(0.3)
			until not Session.Active
		end,

		warrior = function(Session)
			repeat
				if (lplr:GetAttribute('Grit') or 0) >= 100 and findTarget(range(14, 40)) then
					useAbility('warrior_strike')
				end
				task.wait(0.1)
			until not Session.Active
		end,

		builder = function(Session)
			local fortified = {}
			local shapes = {}
			local function pyramid(size)
				if shapes[size] then return shapes[size] end
				local list = {}
				for h = size, 0, -1 do
					for w = h, 0, -1 do
						table.insert(list, Vector3.new(w, size - h, (h + 1) - w) * 3)
						table.insert(list, Vector3.new(-w, size - h, (h + 1) - w) * 3)
						table.insert(list, Vector3.new(w, size - h, -(h - w)) * 3)
						table.insert(list, Vector3.new(-w, size - h, -(h - w)) * 3)
					end
				end
				shapes[size] = list
				return list
			end
			repeat
				local team = lplr:GetAttribute('Team')
				local bedCFrame
				for _, bed in collectionService:GetTagged('bed') do
					if team and bed.Parent and bed:GetAttribute('Team' .. team .. 'NoBreak') then
						bedCFrame = bed:IsA('BasePart') and bed.CFrame or bed:GetPivot()
						break
					end
				end
				local remote = getNet('FortifyBlock')
				if bedCFrame and remote then
					for layer = 1, 3 do
						local sent = false
						for _, offset in pyramid(layer) do
							if not Session.Active then break end
							local block, rounded = getPlacedBlock((bedCFrame * CFrame.new(offset)).Position)
							if block and block.Name ~= 'bed' and fortified[tostring(rounded)] ~= block then
								pcall(function() remote:FireServer(rounded) end)
								fortified[tostring(rounded)] = block
								sent = true
								task.wait(0.05)
							end
						end
						if sent then break end
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		dragon_slayer = function(Session)
			local controller = bedwars.DragonSlayerController
			local oldPunch = controller and controller.playPunchAnimation
			if oldPunch then
				controller.playPunchAnimation = function(self, look)
					if Legit.Enabled then
						return oldPunch(self, look)
					end
					local Maid = debug.getupvalue(oldPunch, 1)
					local AnimUtil = debug.getupvalue(oldPunch, 2)
					local Players = debug.getupvalue(oldPunch, 3)
					local AnimType = debug.getupvalue(oldPunch, 4)
					local Run = debug.getupvalue(oldPunch, 6)
					local maid = Maid.new()
					local track = AnimUtil:playAnimation(Players.LocalPlayer, AnimType.DRAGON_SLAYER_PUNCH)
					maid:GiveTask(function()
						if track then track:Stop() end
					end)
					maid:GiveTask(Run.Heartbeat:Connect(function()
						local char = Players.LocalPlayer.Character
						if not (char and char.PrimaryPart) then
							maid:DoCleaning()
							return
						end
						char:PivotTo(CFrame.new(char:GetPrimaryPartCFrame().Position) * look)
					end))
					task.delay(0.46, function()
						maid:DoCleaning()
					end)
					return maid
				end
				Session:Clean(function()
					controller.playPunchAnimation = oldPunch
				end)
			end
			local cooldown = {}
			repeat
				local punched = false
				if entitylib.isAlive and controller and controller.dragonEmblems then
					local here = entitylib.character.RootPart.Position
					local list = {}
					for model, emblem in controller.dragonEmblems do
						if emblem.stackCount >= 3 and model.PrimaryPart and (here - model.PrimaryPart.Position).Magnitude <= range(14, 18) then
							table.insert(list, model)
						end
					end
					table.sort(list, function(a, b)
						return (here - a.PrimaryPart.Position).Magnitude < (here - b.PrimaryPart.Position).Magnitude
					end)
					for _, model in list do
						if not Session.Active then break end
						if not cooldown[model] and bedwars.AbilityController:canUseAbility('dragon_slayer_punch', {disableBlockedAbilityAlert = true}) then
							if Legit.Enabled then
								task.wait(1)
							end
							cooldown[model] = true
							task.delay(0.4, function() cooldown[model] = nil end)
							local char = lplr.Character
							if char and char.PrimaryPart and model.PrimaryPart then
								local from = char:GetPivot().Position
								local look = CFrame.new(from, model.PrimaryPart.Position * Vector3.new(1, 0, 1) + Vector3.new(0, from.Y, 0))
								char:PivotTo(look)
								pcall(function() controller:playPunchAnimation(look - look.Position) end)
								useAbility('dragon_slayer_punch')
								punched = true
								task.wait(0.2)
							end
						end
					end
				end
				task.wait(punched and 0.15 or 0.1)
			until not Session.Active
		end,

		spirit_gardener = function(Session)
			local gardener = bedwars.SpiritGardenerController
			local oldCharge = gardener and gardener.disableActionsOnCharge
			if oldCharge then
				gardener.disableActionsOnCharge = function(self, maid, character)
					if Legit.Enabled or character ~= lplr.Character then
						return oldCharge(self, maid, character)
					end
					local Knit = bedwars.KnitClient
					Knit.Controllers.SwordController:toggleSwordSwing(true)
					Knit.Controllers.BlockPlacementController:disableBlockPlacer()
					local SyncEvents = debug.getupvalue(oldCharge, 3)
					local block = SyncEvents.BeginProjectileTargeting:connect(function(event)
						event:setCancelled(true)
					end)
					local jump = Knit.Controllers.JumpHeightController:getJumpModifier():addModifier({jumpHeightMultiplier = 0})
					maid:GiveTask(function()
						Knit.Controllers.SwordController:toggleSwordSwing(false)
						Knit.Controllers.BlockPlacementController:enableBlockPlacer()
						block:Destroy()
						jump.Destroy()
					end)
				end
				Session:Clean(function()
					gardener.disableActionsOnCharge = oldCharge
				end)
			end
			local seeds = bedwars.SpiritGardenerSeedController
			local oldPickup = seeds and seeds.checkForPickup
			if oldPickup then
				seeds.checkForPickup = function(self)
					local char = lplr.Character
					if not char or not char.PrimaryPart then return nil end
					local here = char.PrimaryPart.Position
					for _, kind in self:validCollectableEntityTypes() do
						for _, orb in collectionService:GetTagged(kind) do
							local spawned = orb:GetAttribute('SpawnTime')
							if spawned and workspace:GetServerTimeNow() - spawned >= 1 and (here - orb:GetPivot().Position).Magnitude <= 12 then
								self:collectEntity(lplr, orb, kind)
							end
						end
					end
				end
				Session:Clean(function()
					seeds.checkForPickup = oldPickup
				end)
				pcall(function() seeds:listenToPickup() end)
			end
			repeat
				local watered = false
				if entitylib.isAlive then
					local here = entitylib.character.RootPart.Position
					for _, flower in collectionService:GetTagged('SpiritGardenerFlower') do
						if flower:IsA('Model') and flower.PrimaryPart and flower:GetAttribute('PlacedByUserId') == lplr.UserId and not flower:GetAttribute('HasFullyGrown') and (here - flower.PrimaryPart.Position).Magnitude <= range(14, 20) then
							useAbility('spirit_gardener_water')
							watered = true
							break
						end
					end
				end
				task.wait(watered and 0.6 or 0.5)
			until not Session.Active
		end,

		hannah = function(Session)
			KitCollection(Session, 'HannahExecuteInteraction', function() return range(14, 16) end, function(victim, part)
				if not Legit.Enabled and isAboveVoid(part.Position) then return end
				local remote = bedwars.Client:Get(remotes.HannahPromptTrigger).instance
				if remote:InvokeServer({user = lplr, victimEntity = victim}) then
					local icon = victim:FindFirstChild('Hannah Execution Icon')
					if icon then icon:Destroy() end
				end
				task.wait(0.05)
			end)
		end,

		mimic = function(Session)
			repeat
				if entitylib.isAlive and Targets.Players.Enabled then
					local here = entitylib.character.RootPart.Position
					for _, ent in entitylib.List do
						if not Session.Active then break end
						if ent.Targetable and ent.Player and ent.Character and ent.RootPart and (ent.RootPart.Position - here).Magnitude <= range(14, 18) and collectionService:HasTag(ent.Character, 'MimicBLockPickPocketPlayer') then
							if not Targets.Walls.Enabled or not entitylib.Wallcheck(here, ent.RootPart.Position, true, ent) then
								pcall(function()
									bedwars.Client:Get(remotes.MimicBlockPickPocketPlayer).instance:InvokeServer(ent.Player)
								end)
								task.wait(0.5)
							end
						end
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		spirit_assassin = function(Session)
			KitCollection(Session, 'EvelynnSoul', function() return range(14, 150) end, function(spirit)
				bedwars.SpiritAssassinController:useSpirit(lplr, spirit)
				task.wait(0.1)
			end)
		end,

		void_dragon = function(Session)
			local dragon = bedwars.VoidDragonController
			local oldFlap = dragon and dragon.flapWings
			if oldFlap then
				dragon.flapWings = function(self, ...)
					local result = oldFlap(self, ...)
					if not Legit.Enabled and result ~= false and self.inDragonForm then
						self.SpeedMaid:GiveTask(bedwars.SprintController:getMovementStatusModifier():addModifier({
							blockSprint = true,
							constantSpeedMultiplier = 2
						}))
					end
					return result
				end
				Session:Clean(function()
					dragon.flapWings = oldFlap
				end)
			end
			repeat
				if dragon and dragon.inDragonForm and findTarget(range(14, 60)) then
					local remote = getNet('DragonBreath')
					if remote then
						pcall(function() remote:FireServer({player = lplr}) end)
					end
					task.wait(1)
				end
				task.wait(0.1)
			until not Session.Active
		end,

		cactus = function(Session)
			repeat
				if bedwars.AbilityController:canUseAbility('cactus_fire') and findTarget(range(14, 40)) then
					pcall(function() bedwars.AbilityController:useAbility('cactus_fire') end)
					task.wait(0.5)
				end
				task.wait(0.1)
			until not Session.Active
		end,

		card = function(Session)
			repeat
				if bedwars.AbilityController:canUseAbility('CARD_THROW') then
					local ent = findTarget(12)
					if ent and ent.Character then
						useAbility('CARD_THROW', {targetEntityInstance = ent.Character})
						task.wait(0.5)
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		mage = function(Session)
			KitCollection(Session, 'ElementTome', function() return range(14, 30) end, function(tome)
				local secret = tome:GetAttribute('TomeSecret')
				if not secret then return end
				pcall(function() bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.PUNCH) end)
				pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM) end)
				local result = bedwars.Client:Get(remotes.LearnElementTome).instance:InvokeServer({secret = secret})
				if type(result) == 'table' and result.success then
					tome:Destroy()
					task.wait(0.5)
				end
			end)
		end,

		warlock = function(Session)
			local last
			repeat
				if entitylib.isAlive and store.hand.tool and store.hand.tool.Name == 'warlock_staff' then
					local dist = range(10, 20)
					if last then
						local hum = last:FindFirstChildOfClass('Humanoid')
						local root = last:FindFirstChild('HumanoidRootPart')
						if not last.Parent or not hum or hum.Health <= 0 or not root or (root.Position - entitylib.character.RootPart.Position).Magnitude > dist then
							last = nil
						end
					end
					if not last then
						local ent = findTarget(dist)
						if ent and ent.Character then
							last = ent.Character
							pcall(function() bedwars.AbilityController:useAbility('WARLOCK_LINK') end)
							task.wait(0.1)
							pcall(function() bedwars.Client:Get(remotes.WarlockTarget):CallServer({target = last}) end)
						end
					end
				else
					last = nil
				end
				task.wait(0.3)
			until not Session.Active
		end,

		drill = function(Session)
			local useDrill, drillAttack = getNet('PlayerUseDrillController'), getNet('DrillAttack')
			local lastShot = 0
			local function release()
				pcall(function()
					local Knit = bedwars.KnitClient
					local tablet = Knit.Controllers.DrillTabletController
					if tablet then
						if tablet.sessionMaid then tablet.sessionMaid:DoCleaning() end
						tablet.enabled = false
						tablet.lastAttackTime = 0
					end
					local item = Knit.Controllers.DrillItemController
					if item and item.sessionMaid then item.sessionMaid:DoCleaning() end
					gameCamera.CameraSubject = entitylib.character and entitylib.character.Humanoid or gameCamera.CameraSubject
					gameCamera.CameraType = Enum.CameraType.Custom
				end)
			end
			local drills = {}
			for _, obj in workspace:GetDescendants() do
				if obj:IsA('Model') and obj.Name == 'Drill' then drills[obj] = true end
			end
			Session:Clean(workspace.DescendantAdded:Connect(function(obj)
				if obj:IsA('Model') and obj.Name == 'Drill' then drills[obj] = true end
			end))
			repeat
				local acted = false
				if entitylib.isAlive and useDrill and drillAttack and tick() - lastShot >= 0.3 then
					for drill in drills do
						if not drill.Parent then
							drills[drill] = nil
							continue
						end
						if drill:GetAttribute('PlacedByUserId') == lplr.UserId then
							local head = drill:FindFirstChild('Head') or drill.PrimaryPart or drill:FindFirstChildWhichIsA('BasePart')
							local ent = head and findTarget(range(14, 18), {Origin = head.Position})
							if ent and ent.RootPart then
								pcall(function() useDrill:InvokeServer({drill = drill}) end)
								release()
								pcall(function() drillAttack:FireServer({targetPosition = ent.RootPart.Position}) end)
								pcall(function() useDrill:InvokeServer({}) end)
								release()
								lastShot = tick()
								acted = true
								break
							end
						end
					end
				end
				task.wait(acted and 0.05 or 0.15)
			until not Session.Active
		end,

		ghost_catcher = function(Session)
			KitCollection(Session, 'ghost', function() return range(14, 30) end, function(ghost)
				if Legit.Enabled and not isHoldingItem({'vacuum'}) then return end
				local id = ghost:GetAttribute('Id') or ghost:GetAttribute('id') or ghost:GetAttribute('CollectableId') or tonumber(ghost.Name:match('%d+'))
				local remote = getNet('CollectCollectableEntity')
				if id and remote then
					remote:FireServer({id = id})
					task.wait(0.1)
				end
			end)
		end,

		rebellion_leader = function(Session)
			repeat
				local hum = entitylib.isAlive and entitylib.character.Humanoid
				if hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth <= 0.5 then
					useAbility('rebellion_shield')
					if lplr:GetAttribute('LeaderAuraType') ~= 'healing' then
						useAbility('rebellion_aura_swap')
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		miner = function(Session)
			KitCollection(Session, 'petrified-player', function() return range(6, 10) end, function(rock)
				local id = rock:GetAttribute('PetrifyId') or rock:GetAttribute('petrifyId')
				if id then
					bedwars.Client:Get(remotes.DestroyPetrifiedPlayer):SendToServer({petrifyId = id})
				end
			end)
		end,

		dragon_sword = function(Session)
			repeat
				local ent = findTarget(range(14, 18))
				local remote = getNet('DragonSwordFire')
				if ent and ent.Character and remote then
					pcall(function() remote:FireServer({target = ent.Character}) end)
					task.wait(0.5)
				end
				task.wait(0.1)
			until not Session.Active
		end,

		ice_queen = function(Session)
			repeat
				if entitylib.isAlive then
					local here = entitylib.character.RootPart.Position
					for _, ent in entitylib.List do
						local allowed = ent.Player and Targets.Players.Enabled or not ent.Player and Targets.NPCs.Enabled
						if allowed and ent.Targetable and ent.Character and ent.RootPart and (ent.RootPart.Position - here).Magnitude <= range(14, 60) and (ent.Character:GetAttribute('IceQueenStacks') or 0) >= 4 then
							if not Targets.Walls.Enabled or not entitylib.Wallcheck(here, ent.RootPart.Position, true, ent) then
								useAbility('ice_queen')
								task.wait(0.5)
								break
							end
						end
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		styx = function(Session)
			local entrance, exit = nil, ''
			local function enemyClose()
				if not entitylib.isAlive then return false end
				local here = entitylib.character.RootPart.Position
				for _, ent in entitylib.List do
					if ent.Targetable and ent.RootPart and (ent.RootPart.Position - here).Magnitude <= 10 then
						return true
					end
				end
				return false
			end
			Session:Clean(bedwars.Client:Get(remotes.StyxSpawnEntrancePortal):Connect(function(data)
				if data.entrancePortalData.player == lplr then
					entrance = data.entrancePortalData
				end
			end))
			Session:Clean(bedwars.Client:Get(remotes.StyxSpawnExitPortal):Connect(function(data)
				exit = data.exitPortalData.uuid
				task.spawn(function()
					repeat task.wait(0.1) until not Session.Active or enemyClose()
					if Session.Active and exit ~= '' then
						pcall(function() getNet('StyxTryOpenExitPortalFromClient'):InvokeServer(exit) end)
					end
				end)
			end))
			Session:Clean(bedwars.Client:Get(remotes.StyxExitPortal):Connect(function()
				if entrance then
					task.wait(0.1)
					bedwars.Client:Get(remotes.StyxPortal):SendToServer({entrancePortalData = entrance})
				end
			end))
		end,

		sorcerer = function(Session)
			KitCollection(Session, 'alchemy_crystal', function() return 10 end, function(crystal)
				local id = crystal:GetAttribute('Id') or crystal:GetAttribute('id') or crystal:GetAttribute('CollectableId') or tonumber(crystal.Name:match('%d+'))
				local remote = getNet('CollectCollectableEntity')
				if id and remote then
					pcall(function() bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH) end)
					pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM) end)
					remote:FireServer({id = id, collectableName = 'AlchemyCrystal'})
					task.wait(0.1)
				end
			end)
		end,

		hatter = function(Session)
			local app = lplr.PlayerGui:WaitForChild('NotificationApp', 10)
			if not app or not Session.Active then return end
			Session:Clean(app.DescendantAdded:Connect(function(obj)
				if obj:IsA('TextLabel') and obj.Text:lower():find('teleport') then
					task.spawn(function()
						task.wait(0.05)
						for _ = 1, 10 do
							if not Session.Active then break end
							if bedwars.AbilityController:canUseAbility('HATTER_TELEPORT') then
								bedwars.AbilityController:useAbility('HATTER_TELEPORT')
								break
							end
							task.wait(0.05)
						end
					end)
				end
			end))
		end,

		necromancer = function(Session)
			KitCollection(Session, 'Gravestone', function() return range(12, 40) end, function(grave)
				local secret = grave:GetAttribute('GravestoneSecret')
				if not secret then return end
				local result = bedwars.Client:Get(remotes.ActivateGravestone).instance:InvokeServer({
					skeletonData = {
						armorType = grave:GetAttribute('ArmorType'),
						weaponType = grave:GetAttribute('SwordType'),
						associatedPlayerUserId = grave:GetAttribute('GravestonePlayerUserId')
					},
					secret = secret,
					position = grave:GetAttribute('GravestonePosition')
				})
				if type(result) == 'table' and result.success then
					local controller = bedwars.Knit.Controllers.NecromancerController
					if controller then
						pcall(function() controller:useGravestone(lplr, grave) end)
					end
				end
				task.wait(0.1)
			end)
		end,

		midnight = function(Session)
			repeat
				if bedwars.AbilityController:canUseAbility('midnight') and findTarget(range(14, 40)) then
					pcall(function() bedwars.AbilityController:useAbility('midnight') end)
					task.wait(0.5)
				end
				task.wait(0.1)
			until not Session.Active
		end,

		defender = function(Session)
			repeat
				local controller = entitylib.isAlive and bedwars.Knit.Controllers.DefenderKitController
				if controller and controller.currentSchematic then
					for blockPos, blockType in controller.currentSchematic do
						if not Session.Active or not entitylib.isAlive then break end
						pcall(function()
							local mode = bedwars.Store:getState().Kit.defenderScannerMode
							if mode == 'upgrade' then
								controller:requestScannerAction(blockPos, 'upgrade', blockType)
							elseif mode == 'refund' then
								controller:requestScannerAction(blockPos, 'refund')
							else
								controller:requestPlaceDefenderBlock(blockPos)
							end
						end)
						task.wait(0.05)
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		block_kicker = function(Session)
			repeat
				if entitylib.isAlive then
					local blocks = (lplr.Character and lplr.Character:GetAttribute('BlockKickerKit_BlockCount')) or lplr:GetAttribute('BlockKickerKit_BlockCount') or 0
					if blocks <= 0 and bedwars.AbilityController:canUseAbility('BLOCK_STOMP') then
						pcall(function() bedwars.AbilityController:useAbility('BLOCK_STOMP') end)
						task.wait(0.8)
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		jailor = function(Session)
			KitCollection(Session, 'jailor_soul', function() return range(14, 40) end, function(soul)
				bedwars.JailorController:collectEntity(lplr, soul, 'JailorSoul')
				task.wait(0.1)
			end)
		end,

		grim_reaper = function(Session)
			repeat
				local controller = bedwars.GrimReaperController
				local char = entitylib.isAlive and lplr.Character
				local health, maxHealth = char and char:GetAttribute('Health'), char and char:GetAttribute('MaxHealth')
				if controller and controller.soulsByPosition and health and maxHealth and health <= maxHealth / 4 and not char:GetAttribute('GrimReaperChannel') then
					local here = entitylib.character.RootPart.Position
					for _, soul in controller.soulsByPosition do
						if not Session.Active then break end
						local part = typeof(soul) == 'Instance' and (soul:IsA('BasePart') and soul or soul.PrimaryPart)
						local secret = part and soul:GetAttribute('GrimReaperSoulSecret')
						if secret and (here - part.Position).Magnitude <= range(14, 150) then
							pcall(function() bedwars.Client:Get(remotes.ConsumeSoul):CallServer({secret = secret}) end)
							task.wait(0.1)
						end
					end
				end
				task.wait(0.1)
			until not Session.Active
		end,

		gun_blade = function(Session)
			repeat
				local ent = findTarget(range(10, 40))
				local remote = getNet('HandGunFireRequest')
				if ent and ent.RootPart and remote then
					local dir = (ent.RootPart.Position - entitylib.character.RootPart.Position).Unit
					pcall(function() remote:InvokeServer({lookVector = dir}) end)
					useAbility('hand_gun')
				end
				task.wait()
			until not Session.Active
		end,

		sheep_herder = function(Session)
			local tame = bedwars.Client:GetNamespace('SheepHerder'):Get('TameSheep')
			repeat
				local model = workspace:FindFirstChild('SheepModel')
				if entitylib.isAlive and model then
					local here = entitylib.character.RootPart.Position
					for _, sheep in model:GetChildren() do
						if not Session.Active then break end
						if sheep.PrimaryPart and (not Legit.Enabled or (here - sheep.PrimaryPart.Position).Magnitude <= 14) then
							task.wait(0.1)
							tame:SendToServer(sheep.SheepData.Value)
						end
					end
				end
				task.wait(0.1)
			until not Session.Active
		end
	}

	local Tooltips = {
		jellyfish = 'legit = shocks enemies 14 studs from ur jelly, off = 18 studs',
		tinker = 'repairs ur shield at 50%, legit = just repairs, off = also lets u attack while repairing',
		soul_broker = 'legit = links enemies within 14 studs, off = 60 studs',
		warrior = 'legit = strikes enemies within 14 studs, off = 40 studs',
		dragon_slayer = 'legit = punches within 14 studs with a delay and normal slow, off = 18 studs, no delay, no slow',
		spirit_gardener = 'legit = waters flowers within 14 studs with normal slow, off = 20 studs with no slow',
		hannah = 'legit = executes within 14 studs, off = 16 studs and skips anyone over the void',
		mimic = 'legit = pickpockets within 14 studs, off = 18 studs',
		spirit_assassin = 'legit = uses spirits within 14 studs, off = 150 studs',
		void_dragon = 'legit = breathes on enemies within 14 studs with normal flying, off = 60 studs with fast fly',
		cactus = 'legit = shoots enemies within 14 studs, off = 40 studs',
		mage = 'legit = learns tomes within 14 studs, off = 30 studs',
		warlock = 'legit = links enemies within 10 studs, off = 20 studs',
		drill = 'legit = ur drill shoots enemies within 14 studs, off = 18 studs',
		ghost_catcher = 'legit = catches ghosts within 14 studs with ur vacuum out, off = 30 studs any time',
		miner = 'legit = frees petrified players within 6 studs, off = 10 studs',
		dragon_sword = 'legit = fires at enemies within 14 studs, off = 18 studs',
		ice_queen = 'legit = freezes enemies within 14 studs, off = 60 studs',
		necromancer = 'legit = raises gravestones within 12 studs, off = 40 studs',
		midnight = 'legit = uses nyx with enemies within 14 studs, off = 40 studs',
		jailor = 'legit = grabs souls within 14 studs, off = 40 studs',
		grim_reaper = 'legit = eats souls within 14 studs, off = 150 studs',
		gun_blade = 'legit = shoots enemies within 10 studs, off = 40 studs',
		sheep_herder = 'legit = tames sheep within 14 studs, off = any distance'
	}

	local function StopKits()
		for Kit, Session in Running do
			Running[Kit] = nil
			Session:Stop()
		end
	end

	local function EquippedKits()
		if type(store.equippedKits) == 'table' and #store.equippedKits > 0 then
			return store.equippedKits
		end
		return {store.equippedKit}
	end

	local function SyncKits()
		local Kits = EquippedKits()
		for Kit, Session in Running do
			if not table.find(Kits, Kit) or not Toggles[Kit].Enabled then
				Running[Kit] = nil
				Session:Stop()
			end
		end
		for _, Kit in Kits do
			if AutoKitFunctions[Kit] and Toggles[Kit] and Toggles[Kit].Enabled and not Running[Kit] then
				local Session = NewSession()
				Running[Kit] = Session
				Session.Thread = task.spawn(function()
					local ok, err = pcall(AutoKitFunctions[Kit], Session)
					if not ok then
						warn('[aerov4] autokit ' .. Kit .. ': ' .. tostring(err))
					end
				end)
			end
		end
	end

	AutoKit = vape.Categories.Kits:CreateModule({
		Name = 'AutoKit',
		Function = function(Callback)
			local aeroAlive = newRun(AutoKit)
			if Callback then
				AutoKit:Clean(StopKits)
				repeat
					if store.matchState ~= 0 then
						SyncKits()
					end
					task.wait(0.5)
				until not aeroAlive()
			else
				StopKits()
			end
		end,
		Tooltip = 'uses ur kit for u, works for every kit below when u have it equipped'
	})
	Legit = AutoKit:CreateToggle({
		Name = 'Legit',
		Default = true,
		Tooltip = 'keeps every kit at a normal range (6 to 14 studs), turn it off for full range and the blatant extras'
	})
	Targets = AutoKit:CreateTargets({
		Players = true,
		NPCs = true
	})

	local function KitName(Kit)
		local Meta = bedwars.BedwarsKitMeta[Kit]
		return Meta and Meta.name or Kit
	end

	local SortTable = {}
	for Kit in AutoKitFunctions do
		table.insert(SortTable, Kit)
	end
	table.sort(SortTable, function(A, B)
		return KitName(A) < KitName(B)
	end)
	for _, Kit in SortTable do
		Toggles[Kit] = AutoKit:CreateToggle({
			Name = KitName(Kit),
			Default = true,
			Tooltip = Tooltips[Kit],
			Function = function()
				if AutoKit.Enabled then
					SyncKits()
				end
			end
		})
	end
end)

run(function()
    local Mode
    local Expand
    local AutoToggle
    local Visible
    local VisibleColor
    local Targets
    local objects = {}
    local set = false
    local hitboxesActive = false
    local autoToggleConnection = nil
    local autoToggleFrameCounter = 0

    local vector3new = Vector3.new
    local vector3one = Vector3.one

    local colorList = {
        Red = Color3.fromRGB(255, 0, 0),
        Blue = Color3.fromRGB(0, 100, 255),
        Green = Color3.fromRGB(0, 255, 0),
        Yellow = Color3.fromRGB(255, 255, 0),
        Orange = Color3.fromRGB(255, 140, 0),
        Purple = Color3.fromRGB(180, 0, 255),
        White = Color3.fromRGB(255, 255, 255),
        Cyan = Color3.fromRGB(0, 255, 255),
        Pink = Color3.fromRGB(255, 50, 150),
        Black = Color3.fromRGB(0, 0, 0)
    }

    local function shouldCreateHitbox(ent)
        if not ent.Targetable then return false end
        if ent.Player and Targets and Targets.Players and Targets.Players.Enabled then return true end
        if not ent.Player and Targets and Targets.NPCs and Targets.NPCs.Enabled then return true end
        return false
    end

    local _wallRayParams = RaycastParams.new()
    _wallRayParams.FilterType = Enum.RaycastFilterType.Exclude
    local function isTargetBehindWall(ent)
        if not Targets or not Targets.Walls or not Targets.Walls.Enabled then return false end
        if not ent.RootPart then return false end
        if not entitylib.isAlive or not entitylib.character or not entitylib.character.RootPart then return false end
        local origin = entitylib.character.RootPart.Position
        local target = ent.RootPart.Position
        local direction = target - origin
        _wallRayParams.FilterDescendantsInstances = {entitylib.character, ent.Character}
        local result = workspace:Raycast(origin, direction, _wallRayParams)
        if result then
            local hitDist = (result.Position - origin).Magnitude
            local targetDist = direction.Magnitude
            if hitDist < targetDist - 0.5 then return true end
        end
        return false
    end

    local cachedExpandSize = vector3new(3, 6, 3)
    local lastExpandValue = 0
    local function updateExpandSize(val)
        if val ~= lastExpandValue then
            lastExpandValue = val
            cachedExpandSize = vector3new(3, 6, 3) + vector3one * (val / 5)
        end
    end

    local function createHitbox(ent)
        if not shouldCreateHitbox(ent) then return end
        if isTargetBehindWall(ent) then return end
        if objects[ent] then return end
        for _, old in ent.Character:GetChildren() do
            if old.Name == 'AeroHitbox' then old:Destroy() end
        end
        local hitbox = Instance.new('Part')
        hitbox.Name = 'AeroHitbox'
        hitbox.Archivable = false
        hitbox.Size = cachedExpandSize
        hitbox.Position = ent.RootPart.Position
        hitbox.CanCollide = false
        hitbox.Massless = true
        hitbox.Transparency = Visible and Visible.Enabled and 0.5 or 1
        hitbox.LocalTransparencyModifier = Visible and Visible.Enabled and 0 or 1
        if Visible and Visible.Enabled and VisibleColor then
            hitbox.Color = colorList[VisibleColor.Value] or colorList.Red
        end
        hitbox.Parent = ent.Character
        local weld = Instance.new('Motor6D')
        weld.Part0 = hitbox
        weld.Part1 = ent.RootPart
        weld.Parent = hitbox
        local ev = Instance.new('ObjectValue')
        ev.Name = 'EntityValue'
        ev.Value = ent.Character
        ev.Parent = hitbox
        game:GetService('CollectionService'):AddTag(hitbox, 'Hitbox')
        hitbox:GetPropertyChangedSignal('Transparency'):Connect(function()
            local want = Visible and Visible.Enabled and 0.5 or 1
            if hitbox.Transparency ~= want then
                hitbox.Transparency = want
            end
        end)
        hitbox:GetPropertyChangedSignal('LocalTransparencyModifier'):Connect(function()
            local want = Visible and Visible.Enabled and 0 or 1
            if hitbox.LocalTransparencyModifier ~= want then
                hitbox.LocalTransparencyModifier = want
            end
        end)
        objects[ent] = hitbox
    end

    local function clearHitboxes()
        for _, part in pairs(objects) do part:Destroy() end
        table.clear(objects)
        for _, plr in playersService:GetPlayers() do
            local char = plr.Character
            if char then
                for _, old in char:GetChildren() do
                    if old.Name == 'AeroHitbox' then old:Destroy() end
                end
            end
        end
        for _, ent in entitylib.List do
            local char = ent.Character
            if char then
                for _, old in char:GetChildren() do
                    if old.Name == 'AeroHitbox' then old:Destroy() end
                end
            end
        end
    end

    local function refreshAllHitboxes()
        clearHitboxes()
        local entityList = entitylib.List
        for i = 1, #entityList do
            createHitbox(entityList[i])
        end
    end

    local function handleAutoToggle()
        if not AutoToggle or not AutoToggle.Enabled then return end
        if not HitBoxes.Enabled or Mode.Value ~= 'Player' then return end
        local holdingSword = isSword()
        if holdingSword and not hitboxesActive then
            hitboxesActive = true
            refreshAllHitboxes()
        elseif not holdingSword and hitboxesActive then
            hitboxesActive = false
            clearHitboxes()
        end
    end

    HitBoxes = vape.Categories.Combat:CreateModule({
        Name = 'HitBoxes',
        Function = function(callback)
            if callback then
                updateExpandSize(Expand.Value)
                if Mode.Value == 'Sword' then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (Expand.Value / 3))
                    set = true
                else
                    HitBoxes:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
                        if AutoToggle and AutoToggle.Enabled then
                            if hitboxesActive then createHitbox(ent) end
                        else
                            createHitbox(ent)
                        end
                    end))
                    HitBoxes:Clean(entitylib.Events.EntityRemoving:Connect(function(ent)
                        local obj = objects[ent]
                        if obj then obj:Destroy() objects[ent] = nil end
                    end))
                    if AutoToggle and AutoToggle.Enabled then
                        handleAutoToggle()
                        if not autoToggleConnection or not autoToggleConnection.Connected then
                            autoToggleFrameCounter = 0
                            autoToggleConnection = runService.Heartbeat:Connect(function()
                                autoToggleFrameCounter = autoToggleFrameCounter + 1
                                if autoToggleFrameCounter % 5 == 0 then
                                    handleAutoToggle()
                                end
                            end)
                            HitBoxes:Clean(autoToggleConnection)
                        end
                    else
                        refreshAllHitboxes()
                    end
                    local hitboxThrottleCounter = 0
                    HitBoxes:Clean(runService.Heartbeat:Connect(function()
                        if not Targets or not Targets.Walls or not Targets.Walls.Enabled then return end
                        hitboxThrottleCounter = hitboxThrottleCounter + 1
                        if hitboxThrottleCounter % 20 ~= 0 then return end
                        for ent, part in pairs(objects) do
                            if isTargetBehindWall(ent) then
                                part:Destroy()
                                objects[ent] = nil
                            end
                        end
                        local entityList = entitylib.List
                        for i = 1, #entityList do
                            local ent = entityList[i]
                            if not objects[ent] then
                                if AutoToggle and AutoToggle.Enabled then
                                    if hitboxesActive then createHitbox(ent) end
                                else
                                    createHitbox(ent)
                                end
                            end
                        end
                    end))
                end
            else
                hitboxesActive = false
                if set then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, 3.8)
                    set = false
                end
                clearHitboxes()
            end
        end,
        Tooltip = 'increases attack hitbox'
    })

    HitBoxes.ExtraText = function()
        return Expand and tostring(Expand.Value) or ''
    end

    Targets = HitBoxes:CreateTargets({
        Players = true,
        Walls = false,
        NPCs = false,
        Function = function()
            if HitBoxes.Enabled and Mode.Value == 'Player' then
                if AutoToggle and AutoToggle.Enabled then
                    if hitboxesActive then refreshAllHitboxes() end
                else
                    refreshAllHitboxes()
                end
            end
        end
    })

    Mode = HitBoxes:CreateDropdown({
        Name = 'Mode',
        List = {'Sword', 'Player'},
        Function = function(val)
            local isPlayer = val == 'Player'
            if AutoToggle then AutoToggle.Object.Visible = isPlayer end
            if Visible then Visible.Object.Visible = isPlayer end
            if VisibleColor then VisibleColor.Object.Visible = isPlayer and Visible.Enabled end
            if HitBoxes.Enabled then HitBoxes:Toggle() HitBoxes:Toggle() end
        end,
    })

    Expand = HitBoxes:CreateSlider({
        Name = 'Expand amount',
        Min = 0,
        Max = 30,
        Default = 14.4,
        Decimal = 10,
        Function = function(val)
            updateExpandSize(val)
            pcall(function() vape:UpdateTextGUI() end)
            if HitBoxes.Enabled then
                if Mode.Value == 'Sword' then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (val / 3))
                else
                    for _, part in pairs(objects) do part.Size = cachedExpandSize end
                end
            end
        end,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })

    AutoToggle = HitBoxes:CreateToggle({
        Name = 'Auto Toggle',
        Default = false,
        Tooltip = 'enables hitbox when holding sword, disable when not',
        Function = function(callback)
            if callback then
                if autoToggleConnection then autoToggleConnection:Disconnect() end
                hitboxesActive = false
                autoToggleFrameCounter = 0
                autoToggleConnection = runService.Heartbeat:Connect(function()
                    autoToggleFrameCounter = autoToggleFrameCounter + 1
                    if autoToggleFrameCounter % 5 == 0 then
                        handleAutoToggle()
                    end
                end)
                HitBoxes:Clean(autoToggleConnection)
                handleAutoToggle()
            else
                if autoToggleConnection then
                    autoToggleConnection:Disconnect()
                    autoToggleConnection = nil
                end
                hitboxesActive = false
                if HitBoxes.Enabled and Mode.Value == 'Player' then
                    refreshAllHitboxes()
                end
            end
        end
    })

    Visible = HitBoxes:CreateToggle({
        Name = 'Visible',
        Default = false,
        Function = function(callback)
            if VisibleColor then VisibleColor.Object.Visible = callback end
            if HitBoxes.Enabled and Mode.Value == 'Player' then
                local transparency = callback and 0.5 or 1
                local col = callback and VisibleColor and (colorList[VisibleColor.Value] or colorList.Red) or nil
                for _, part in pairs(objects) do
                    part.LocalTransparencyModifier = callback and 0 or 1
                    part.Transparency = transparency
                    if col then part.Color = col end
                end
            end
        end
    })

    VisibleColor = HitBoxes:CreateDropdown({
        Name = 'Hitbox Color',
        List = {'Red', 'Blue', 'Green', 'Yellow', 'Orange', 'Purple', 'White', 'Cyan', 'Pink', 'Black'},
        Default = 'Red',
        Visible = false,
        Function = function(val)
            if HitBoxes.Enabled and Mode.Value == 'Player' and Visible.Enabled then
                local col = colorList[val] or colorList.Red
                for _, part in pairs(objects) do part.Color = col end
            end
        end
    })

    task.spawn(function()
        repeat task.wait() until Mode and Mode.Value
        local isPlayer = Mode.Value == 'Player'
        AutoToggle.Object.Visible = isPlayer
        Visible.Object.Visible = isPlayer
    end)

    task.defer(function()
        if VisibleColor and VisibleColor.Object then
            VisibleColor.Object.Visible = false
        end
    end)
end)

run(function()
    local InfKrystal
    local UPDATE_INTERVAL = 0.016
    local lastUpdateTime = 0
    local renderStepName = 'InfiniteKrystalMovement'

    InfKrystal = vape.Categories.Kits:CreateModule({
        Name = 'InfKrystal',
        Function = function(callback)
            if callback then
                lastUpdateTime = 0

                runService:BindToRenderStep(
                    renderStepName,
                    Enum.RenderPriority.Character.Value + 2,
                    function()
                        local currentTime = tick()

                        if currentTime - lastUpdateTime < UPDATE_INTERVAL then
                            return
                        end

                        lastUpdateTime = currentTime

                        pcall(function()
                            bedwars.GlacialSkaterController:updateMomentum(100, "newValue")
                        end)
                    end
                )
            else
                runService:UnbindFromRenderStep(renderStepName)

                pcall(function()
                    bedwars.GlacialSkaterController:updateMomentum(0, "newValue")
                end)
            end
        end
    })
end)

run(function()
	local KnockbackDisplace
	local KBDirection
	local originalApplyKnockback
	local hookedUtil
	local installedHook
	local hooked = false

	local _cachedKnockbackUtil = nil
	local function findKnockbackUtil()
		if _cachedKnockbackUtil and rawget(_cachedKnockbackUtil, 'applyKnockback') then
			return _cachedKnockbackUtil
		end
		for _, v in getgc(true) do
			if type(v) == 'table' and rawget(v, 'applyKnockback') and rawget(v, 'getDirection') and rawget(v, 'applyKnockbackDirection') then
				_cachedKnockbackUtil = v
				return v
			end
		end
	end

	local function unhookKnockback()
		if hookedUtil and originalApplyKnockback then
			pcall(function()
				if rawget(hookedUtil, 'applyKnockback') == installedHook then
					hookedUtil.applyKnockback = originalApplyKnockback
				end
			end)
		end
		hookedUtil = nil
		installedHook = nil
		originalApplyKnockback = nil
		hooked = false
	end

	KnockbackDisplace = vape.Categories.Combat:CreateModule({
		Name = 'KnockbackDisplace',
		Function = function(callback)
			if callback then
				if hooked then return end
				local util = findKnockbackUtil()
				if not util then
					notif('KnockbackDisplace', 'Failed to hook knockback!', 3)
					KnockbackDisplace:Toggle()
					return
				end
				originalApplyKnockback = util.applyKnockback
				local capturedOriginal = originalApplyKnockback
				local hookFn = function(hrp, mass, sourcePos, modifier)
					if not capturedOriginal then return end
					if not KnockbackDisplace.Enabled then
						return capturedOriginal(hrp, mass, sourcePos, modifier)
					end
					local dir = KBDirection.Value
					if dir == 'Default' then
						return capturedOriginal(hrp, mass, sourcePos, modifier)
					elseif dir == 'Void' then
						hrp:ApplyImpulse(Vector3.new(0, -mass * 60, 0))
						return
					elseif dir == 'Up' then
						hrp:ApplyImpulse(Vector3.new(0, mass * 48, 0))
						return
					else
						local hrpPos = hrp.Position
						local cf = hrp.CFrame
						local fakeSource
						if dir == 'Left' then
							fakeSource = hrpPos + cf.RightVector * 10
						elseif dir == 'Right' then
							fakeSource = hrpPos - cf.RightVector * 10
						elseif dir == 'Reverse' then
							if sourcePos then
								fakeSource = Vector3.new(2 * hrpPos.X - sourcePos.X, sourcePos.Y, 2 * hrpPos.Z - sourcePos.Z)
							end
						end
						return capturedOriginal(hrp, mass, fakeSource or sourcePos, modifier)
					end
				end
				util.applyKnockback = hookFn
				hookedUtil = util
				installedHook = hookFn
				hooked = true
			else
				unhookKnockback()
			end
		end,
		Tooltip = 'changes your knockback direction'
	})

	vape:Clean(unhookKnockback)

	KBDirection = KnockbackDisplace:CreateDropdown({
		Name = 'KBDirection',
		List = {'Default', 'Backwards', 'Up', 'Left', 'Right', 'Reverse'},
		Default = 'Default',
		Tooltip = 'Choose which direction to redirect your knockback'
	})
end)