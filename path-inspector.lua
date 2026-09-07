local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

local Window = Fluent:CreateWindow({
    Title = "3D Object Path Inspector",
    SubTitle = "by Barron",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Nearby List", Icon = "list" }),
    Picker = Window:AddTab({ Title = "Click Picker", Icon = "mouse-pointer" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local overlayContainer = nil
pcall(function()
    overlayContainer = game:GetService("CoreGui")
end)
if not overlayContainer then
    pcall(function()
        overlayContainer = LocalPlayer:WaitForChild("PlayerGui")
    end)
end
if not overlayContainer then
    overlayContainer = workspace
end

local currentSelectionBox = Instance.new("SelectionBox")
currentSelectionBox.Color3 = Color3.fromRGB(0, 255, 200)
currentSelectionBox.LineThickness = 0.05
pcall(function()
    currentSelectionBox.Parent = overlayContainer
end)

local currentHighlight = Instance.new("Highlight")
currentHighlight.FillColor = Color3.fromRGB(0, 255, 200)
currentHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
currentHighlight.FillTransparency = 0.5
currentHighlight.OutlineTransparency = 0.0
currentHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
pcall(function()
    currentHighlight.Parent = overlayContainer
end)

local function getCleanPath(inst)
    if not inst then return "nil" end
    if inst == game then return "game" end
    if inst == workspace then return "workspace" end
    
    local parts = {}
    local curr = inst
    while curr and curr ~= game do
        local name = curr.Name
        if curr == workspace then
            table.insert(parts, 1, "workspace")
            break
        elseif name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
            table.insert(parts, 1, "." .. name)
        else
            table.insert(parts, 1, "[\"" .. name:gsub("\"", "\\\"") .. "\"]")
        end
        curr = curr.Parent
    end
    
    local pathStr = table.concat(parts, "")
    if pathStr:sub(1, 1) == "." then
        pathStr = "game" .. pathStr
    end
    return pathStr
end

local scanRadius = 35
local lastScanAIReport = ""

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Scan Status",
    Content = "Status: Ready\nObjects Found: 0"
})

local NearbyListParagraph = Tabs.Main:AddParagraph({
    Title = "Nearby 3D Objects",
    Content = "Click 'Scan Nearby' to find objects around you."
})

local function doScan()
    local char = LocalPlayer.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head") or char.PrimaryPart)
    if not hrp then
        StatusParagraph:SetDesc("Status: Error (Character not found)\nObjects Found: 0")
        return
    end
    
    local found = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if not obj:IsDescendantOf(char) then
            local pos = nil
            if obj:IsA("BasePart") then
                pos = obj.Position
            elseif obj:IsA("Model") then
                pos = obj:GetPivot().Position
            elseif obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") then
                if obj.Parent and obj.Parent:IsA("BasePart") then
                    pos = obj.Parent.Position
                end
            end
            
            if pos then
                local dist = (pos - hrp.Position).Magnitude
                if dist <= scanRadius then
                    table.insert(found, {
                        obj = obj,
                        dist = math.round(dist),
                        path = getCleanPath(obj),
                        name = obj.Name,
                        className = obj.ClassName
                    })
                end
            end
        end
    end
    
    table.sort(found, function(a, b) return a.dist < b.dist end)
    
    local displayTxt = ""
    local aiDumpTxt = string.format("-- Nearby Objects Dump within %d studs (Player: %s, Total: %d)\n\n", scanRadius, LocalPlayer.Name, #found)
    
    for i = 1, math.min(#found, 20) do
        local item = found[i]
        displayTxt = displayTxt .. string.format("[%d] %s [%s] (%d studs)\n    %s\n\n", i, item.name, item.className, item.dist, item.path)
    end
    
    for i = 1, math.min(#found, 40) do
        local item = found[i]
        aiDumpTxt = aiDumpTxt .. string.format("[%d] %s [%s] - %d studs\nPath: %s\n", i, item.name, item.className, item.dist, item.path)
        local attrs = item.obj:GetAttributes()
        if next(attrs) ~= nil then
            aiDumpTxt = aiDumpTxt .. "Attributes: "
            for k, v in pairs(attrs) do
                aiDumpTxt = aiDumpTxt .. string.format("%s=%s ", k, tostring(v))
            end
            aiDumpTxt = aiDumpTxt .. "\n"
        end
        aiDumpTxt = aiDumpTxt .. "\n"
    end
    
    lastScanAIReport = aiDumpTxt
    if displayTxt == "" then displayTxt = "No objects found in this radius." end
    NearbyListParagraph:SetDesc(displayTxt)
    StatusParagraph:SetDesc(string.format("Status: Success\nObjects Found: %d (Radius: %d studs)", #found, scanRadius))
end

Tabs.Main:AddSlider("RadiusSlider", {
    Title = "Scan Radius (Studs)",
    Default = 35,
    Min = 5,
    Max = 150,
    Rounding = 0,
    Callback = function(Value)
        scanRadius = Value
    end
})

Tabs.Main:AddButton({
    Title = "🔄 Scan Nearby Objects",
    Description = "Scans 3D models, parts, and prompts around your character",
    Callback = function()
        task.spawn(doScan)
    end
})

Tabs.Main:AddButton({
    Title = "📋 Copy Full List for AI",
    Description = "Copies full list with clean paths and attributes to clipboard",
    Callback = function()
        if lastScanAIReport == "" then
            doScan()
        end
        if setclipboard then
            setclipboard(lastScanAIReport)
            Fluent:Notify({ Title = "Copied!", Content = "Full list copied to clipboard!", Duration = 3 })
        else
            print(lastScanAIReport)
            Fluent:Notify({ Title = "Printed", Content = "Printed to F9 console!", Duration = 3 })
        end
    end
})

local isPickingEnabled = false
local pickedInstance = nil

local TargetInfoParagraph = Tabs.Picker:AddParagraph({
    Title = "Selected Object Info",
    Content = "Click any object in the game world to inspect."
})

local function selectTarget(target)
    if not target then return end
    pickedInstance = target
    
    if target:IsA("BasePart") then
        currentSelectionBox.Adornee = target
        currentHighlight.Adornee = (target.Parent:IsA("Model") and target.Parent ~= workspace) and target.Parent or target
    else
        currentSelectionBox.Adornee = nil
        currentHighlight.Adornee = target
    end
    
    local path = getCleanPath(target)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local dist = 0
    if hrp and target:IsA("BasePart") then
        dist = math.round((hrp.Position - target.Position).Magnitude)
    end
    
    local info = string.format("Name: %s\nClass: %s\nDistance: %d studs\n\nPath:\n%s", target.Name, target.ClassName, dist, path)
    TargetInfoParagraph:SetDesc(info)
end

Tabs.Picker:AddToggle("PickToggle", {
    Title = "Enable Click to Pick Object",
    Default = false,
    Callback = function(Value)
        isPickingEnabled = Value
        if not Value then
            currentSelectionBox.Adornee = nil
            currentHighlight.Adornee = nil
        else
            Fluent:Notify({ Title = "Picker Active", Content = "Left-click on any 3D object in game!", Duration = 3 })
        end
    end
})

Tabs.Picker:AddButton({
    Title = "📋 Copy Selected Object Path",
    Callback = function()
        if pickedInstance then
            local path = getCleanPath(pickedInstance)
            if setclipboard then
                setclipboard(path)
                Fluent:Notify({ Title = "Copied!", Content = path, Duration = 3 })
            else
                print("Path: " .. path)
            end
        else
            Fluent:Notify({ Title = "Notice", Content = "Please click an object first!", Duration = 3 })
        end
    end
})

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not isPickingEnabled or gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local mouse = LocalPlayer:GetMouse()
        local target = mouse.Target
        if target and not (LocalPlayer.Character and target:IsDescendantOf(LocalPlayer.Character)) then
            selectTarget(target)
        end
    end
end)

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentPathInspector")
SaveManager:SetFolder("FluentPathInspector/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

task.defer(function()
    task.wait(0.5)
    doScan()
end)

Fluent:Notify({
    Title = "Path Inspector",
    Content = "Loaded successfully!",
    Duration = 4
})
