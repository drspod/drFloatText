
local DrFloatText = {}
local FloatText = Apollo.GetAddon("FloatText")

local drfInstance = nil

function DrFloatText:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function DrFloatText:Init()
    Apollo.RegisterAddon(self, false, nil, {"FloatText"})
    self.options = {
        strFontFace = "CRB_FloaterSmall",
        bSeparateShieldDamage = false,
        bDropTallUnits = true,
        nDropTallUnitOffset = 180,
        fMinPercentile = 0.0,
        fMinHighlightPercentile = 0.8,
        nSampleWindowSize = 100,
        fHighlightLingerTime = 0.7,
        fBaseSpeed = 5.0,
        tColors = {
            ["Player Damage"] = {["normal"] = "0xff6d6d", ["crit"] = "0xffab3d"},
            ["Target Damage"] = {["normal"] = "0xe5feff", ["crit"] = "0xfffb93"},
            ["Player Heal"] = {["normal"] = "0xb0ff6a", ["crit"] = "0xc6ff94"},
            ["Target Heal"] = {["normal"] = "0xb0ff6a", ["crit"] = "0xcdffa0"},
            ["Player Shield Heal"] = {["normal"] = "0x6afff3", ["crit"] = "0xa6fff8"},
            ["Target Shield Heal"] = {["normal"] = "0x6afff3", ["crit"] = "0xc9fffb"},
            ["Vulnerable Damage"] = {["normal"] = "0xf5a2ff"},
        }
    }
    self.damageSamples = {}
    self.windowPtr = 1
end

function DrFloatText:OnLoad()
    FloatText.OnDamageOrHealing = self.OnDamageOrHealing
    FloatText.OnPlayerDamageOrHealing = self.OnPlayerDamageOrHealing
    FloatText.GetDefaultTextOption = self.GetDefaultTextOption
end

function DrFloatText:OnDamageOrHealing(unitCaster, unitTarget, eDamageType, nDamage, nShieldDamaged, nAbsorptionAmount, bCritical)
    if unitTarget == nil or not Apollo.GetConsoleVariable("ui.showCombatFloater") or nDamage == nil then
        return
    end

    if GameLib.IsControlledUnit(unitTarget) or unitTarget == GameLib.GetPlayerMountUnit() or GameLib.IsControlledUnit(unitTarget:GetUnitOwner()) then
        self:OnPlayerDamageOrHealing(unitTarget, eDamageType, nDamage, nShieldDamaged, nAbsorptionAmount, bCritical)
        return
    end

    if type(nAbsorptionAmount) == "number" and nAbsorptionAmount > 0 then
        local tTextOptionAbsorb = drfInstance:GetTargetAbsorbTextOptions()
        CombatFloater.ShowTextFloater(unitTarget, String_GetWeaselString(Apollo.GetString("FloatText_Absorbed"), nAbsorptionAmount), tTextOptionAbsorb)
        if nDamage <= 0 then
            return
        end
    end

    local fDamagePercentile = drfInstance:GetDamagePercentile(nDamage)
    local bHighlight = fDamagePercentile > drfInstance:GetSettings().fMinHighlightPercentile

    if fDamagePercentile < drfInstance:GetSettings().fMinPercentile then
        return
    end

    local tTextOption = drfInstance:GetDamageOrHealTextOptions(unitTarget, eDamageType, bCritical, bHighlight, fDamagePercentile)

    if eDamageType == GameLib.CodeEnumDamageType.Heal or eDamageType == GameLib.CodeEnumDamageType.HealShields then
        CombatFloater.ShowTextFloater(unitTarget, String_GetWeaselString(Apollo.GetString("FloatText_PlusValue"), nDamage), tTextOption)
    else
        if not drfInstance:GetSettings().bSeparateShieldDamage then
            nDamage = nDamage + nShieldDamaged
            nShieldDamaged = 0
        end
        CombatFloater.ShowTextFloater(unitTarget, nDamage, nShieldDamaged, tTextOption)
    end
end

