local addonName = ...

local LAYOUT_VERSION = 8

local DEFAULTS = {
    layoutVersion = LAYOUT_VERSION,
    -- Global Nudge offsets
    nudgeX = -6.0,
    nudgeY = 0.0,
    -- Concentric Portrait Circle Center
    portraitCX = 58.5,
    portraitCY = 53.9,
    -- Horizontal span
    xStart = 30.0,
    xEnd = 215.0,
    -- Vertical bottom bounds & blend ratio
    leftBottomY = 10.8,
    rightBottomY = 17.2,
    filletRatio = 0.55,
    -- Border color & shine
    borderR = 0.61,
    borderG = 0.44,
    borderB = 0.20,
    borderHighlight = 1.00,
    -- Display & Weapon Options
    behindPlayerFrame = true,
    showText = true,
    showOffhand = true,
    enableRanged = true,
    hideOutOfCombat = false,
    oocAlpha = 1.0,
    combatAlpha = 1.0,
    -- Bar fill colors (Top highlight / Bottom shadow for smooth GPU vertical gradient)
    mhColorTop = { r = 1.00, g = 0.84, b = 0.25, a = 1.0 },
    mhColorBot = { r = 0.72, g = 0.42, b = 0.04, a = 1.0 },
    ohColorTop = { r = 0.50, g = 0.88, b = 1.00, a = 1.0 },
    ohColorBot = { r = 0.12, g = 0.45, b = 0.75, a = 1.0 },
    rangedColorTop = { r = 1.00, g = 0.84, b = 0.25, a = 1.0 },
    rangedColorBot = { r = 0.72, g = 0.42, b = 0.04, a = 1.0 },
}

-- Safe number sanitizer for WoW Forever 1.60.1 secret-value restrictions
local function SafeNumber(val, fallback)
    if val == nil then return fallback end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, val)
        if ok and secret then return fallback end
    end
    if scrubsecretvalues then
        local ok, scrubbed = pcall(scrubsecretvalues, val)
        if ok then val = scrubbed end
    end
    local ok, num = pcall(function()
        local n = tonumber(val)
        return math.max(n, n)
    end)
    if ok and type(num) == "number" then
        return num
    end
    return fallback
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function CopyDefaults(src, dst)
    dst = dst or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, type(dst[k]) == "table" and dst[k] or {})
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function ResetToDefaults()
    PFST_Settings = {}
    CopyDefaults(DEFAULTS, PFST_Settings)
end

local function DisablePixelSnap(tex)
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
    end
    if tex.SetTexelSnappingBias then
        tex:SetTexelSnappingBias(0)
    end
end

local function MakeSmoothTexture(tex, r, g, b, a)
    tex:SetColorTexture(Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), Clamp(a or 1.0, 0, 1))
    DisablePixelSnap(tex)
end

local function MakeSmoothGradient(tex, rBot, gBot, bBot, aBot, rTop, gTop, bTop, aTop)
    rBot, gBot, bBot, aBot = Clamp(rBot, 0, 1), Clamp(gBot, 0, 1), Clamp(bBot, 0, 1), Clamp(aBot or 1, 0, 1)
    rTop, gTop, bTop, aTop = Clamp(rTop, 0, 1), Clamp(gTop, 0, 1), Clamp(bTop, 0, 1), Clamp(aTop or 1, 0, 1)
    tex:SetColorTexture(1, 1, 1, 1)
    DisablePixelSnap(tex)
    if tex.SetGradient and CreateColor then
        local ok = pcall(
            tex.SetGradient,
            tex,
            "VERTICAL",
            CreateColor(rBot, gBot, bBot, aBot),
            CreateColor(rTop, gTop, bTop, aTop)
        )
        if ok then return end
    end
    tex:SetColorTexture((rBot + rTop) * 0.5, (gBot + gTop) * 0.5, (bBot + bTop) * 0.5, aTop)
end

local ON_SWING_SPELLS = {
    [78] = true, [284] = true, [285] = true, [1608] = true, [11564] = true,
    [11565] = true, [11566] = true, [11567] = true, [25286] = true, [29707] = true, [30324] = true, -- Heroic Strike
    [845] = true, [7369] = true, [11608] = true, [11609] = true, [20569] = true, [25231] = true, -- Cleave
    [1464] = true, [8820] = true, [11604] = true, [11605] = true, [25241] = true, [25242] = true, -- Slam
    [6807] = true, [6808] = true, [6809] = true, [8972] = true, [9745] = true, [9880] = true, [9881] = true, -- Maul
    [2973] = true, [14260] = true, [14261] = true, [14262] = true, [14263] = true, [14264] = true, [14265] = true, [14266] = true, [27014] = true, -- Raptor Strike
}

-- Auto Shot (75), Wand Shoot (5019), Throw (2764)
local RANGED_RESET_SPELLS = {
    [75] = true,
    [5019] = true,
    [2764] = true,
}

