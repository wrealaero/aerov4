-- LIFT A CUBE

local run = function(func) func() end
local cloneref = cloneref or function(obj) return obj end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local runService = cloneref(game:GetService('RunService'))
local httpService = cloneref(game:GetService('HttpService'))
local virtualUser = cloneref(game:GetService('VirtualUser'))
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local sessioninfo = vape.Libraries.sessioninfo
local gameapi = {}
local bridgenet2 = require(replicatedStorage.Packages.bridgenet2)
local liftingRaw = require(replicatedStorage.Schematics.Lifting)
local liftingLib = require(replicatedStorage.Modules.Lifting)
local cubeRollLib = require(replicatedStorage.Modules.CubeRoll)
local armsSchematic = require(replicatedStorage.Schematics.Arms)
local speedSchematic = require(replicatedStorage.Schematics.SpeedUpgrades)
local materialsSchematic = require(replicatedStorage.Schematics.Materials)
local cleanId = (tostring(lplr.UserId)):gsub('-', '')
local bridges = {
	Training = bridgenet2.ReferenceBridge(cleanId..'_Training'),
	Cubes = bridgenet2.ReferenceBridge(cleanId..'_Cubes'),
	Pops = bridgenet2.ReferenceBridge(cleanId..'_Pops'),
	GroupReward = bridgenet2.ReferenceBridge(cleanId..'_GroupReward'),
	AFK = bridgenet2.ReferenceBridge(cleanId..'_AFK')
}
local cachedControllers = nil
local function getControllers()
	if cachedControllers then
		return cachedControllers
	end
	if getgc then
		for _, obj in getgc(true) do
			if type(obj) == 'table' and rawget(obj, 'name') == 'Cubes' and rawget(obj, 'controllers') then
				cachedControllers = obj.controllers
				return cachedControllers
			end
		end
	end
	return nil
end

local function notif(...)
	return vape:CreateNotification(...)
end

for _, v in {'PlayerModel','AimAssist', 'Search', 'Waypoints', 'StaffDetector', 'AutoClicker', 'Reach', 'Disabler', 'MurderMystery', 'Killaura', 'TriggerBot', 'SilentAim', 'Gravity', 'Parkour', 'LongJump', 'HitBoxes', 'TargetStrafe' } do
	vape:Remove(v)
end

local function getStrength()
	return lplr:GetAttribute('Strength') or 0
end

local function getCash()
	return lplr:GetAttribute('Cash') or 0
end

local function getEquippedArms()
	return lplr:GetAttribute('EquippedArms') or 0
end

local function getCubesFolder()
	local folder = workspace:FindFirstChild('World')
	folder = folder and folder:FindFirstChild('Shared')
	folder = folder and folder:FindFirstChild('Cubes')
	return folder
end

local function getBestLiftableCube()
	local str = getStrength()
	local cubesFolder = getCubesFolder()
	if not cubesFolder then
		return 1
	end
	local best = 1
	for i = 1, #cubesFolder:GetChildren() do
		local scale = cubeRollLib.Scale(cubesFolder, i)
		local mass = cubeRollLib.Mass(i, scale)
		if liftingLib.Possible(str, mass) then
			local minTime = liftingLib.MinimumTime(str, mass)
			if minTime <= 1.5 then
				best = i
			end
		end
	end
	return best
end

local function ensureTrainToolEquipped()
	local char = lplr.Character
	if not char then
		return false
	end
	local hum = char:FindFirstChildOfClass('Humanoid')
	if not hum or hum.Health <= 0 then
		return false
	end
	local toolInChar = char:FindFirstChild('Train')
	if toolInChar then
		local ctrl = getControllers()
		if ctrl and ctrl.Training and not ctrl.Training.locked then
			ctrl.Training:SetLocked(true)
		end
		return true
	end
	local backpack = lplr:FindFirstChildOfClass('Backpack')
	local toolInBp = backpack and backpack:FindFirstChild('Train')
	if toolInBp then
		toolInBp.Parent = char
		local ctrl = getControllers()
		if ctrl and ctrl.Training then
			ctrl.Training:SetLocked(true)
		end
		return true
	end
	return false
end

run(function()
	AutoTrain = vape.Categories.Blatant:CreateModule({
		Name = 'AutoTrain',
		Function = function(callback)
			if callback then
				repeat
					task.wait(0.105)
					local equipped = ensureTrainToolEquipped()
					if equipped then
						bridges.Training:Fire({Function = 'CompletePushup', Args = {1}})
					end
				until not AutoTrain.Enabled
				local ctrl = getControllers()
				if ctrl and ctrl.Training then
					ctrl.Training:SetLocked(false)
				end
				local char = lplr.Character
				local hum = char and char:FindFirstChildOfClass('Humanoid')
				if hum then
					hum:UnequipTools()
				end
			end
		end,
		Tooltip = 'auto trains for u so ur strength keeps going up gng'
	})
end)

