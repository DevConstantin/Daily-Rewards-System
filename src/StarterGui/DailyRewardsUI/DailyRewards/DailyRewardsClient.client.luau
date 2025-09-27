
--- // SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- // OBJECTS
local rewardsDb = require(ReplicatedStorage.DB.DailyRewardsDB)

-- Daily rewards UI
local rewardsGUI = script.Parent
local rewardFrame = rewardsGUI.Main.RewardFrame
local rewardButtonTemplate = script.Parent.RewardButton
local templateImages = rewardButtonTemplate.Images

-- Main menu elements, to ensure the daily rewards UI doesn't open while we're in the main menu
local mainMenu = script.Parent.Parent.Parent:FindFirstChild("MainMenu")
local mainMenuFrame = mainMenu and mainMenu:FindFirstChild("MainMenuFrame")
local mainMenuButtons = mainMenuFrame and mainMenuFrame:FindFirstChild("ButtonsFrame")
local enterGame = mainMenuButtons and mainMenuButtons:FindFirstChild("EnterGame")

-- Events
local rewardEvents = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("DailyRewardEvents")
local rewardEvent  = rewardEvents:WaitForChild("DailyRewardEvent")
local requestData  = rewardEvents:WaitForChild("RequestRewardData")

-- Sounds 
local uiSounds = game:GetService("SoundService"):WaitForChild("UI_Sounds")
local clickSound = uiSounds:WaitForChild("RBLX UI Hover 02 (SFX)")
local enter_DC_Sound = uiSounds:WaitForChild("RBLX UI Hover 03 (SFX)")
local confirmSound = uiSounds:WaitForChild("RBLX UI Back (SFX)")
local rewardClaimedSound = uiSounds:WaitForChild("Audio/凹凸世界-v_ui_comm_active")

--- // CONFIG
local imageIds = ReplicatedStorage:WaitForChild("Configurations"):WaitForChild("ImageIds")
local galleonsImageId = imageIds:GetAttribute("Galleons")
local chestsImageId   = imageIds:GetAttribute("EnchantedChests")
local UPDATE_ZINDEX   = false
local IMAGE_COLOR     = Color3.fromRGB(255, 186, 47)

--- // VARIABLES
local currentStreak = nil
local currentSeason = nil
local rewardAvailable = nil
local nextRewardReset = math.floor(21.3 * 60 * 60)

-- // Typical reward DB setup: 
--local dailyRewards = {
--	[1] = { galleons = 50  },
--	[2] = { galleons = 100 },
--	[3] = { galleons = 100, chests = 1 },
--	[4] = { galleons = 150, chests = 2 },
--	[5] = { galleons = 200, chests = 3 },
--}

--- // FUNCTIONS

-- Function to convert seconds to minutes or hours 
-- @param noSeconds: Will not show seconds while hours are present, to shorten the string
local function formatTime(seconds, noSeconds : boolean)
	local parts = {}

	-- Calculate hours
	local hours = math.floor(seconds / 3600)
	if hours > 0 then
		table.insert(parts,
			hours .. (hours == 1 and " hour" or " hours")
		)
	end

	-- Calculate remaining minutes
	local minutes = math.floor((seconds % 3600) / 60)
	if minutes > 0 then
		table.insert(parts,
			minutes .. (minutes == 1 and " minute" or " minutes")
		)
	end

	if noSeconds and hours > 0 then return table.concat(parts, ", ") end

	-- Calculate remaining seconds
	local secs = seconds % 60
	if secs > 0 or #parts == 0 then
		-- always show seconds if nothing else was added
		table.insert(parts,
			secs .. (secs == 1 and " second" or " seconds")
		)
	end

	-- Join parts with commas
	return table.concat(parts, ", ")
end

function formatDailyRewardTitleText(rewardData)
	local parts = {}

	if rewardData.galleons then
		table.insert(parts, rewardData.galleons .. " galleons")
	end

	if rewardData.chests then
		local chestText = rewardData.chests == 1 and "chest" or "chests"
		table.insert(parts, rewardData.chests .. " " .. chestText)
	end

	return table.concat(parts, " + ")
end

-- Can be set up later so certain buttons are pre-created. For instance, if we are rewarding a pet on day 7
local function isValidSetupDay(rewardDay)
	return true -- rewardDay < 7
end

local function setupButtonImages(rewardButton, rewards)
	local images = rewardButton:FindFirstChild("Images")
	if not images then 
		warn("Failed to get images folder within reward button.") 
		return 
	end 
	
	local chestsCount = rewards.chests 
	
	if chestsCount then 
		for i = 1, chestsCount do 
			local imageLabel = images:FindFirstChild(i)
			if not imageLabel then 
				warn("Failed to get image level for index", i, "within", images:GetFullName())
				imageLabel.Visible = false 
				continue 
			end 
				
			imageLabel.Image = chestsImageId
			imageLabel.Visible = true 
		end
	end
	
	if chestsCount == 3 then return end -- No coins need to be shown 
		
	local galleonRewards = math.min(math.floor(rewards.galleons / 50), 3) -- How many galleons images should the player see in total? (1-3)
	-- If we have two enchanted chests being shown, we'll begin at 3 
	for i = (chestsCount or 0) + 1, galleonRewards do 
		local imageLabel = images:FindFirstChild(i)
		if not imageLabel then 
			warn("Failed to get image level for index", i, "within", images:GetFullName()) 
			continue 
		end 
		imageLabel.Image = galleonsImageId
		imageLabel.Visible = true 
	end
