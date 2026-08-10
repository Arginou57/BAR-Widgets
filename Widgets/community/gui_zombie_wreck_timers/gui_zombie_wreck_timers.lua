local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name    = "Zombie Wreck Timers",
		desc    = "When the Zombies modoption is on, shows a countdown over each wreck until it reanimates. Display only.",
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

local spGetFeaturePosition   = Spring.GetFeaturePosition
local spGetFeatureRulesParam = Spring.GetFeatureRulesParam
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
local format = string.format

local tracked = {}
local trackedCount = 0

local function untrackFeature(featureID)
	if tracked[featureID] then
		tracked[featureID] = nil
		trackedCount = trackedCount - 1
	end
end

local function tryAddFeature(featureID)
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

	tracked[featureID] = {
		spawnFrame = spawnFrame,
		x = x,
		y = y,
		z = z,
		hidden = false,
	}
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
	end

	data.hidden = false
	data.spawnFrame = spawnFrame
	data.x = x
	data.y = y
	data.z = z
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

	for _, featureID in ipairs(Spring.GetAllFeatures()) do
		tryAddFeature(featureID)
	end
end

function widget:FeatureCreated(featureID, allyTeamID)
	tryAddFeature(featureID)
end

function widget:FeatureDestroyed(featureID)
	untrackFeature(featureID)
end

function widget:GameFrame(frame)
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
				local remainingFrames = data.spawnFrame - frame
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
