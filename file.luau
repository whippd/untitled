local fps = 240
local teleportInterval = 0.3
local sprintInterval = 3.2
local enable = false
local sprintEnabled = true
local farmThread = nil
local floorThreshold = 270
local sessionAurum, sessionEXP, sessionLevel = 0, 0, 0
local lastAurum, lastEXP, lastLevel, lastFloor
local farmtype = "lawn"
if game.PlaceId == 4742977291 then
	farmtype = "arena"
end
local intervalTotals = {
	["10min"] = {A=0, E=0, L=0, F=0, start=os.time()},
	["30min"] = {A=0, E=0, L=0, F=0, start=os.time()},
	["60min"] = {A=0, E=0, L=0, F=0, start=os.time()}
}
local startTime = os.time()
_G.AutoLawnBoss = false
local islawnbosshere = false

local library = loadstring(game:GetObjects("rbxassetid://7657867786")[1].Source)()
local Wait = library.subs.Wait

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local sprinttoggles = {}
local sprinttimetoggles = {}
local function getLawnBoss()
	local fallback

	for _, v in ipairs(workspace:GetChildren()) do
		if v.Name == "Troop" then
			local maxhp = v:FindFirstChild("MaxHP", true)
			local realhp = v:FindFirstChild("RealHP", true)
			local hrp = v:FindFirstChild("HumanoidRootPart", true)

			if maxhp and maxhp:IsA("NumberValue") and maxhp.Value == 90 and hrp and realhp.Value ~= 0 then
				return hrp
			end
		elseif v:IsA("Folder") and not fallback then
			local boss = v:FindFirstChild("BossModel")
			if boss then
				fallback = boss:FindFirstChild("HumanoidRootPart")
			end
		end
	end

	return fallback
end
local function getChar()
	return LP.Character or LP.CharacterAdded:Wait()
end

local function getHum(char)
	return char and char:FindFirstChildOfClass("Humanoid")
end

local Remotes = workspace:WaitForChild("Heck Yeah")

local function fireSprint(state)
	Remotes.RunAway:FireServer(state)
end


local function strengthen(amount)
	for _, child in pairs(getChar():GetDescendants()) do
		if child.ClassName == "Part" then
			child.CustomPhysicalProperties = PhysicalProperties.new(amount, 0.3, 0.5)
		end
	end
end
getgenv().Settings = getgenv().Settings or {
	WebhookEnabled = false,
	WebhookLink = "PASTE_WEBHOOK_HERE",
	WebhookInterval = 300,
}


local Settings = getgenv().Settings
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local function TweenTo(cf)
	local character = LP.Character or LP.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart")

	local BV = rootPart:FindFirstChild("PaciationBV") or Instance.new("BodyVelocity")
	BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	BV.Velocity = Vector3.new(0, 0, 0)
	BV.Parent = rootPart
	BV.Name = "PaciationBV"

	rootPart.CFrame = CFrame.new(rootPart.Position.X, cf.Position.Y, rootPart.Position.Z)

	local goal = CFrame.new(cf.Position)

	local tween = TweenService:Create(
		rootPart,
		TweenInfo.new((cf.Position - rootPart.Position).Magnitude / 20, Enum.EasingStyle.Linear),
		{CFrame = goal}
	)

	tween:Play()
	return tween
end

local function TweenToWait(cf)
	local tween = TweenTo(cf)
	tween.Completed:Wait()
end
local function setMassless(obj)
	for i, v in pairs(obj:GetDescendants()) do
		if pcall(function() return v.Massless end) then
			v.Massless = true
		end
	end
end
local function sendWebhook(title, intervalStats)
	if not Settings.WebhookEnabled or Settings.WebhookLink == "" then return end

	local payload = {
		embeds = {{
			title = title,
			description = "**Dungeon Progress Update**",
			color = 0x57f287,
			timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"), 
			fields = {
				{name = "Session Aurum", value = tostring(sessionAurum), inline = true},
				{name = "Session EXP", value = tostring(sessionEXP), inline = true},
				{name = "Session Levels", value = tostring(sessionLevel), inline = true},
				{name = "Interval Stats", value = intervalStats, inline = false},
				{name = "Current Floor", value = tostring(workspace.DungeonData.Floor.Value), inline = true}
			},
			footer = {
				text = "Paciation Tech Arena Farm",
				icon_url = "https://cdn.discordapp.com/attachments/394939426565783562/149231223966597130/Medal_nX24dR4vRN.png?ex=69d6f0cd&is=69d59f4d&hm=4c1dbb51a4575363be57f0a013fbdc1366c99074a6403262a2983928af8be2c7" 
			}
		}}
	}

	request({
		Url = Settings.WebhookLink,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode(payload)
	})
end

local function getClosestBadGuy(myHRP)
	local badGuysFolder = workspace:FindFirstChild("BadGuys")
	if not badGuysFolder then
		return nil
	end

	local closest = nil
	local shortest = math.huge

	for _, v in pairs(badGuysFolder:GetChildren()) do
		local hrp = v:FindFirstChild("HumanoidRootPart")
		local hum = v:FindFirstChildOfClass("Humanoid")
		local stats = v:FindFirstChild("Stats")
		local hp = stats and stats:FindFirstChild("HP")

		if hrp and hum and hp and hp.Value > 0 then
			local dist = (myHRP.Position - hrp.Position).Magnitude
			if dist < shortest then
				shortest = dist
				closest = hrp
			end
		end
	end

	return closest
end

local lastRelativeCFs = {}
local lastFireTimes = {}

if workspace:FindFirstChild("DungeonData") then
	workspace.DungeonData:WaitForChild("Floor"):GetPropertyChangedSignal("Value"):Connect(function()
		lastRelativeCFs = {}
		lastFireTimes = {}
	end)
