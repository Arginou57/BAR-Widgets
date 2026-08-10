local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name    = "Zombie Wreck Timers",
		desc    = "When the Zombies modoption is on, shows a countdown over each wreck until it reanimates. Reacts instantly when a corpse is reclaimed or resurrected. Display only.",
		author  = "SethDGamre + Egzothicki",
		date    = "August 2026",
		license = "GNU GPL, v2 or later",
		layer   = 10,
		enabled = true,
	}
end

local textSize    = 16
local heightBonus = 25
local maxDrawDist = 5500
local warnSeconds = 15

local ZOMBIE_REZ_FRAME_PARAM = "zombie_rez_frame"

-- royal purple ladder: white with plenty of time, purple as the rise nears
local COL_FAR    = { 0.95, 0.95, 0.95 } -- > 2 min
local COL_NEAR   = { 0.62, 0.44, 1.00 } -- 2..1 min
local COL_CLOSE  = { 0.47, 0.24, 0.95 } -- 60..15s
local COL_MIST   = { 0.36, 0.12, 0.85 } -- < 15s, pulsing
local COL_HIDDEN = { 0.45, 0.15, 0.90 } -- "?" for wrecks in the fog

local gameSpeed = Game.gameSpeed
local maxDistSq = maxDrawDist * maxDrawDist
local syncInterval = gameSpeed
local touchPollInterval = 6 -- frames between tamper-detection polls (~5x per second)

local spGetFeaturePosition   = Spring.GetFeaturePosition
local spGetFeatureRulesParam = Spring.GetFeatureRulesParam
local spGetFeatureResources  = Spring.GetFeatureResources
local spGetFeatureHealth     = Spring.GetFeatureHealth
local spIsPosInLos           = Spring.IsPosInLos
local spGetGameFrame         = Spring.GetGameFrame
local spGetCameraPosition    = Spring.GetCameraPosition
local spIsGUIHidden          = Spring.IsGUIHidden
local spValidFeatureID       = Spring.ValidFeatureID

local glPushMatrix = gl.PushMatrix
local glPopMatrix  = gl.PopMatrix
local glTranslate  = gl.Translate
local glBillboard  = gl.Billboard
local glText       = gl.Text
local glDepthTest  = gl.DepthTest
local glColor      = gl.Color

local floor = math.floor
local sin   = math.sin
local abs   = math.abs
local format = string.format

local tracked = {}
local trackedCount = 0

local function untrackFeature(featureID)
	if tracked[featureID] then
		tracked[featureID] = nil
		trackedCount = trackedCount - 1
	end
end

local function tryAddFeature(featureID, knownCreation)
	if tracked[featureID] then
		return
	end

	local spawnFrame = spGetFeatureRulesParam(featureID, ZOMBIE_REZ_FRAME_PARAM)
	if not spawnFrame then
		return
	end

	local x, y, z = spGetFeaturePosition(featureID)
	if not x then
		return
	end

	local data = {
		spawnFrame = spawnFrame,
		x = x,
		y = y,
		z = z,
		hidden = false,
	}
	-- seen from birth: the param minus now is this corpse's exact full delay,
	-- which is what the gadget re-arms to when the corpse gets touched
	if knownCreation then
		local frame = spGetGameFrame()
		if spawnFrame > frame then
			data.delayFrames = spawnFrame - frame
		end
	end
	tracked[featureID] = data
	trackedCount = trackedCount + 1
end

local function syncTrackedFeature(featureID, data, frame)
	local spawnFrame = spGetFeatureRulesParam(featureID, ZOMBIE_REZ_FRAME_PARAM)

	if not spawnFrame or not spValidFeatureID(featureID) then
		-- unreadable: gone for real (we can see the spot), or just fogged
		if spIsPosInLos(data.x, data.y, data.z) then
			untrackFeature(featureID)
		else
			data.hidden = true -- timer may get reset unseen: show "?"
		end
		return
	end

	local x, y, z = spGetFeaturePosition(featureID)
	if not x then
		if spIsPosInLos(data.x, data.y, data.z) then
			untrackFeature(featureID)
		else
			data.hidden = true
		end
		return
	end

	if frame > spawnFrame + gameSpeed then
		untrackFeature(featureID)
		return
	end

	if data.spawnFrame ~= spawnFrame then
		data.displaySec = nil
		data.predictedFrame = nil -- the gadget published the real reset; it wins
	end

	if data.hidden then
		data.lastMetal = nil -- fog gap: reseed before trusting change detection
	end
	data.hidden = false
	data.spawnFrame = spawnFrame
	data.x = x
	data.y = y
	data.z = z
