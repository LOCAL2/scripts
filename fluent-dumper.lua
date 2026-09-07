local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Game Dumper Hub",
    SubTitle = "by Barron",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true, 
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Dumper", Icon = "download" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local dumpFolderName = "MyGameDump"
local isDumping = false
local includeProperties = false
local includeScripts = true
local skipRobloxInternals = true
local exportFormat = "Single File (.txt)"

local function sanitizePath(name)
    return string.gsub(name, "[^%w%-%_%.%s/\\]", "_")
end

local mapName = game.Name
if not mapName or mapName == "" then mapName = "UnknownMap" end

local function getMapName()
    return sanitizePath(mapName)
end

local PathParagraph = Tabs.Main:AddParagraph({
    Title = "Save Location",
    Content = "Path: [Executor Folder]/workspace/" .. sanitizePath(dumpFolderName) .. "/" .. getMapName() .. "/"
})

task.spawn(function()
    local mps = game:GetService("MarketplaceService")
    local s, info = pcall(function() return mps:GetProductInfo(game.PlaceId) end)
    if s and info and info.Name then
        mapName = info.Name
        PathParagraph:SetDesc("Path: [Executor Folder]/workspace/" .. sanitizePath(dumpFolderName) .. "/" .. getMapName() .. "/")
    end
end)

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Dump Status",
    Content = "Status: Idle\nProgress: 0%"
})

Tabs.Main:AddInput("FolderNameInput", {
    Title = "Dump Folder Name",
    Default = "MyGameDump",
    Placeholder = "Enter folder name...",
    Numeric = false,
    Finished = false,
    Callback = function(Value)
        dumpFolderName = Value
        PathParagraph:SetDesc("Path: [Executor Folder]/workspace/" .. sanitizePath(dumpFolderName) .. "/" .. getMapName() .. "/")
    end
})

Tabs.Main:AddToggle("IncludePropertiesToggle", {
    Title = "Dump Part Properties",
    Description = "Turn OFF to skip saving Size and Position of map parts. Makes dumping much faster and the file smaller!",
    Default = false,
    Callback = function(Value)
        includeProperties = Value
    end
})

Tabs.Main:AddToggle("IncludeScriptsToggle", {
    Title = "Decompile Scripts",
    Description = "Turn OFF to skip extracting source code. Use this if you want the dump to finish instantly!",
    Default = true,
    Callback = function(Value)
        includeScripts = Value
    end
})

Tabs.Main:AddToggle("SkipRobloxInternalsToggle", {
    Title = "Skip Roblox Internals",
    Description = "Skip internal Roblox scripts/services like CoreGui, CorePackages, RobloxReplicatedStorage.",
    Default = true,
    Callback = function(Value)
        skipRobloxInternals = Value
    end
})

Tabs.Main:AddParagraph({
    Title = "⚠️ คำชี้แจงเรื่องความเร็ว (Disclaimer)",
    Content = "ความเร็วในการแกะสคริปต์ (Decompile) ขึ้นอยู่กับประสิทธิภาพของตัวรัน (Executor) ที่คุณใช้งานเป็นหลัก อาการล่าช้าเกิดจากการที่ตัวรันพยายามแปลภาษาโค้ดที่ถูกเข้ารหัสป้องกันมาอย่างหนัก สคริปต์ตัวนี้ถูกปรับแต่งให้รันด้วยความเร็วสูงสุดแล้ว หากรู้สึกว่าการดึงข้อมูลยังล่าช้าเกินไป กรุณากดปิดสวิตช์ 'Decompile Scripts'"
})

local function getScriptSource(obj)
    local resultSource = nil
    local completed = false

    task.spawn(function()
        if decompile then
            local success, source = pcall(decompile, obj)
            if success and type(source) == "string" and source ~= "" then
                resultSource = source
                completed = true
                return
            end
        end

        local success, source = pcall(function() return obj.Source end)
        if success and type(source) == "string" and source ~= "" then
            resultSource = source
            completed = true
            return
        end

        resultSource = "-- Failed to decompile or source is restricted"
        completed = true
    end)

    local start = os.clock()
    while not completed do
        if os.clock() - start > 3 then -- 3 seconds timeout per script
            return "-- [TIMEOUT] Decompile took too long (Skipped to prevent freeze)"
        end
        task.wait(0.05)
    end

    return resultSource
end

