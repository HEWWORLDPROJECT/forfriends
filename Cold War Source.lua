local EXPECTED_PLACE_ID = 13687899540
local VEHICLE_SPIN_DEGREES = 3600
if game.PlaceId ~= EXPECTED_PLACE_ID then
    warn(string.format("[ballistics probe] wrong place: expected %d, got %d", EXPECTED_PLACE_ID, game.PlaceId))
    return
end
local env = (getgenv and getgenv()) or _G
if type(env.__P13687899540_BALLISTICS_PROBE) == "table" then
    local previous = env.__P13687899540_BALLISTICS_PROBE
    if type(previous.Unload) == "function" then
        pcall(previous.Unload, previous, "reloaded")
    end
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local function table_clear(t)
    if type(table.clear) == "function" then table_clear(t) return end
    for k in pairs(t) do t[k] = nil end
end
local function table_clone(t)
    if type(table.clone) == "function" then return table_clone(t) end
    local n = {}
    for k, v in pairs(t) do n[k] = v end
    return n
end
local function table_find(t, value)
    if type(table.find) == "function" then return table_find(t, value) end
    for i, v in ipairs(t) do if v == value then return i end end
    return nil
end
local State = {
    active = true,
    panelVisible = true,
    activeTab = "combat",
    profile = "rage",
    rageSettings = nil,
    legitLockTarget = nil,
    legitLockSince = 0,
    legitDwell = 0.12,
    legitMaxAngle = 4,
    silentAim = false,
    esp = true,
    espStyle = "Box",
    autoDefense = false,
    defenseTarget = nil,
    defenseThreatScore = 0,
    defenseThreshold = 90,
    nextDefenseScanAt = 0,
    defenseSavedModes = nil,
    defenseSavedAutoRotate = nil,
    tracers = true,
    triggerbot = false,
    visibility = true,
    prediction = true,
    smartTargeting = false,
    angleAudit = false,
    penetrationAudit = false,
    targetPart = "Torso",
    fovRadius = 180,
    aimDistance = 1200,
    espDistance = 900,
    tracerDistance = 650,
    triggerRadius = 180,
    triggerDelay = 0.065,
    nextTriggerAt = 0,
    firing = false,
    currentTarget = nil,
    currentPart = nil,
    redirectedShots = 0,
    triggerPulls = 0,
    penetrationShots = 0,
    penetrationPierces = 0,
    penetrationStops = 0,
    penetrationReached = 0,
    lastPenetrationLogAt = 0,
    vehicleSpeedEnabled = false,
    vehicleTargetSpeed = 110,
    vehicleFly = false,
    vehicleSpin = false,
    vehicleNoclip = false,
    vehicleNoclipVehicle = nil,
    vehicleNoclipOriginal = {},
    autoRoadkill = false,
    roadkillRadius = 60,
    roadkillTarget = nil,
    roadkillHumanoid = nil,
    roadkillPreviousHealth = nil,
    roadkillLastNearAt = 0,
    roadkillKillsObserved = 0,
    vehicleRoot = nil,
    vehicleLastWaitLogAt = 0,
    vehicleTestRoot = nil,
    vehicleTestMode = nil,
    vehicleTestStartPosition = nil,
    vehicleTestLogAt = 0,
    nextVehicleLookupAt = 0,
    cachedVehicle = nil,
    cachedVehicleRoot = nil,
    cachedVehicleSeat = nil,
    cachedVehicleIsDriver = false,
    authoritativeDamageObservations = 0,
    maxAcceptedAngle = 0,
    angleAuditPending = false,
    lastResult = "ready",
    connections = {},
    cleanups = {},
    drawings = {},
    playerDrawings = {},
    hookReady = false,
    localBuildingsHidden = false,
    hiddenBuildingParts = {},
    nextBuildingRefreshAt = 0,
    lastVolleyTool = nil,
    lastMuzzleIndex = 1,
    lastBulletIndex = 1,
    weaponConfigCache = {},
    nextAssessmentAt = 0,
    nextVisualAt = 0,
    nextPanelAt = 0,
    frameMs = 16.7,
    perfVisualMs = 0,
    perfPanelMs = 0,
    perfTriggerMs = 0,
    perfDefenseMs = 0,
    nextVehicleNoclipScanAt = 0,
    nextVehicleNoclipApplyAt = 0,
    shotAssessment = nil,
}
env.__P13687899540_BALLISTICS_PROBE = State
local function log(message)
    State.lastResult = tostring(message)
    print("[ballistics probe] " .. State.lastResult)
end
local function requirePath(root, path, label)
    local node = root
    for _, name in ipairs(path) do
        node = node and node:WaitForChild(name, 12)
    end
    if not node then
        warn("[ballistics probe] missing " .. label)
        return nil
    end
    local ok, result = pcall(require, node)
    if not ok then
        warn(string.format("[ballistics probe] could not require %s: %s", label, tostring(result)))
        return nil
    end
    return result
end
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts", 15)
if not PlayerScripts then
    warn("[ballistics probe] PlayerScripts did not load")
    return
end
local ClientFire = requirePath(PlayerScripts, {"BallisticsClient", "ClientFire"}, "ClientFire")
local WeaponSource = requirePath(ReplicatedStorage, {"Shared", "Ballistics", "Sources", "WeaponSource"}, "WeaponSource")
local WeaponConfigManager = requirePath(ReplicatedStorage, {"Shared", "WeaponConfigManager"}, "WeaponConfigManager")
local DriverController = requirePath(ReplicatedStorage, {"Shared", "Vehicle", "DriverController"}, "DriverController")
local volleyRoute
if type(ClientFire) == "table" then
    for _, candidate in ipairs({"tRa_ASYc_V", "fireVolley"}) do
        if type(ClientFire[candidate]) == "function" then
            volleyRoute = candidate
            break
        end
    end
end
if not volleyRoute then
    warn("[ballistics probe] required native ballistics modules are unavailable")
    return
end
State.volleyRoute = volleyRoute
local Inputs = ReplicatedStorage:WaitForChild("Inputs", 12)
local WeaponContext = Inputs and Inputs:WaitForChild("WeaponContext", 12)
local ShootAction = WeaponContext and WeaponContext:WaitForChild("Shoot", 12)
local ShootPressed
local ShootReleased
if ShootAction then
    pcall(function() ShootPressed = ShootAction.Pressed end)
    pcall(function() ShootReleased = ShootAction.Released end)
end
local function aliveCharacter(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if character and humanoid and humanoid.Health > 0 then
        return character, humanoid
    end
    return nil, nil
end
local function isEnemy(player)
    if player == LocalPlayer then
        return false
    end
    if LocalPlayer.Team ~= nil and player.Team ~= nil and LocalPlayer.Team == player.Team then
        return false
    end
    return aliveCharacter(player) ~= nil
end
local function aimPartOf(player)
    local character = aliveCharacter(player)
    if not character then
        return nil
    end
    if State.targetPart == "Head" then
        return character:FindFirstChild("Head")
    end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Head")
end
local function localOrigin()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root.Position or Camera.CFrame.Position
end
local rawLineOfSight
local function closestEnemy()
    local origin = localOrigin()
    local best, bestDistance
    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) then
            local part = aimPartOf(player)
            if part then
                local distance = (part.Position - origin).Magnitude
                if not bestDistance or distance < bestDistance then
                    bestDistance = distance
                    best = {player = player, part = part, distance = distance}
                end
            end
        end
    end
    return best
end
local function buildingRoots()
    local map = Workspace:FindFirstChild("Map")
    local destructible = map and map:FindFirstChild("Destructible")
    local roots = {}
    local buildings = destructible and destructible:FindFirstChild("Buildings")
    if buildings then table.insert(roots, buildings) end
    return roots
end
local function restoreLocalBuildings()
    local restored = 0
    for part, original in pairs(State.hiddenBuildingParts) do
        if part and part.Parent then
            local ok = pcall(function() part.LocalTransparencyModifier = original end)
            if ok then restored = restored + 1 end
        end
    end
    table_clear(State.hiddenBuildingParts)
    State.localBuildingsHidden = false
    return restored
end
local function refreshHiddenBuildings()
    if not State.localBuildingsHidden then return 0 end
    local roots = buildingRoots()
    if #roots == 0 then return 0 end
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = roots
    params.MaxParts = 12000
    local ok, nearby = pcall(Workspace.GetPartBoundsInRadius, Workspace, localOrigin(), 400, params)
    if not ok then return 0 end
    local changed = 0
    for _, part in ipairs(nearby) do
        local model = part:FindFirstAncestorOfClass("Model")
        if State.hiddenBuildingParts[part] == nil
            and (not model or not model:FindFirstChildOfClass("Humanoid")) then
            local saved, original = pcall(function() return part.LocalTransparencyModifier end)
            if saved then
                State.hiddenBuildingParts[part] = original
                pcall(function() part.LocalTransparencyModifier = 1 end)
                changed = changed + 1
            end
        end
    end
    return changed
