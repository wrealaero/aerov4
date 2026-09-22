--!nocheck

local module = {}

local workspace = game:GetService('Workspace')
local stats = game:GetService('Stats')

local eps = 1e-9
local RAY_LIMIT = 600

local function isZero(d)
	return d > -eps and d < eps
end

local function validNumber(v)
	return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

local function validVector(v)
	if typeof(v) ~= 'Vector3' then return false end
	return validNumber(v.X) and validNumber(v.Y) and validNumber(v.Z)
end

local function cuberoot(x)
	return (x > 0) and math.pow(x, 1 / 3) or -math.pow(math.abs(x), 1 / 3)
end

local function solveQuadric(c0, c1, c2)
	local p = c1 / (2 * c0)
	local q = c2 / c0
	local D = p * p - q

	if isZero(D) then
		return {-p}
	elseif D < 0 then
		return {}
	end

	local sqrtD = math.sqrt(D)
	return {sqrtD - p, -sqrtD - p}
end

local function solveCubic(c0, c1, c2, c3)
	local A = c1 / c0
	local B = c2 / c0
	local C = c3 / c0

	local sqA = A * A
	local p = (1 / 3) * (-(1 / 3) * sqA + B)
	local q = 0.5 * ((2 / 27) * A * sqA - (1 / 3) * A * B + C)

	local cbP = p * p * p
	local D = q * q + cbP
	local results

	if isZero(D) then
		if isZero(q) then
			results = {0}
		else
			local u = cuberoot(-q)
			results = {2 * u, -u}
		end
	elseif D < 0 then
		local phi = (1 / 3) * math.acos(-q / math.sqrt(-cbP))
		local t = 2 * math.sqrt(-p)
		results = {
			t * math.cos(phi),
			-t * math.cos(phi + math.pi / 3),
			-t * math.cos(phi - math.pi / 3)
		}
	else
		local sqrtD = math.sqrt(D)
		local u = cuberoot(sqrtD - q)
		local v = -cuberoot(sqrtD + q)
		results = {u + v}
	end

	local sub = (1 / 3) * A
	for i = 1, #results do
		results[i] = results[i] - sub
	end
	return results
end

function module.solveQuartic(c0, c1, c2, c3, c4)
	if isZero(c0) then
		return solveCubic(c1, c2, c3, c4)
	end

	local A = c1 / c0
	local B = c2 / c0
	local C = c3 / c0
	local D = c4 / c0

	local sqA = A * A
	local p = -0.375 * sqA + B
	local q = 0.125 * sqA * A - 0.5 * A * B + C
	local r = -(3 / 256) * sqA * sqA + 0.0625 * sqA * B - 0.25 * A * C + D

	local results

	if isZero(r) then
		results = solveCubic(1, 0, p, q)
		table.insert(results, 0)
	else
		local cubic = solveCubic(1, -0.5 * p, -r, 0.5 * r * p - 0.125 * q * q)
		local z = cubic[1]
		if not z then return {} end

		local u = z * z - r
		local v = 2 * z - p

		if isZero(u) then
			u = 0
		elseif u > 0 then
			u = math.sqrt(u)
		else
			return {}
		end

		if isZero(v) then
			v = 0
		elseif v > 0 then
			v = math.sqrt(v)
		else
			return {}
		end

		results = solveQuadric(1, q < 0 and -v or v, z - u)
		local second = solveQuadric(1, q < 0 and v or -v, z + u)
		for _, root in second do
			table.insert(results, root)
		end
	end

	local sub = 0.25 * A
	for i = 1, #results do
		results[i] = results[i] - sub
	end
	return results
end

local function interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, t)
	local offset = relativePosition + targetVelocity * t + halfRelativeAcceleration * (t * t)
	return offset:Dot(offset) - projectileSpeed * projectileSpeed * t * t
end

