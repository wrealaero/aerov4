-- 1 BILLION DUCKS

local run = function(func)
	local ok, err = pcall(func)
	if not ok then
		warn('[aerov4] module failed: '..tostring(err))
	end
end
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

local umePointer = replicatedStorage:WaitForChild('UmePointer', 10)
local UmeValue = umePointer and umePointer.Value and require(umePointer.Value)
local Network = UmeValue and UmeValue.Network

local function fireNetwork(name, ...)
	if Network and Network.Fire then
		Network.Fire(name, nil, ...)
	end
end

local function getClosestDuck(hrp)
	local umeFolder = workspace:FindFirstChild('Ume')
	if not umeFolder then
		return nil
	end
	local closest = nil
	local closestPart = nil
	local closestDist = math.huge
	for _, duck in umeFolder:GetChildren() do
		if duck:IsA('Model') and duck.Name:match('^DuckController_Client_') then
			local part = duck.PrimaryPart
			if not part then
				for _, desc in duck:GetDescendants() do
					if desc:IsA('BasePart') then
						part = desc
						break
					end
				end
			end
			if part then
				local dist = (part.Position - hrp.Position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closest = duck
					closestPart = part
				end
			end
		end
	end
	return closest, closestPart
end

for _, v in {'PlayerModel','AimAssist', 'Search', 'Waypoints', 'StaffDetector', 'AutoClicker', 'Reach', 'Disabler', 'MurderMystery', 'Killaura', 'TriggerBot', 'SilentAim', 'Gravity', 'Parkour', 'LongJump', 'HitBoxes', 'TargetStrafe'} do
	vape:Remove(v)
end

run(function()
	local AutoSell

	AutoSell = vape.Categories.Blatant:CreateModule({
		Name = 'AutoSell',
		Function = function(callback)
			if callback then
				repeat
					task.wait(1.5)
					if Network and Network.Invoke then
						Network.Invoke('DuckController_Sell', nil)
					end
				until not AutoSell.Enabled
			end
		end,
		Tooltip = 'auto sells ur ducks'
	})
end)

run(function()
	local AutoShoot
	local shotCounter = 0

	AutoShoot = vape.Categories.Combat:CreateModule({
		Name = 'AutoShoot',
		Function = function(callback)
			if callback then
				repeat
					task.wait(0.5)
					local char = lplr.Character
					local hrp = char and char:FindFirstChild('HumanoidRootPart')
					if not hrp then
						local _, targetPart = getClosestDuck(hrp)
						if Network and Network.Fire then
							local direction = (targetPart.Position - hrp.Position).Unit
							shotCounter = shotCounter + 1
							Network.Fire('WeaponController_Shoot', vector.create(hrp.Position.X, hrp.Position.Y, hrp.Position.Z), vector.create(direction.X, direction.Y, direction.Z), shotCounter, workspace:GetServerTimeNow(), 'Shoot')
						end
					end
				until not AutoShoot.Enabled
			end
		end,
		Tooltip = 'auto shoots the closest duck for u'
	})
end)