end
local function toggleLocalBuildings()
    if State.profile == "legit" and not State.localBuildingsHidden then
        log("Legit profile keeps building visibility and collision checks intact")
        return
    end
    if State.localBuildingsHidden then
        log(string.format("local building visuals restored: %d parts", restoreLocalBuildings()))
        return
    end
    if #buildingRoots() == 0 then
        log("building test: static building folder unavailable")
        return
    end
    local target = closestEnemy()
    local before = target and rawLineOfSight(target.part, localOrigin())
    State.localBuildingsHidden = true
    local changed = refreshHiddenBuildings()
    local after = target and rawLineOfSight(target.part, localOrigin())
    log(string.format("local buildings hidden: %d nearby parts; LOS %s -> %s; projectile ray filter %s. Confirm any damage on the alt",
        changed, before == nil and "n/a" or tostring(before), after == nil and "n/a" or tostring(after),
        State.buildingRayHookReady and "ON" or "unavailable"))
end
rawLineOfSight = function(part, origin)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = LocalPlayer.Character and {LocalPlayer.Character} or {}
    if State.localBuildingsHidden then
        for _, root in ipairs(buildingRoots()) do table.insert(ignored, root) end
    end
    rayParams.FilterDescendantsInstances = ignored
    rayParams.IgnoreWater = true
    local start = origin or Camera.CFrame.Position
    local result = Workspace:Raycast(start, part.Position - start, rayParams)
    return result == nil or result.Instance:IsDescendantOf(part.Parent)
end
local function hasLineOfSight(part, origin)
    return not State.visibility or rawLineOfSight(part, origin)