end
local ATTACH_INTERVAL = 5
local detach = false
local function doSpecialAttachment()
	local char = getChar()
	if not char then return end
	local myHRP = char:FindFirstChild("HumanoidRootPart")
	if not myHRP then return end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then return end
	local smashMouth = tool:FindFirstChild("SmashMouth")
	if not smashMouth then return end
	local targetHRP

	local isLawn = farmtype == "lawn"
	targetHRP = isLawn and getLawnBoss() or getClosestBadGuy(myHRP)

	if not targetHRP then return end
	local hum = getHum(char)
	if not hum or hum.Health == 0 then return end
	local relativeCF = myHRP.CFrame:ToObjectSpace(targetHRP.CFrame)
	local lastCF = lastRelativeCFs[targetHRP]
	local lastTime = lastFireTimes[targetHRP] or 0
	local now = tick()

	local changed = true
	if lastCF then
		local posDiff = (relativeCF.Position - lastCF.Position).Magnitude
		local rotDiff = (relativeCF.LookVector - lastCF.LookVector).Magnitude
		if posDiff <= 0.1 and rotDiff <= 0.1 then
			changed = false
		end
	end

	if changed or (now - lastTime >= ATTACH_INTERVAL) then
		lastRelativeCFs[targetHRP] = relativeCF
		lastFireTimes[targetHRP] = now
		if detach == true then
			Remotes.SpecialDetachment:FireServer()
		end
		Remotes.SpecialAttachment:FireServer(
			smashMouth,
			relativeCF,
			nil,
			"HumanoidRootPart"
		)
	end
	Remotes.BringTheMowingIGuess:FireServer(
		targetHRP,
		tool
	)

end

local function handleSprintCycle()
	if not sprintEnabled then
		return
	end

	local char = getChar()
	if not char then
		return
	end

	local stats = char:FindFirstChild("Stats")
	if not stats then
		return
	end

	local sprintVal = stats:FindFirstChild("SprintFactor")
	if not sprintVal then
		return
	end

	if sprintVal.Value == 0 then
		fireSprint("on")

		repeat
			task.wait(0.05)
			if not enable or not _G.AutoLawnBoss or not sprintEnabled then
				return
			end
		until sprintVal.Value >= 20
	end

	if sprintVal.Value >= 20 then
		fireSprint("off")

		local elapsed = 0
		while (enable or _G.AutoLawnBoss) and elapsed < sprintInterval do
			doSpecialAttachment()

			local step = task.wait(teleportInterval)
			elapsed = elapsed + step
		end
	end
end

local function stopFarm()
	enable = false
	lastRelativeCFs = {}
	lastFireTimes = {}
end

local function startFarm()
	if farmThread then
		return
	end
	lastRelativeCFs = {}
	lastFireTimes = {}
	farmThread = task.spawn(function()
		while task.wait(0.1) and enable do
			local ok, err = pcall(function()
				if sprintEnabled then
					handleSprintCycle()
				else
					doSpecialAttachment()
					task.wait(teleportInterval)
				end
			end)
		end

		farmThread = nil
	end)
end
local function reset()
	getChar().Humanoid.Health = 0
	if enable and game.PlaceId == 4742977291 then
		LP.CharacterAdded:Wait()
		stopFarm()
		task.wait(3)
		farmThread = nil
		enable = true
		startFarm()
	end
end
local PepsisWorld = library:CreateWindow({
	Name = "Paciation Tech Arena Farm",
	Themeable = {
		Info = "Made with Greatness"
	}
})

local GeneralTab = PepsisWorld:CreateTab({
	Name = "General"
})

local MainSection = GeneralTab:CreateSection({
	Name = "Main"
})

MainSection:AddToggle({
	Name = "Toggle Farm",
	Flag = "Enabled",
	Callback = function(state)
		enable = state

		if enable then
			startFarm()
		else
			stopFarm()
			print("Farm disabled")
		end
	end
})

MainSection:AddSlider({
	Name = "Teleport Interval",
	Flag = "MainSection_TeleportInterval",
	Value = teleportInterval,
	Precise = 2,
	Min = 0.05,
	Max = 2,
	Callback = function(value)
		teleportInterval = value
		print("Teleport Interval set to:", teleportInterval)
	end
})

sprinttoggles[1] = MainSection:AddToggle({
	Name = "Sprint Toggle",
	Flag = "FarmingSection_TrickSpammer",
	Value = sprintEnabled,
	Callback = function(state)
		sprintEnabled = state
		for i,v in pairs(sprinttoggles) do
			v:Set(state)
		end
		print("Sprint Toggle:", sprintEnabled)
	end
})

sprinttimetoggles[1] = MainSection:AddSlider({
	Name = "Sprint Interval",
	Flag = "MainSection_SprintInterval",
	Value = sprintInterval,
	Precise = 1,
	Min = 0.5,
	Max = 10,
	Callback = function(value)
		sprintInterval = value
		for i,v in pairs(sprinttimetoggles) do
			v:Set(value)
		end
		print("Sprint Interval set to:", sprintInterval)
	end
})
MainSection:AddToggle({
	Name = "Detach upon new attachment",
	Flag = "Enableddetach",
	Callback = function(state)
		detach = state
	end
})
local positions = {
	Center = CFrame.new(-40, 150, -40),
	Corner1 = CFrame.new(52.515, 150, 102.028),
	Corner2 = CFrame.new(-147.433, 150, 101.946),
	Corner3 = CFrame.new(-148.428, 150, -108.438),
	Corner4 = CFrame.new(63.792, 150, -108.438),
  	UnderCenter = CFrame.new(-40, -200, -40),
	UnderCorner1 = CFrame.new(52.515, -200, 102.028),
	UnderCorner2 = CFrame.new(-147.433, -200, 101.946),
	UnderCorner3 = CFrame.new(-148.428, -200, -108.438),
	UnderCorner4 = CFrame.new(63.792, -200, -108.438)
}
local tweenchosen = "Center"
local autoTween = false
MainSection:AddDropdown({
	Name = "Tween to:",
	Value = tweenchosen,
	List = {"Corner1", "Corner2", "Corner3", "Corner4", "Center", "UnderCenter", "UnderCorner1", "UnderCorner2", "UnderCorner3", "UnderCorner4"},
	Flag = "TweenDropdown",
	Callback = function(value, old)
		tweenchosen = value
	end,
	Multi = false,
	Sort = true
})