end

-- Run the countdown 
local function showNextRewardTime(claimTextLabel)
	task.spawn(function()
		for i = nextRewardReset, 0, -1 do 
			--if not dailyRewardsUi.Enabled then break end 
			claimTextLabel.Text = formatTime(i, true)

			if i <= 0 then
				rewardsGUI.Enabled = false 
				break 
			end

			task.wait(1)
		end
	end)	
end

-- Initialize the UI, buttons, etc.
local function initialize()
	if not rewardAvailable then 
		print("DailyRewardsUI: A reward is not currently available. Daily rewards UI closed.") 
		rewardsGUI.Enabled = false 
		return 
	end 
	
	for _, button in ipairs(rewardFrame:GetChildren()) do 
		if button:IsA("TextButton") then 
			button:Destroy() 
		end 
	end
	
	local countdownDay = nil 	-- Keep strack of the day on which we'll have a countdown 
	print("SETTING UP BUTTONS FOR REWARDS:", rewardsDb, "Current reward streak:", currentStreak, "Is a reward available?", rewardAvailable)
	for rewardDay = 1, #rewardsDb do 
		local rewards = rewardsDb[rewardDay]
		print(" ")
		print("Setting up reward button for day", rewardDay)
		print("Day", rewardDay, "reward data:", rewards)
		
		local rewardButton = rewardButtonTemplate:Clone() 		
		rewardButton.DayTitle.Text = formatDailyRewardTitleText(rewards) --"Day " .. rewardDay
		
		local claimText = nil
		if not currentStreak then -- Do not display a claim text if the currentStreak is missing
			claimText = "Day " .. rewardDay
		elseif rewardDay == countdownDay then 
			showNextRewardTime(rewardButton.ClaimText) 
			claimText = ""
		elseif (rewardDay == #rewardsDb and currentStreak >= rewardDay) or (rewardDay == currentStreak + 1) then -- Reward day index is 3, and our streak is 2, so we can pick up the reward for this day
			if rewardAvailable then 
				claimText = "Claim"
				countdownDay = rewardDay + 1
				print("Setting countdown day to day", countdownDay)
			else 
				showNextRewardTime(rewardButton.ClaimText) 
				claimText = ""
			end
		elseif rewardDay <= currentStreak then 
			claimText = "Claimed"
		else 
			claimText = "Day " .. rewardDay
		end 
		
		print("Countdown day:", countdownDay)
		rewardButton.ClaimText.Text = claimText
		rewardButton.Checkmark.Visible = claimText == "Claimed" -- currentStreak check isn't necessary, but it's here for testing purposes 
		setupButtonImages(rewardButton, rewards)
		rewardButton.Visible = true 

		rewardButton.MouseButton1Click:Connect(function()
			if not rewardAvailable then 
				warn("You cannot request a reward for day", rewardDay, "A reward is not currently available.") 
				return 
			end
			
			if rewardDay == currentStreak + 1 then -- If our streak is 0, we are rewarded with day '1' reward
				rewardClaimedSound:Play() 
				rewardEvent:FireServer()
			else 
				warn("You cannot request a reward for day", rewardDay, "Current streak:", currentStreak)
			end 
		end)

		rewardButton.Parent = rewardFrame
	end
	
	if not rewardsGUI.Enabled then 
		rewardsGUI.Enabled = true 
	end 	
end

local function updateUIClientEvent(_currentStreak, _rewardAvailable, _nextRewardReset)
	print("Player data from server:", _currentStreak, "Rewarda available?", _rewardAvailable, _nextRewardReset)
	currentStreak = _currentStreak
	rewardAvailable = _rewardAvailable
	if _nextRewardReset then 
		nextRewardReset = nextRewardReset 
	end
	initialize()
end

--- // MAIN

if IMAGE_COLOR then   
    for _, imageLabel in ipairs(templateImages:GetChildren()) do  
        imageLabel.ImageColor3 = IMAGE_COLOR
    end
end

if UPDATE_ZINDEX then
	templateImages["1"].ZIndex = 3 
	templateImages["2"].ZIndex = 2 
	templateImages["3"].ZIndex = 1 
end 

if mainMenu then 
	-- Ensure the daily rewards don't pop up while the main menu is enabled 
	repeat 
		task.wait(5) 
	until enterGame.Text == "Continue"
end

rewardEvent.OnClientEvent:Connect(updateUIClientEvent)
requestData.OnClientEvent:Connect(updateUIClientEvent)

script.Parent.Main.CloseButton.MouseButton1Click:Connect(function()
	confirmSound:Play()
	rewardsGUI.Enabled = false
end)

rewardsGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
	--if dailyRewardsUi.Enabled then initialize() end
end)

-- Request daily reward data from the server. The server will send the data back and the UI will be initialized (requestData.OnClientEvent) 
for i = 0, 5 do
	if currentStreak ~= nil then break end
	requestData:FireServer()
	task.wait(1)
	
	if i == 5 then 
		warn("Failed to get daily reward data.") 
	end
end

--initialize()