function DrFloatText:OnPlayerDamageOrHealing(unitPlayer, eDamageType, nDamage, nShieldDamaged, nAbsorptionAmount, bCritical)
    if unitPlayer == nil or not Apollo.GetConsoleVariable("ui.showCombatFloater") or nDamage == nil then
        return
    end

    if type(nAbsorptionAmount) == "number" and nAbsorptionAmount > 0 then
        local tTextOptionAbsorb = drfInstance:GetPlayerAbsorbTextOptions()
        CombatFloater.ShowTextFloater(unitPlayer, String_GetWeaselString(Apollo.GetString("FloatText_Absorbed"), nAbsorptionAmount), tTextOptionAbsorb)
        if nDamage <= 0 then
            return
        end
    end

    local tTextOption = drfInstance:GetPlayerDamageOrHealTextOptions(eDamageType, bCritical)

    if eDamageType == GameLib.CodeEnumDamageType.Heal or eDamageType == GameLib.CodeEnumDamageType.HealShields then
        CombatFloater.ShowTextFloater(unitPlayer, String_GetWeaselString(Apollo.GetString("FloatText_PlusValue"), nDamage), tTextOption)
    else
        if not drfInstance:GetSettings().bSeparateShieldDamage then
            nDamage = nDamage + nShieldDamaged
            nShieldDamaged = 0
        end
        CombatFloater.ShowTextFloater(unitPlayer, nDamage, nShieldDamaged, tTextOption)
    end
end

function DrFloatText:GetSettings()
    return self.options
end

function DrFloatText:GetDamageOrHealTextOptions(unitTarget, eDamageType, bCritical, bHighlight, fDamagePercentile)
    local options = self:GetDefaultTextOption()
    options.eCollisionMode = bHighlight and CombatFloater.CodeEnumFloaterCollisionMode.Vertical or CombatFloater.CodeEnumFloaterCollisionMode.IgnoreCollision
    options.strFontFace = self:GetSettings().strFontFace
    options.eLocation = (not self:GetSettings().bDropTallUnits or unitTarget:GetOverheadAnchor().y > self:GetSettings().nDropTallUnitOffset)
            and CombatFloater.CodeEnumFloaterLocation.Top or CombatFloater.CodeEnumFloaterLocation.Bottom
    options.arFrames = self:GetDamageOrHealAnimation(unitTarget, eDamageType, bCritical, bHighlight, fDamagePercentile)
    return options
end

function DrFloatText:GetDamageOrHealAnimation(unitTarget, eDamageType, bCritical, bHighlight, fDamagePercentile)
    local nBaseColor = self:GetColor(unitTarget, false, eDamageType, bCritical)
    local fMaxSize = 1.0
    local fBaseSpeed = self:GetSettings().fBaseSpeed
    local fHighlightDelay = bHighlight and
            (self:GetSettings().fHighlightLingerTime * (fDamagePercentile - self:GetSettings().fMinHighlightPercentile) / (1 - self:GetSettings().fMinHighlightPercentile))
            or 0.0

    return {
            [1] = {fTime = 0,                     fAlpha = 1.0, fScale = fMaxSize * (bHighlight and 1.8 or 1.3), fVelocityMagnitude = bHighlight and 0.0 or fBaseSpeed, fVelocityDirection = 0.0, nColor = nBaseColor},
            [2] = {fTime = fHighlightDelay,                     fScale = fMaxSize * (bHighlight and 1.8 or 1.3), fVelocityMagnitude = bHighlight and 0.0 or fBaseSpeed},
            [3] = {fTime = fHighlightDelay + 0.15,              fScale = fMaxSize,                               fVelocityMagnitude = fBaseSpeed},
            [4] = {fTime = fHighlightDelay + 0.5, fAlpha = 1.0},
            [5] = {fTime = fHighlightDelay + 0.7, fAlpha = 0.0},
    }
end

function DrFloatText:GetTargetAbsorbTextOptions()
    local options = self:GetDefaultTextOption()
    options.fScale = 1.0
    options.fDuration = 2
    options.eCollisionMode = CombatFloater.CodeEnumFloaterCollisionMode.IgnoreCollision
    options.eLocation = CombatFloater.CodeEnumFloaterLocation.Chest
    options.fOffset = -0.8
    options.fOffsetDirection = 0
    options.arFrames = {
            [1] = {fTime = 0,   fScale = 1.1, fAlpha = 1.0, nColor = 0xb0b0b0},
            [2] = {fTime = 0.1, fScale = 0.7},
            [3] = {fTime = 0.8,               fAlpha = 1.0},
            [4] = {fTime = 0.9,               fAlpha = 0.0},
    }
    return options
end

function DrFloatText:GetPlayerDamageOrHealTextOptions(eDamageType, bCritical)
    local options = self:GetDefaultTextOption()
    options.eCollisionMode = CombatFloater.CodeEnumFloaterCollisionMode.IgnoreCollision
    options.eLocation = (eDamageType == GameLib.CodeEnumDamageType.Heal or eDamageType == GameLib.CodeEnumDamageType.HealShields)
            and CombatFloater.CodeEnumFloaterLocation.Top or CombatFloater.CodeEnumFloaterLocation.Back
    options.strFontFace = self:GetSettings().strFontFace
    options.arFrames = self:GetPlayerDamageOrHealAnimation(eDamageType, bCritical)
    return options
end