MainSection:AddButton({
	Name = "Tween",
	Callback = function()
		TweenTo(positions[tweenchosen])
	end
})

MainSection:AddToggle({
	Name = "Auto Tween on Respawn",
	Value = autoTween,
	Flag = "AutoTweenRespawn",
	Callback = function(value, old)
		autoTween = value
	end
})

MainSection:AddToggle({
	Name = "Auto Reset Dungeon (Threshold)",
	Flag = "FarmingSection_ResetDungeon",
	Callback = function(state)
		_G.AutoDungeonQuit = state
		while _G.AutoDungeonQuit and task.wait(5) do
			pcall(function()
				if workspace.DungeonData.Floor.Value >= floorThreshold then
					reset()
				end
			end)
		end		
	end
})

MainSection:AddTextbox({
	Name = "Floor Reset Threshold",
	Value = floorThreshold,
	Placeholder = "Replace with what wave to reset on MUST BE A NUMBER",
	Flag = "FarmingSection_ResetThreshold",
	Type = "number",
	Min = 1,
	Max = 10000,
	Callback = function(value)
		floorThreshold = tonumber(value)
		print("Floor set to", value)
	end
})

local OptimizeSection = GeneralTab:CreateSection({
	Name = "Optimisation"
})

OptimizeSection:AddButton({
	Name = "Disable Enemy Animations",
	Callback = function()
		local BadGuys = workspace:WaitForChild("BadGuys")
		local connections = {} 

		local function disableAnims(humanoid)
			if not humanoid or humanoid.Parent == nil then return end

			for _, v in pairs(humanoid.Parent:GetDescendants()) do
				if v:IsA("Animator") or v:IsA("Animation") or v:IsA("AnimationController") then
					v:Destroy()
				end
			end

			local con
			con = humanoid.Died:Connect(function()
				if con then
					con:Disconnect()
					con = nil
				end
			end)
			table.insert(connections, con)
		end

		for _, enemy in pairs(BadGuys:GetChildren()) do
			local h = enemy:FindFirstChildOfClass("Humanoid")
			if h then disableAnims(h) end
		end

		local childCon = BadGuys.ChildAdded:Connect(function(enemy)
			local h = enemy:FindFirstChildOfClass("Humanoid")
			if h then disableAnims(h) end

			local descCon
			descCon = enemy.DescendantAdded:Connect(function(d)
				if d:IsA("Humanoid") then disableAnims(d) end
			end)
			table.insert(connections, descCon)
		end)
		table.insert(connections, childCon)
	end
})

local badGuysConnection 

OptimizeSection:AddButton({
	Name = "Delete Enemies",
	Callback = function()
		if badGuysConnection then
			badGuysConnection:Disconnect()
		end

		badGuysConnection = workspace.BadGuys.DescendantAdded:Connect(function(obj)
			if obj.Name == "HumanoidRootPart" then
				obj.Anchored = true
			elseif (obj:IsA("BasePart") or obj:IsA("UnionOperation")) and obj.Name ~= "HumanoidRootPart" then
				game:GetService("Debris"):AddItem(obj, 0)
			end
		end)
	end
})
OptimizeSection:AddButton({
	Name = "Delete Map",
	Callback = function()
		workspace:FindFirstChild("Shell",true):Destroy()
	end
})

OptimizeSection:AddSlider({
	Name = "Set FPS",
	Flag = "OptimizeSection_ChangeFPS",
	Value = fps,
	Precise = 1,
	Min = 10,
	Max = 240,
	Callback = function(value)
		fps = value
		if setfpscap then
			setfpscap(fps)
		end
	end
})

local WebhookSection = GeneralTab:CreateSection({
	Name = "Webhook Settings"
})
WebhookSection:AddToggle({
	Name = "Enable Webhook",
	Flag = "WebhookEnabled",
	Value = Settings.WebhookEnabled,
	Callback = function(state)
		Settings.WebhookEnabled = state

		if state then
			startTime = os.time()
			sessionAurum, sessionEXP, sessionLevel = 0, 0, 0
			lastAurum, lastEXP, lastLevel, lastFloor = nil, nil, nil, nil
			task.spawn(function()
				while Settings.WebhookEnabled do
					task.wait(Settings.WebhookInterval)

					local stats = LP:FindFirstChild("Stats")
					if not stats then continue end

					local aurum, exp, level = stats:FindFirstChild("Aurum"), stats:FindFirstChild("EXP"), stats:FindFirstChild("Level")
					local floor = workspace.DungeonData:WaitForChild("Floor").Value
					if not aurum or not exp or not level then continue end

					local curAurum, curEXP, curLevel = aurum.Value, exp.Value, level.Value
					if not lastAurum then
						lastAurum, lastEXP, lastLevel, lastFloor = curAurum, curEXP, curLevel, floor
						continue
					end

					local diffAurum = math.max(curAurum - lastAurum, 0)
					local diffEXP = math.max(curEXP - lastEXP, 0)
					local diffLevel = math.max(curLevel - lastLevel, 0)
					local diffFloor = math.max(floor - lastFloor, 0)

					sessionAurum += diffAurum
					sessionEXP += diffEXP
					sessionLevel += diffLevel

					for _, v in pairs(intervalTotals) do
						v.A += diffAurum
						v.E += diffEXP
						v.L += diffLevel
						v.F += diffFloor
					end

					local now = os.time()
					local totalElapsed = now - startTime
					local totalElapsedStr = string.format("<t:%d:R>", startTime)

					local totalAurumPerMin = totalElapsed > 0 and (sessionAurum / totalElapsed * 60) or 0
					local totalEXPPerMin = totalElapsed > 0 and (sessionEXP / totalElapsed * 60) or 0
					local totalLevelPerMin = totalElapsed > 0 and (sessionLevel / totalElapsed * 60) or 0

					local statStr = string.format(
						"**Total Elapsed:** %s\n**Since Start** | Aurum: +%d (%.1f/m) | EXP: +%d (%.1f/m) | Level: +%d (%.2f/m)\n\n",
						totalElapsedStr,
						sessionAurum, totalAurumPerMin,
						sessionEXP, totalEXPPerMin,
						sessionLevel, totalLevelPerMin
					)

					for k,v in pairs(intervalTotals) do
						local elapsed = now - v.start
						if elapsed >= 1 then
							local aurumPerMin = math.max(v.A/elapsed*60, 0)
							local expPerMin = math.max(v.E/elapsed*60, 0)
							local levelPerMin = math.max(v.L/elapsed*60, 0)
							local floorPerMin = math.max(v.F/elapsed*60, 0)

							statStr = statStr .. string.format(
								"%s | Aurum: +%d (%.1f/m) | EXP: +%d (%.1f/m) | Level: +%d (%.2f/m) | Floor: +%d\n",
								k, v.A, aurumPerMin, v.E, expPerMin, v.L, levelPerMin, v.F
							)
						end
					end

					sendWebhook("Progress Update", statStr)

					if now - intervalTotals["10min"].start >= 600 then intervalTotals["10min"] = {A=0,E=0,L=0,F=0,start=now} end
					if now - intervalTotals["30min"].start >= 1800 then intervalTotals["30min"] = {A=0,E=0,L=0,F=0,start=now} end
					if now - intervalTotals["60min"].start >= 3600 then intervalTotals["60min"] = {A=0,E=0,L=0,F=0,start=now} end

					lastAurum, lastEXP, lastLevel, lastFloor = curAurum, curEXP, curLevel, floor
				end
			end)
		end
	end
})