end

-- The gadget postpones the spawn to (last touch + full delay) whenever a build
-- step hits the corpse, but only publishes the new frame once the old one
-- expires. Reclaim and resurrect progress are visible on screen, so watch them
-- and predict the reset instantly; the published value reconciles it later.
local function pollTampering(frame)
	for featureID, data in pairs(tracked) do
		if not data.hidden and data.delayFrames then
			local metal, _, _, _, reclaimLeft = spGetFeatureResources(featureID)
			if metal then
				local _, _, rezProgress = spGetFeatureHealth(featureID)
				reclaimLeft = reclaimLeft or 1
				rezProgress = rezProgress or 0
				if data.lastMetal and (abs(metal - data.lastMetal) > 0.01
					or abs(reclaimLeft - data.lastReclaimLeft) > 0.0001
					or abs(rezProgress - data.lastRezProgress) > 0.0001) then
					data.predictedFrame = frame + data.delayFrames
				end
				data.lastMetal = metal
				data.lastReclaimLeft = reclaimLeft
				data.lastRezProgress = rezProgress
			end
		end
	end
end

local function getDisplayText(data, remainingSec)
	if data.displaySec == remainingSec then
		return data.text
	end

	local text
	if remainingSec >= 60 then
		text = format("%d:%02d", floor(remainingSec / 60), remainingSec % 60)
	else
		text = format("%d", remainingSec)
	end

	data.displaySec = remainingSec
	data.text = text
	return text
end

function widget:Initialize()
	local zombies = Spring.GetModOptions().zombies
	if not zombies or zombies == "disabled" then
		widgetHandler:RemoveWidget(self)
		return
	end

	-- corpses found at game start were queued this frame, so their delay is
	-- exact too; after a mid-game /luaui reload it is unknown -> no prediction
	local knownCreation = spGetGameFrame() <= 1
	for _, featureID in ipairs(Spring.GetAllFeatures()) do
		tryAddFeature(featureID, knownCreation)
	end
end

function widget:FeatureCreated(featureID, allyTeamID)
	tryAddFeature(featureID, true)
end

function widget:FeatureDestroyed(featureID)
	untrackFeature(featureID)
end

function widget:GameFrame(frame)
	if frame % touchPollInterval == 2 then
		pollTampering(frame)
	end

	if frame % syncInterval ~= 11 then
		return
	end

	for featureID, data in pairs(tracked) do
		syncTrackedFeature(featureID, data, frame)
	end
end

function widget:DrawWorld()
	if trackedCount == 0 or spIsGUIHidden() then
		return
	end

	local frame = spGetGameFrame()
	local camX, camY, camZ = spGetCameraPosition()

	glDepthTest(false)
	for featureID, data in pairs(tracked) do
		local dx = data.x - camX
		local dy = data.y - camY
		local dz = data.z - camZ
		if (dx * dx + dy * dy + dz * dz) < maxDistSq then
			local text, r, g, b, a

			if data.hidden then
				-- out of sight: the timer may have been reset unseen
				text = "?"
				r, g, b = COL_HIDDEN[1], COL_HIDDEN[2], COL_HIDDEN[3]
				a = 0.85
			else
				local spawnFrame = data.spawnFrame
				if data.predictedFrame and data.predictedFrame > spawnFrame then
					spawnFrame = data.predictedFrame
				end
				local remainingFrames = spawnFrame - frame
				if remainingFrames >= 0 then
					local remainingSec = floor(remainingFrames / gameSpeed)
					text = getDisplayText(data, remainingSec)

					local c = COL_FAR
					a = 0.85
					if remainingSec < warnSeconds then
						c = COL_MIST
						a = 0.6 + 0.4 * sin(frame * 0.35)
					elseif remainingSec < 60 then
						c = COL_CLOSE
					elseif remainingSec < 120 then
						c = COL_NEAR
					end
					r, g, b = c[1], c[2], c[3]
					if not spIsPosInLos(data.x, data.y, data.z) then
						a = a * 0.6
					end
				end
			end

			if text then
				glPushMatrix()
				glTranslate(data.x, data.y + heightBonus, data.z)
				glBillboard()
				glColor(r, g, b, a)
				glText(text, 0, 0, textSize, "con")
				glPopMatrix()
			end
		end
	end
	glColor(1, 1, 1, 1)
	glDepthTest(true)
end