function module.SolveIntercept(origin, projectileSpeed, projectileAcceleration, targetPosition, targetVelocity, targetAcceleration, minimumTime, maximumTime, preferHigh)
	if not validVector(origin)
		or not validVector(projectileAcceleration)
		or not validVector(targetPosition)
		or not validVector(targetVelocity)
		or not validVector(targetAcceleration)
		or not validNumber(projectileSpeed)
		or projectileSpeed <= eps
	then
		return nil
	end

	local minT = math.max(tonumber(minimumTime) or 0, eps)
	local maxT = tonumber(maximumTime) or 10
	if not validNumber(maxT) or maxT < minT then return nil end

	local wantHigh = preferHigh == true
	local relativePosition = targetPosition - origin
	local halfRelativeAcceleration = (targetAcceleration - projectileAcceleration) * 0.5
	local bestTime

	local function acceptRoot(root)
		if not validNumber(root) or root < minT or root > maxT then return end
		local residual = math.abs(interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, root))
		local scale = math.max(projectileSpeed * projectileSpeed * root * root, 1)
		if residual <= math.max(0.05, scale * 0.001) then
			if not bestTime then
				bestTime = root
			elseif wantHigh then
				if root > bestTime then bestTime = root end
			elseif root < bestTime then
				bestTime = root
			end
		end
	end

	local c4 = halfRelativeAcceleration:Dot(halfRelativeAcceleration)
	local c3 = 2 * targetVelocity:Dot(halfRelativeAcceleration)
	local c2 = targetVelocity:Dot(targetVelocity) + 2 * relativePosition:Dot(halfRelativeAcceleration) - projectileSpeed * projectileSpeed
	local c1 = 2 * relativePosition:Dot(targetVelocity)
	local c0 = relativePosition:Dot(relativePosition)

	if math.abs(c4) > eps then
		local roots = module.solveQuartic(c4, c3, c2, c1, c0)
		if roots then
			for _, root in roots do
				acceptRoot(root)
			end
		end
	elseif math.abs(c2) > eps then
		local discriminant = c1 * c1 - 4 * c2 * c0
		if discriminant >= 0 then
			local squareRoot = math.sqrt(discriminant)
			acceptRoot((-c1 - squareRoot) / (2 * c2))
			acceptRoot((-c1 + squareRoot) / (2 * c2))
		end
	elseif math.abs(c1) > eps then
		acceptRoot(-c0 / c1)
	end

	if not bestTime then
		local steps = 96
		local previousTime = minT
		local previousValue = interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, previousTime)

		for step = 1, steps do
			local currentTime = minT + ((maxT - minT) * step / steps)
			local currentValue = interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, currentTime)

			if validNumber(previousValue) and validNumber(currentValue) then
				if previousValue == 0 then
					bestTime = previousTime
					break
				end
				if (previousValue < 0) ~= (currentValue < 0) then
					local low, high = previousTime, currentTime
					for _ = 1, 48 do
						local mid = (low + high) * 0.5
						local midValue = interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, mid)
						if not validNumber(midValue) then break end
						if (previousValue < 0) == (midValue < 0) then
							low = mid
						else
							high = mid
						end
					end
					bestTime = (low + high) * 0.5
					break
				end
			end

			previousTime = currentTime
			previousValue = currentValue
		end
	end

	if not bestTime then return nil end

	local displacement = relativePosition + targetVelocity * bestTime + halfRelativeAcceleration * (bestTime * bestTime)
	if displacement.Magnitude <= eps then return nil end

	local initialVelocity = displacement / bestTime
	return {
		FlightTime = bestTime,
		InitialVelocity = initialVelocity,
		ImpactPosition = targetPosition + targetVelocity * bestTime + targetAcceleration * (0.5 * bestTime * bestTime)
	}
end

local function predictVertical(groundY, currentY, vy, jumpImpulse, holdingJump, gravity, t)
	local g = gravity
	if not validNumber(g) or g <= eps then return currentY + vy * t end

	local j = math.max(jumpImpulse or 1, 1)
	local apex = j * j / (2 * g)
	local period = 2 * j / g
	local rise = math.clamp(currentY - groundY, 0, apex)

	if rise < 0.5 and math.abs(vy) < 5 then
		return currentY
	end

	local sqrtTerm = math.sqrt(math.max(j * j - 2 * g * rise, 0))
	local phase
	if vy >= 0 then
		phase = (j - sqrtTerm) / g
	else
		phase = (j + sqrtTerm) / g
	end

	local cycleT = phase + t

	if holdingJump then
		local tau = cycleT % period
		return groundY + j * tau - 0.5 * g * tau * tau
	end

	if cycleT >= period then
		return groundY
	end

	return groundY + j * cycleT - 0.5 * g * cycleT * cycleT
end

module.predictVertical = predictVertical

local rawLatency = 0.1
local latencyClock = 0

function module.setLatency(value)
	if validNumber(value) then
		rawLatency = math.clamp(value, 0, 1)
	end
end

function module.getRawLatency()
	if tick() - latencyClock < 1 then return rawLatency end
	latencyClock = tick()
	local ok, value = pcall(function()
		return stats.Network.ServerStatsItem['Data Ping']:GetValue() / 1000
	end)
	if ok and validNumber(value) then
		rawLatency = math.clamp(value, 0.01, 1)
	end
	return rawLatency
end

local latencyBias = 0