WebhookSection:AddTextbox({
	Name = "Webhook URL",
	Value = Settings.WebhookLink,
	Placeholder = "Paste your webhook here...",
	Flag = "WebhookLink",
	Callback = function(value)
		Settings.WebhookLink = tostring(value)
		print("Webhook URL set")
	end
})

WebhookSection:AddSlider({
	Name = "Webhook Interval (s)",
	Value = Settings.WebhookInterval,
	Min = 60,
	Max = 3600,
	Precise = 1,
	Flag = "WebhookInterval",
	Callback = function(value)
		Settings.WebhookInterval = value
		print("Webhook Interval set to:", value)
	end
})

local OtherSection = GeneralTab:CreateSection({ Name = "Other Stuff", Side = "Right" })

OtherSection:AddButton({
	Name = "TP to Public Arena (be n arena)",
	Callback = function()
		queue_on_teleport([[repeat task.wait() until game:IsLoaded()
		task.wait(5)
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		_G.NoClip1 = true
		local function NoclipLoop()
			if _G.NoClip1 == true and player.Character ~= nil then
				for _, child in pairs(player.Character:GetDescendants()) do
					if child:IsA("BasePart") and child.CanCollide == true  then
						child.CanCollide = false
					end
				end
			end
		end

        local Noclipping = game:GetService("RunService").Stepped:Connect(NoclipLoop)
        local characterAddedConnection = player.CharacterAdded:Connect(function()
            repeat
                task.wait()
            until player.Character and
                player.Character:FindFirstChild("HumanoidRootPart")
            if _G.NoClip1 == true then
                NoclipLoop()
            end
        end)

        if _G.NoClip1 == false then
            characterAddedConnection:Disconnect()
            Noclipping:Disconnect()
         end
		local function TweenTo(cf)
			local character = player.Character or player.CharacterAdded:Wait()
			local rootPart = character:WaitForChild("HumanoidRootPart")
			rootPart.CFrame = CFrame.new(rootPart.Position.X, cf.Position.Y, rootPart.Position.Z)
			local bv = rootPart:FindFirstChild("PaciationBV")

			if not bv then
				local BV = Instance.new("BodyVelocity")
				BV.Name = "PaciationBV"
				BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
				BV.Velocity = Vector3.new(0, 0, 0)
				BV.Parent = rootPart
			end
		end
		task.spawn(function()
			for i,v in pairs(workspace:GetDescendants()) do
				if v.Name == "ToolGrip" then
					v:Destroy()
				end
			end
		end)
		for i=1,120 do
			task.spawn(function()
				TweenTo(CFrame.new(-40, 180, -40))
			end)
			task.wait(0.1)
		end
		_G.NoClip1 = false
        characterAddedConnection:Disconnect()
        Noclipping:Disconnect()
		]])
		task.wait(2)
		game:GetService("TeleportService"):Teleport(4742977291)

	end
})

--[[OtherSection:AddToggle({
	Name = "Anti Softlock",
	Flag = "AntiSoftlock",
	Callback = function(state)
        _G.AntiDungeonSoftlock = state
		while _G.AntiDungeonSoftlock and task.wait(4) do
			local data = workspace:FindFirstChild("DungeonData")
			local char = getChar()
			local hum = getHum(char)

			if not data or not hum then continue end

			local wave = data.Floor.Value

			if data.Enemies.Value == 0 or #workspace.BadGuys:GetChildren() == 0 then
				task.wait(7)

				if data.Floor.Value == wave then
					hum.Health = 0
				end
			end
		end		
	end
})]]
OtherSection:AddToggle({
	Name = "Anti Softlock but V2!!!!!",
	Flag = "AntiSoftlock2",
	Callback = function(state)
		_G.AntiDungeonSoftlock2 = state
		while _G.AntiDungeonSoftlock2 and task.wait(4) do
			local data = workspace:FindFirstChild("DungeonData")
			local char = getChar()
			local hum = getHum(char)

			if not data or not hum then continue end


			for i,v in pairs(workspace:FindFirstChild("BadGuys"):GetChildren()) do
				task.spawn(function()
					if not v:FindFirstChild("HumanoidRootPart") then
						task.wait(5)
						if not v:FindFirstChild("HumanoidRootPart") then
							hum.Health = 0
						end
					end
				end)
			end
		end		
	end
})

local noclipConnection
local characterConnection