run(function()
	AutoLift = vape.Categories.Blatant:CreateModule({
		Name = 'AutoLift',
		Function = function(callback)
			if callback then
				repeat
					task.wait(0.05)
					local ctrl = getControllers()
					local cubesFolder = getCubesFolder()
					local char = lplr.Character
					local hrp = char and char:FindFirstChild('HumanoidRootPart')
					local hum = char and char:FindFirstChildOfClass('Humanoid')
					if ctrl and ctrl.Cubes and cubesFolder and hrp and hum and hum.Health > 0 then
						local index = getBestLiftableCube()
						local cubePart = cubesFolder:FindFirstChild(tostring(index))
						if cubePart then
							local strength = getStrength()
							local scale = cubeRollLib.Scale(cubesFolder, index)
							local mass = cubeRollLib.Mass(index, scale)
							if liftingLib.Possible(strength, mass) then
								local minTime = liftingLib.MinimumTime(strength, mass)
								if (hrp.Position - cubePart.Position).Magnitude > 8 then
									hrp.CFrame = cubePart.CFrame + Vector3.new(0, 3, 2.5)
									task.wait(0.08)
								end
								hum:UnequipTools()
								ctrl.Cubes:Start(index, cubePart)
								task.wait(minTime <= 0 and 0.02 or minTime + 0.04)
								if ctrl.Cubes.active then
									ctrl.Cubes.active.Progress = 1
									ctrl.Cubes:_Finish(true)
								end
							end
						end
					end
				until not AutoLift.Enabled
			end
		end,
		Tooltip = 'auto lifts the best cube it can find for free cash'
	})
end)

run(function()
	AutoBuyArms = vape.Categories.Blatant:CreateModule({
		Name = 'AutoBuyArms',
		Function = function(callback)
			if callback then
				repeat
					task.wait(3)
					local armsFolder = workspace:FindFirstChild('World')
					armsFolder = armsFolder and armsFolder:FindFirstChild('Shared')
					armsFolder = armsFolder and armsFolder:FindFirstChild('Arms')
					local char = lplr.Character
					local hrp = char and char:FindFirstChild('HumanoidRootPart')
					if armsFolder and hrp then
						local currentArms = getEquippedArms()
						local currentCash = getCash()
						for tier = #armsSchematic, currentArms + 1, -1 do
							local data = armsSchematic[tier]
							if data and currentCash >= data.Price then
								local pad = armsFolder:FindFirstChild(tostring(tier))
								if pad and pad:FindFirstChild('Main') then
									local oldPos = hrp.CFrame
									hrp.CFrame = CFrame.new(pad.Main.Position + Vector3.new(0, 3, 0))
									task.wait(0.35)
									hrp.CFrame = oldPos
									break
								end
							end
						end
					end
				until not AutoBuyArms.Enabled
			end
		end,
		Tooltip = 'auto buys the best arms u can afford'
	})
end)

run(function()
	AutoPops = vape.Categories.Blatant:CreateModule({
		Name = 'AutoPops',
		Function = function(callback)
			if callback then
				repeat
					task.wait(0.2)
					local ctrl = getControllers()
					if ctrl and ctrl.Pops and ctrl.Pops.live then
						for popId in ctrl.Pops.live do
							if type(popId) == 'number' then
								ctrl.Pops:_Claim(popId)
								task.wait(0.05)
							end
						end
					end
				until not AutoPops.Enabled
			end
		end,
		Tooltip = 'auto claims those pop multipliers for u'
	})
end)

run(function()
	local function getBestUpgrade(ctrl)
		local currentMult = 0
		if ctrl.Roll.equipped and materialsSchematic[ctrl.Roll.equipped] then
			currentMult = materialsSchematic[ctrl.Roll.equipped].StrengthMultiplier
		end
		local currentCash = getCash()
		local owned = ctrl.Roll.owned or {}
		local best = nil
		local bestMult = currentMult
		for name, data in materialsSchematic do
			if data.StrengthMultiplier > bestMult and (owned[name] or currentCash >= data.Price) then
				best = name
				bestMult = data.StrengthMultiplier
			end
		end
		return best
	end
	AutoRoll = vape.Categories.Blatant:CreateModule({
		Name = 'AutoRoll',
		Function = function(callback)
			if callback then
				repeat
					task.wait(0.5)
					local ctrl = getControllers()
					if ctrl and ctrl.Roll and not ctrl.Roll.rolling and not ctrl.Roll.buying then
						local targetMat = getBestUpgrade(ctrl)
						if targetMat then
							local chestData = nil
							for _, data in pairs(ctrl.Roll.chests) do
								if data.ready and ctrl.Roll:_Unlocked(data) then
									chestData = data
									break
								end
							end
							if chestData then
								ctrl.Roll:ForceNext(targetMat)
								ctrl.Roll:Play(chestData)
								local started = os.clock()
								repeat
									task.wait(0.1)
								until not ctrl.Roll.rolling or os.clock() - started > 5
								if ctrl.Roll.pending then
									ctrl.Roll:Buy()
								end
							end
						end
					end
				until not AutoRoll.Enabled
			end
		end,
		Tooltip = 'only buys materials stronger than what u already got equipped'
	})
end)

run(function()
	AutoGroupReward = vape.Categories.Blatant:CreateModule({
		Name = 'AutoGroupReward',
		Function = function(callback)
			if callback then
				repeat
					task.wait(20)
					local ctrl = getControllers()
					if ctrl and ctrl.GroupReward and not ctrl.GroupReward:IsClaimed() then
						bridges.GroupReward:Fire({Function = 'RequestClaim', Args = {}})
					end
				until not AutoGroupReward.Enabled
			end
		end,
		Tooltip = 'auto claims the group reward for u'
	})
end)

run(function()
	AutoRespawn = vape.Categories.Utility:CreateModule({
		Name = 'AutoRespawn',
		Function = function(callback)
			if callback then
				repeat
					task.wait(1)
					local char = lplr.Character
					local hum = char and char:FindFirstChildOfClass('Humanoid')
					if hum and hum.Health <= 0 then
						local GlobalReplicator = require(replicatedStorage.Modules.GlobalReplicator)
						GlobalReplicator.StreamToServer('Systems', {Path = 'Spawn', Function = 'RequestSpawn', Args = {}})
					end
				until not AutoRespawn.Enabled
			end
		end,
		Tooltip = 'respawns u right away when u die'
	})
end)