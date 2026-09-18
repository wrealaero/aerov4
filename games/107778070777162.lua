-- STEAL AN EGG

local run = function(func) func() end
local cloneref = cloneref or function(obj) return obj end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local runService = cloneref(game:GetService('RunService'))
local httpService = cloneref(game:GetService('HttpService'))
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local sessioninfo = vape.Libraries.sessioninfo
local gameapi = {}

local function notif(...)
	return vape:CreateNotification(...)
end

for _, v in {'PlayerModel','AimAssist', 'Search', 'Waypoints', 'StaffDetector', 'AutoClicker', 'Reach', 'Disabler', 'MurderMystery', 'Killaura', 'TriggerBot', 'SilentAim', 'Gravity', 'Parkour', 'LongJump', 'HitBoxes', 'TargetStrafe' } do
	vape:Remove(v)
end

local packages = replicatedStorage:FindFirstChild('Packages')
local networking = packages and packages:FindFirstChild('Networking')
local clientFolder = replicatedStorage:FindFirstChild('Client')
local toolGuard = clientFolder and require(clientFolder:FindFirstChild('ToolGameplayGuard'))
local batSwingRemote = networking and networking:FindFirstChild('RE/BatSwing/Trigger')
local rigSyncRemote = networking and networking:FindFirstChild('RE/RigSync/Refresh')
local Save = require(replicatedStorage.Shared.Save)
local Remotes = require(replicatedStorage.Shared.Remotes)
local Treadmills = require(replicatedStorage.Data.Treadmills)
local EggState = require(replicatedStorage.Client.EggState)
local EggToolDisplay = require(replicatedStorage.Shared.Eggs.EggToolDisplay)
local PlotState = require(replicatedStorage.Client.PlotState)
local Assets = require(replicatedStorage.Data.Assets)
local AssetItems = require(replicatedStorage.Shared.Util.AssetItems)
local AssetEarnings = require(replicatedStorage.Shared.Util.AssetEarnings)
local carryState = {carrying = false}

local function createSeed()
	return ('%*:%*:%*'):format(lplr.UserId, 100, math.floor(workspace:GetServerTimeNow() * 1000))
end

local function canUseTool()
	local char = lplr.Character
	if not char then
		return false
	end
	local tool = char:FindFirstChildOfClass('Tool')
	if not tool or tool:GetAttribute('ItemType') ~= 'Gear' then
		return false
	end
	local hrp = char:FindFirstChild('HumanoidRootPart')
	if not hrp then
		return false
	end
	if not toolGuard or not toolGuard.IsLocalInsideArena() then
		return false
	end
	if workspace:GetAttribute('Event_MonsterEvent') then
		return hrp.Position.Z > -268
	end
	return true
end

local function getClosestPlayer()
	local closest = nil
	local closestDist = math.huge
	for _, p in playersService:GetPlayers() do
		if p ~= lplr then
			local char = p.Character
			local hrp = char and char:FindFirstChild('HumanoidRootPart')
			if hrp then
				local dist = lplr:DistanceFromCharacter(hrp.Position)
				if dist < closestDist and dist <= 16.5 then
					closestDist = dist
					closest = p
				end
			end
		end
	end
	return closest
end

run(function()
	local AutoHatch

	AutoHatch = vape.Categories.Blatant:CreateModule({
		Name = 'AutoHatch',
		Function = function(callback)
			if callback then
				repeat
					task.wait(1)
					local owned = EggState.ReadOwnedEggs()
					for _, row in owned do
						if row.OwnerUserId == lplr.UserId then
							for uid in pairs(row.Records) do
								if EggState.IsReadyToHatch(uid) then
									local ok = EggState.BeginHatch(uid)
									if ok then
										EggState.FinishHatch(uid)
									end
								end
							end
						end
					end
				until not AutoHatch.Enabled
			end
		end,
		Tooltip = 'auto hatches ur eggs the second theyre ready '
	})
end)

run(function()
	local AutoTreadmillUpgrade

	AutoTreadmillUpgrade = vape.Categories.Blatant:CreateModule({
		Name = 'AutoTreadmillUpgrade',
		Function = function(callback)
			if callback then
				repeat
					task.wait(1)
					local save = Save.Get()
					if save then
						local nextLevel = save.TreadmillUpgradeLevel + 1
						local config = Treadmills.GetByUpgradeLevel(nextLevel)
						if config and save.Money >= config.Price then
							Remotes.Treadmill.AskTierRaise:InvokeServer(config._id)
						end
					end
				until not AutoTreadmillUpgrade.Enabled
			end
		end,
		Tooltip = 'auto buys the next treadmill speed upgrade when u can afford it '
	})
end)