local function NoclipLoop()
	if _G.NoClip == true and LP.Character then
		for i, v in pairs(LP.Character:GetDescendants()) do
			if v:IsA("BasePart") and v.CanCollide == true then
				v.CanCollide = false
			end
		end
	end
end

OtherSection:AddToggle({
	Name = "Noclip",
	Flag = "noclip",
	Callback = function(state)
		_G.NoClip = state

		if state then
			noclipConnection = game:GetService("RunService").Stepped:Connect(NoclipLoop)

			characterConnection = LP.CharacterAdded:Connect(function()
				repeat task.wait() until LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
				if _G.NoClip == true then
					NoclipLoop()
				end
			end)
		else
			if noclipConnection then
				noclipConnection:Disconnect()
				noclipConnection = nil
			end

			if characterConnection then
				characterConnection:Disconnect()
				characterConnection = nil
			end
		end
	end
})

OtherSection:AddButton({
	Name = "Freeze/Unfreeze yourself",
	Callback = function()
		local anchored = getChar().HumanoidRootPart.Anchored
		getChar().HumanoidRootPart.Anchored = not anchored
	end
})
local removeToolGrips = false
OtherSection:AddToggle({
	Name = "Anti ToolGrips",
	Flag = "fucktoolgips",
	Callback = function(state)
		removeToolGrips = state
		task.spawn(function()
			for i,v in pairs(workspace:GetDescendants()) do
				if v.Name == "ToolGrip" then
					v:Destroy()
				end
			end
		end)
	end
})


--[[local toolswapantilaginterval = 600
_G.SwapTool = false
OtherSection:AddSlider({
    Name = "Tool Swap Interval",
    Value = toolswapantilaginterval,
    Min = 60,
    Max = 3600,
    Precise = 1,
    Flag = "Toolswap",
    Callback = function(value)
        toolswapantilaginterval = value
    end
})

OtherSection:AddToggle({
	Name = "Auto Swap Tool (no server lag)",
	Flag = "ServerLagWow",
	Callback = function(state)
		_G.SwapTool = state
		while _G.SwapTool and task.wait(toolswapantilaginterval) do
			local currenttool = LP.Stats.Tool.Value
			task.wait(1)
			local args = {
				"Tool",
				"PushMowerSilver"
			}
			workspace:WaitForChild("Heck Yeah"):WaitForChild("WhenIDanceYouEquip"):FireServer(unpack(args))
			task.wait(2)
			local args = {
				"Tool",
				currenttool
			}
			workspace:WaitForChild("Heck Yeah"):WaitForChild("WhenIDanceYouEquip"):FireServer(unpack(args))
			task.wait(1)
		end
	end
})]]
--local torsoConnection



local LawnTab = PepsisWorld:CreateTab({
	Name = "Lawn"
})
local equipdps = true
local toolStatsTable = {}
local ToolStats = workspace.Singularity.ToolStats
local EquipRemote = Remotes:WaitForChild("WhenIDanceYouEquip")
local function getBestTool()
	local best, bestValue = nil, 0
	if _G.KaliAutoMow == true then
		best = "ExKalibur"
	else
		for i, tool in ipairs(ToolStats:GetChildren()) do
			local yield = tool:FindFirstChild("Yield")
			if yield then
				local val = yield.Value
				if val > bestValue and LP.ItemInventory:FindFirstChild(tool.Name) then
					best = tool.Name
					bestValue = val
				end
			end
		end
	end
	return best
end

local function getBestDPS()
	local best, bestValue = nil, 0

	for i, tool in ipairs(ToolStats:GetChildren()) do
		local dmg = tool:FindFirstChild("Damage")
		local cd = tool:FindFirstChild("Cooldown")

		if dmg and cd and cd.Value > 0 then
			local dps = dmg.Value / cd.Value

			if dps > bestValue and LP.ItemInventory:FindFirstChild(tool.Name) then
				best = tool.Name
				bestValue = dps
			end
		end
	end

	return best
end
local function equipBest()
	if _G.AutoLawnBoss == true and equipdps == true and islawnbosshere == true then return end
	local best = getBestTool()
	if best then
		task.wait(.25)
		if islawnbosshere == return end
		EquipRemote:FireServer("Tool", best)
	end
end

for _, child in ipairs(ToolStats:GetChildren()) do
	if child.Class.Value ~= "Boss" and child.GamepassID.Value == 0 and child.Name ~= "PushMower" then
		table.insert(toolStatsTable, child.Name)
	end
end

local MainLawn = LawnTab:CreateSection({
	Name = "Main"
})

local autoMow = false
local mowLoopDelay = 5
local mowStepDelay = 0.08
local mowThread
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = workspace:FindFirstChild("GRASS") and workspace.GRASS:GetDescendants() or {}
local randomOffset = 0 
local lawnYOffset = 0 


local function MowLawn()
	if _G.AutoLawnBoss == true and islawnbosshere == true then return end
	local char = getChar()
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local tool = char:FindFirstChildOfClass("Tool")
	if not hrp or not tool then return end
	local toolStats = workspace.Singularity.ToolStats:FindFirstChild(tool.Name)
	if not toolStats then return end
	local radius = toolStats.SmashSize.Value
	local sprint = char:FindFirstChild("SprintFactor", true)
	if sprint and sprint.Value == 20 then
		fireSprint("off")
	end
	local BottomRight = Vector3.new(-54.5,0,-121.5)
	local TopLeft = Vector3.new(90.5,0,23.5)
	local smashmouth = tool:FindFirstChild("SmashMouth") or tool:FindFirstChildOfClass("BasePart")

	for x = BottomRight.X, TopLeft.X, math.sqrt(2)*radius do
		for z = BottomRight.Z, TopLeft.Z, math.sqrt(2)*radius do
			local offsetX = math.random() * randomOffset * 2 - randomOffset
			local offsetZ = math.random() * randomOffset * 2 - randomOffset

			workspace["Heck Yeah"].SpecialAttachment:FireServer(
				smashmouth,
				hrp.CFrame:ToObjectSpace(CFrame.new(x + offsetX, 2.5 + lawnYOffset, z + offsetZ)),
				nil,
				"HumanoidRootPart"
			)
			task.wait(mowStepDelay)

			for _, grass in pairs(workspace:GetPartBoundsInRadius(smashmouth.Position, radius*1.25, params)) do
				if grass.Parent == workspace.GRASS and grass:FindFirstChild("Slapped") and not grass.Slapped.Value and grass:FindFirstChild("Mesh") and grass.Mesh.Scale.Y == 1 then
					workspace["Heck Yeah"].BringTheMowingIGuess:FireServer(grass, tool)
				end
			end
		end
	end