end
local function targetData(radius, maxDistance, requireVisible, originOverride)
    Camera = Workspace.CurrentCamera or Camera
    if not Camera then
        return nil
    end
    local viewport = Camera.ViewportSize
    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local origin = originOverride or localOrigin()
    local best
    local bestScore
    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) and (not State.autoDefense or not State.defenseTarget
            or player == State.defenseTarget) then
            local part = aimPartOf(player)
            if part then
                local distance = (part.Position - origin).Magnitude
                if distance <= maxDistance then
                    local screen, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen and screen.Z > 0 then
                        local screenDistance = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                        if screenDistance <= radius then
                            local visible = rawLineOfSight(part, origin)
                            if not requireVisible or visible then
                                local direction = part.Position - Camera.CFrame.Position
                                local angle = 180
                                if direction.Magnitude > 0.001 then
                                    angle = math.deg(math.acos(math.clamp(Camera.CFrame.LookVector:Dot(direction.Unit), -1, 1)))
                                end
                                local _, humanoid = aliveCharacter(player)
                                local healthFraction = humanoid and humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
                                local score
                                if State.smartTargeting then
                                    score = (visible and 0 or 2000) + healthFraction * 500 + distance * 0.3 + angle * 3
                                else
                                    score = screenDistance
                                end
                                if not bestScore or score < bestScore then
                                    bestScore = score
                                    best = {
                                        player = player, part = part, distance = distance,
                                        screenDistance = screenDistance, screen = screen,
                                        visible = visible, angle = angle, score = score,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end
local function penetrationPower(tool, muzzleIndex, bulletIndex)
    if type(WeaponConfigManager) ~= "table" or type(WeaponConfigManager.GetMuzzleConfig) ~= "function" then
        return 0
    end
    local weaponName = typeof(tool) == "Instance" and tool.Name or tostring(tool)
    local ok, muzzle = pcall(WeaponConfigManager.GetMuzzleConfig, WeaponConfigManager, weaponName, muzzleIndex)
    if ok and type(muzzle) == "table" and type(muzzle.BulletSettings) == "table" then
        local bullet = muzzle.BulletSettings[bulletIndex]
        if type(bullet) == "table" and type(bullet.Penetration) == "number" then
            return bullet.Penetration
        end
    end
    return 0
end
local function obstructionInfo(origin, targetPart)
    local direction = targetPart.Position - origin
    if direction.Magnitude <= 0.001 then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = {}
    if LocalPlayer.Character then table.insert(ignored, LocalPlayer.Character) end
    local ignoreFolder = Workspace:FindFirstChild("Ignore")
    if ignoreFolder then table.insert(ignored, ignoreFolder) end
    params.FilterDescendantsInstances = ignored
    params.IgnoreWater = false
    local hit = Workspace:Raycast(origin, direction, params)
    if not hit or hit.Instance:IsDescendantOf(targetPart.Parent) then return nil end
    local thickness
    local include = RaycastParams.new()
    include.FilterType = Enum.RaycastFilterType.Include
    include.FilterDescendantsInstances = {hit.Instance}
    local unit = direction.Unit
    local back = Workspace:Raycast(hit.Position + unit * 64, -unit * 64, include)
    if back then thickness = (back.Position - hit.Position).Magnitude end
    return {
        instance = hit.Instance,
        material = tostring(hit.Material),
        thickness = thickness,
    }
end
local function predictedPoint(data, origin, velocity, drag, gravity)
    local point = data.part.Position
    if not State.prediction then
        return point
    end
    local targetVelocity = data.part.AssemblyLinearVelocity
    if targetVelocity.Magnitude > 100 then targetVelocity = targetVelocity.Unit * 100 end
    local travel = 0
    for _ = 1, 3 do
        local distance = (point + targetVelocity * travel - origin).Magnitude
        if drag and drag > 0.0001 and distance * drag < velocity * 0.95 then
            travel = -math.log(1 - distance * drag / velocity) / drag
        else
            travel = distance / math.max(velocity, 1)
        end
        travel = math.clamp(travel, 0, 0.75)
    end
    return point + targetVelocity * travel + Vector3.new(0, 0.5 * gravity * travel * travel, 0)
end
local function equippedWeapon()
    local character = LocalPlayer.Character
    if not character then return nil end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute("ToolType") == "Weapon" then
            return child
        end
    end
    return nil
end
local function equippedWeaponOrigin(tool)
    local handle = tool and tool:FindFirstChild("Handle")
    return handle and handle:IsA("BasePart") and handle.Position or localOrigin()
end
local function liveWeaponData(tool, forcedMuzzle, forcedBullet)
    if not tool then return nil end
    local muzzleIndex = forcedMuzzle or (State.lastVolleyTool == tool and State.lastMuzzleIndex) or 1
    local bulletIndex = forcedBullet or (State.lastVolleyTool == tool and State.lastBulletIndex) or 1
    if type(WeaponConfigManager) ~= "table" or type(WeaponConfigManager.GetMuzzleConfig) ~= "function" then return nil end
    local key = tool.Name .. ":" .. tostring(muzzleIndex) .. ":" .. tostring(bulletIndex)
    local config = State.weaponConfigCache[key]
    if not config then
        local ok, muzzle = pcall(WeaponConfigManager.GetMuzzleConfig, WeaponConfigManager, tool.Name, muzzleIndex)
        if not ok or type(muzzle) ~= "table" or type(muzzle.BulletSettings) ~= "table" then return nil end
        local bullet = muzzle.BulletSettings[bulletIndex]
        if type(bullet) ~= "table" then return nil end
        config = {
            speed = tonumber(bullet.MuzzleVelocity) or 0,
            drag = tonumber(bullet.Drag) or 0,
            spread = tonumber(bullet.Spread) or 1,
            fireInterval = 60 / math.max(tonumber(muzzle.Firerate) or 600, 1),
        }
        State.weaponConfigCache[key] = config
    end
    return {
        tool = tool, muzzleIndex = muzzleIndex, bulletIndex = bulletIndex,
        speed = config.speed, drag = config.drag, spread = config.spread,
        fireInterval = config.fireInterval,
        source = forcedBullet and "native" or (State.lastVolleyTool == tool and "recent" or "config"),
    }
end
local function assessShot(data, origin, weapon)
    if not data or not data.part or not data.part.Parent then
        return {canFire = false, color = "bad", text = "TARGET LOST"}
    end
    if not data or not weapon or weapon.speed <= 0 then
        return {canFire = false, color = "bad", text = "NO WEAPON DATA"}
    end
    local point = predictedPoint(data, origin, weapon.speed, weapon.drag, Workspace.Gravity)
    local vector = point - origin
    local distance = vector.Magnitude
    if distance < 0.01 then return {canFire = false, color = "bad", text = "NO TRAJECTORY"} end
    local travel
    if weapon.drag > 0.0001 and distance * weapon.drag < weapon.speed * 0.99 then
        travel = -math.log(1 - distance * weapon.drag / weapon.speed) / weapon.drag
    else
        travel = distance / weapon.speed
    end
    if travel > 1.5 then return {canFire = false, color = "bad", text = "OUT OF BALLISTIC RANGE"} end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = {}
    if LocalPlayer.Character then table.insert(ignored, LocalPlayer.Character) end
    table.insert(ignored, data.part.Parent)
    local ignoreFolder = Workspace:FindFirstChild("Ignore")
    if ignoreFolder then table.insert(ignored, ignoreFolder) end
    if State.localBuildingsHidden then
        for _, root in ipairs(buildingRoots()) do table.insert(ignored, root) end
    end
    params.FilterDescendantsInstances = ignored
    params.IgnoreWater = false
    local direction = vector.Unit
    local previous = origin
    local segments = travel <= 0.25 and 3 or (travel <= 0.6 and 5 or 8)
    for step = 1, segments do
        local t = travel * step / segments
        local forward = weapon.drag > 0.0001
            and weapon.speed / weapon.drag * (1 - math.exp(-weapon.drag * t))
            or weapon.speed * t
        local position = origin + direction * forward - Vector3.new(0, Workspace.Gravity * 0.5 * t * t, 0)
        local hit = Workspace:Raycast(previous, position - previous, params)
        if hit then
            return {canFire = false, color = "bad", text = "BLOCKED: " .. hit.Instance.Name, point = point}
        end
        previous = position
    end
    local spreadRadius = distance * math.tan(math.atan(weapon.spread / 3570))
    local halfWidth = math.max(data.part.Size.X, data.part.Size.Y) * 0.5
    local risky = spreadRadius > halfWidth
    local highConfidence = not risky and data.visible and not State.localBuildingsHidden
        and spreadRadius <= halfWidth * 0.6
        and data.part.AssemblyLinearVelocity.Magnitude * travel <= halfWidth * 2
        and travel <= 0.35
    return {
        canFire = true, color = risky and "caution" or "good", point = point,
        highConfidence = highConfidence,
        text = string.format("%s%s | %s M%d/B%d (%s) | %.2fs | spread %.1f",
            risky and "SPREAD RISK" or "CLEAR ARC",
            highConfidence and " | HIGH CONFIDENCE" or "", weapon.tool.Name,
            weapon.muzzleIndex, weapon.bulletIndex, weapon.source, travel, spreadRadius),
    }
end
local function safeAssessShot(data, origin, weapon)
    local ok, result = pcall(assessShot, data, origin, weapon)
    if ok and type(result) == "table" then return result end
    return {canFire = false, color = "bad", text = "ASSESSMENT UNAVAILABLE"}
end
local function legitReady(data, assessment, origin, originalDirection)
    if State.profile ~= "legit" then return true end
    if not data or not assessment or not assessment.canFire then return false, "NO CLEAR SHOT" end
    if not data.visible then return false, "NO LINE OF SIGHT" end
    if State.legitLockTarget ~= data.player
        or os.clock() - State.legitLockSince < State.legitDwell then
        return false, "ACQUIRING TARGET"
    end
    local aimVector = assessment.point and assessment.point - origin
    if not aimVector or aimVector.Magnitude < 0.001
        or typeof(originalDirection) ~= "Vector3" or originalDirection.Magnitude < 0.001 then
        return false, "AIM UNAVAILABLE"
    end
    local angle = math.deg(math.acos(math.clamp(originalDirection.Unit:Dot(aimVector.Unit), -1, 1)))
    if angle > State.legitMaxAngle then
        return false, string.format("AIM %.1f° > %.1f°", angle, State.legitMaxAngle)
    end
    return true
end
local function observeAuthoritativeDamage(data, beforeHealth, label, onResult)
    local targetPlayer = data and data.player
    task.delay(1.5, function()
        if not State.active then return end
        if not targetPlayer or targetPlayer.Parent ~= Players then
            log(string.format("INCONCLUSIVE: %s target left before observation", label))
            if type(onResult) == "function" then pcall(onResult, false, 0) end
            return
        end
        local _, humanoid = aliveCharacter(targetPlayer)
        local afterHealth = humanoid and humanoid.Health or 0
        if beforeHealth and afterHealth < beforeHealth then
            State.authoritativeDamageObservations = State.authoritativeDamageObservations + 1
            log(string.format("VULNERABLE CANDIDATE: %s caused server health %.1f -> %.1f", label, beforeHealth, afterHealth))
            if type(onResult) == "function" then pcall(onResult, true, beforeHealth - afterHealth) end
        else
            log(string.format("PROTECTED/NO EFFECT: %s produced no observed health loss", label))
            if type(onResult) == "function" then pcall(onResult, false, 0) end
        end
    end)
end
local nativeFireVolley
local hookClosure = (type(newcclosure) == "function" and newcclosure) or function(fn) return fn end
if type(hookfunction) == "function" then
    local hookOk, hookError = pcall(function()
    nativeFireVolley = hookfunction(ClientFire[volleyRoute], hookClosure(function(tool, muzzleIndex, bulletIndex, origin, directions, options)
        local silentAuditData
        local silentBeforeHealth
        local silentAngle
        State.lastVolleyTool = tool
        State.lastMuzzleIndex = muzzleIndex
        State.lastBulletIndex = bulletIndex
        if State.active and State.silentAim and type(directions) == "table" and #directions > 0 then
            local shotOrigin = origin or localOrigin()
            local data = targetData(State.fovRadius, State.aimDistance,
                State.profile == "legit" or (State.visibility and not State.penetrationAudit), shotOrigin)
            if data then
                local weapon = liveWeaponData(tool, muzzleIndex, bulletIndex)
                local assessment = safeAssessShot(data, shotOrigin, weapon)
                State.shotAssessment = assessment
                local allowed, reason = legitReady(data, assessment, shotOrigin, directions[1])
                if not allowed then State.lastResult = "Legit held: " .. tostring(reason) end
                local point = allowed and assessment.canFire and assessment.point
                if not point and State.penetrationAudit and weapon then
                    point = predictedPoint(data, shotOrigin, weapon.speed, weapon.drag, Workspace.Gravity)
                end
                if point then
                local vector = point - shotOrigin
                if vector.Magnitude > 0.001 then
                    local originalDirection = directions[1]
                    if typeof(originalDirection) == "Vector3" and originalDirection.Magnitude > 0.001 then
                        silentAngle = math.deg(math.acos(math.clamp(originalDirection.Unit:Dot(vector.Unit), -1, 1)))
                    end
                    local redirected = table_clone(directions)
                    redirected[1] = vector
                    directions = redirected
                    State.redirectedShots = State.redirectedShots + 1
                    State.currentTarget = data.player
                    State.currentPart = data.part
                    State.lastResult = "native volley redirected to " .. data.player.Name
                    if State.angleAudit and not State.angleAuditPending then
                        local _, humanoid = aliveCharacter(data.player)
                        silentAuditData = data
                        silentBeforeHealth = humanoid and humanoid.Health
                        State.angleAuditPending = silentBeforeHealth ~= nil
                    end
                    if State.penetrationAudit then
                        State.penetrationShots = State.penetrationShots + 1
                        local cover = obstructionInfo(shotOrigin, data.part)
                        local power = penetrationPower(tool, muzzleIndex, bulletIndex)
                        if cover and os.clock() - State.lastPenetrationLogAt >= 0.75 then
                            State.lastPenetrationLogAt = os.clock()
                            log(string.format("native penetration shot: power %.2f | %s | thickness %s",
                                power, cover.material, cover.thickness and string.format("%.2f", cover.thickness) or "unknown"))
                        end
                        local originalOptions = type(options) == "table" and options or {}
                        local wrappedOptions = table_clone(originalOptions)
                        local originalImpact = originalOptions.OnImpact
                        local expectedCharacter = data.player.Character
                        wrappedOptions.OnImpact = function(impact)
                            local instance = type(impact) == "table" and impact.Instance or nil
                            local outcome = type(impact) == "table" and impact.Outcome or nil
                            if instance and expectedCharacter and instance:IsDescendantOf(expectedCharacter) then
                                State.penetrationReached = State.penetrationReached + 1
                                State.lastResult = "native projectile reached " .. data.player.Name .. " after cover processing"
                            elseif outcome == "Pierce" then
                                State.penetrationPierces = State.penetrationPierces + 1
                            elseif outcome == "Stop" then
                                State.penetrationStops = State.penetrationStops + 1
                            end
                            if type(originalImpact) == "function" then originalImpact(impact) end
                        end
                        options = wrappedOptions
                    end
                end
                end
            end
        end
        local result = nativeFireVolley(tool, muzzleIndex, bulletIndex, origin, directions, options)
        if silentAuditData and silentBeforeHealth then
            local angle = silentAngle or 0
            observeAuthoritativeDamage(silentAuditData, silentBeforeHealth,
                string.format("silent-angle %.1f degrees", angle), function(accepted)
                    State.angleAuditPending = false
                    if accepted then
                        State.maxAcceptedAngle = math.max(State.maxAcceptedAngle, angle)
                        log(string.format("angle audit accepted %.1f degrees; max accepted %.1f", angle, State.maxAcceptedAngle))
                    end
                end)
        end
        return result
    end))
    end)
    if not hookOk then
        log("native volley hook unavailable: " .. tostring(hookError))
    end
    if type(nativeFireVolley) == "function" then
        State.hookReady = true
        table.insert(State.cleanups, function()
            pcall(hookfunction, ClientFire[volleyRoute], nativeFireVolley)
        end)
    end
else
    log("hookfunction unavailable; ESP works, shot redirection unavailable")
end
if type(hookfunction) == "function" and type(WeaponSource) == "table"
    and type(WeaponSource.toFireParams) == "function" then
    local nativeToFireParams
    local ok, err = pcall(function()
        nativeToFireParams = hookfunction(WeaponSource.toFireParams, hookClosure(function(params)
            local result = nativeToFireParams(params)
            if State.active and State.localBuildingsHidden and result and result.RaycastParams then
                local ignored = table_clone(result.RaycastParams.FilterDescendantsInstances)
                for _, root in ipairs(buildingRoots()) do table.insert(ignored, root) end
                result.RaycastParams.FilterDescendantsInstances = ignored
            end
            return result
        end))
    end)
    if ok and type(nativeToFireParams) == "function" then
        State.buildingRayHookReady = true
        table.insert(State.cleanups, function()
            pcall(hookfunction, WeaponSource.toFireParams, nativeToFireParams)
        end)
    else
        log("building projectile filter unavailable: " .. tostring(err))
    end
end
local function emitSignal(signal)
    if not signal then
        return false
    end
    if type(firesignal) == "function" then
        local ok = pcall(firesignal, signal)
        if ok then
            return true
        end
    end
    if type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, signal)
        if ok then
            local fired = false
            for _, connection in ipairs(connections) do
                if type(connection.Fire) == "function" then
                    fired = pcall(connection.Fire, connection) or fired
                elseif type(connection.Function) == "function" then
                    fired = pcall(connection.Function) or fired
                end
            end
            if fired then
                return true
            end
        end
    end
    return false