local state = {
    mode = "MELEE", -- "MELEE" or "RANGED"
    inCombat = false,
    mhSpeed = 2.0,
    mhDuration = 2.0,
    mhRemaining = 0,
    ohSpeed = 0,
    ohDuration = 2.0,
    ohRemaining = 0,
    hasOffhand = false,
    rangedSpeed = 2.5,
    rangedDuration = 2.5,
    rangedRemaining = 0,
    autoRepeating = false,
    extraAttack = false,
    mhWeaponID = nil,
    ohWeaponID = nil,
    rangedWeaponID = nil,
    -- 0 = Off, 1 = 2H Melee Test, 2 = Dual-Wield Test, 3 = Ranged/Wand Test
    testMode = 0,
}

local SLICE_STEP = 0.5
local MAX_SLICES = 420

local barFrame
local settingsCategoryID
local slices = {}
local activeSliceCount = 0

-- Computes the exact concentric circle + tangent parabolic fillet bottom & visible top at X
local function GetContourBounds(x)
    local s = PFST_Settings
    local cx          = s.portraitCX or 58.5
    local cy          = s.portraitCY or 53.9
    local leftY       = s.leftBottomY or 10.8
    local rightY      = s.rightBottomY or 17.2
    local filletRatio = Clamp(s.filletRatio or 0.55, 0.20, 0.90)

    -- Outer radius of the swing bar's bottom edge, concentric with the Portrait Ring
    local rOuter = math.max(15.0, cy - leftY)
    local totalRise = rightY - leftY

    local yBottom
    if totalRise <= 0.05 then
        local dx = x - cx
        local sq = math.max(0, (rOuter * rOuter) - (dx * dx))
        yBottom = math.min(rightY, cy - math.sqrt(sq))
    else
        local y1 = leftY + totalRise * filletRatio
        local dy1 = cy - y1
        local dx1Sq = math.max(0.5, (rOuter * rOuter) - (dy1 * dy1))
        local dx1 = math.sqrt(dx1Sq)
        local x1 = cx + dx1
        local m1 = dx1 / math.max(1.0, dy1)
        local remRise = rightY - y1
        local filletSpan = (2.0 * remRise) / math.max(0.05, m1)
        local x2 = x1 + filletSpan

        if x <= x1 then
            local dx = x - cx
            local sq = math.max(0, (rOuter * rOuter) - (dx * dx))
            yBottom = cy - math.sqrt(sq)
        elseif x < x2 then
            local t = (x - x1) / filletSpan
            yBottom = y1 + remRise * (2.0 * t - t * t)
        else
            yBottom = rightY
        end
    end

    -- Keep the far-left tip tucked inside the Level circle's gold rim
    if x < 41.5 then
        local dxL = x - 25.3
        local sqL = (16.2 * 16.2) - (dxL * dxL)
        if sqL > 0 then
            local yLevelRim = 25.5 - math.sqrt(sqL)
            if yBottom < yLevelRim then
                yBottom = yLevelRim
            end
        end
    end

    -- Exact visible top boundary where PlayerFrame's Portrait Ring (R=32.2) and Mana Bar border (Y=25.1) sit
    local rPortrait = 32.2
    local frameFlatY = 25.1
    local yVisTop = frameFlatY
    local dxP = x - cx
    if dxP < rPortrait and dxP > -rPortrait then
        local yPortraitEdge = cy - math.sqrt((rPortrait * rPortrait) - (dxP * dxP))
        if yPortraitEdge < frameFlatY then
            yVisTop = yPortraitEdge
        end
    end

    if yVisTop < yBottom + 2.0 then
        yVisTop = yBottom + 2.0
    end

    -- Extend actual texture slice 2.2 units behind PlayerFrame's opaque gold border so there is zero seam
    local yTop = yVisTop + 2.2

    return yBottom, yTop, yVisTop
end

local function UpdateWeaponSpeeds()
    local mh, oh = UnitAttackSpeed("player")
    mh = SafeNumber(mh, state.mhSpeed or 2.0)
    oh = SafeNumber(oh, 0)

    if mh and mh > 0 then
        if state.mhSpeed > 0 and mh ~= state.mhSpeed and state.mhRemaining > 0 then
            local scale = mh / state.mhSpeed
            state.mhRemaining = state.mhRemaining * scale
            state.mhDuration = state.mhDuration * scale
        end
        state.mhSpeed = mh
    end

    if oh and oh > 0 then
        state.hasOffhand = true
        if state.ohSpeed > 0 and oh ~= state.ohSpeed and state.ohRemaining > 0 then
            local scale = oh / state.ohSpeed
            state.ohRemaining = state.ohRemaining * scale
            state.ohDuration = state.ohDuration * scale
        end
        state.ohSpeed = oh
    else
        state.hasOffhand = false
        state.ohSpeed = 0
        state.ohRemaining = 0
    end

    if UnitRangedDamage then
        local rSpeed = UnitRangedDamage("player")
        rSpeed = SafeNumber(rSpeed, state.rangedSpeed or 2.5)
        if rSpeed and rSpeed > 0 then
            if state.rangedSpeed > 0 and rSpeed ~= state.rangedSpeed and state.rangedRemaining > 0 then
                local scale = rSpeed / state.rangedSpeed
                state.rangedRemaining = state.rangedRemaining * scale
                state.rangedDuration = state.rangedDuration * scale
            end
            state.rangedSpeed = rSpeed
        end
    end
end

local function StartMainHand(duration)
    state.mode = "MELEE"
    UpdateWeaponSpeeds()
    local d = SafeNumber(duration, state.mhSpeed) or state.mhSpeed
    state.mhDuration = math.max(d, state.mhSpeed)
    state.mhRemaining = d