end

MainLawn:AddSlider({
	Name = "Loop Delay",
	Value = mowLoopDelay,
	Min = 0.1,
	Max = 10,
	Precise = 1,
	Callback = function(v)
		mowLoopDelay = v
	end
})

MainLawn:AddSlider({
	Name = "Step Speed",
	Value = mowStepDelay,
	Min = 0.01,
	Max = 2.5,
	Precise = 2,
	Callback = function(v)
		mowStepDelay = v
	end
})

MainLawn:AddSlider({
	Name = "Random TP Offset",
	Value = randomOffset,
	Min = 0,
	Max = 10, 
	Precise = 1,
	Callback = function(v)
		randomOffset = v
	end
})
MainLawn:AddSlider({
	Name = "Y Offset",
	Value = lawnYOffset,
	Min = -5,
	Max = 5, 
	Precise = 2,
	Callback = function(v)
		lawnYOffset = v
	end
})

MainLawn:AddButton({
	Name = "Mow Lawn",
	Callback = function()
		task.spawn(MowLawn)
	end
})



MainLawn:AddToggle({
	Name = "Auto Mow",
	Flag = "AutoMow",
	Callback = function(state)
		autoMow = state

		if autoMow and not mowThread then
			mowThread = task.spawn(function()
				while autoMow do
					local success, err = pcall(MowLawn)
					task.wait(mowLoopDelay)
				end
				mowThread = nil
			end)
		elseif not autoMow and mowThread then
			mowThread = nil
		end
	end
})

_G.KaliAutoMow = false
MainLawn:AddToggle({
	Name = "Use Exkalibur For Auto Mow",
	Flag = "KaliAutoMow",
	Value = _G.KaliAutoMow,
	Callback = function(state)
		_G.KaliAutoMow = state
	end
})


local MainLawnBosses = LawnTab:CreateSection({
	Name = "Bosses"
})

MainLawnBosses:AddButton({
	Name = "Lose Boss",
	Callback = function()
		game.Players.LocalPlayer.Character:MoveTo(Vector3.new(game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame.X, -493, game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame.Z))
	end
})


local alllawnbosses = {}
local selectedBosses = {}

for i, v in pairs(workspace.Singularity.BossDex:GetChildren()) do
	table.insert(alllawnbosses, v.Name)
	table.insert(selectedBosses, v.Name)
end

local lawnbosses = MainLawnBosses:AddDropdown({
	Name = "Select Bosses to void",
	List = alllawnbosses,
	Flag = "SelectedBosses",
	Multi = true,
	Callback = function(values)
		selectedBosses = values
	end
})
lawnbosses:Set(selectedBosses)
MainLawnBosses:AddToggle({
	Name = "Auto Lose Bosses",
	Flag = "AutoLose",
	Value = false,
	Callback = function(state)
		_G.AutoLoss = state

		while _G.AutoLoss == true do
			task.wait(1.5)

			local char = game.Players.LocalPlayer.Character
			if not char then continue end

			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then continue end

			for i, v in pairs(workspace:GetChildren()) do
				if v:IsA("Folder") and v:FindFirstChild("BossModel") then

					local isSelected = false
					for i = 1, #selectedBosses do
						if selectedBosses[i] == v.Name then
							isSelected = true
							break
						end
					end
					if not isSelected then continue end

					pcall(function()
						local tween = hrp:FindFirstChild("PaciationBV")
						if tween then tween:Destroy() end
					end)

					char:MoveTo(Vector3.new(hrp.Position.X, -495, hrp.Position.Z))
				end
			end
		end
	end
})
local safespot = true
MainLawnBosses:AddToggle({
	Name = "Auto Farm Lawn Bosses",
	Flag = "AutoLawn",
	Value = false,
	Callback = function(state)
		_G.AutoLawnBoss = state

		while _G.AutoLawnBoss == true do
			task.wait(0.25)

			local lawnboss = getLawnBoss()
			if lawnboss then
				islawnbosshere = true
				pcall(function()
					if sprintEnabled then
						handleSprintCycle()
					else
						doSpecialAttachment()
						task.wait(teleportInterval)
					end
					if safespot then
						local char = getChar()
						local rootPart = char:FindFirstChild("HumanoidRootPart")
						local BV = rootPart:FindFirstChild("PaciationBV") or Instance.new("BodyVelocity")
						BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
						BV.Velocity = Vector3.new(0, 0, 0)
						BV.Name = "PaciationBV"
						local bv = rootPart:FindFirstChild("PaciationBV")
						BV.Parent = rootPart
						if not bv then
							if equipdps then
								local best = getBestDPS()
								
								if best then
									print("best tool found")
									print(best)
									task.wait(0.5)
									EquipRemote:FireServer("Tool", best)
									print("equipped best")
								else
									print("best tool for dps not found")
								end
							end
							char:PivotTo(CFrame.new(rootPart.Position.X, -495, rootPart.Position.Z))
							local road = workspace:FindFirstChild("Road",true)
							tweenTo(CFrame.new(road.Position.X, -495, road.Position.Z - 5))
						end
						BV.Name = "PaciationBV"
					end
				end)
			else
				lastRelativeCFs = {}
				lastFireTimes = {}
				task.spawn(function()
					if safespot and (islawnbosshere or workspace.Singularity.BossActive.Value == false) then
						task.wait(1)
						local char = LP.Character
						if char then
							local bv = char:FindFirstChild("PaciationBV",true)
							if bv then
								reset()
							end
						end
					end
				end)
				islawnbosshere = false
			end
		end
	end
})