run(function()
	local Disabler
	local conn = nil
	local hookedFunc = nil
	local isCarrying = false

	local function findSpeedFunction()
		if not getgc then
			return nil
		end
		for _, f in getgc(true) do
			if typeof(f) == 'function' and islclosure(f) then
				local upvs = debug.getupvalues(f)
				local line = debug.info(f, 'l')
				if upvs and #upvs == 19 and line == 634 then
					return f
				end
			end
		end
		return nil
	end

	Disabler = vape.Categories.Blatant:CreateModule({
		Name = 'Disabler',
		Function = function(callback)
			if callback then
				if getgc and hookfunction and islclosure and not hookedFunc then
					local func = findSpeedFunction()
					if func then
						local target = debug.getupvalue(func, 2)
						if target then
							hookedFunc = hookfunction(target, newlclosure(function(p1, p2)
								if p2 and typeof(p2) == 'table' then
									setmetatable(p2, {})
								end
								return hookedFunc(p1, p2)
							end))
						end
					end
				end
				task.spawn(function()
					repeat
						task.wait(1)
						local carrying = false
						for _, record in EggState.ReadFieldEggs().Records do
							if record.State == 'Carried' and record.CarrierUserId == lplr.UserId then
								carrying = true
								break
							end
						end
						isCarrying = carrying
					until not Disabler.Enabled
				end)
				conn = runService.Heartbeat:Connect(function()
					local char = lplr.Character
					local hum = char and char:FindFirstChildOfClass('Humanoid')
					if hum then
						hum.WalkSpeed = isCarrying and 16 or 500
					end
				end)
			else
				if conn then
					conn:Disconnect()
					conn = nil
				end
			end
		end,
		Tooltip = 'makes u run way faster than normal gng'
	})
end)

run(function()
	local AutoPlaceEgg

	AutoPlaceEgg = vape.Categories.Blatant:CreateModule({
		Name = 'AutoPlaceEgg',
		Function = function(callback)
			if callback then
				repeat
					task.wait(1)
					local char = lplr.Character
					local hum = char and char:FindFirstChildOfClass('Humanoid')
					local backpack = lplr:FindFirstChildOfClass('Backpack')
					local plot = PlotState.ResolvePlot()
					if hum and backpack and plot then
						local eggTool = nil
						for _, tool in char:GetChildren() do
							if tool:IsA('Tool') and EggToolDisplay.IsEggTool(tool) then
								eggTool = tool
								break
							end
						end
						if not eggTool then
							for _, tool in backpack:GetChildren() do
								if EggToolDisplay.IsEggTool(tool) then
									eggTool = tool
									hum:EquipTool(tool)
									break
								end
							end
						end
						if eggTool then
							local uid = EggToolDisplay.GetToolUid(eggTool)
							if uid then
								EggState.PlantEgg(uid, CFrame.new())
							end
						end
					end
				until not AutoPlaceEgg.Enabled
			end
		end,
		Tooltip = 'auto places an egg from ur backpack onto ur plot '
	})
end)

run(function()
	local AutoRedeemCodex

	AutoRedeemCodex = vape.Categories.Blatant:CreateModule({
		Name = 'AutoRedeemCodex',
		Function = function(callback)
			if callback then
				repeat
					task.wait(1)
					Remotes.Codex.AskRedeemAll:InvokeServer()
				until not AutoRedeemCodex.Enabled
			end
		end,
		Tooltip = 'auto claims everything in ur codex '
	})
end)

run(function()
	local AutoBat
	local conn = nil
	local AutoBat
	AutoBat = vape.Categories.Combat:CreateModule({
		Name = 'AutoBat',
		Function = function(callback)
			if callback then
				local last = tick()
				conn = runService.Heartbeat:Connect(function()
					local target = getClosestPlayer()
					if target and tick() - last >= 0.1 and canUseTool() then
						if batSwingRemote then
							batSwingRemote:FireServer(target, createSeed())
						end
						last = tick()
					end
				end)
			else
				if conn then
					conn:Disconnect()
					conn = nil
				end
			end
		end,
		Tooltip = 'auto swings the bat on the closest player near u '
	})
end)