end

local function StartOffHand(duration)
    state.mode = "MELEE"
    UpdateWeaponSpeeds()
    if not state.hasOffhand then return end
    local d = SafeNumber(duration, state.ohSpeed) or state.ohSpeed
    state.ohDuration = math.max(d, state.ohSpeed)
    state.ohRemaining = d
end

local function StartRanged(duration)
    if not PFST_Settings.enableRanged then return end
    state.mode = "RANGED"
    UpdateWeaponSpeeds()
    local d = SafeNumber(duration, state.rangedSpeed) or state.rangedSpeed
    if not d or d <= 0 then d = 2.5 end
    state.rangedDuration = math.max(d, state.rangedSpeed or d)
    state.rangedRemaining = d
end

local function RefreshSliceFillColors()
    if not PFST_Settings then return end
    local isRanged = (state.testMode == 3) or (state.testMode == 0 and state.mode == "RANGED")
    local topCol = isRanged and PFST_Settings.rangedColorTop or PFST_Settings.mhColorTop
    local botCol = isRanged and PFST_Settings.rangedColorBot or PFST_Settings.mhColorBot
    local ohTop  = PFST_Settings.ohColorTop
    local ohBot  = PFST_Settings.ohColorBot

    for i = 1, activeSliceCount do
        local s = slices[i]
        if s then
            MakeSmoothGradient(s.mh, botCol.r, botCol.g, botCol.b, botCol.a, topCol.r, topCol.g, topCol.b, topCol.a)
            MakeSmoothGradient(s.oh, ohBot.r, ohBot.g, ohBot.b, ohBot.a, ohTop.r, ohTop.g, ohTop.b, ohTop.a)
        end
    end
end