MainLawnBosses:AddToggle({
	Name = "Safe Spot TP",
	Flag = "safespottp",
	Value = safespot,
	Callback = function(state)
		safespot = state
	end
})
MainLawnBosses:AddToggle({
	Name = "Equip Highest DPS Tool",
	Flag = "highestdps",
	Value = equipdps,
	Callback = function(state)
		equipdps = state
	end
})
sprinttoggles[2] = MainLawnBosses:AddToggle({
	Name = "Sprint Toggle",
	Flag = "FarmingSection_TrickSpammer2",
	Value = sprintEnabled,
	Callback = function(state)
		sprintEnabled = state
		for i,v in pairs(sprinttoggles) do
			v:Set(state)
		end
		print("Sprint Toggle:", sprintEnabled)
	end
})

sprinttimetoggles[2] = MainLawnBosses:AddSlider({
	Name = "Sprint Interval",
	Flag = "MainSection_SprintInterval2",
	Value = sprintInterval,
	Precise = 1,
	Min = 0.5,
	Max = 10,
	Callback = function(value)
		sprintInterval = value
		for i,v in pairs(sprinttimetoggles) do
			v:Set(value)
		end
		print("Sprint Interval set to:", sprintInterval)
	end
})

local MainLawnTools = LawnTab:CreateSection({ Name = "Tools + BS", Side = "Right" })

MainLawnTools:AddToggle({
	Name = "Auto Buy Best Tools",
	Flag = "AutoBuyBest",
	Callback = function(state)
		_G.AutoBuyAllTools = state
		while _G.AutoBuyAllTools == true do
			for _, toolName in ipairs(toolStatsTable) do
				if not LP.ItemInventory:FindFirstChild(toolName) then
					local args = {
						[1] = "Tool",
						[2] = tostring(toolName)
					}
					workspace:FindFirstChild("Heck Yeah").WhenIDanceYouGive:FireServer(unpack(args))
				end
				task.wait(0.1)
			end
			task.wait(1)
		end
	end
})

MainLawnTools:AddToggle({
	Name = "Auto Equip Best Tool",
	Flag = "AutoequipBest",
	Callback = function(state)
		_G.AutoEquipBest = state

		if state then
			equipBest()
			task.spawn(function()
				while _G.AutoEquipBest and task.wait(5) do
					equipBest()
				end
			end)
		end
	end
})

local removeToolGrips2 = false
MainLawnTools:AddToggle({
	Name = "Anti ToolGrips V2 (for lawn)",
	Flag = "fucktoolgips2",
	Callback = function(state)
		removeToolGrips2 = state
		task.spawn(function()
			while removeToolGrips2 and task.wait(5) do
				local char = getChar()
				local torso = char:FindFirstChild("Torso")

				if not torso then
					continue
				end

				for _, obj in torso:GetDescendants() do
					if obj.Name == "ToolGrip" then
						if obj.Part0 == nil and obj.Part1 == nil then
							obj:Destroy()
						end
					end
				end
			end
		end)
	end
})
_G.MasslessTools = true
MainLawnTools:AddToggle({
	Name = "Auto Massless Tools",
	Flag = "maslesstools",
	Value = _G.MasslessTools,
	Callback = function(state)
		_G.MasslessTools = state
		char = getChar()
		if char then
			tool = char:FindFirstChildOfClass("Tool")
			if tool then
				for i,v in pairs(tool:GetDescendants()) do
					setMassless(v)
				end
			end
		end
	end
})
local autoresetinterval = 2700
_G.AutoReset = false
MainLawnTools:AddSlider({
	Name = "Auto Reset Interval",
	Value = autoresetinterval,
	Min = 60,
	Max = 10000,
	Precise = 1,
	Flag = "autoreset",
	Callback = function(value)
		autoresetinterval = value
	end
})

MainLawnTools:AddToggle({
	Name = "Auto Reset",
	Flag = "AutoResetToggle",
	Callback = function(state)
		_G.AutoReset = state
		while _G.AutoReset and task.wait(autoresetinterval) do
			pcall(function()
				reset()
			end)
		end
	end
})

local autoclickinterval = 60
_G.AutoClicks = false
MainLawnTools:AddSlider({
	Name = "Auto Click Interval",
	Value = autoclickinterval,
	Min = 0.1,
	Max = 300,
	Precise = 1,
	Flag = "autoclickinterval",
	Callback = function(value)
		autoclickinterval = value
	end
})

MainLawnTools:AddToggle({
	Name = "Auto Click",
	Flag = "AutoClickToggle",
	Callback = function(state)
		_G.AutoClicks = state
		while _G.AutoClicks and task.wait(autoclickinterval) do
			game:GetService("VirtualInputManager"):SendMouseButtonEvent(0, 0, 0, true, game, 1)
			task.wait()
			game:GetService("VirtualInputManager"):SendMouseButtonEvent(0, 0, 0, false, game, 1)
		end
	end
})
MainLawnTools:AddButton({
	Name = "Remove Body Velocity",
	Callback = function()
		getChar():FindFirstChild("PaciationBV",true):Destroy()
	end
})

local questFolder = workspace:FindFirstChild("Singularity"):FindFirstChild("Quests")
local questNames = {}
local namePlates = {}
local selectedTasks = {}

if questFolder then
	for i, v in pairs(questFolder:GetChildren()) do
		local namePlate = v:FindFirstChild("NamePlate")
		if namePlate then
			table.insert(questNames, v.Name)
			table.insert(namePlates, namePlate.Value)
		end
	end
end

local function getQuest(value)
	for i, v in pairs(namePlates) do
		if v == value then
			return questNames[i]
		end
	end
end
local function isSelected(taskName)
	for i, v in pairs(selectedTasks) do
		if v == taskName then
			return true
		end
	end
	return false
end

local availabletasks = {}
local level = LP:FindFirstChild("Stats") and LP.Stats:FindFirstChild("Level")

