local plr = game.Players.LocalPlayer

local function magnitude(p1, p2)
    local dx = p2.X - p1.X
    local dy = p2.Y - p1.Y
    local dz = p2.Z - p1.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local fruitBoxes = {}

while true do
    task.wait(0.005)

    local character = plr.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        for _, data in pairs(fruitBoxes) do
            data.box.Visible = false
            data.text.Visible = false
        end
        continue
    end

    local currentFruits = {}
    for _, v in ipairs(workspace:GetChildren()) do
        if v:IsA("Tool") then
            local preHandle = v:FindFirstChild("preHandle", true)
            if preHandle and preHandle:IsA("BasePart") then
                currentFruits[v] = preHandle
            end
        end
    end

    for fruit, data in pairs(fruitBoxes) do
        if not currentFruits[fruit] then
            data.box:Remove()
            data.text:Remove()
            fruitBoxes[fruit] = nil
        end
    end

    for fruit, preHandle in pairs(currentFruits) do
        if not fruitBoxes[fruit] then
            local box = Drawing.new("Square")
            box.Filled = false
            box.Color = Color3.fromRGB(255, 255, 255)
            box.Thickness = 1
            box.Visible = true

            local txt = Drawing.new("Text")
            txt.Text = ""
            txt.Color = Color3.fromRGB(255, 255, 255)
            txt.Size = 12
            txt.Center = true
            txt.Outline = true
            txt.Visible = true

            fruitBoxes[fruit] = {box = box, text = txt}
        end

        local data = fruitBoxes[fruit]
        local box, txt = data.box, data.text

        local screenPos, onScreen = WorldToScreen(preHandle.Position)
        if onScreen then
            box.Position = Vector2.new(screenPos.X - 25, screenPos.Y - 25)
            box.Size = Vector2.new(50, 50)
            box.Visible = true

            local dist = magnitude(preHandle.Position, hrp.Position)
            txt.Text = fruit.Name .. " | " .. string.format("%.1f Studs", dist)
            txt.Position = Vector2.new(screenPos.X, screenPos.Y - 35)
            txt.Visible = true
        else
            box.Visible = false
            txt.Visible = false
        end
    end
end