local function dumpGame()
    if isDumping then return end
    isDumping = true
    
    local baseFolder = sanitizePath(dumpFolderName)
    local mapFolder = baseFolder .. "/" .. getMapName()
    local folderPath = mapFolder
    
    pcall(function()
        if not isfolder(baseFolder) then
            makefolder(baseFolder)
        end
        if not isfolder(mapFolder) then
            makefolder(mapFolder)
        end
    end)
    
    local mainLuaFile = folderPath .. "/game_structure.lua"
    
    Fluent:Notify({
        Title = "Dumping Started",
        Content = "Please wait... saving to " .. folderPath,
        Duration = 10
    })

    local header = "--[[=========================================================\n" ..
                   "  Game Dump Output\n" ..
                   "=========================================================\n" ..
                   "  Game Name: " .. tostring(mapName) .. "\n" ..
                   "  PlaceId: " .. tostring(game.PlaceId) .. "\n" ..
                   "  JobId: " .. tostring(game.JobId) .. "\n" ..
                   "=========================================================]]\n\n"
                   
    local wSuccess, wErr = pcall(function()
        writefile(mainLuaFile, header)
    end)
    
    if not wSuccess then
        Fluent:Notify({Title = "Error", Content = "Cannot write file: " .. tostring(wErr), Duration = 5})
        isDumping = false
        return
    end

    local buffer = {}
    local lineCount = 0
    
    local servicesToDump = {
        game:GetService("Workspace"),
        game:GetService("Players"),
        game:GetService("ReplicatedStorage"),
        game:GetService("ReplicatedFirst"),
        game:GetService("StarterGui"),
        game:GetService("StarterPack"),
        game:GetService("StarterPlayer"),
        game:GetService("Lighting"),
        game:GetService("TextChatService")
    }

    -- Roblox internal filtering logic
    local function isRobloxInternal(instance)
        local fullName = ""
        pcall(function() fullName = instance:GetFullName() end)
        if string.find(fullName, "RobloxReplicatedStorage") 
           or string.find(fullName, "CoreGui")
           or string.find(fullName, "CorePackages") then
            return true
        end
        return false
    end

    StatusParagraph:SetDesc("Status: Counting total objects...\nProgress: 0%")
    local totalObjects = 0
    local cStart = os.clock()
    local cTick = tick()
    local function countRecursive(inst, depth)
        if depth > 15 or not isDumping then return end
        if skipRobloxInternals and isRobloxInternal(inst) then return end

        local s, children = pcall(function() return inst:GetChildren() end)
        if s and children then
            totalObjects = totalObjects + #children
            if os.clock() - cStart > 0.015 then
                task.wait()
                cStart = os.clock()
                if tick() - cTick > 0.5 then
                    StatusParagraph:SetDesc("Status: Counting... (" .. totalObjects .. " objects found)\nProgress: 0%")
                    cTick = tick()
                end
            end
            for _, c in ipairs(children) do
                countRecursive(c, depth + 1)
            end
        end
    end
    for _, s in ipairs(servicesToDump) do
        if s then
            totalObjects = totalObjects + 1
            countRecursive(s, 0)
        end
    end
    if not isDumping then return end 
    
    if not isDumping then return end
    
    local processedObjects = 0
    local startTime = os.clock()
    local lastUpdateTick = tick()
    local scriptIndexList = {}

    local function dumpInstance(instance, depth)
        if not isDumping then return end
        if depth > 15 then return end
        if skipRobloxInternals and isRobloxInternal(instance) then return end
        
        processedObjects = processedObjects + 1
        if os.clock() - startTime > 0.015 then
            task.wait()
            startTime = os.clock()
            if tick() - lastUpdateTick > 0.5 then
                if processedObjects > totalObjects then
                    totalObjects = processedObjects + 5000
                end
                local percent = totalObjects > 0 and math.floor((processedObjects / totalObjects) * 100) or 0
                StatusParagraph:SetDesc("Status: Dumping (" .. processedObjects .. " / " .. totalObjects .. ")\nProgress: " .. percent .. "%")
                lastUpdateTick = tick()
            end
        end
        
        local sName, iName = pcall(function() return instance.Name end)
        local sClass, iClass = pcall(function() return instance.ClassName end)
        iName = sName and iName or "Unknown"
        iClass = sClass and iClass or "Unknown"

        local indent = string.rep("  ", depth)
        
        table.insert(buffer, indent .. "├── " .. iName .. " [" .. iClass .. "]")
        lineCount = lineCount + 1
            
            -- Attributes
            local sAttr, attributes = pcall(function() return instance:GetAttributes() end)
            if sAttr and attributes then
                for k, v in pairs(attributes) do
                    table.insert(buffer, indent .. "│   @ Attribute: " .. tostring(k) .. " = " .. tostring(v) .. " [" .. typeof(v) .. "]")
                    lineCount = lineCount + 1
                end
            end
            
            -- Properties
            if includeProperties then
                if instance:IsA("BasePart") then
                    table.insert(buffer, indent .. "│   > Property: Position = " .. tostring(instance.Position)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: Size = " .. tostring(instance.Size)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: Transparency = " .. tostring(instance.Transparency)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: Color = " .. tostring(instance.Color)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: Anchored = " .. tostring(instance.Anchored)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: CanCollide = " .. tostring(instance.CanCollide)); lineCount = lineCount + 1
                elseif instance:IsA("Humanoid") then
                    table.insert(buffer, indent .. "│   > Property: Health = " .. tostring(instance.Health)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: MaxHealth = " .. tostring(instance.MaxHealth)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: WalkSpeed = " .. tostring(instance.WalkSpeed)); lineCount = lineCount + 1
                    table.insert(buffer, indent .. "│   > Property: JumpPower = " .. tostring(instance.JumpPower)); lineCount = lineCount + 1
                end
            end
        
        -- Scripts
        if instance:IsA("LuaSourceContainer") then
            local fullName = "UnknownPath"
            pcall(function() fullName = instance:GetFullName() end)
            if type(scriptIndexList) == "table" then
                table.insert(scriptIndexList, "[" .. tostring(iClass) .. "] " .. tostring(fullName))
            end

            if includeScripts then
                local scriptName = sName and iName or "UnknownScript"

                pcall(function()
                    StatusParagraph:SetDesc("Status: Dumping (" .. processedObjects .. " / " .. totalObjects .. ")\n[SLOW] Decompiling: " .. scriptName)
                    appendfile(folderPath .. "/decompile_log.txt", "Attempting: " .. fullName .. "\n")
                end)
                
                task.wait()
                
                local src = getScriptSource(instance)
                
                pcall(function() appendfile(folderPath .. "/decompile_log.txt", "Finished: " .. fullName .. "\n") end)
                
                if src and src ~= "" and not string.match(src, "Failed to decompile") then
                    -- Reconstruct folder hierarchy for separate .lua files
                    local cleanParts = {}
                    for part in string.gmatch(fullName, "[^%.]+") do
                        table.insert(cleanParts, sanitizePath(part))
                    end
                    
                    if #cleanParts > 0 then
                        local rawFileName = table.remove(cleanParts, #cleanParts)
                        local fileName = tostring(rawFileName) .. "." .. tostring(instance.ClassName) .. ".lua"
                        
                        local currentPath = folderPath .. "/Scripts"
                        pcall(function()
                            if not isfolder(currentPath) then
                                makefolder(currentPath)
                            end
                            for _, folder in ipairs(cleanParts) do
                                currentPath = currentPath .. "/" .. tostring(folder)
                                if not isfolder(currentPath) then
                                    makefolder(currentPath)
                                end
                            end
                            writefile(currentPath .. "/" .. fileName, src)
                        end)
                    end
                end
            end
        end
        
        local sChild, children = pcall(function() return instance:GetChildren() end)
        if sChild and children then
            for _, child in ipairs(children) do
                dumpInstance(child, depth + 1)
            end
        end
    end

    for _, service in ipairs(servicesToDump) do
        if service then
            dumpInstance(service, 0)
        end
    end

    -- Loaded Modules (getloadedmodules executor function)
    if getloadedmodules then
        table.insert(buffer, "\n--[[=========================================================")
        table.insert(buffer, "  Loaded Modules (getloadedmodules)")
        table.insert(buffer, "=========================================================]]\n")
        local successLM, loadedModules = pcall(getloadedmodules)
        if successLM and type(loadedModules) == "table" then
            for idx, mod in ipairs(loadedModules) do
                local modPath = "Unknown"
                pcall(function() modPath = mod:GetFullName() end)
                if not (skipRobloxInternals and isRobloxInternal(mod)) then
                    table.insert(buffer, "-- [" .. idx .. "] " .. modPath)
                end
            end
        else
            table.insert(buffer, "-- Unable to fetch loaded modules via getloadedmodules()")
        end
    end

    -- Script Index Summary Section
    table.insert(buffer, "\n--[[=========================================================")
    table.insert(buffer, "  Script Index Summary (" .. #scriptIndexList .. " total)")
    table.insert(buffer, "=========================================================]]\n")
    for _, scriptInfo in ipairs(scriptIndexList) do
        table.insert(buffer, "-- " .. scriptInfo)
    end

    
    if isDumping then
        pcall(function() appendfile(mainLuaFile, table.concat(buffer, "\n") .. "\n") end)
        isDumping = false
        StatusParagraph:SetDesc("Status: Complete!\nProgress: 100%")
        Fluent:Notify({
            Title = "Dump Success",
            Content = "Game has been successfully dumped into " .. folderPath,
            Duration = 8
        })
    else
        StatusParagraph:SetDesc("Status: Cancelled\nProgress: 0%")
        Fluent:Notify({
            Title = "Dumping Cancelled",
            Content = "The dump was stopped by user.",
            Duration = 5
        })
    end
end

Tabs.Main:AddButton({
    Title = "Start Dump",
    Description = "Dumps the entire game into a single file.",
    Callback = function()
        if not isDumping then
            task.spawn(dumpGame)
        end
    end
})

Tabs.Main:AddButton({
    Title = "Cancel Dump",
    Description = "Stops the dump process if it's currently running.",
    Callback = function()
        if isDumping then
            isDumping = false
        end
    end
})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentDumperHub")
SaveManager:SetFolder("FluentDumperHub/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
Window:SelectTab(1)
Fluent:Notify({
    Title = "Fluent Dumper",
    Content = "The script has been loaded.",
    Duration = 8
})