if questFolder and level then
	for i, v in pairs(questFolder:GetChildren()) do
		local min = v:FindFirstChild("MinLvl")
		local max = v:FindFirstChild("MaxLvl")
		local namePlate = v:FindFirstChild("NamePlate")
		local mowerReq = v:FindFirstChild("MowerReq")

		if min and max and namePlate and mowerReq then
			if level.Value >= min.Value and level.Value <= max.Value and mowerReq.Value == "None" then
				table.insert(availabletasks, namePlate.Value)
			end
		end
	end
end

local MainLawnTasks = LawnTab:CreateSection({ Name = "Tasks", Side = "Right" })

local taskstoComplete = MainLawnTasks:AddDropdown({
	Name = "Select Tasks",
	List = availabletasks,
	Flag = "taskstocompelte",
	Multi = true,
	Callback = function(values)
		actualnames = {}
		for i,v in pairs(values) do
			table.insert(actualnames, getQuest(v))
			print(getQuest(v))
		end
		selectedTasks = actualnames
	end
})
taskstoComplete:Set(availabletasks)
MainLawnTasks:AddToggle({
	Name = "Auto Tasks",
	Flag = "tasksautomatic",
	Callback = function(state)
		_G.AutoTasks = state
		while _G.AutoTasks and task.wait(1) do
			pcall(function()
				local currentTask = LP:FindFirstChild("Stats")
					and LP.Stats:FindFirstChild("Task")
					and LP.Stats.Task:FindFirstChild("CurrentTaskName")

				if not currentTask then return end

				if currentTask.Value == "None" then
					Remotes:WaitForChild("SendMeAQuest"):FireServer()
					return
				end

				if isSelected(currentTask.Value) == false then
					local args = {331425813}
					workspace:WaitForChild("Heck Yeah"):WaitForChild("WipeTask"):FireServer(unpack(args))
				end
			end)
		end
	end
})

local MainLawnMinigame = LawnTab:CreateSection({ Name = "Minigames", Side = "Right" })
local minigameinterval = 0.1
MainLawnMinigame:AddSlider({
	Name = "Minigame Interval",
	Value = minigameinterval,
	Min = 0.01,
	Max = 5,
	Precise = 2,
	Flag = "minigameinterval",
	Callback = function(value)
		minigameinterval = value
	end
})
MainLawnMinigame:AddToggle({
	Name = "Solo Minigame Farm",
	Flag = "MinigameSolo",
	Callback = function(state)
		_G.AllFarm = state

		while _G.AllFarm == true and task.wait(minigameinterval) do

			local success, error = pcall(function()
				local char = getChar()
				if not char then return end

				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not hrp then return end

				local rain = workspace:FindFirstChild("Rain")

				for i, part in pairs(workspace:GetChildren()) do
					local name = part.Name

					if name == "Part" then
						if rain and part:FindFirstChild("TouchInterest") then
							part.CanCollide = false
							part.CFrame = hrp.CFrame
						end

					elseif name == "RingChase" then
						local ring = part:FindFirstChild("ARingadingding")
						if ring then
							TweenTo(ring.CFrame + Vector3.new(0, 1.3, 0))
						end

					elseif name == "GoldRoller" or name == "Roller" then
						local ball = part:FindFirstChild("Ball")
						local goal = part:FindFirstChild("Goal")

						if ball and goal then
							strengthen(99)
							if sethiddenproperty then
								sethiddenproperty(LP, "SimulationRadius", 1000)
								sethiddenproperty(LP, "MaxSimulationRadius", 1000)
							end
							local dist = (ball.Position - goal.Position).Magnitude
							-- ball.CanCollide = false

							if dist > 20 then
								TweenToWait(ball.CFrame)
								local args = {
									"Tool",
									"PushMowerSilver"
								}
								workspace:WaitForChild("Heck Yeah"):WaitForChild("WhenIDanceYouEquip"):FireServer(unpack(args))
								task.wait()
								ball.CFrame = goal.CFrame
							end
							for i = 1, 5 do
								ball.CFrame = goal.CFrame
								task.wait(0.1)
							end
						end
					end

				end
			end)

			if not success then
				print(error)
			end
		end
	end
})

MainLawnMinigame:AddToggle({
	Name = "Codes On The Go Farm",
	Flag = "codesonthego??",
	Callback = function(state)
		_G.Codes = state
		while _G.Codes == true and task.wait(1) do
			pcall(function()
				game:GetService("Workspace").Singularity.MrCodes.HumanoidRootPart.CFrame = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
			end)
		end
	end
})


workspace.DescendantAdded:Connect(function(descendant)
	if removeToolGrips == true then
		if descendant.Name == "ToolGrip" then
			task.wait(1)
			game:GetService("Debris"):AddItem(descendant, 0)
		end
	end
end)



local toolConn
LP.CharacterAdded:Connect(function(char)
	lastRelativeCFs = {}
	lastFireTimes = {}
	if toolConn then
		toolConn:Disconnect()
		toolConn = nil
	end

    --[[if torsoConnection then
        torsoConnection:Disconnect()
        torsoConnection = nil
    end]]
	task.spawn(function()
		if autoTween then
			local rootPart = char:WaitForChild("HumanoidRootPart", 10)
			if rootPart then
				task.wait(0.1)
				TweenTo(positions[tweenchosen])
			end
		end
	end)
	if _G.MasslessTools == true then
		toolConn = char.ChildAdded:Connect(function(v)
			if v:IsA("Tool") then
				setMassless(v)
			end
		end)
	end
    --[[if removeToolGrips then
        local torso = char:FindFirstChild("Torso") or char:WaitForChild("Torso", 10)
		task.wait(0.1)
        if torso then
            for i, child in ipairs(torso:GetChildren()) do
                if child.Name == "ToolGrip" then
                    child:Destroy()
                end
            end
            torsoConnection = torso.ChildAdded:Connect(function(child)
                if child.Name == "ToolGrip" then
                    child:Destroy()
                end
            end)
        end
    end]]
end)
