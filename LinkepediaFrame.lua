------------------------------------------------------
-- LinkepediaFrame.lua
-- The frame code for Linkepedia
------------------------------------------------------

-- PROGRESS FRAME --

LNKPDFrame_FrameState = "IDLE";
local LNKPDFrame_OrigBarWidth = 0;

function LNKPDFrame_SetIdleState()
    LNKPDFrame_FrameState = "IDLE";
    LNKPDFrame_BuildCache_Cancel:SetText("Rebuild");
    LNKPDFrame_SetStatusText(" > Idle Scanning", "", "")
    LNKPDFrame_SetActiveStatus(1);
end

function LNKPDFrame_SetBuildState()
    LNKPDFrame_FrameState = "BUILD";
    LNKPDFrame_BuildCache_Cancel:SetText("Cancel");
    LNKPDFrame_SetActiveStatus(1);
end

function LNKPDFrame_BuildCache_OnLoad()
    LNKPDFrame_OrigBarWidth = LNKPDFrame_BuildCache_ProgressBar:GetWidth();
    LNKPDFrame_SetIdleState();
end

function LNKPDFrame_BuildCache_Cancel_OnClick()
    if(LNKPDFrame_FrameState == "BUILD") then
        LNKPD_CancelBuild();
        LNKPDFrame_BuildCache_Cancel:SetText("Rebuild");
        LNKPDFrame_SetStatusText(" > Idle Scanning", "", "")
        LNKPDFrame_SetActiveStatus(1);

    elseif(LNKPDFrame_FrameState == "IDLE") then
        LNKPD_RebuildCache();
        LNKPDFrame_BuildCache_Cancel:SetText("Cancel");
        LNKPDFrame_FrameState = "BUILD";
    end
end

function LNKPDFrame_BuildCache_HideWindow_OnClick()
    LNKPDFrame_BuildCache:Hide();
end

function LNKPDFrame_ShowBuild()
    LNKPDFrame_BuildCache:Show();
    LNKPDFrame_BuildCache:ClearAllPoints();
    LNKPDFrame_BuildCache:SetPoint("CENTER", 0, 0);

end

function LNKPDFrame_SetStatusText(one, two, three)
    LNKPDFrame_BuildCache_Status1:SetText(one);
    LNKPDFrame_BuildCache_Status2:SetText(two);
    LNKPDFrame_BuildCache_Status3:SetText(three);
end

function LNKPDFrame_SetActiveStatus(val)
    LNKPDFrame_BuildCache_Status1:SetTextColor(0.5, 0.5, 0.5);
    LNKPDFrame_BuildCache_Status2:SetTextColor(0.5, 0.5, 0.5);
    LNKPDFrame_BuildCache_Status3:SetTextColor(0.5, 0.5, 0.5);

    _G["LNKPDFrame_BuildCache_Status" .. val]:SetTextColor(0.0, 1.0, 0.0);
end

function LNKPDFrame_SetPercentage(val)
    LNKPDFrame_BuildCache_Percent:SetText(string.format("%.2f", val * 100) .. "%");
    local newWidth = LNKPDFrame_OrigBarWidth * val;
    LNKPDFrame_BuildCache_ProgressBar:SetWidth(newWidth);
end

function LNKPDFrame_SetLinksFound(val)
    LNKPDFrame_BuildCache_LinksFound:SetText("Items Found: " .. LNKPDUtils.CommaValue(val));
end

-- WELCOME FRAME --
function LNKPDFrame_ShowWelcome()
    LNKPDFrame_Welcome:Show();
    LNKPDFrame_BuildCache:ClearAllPoints();
    LNKPDFrame_BuildCache:SetPoint("CENTER", 0, 0);
end

function LNKPDFrame_Welcome_Build_OnClick()
    LNKPDFrame_Welcome:Hide();
    LNKPD_RebuildCache();
end

function LNKPDFrame_Welcome_Close_OnClick()
    LNKPDFrame_Welcome:Hide();
end

-- Update Frame
function LNKPDFrame_ShowUpdate()
    LNKPDFrame_Update:Show();
    LNKPDFrame_BuildCache:ClearAllPoints();
    LNKPDFrame_BuildCache:SetPoint("CENTER", 0, 0);   
end

function LNKPDFrame_Update_Close_OnClick()
    LNKPDFrame_Update:Hide();
end