end
local function releaseFire()
    if State.firing then
        emitSignal(ShootReleased)
        State.firing = false
    end
end
local function triggerOnce()
    if State.firing then
        return
    end
    if not emitSignal(ShootPressed) then
        log("native Shoot.Pressed signal could not be driven")
        State.triggerbot = false
        return
    end
    State.firing = true
    State.triggerPulls = State.triggerPulls + 1
    task.delay(0.045, function()
        if State.active then
            releaseFire()
        end
    end)
end
local function projectileForward(speed, drag, seconds)
    return drag > 0.0001 and speed / drag * (1 - math.exp(-drag * seconds)) or speed * seconds
end
local function enemyWeaponThreat(player)
    if type(WeaponConfigManager) ~= "table"
        or type(WeaponConfigManager.MuzzleConfigsOf) ~= "function" then return 0 end
    local enemyCharacter = aliveCharacter(player)
    local localCharacter = aliveCharacter(LocalPlayer)
    if not enemyCharacter or not localCharacter then return 0 end
    local localPart = localCharacter:FindFirstChild("UpperTorso")
        or localCharacter:FindFirstChild("Torso") or localCharacter:FindFirstChild("HumanoidRootPart")
    if not localPart then return 0 end
    local tool
    for _, child in ipairs(enemyCharacter:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute("ToolType") == "Weapon" then tool = child break end
    end
    if not tool then return 0 end
    local handle = tool:FindFirstChild("Handle")
    if not handle then return 0 end
    local ok, muzzles = pcall(WeaponConfigManager.MuzzleConfigsOf, WeaponConfigManager, tool.Name)
    if not ok or type(muzzles) ~= "table" then return 0 end
    local best = 0
    for muzzleIndex, muzzle in ipairs(muzzles) do
        local attachment = handle:FindFirstChild("Muzzle" .. muzzleIndex)
        if attachment and attachment:IsA("Attachment") and type(muzzle.BulletSettings) == "table" then
            local origin = attachment.WorldPosition
            local direction = (attachment.WorldCFrame * CFrame.Angles(math.rad(muzzle.DefaultAngle or 0), 0, 0)).LookVector
            local distance = (localPart.Position - origin).Magnitude
            if distance <= State.aimDistance and distance > 0.1 then
                for _, bullet in ipairs(muzzle.BulletSettings) do
                    local speed = tonumber(bullet.MuzzleVelocity) or 0
                    local drag = tonumber(bullet.Drag) or 0
                    if speed > 0 and (drag <= 0 or distance * drag < speed * 0.99) then
                        local travel = drag > 0.0001
                            and -math.log(1 - distance * drag / speed) / drag or distance / speed
                        if travel <= 0.7 then
                            local localVelocity = localPart.AssemblyLinearVelocity
                            if localVelocity.Magnitude > 80 then localVelocity = localVelocity.Unit * 80 end
                            local predicted = localPart.Position + localVelocity * travel
                            local pathEnd = origin + direction * projectileForward(speed, drag, travel)
                                - Vector3.new(0, Workspace.Gravity * 0.5 * travel * travel, 0)
                            local miss = (pathEnd - predicted).Magnitude
                            local radius = math.max(localPart.Size.X, localPart.Size.Y, localPart.Size.Z) * 0.5 + 0.7
                            local spreadRadius = distance * math.tan(math.atan((tonumber(bullet.Spread) or 1) / 3570))
                            if miss <= radius + spreadRadius then
                                local params = RaycastParams.new()
                                params.FilterType = Enum.RaycastFilterType.Exclude
                                local ignored = {enemyCharacter, localCharacter}
                                local ignoreFolder = Workspace:FindFirstChild("Ignore")
                                if ignoreFolder then table.insert(ignored, ignoreFolder) end
                                params.FilterDescendantsInstances = ignored
                                params.IgnoreWater = false
                                local previous, blocked = origin, false
                                local segments = travel <= 0.25 and 3 or (travel <= 0.5 and 5 or 8)
                                for step = 1, segments do
                                    local t = travel * step / segments
                                    local position = origin + direction * projectileForward(speed, drag, t)
                                        - Vector3.new(0, Workspace.Gravity * 0.5 * t * t, 0)
                                    if Workspace:Raycast(previous, position - previous, params) then
                                        blocked = true
                                        break
                                    end
                                    previous = position
                                end
                                if not blocked then
                                    local score = math.clamp(100 - miss / radius * 15
                                        - spreadRadius / radius * 7 - travel * 3, 0, 100)
                                    best = math.max(best, math.floor(score + 0.5))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end
local function releaseDefenseTarget(reason)
    if State.defenseTarget then
        log("auto defense released " .. State.defenseTarget.Name .. (reason and " (" .. reason .. ")" or ""))
    end
    State.defenseTarget = nil
    State.defenseThreatScore = 0
    releaseFire()
    if State.defenseSavedModes then
        State.silentAim = State.defenseSavedModes.silentAim
        State.triggerbot = State.defenseSavedModes.triggerbot
        State.visibility = State.defenseSavedModes.visibility
        State.penetrationAudit = State.defenseSavedModes.penetrationAudit
        State.defenseSavedModes = nil
    end
    if State.defenseRotationHumanoid then
        pcall(function() State.defenseRotationHumanoid.AutoRotate = State.defenseSavedAutoRotate end)
        State.defenseRotationHumanoid = nil
        State.defenseSavedAutoRotate = nil
    end
end
local function scanDefenseThreats()
    if not State.autoDefense then return end
    if State.defenseTarget and not isEnemy(State.defenseTarget) then
        releaseDefenseTarget("target eliminated or left")
    end
    if State.defenseTarget then
        local ok, score = pcall(enemyWeaponThreat, State.defenseTarget)
        State.defenseThreatScore = ok and score or 0
        State.silentAim = true
        State.triggerbot = true
        State.visibility = true
        State.penetrationAudit = false
        return
    end
    local bestPlayer, bestScore
    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) then
            local ok, score = pcall(enemyWeaponThreat, player)
            if ok and score >= State.defenseThreshold and (not bestScore or score > bestScore) then
                bestPlayer, bestScore = player, score
            end
        end
    end
    if bestPlayer then
        State.defenseSavedModes = {
            silentAim = State.silentAim, triggerbot = State.triggerbot,
            visibility = State.visibility, penetrationAudit = State.penetrationAudit,
        }
        State.defenseTarget = bestPlayer
        State.defenseThreatScore = bestScore
        State.silentAim = true
        State.triggerbot = true
        State.visibility = true
        State.penetrationAudit = false
        State.nextTriggerAt = 0
        log(string.format("auto defense locked %s | modeled threat %d/100", bestPlayer.Name, bestScore))
    end