function module.getLatency()
	return module.getRawLatency() + latencyBias
end

function module.getLatencyBias()
	return latencyBias
end

local shotLog = {}
local residualSpread = 0

function module.trackShot(targetRoot)
	if typeof(targetRoot) ~= 'Instance' then return end
	shotLog[targetRoot] = {
		time = workspace:GetServerTimeNow(),
		position = targetRoot.Position
	}
end

function module.reportHit(targetRoot)
	local entry = shotLog[targetRoot]
	if not entry then return end
	shotLog[targetRoot] = nil
	local drift = (targetRoot.Position - entry.position).Magnitude
	residualSpread = residualSpread + (drift - residualSpread) * 0.25
end

function module.getResidualSpread()
	return residualSpread
end

local knockbackLog = setmetatable({}, {__mode = 'k'})

function module.markKnockback(target, multiplier, impulse)
	if typeof(target) ~= 'Instance' then return end
	knockbackLog[target] = {
		time = workspace:GetServerTimeNow(),
		multiplier = multiplier or 1,
		impulse = impulse
	}
end

function module.expectKnockback(target, arrival, impulse, multiplier)
	module.markKnockback(target, multiplier, impulse)
	return arrival
end

function module.Raycast(origin, direction, params)
	if not validVector(origin) or not validVector(direction) then return nil end
	return workspace:Raycast(origin, direction, params)
end

module.IsTrajectoryClear = function(origin, velocity, gravity, travelTime, params, target, ignored)
	if not validVector(origin) or not validVector(velocity) then return true end
	if not validNumber(travelTime) or travelTime <= 0 then return true end

	local steps = math.clamp(math.ceil(travelTime / 0.06), 3, 24)
	local previous = origin
	local accel = Vector3.new(0, -(gravity or 0), 0)

	for i = 1, steps do
		local t = travelTime * (i / steps)
		local point = origin + velocity * t + accel * (0.5 * t * t)
		local segment = point - previous
		if segment.Magnitude > eps then
			local result = workspace:Raycast(previous, segment, params)
			if result then
				local hit = result.Instance
				if hit ~= ignored and (not target or not hit:IsDescendantOf(target)) then
					return false, result
				end
			end
		end
		previous = point
	end

	return true
end

module.SpawnTracer = function(from, to, custom)
	if not validVector(from) or not validVector(to) then return end
	local part = Instance.new('Part')
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = (custom and custom.Color) or Color3.fromRGB(120, 220, 255)
	part.Transparency = (custom and custom.Transparency) or 0.4
	part.Size = Vector3.new(0.12, 0.12, (to - from).Magnitude)
	part.CFrame = CFrame.lookAt((from + to) * 0.5, to)
	part.Parent = workspace
	game:GetService('Debris'):AddItem(part, (custom and custom.Life) or 0.4)
	return part
end

module.SpawnArcTracer = function(origin, aimDirection, projectileSpeed, gravity, travelTime, steps, custom)
	if not validVector(origin) or not validVector(aimDirection) then return end
	steps = math.clamp(steps or 12, 2, 40)
	local velocity = aimDirection.Unit * (projectileSpeed or 100)
	local accel = Vector3.new(0, -(gravity or 0), 0)
	local previous = origin
	for i = 1, steps do
		local t = (travelTime or 1) * (i / steps)
		local point = origin + velocity * t + accel * (0.5 * t * t)
		module.SpawnTracer(previous, point, custom)
		previous = point
	end
end

local targetMotion = setmetatable({}, {__mode = 'k'})

local function getMotion(root, position, velocity, airborne, playerGravity)
	if typeof(root) ~= 'Instance' then
		return {
			groundY = position and (position.Y - 3) or 0,
			airborne = airborne == true,
			holding = false
		}
	end

	local state = targetMotion[root]
	if not state then
		state = {
			groundY = position.Y,
			airborne = false,
			holding = false,
			airborneSince = 0,
			lastVy = velocity and velocity.Y or 0,
			jumpImpulse = nil
		}
		targetMotion[root] = state
	end

	local now = workspace:GetServerTimeNow()
	local vy = velocity and velocity.Y or 0
	local isAir = airborne == true

	if not isAir then
		state.groundY = position.Y
		if state.airborne then
			local airTime = now - (state.airborneSince or now)
			if airTime > 0.15 and airTime < 3 then
				state.holding = airTime > 0.85
			end
		end
		state.airborne = false
	else
		if not state.airborne then
			state.airborne = true
			state.airborneSince = now
			if vy > 5 and validNumber(playerGravity) and playerGravity > 0 then
				local observed = vy
				if state.jumpImpulse then
					state.jumpImpulse = state.jumpImpulse + (observed - state.jumpImpulse) * 0.35
				else
					state.jumpImpulse = observed
				end
			end
		else
			local airTime = now - (state.airborneSince or now)
			state.holding = airTime > 0.85
		end
	end

	state.lastVy = vy
	return state