run(function()
	local InstantCarry
	local conn = nil
	InstantCarry = vape.Categories.Blatant:CreateModule({
		Name = 'InstantCarry',
		Function = function(callback)
			if callback then
				conn = game:GetService('ProximityPromptService').PromptButtonHoldBegan:Connect(function(prompt, player)
					if player == lplr and tostring(prompt) == 'CarryAreaEgg' then
						prompt.HoldDuration = 0
					end
				end)
			else
				if conn then
					conn:Disconnect()
					conn = nil
				end
			end
		end,
		Tooltip = 'grabs the egg instantly with no hold time '
	})
end)

run(function()
	local AntiReset

	AntiReset = vape.Categories.Utility:CreateModule({
		Name = 'AntiReset',
		Function = function(callback)
			if callback then
				if rigSyncRemote and getconnections then
					local conns = getconnections(rigSyncRemote.OnClientEvent)
					for _, c in conns do
						c:Disconnect()
					end
				end
			end
		end,
		Tooltip = 'stops the game from resetting stuff back on u '
	})
end)

run(function()
	local AutoSell

	AutoSell = vape.Categories.Blatant:CreateModule({
		Name = 'AutoSell',
		Function = function(callback)
			if callback then
				repeat
					task.wait(3)
					if KeepGoodPets.Enabled then
						local save = Save.Get(lplr, false)
						if save then
							local toSell = {}
							for uid, itemData in save.Inventory do
								local decoded = AssetItems.Decode(itemData)
								local assetInfo = Assets.Directory[decoded.Category]
								if assetInfo then
									local isGood
									if FilterMethod.Value == 'Rarity' then
										isGood = assetInfo.Rarity.RarityNumber > 2
									else
										local rate = AssetEarnings.LiveRatePerSecond(decoded, save.Gamepasses, save.Products, lplr)
										isGood = rate > 5
									end
									if not isGood then
										table.insert(toSell, uid)
									end
								end
							end
							if #toSell > 0 then
								Remotes.PetSatchel.SellSelection:FireServer({Assets = toSell, Eggs = {}})
							end
						end
					else
						Remotes.PetSatchel.SellEveryPet:FireServer()
					end
				until not AutoSell.Enabled
			end
		end,
		Tooltip = 'auto sells ur pets, turn on keep good pets to only sell junk '
	})
	KeepGoodPets = AutoSell:CreateToggle({
		Name = 'Keep Good Pets'
	})
	FilterMethod = AutoSell:CreateDropdown({
		Name = 'Filter Method',
		List = {'Rarity', 'Rate'},
		Tooltip = 'rarity - keeps stuff based on the games rarity tier\nrate - keeps stuff based on real cash per second value'
	})
end)

run(function()
	local AutoEquipBest

	AutoEquipBest = vape.Categories.Blatant:CreateModule({
		Name = 'AutoEquipBest',
		Function = function(callback)
			if callback then
				repeat
					task.wait(5.1)
					Remotes.Haul.WearBest:InvokeServer()
				until not AutoEquipBest.Enabled
			end
		end,
		Tooltip = 'auto equips ur best pets for u'
	})
end)

run(function()
	local TrapESP
	local conn = nil
	local tracked = {}

	local function addTrap(trap)
		if tracked[trap] or trap.Name ~= 'PlayerTrap' then
			return
		end
		local billboard = Instance.new('BillboardGui')
		billboard.Name = 'TrapESPTag'
		billboard.Size = UDim2.new(0, 200, 0, 60)
		billboard.StudsOffset = Vector3.new(0, 2, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = trap
		local label = Instance.new('TextLabel')
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextStrokeTransparency = 0
		label.Text = 'trap'
		label.TextColor3 = trap:GetAttribute('Owner') == lplr.Name and Color3.fromRGB(80, 160, 255) or Color3.fromRGB(255, 60, 60)
		label.Parent = billboard
		billboard.Parent = trap
		tracked[trap] = billboard
	end

	local function removeTrap(trap)
		local billboard = tracked[trap]
		if billboard then
			billboard:Destroy()
			tracked[trap] = nil
		end
	end

	TrapESP = vape.Categories.Render:CreateModule({
		Name = 'TrapESP',
		Function = function(callback)
			if callback then
				local debris = workspace:FindFirstChild('__DEBRIS')
				if debris then
					for _, v in debris:GetChildren() do
						addTrap(v)
					end
					conn = debris.ChildAdded:Connect(addTrap)
				end
			else
				for trap in tracked do
					removeTrap(trap)
				end
				if conn then
					conn:Disconnect()
					conn = nil
				end
			end
		end,
		Tooltip = 'shows every trap on the map, blue is urs red is everyone elses gng'
	})
end)