end
local function rotateToDefenseTarget()
    local player = State.defenseTarget
    if not State.active or not State.autoDefense or not player or not isEnemy(player) then return end
    local target = aimPartOf(player)
    local character, humanoid = aliveCharacter(LocalPlayer)
    local root = character and character:FindFirstChild("HumanoidRootPart")
    Camera = Workspace.CurrentCamera or Camera
    if not target or not Camera then return end
    if root and humanoid and not humanoid.SeatPart then
        if State.defenseRotationHumanoid ~= humanoid then
            if State.defenseRotationHumanoid then
                pcall(function() State.defenseRotationHumanoid.AutoRotate = State.defenseSavedAutoRotate end)
            end
            State.defenseRotationHumanoid = humanoid
            State.defenseSavedAutoRotate = humanoid.AutoRotate
        end
        if humanoid.AutoRotate then humanoid.AutoRotate = false end
        local flatTarget = Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
        local flatDirection = flatTarget - root.Position
        if flatDirection.Magnitude > 0.01
            and root.CFrame.LookVector:Dot(flatDirection.Unit) < 0.9998 then
            root.CFrame = CFrame.lookAt(root.Position, flatTarget)
        end
    end
    local cameraPosition = Camera.CFrame.Position
    local cameraDirection = target.Position - cameraPosition
    if cameraDirection.Magnitude > 0.01
        and Camera.CFrame.LookVector:Dot(cameraDirection.Unit) < 0.99995 then
        Camera.CFrame = CFrame.lookAt(cameraPosition, target.Position)
    end
end
local defenseRenderKey = "BallisticsProbeAutoDefense_13687899540"
local defenseBound = pcall(function()
    RunService:BindToRenderStep(defenseRenderKey, Enum.RenderPriority.Camera.Value + 1, function()
        if State.active and State.autoDefense and State.defenseTarget then
            pcall(rotateToDefenseTarget)
        end
    end)
end)
if defenseBound then
    table.insert(State.cleanups, function() RunService:UnbindFromRenderStep(defenseRenderKey) end)
end
local function occupiedVehicleRoot()
    local character = LocalPlayer.Character
    if type(DriverController) == "table" and type(DriverController.GetVehicle) == "function" then
        local ok, vehicle = pcall(DriverController.GetVehicle)
        if ok and vehicle and vehicle:IsA("Model") then
            local root = vehicle:FindFirstChild("RootPart")
                or vehicle.PrimaryPart
                or vehicle:FindFirstChildWhichIsA("BasePart")
            if root and root:IsA("BasePart") then
                local seats = vehicle:FindFirstChild("Seats")
                local driverSeat = seats and seats:FindFirstChild("DriverSeat", true)
                return vehicle, root, driverSeat, true
            end
        end
    end
    if character then
        for _, seat in ipairs(CollectionService:GetTagged("FactoryVehicleSeat")) do
            local occupant = seat:FindFirstChild("Occupant")
            if occupant and occupant:IsA("ObjectValue") and occupant.Value == character then
                local vehicle = seat.Parent and seat.Parent.Parent
                if vehicle and vehicle:IsA("Model") then
                    local root = vehicle:FindFirstChild("RootPart")
                        or vehicle.PrimaryPart
                        or vehicle:FindFirstChildWhichIsA("BasePart")
                    if root and root:IsA("BasePart") then
                        return vehicle, root, seat, seat.Name == "DriverSeat"
                    end
                end
            end
        end
    end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local seat = humanoid and humanoid.SeatPart
    if not seat then return nil, nil end
    local node = seat
    while node and node ~= Workspace do
        if node:IsA("Model") then
            local root = node:FindFirstChild("RootPart")
                or node.PrimaryPart
                or node:FindFirstChildWhichIsA("BasePart")
            if root and root:IsA("BasePart") then
                return node, root, seat, seat.Name == "DriverSeat"
            end
        end
        node = node.Parent
    end
    return nil, seat, seat, seat.Name == "DriverSeat"
end
local function toggleVehicleSpeed()
    State.vehicleSpeedEnabled = not State.vehicleSpeedEnabled
    State.vehicleRoot = nil
    log(string.format("vehicle speed modifier %s at %d studs/s",
        State.vehicleSpeedEnabled and "enabled" or "disabled", State.vehicleTargetSpeed))
end
local function movementKey(key)
    return UserInputService:IsKeyDown(key) and 1 or 0
end
local function flyOccupiedVehicle(root)
    Camera = Workspace.CurrentCamera or Camera
    if not Camera then return end
    local direction = Camera.CFrame.LookVector * (movementKey(Enum.KeyCode.W) - movementKey(Enum.KeyCode.S))
        + Camera.CFrame.RightVector * (movementKey(Enum.KeyCode.D) - movementKey(Enum.KeyCode.A))
        + Vector3.new(0, movementKey(Enum.KeyCode.Space) - movementKey(Enum.KeyCode.LeftControl), 0)
    if direction.Magnitude > 0.001 then
        root.AssemblyLinearVelocity = direction.Unit * State.vehicleTargetSpeed
    else
        root.AssemblyLinearVelocity = Vector3.zero
    end
    root.AssemblyAngularVelocity = Vector3.zero
end
local function nearestRoadkillTarget(origin)
    local bestPlayer
    local bestPart
    local bestHumanoid
    local bestDistance
    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) then
            local character, humanoid = aliveCharacter(player)
            local part = character and character:FindFirstChild("HumanoidRootPart")
            if part then
                local distance = (part.Position - origin).Magnitude
                if distance <= State.roadkillRadius and (not bestDistance or distance < bestDistance) then
                    bestPlayer, bestPart, bestHumanoid, bestDistance = player, part, humanoid, distance
                end
            end
        end
    end
    return bestPlayer, bestPart, bestHumanoid, bestDistance
end
local function driveTowardRoadkillTarget(root)
    if State.roadkillHumanoid and State.roadkillPreviousHealth
        and State.roadkillPreviousHealth > 0 and State.roadkillHumanoid.Health <= 0 then
        if os.clock() - State.roadkillLastNearAt <= 2.5 then
            State.roadkillKillsObserved = State.roadkillKillsObserved + 1
            log("roadkill candidate killed " .. (State.roadkillTarget and State.roadkillTarget.Name or "target")
                .. "; confirm Roadkill in the authoritative death feed")
        end
        State.roadkillTarget = nil
        State.roadkillHumanoid = nil
        State.roadkillPreviousHealth = nil
    end
    local player, part, humanoid, distance = nearestRoadkillTarget(root.Position)
    if not player then
        if State.roadkillTarget and os.clock() - State.roadkillLastNearAt > 3 then
            State.roadkillTarget = nil
            State.roadkillHumanoid = nil
            State.roadkillPreviousHealth = nil
        end
        return false
    end
    if State.roadkillTarget ~= player then
        State.roadkillTarget = player
        State.roadkillHumanoid = humanoid
        State.roadkillPreviousHealth = humanoid.Health
        log(string.format("auto roadkill acquired %s at %.1f studs; server collision decides damage", player.Name, distance))
    end
    State.roadkillLastNearAt = os.clock()
    State.roadkillPreviousHealth = humanoid.Health
    local direction = part.Position - root.Position
    local horizontal = Vector3.new(direction.X, 0, direction.Z)
    if horizontal.Magnitude > 0.001 then
        local current = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = horizontal.Unit * State.vehicleTargetSpeed + Vector3.new(0, current.Y, 0)
        return true
    end
    return false
end
local function restoreVehicleNoclip()
    for part, canCollide in pairs(State.vehicleNoclipOriginal) do
        if part and part.Parent then
            pcall(function() part.CanCollide = canCollide end)
        end
    end
    State.vehicleNoclipOriginal = {}
    State.vehicleNoclipVehicle = nil