end

function module.Observe(root, position, velocity, airborne, playerGravity, origin, playerHeight, playerJump)
	if typeof(root) ~= 'Instance' then return end
	if not validVector(position) then return end
	getMotion(root, position, velocity or Vector3.zero, airborne, playerGravity)
end

local velHistory = setmetatable({}, {__mode = 'k'})

local function getSteadiness(root, velocity)
	if typeof(root) ~= 'Instance' then return 1, velocity end
	local now = os.clock()
	local h = velHistory[root]
	if not h or now - h.time > 0.5 then
		velHistory[root] = {vel = velocity, time = now, old = velocity, oldTime = now, smooth = velocity}
		return 1, velocity
	end
	if now - h.oldTime > 0.2 then
		h.old, h.oldTime = h.vel, h.time
	end
	h.vel, h.time = velocity, now
	h.smooth = h.smooth:Lerp(velocity, 0.5)
	local a = Vector3.new(velocity.X, 0, velocity.Z)
	local b = Vector3.new(h.old.X, 0, h.old.Z)
	if a.Magnitude < 1 then return 0, h.smooth end
	if b.Magnitude < 1 then return 0.5, h.smooth end
	return math.clamp(a.Unit:Dot(b.Unit), 0, 1), h.smooth
end

module.LeadScale = 0.5
module.MaxLead = 4
module.MaxVerticalLead = 2

function module.setLead(scale, maxLead, maxVertical)
	if validNumber(scale) then module.LeadScale = math.clamp(scale, 0, 1) end
	if validNumber(maxLead) then module.MaxLead = math.max(maxLead, 0) end
	if validNumber(maxVertical) then module.MaxVerticalLead = math.max(maxVertical, 0) end
end

module.SolveTrajectory = function(origin, projectileSpeed, gravity, targetPos, targetVelocity, playerGravity, playerHeight, playerJump, params, targetAirborne, targetRootPosition, targetRoot, minimumTime, strict)
	targetVelocity = targetVelocity or Vector3.zero
	projectileSpeed = tonumber(projectileSpeed) or 0
	gravity = tonumber(gravity) or 0

	if not validVector(origin)
		or not validVector(targetPos)
		or not validVector(targetVelocity)
		or not validNumber(projectileSpeed)
		or projectileSpeed <= eps
		or not validNumber(gravity)
	then
		if strict then return nil end
		return targetPos, targetPos, 0
	end

	local projectileAccel = Vector3.new(0, -gravity, 0)
	local maxTime = 10
	if validNumber(minimumTime) then
		maxTime = math.max(maxTime, minimumTime + 1)
	end

	local root = typeof(targetRoot) == 'Instance' and targetRoot or (typeof(targetRootPosition) == 'Instance' and targetRootPosition) or nil
	local steady, smooth = getSteadiness(root, targetVelocity)
	local scaledVelocity = Vector3.new(smooth.X * steady, targetVelocity.Y, smooth.Z * steady) * module.LeadScale
	local first = module.SolveIntercept(origin, projectileSpeed, projectileAccel, targetPos, scaledVelocity, Vector3.zero, minimumTime, maxTime, false)
	local flightTime = first and first.FlightTime or 0
	local lead = scaledVelocity * flightTime
	local flat = Vector3.new(lead.X, 0, lead.Z)
	if flat.Magnitude > module.MaxLead then
		flat = flat.Unit * module.MaxLead
	end
	local aimPoint = targetPos + flat + Vector3.new(0, math.clamp(lead.Y, -module.MaxVerticalLead, module.MaxVerticalLead), 0)
	local solution = module.SolveIntercept(origin, projectileSpeed, projectileAccel, aimPoint, Vector3.zero, Vector3.zero, minimumTime, maxTime, false)
	
	if not solution then
		if strict then return nil end
		return targetPos, targetPos, 0
	end

	local launchVelocity = solution.InitialVelocity
	if not validVector(launchVelocity) or launchVelocity.Magnitude <= eps then
		if strict then return nil end
		return targetPos, targetPos, 0
	end

	if params and solution.FlightTime then
		local clear = module.IsTrajectoryClear(origin, launchVelocity, gravity, solution.FlightTime, params, nil, nil)
		if clear == false and strict then
			return nil
		end
	end

	return origin + launchVelocity, aimPoint, solution.FlightTime
end

return module