function DrFloatText:GetPlayerDamageOrHealAnimation(eDamageType, bCritical)
    local nBaseColor = self:GetColor(nil, true, eDamageType, bCritical)
    local fMaxSize = bCritical and 1.5 or 1.0
    local nStallTime = 0.3
    local fDirection = (eDamageType == GameLib.CodeEnumDamageType.Heal or eDamageType == GameLib.CodeEnumDamageType.HealShields) and 0 or 180

    return {
            [1] = {fTime = 0,                 fScale = fMaxSize * 0.75,               nColor = nBaseColor},
            [2] = {fTime = 0.05,              fScale = fMaxSize * 1.5},
            [3] = {fTime = 0.1,               fScale = fMaxSize},
            [4] = {fTime = 0.3 + nStallTime,                            fAlpha = 1.0, fVelocityDirection = fDirection, fVelocityMagnitude = 3},
            [5] = {fTime = 0.65 + nStallTime,                           fAlpha = 0.2},
    }
end

function DrFloatText:GetPlayerAbsorbTextOptions()
    local nStallTime = 0.3
    local options = self:GetDefaultTextOption()
    options.nColor = 0xf8f3d7
    options.eCollisionMode = CombatFloater.CodeEnumFloaterCollisionMode.IgnoreCollision
    options.eLocation = CombatFloater.CodeEnumFloaterLocation.Chest
    options.fOffsetDirection = 0
    options.fOffset = -0.5
    options.arFrames = {
            [1] = {fTime = 0,                 fScale = 1.1},
            [2] = {fTime = 0.05,              fScale = 0.7},
            [3] = {fTime = 0.2 + nStallTime,                fAlpha = 1.0, fVelocityDirection = 180, fVelocityMagnitude = 3},
            [4] = {fTime = 0.45 + nStallTime,               fAlpha = 0.2},
    }
    return options
end

function DrFloatText:GetColor(unitTarget, bIsPlayer, eDamageType, bCritical)
    local tColors = self:GetSettings().tColors
    local prefix = bIsPlayer and "Player " or "Target "
    local severity = bCritical and "crit" or "normal"

    if eDamageType == GameLib.CodeEnumDamageType.Heal then
        return tColors[prefix .. "Heal"][severity]
    elseif eDamageType == GameLib.CodeEnumDamageType.HealShields then
        return tColors[prefix .. "Shield Heal"][severity]
    elseif not bIsPlayer and unitTarget:IsInCCState(Unit.CodeEnumCCState.Vulnerability) then
        return tColors["Vulnerable Damage"]["normal"]
    else
        return tColors[prefix .. "Damage"][severity]
    end
end

-- this is a horrible way to compute a moving percentile, but if we keep the window small then it should be fine
function DrFloatText:GetDamagePercentile(nDamage)
    if nDamage == 0 then
        return 0
    end

    local p = percentile(self.damageSamples, nDamage)
    self.damageSamples[self.windowPtr] = nDamage
    self.windowPtr = (self.windowPtr % self:GetSettings().nSampleWindowSize) + 1
    return p
end

function percentile(data, sample)
    if #data == 0 then
        return 0.5
    end

    local tmp = {}
    for _,d in pairs(data) do
        tmp[#tmp + 1] = d
    end
    table.sort(tmp)
    for i,d in pairs(tmp) do
        if d > sample then return i/#tmp end
    end
    return 1.0
end

function DrFloatText:GetDefaultTextOption()
    local tTextOption =
    {
        strFontFace                 = drfInstance:GetSettings().strFontFace,
        fDuration                   = 2,
        fScale                      = 1.0,
        fExpand                     = 1,
        fVibrate                    = 0,
        fSpinAroundRadius           = 0,
        fFadeInDuration             = 0,
        fFadeOutDuration            = 0,
        fVelocityDirection          = 0,
        fVelocityMagnitude          = 0,
        fAccelDirection             = 0,
        fAccelMagnitude             = 0,
        fEndHoldDuration            = 0,
        eLocation                   = CombatFloater.CodeEnumFloaterLocation.Top,
        fOffsetDirection            = 0,
        fOffset                     = -0.5,
        eCollisionMode              = CombatFloater.CodeEnumFloaterCollisionMode.IgnoreCollision,
        fExpandCollisionBoxWidth    = 1,
        fExpandCollisionBoxHeight   = 1,
        nColor                      = 0xFFFFFF,
        iUseDigitSpriteSet          = nil,
        bUseScreenPos               = false,
        bShowOnTop                  = false,
        fRotation                   = 0,
        fDelay                      = 0,
        nDigitSpriteSpacing         = 0,
    }
    return tTextOption
end

drfInstance = DrFloatText:new()
drfInstance:Init()