end
local function applyVehicleNoclip(vehicle)
    if not vehicle then
        restoreVehicleNoclip()
        return
    end
    if State.vehicleNoclipVehicle ~= vehicle then
        restoreVehicleNoclip()
        State.vehicleNoclipVehicle = vehicle
        State.nextVehicleNoclipScanAt = 0
        State.nextVehicleNoclipApplyAt = 0
    end
    if os.clock() >= State.nextVehicleNoclipScanAt then
        State.nextVehicleNoclipScanAt = os.clock() + 1
        for _, descendant in ipairs(vehicle:GetDescendants()) do
            if descendant:IsA("BasePart") and State.vehicleNoclipOriginal[descendant] == nil then
                State.vehicleNoclipOriginal[descendant] = descendant.CanCollide
            end
        end
    end
    if os.clock() >= State.nextVehicleNoclipApplyAt then
        State.nextVehicleNoclipApplyAt = os.clock() + 0.1
        for part in pairs(State.vehicleNoclipOriginal) do
            if part.Parent then part.CanCollide = false end
        end
    end
end
local function setDrawingVisible(object, visible)
    if object then pcall(function() object.Visible = visible end) end
end
local function removeDrawing(object)
    if object then
        local ok = pcall(function() object:Destroy() end)
        if not ok then pcall(function() object:Remove() end) end
    end
end
local bonePairs = {
    {"head", "chest"}, {"chest", "pelvis"},
    {"chest", "leftUpperArm"}, {"leftUpperArm", "leftLowerArm"}, {"leftLowerArm", "leftHand"},
    {"chest", "rightUpperArm"}, {"rightUpperArm", "rightLowerArm"}, {"rightLowerArm", "rightHand"},
    {"pelvis", "leftUpperLeg"}, {"leftUpperLeg", "leftLowerLeg"}, {"leftLowerLeg", "leftFoot"},
    {"pelvis", "rightUpperLeg"}, {"rightUpperLeg", "rightLowerLeg"}, {"rightLowerLeg", "rightFoot"},
}
local function bodyPoint(character, names)
    for _, name in ipairs(names) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part.Position end
    end
    return nil
end
local function skeletonAnchors(character)
    return {
        head = bodyPoint(character, {"Head"}),
        chest = bodyPoint(character, {"UpperTorso", "Torso"}),
        pelvis = bodyPoint(character, {"LowerTorso", "Torso"}),
        leftUpperArm = bodyPoint(character, {"LeftUpperArm", "Left Arm"}),
        leftLowerArm = bodyPoint(character, {"LeftLowerArm", "Left Arm"}),
        leftHand = bodyPoint(character, {"LeftHand", "Left Arm"}),
        rightUpperArm = bodyPoint(character, {"RightUpperArm", "Right Arm"}),
        rightLowerArm = bodyPoint(character, {"RightLowerArm", "Right Arm"}),
        rightHand = bodyPoint(character, {"RightHand", "Right Arm"}),
        leftUpperLeg = bodyPoint(character, {"LeftUpperLeg", "Left Leg"}),
        leftLowerLeg = bodyPoint(character, {"LeftLowerLeg", "Left Leg"}),
        leftFoot = bodyPoint(character, {"LeftFoot", "Left Leg"}),
        rightUpperLeg = bodyPoint(character, {"RightUpperLeg", "Right Leg"}),
        rightLowerLeg = bodyPoint(character, {"RightLowerLeg", "Right Leg"}),
        rightFoot = bodyPoint(character, {"RightFoot", "Right Leg"}),
    }
end
local function drawLockTriangle(center, height, color)
    local radius = math.clamp(height * 0.38, 20, 78)
    local points = {
        Vector2.new(center.X, center.Y - radius),
        Vector2.new(center.X - radius * 0.85, center.Y + radius * 0.72),
        Vector2.new(center.X + radius * 0.85, center.Y + radius * 0.72),
    }
    for index = 1, 3 do
        local nextIndex = index % 3 + 1
        for _, line in ipairs({lockHalos[index], lockLines[index]}) do
            if line then
                line.From = points[index]
                line.To = points[nextIndex]
                line.Color = color
                line.Visible = true
            end
        end
    end
end
local function drawBodyOverlays(visual, character, color, height, showSkeleton, showChams)
    local anchors = skeletonAnchors(character)
    local projected = {}
    for name, position in pairs(anchors) do
        if position then
            local screen, visible = Camera:WorldToViewportPoint(position)
            if visible and screen.Z > 0 then projected[name] = Vector2.new(screen.X, screen.Y) end
        end
    end
    for index, pair in ipairs(bonePairs) do
        if showSkeleton and not visual["bone" .. index] then
            visual["bone" .. index] = newDrawing("Line", {Thickness = 2, Color = Colors.enemy,
                Transparency = 1, ZIndex = 11, Visible = false})
        end
        if showChams and not visual["cham" .. index] then
            visual["cham" .. index] = newDrawing("Line", {Thickness = 8, Color = Colors.enemy,
                Transparency = 0.48, ZIndex = 9, Visible = false})
        end
        local a, b = projected[pair[1]], projected[pair[2]]
        local bone, cham = visual["bone" .. index], visual["cham" .. index]
        local valid = a and b and (a - b).Magnitude > 0.08
        if valid then
            if bone then
                bone.From = a; bone.To = b; bone.Color = color
                bone.Visible = showSkeleton
            end
            if cham then
                cham.From = a; cham.To = b; cham.Color = color
                cham.Thickness = math.clamp(height / 17, 5, 16)
                cham.Visible = showChams
            end
        end
        if not valid then
            setDrawingVisible(bone, false)
            setDrawingVisible(cham, false)
        end
    end
end
local function hideBodyOverlays(visual)
    for index = 1, #bonePairs do
        setDrawingVisible(visual["bone" .. index], false)
        setDrawingVisible(visual["cham" .. index], false)
    end
end
local function playerVisual(player)
    local visual = State.playerDrawings[player]
    if visual then return visual end
    visual = {
        box = newDrawing("Square", {Filled = false, Thickness = 1.5, Color = Colors.enemy, ZIndex = 10}),
        outline = newDrawing("Square", {Filled = false, Thickness = 3.5, Color = Color3.new(0, 0, 0), ZIndex = 9}),
        name = newDrawing("Text", {Center = true, Size = 14, Font = 2, Color = Colors.text, Outline = true, ZIndex = 11}),
        tracer = newDrawing("Line", {Thickness = 1.5, Color = Colors.enemy, ZIndex = 10}),
    }
    State.playerDrawings[player] = visual
    return visual
end
local function hideVisual(visual)
    for _, object in pairs(visual) do setDrawingVisible(object, false) end