local function ApplyBarGeometry()
    if not barFrame or not PlayerFrame then return end

    local cfg = PFST_Settings
    local nudgeX = (cfg.nudgeX ~= nil) and cfg.nudgeX or -6.0
    local nudgeY = (cfg.nudgeY ~= nil) and cfg.nudgeY or 0.0
    local xStart = cfg.xStart or 30.0
    local xEnd   = cfg.xEnd or 215.0

    if cfg.behindPlayerFrame then
        if PlayerFrame:GetFrameStrata() == "BACKGROUND" then
            PlayerFrame:SetFrameStrata("LOW")
        end
        barFrame:SetParent(UIParent)
        barFrame:SetFrameStrata("BACKGROUND")
        barFrame:SetFrameLevel(1)
        barFrame:SetScale(PlayerFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    else
        barFrame:SetParent(PlayerFrame)
        barFrame:SetFrameStrata(PlayerFrame:GetFrameStrata())
        barFrame:SetFrameLevel(math.max(1, PlayerFrame:GetFrameLevel() + 1))
        barFrame:SetScale(1)
    end

    barFrame:ClearAllPoints()
    barFrame:SetPoint("BOTTOMLEFT", PlayerFrame, "BOTTOMLEFT", nudgeX, nudgeY)
    barFrame:SetSize(240, 40)

    local span = math.max(20, xEnd - xStart)
    activeSliceCount = math.min(MAX_SLICES, math.floor(span / SLICE_STEP))

    local bR = cfg.borderR or 0.61
    local bG = cfg.borderG or 0.44
    local bB = cfg.borderB or 0.20
    local hi = cfg.borderHighlight or 1.00

    local hiR, hiG, hiB = Clamp(bR * hi, 0, 1), Clamp(bG * hi, 0, 1), Clamp(bB * hi, 0, 1)
    local shR, shG, shB = bR * 0.55, bG * 0.52, bB * 0.48
    local dkR, dkG, dkB = bR * 0.18, bG * 0.16, bB * 0.14

    for i = 1, MAX_SLICES do
        local s = slices[i]
        if i <= activeSliceCount then
            local x = xStart + (i - 1) * SLICE_STEP
            local yBot, yTop, yVisTop = GetContourBounds(x)
            local yBotPrev = GetContourBounds(x - SLICE_STEP)
            local yBotNext = GetContourBounds(x + SLICE_STEP)

            -- Exact slope dy/dx and secant factor sqrt(1 + m^2) so perpendicular border width is uniform
            local slope = (yBotNext - yBotPrev) / (2.0 * SLICE_STEP)
            local secant = math.min(1.35, math.sqrt(1.0 + slope * slope))

            local h = yTop - yBot
            local visH = math.max(2.0, yVisTop - yBot)
            local w = SLICE_STEP + 0.03

            s.x = x
            s.yBot = yBot
            s.yTop = yTop
            s.yVisTop = yVisTop
            s.h = h
            s.visH = visH

            -- 1. Recessed dark trough
            s.bg:ClearAllPoints()
            s.bg:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", x, yBot)
            s.bg:SetSize(w, h)
            s.bg:Show()

            -- 2. Top inner recess shadow right under the visible Portrait / Mana Bar edge
            s.topShadow:ClearAllPoints()
            s.topShadow:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", x, yVisTop + 0.3)
            s.topShadow:SetSize(w, 1.6)
            s.topShadow:Show()

            -- 3. Multi-layered metallic border with secant slope compensation
            local isCurved = (math.abs(slope) > 0.01)

            s.botInnerDark:ClearAllPoints()
            s.botInnerDark:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", x, yBot + 0.4)
            s.botInnerDark:SetSize(w, 0.7 * secant)
            s.botInnerDark:Show()

            local uH = 1.1 * secant
            local lH = 1.8 * secant
            local oH = 0.9 * secant

            MakeSmoothGradient(s.botUpperBevel, hiR, hiG, hiB, 1.0, bR * 0.88, bG * 0.88, bB * 0.88, 1.0)
            s.botUpperBevel:ClearAllPoints()
            s.botUpperBevel:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", x, yBot - 0.1)
            s.botUpperBevel:SetSize(w, uH)
            s.botUpperBevel:Show()

            MakeSmoothGradient(s.botLowerBevel, shR, shG, shB, 1.0, hiR, hiG, hiB, 1.0)
            s.botLowerBevel:ClearAllPoints()
            s.botLowerBevel:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", x, yBot - 0.1 - uH * 0.9)
            s.botLowerBevel:SetSize(w, lH)
            s.botLowerBevel:Show()

            local outerTopY = yBot - 0.1 - uH * 0.9 - lH * 0.92
            MakeSmoothTexture(s.botOuterEdge, dkR, dkG, dkB, 0.96)
            s.botOuterEdge:ClearAllPoints()
            s.botOuterEdge:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", x, outerTopY)
            s.botOuterEdge:SetSize(w, oH)
            s.botOuterEdge:Show()

            if isCurved then
                MakeSmoothTexture(s.botAAFeather, dkR, dkG, dkB, 0.42)
                s.botAAFeather:ClearAllPoints()
                s.botAAFeather:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", x, outerTopY - oH * 0.75)
                s.botAAFeather:SetSize(w, 0.7)
                s.botAAFeather:Show()
            else
                s.botAAFeather:Hide()
            end

            -- 4. Off-Hand bottom track & Main-Hand track scaled to visible channel height
            local ohH = math.max(2.4, visH * 0.38)
            s.ohH = ohH
            s.w = w

            s.oh:ClearAllPoints()
            s.oh:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", x, yBot)
            s.oh:SetSize(w, ohH)

            s.ohDivider:ClearAllPoints()
            s.ohDivider:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", x, yBot + ohH)
            s.ohDivider:SetSize(w, 0.8)

            s.mh:ClearAllPoints()
            s.mh:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", x, yBot)
            s.mh:SetSize(w, h)
        else
            s.bg:Hide()
            s.topShadow:Hide()
            s.botInnerDark:Hide()
            s.botUpperBevel:Hide()
            s.botLowerBevel:Hide()
            s.botOuterEdge:Hide()
            s.botAAFeather:Hide()
            s.mh:Hide()
            s.oh:Hide()
            s.ohDivider:Hide()
        end
    end

    RefreshSliceFillColors()

    -- Right vertical end-cap aligned with xEnd
    local yBotEnd, yTopEnd, yVisTopEnd = GetContourBounds(xEnd)
    local capHeight = (yVisTopEnd - yBotEnd) + 4.4

    MakeSmoothTexture(barFrame.rightCapOuter, dkR, dkG, dkB, 0.98)
    barFrame.rightCapOuter:ClearAllPoints()
    barFrame.rightCapOuter:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", xEnd - 0.2, yBotEnd - 3.4)
    barFrame.rightCapOuter:SetSize(3.4, capHeight)

    MakeSmoothTexture(barFrame.rightCapGold, bR, bG, bB, 1.0)
    barFrame.rightCapGold:ClearAllPoints()
    barFrame.rightCapGold:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", xEnd + 0.5, yBotEnd - 2.6)
    barFrame.rightCapGold:SetSize(2.0, capHeight - 1.4)

    MakeSmoothTexture(barFrame.rightCapHighlight, hiR, hiG, hiB, 1.0)
    barFrame.rightCapHighlight:ClearAllPoints()
    barFrame.rightCapHighlight:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", xEnd + 1.0, yBotEnd - 1.8)
    barFrame.rightCapHighlight:SetSize(0.9, capHeight - 2.8)

    barFrame.timerText:ClearAllPoints()
    barFrame.timerText:SetPoint("RIGHT", barFrame, "BOTTOMLEFT", xEnd - 3, yBotEnd + (yVisTopEnd - yBotEnd) * 0.5)
end

local function CreatePlayerFrameSwingBar()
    if barFrame or not PlayerFrame then return end

    barFrame = CreateFrame("Frame", "PFST_SwingBarFrame", UIParent)

    PlayerFrame:HookScript("OnShow", function() if barFrame then barFrame:Show() end end)
    PlayerFrame:HookScript("OnHide", function() if barFrame then barFrame:Hide() end end)

    for i = 1, MAX_SLICES do
        local s = {}

        s.bg = barFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        MakeSmoothTexture(s.bg, 0.09, 0.07, 0.04, 0.94)

        s.mh = barFrame:CreateTexture(nil, "ARTWORK", nil, 1)
        s.oh = barFrame:CreateTexture(nil, "ARTWORK", nil, 2)

        s.ohDivider = barFrame:CreateTexture(nil, "ARTWORK", nil, 3)
        MakeSmoothTexture(s.ohDivider, 0.04, 0.03, 0.01, 0.90)
        s.ohDivider:Hide()

        s.topShadow = barFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        MakeSmoothTexture(s.topShadow, 0.04, 0.03, 0.01, 0.72)

        s.botInnerDark = barFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        MakeSmoothTexture(s.botInnerDark, 0.12, 0.09, 0.04, 0.85)

        s.botUpperBevel = barFrame:CreateTexture(nil, "BORDER", nil, 4)
        s.botLowerBevel = barFrame:CreateTexture(nil, "BORDER", nil, 3)
        s.botOuterEdge  = barFrame:CreateTexture(nil, "BORDER", nil, 2)
        s.botAAFeather  = barFrame:CreateTexture(nil, "BORDER", nil, 1)

        slices[i] = s
    end

    barFrame.rightCapOuter     = barFrame:CreateTexture(nil, "BORDER", nil, 2)
    barFrame.rightCapGold      = barFrame:CreateTexture(nil, "BORDER", nil, 3)
    barFrame.rightCapHighlight = barFrame:CreateTexture(nil, "BORDER", nil, 4)

    barFrame.mhSpark = barFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    barFrame.mhSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    barFrame.mhSpark:SetBlendMode("ADD")

    barFrame.ohSpark = barFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    barFrame.ohSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    barFrame.ohSpark:SetBlendMode("ADD")
    barFrame.ohSpark:Hide()

    barFrame.timerText = barFrame:CreateFontString(nil, "OVERLAY", nil, 6)
    barFrame.timerText:SetFont("Fonts\\FRIZQT__.ttf", 8, "OUTLINE")
    barFrame.timerText:SetTextColor(1.0, 0.92, 0.55, 1.0)

    ApplyBarGeometry()

    local lastColorMode = "MELEE"

    barFrame:SetScript("OnUpdate", function(self, elapsed)
        if state.testMode > 0 then
            state.mhDuration = 2.6
            state.mhRemaining = state.mhRemaining - elapsed
            if state.mhRemaining <= 0 then state.mhRemaining = state.mhDuration end

            state.ohDuration = 1.7
            state.ohRemaining = state.ohRemaining - elapsed
            if state.ohRemaining <= 0 then state.ohRemaining = state.ohDuration end

            state.rangedDuration = 2.8
            state.rangedRemaining = state.rangedRemaining - elapsed
            if state.rangedRemaining <= 0 then state.rangedRemaining = state.rangedDuration end
        else
            if state.mhRemaining > 0 then
                state.mhRemaining = math.max(0, state.mhRemaining - elapsed)
            end
            if state.ohRemaining > 0 then
                state.ohRemaining = math.max(0, state.ohRemaining - elapsed)
            end
            if state.rangedRemaining > 0 then
                state.rangedRemaining = math.max(0, state.rangedRemaining - elapsed)
            end
        end

        local isRangedMode = (state.testMode == 3) or (state.testMode == 0 and state.mode == "RANGED" and PFST_Settings.enableRanged)
        local curColorMode = isRangedMode and "RANGED" or "MELEE"
        if curColorMode ~= lastColorMode then
            lastColorMode = curColorMode
            RefreshSliceFillColors()
        end

        local showOH = false
        if state.testMode == 2 then
            showOH = true
        elseif not isRangedMode and state.hasOffhand and PFST_Settings.showOffhand then
            showOH = true
        end

        local primaryRem = isRangedMode and state.rangedRemaining or state.mhRemaining
        local primaryDur = isRangedMode and state.rangedDuration or state.mhDuration
        if not primaryDur or primaryDur <= 0 then primaryDur = 2.0 end

        local primaryProgress = Clamp(1 - (primaryRem / primaryDur), 0, 1)
        if primaryRem <= 0 and state.testMode == 0 then
            primaryProgress = 1.0
        end
        local primaryFullSlices = math.floor(primaryProgress * activeSliceCount)

        local ohDenom = (state.ohDuration > 0) and state.ohDuration or 1.7
        local ohProgress = Clamp(1 - (state.ohRemaining / ohDenom), 0, 1)
        if state.ohRemaining <= 0 and state.testMode == 0 then
            ohProgress = 1.0
        end
        local ohFullSlices = showOH and math.floor(ohProgress * activeSliceCount) or 0

        for i = 1, activeSliceCount do
            local s = slices[i]
            if showOH then
                s.mh:ClearAllPoints()
                s.mh:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", s.x, s.yBot + s.ohH)
                s.mh:SetSize(s.w, math.max(1.5, s.h - s.ohH))
                s.ohDivider:Show()
            else
                s.mh:ClearAllPoints()
                s.mh:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", s.x, s.yBot)
                s.mh:SetSize(s.w, s.h)
                s.ohDivider:Hide()
            end

            if i <= primaryFullSlices then
                s.mh:Show()
            else
                s.mh:Hide()
            end

            if showOH and i <= ohFullSlices then
                s.oh:Show()
            else
                s.oh:Hide()
            end
        end

        if primaryProgress > 0.01 and primaryProgress < 0.995 and activeSliceCount > 0 then
            local idx = Clamp(primaryFullSlices + 1, 1, activeSliceCount)
            local s = slices[idx]
            local baseBot = showOH and (s.yBot + s.ohH) or s.yBot
            local trackH = showOH and math.max(2, s.visH - s.ohH) or s.visH
            local sparkH = math.min(trackH, 10)
            self.mhSpark:SetSize(14, sparkH + 8)
            self.mhSpark:ClearAllPoints()
            self.mhSpark:SetPoint("CENTER", self, "BOTTOMLEFT", s.x, baseBot + trackH * 0.5)
            self.mhSpark:Show()
        else
            self.mhSpark:Hide()
        end

        if showOH and ohProgress > 0.01 and ohProgress < 0.995 and activeSliceCount > 0 then
            local idx = Clamp(ohFullSlices + 1, 1, activeSliceCount)
            local s = slices[idx]
            self.ohSpark:SetSize(11, s.ohH + 5)
            self.ohSpark:ClearAllPoints()
            self.ohSpark:SetPoint("CENTER", self, "BOTTOMLEFT", s.x, s.yBot + s.ohH * 0.5)
            self.ohSpark:Show()
        else
            self.ohSpark:Hide()
        end

        if PFST_Settings.showText and primaryRem > 0.05 then
            self.timerText:SetText(string.format("%.1f", primaryRem))
        else
            self.timerText:SetText("")
        end

        local activeSwing = (primaryRem > 0.05) or (showOH and state.ohRemaining > 0.05) or (state.testMode > 0)
        if state.inCombat or activeSwing or state.autoRepeating then
            self:SetAlpha(PFST_Settings.combatAlpha or 1.0)
        elseif PFST_Settings.hideOutOfCombat then
            self:SetAlpha(0)
        else
            self:SetAlpha(PFST_Settings.oocAlpha or 1.0)
        end
    end)
end

-- ============================================================================
-- ADDON SETTINGS MENU (Options -> AddOns -> PlayerFrame Swing Timer)
-- ============================================================================
local function OpenColorPicker(colorTopKey, colorBotKey, swatchTex)
    local top = PFST_Settings[colorTopKey]
    local startR, startG, startB, startA = top.r, top.g, top.b, top.a or 1.0

    local function ApplyColor(r, g, b, a)
        PFST_Settings[colorTopKey] = { r = r, g = g, b = b, a = a }
        PFST_Settings[colorBotKey] = { r = r * 0.62, g = g * 0.52, b = b * 0.35, a = a }
        swatchTex:SetColorTexture(r, g, b, a)
        RefreshSliceFillColors()
    end

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = startR,
            g = startG,
            b = startB,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                ApplyColor(r, g, b, 1.0)
            end,
            cancelFunc = function()
                ApplyColor(startR, startG, startB, startA)
            end,
        })
    end