end
local function updateVisuals()
    Camera = Workspace.CurrentCamera or Camera
    if not Camera then return end
    local viewport = Camera.ViewportSize
    if fovCircle then
        fovCircle.Position = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
        fovCircle.Radius = State.fovRadius
        fovCircle.Visible = State.active
    end
    if triggerCircle then
        triggerCircle.Position = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
        triggerCircle.Radius = State.triggerRadius
        triggerCircle.Visible = State.active and State.triggerbot
    end
    local target = targetData(State.fovRadius, State.aimDistance, false)
    State.currentTarget = target and target.player or nil
    State.currentPart = target and target.part or nil
    if State.profile == "legit" and target and target.visible then
        if State.legitLockTarget ~= target.player then
            State.legitLockTarget = target.player
            State.legitLockSince = os.clock()
        end
    else
        State.legitLockTarget = nil
        State.legitLockSince = 0
    end
    if target and targetAssessmentLabel then
        if os.clock() >= State.nextAssessmentAt or State.assessedTarget ~= target.player then
            State.nextAssessmentAt = os.clock() + 0.1
            State.assessedTarget = target.player
            local weapon = equippedWeapon()
            local data = liveWeaponData(weapon)
            State.shotAssessment = safeAssessShot(target, equippedWeaponOrigin(weapon), data)
        end
        local assessment = State.shotAssessment
        targetAssessmentLabel.Position = Vector2.new(target.screen.X, target.screen.Y - 35)
        local displayText = assessment and assessment.text or "ASSESSING"
        local displayColor = assessment and (assessment.color == "good" and Colors.on
            or assessment.color == "bad" and Colors.off or Colors.accent) or Colors.accent
        State.visualShotReady = assessment and assessment.canFire or false
        if State.profile == "legit" and assessment then
            local ready, reason = legitReady(target, assessment,
                equippedWeaponOrigin(equippedWeapon()), Camera.CFrame.LookVector)
            State.visualShotReady = ready
            if not ready then
                displayText = "LEGIT HOLD: " .. tostring(reason)
                displayColor = Colors.accent
            end
        end
        targetAssessmentLabel.Text = displayText
        targetAssessmentLabel.Color = displayColor
        targetAssessmentLabel.Visible = State.active
    elseif targetAssessmentLabel then
        targetAssessmentLabel.Visible = false
        State.shotAssessment = nil
        State.assessedTarget = nil
        State.visualShotReady = false
    end
    for _, line in ipairs(lockLines) do setDrawingVisible(line, false) end
    for _, line in ipairs(lockHalos) do setDrawingVisible(line, false) end
    local showPlayers = State.esp or State.tracers
    for _, player in ipairs(Players:GetPlayers()) do
        local visual = State.playerDrawings[player]
        if not showPlayers or not isEnemy(player) then
            if visual then hideVisual(visual) end
        else
            visual = visual or playerVisual(player)
            local character = aliveCharacter(player)
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local head = character and character:FindFirstChild("Head")
            if not root or not head then
                hideVisual(visual)
            else
                local distance = (root.Position - localOrigin()).Magnitude
                local rootScreen, rootVisible = Camera:WorldToViewportPoint(root.Position)
                local headScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local footScreen = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                if not rootVisible or rootScreen.Z <= 0 then
                    hideVisual(visual)
                else
                    local height = math.max(math.abs(footScreen.Y - headScreen.Y), 12)
                    local width = height * 0.55
                    local selected = State.currentTarget == player
                    local highConfidence = selected and State.assessedTarget == player
                        and State.visualShotReady and State.shotAssessment and State.shotAssessment.highConfidence
                    local color = highConfidence and Colors.lock or selected and Colors.accent or Colors.enemy
                    local espVisible = State.esp and distance <= State.espDistance
                    local showBox = State.espStyle == "Box" or State.espStyle == "Combined"
                    local showChams = State.espStyle == "Chams" or State.espStyle == "Combined"
                    local showSkeleton = State.espStyle == "Skeleton" or State.espStyle == "Combined"
                    visual.outline.Position = Vector2.new(rootScreen.X - width * 0.5, headScreen.Y)
                    visual.outline.Size = Vector2.new(width, height)
                    visual.outline.Visible = espVisible and showBox
                    visual.box.Position = visual.outline.Position
                    visual.box.Size = visual.outline.Size
                    visual.box.Color = color
                    visual.box.Visible = espVisible and showBox
                    if showChams and espVisible and not visual.chamFill then
                        visual.chamFill = newDrawing("Square", {Filled = true, Color = Colors.enemy,
                            Transparency = 0.20, ZIndex = 8, Visible = false})
                    end
                    if visual.chamFill then
                        visual.chamFill.Position = visual.outline.Position
                        visual.chamFill.Size = visual.outline.Size
                        visual.chamFill.Color = color
                        visual.chamFill.Visible = espVisible and showChams
                    end
                    if espVisible and (showSkeleton or showChams) then
                        drawBodyOverlays(visual, character, color, height, showSkeleton, showChams)
                    else
                        hideBodyOverlays(visual)
                    end
                    visual.name.Position = Vector2.new(rootScreen.X, headScreen.Y - 18)
                    visual.name.Text = string.format("%s  [%dm]", player.Name, math.floor(distance + 0.5))
                    visual.name.Color = color
                    visual.name.Visible = espVisible
                    visual.tracer.From = Vector2.new(viewport.X * 0.5, viewport.Y - 4)
                    visual.tracer.To = Vector2.new(rootScreen.X, rootScreen.Y)
                    visual.tracer.Color = color
                    visual.tracer.Visible = State.tracers and distance <= State.tracerDistance
                    if selected and espVisible then
                        drawLockTriangle(Vector2.new(rootScreen.X, headScreen.Y + height * 0.34), height, color)
                    end
                end
            end
        end
    end
end
local Rayfield
do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
    end)
    if ok and result then
        Rayfield = result
    end
end
if not Rayfield then
    warn("[ballistics probe] Rayfield Gen2 failed to load")
end
local window = nil
local menuVisible = true
if Rayfield then
    window = Rayfield:CreateWindow({
        name = "Cold War",
        subtitle = "Ballistics Probe",
        sidebarLayout = true,
        theme = "cobalt",
    })
    local combat = window:CreateTab({ name = "Combat", icon = 93364949241311 })
    local visuals = window:CreateTab({ name = "Visuals", icon = 93364949241311 })
    local movement = window:CreateTab({ name = "Movement", icon = 93364949241311 })
    local settings = window:CreateTab({ name = "Settings", icon = 93364949241311 })
    pcall(function() combat:CreateSection({ name = "Aim" }) end)
    combat:CreateToggle({
        name = "Silent Aim",
        flag = "silentAim",
        value = State.silentAim,
        callback = function(v)
            State.silentAim = v
            log("silent aim " .. (v and "ON" or "OFF"))
        end,
    })
    combat:CreateToggle({
        name = "Triggerbot",
        flag = "triggerbot",
        value = State.triggerbot,
        callback = function(v)
            State.triggerbot = v
            log("triggerbot " .. (v and "ON" or "OFF"))
        end,
    })
    combat:CreateToggle({
        name = "Visibility Check",
        flag = "visibility",
        value = State.visibility,
        callback = function(v) State.visibility = v end,
    })
    combat:CreateToggle({
        name = "Prediction",
        flag = "prediction",
        value = State.prediction,
        callback = function(v) State.prediction = v end,
    })
    combat:CreateToggle({
        name = "Smart Targeting",
        flag = "smartTargeting",
        value = State.smartTargeting,
        callback = function(v) State.smartTargeting = v end,
    })
    combat:CreateToggle({
        name = "Penetration Audit",
        flag = "penetrationAudit",
        value = State.penetrationAudit,
        callback = function(v) State.penetrationAudit = v end,
    })
    combat:CreateToggle({
        name = "Angle Audit",
        flag = "angleAudit",
        value = State.angleAudit,
        callback = function(v) State.angleAudit = v end,
    })
    combat:CreateToggle({
        name = "Auto Defense",
        flag = "autoDefense",
        value = State.autoDefense,
        callback = function(v)
            State.autoDefense = v
            if not v then releaseDefenseTarget("toggle off") end
            log("auto defense " .. (v and "ON" or "OFF"))
        end,
    })
    combat:CreateDropdown({
        name = "Target Part",
        flag = "targetPart",
        options = { "Torso", "Head" },
        value = { State.targetPart },
        multiSelect = false,
        callback = function(selected)
            local v = type(selected) == "table" and selected[1] or selected
            State.targetPart = v or "Torso"
            log("target part: " .. State.targetPart)
        end,
    })
    combat:CreateDropdown({
        name = "Profile",
        flag = "profile",
        options = { "rage", "legit" },
        value = { State.profile },
        multiSelect = false,
        callback = function(selected)
            local v = type(selected) == "table" and selected[1] or selected
            State.profile = v or "rage"
            log("profile: " .. State.profile)
        end,
    })
    combat:CreateSlider({
        name = "Aim FOV",
        flag = "fovRadius",
        range = { 90, 360 },
        increment = 5,
        value = State.fovRadius,
        suffix = " px",
        callback = function(v) State.fovRadius = v end,
    })
    combat:CreateSlider({
        name = "Trigger FOV",
        flag = "triggerRadius",
        range = { 10, 360 },
        increment = 5,
        value = State.triggerRadius,
        suffix = " px",
        callback = function(v) State.triggerRadius = v end,
    })
    combat:CreateSlider({
        name = "Aim Distance",
        flag = "aimDistance",
        range = { 100, 2000 },
        increment = 50,
        value = State.aimDistance,
        callback = function(v) State.aimDistance = v end,
    })
    pcall(function() visuals:CreateSection({ name = "ESP" }) end)
    visuals:CreateToggle({
        name = "ESP",
        flag = "esp",
        value = State.esp,
        callback = function(v) State.esp = v end,
    })
    visuals:CreateToggle({
        name = "Tracers",
        flag = "tracers",
        value = State.tracers,
        callback = function(v) State.tracers = v end,
    })
    visuals:CreateDropdown({
        name = "ESP Style",
        flag = "espStyle",
        options = { "Box", "Corner", "Skeleton", "Chams" },
        value = { State.espStyle },
        multiSelect = false,
        callback = function(selected)
            local v = type(selected) == "table" and selected[1] or selected
            State.espStyle = v or "Box"
        end,
    })
    visuals:CreateSlider({
        name = "ESP Distance",
        flag = "espDistance",
        range = { 100, 2000 },
        increment = 50,
        value = State.espDistance,
        callback = function(v) State.espDistance = v end,
    })
    visuals:CreateSlider({
        name = "Tracer Distance",
        flag = "tracerDistance",
        range = { 100, 1500 },
        increment = 50,
        value = State.tracerDistance,
        callback = function(v) State.tracerDistance = v end,
    })
    visuals:CreateButton({
        name = "Hide / Restore Buildings",
        callback = function() toggleLocalBuildings() end,
    })
    pcall(function() movement:CreateSection({ name = "Vehicle" }) end)
    movement:CreateToggle({
        name = "Vehicle Speed",
        flag = "vehicleSpeed",
        value = State.vehicleSpeedEnabled,
        callback = function(v)
            State.vehicleSpeedEnabled = v
            State.vehicleRoot = nil
        end,
    })
    movement:CreateToggle({
        name = "Vehicle Fly",
        flag = "vehicleFly",
        value = State.vehicleFly,
        callback = function(v) State.vehicleFly = v end,
    })
    movement:CreateToggle({
        name = "Vehicle Spin",
        flag = "vehicleSpin",
        value = State.vehicleSpin,
        callback = function(v) State.vehicleSpin = v end,
    })
    movement:CreateToggle({
        name = "Building Noclip",
        flag = "vehicleNoclip",
        value = State.vehicleNoclip,
        callback = function(v)
            State.vehicleNoclip = v
            if not v then restoreVehicleNoclip() end
        end,
    })
    movement:CreateToggle({
        name = "Auto Roadkill",
        flag = "autoRoadkill",
        value = State.autoRoadkill,
        callback = function(v) State.autoRoadkill = v end,
    })
    movement:CreateSlider({
        name = "Vehicle Speed Cap",
        flag = "vehicleTargetSpeed",
        range = { 20, 110 },
        increment = 5,
        value = State.vehicleTargetSpeed,
        suffix = " studs/s",
        callback = function(v) State.vehicleTargetSpeed = v end,
    })
    pcall(function() settings:CreateSection({ name = "Menu" }) end)
    settings:CreateKeybind({
        name = "Toggle Menu",
        flag = "menuKey",
        value = Enum.KeyCode.Insert,
        callback = function()
            if not window then return end
            menuVisible = not menuVisible
            if menuVisible then
                pcall(function() window:Show() end)
            else
                pcall(function() window:Hide() end)
            end
        end,
    })
    settings:CreateButton({
        name = "Unload Script",
        callback = function()
            if State.Unload then State:Unload("menu") end
            pcall(function()
                if window and window.Destroy then window:Destroy() end
            end)
        end,
    })
end
table.insert(State.connections, UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not State.active then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        if not window then return end
        menuVisible = not menuVisible
        if menuVisible then
            pcall(function() window:Show() end)
        else
            pcall(function() window:Hide() end)
        end
    end
end))
table.insert(State.connections, RunService.RenderStepped:Connect(function(deltaTime)
    if not State.active then return end
    State.frameMs = State.frameMs * 0.9 + math.min(deltaTime * 1000, 100) * 0.1
    if fovCircle then
        pcall(function()
            Camera = Workspace.CurrentCamera or Camera
            if Camera then
                local vp = Camera.ViewportSize
                fovCircle.Position = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
                fovCircle.Radius = State.fovRadius
                fovCircle.Visible = State.silentAim or State.triggerbot
            end
        end)
    end
    if triggerCircle then
        pcall(function()
            Camera = Workspace.CurrentCamera or Camera
            if Camera then
                local vp = Camera.ViewportSize
                triggerCircle.Position = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
                triggerCircle.Radius = State.triggerRadius
                triggerCircle.Visible = State.triggerbot
            end
        end)
    end
    if State.localBuildingsHidden and os.clock() >= State.nextBuildingRefreshAt then
        State.nextBuildingRefreshAt = os.clock() + 1.5
        refreshHiddenBuildings()
    end
    local defenseScanned = false
    if State.autoDefense and os.clock() >= State.nextDefenseScanAt then
        State.nextDefenseScanAt = os.clock() + 0.18
        local started = os.clock()
        scanDefenseThreats()
        State.perfDefenseMs = State.perfDefenseMs * 0.7 + (os.clock() - started) * 300
        defenseScanned = true
    end
    if State.autoDefense and State.defenseTarget and not defenseScanned then
        rotateToDefenseTarget()
    end
    local triggerDue = State.triggerbot and os.clock() >= State.nextTriggerAt
    if not triggerDue and not defenseScanned and os.clock() >= State.nextVisualAt then
        State.nextVisualAt = os.clock() + (State.frameMs > 7 and 0.10 or (State.frameMs > 5 and 0.07 or 0.05))
        local started = os.clock()
        if updateVisuals then updateVisuals() end
        State.perfVisualMs = State.perfVisualMs * 0.7 + (os.clock() - started) * 300
    end
    if triggerDue then
        local started = os.clock()
        local data = targetData(State.triggerRadius, State.aimDistance,
            State.profile == "legit" or (State.visibility and not State.penetrationAudit))
        if data then
            State.currentTarget = data.player
            State.currentPart = data.part
            local tool = equippedWeapon()
            local weapon = liveWeaponData(tool)
            local assessment = safeAssessShot(data, equippedWeaponOrigin(tool), weapon)
            State.shotAssessment = assessment
            State.nextTriggerAt = os.clock() + math.max(State.triggerDelay,
                weapon and math.min(0.15, weapon.fireInterval * 0.5) or State.triggerDelay)
            local ready = legitReady(data, assessment, equippedWeaponOrigin(tool), Camera.CFrame.LookVector)
            if assessment.canFire and ready then triggerOnce() end
        else
            State.nextTriggerAt = os.clock() + State.triggerDelay
        end
        State.perfTriggerMs = State.perfTriggerMs * 0.7 + (os.clock() - started) * 300
    end
    local vehicle, root
    local vehicleProbeActive = State.vehicleSpeedEnabled or State.vehicleFly
        or State.vehicleSpin or State.vehicleNoclip or State.autoRoadkill
    if vehicleProbeActive then
        if os.clock() >= State.nextVehicleLookupAt then
            State.nextVehicleLookupAt = os.clock() + 0.05
            State.cachedVehicle, State.cachedVehicleRoot,
                State.cachedVehicleSeat, State.cachedVehicleIsDriver = occupiedVehicleRoot()
        end
        vehicle, root = State.cachedVehicle, State.cachedVehicleRoot
    end
    if State.vehicleNoclip then
        applyVehicleNoclip(vehicle)
    elseif State.vehicleNoclipVehicle then
        restoreVehicleNoclip()
    end
    if State.vehicleSpeedEnabled or State.vehicleFly or State.vehicleSpin or State.autoRoadkill then
        if vehicle and root then
            State.vehicleRoot = root
            if State.autoRoadkill then
                driveTowardRoadkillTarget(root)
            elseif State.vehicleFly then
                flyOccupiedVehicle(root)
            elseif State.vehicleSpeedEnabled then
                local velocity = root.AssemblyLinearVelocity
                local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
                if horizontal.Magnitude >= 3 then
                    root.AssemblyLinearVelocity = horizontal.Unit * State.vehicleTargetSpeed + Vector3.new(0, velocity.Y, 0)
                end
            end
            if State.vehicleSpin then
                root.AssemblyAngularVelocity = Vector3.new(0, math.rad(VEHICLE_SPIN_DEGREES), 0)
            end
        end
    end
end))
table.insert(State.connections, Players.PlayerRemoving:Connect(function(player)
    if State.defenseTarget == player then releaseDefenseTarget("target left") end
    local visual = State.playerDrawings[player]
    if visual then
        for _, object in pairs(visual) do removeDrawing(object) end
        State.playerDrawings[player] = nil
    end
end))
function State:Unload(reason)
    if not self.active then return end
    self.autoDefense = false
    releaseDefenseTarget("unload")
    self.active = false
    releaseFire()
    restoreVehicleNoclip()
    restoreLocalBuildings()
    for _, connection in ipairs(self.connections) do pcall(function() connection:Disconnect() end) end
    for _, cleanup in ipairs(self.cleanups) do pcall(cleanup) end
    for _, object in ipairs(self.drawings) do removeDrawing(object) end
    self.drawings = {}
    pcall(function()
        if window and window.Destroy then window:Destroy() end
    end)
    print("[ballistics probe] unloaded" .. (reason and (": " .. tostring(reason)) or ""))
end
log("loaded Rayfield Gen2 — INSERT toggles menu | route=" .. tostring(State.volleyRoute))