end

local function InitializeSettingsPanel()
    local panel = CreateFrame("Frame", "PFST_SettingsCanvas", UIParent)
    panel:SetSize(620, 560)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("PlayerFrame Swing Timer")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Concentric PlayerFrame-hugging swing timer for Melee, Off-Hand, Ranged, and Wands (/pfst).")

    panel.sliders = {}
    panel.checkboxes = {}
    panel.swatches = {}

    -- Left Column: Concentric Circle & Border Sliders
    local sliderDefs = {
        { key = "portraitCX",      label = "Portrait Center X",     min = 35.0, max = 70.0, step = 0.5 },
        { key = "portraitCY",      label = "Portrait Center Y",     min = 42.0, max = 66.0, step = 0.5 },
        { key = "leftBottomY",     label = "Portrait Curve Bottom", min = 6.0,  max = 20.0, step = 0.2 },
        { key = "rightBottomY",    label = "Straight Bar Bottom",   min = 10.0, max = 22.0, step = 0.2 },
        { key = "filletRatio",     label = "Curve-to-Bar Blend",    min = 0.25, max = 0.85, step = 0.05 },
        { key = "xStart",          label = "Left Start X",          min = 20.0, max = 48.0, step = 0.5 },
        { key = "xEnd",            label = "Right End X",           min = 185,  max = 230,  step = 0.5 },
        { key = "nudgeX",          label = "Global Nudge X",        min = -20,  max = 20,   step = 0.5 },
        { key = "nudgeY",          label = "Global Nudge Y",        min = -20,  max = 20,   step = 0.5 },
        { key = "borderR",         label = "Border Red",            min = 0.20, max = 1.00, step = 0.01 },
        { key = "borderG",         label = "Border Green",          min = 0.15, max = 1.00, step = 0.01 },
        { key = "borderB",         label = "Border Blue",           min = 0.05, max = 1.00, step = 0.01 },
        { key = "borderHighlight", label = "Border Shine",          min = 0.80, max = 1.80, step = 0.02 },
    }

    for idx, def in ipairs(sliderDefs) do
        local yOff = -58 - (idx - 1) * 32

        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 18, yOff)
        lbl:SetText(def.label)

        local valText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valText:SetPoint("TOPLEFT", 285, yOff)

        local slider = CreateFrame("Slider", "PFST_OptSlider_" .. def.key, panel, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 140, yOff + 2)
        slider:SetSize(135, 14)
        slider:SetMinMaxValues(def.min, def.max)
        slider:SetValueStep(def.step)
        slider:SetObeyStepOnDrag(true)
        _G[slider:GetName() .. "Low"]:SetText("")
        _G[slider:GetName() .. "High"]:SetText("")
        _G[slider:GetName() .. "Text"]:SetText("")

        slider:SetScript("OnValueChanged", function(self, val)
            local rounded = math.floor((val / def.step) + 0.5) * def.step
            PFST_Settings[def.key] = rounded
            valText:SetText(string.format(def.step < 0.1 and "%.2f" or "%.1f", rounded))
            ApplyBarGeometry()
        end)

        panel.sliders[def.key] = { slider = slider, valText = valText, step = def.step }
    end

    -- Right Column: Behavior Checkboxes & Color Pickers
    local rightHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightHeader:SetPoint("TOPLEFT", 355, -58)
    rightHeader:SetText("Display & Weapon Options")

    local checkDefs = {
        { key = "showText",          label = "Show Countdown Timer Text" },
        { key = "showOffhand",       label = "Show Off-Hand Dual-Wield Track" },
        { key = "enableRanged",      label = "Enable Ranged & Wand Auto-Shot" },
        { key = "behindPlayerFrame", label = "Tuck Top Seam Behind PlayerFrame" },
        { key = "hideOutOfCombat",   label = "Hide Bar When Out of Combat" },
    }

    for idx, cdef in ipairs(checkDefs) do
        local cb = CreateFrame("CheckButton", "PFST_Check_" .. cdef.key, panel, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 352, -82 - (idx - 1) * 28)
        _G[cb:GetName() .. "Text"]:SetText(" " .. cdef.label)
        cb:SetScript("OnClick", function(self)
            PFST_Settings[cdef.key] = self:GetChecked() and true or false
            ApplyBarGeometry()
        end)
        panel.checkboxes[cdef.key] = cb
    end

    local colorHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorHeader:SetPoint("TOPLEFT", 355, -240)
    colorHeader:SetText("Bar Fill Colors")

    local colorDefs = {
        { topKey = "mhColorTop",     botKey = "mhColorBot",     label = "Main-Hand Bar Color" },
        { topKey = "ohColorTop",     botKey = "ohColorBot",     label = "Off-Hand Bar Color" },
        { topKey = "rangedColorTop", botKey = "rangedColorBot", label = "Ranged / Wand Bar Color" },
    }

    for idx, col in ipairs(colorDefs) do
        local btn = CreateFrame("Button", nil, panel)
        btn:SetSize(18, 18)
        btn:SetPoint("TOPLEFT", 356, -266 - (idx - 1) * 28)

        local border = btn:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(1, 1, 1, 0.9)

        local swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetAllPoints()

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        txt:SetText(col.label)

        btn:SetScript("OnClick", function()
            OpenColorPicker(col.topKey, col.botKey, swatch)
        end)

        panel.swatches[col.topKey] = swatch
    end

    local testLabels = {
        [0] = "Preview Mode: Off",
        [1] = "Preview: 2H Melee",
        [2] = "Preview: Dual-Wield",
        [3] = "Preview: Ranged / Wand",
    }

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(175, 24)
    testBtn:SetPoint("TOPLEFT", 355, -365)
    testBtn:SetText(testLabels[state.testMode])
    testBtn:SetScript("OnClick", function(self)
        state.testMode = (state.testMode + 1) % 4
        state.mhRemaining = 2.6
        state.ohRemaining = 1.7
        state.rangedRemaining = 2.8
        self:SetText(testLabels[state.testMode])
        RefreshSliceFillColors()
    end)

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(175, 24)
    resetBtn:SetPoint("TOPLEFT", 355, -398)
    resetBtn:SetText("Restore Default Settings")

    local function RefreshPanelControls()
        for key, item in pairs(panel.sliders) do
            local v = PFST_Settings[key]
            if v == nil then v = DEFAULTS[key] end
            item.slider:SetValue(v)
            item.valText:SetText(string.format(item.step < 0.1 and "%.2f" or "%.1f", v))
        end
        for key, cb in pairs(panel.checkboxes) do
            cb:SetChecked(PFST_Settings[key])
        end
        for topKey, swatch in pairs(panel.swatches) do
            local c = PFST_Settings[topKey] or DEFAULTS[topKey]
            swatch:SetColorTexture(c.r, c.g, c.b, c.a or 1)
        end
        testBtn:SetText(testLabels[state.testMode])
    end

    resetBtn:SetScript("OnClick", function()
        ResetToDefaults()
        RefreshPanelControls()
        ApplyBarGeometry()
    end)

    panel:SetScript("OnShow", RefreshPanelControls)
    panel.default = function()
        ResetToDefaults()
        RefreshPanelControls()
        ApplyBarGeometry()
    end

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "PlayerFrame Swing Timer")
        settingsCategoryID = category:GetID()
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        panel.name = "PlayerFrame Swing Timer"
        InterfaceOptions_AddCategory(panel)
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_SWING")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("UNIT_ATTACK_SPEED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("START_AUTOREPEAT_SPELL")
eventFrame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            PFST_Settings = PFST_Settings or {}
            if PFST_Settings.layoutVersion ~= LAYOUT_VERSION then
                ResetToDefaults()
            else
                CopyDefaults(DEFAULTS, PFST_Settings)
            end
            CreatePlayerFrameSwingBar()
            InitializeSettingsPanel()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        CreatePlayerFrameSwingBar()
        ApplyBarGeometry()
        state.mhWeaponID = GetInventoryItemID("player", 16)
        state.ohWeaponID = GetInventoryItemID("player", 17)
        state.rangedWeaponID = GetInventoryItemID("player", 18)
        UpdateWeaponSpeeds()
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
    elseif event == "START_AUTOREPEAT_SPELL" then
        state.autoRepeating = true
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        state.autoRepeating = false
    elseif event == "PLAYER_SWING" then
        state.testMode = 0
        local swingDuration, swingType = ...
        local isMH = (Enum and Enum.PlayerSwingType and swingType == Enum.PlayerSwingType.MainHand) or (swingType == 0)
        local isOH = (Enum and Enum.PlayerSwingType and swingType == Enum.PlayerSwingType.OffHand) or (swingType == 1)
        local isRanged = (Enum and Enum.PlayerSwingType and swingType == Enum.PlayerSwingType.Ranged) or (swingType == 2)

        if isMH then
            StartMainHand(swingDuration)
        elseif isOH then
            StartOffHand(swingDuration)
        elseif isRanged then
            StartRanged(swingDuration)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and RANGED_RESET_SPELLS[spellID] then
            state.testMode = 0
            StartRanged()
        end
    elseif event == "UNIT_ATTACK_SPEED" then
        local unit = ...
        if unit == "player" then
            UpdateWeaponSpeeds()
        end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then
            local newMH = GetInventoryItemID("player", 16)
            local newOH = GetInventoryItemID("player", 17)
            local newRanged = GetInventoryItemID("player", 18)
            if newMH ~= state.mhWeaponID then
                state.mhWeaponID = newMH
                StartMainHand()
            end
            if newOH ~= state.ohWeaponID then
                state.ohWeaponID = newOH
                StartOffHand()
            end
            if newRanged ~= state.rangedWeaponID then
                state.rangedWeaponID = newRanged
                UpdateWeaponSpeeds()
            end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if C_CombatLog and C_CombatLog.IsCombatLogRestricted and C_CombatLog.IsCombatLogRestricted() then return end

        local _, subEvent, _, srcGUID, _, _, _, destGUID, _, _, _, arg12, arg13 = CombatLogGetCurrentEventInfo()
        if issecretvalue and issecretvalue(srcGUID) then return end

        local playerGUID = UnitGUID("player")
        if srcGUID == playerGUID then
            if subEvent == "SPELL_EXTRA_ATTACKS" then
                state.extraAttack = true
            elseif subEvent == "SWING_DAMAGE" and not (Enum and Enum.PlayerSwingType) then
                state.testMode = 0
                local isOffHand = select(21, CombatLogGetCurrentEventInfo())
                if isOffHand then
                    StartOffHand()
                else
                    if not state.extraAttack then StartMainHand() end
                    state.extraAttack = false
                end
            elseif subEvent == "SWING_MISSED" and not (Enum and Enum.PlayerSwingType) then
                state.testMode = 0
                local isOffHand = arg13
                if isOffHand then
                    StartOffHand()
                else
                    if not state.extraAttack then StartMainHand() end
                    state.extraAttack = false
                end
            elseif subEvent == "RANGE_DAMAGE" or subEvent == "RANGE_MISSED" then
                if not (Enum and Enum.PlayerSwingType) then
                    state.testMode = 0
                    StartRanged()
                end
            elseif subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_MISSED" then
                if ON_SWING_SPELLS[arg12] and not (Enum and Enum.PlayerSwingType) then
                    state.testMode = 0
                    StartMainHand()
                end
            end
        elseif destGUID == playerGUID and subEvent == "SWING_MISSED" and arg12 == "PARRY" then
            local minTime = state.mhSpeed * 0.20
            if state.mhRemaining > minTime then
                state.mhRemaining = math.max(minTime, state.mhRemaining - (state.mhSpeed * 0.40))
            end
        end
    end
end)

SLASH_PFST1 = "/pfst"
SLASH_PFST2 = "/playerframeswingtimer"
SlashCmdList["PFST"] = function(msg)
    local cmd = (msg or ""):match("^(%S*)")
    cmd = (cmd or ""):lower()

    if cmd == "test" then
        state.testMode = (state.testMode + 1) % 4
        state.mhRemaining = 2.6
        state.ohRemaining = 1.7
        state.rangedRemaining = 2.8
        RefreshSliceFillColors()
        local names = { [0] = "OFF", [1] = "2H Melee", [2] = "Dual-Wield", [3] = "Ranged / Wand" }
        print("|cff00ffb0PFST:|r Preview mode: " .. names[state.testMode])
    elseif cmd == "reset" then
        ResetToDefaults()
        ApplyBarGeometry()
        print("|cff00ffb0PFST:|r Restored default settings.")
    else
        if Settings and Settings.OpenToCategory and settingsCategoryID then
            Settings.OpenToCategory(settingsCategoryID)
        elseif InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("PlayerFrame Swing Timer")
            InterfaceOptionsFrame_OpenToCategory("PlayerFrame Swing Timer")
        end
    end
end