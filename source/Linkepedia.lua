------------------------------------------------------
-- Linkepedia.lua
-- Based off of original addon, Linkerator, by Gazmik Fizzwidget http://fizzwidget.com/
-- Code updated by Hirsute for WoW 3.3.5 http://ui.wowinterface.com/downloads/info17104-Linkerator.luafor3.3.5.html
-- GhostfromTexas has original author's approval to create Linkepedia based off of Linkerator
------------------------------------------------------

LNKPD_VERSION       = {1, 5, 0};
LNKPD_VERSION_STR   = tostring(LNKPD_VERSION[1]) .. "." .. tostring(LNKPD_VERSION[2]) .. "." .. tostring(LNKPD_VERSION[3]);

LNKPD_RandomPropIDs = { };
LNKPD_RandomItemCombos = { };

LNKPD_Locale = GetLocale();
LNKPD_RandomPropIDs[LNKPD_Locale] = { };
LNKPD_RandomItemCombos[LNKPD_Locale] = { };
local LNKPD_Orig_ChatEdit_OnChar = {};

local LNKPD_SavedVariablesLoaded = false;
local LNKPD_IsQueryMode = false;
local LNKPD_ForceHighlight = false;

-- number greater than the highest known item ID, used to import link names from client cache.
-- may need updating as future patches/expansions add items to the game.
LNKPD_MAX_ITEM_ID               = 134047;
LNKPD_MAX_SPELL_ID              = 200000;
LNKPD_DEFAULT_DELAY             = 0.25;
LNKPD_MAX_TABLE_KEY             = 3;

-- BETA USE ONLY!!! --
local LNKPD_TimeOfLoad = GetTime();
local LNKPD_HasDisplayedBeta = false;

local function EditBoxHooks()
	for i=1,NUM_CHAT_WINDOWS do
		local ChatFrameEditBox = _G["ChatFrame"..i.."EditBox"]
		if not LNKPD_Orig_ChatEdit_OnChar.i then
			LNKPD_Orig_ChatEdit_OnChar.i = ChatFrameEditBox:GetScript("OnChar");
			ChatFrameEditBox:SetScript("OnChar", LNKPD_ChatEdit_OnChar);
		end
	end
end

local function GetFocusedChatFrame()
	local c = DEFAULT_CHAT_FRAME.editBox
	for i=1,NUM_CHAT_WINDOWS do
		local n,_,_,_,_,_,s,_,_,_ = GetChatWindowInfo(i)
		if n and s then c = _G["ChatFrame"..i.."EditBox"] end
	end
	return c
end

------------------------------------------------------
-- Autocompletion in chat edit box
------------------------------------------------------

function LNKPD_ChatEdit_OnChar(self, text)
	local ChatFrameIndex = string.match(GetFocusedChatFrame():GetName(),"%d+")
	if (not LNKPD_ChatEdit_ShouldComplete(self)) then
		LNKPD_ChatCompleteQueued = nil;
		if (LNKPD_Orig_ChatEdit_OnChar.ChatFrameIndex) then return LNKPD_Orig_ChatEdit_OnChar.ChatFrameIndex(self, text); end
	end

	local text = self:GetText();
	local textlen = strlen(text);
    local _, _, query = string.find(text, "%[([^]]-)$");
	if (query and string.len(query) > 0) then
		LNKPD_PartialText = text;
	end

	LNKPD_ChatCompleteQueued = GetTime();
	LNKPD_CompletionBox = self;
end

function LNKPD_ChatEdit_ShouldComplete(editBox)
	local text = editBox:GetText();

	-- If the string is in the format "/cmd blah", command will be "/cmd"
	local command = strmatch(text, "^(/[^%s]+)") or "";
	command = strlower(command);

	-- don't autocomplete in scripts
	for i = 1, 10 do
		if (not getglobal("SLASH_SCRIPT"..i)) then
			break;
		end
		if (command == getglobal("SLASH_SCRIPT"..i)) then
			return;
		end
	end
	if ( command == "/dump" ) then
		return;
	end

	-- don't autocomplete in secure /commands or we'll taint the text and cause the commands to be blocked
	-- item links don't make sense in most of the secure commands anyway
	if (IsSecureCmd(command)) then
		return;
	end

	return true;

end

function LNKPD_ChatEdit_Complete(editBox)

    -- should we complete the link? If yes continue, if not then return
	if (not LNKPD_ChatEdit_ShouldComplete(editBox)) then return; end

	local text = editBox:GetText();

	-- if the text contains any completed (brackets on both sides) links, "linkify" them
    local newText = LNKPD_ParseChatMessage(text);
	if (newText ~= text) then
		editBox:SetText(newText);
		LNKPD_PartialText = nil;
		LNKPD_Matches = nil;
		LNKPD_LastCompletion = nil;
		LNKPD_HighlightStart = nil;
		LNKPD_MatchCount = 0;	-- will get incremented before use
		return;
	end

	-- if we just typed a ']' and had highlighted completion text, finish it
	local _, _, closedPart = string.find(text, "%[([^]]-)%]$");
	if (closedPart and LNKPD_LastCompletion) then
		local lowerQuery = string.lower(closedPart); -- for case insensitive lookups
		if (string.sub(string.lower(LNKPD_LastCompletion), 1, string.len(lowerQuery)) == lowerQuery) then
			local newText = string.gsub(text, "%[([^]]-)%]$", "["..LNKPD_LastCompletion.."]");
		    newText = LNKPD_ParseChatMessage(newText);
			if (newText ~= text) then
				editBox:SetText(newText);
				LNKPD_PartialText = nil;
				LNKPD_Matches = nil;
				LNKPD_LastCompletion = nil;
				LNKPD_HighlightStart = nil;
				return;
			end
		end
	end

	-- otherwise, see if there's a partial link typed and provide highlighted completion
	local textlen = strlen(text);
    local _, _, query = string.find(text, "%[([^]]-)$");
	if (query and string.len(query) > 0) then
		LNKPD_PartialText = text;
		LNKPD_Matches = LNKPD_LinkPrefixMatches(query);
		LNKPD_MatchCount = 1;

		if (LNKPD_Matches and LNKPD_Matches[LNKPD_MatchCount]) then
			local lowerQuery = string.lower(query); -- for case insensitive lookups
			lowerQuery = string.gsub(lowerQuery, "([%$%(%)%.%[%]%*%+%-%?%^%%])", "%%%1"); -- convert regex special characters
			local completion = string.gsub(LNKPD_Matches[LNKPD_MatchCount], "^"..lowerQuery, query);
			local newText = string.gsub(text, "%[([^]]-)$", "["..completion);
			LNKPD_LastCompletion = completion;
			editBox:SetText(newText);
            LNKPD_ForceHighlight = true;
            LNKPD_AllowHighlight = true;
			LNKPD_HighlightStart = textlen;
			return;
		end
	end

end

function LNKPD_ChatEdit_OnTextChanged(self)
	-- if (not LNKPD_ChatEdit_ShouldComplete(self)) then
		-- if (LNKPD_Orig_ChatEdit_OnTextChanged) then return LNKPD_Orig_ChatEdit_OnTextChanged(self); end
	-- end
-- 
	-- local text = self:GetText();
	-- -- reset matches if text has been deleted
	-- if (LNKPD_PartialText and string.len(text) <= string.len(LNKPD_PartialText)) then
		-- LNKPD_HighlightStart = nil;
		-- LNKPD_LastCompletion = nil;
		-- LNKPD_Matches = nil;
		-- LNKPD_MatchCount = 0;	-- will get incremented before use
	-- end
	-- LNKPD_Orig_ChatEdit_OnTextChanged(self);
	-- if (LNKPD_HighlightStart and LNKPD_HighlightStart < string.len(text)) then
		-- LNKPD_ForceHighlight = true;
        -- LNKPD_TimeOfHighlight = GetTime();
	-- end
end

function LNKPD_ChatEdit_OnTabPressed(self)

	if (not LNKPD_ChatEdit_ShouldComplete(self)) then
		if (LNKPD_Orig_ChatEdit_OnTabPressed) then return LNKPD_Orig_ChatEdit_OnTabPressed(); end
	end

	-- if we haven't highlighted text, we don't have matches agains the current query
	if (LNKPD_PartialText and not LNKPD_HighlightStart) then
		LNKPD_PartialText = self:GetText();
		local _, _, query = string.find(LNKPD_PartialText, "%[([^]]-)$");
		if (query and string.len(query) > 0) then
			LNKPD_Matches = LNKPD_LinkPrefixMatches(query);
		end
	end
	if (LNKPD_Matches and table.getn(LNKPD_Matches) > 0) then

		local prefix = LNKPD_CommonPrefixFromList(LNKPD_Matches);

	    local _, _, query = string.find(LNKPD_PartialText, "%[([^]]-)$");
		local lowerQuery = string.lower(query); -- for case insensitive lookups
		lowerQuery = string.gsub(lowerQuery, "([%$%(%)%.%[%]%*%+%-%?%^%%])", "%%%1"); -- convert regex special characters
		if (prefix and string.len(prefix) > string.len(query)) then
			local expandedPrefix = string.gsub(prefix, "^"..lowerQuery, query);
			local newText = string.gsub(LNKPD_PartialText, "%[([^]]-)$", "["..expandedPrefix);
			if (LNKPD_PartialText ~= newText) then
				self:SetText(newText);
				LNKPD_ChatEdit_OnChar(self);
				LNKPD_PartialText = newText;
			    local _, _, newQuery = string.find(LNKPD_PartialText, "%[([^]]-)$");
				if (newQuery and string.len(newQuery) > 0) then
					LNKPD_Matches = LNKPD_LinkPrefixMatches(newQuery);
				end
			end
			return;
		elseif (LNKPD_Matches and table.getn(LNKPD_Matches) > 0) then
			-- we've hit tab and there's no prefix to expand
			LNKPD_MatchCount = LNKPD_MatchCount + 1;
			if (LNKPD_MatchCount > table.getn(LNKPD_Matches)) then
				LNKPD_MatchCount = 1;
			end

			-- if we add a display of the match list, it should go here...

			local completion = string.gsub(LNKPD_Matches[LNKPD_MatchCount], "^"..lowerQuery, query);
			newText = string.gsub(LNKPD_PartialText, "%[([^]]-)$", "["..completion);
			LNKPD_LastCompletion = completion;
			self:SetText(newText);
			local textlen = string.len(LNKPD_PartialText);
			LNKPD_ForceHighlight = true;
            LNKPD_TimeOfHighlight = GetTime();
			LNKPD_HighlightStart = textlen;
			return;
		end
	end
	LNKPD_Orig_ChatEdit_OnTabPressed(self);
end

function LNKPD_ChatEdit_OnEscapePressed(self)
	LNKPD_ResetCompletion();
end

function LNKPD_ChatEdit_OnEnterPressed(self)
	LNKPD_ResetCompletion();
end

function LNKPD_ResetCompletion()
	local ChatFrameEditBox = GetFocusedChatFrame()
	if (LNKPD_ItemCacheFull and not ChatFrameEditBox:IsVisible()) then
		LNKPD_ItemCacheFull = nil;
	end
	LNKPD_PartialText = nil;
	LNKPD_Matches = nil;
	LNKPD_LastCompletion = nil;
	LNKPD_HighlightStart = nil;
	LNKPD_MatchCount = 0;	-- will get incremented before use
end

function LNKPD_SendChatMessage(message, type, language, channel)

	-- TODO: WTB a locale-independent way to identify the Trade channel (or channels in which links are allowed)
	-- for now we allow linkifying in all server channels even though Trade is the only one that allows links
	if (type == "CHANNEL") then
		local _, channelName = GetChannelName(channel);
		if (channelName) then
			local _, _, name1, name2 = string.find(channelName, "^(.-) %- (.-)$");
			local serverChannels = {EnumerateServerChannels()};
			for _, serverChannel in ipairs(serverChannels) do
				if (name1 == serverChannel or name2 == serverChannel) then
					-- if the text contains any completed (brackets on both sides) links, "linkify" them
				    message = LNKPD_ParseChatMessage(message);
					LNKPD_ResetCompletion();
					break;
				end
			end
		end
	else
		-- if the text contains any completed (brackets on both sides) links, "linkify" them
	    message = LNKPD_ParseChatMessage(message);
		LNKPD_ResetCompletion();
	end

	LNKPD_Orig_SendChatMessage(message, type, language, channel);
end

function LNKPD_OnLoad(self)

    -- load slash commands
	SLASH_LNKPD1 = "/linkepedia";
	SlashCmdList["LNKPD"] = function(msg)
		LNKPD_LinkepediaCommand(msg);
	end

    SLASH_LNKPDITEM1 = "/link";
    SlashCmdList["LNKPDITEM"] = function(msg)
		LNKPD_LinkCommand(msg);
	end

	--[[
    SLASH_LNKPDSPELL1 = "/linkspell";
    SlashCmdList["LNKPDSPELL"] = function(msg)
		LNKPD_LinkSpellCommand(msg);
	end
	--]]

	self:RegisterEvent("ADDON_LOADED");
    self:RegisterEvent("VARIABLES_LOADED");
	self:RegisterEvent("UPDATE_CHAT_WINDOWS");

	-- hooks for autocompletion in the edit box
	-- Code edited by Hirsute for 3.3.5 compatibility
	EditBoxHooks();
	LNKPD_Orig_ChatEdit_OnTextChanged = ChatEdit_OnTextChanged;
	ChatEdit_OnTextChanged = LNKPD_ChatEdit_OnTextChanged;
	LNKPD_Orig_ChatEdit_OnTabPressed = ChatEdit_OnTabPressed;
	ChatEdit_OnTabPressed = LNKPD_ChatEdit_OnTabPressed;

	-- hooks for automatic linkifying of other text sent to chat
	LNKPD_Orig_SendChatMessage = SendChatMessage;
	SendChatMessage = LNKPD_SendChatMessage;

	-- hooks for cleaning up after completion
	hooksecurefunc("ChatEdit_OnEscapePressed", LNKPD_ChatEdit_OnEscapePressed);
	hooksecurefunc("ChatEdit_OnEnterPressed", LNKPD_ChatEdit_OnEnterPressed);

end

LNKPD_UpdateInterval = 1;
function LNKPD_OnUpdate(self, elapsed)

    if(GetTime() - LNKPD_TimeOfLoad > 5 and not LNKPD_HasDisplayedBeta) then
        --LNKPDUtils.Print("Linkepedia Beta Message: ");
        --LNKPDUtils.Print("Hey guys, " .. LNKPDUtils.Lite("GhostfromTexas") .. " here with a Linkepedia Beta Update!");
        --LNKPDUtils.Print(LNKPDUtils.Lite("   - ") .. "Fixed the help text to mention the /link and /linkspell commands");
        --LNKPDUtils.Print(LNKPDUtils.Lite("   - ") .. "Fixed frame issue where the progress bar overlapped windows ontop of the frame");
        LNKPD_HasDisplayedBeta = true;
    end
    
    -- if the user is in combat, then do NOTHING.
    if UnitAffectingCombat("player") then return; end;    

    -- Update the current database
    LNKPD_UpdateActiveItemCache();

    -- Highlight text. This MUST come before the completed call
    if(LNKPD_ForceHighlight) then
        LNKPD_ForceHighlight = false;
        LNKPD_CompletionBox:HighlightText(LNKPD_HighlightStart);
    end

    -- check to see if the link being typed needs to be completed
	if (LNKPD_ChatCompleteQueued and GetTime() - LNKPD_ChatCompleteQueued >= LNKPDSV_AutoCompleteDelay) then
		LNKPD_ChatEdit_Complete(LNKPD_CompletionBox);
		LNKPD_ChatCompleteQueued = nil;
	end

	self.TimeSinceLastUpdate = (self.TimeSinceLastUpdate or 0) + elapsed;
	if (self.TimeSinceLastUpdate <= LNKPD_UpdateInterval) then return; end
	self.TimeSinceLastUpdate = 0;

end

function LNKPD_OnEvent(self, event, ...)
	local arg1 = ...;
    if( event == "VARIABLES_LOADED" ) then
        LNKPD_SavedVariablesLoaded = true;
        LNKPD_CheckSavedVariables();
	elseif (event == "UPDATE_CHAT_WINDOWS") then
		EditBoxHooks()
	end
end

function LNKPD_LinkepediaCommand(msg)
    
    -- do not run any commands
    if(LNKPD_SavedVariablesLoaded == false) then
        LINKPDUtils.Print("Linkepedia is not done loading. Please wait!");
        return;
    end

    msg = string.lower(msg);

    local _, _, delay = string.find(msg, "^delay (.+)");

	-- Print Help
	if ( msg == "help" ) or ( msg == "" ) then
		local version = GetAddOnMetadata("Linkepedia", "Version");
		LNKPDUtils.Print("Linkepedia "..version..":");
		LNKPDUtils.Print("/linkepedia <command>");
		LNKPDUtils.Print("- " .. LNKPDUtils.Lite("help")            .. " - Print this helplist.");
        LNKPDUtils.Print("- " .. LNKPDUtils.Lite("rebuild")         .. " - Rebuild the entire database. This is a very laggy process.");
		LNKPDUtils.Print("- " .. LNKPDUtils.Lite("expand")          .. " - Expand the current database to find unfound items. Quicker than Rebuilding.");
        LNKPDUtils.Print("- " .. LNKPDUtils.Lite("cancel")          .. " - Cancel the expanding or rebuilding process.");
        LNKPDUtils.Print("- " .. LNKPDUtils.Lite("show")            .. " - Show the build progress bar window.");
        LNKPDUtils.Print("- " .. LNKPDUtils.Lite("delay <seconds>") .. " - Change the delay before links typed in chat are automatically completed.");
		
        LNKPDUtils.Print("/link <command>");
        LNKPDUtils.Print("- " .. LNKPDUtils.Lite("<item name>")     .. " - Print a hyperlink to the chat window for an item known by name.");
		--LNKPDUtils.Print("- " .. LNKPDUtils.Lite("<item id #>")     .. " - Print a hyperlink to the chat window for a generic item whose ID number is known.");
		--LNKPDUtils.Print("- " .. LNKPDUtils.Lite("<code>")          .. " - Print a hyperlink to the chat window for an item whose complete link code is known.");
		
        --LNKPDUtils.Print("/linkspell <command>");
        --LNKPDUtils.Print("- " .. LNKPDUtils.Lite("<spell name>")     .. " - Print a hyperlink to the chat window for a spell known by name.");
    elseif (msg == "rebuild") or (msg == "reload") or (msg == "build") then
        LNKPD_RebuildCache();
    elseif (msg == "expand") then
        LNKPD_ExpandCache("Expanding");
    elseif (msg == "stop") or (msg == "cancel") then
        LNKPDFrame_BuildCache_Cancel_OnClick();
    elseif (msg == "show") then
        LNKPDFrame_ShowBuild();
    elseif (delay) then
        local _, _, delay = string.find(msg, "^delay (.+)");
        LNKPDSV_AutoCompleteDelay = tonumber(delay)
        LNKPDUtils.Print("Linkepedia: Delay set to " .. LNKPDUtils.Lite(tostring(delay)) .. " - default is " .. LNKPDUtils.Lite(tostring(LNKPD_DEFAULT_DELAY)));
    else
	    -- If we're this far, we probably have bad input.
	    LNKPD_LinkepediaCommand("help");
    end
end

function LNKPD_LinkCommand(msg)
    -- do not run any commands
    if(LNKPD_SavedVariablesLoaded == false) then
        LINKPDUtils.Print("Linkepedia is not done loading. Please wait!");
        return;
    end

    if (msg and msg ~= "") then
        msg = string.lower(msg);

        local linkItem  = true;
        local linkID    = false;
        
        if(string.find(msg, "%-id ") ~= nil) then
            msg = string.gsub(msg, "%-id ", "");
            linkItem = false;
            linkID = true;
        end 
            
		if (LNKPD_PrintLinkSearch(msg, linkItem, false, linkID)) then return; end
	end
end

--[[
function LNKPD_LinkSpellCommand(msg)
    -- do not run any commands
    if(LNKPD_SavedVariablesLoaded == false) then
        LINKPDUtils.Print("Linkepedia is not done loading. Please wait!");
        return;
    end

    if (msg and msg ~= "") then
		if (LNKPD_PrintLinkSearch(msg, false, true, false)) then return; end
	end
end
--]]

function LNKPD_GetItemLink(linkInfo, shouldAdd)
	if (linkInfo == nil) then
		error("invalid argument #1 to LNKPD_GetItemLink()", 2);
	end
	local sName, sLink = GetItemInfo(linkInfo);
	if (sLink and shouldAdd) then
		added = LNKPD_AddLink(sName, sLink); -- add it to our name index if we're getting it from another source
	end
	return sLink;
end

------------------------------------------------------
-- Searching for links
------------------------------------------------------

function LNKPD_PrintLinkSearch(msg, linkItems, linkSpells, linkItemByID)

    local foundCount = 0;

    if(linkItemByID) then
        if(GetItemIcon(msg)) then
            local _, link = GetItemInfo(msg);
            LNKPDUtils.PrintLink(link);
            foundCount = 1;
        else
            LNKPDUtils.Print("'" .. LNKPDUtils.Lite(msg) .. "' is not a valid ID");
            return true;
        end
    end
    --[[
    if(linkItems) then
	    -- if it's just a number, try it as an itemID
	    if (tonumber(msg)) then
		    --DevTools_Dump({msg=msg});
		    local link = LNKPD_GetItemLink(msg, 1);
		    if (link) then
			    LNKPDUtils.Print("Item ID "..msg..": "..link);
		    else
			    LinkepediaTip.printHyperlinkID = 1;
			    LinkepediaTip:SetHyperlink("item:"..msg);
		    end
		    return true;
	    end

	    -- dump code when a full link is provided
	    local _, _, itemLink = string.find(msg, "(item:[-%d:]+)");
	    local _, _, enchantLink = string.find(msg, "(enchant:[-%d:]+)");
	    local _, _, spellLink = string.find(msg, "(spell:[-%d:]+)");
	    local _, _, talentLink = string.find(msg, "(talent:[-%d:]+)");
	    local _, _, questLink = string.find(msg, "(quest:[-%d:]+)");
	    if (itemLink) then
		    --DevTools_Dump({msg=msg, itemLink=itemLink});
		    local link = LNKPD_GetItemLink(itemLink);
		    if (link) then
			    LNKPDUtils.PrintLink(itemLink..": "..link);
		    else
			    LNKPDUtils.PrintLink(itemLink.." is unknown to this WoW client.");
		    end
		    return true;
	    elseif (enchantLink) then
		    --DevTools_Dump({msg=msg, itemLink=itemLink});
		    local _, _, enchantID = string.find(msg, "enchant:(%d+)");
		    local link = LNKPD_EnchantLink(enchantID);
		    if (link) then
			    LNKPDUtils.PrintLink(enchantLink..": "..link);
		    else
			    LNKPDUtils.PrintLink(enchantLink.." is unknown, or not a tradeskill link.");
		    end
		    return true;
	    elseif (spellLink or talentLink or questLink) then
		    local _, _, link = string.find(msg, "(|c%x+.-|h|r)");
		    LNKPDUtils.PrintLink((spellLink or talentLink or questLink)..": "..link);
		    return true;
	    end

	    -- search for basic item links (no random property)
	    msg = string.lower(msg);
    end
    --]]

    if(linkItems) then
	    local itemsFound = LNKPD_SearchItems(msg, true);
	    foundCount = #itemsFound;
    end

    if(linkSpells) then
	    -- search spells
        LNKPD_ResetSpellNamesCache();
	    local spellsFound = LNKPD_SearchSpells(msg, true);
	    foundCount = #spellsFound;
    end

	if (foundCount > 0) then
		LNKPDUtils.Print(LNKPDUtils.Lite(foundCount) .. " links found for '" .. LNKPDUtils.Lite(msg) .. "'");
	else
		LNKPDUtils.Print("Could not find '" .. LNKPDUtils.Lite(msg) .. "' in Linkepedia's item history.");
		LNKPDUtils.Print("Type '" .. LNKPDUtils.Lite("/linkepedia help") .. "' for options.");
	end

	return true;
end

function LNKPD_SearchItems(text, printResults)
	text = string.lower(text);
	local itemsFound = {};

    --for tbl = LNKPD_START_LINK_IDX, LNKPD_END_LINK_IDX do
    for key, val in pairs(LNKPDSV_ActiveItemLink) do
        for idx = 1, getn(val) do    
            local link = LNKPD_RetrieveItem(key, idx);
            local itemName = LNKPDUtils.LinkName(link);
		    
            if (itemName) then
			    itemName = string.lower(itemName);
			    if (string.find(itemName, text, 1, true)) then
				    table.insert(itemsFound, link);

                    if (printResults) then
                        LNKPDUtils.PrintLink(link);
                    end
			    end
		    end
        end
	end

    return itemsFound;
end

function LNKPD_SearchSpells(text, printResults)
	text = string.lower(text);
	local spellsFound = {};
	for spellID = 1, LNKPD_MAX_SPELL_ID do
		local spellName = LNKPD_SpellNamesCache[spellID];
		if (spellName) then
			spellName = string.lower(spellName);
			if (string.find(spellName, text, 1, true)) then
				table.insert(spellsFound, spellID);
			end
		end
	end
	if (printResults and #spellsFound > 0) then
		for _, spellID in pairs(spellsFound) do
			local spellName = GetSpellInfo(spellID);
			local cachedName = LNKPD_SpellNamesCache[spellID];
			local link;
			if (cachedName == spellName) then
				-- it's a regular spell
				link = GetSpellLink(spellID);
			else
				-- it's a tradeskill
				link = LNKPD_EnchantLink(spellID);
			end
			if (LNKPD_Debug) then
				LNKPDUtils.PrintLink(link.." ("..spellID..")");
			else
				LNKPDUtils.PrintLink(link);
			end
		end
	end
	return spellsFound;
end

function LNKPD_GetLinkByName(text)

	-- if the text in brackets is just a number, let it pass unchanged
	if (string.find(text, "^%d+$")) then
		return;
	end

	-- if we're passed some form of link code, just resolve it
	if (string.find(text, "^(item:[-%d:]+)$")) then
		local link = LNKPD_GetItemLink(text);
		if (link) then return link; end
	elseif (string.find(text, "^(enchant:%d+)$")) then
		local _, _, enchantID = string.find(text, "enchant:(%d+)");
		local link = LNKPD_EnchantLink(enchantID);
		if (link) then return link; end
	elseif (string.find(text, "^#%d+$")) then
		local link = LNKPD_GetItemLink(string.sub(text,2));
		if (link) then return link; end
	end

	-- otherwise, we get into searching for matches by name
    local char      = string.upper(string.sub(text, 0, LNKPD_MAX_TABLE_KEY))
	local lowerText = string.lower(text);
	local allResults = {};

	-- try to find exact matches for the text in basic (no random property) items
    if(LNKPDSV_ActiveItemLink[char] ~= nil) then
	    for idx = 1, getn(LNKPDSV_ActiveItemLink[char]) do
            local link = LNKPD_RetrieveItem(char, idx);
		    local itemName = LNKPDUtils.LinkName(link);
		    if (itemName and string.lower(itemName) == lowerText) then
			    if (not returnAll) then
				    return link;
			    else
				    table.insert(allResults, link);
			    end
		    end
	    end
    end

    -- -- no exact matches, so we prepare to look for parenthesized description elements and search based on those
	-- local _, _, name, description = string.find(lowerText, "(.+)%((.-)%)" );
	-- -- 'description' here is some text from the item's tooltip, such as part of a slot name or a stat line
	-- -- e.g. "warblade of the hakkari (main)" or "funky boots of the eagle (11 int)"
	-- if (name and description) then
        -- local char = string.upper(string.sub(name, 0, 1))
		-- name = string.gsub(name, " +$", ""); -- drop trailing spaces
-- 
		-- -- back in the basic (no random property) items, now looking based on description
		-- local basicResults = {};
		-- for idx = 1, getn(LNKPDSV_ActiveItemLink) do
			-- local itemName = LNKPDUtils.LinkName(LNKPD_RetrieveItem(idx));
            -- local link = LNKPD_RetrieveItem(idx);
			-- if (itemName and string.lower(itemName) == name) then
				-- table.insert(basicResults, link);
			-- end
		-- end
		-- if (not returnAll and #basicResults == 1) then
			-- -- only one exact match for the name, no description needed
			-- return basicResults[1];
		-- elseif (#basicResults > 1) then
			-- -- see if the description matches the item type or equip location
			-- for _, link in pairs(basicResults) do
				-- if (LNKPD_ItemLinkMatchesDescriptor(link, description)) then
					-- if (returnAll) then
						-- table.insert(allResults, link);
					-- else
						-- return link;
					-- end
				-- end
			-- end
			-- -- failing that, see if the description matches any text from the item tooltip
			-- for _, link in pairs(basicResults) do
				-- if (LNKPD_FindInItemTooltip(description, link)) then
					-- if (returnAll) then
						-- table.insert(allResults, link);
					-- else
						-- return link;
					-- end
				-- end
			-- end
		-- end
	-- end
        -- 
	-- if (returnAll and table.getn(allResults) > 0) then
		-- return allResults;
	-- end
end

function LNKPD_ItemLinkMatchesDescriptor(itemLink, description)
	-- see if the description matches the item type or equip location
	local name, link, rarity, level, minLevel, type, subType, stackCount, equipLoc, texture = GetItemInfo(itemLink);
	if ((type and string.find(string.lower(type), description, 1, true))
	 or (subType and string.find(string.lower(subType), description, 1, true))
	 or (getglobal(equipLoc) and string.find(string.lower(getglobal(equipLoc)), description, 1, true))) then
		return true;
	end
end

function LNKPD_AddLink(name, link)
	name = string.lower(name); -- so we can do case-insensitive lookups
	local itemID, enchant, gem1, gem2, gem3, gem4, randomProp, uniqueID;
	if (type(link) == "number") then
		itemID = link;
	elseif (type(link) == "string") then
		itemID, enchant, gem1, gem2, gem3, gem4, randomProp, uniqueID = LNKPDUtils.DecomposeItemLink(link);
		if (itemID == nil) then
			itemID = tonumber(link);
		end
	end
	--DevTools_Dump({name=name, link=link, itemID=itemID, randomProp=randomProp})
	if (itemID) then
		LinkepediaTip:SetHyperlink("item:"..itemID);	-- make sure client caches the (base) item
		if (randomProp == 0 or randomProp == nil) then
			return;	-- we don't need our own database for basic links; we can just rely on the WoW client
		else
			return LNKPD_AddRandomPropertyItemLink(name, link);
		end
	end

	-- if we got down to here, it's bad input
	LNKPDUtils.Print("Error: unparseable link passed to LNKPD_AddLink()");
end

function LNKPD_AddRandomPropertyItemLink(name, link)
	local itemID, enchant, gem1, gem2, gem3, gem4, randomProp, uniqueID = LNKPDUtils.DecomposeItemLink(link);
	local cleanLink = LNKPDUtils.BuildItemLink(itemID, nil, nil, nil, nil, nil, randomProp, uniqueID);

	local baseName = GetItemInfo(itemID); -- the item name without the "of the Boar", etc suffix for random property
	if (baseName == nil) then return; end
	local lowerBase = string.lower(baseName);

	local searchBase = string.gsub(lowerBase, "([%$%(%)%.%[%]%*%+%-%?%^%%])", "%%%1"); -- convert regex special characters
	local propertyName = string.gsub(name, searchBase, "%%s"); -- format string for just the suffix (or whatever alteration to the name) with token for inserting the base name
	local existingProp = LNKPD_RandomPropIDs[LNKPD_Locale][randomProp];
	if (existingProp == propertyName) then
		-- these aren't the droids you're looking for
	elseif (existingProp == nil) then
		LNKPD_RandomPropIDs[LNKPD_Locale][randomProp] = propertyName;
	else
		LNKPD_RandomPropIDs[LNKPD_Locale][randomProp] = propertyName;
	end

	local verifiedLink = LNKPD_GetItemLink(cleanLink);
	if (verifiedLink) then
		if (LNKPD_RandomItemCombos[LNKPD_Locale][itemID] == nil) then
			LNKPD_RandomItemCombos[LNKPD_Locale][itemID] = {};
		end
		if (LNKPD_RandomItemCombos[LNKPD_Locale][itemID][randomProp] == nil) then
			LNKPD_RandomItemCombos[LNKPD_Locale][itemID][randomProp] = uniqueID;
		end
	else
		if (LNKPD_RandomItemCombos[LNKPD_Locale][itemID] and LNKPD_RandomItemCombos[LNKPD_Locale][itemID][randomProp]) then
			LNKPD_RandomItemCombos[LNKPD_Locale][itemID][randomProp] = nil;
		end
		if (LNKPDUtils.TableCount(LNKPD_RandomItemCombos[LNKPD_Locale][itemID]) == 0) then
			LNKPD_RandomItemCombos[LNKPD_Locale][itemID] = nil;
		end
	end
end

------------------------------------------------------
-- utilities
------------------------------------------------------

function LNKPD_LinkifyName(head, text, tail)
	if (head ~= "|h" and tail ~= "|h") then -- only linkify things text that isn't linked already
        local link = nil
        local num = tonumber(text);
        if (num) then
            _, link = GetItemInfo(num);
        else
		    link = LNKPD_GetLinkByName(text);
        end
		if (link) then return link; end
	end
	return head.."["..text.."]"..tail;
end

function LNKPD_FindInItemTooltip(text, link)
	LinkepediaTip:ClearLines();
	LinkepediaTip:SetHyperlink(link);
	for lineNum = 1, LinkepediaTip:NumLines() do
		local leftText = getglobal("LinkepediaTipTextLeft"..lineNum):GetText();
		if (leftText and string.find(string.lower(leftText), text, 1, true)) then return true; end
		local rightText = getglobal("LinkepediaTipTextRight"..lineNum):GetText();
		if (rightText and string.find(string.lower(rightText), text, 1, true)) then return true; end
	end
	for lineNum = 1, LinkepediaTip:NumLines() do
		-- for some reason ClearLines alone isn't clearing the right-side text
		getglobal("LinkepediaTipTextLeft"..lineNum):SetText(nil);
		getglobal("LinkepediaTipTextRight"..lineNum):SetText(nil);
	end
end

function LNKPD_ParseChatMessage(text)
    --lnktext = string.sub(text, 2, string.len(text)-1);
    --LNKPDUtils.Print(lnktext);
    --_, link = GetItemInfo(lnktext)
    --if (link and string.find(text, "[", 1, true) and string.find(text, "]", 1, true)) then
        --return link;
    --else
	   return string.gsub(text, "(|?h?)%[(.-)%](|?h?)", LNKPD_LinkifyName);
    --end
end

function LNKPD_LinkPrefixMatches(text)
    local char = string.upper(string.sub(text, 0, LNKPD_MAX_TABLE_KEY));
	text = string.lower(text) -- for case insensitive lookups

	-- build list of known links prefixed with the search string
	local matches = {};
    if (LNKPDSV_ActiveItemLink[char]) then
	    for idx = 1, getn(LNKPDSV_ActiveItemLink[char]) do
		    local name = LNKPDUtils.LinkName(LNKPD_RetrieveItem(char, idx));
		    if (name and string.sub(string.lower(name), 1, string.len(text)) == text) then
			    table.insert(matches, name);
		    end
	    end

	    table.sort(matches);
    end

	return matches;
end

function LNKPD_CommonPrefixFromList(list, minLength)
	if (table.getn(list) == 1) then
		return list[1];
	elseif (table.getn(list) == 2) then
		return LNKPD_CommonPrefix(list[1], list[2]);
	elseif (table.getn(list) > 2) then
		local previousCommon;
		local lastCommon = LNKPD_CommonPrefix(list[1], list[2]);
		local i = 3;
		while (lastCommon) do
			previousCommon = lastCommon;
			lastCommon = LNKPD_CommonPrefix(previousCommon, list[i]);
			if (lastCommon and minLength and string.len(lastCommon) <= minLength) then
				break;
			end
			i = i + 1;
		end
		return previousCommon;
	end
end

function LNKPD_CommonPrefix(strA, strB)

	if (strA == nil or strB == nil) then return; end

    -- shorter string first
    if (string.len(strA) > string.len(strB)) then
        strA, strB = strB, strA;
    end

    for length = string.len(strA), 1, -1 do
        local subA = string.sub(strA, 1, length);
        local subB = string.sub(strB, 1, length);
        if (subA == subB) then
            return subA;
        end
    end
end

-- substitute for GetItemInfo() for "enchant:0000" style links
function LNKPD_GetEnchantInfo(id)
	local name = GetSpellInfo(id);
	if (name) then
		LinkepediaTip:SetHyperlink("spell:"..id);
		local tooltipName = LinkepediaTipTextLeft1:GetText();
		if (name ~= tooltipName) then
			return tooltipName;
		end
	end
end

function LNKPD_EnchantLink(id)
	if (tonumber(id) == nil) then
		error("bad argument #1 to 'LNKPD_EnchantLink' (number expected, got "..type(id)..")", 2);
	end
    local name = LNKPD_GetEnchantInfo(id);
    if (name) then
	    local linkFormat = "|cffffd000|Henchant:%s|h[%s]|h|r";
        return string.format(linkFormat, id, name);
    else
        return nil;
    end
end

function LNKPD_ResetSpellNamesCache()
	LNKPD_SpellNamesCache = {};
	setmetatable(LNKPD_SpellNamesCache, {__index = function(tbl,key)
		local name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange = GetSpellInfo(key);
		local link = GetSpellLink(key);
		if (name and link) then
			return name;
		end
	end});
	LNKPD_SpellCacheFull = true;
end

--[[
    This section is what deals with inserting and remove from tables
--]]

function LNKPD_CacheItem(link)
    local comp = LNKPDUtils.Comp(link);
    local char = string.upper(string.sub(comp, 0, LNKPD_MAX_TABLE_KEY));
    
    if (LNKPDSV_ActiveItemLink[char] == nil) then
        LNKPDSV_ActiveItemLink[char] = {}
    end
    
    table.insert(LNKPDSV_ActiveItemLink[char], comp);
    
end

function LNKPD_RetrieveItem(tbl, idx)
    local data = LNKPDSV_ActiveItemLink[tbl][idx]
    local decomp = LNKPDUtils.Decomp(data);

    return decomp;
end

--[[
    This section is what works on updating the item cache
--]]

local LNKPD_updateMode        = nil;
local LNKPD_updatesPerFrame   = 1;
local LNKPD_currentSearchIDX  = 1;
local LNKPD_linksFound        = 0;
local LNKPD_showResults       = false;
local LNKPD_lastPercPrintTime = GetTime();
local LNKPD_percSecPerPrint   = 5;
local LNKPD_percDenom         = 1;
local LNKPD_percNum           = 0;
local LNKPD_printPrefix       = "";
local LNKPD_prevTimeLag       = 0;
local LNKPD_timeToLag         = 0;
local LNKPD_expandBounceSec   = 2;
local LKNPD_prevExpandTime    = 0;

-- Scan the database for items
function LNKPD_UpdateModeIdleScan()
    
     local currentTime = GetTime();

    local diff = currentTime - LKNPD_prevExpandTime;
    LKNPD_prevExpandTime = currentTime;

    LNKPD_expandBounceSec = LNKPD_expandBounceSec - diff;

    if(LNKPD_expandBounceSec <= 0) then

        LNKPD_expandBounceSec = 2;
        LNKPD_showResults = false;
        LNKPD_updatesPerFrame = 1;

        -- Reset the search idx if it's too high
        if(LNKPD_currentSearchIDX > getn(LNKPDSV_ValidSearchID)) then
            LNKPD_currentSearchIDX = 1;
            LNKPD_percNum   = 0;
            LNKPD_percDenom = getn(LNKPDSV_ValidSearchID);
        end

        -- Search grab an ID we want a link for
        local itemID = LNKPDSV_ValidSearchID[LNKPD_currentSearchIDX];
        local itemName, itemLink = GetItemInfo(itemID);
    
        -- If the ID exists at this point, then cache it
        if(itemName) then
            LNKPD_CacheItem(itemLink, LNKPD_currentSearchIDX);
            table.remove(LNKPDSV_ValidSearchID, LNKPD_currentSearchIDX);
            LNKPD_linksFound = LNKPD_linksFound + 1;
        else
            LNKPD_currentSearchIDX = LNKPD_currentSearchIDX + 1;
        end

        LNKPD_percNum = LNKPD_percNum + 1;

        LNKPDFrame_SetLinksFound(LNKPD_linksFound);
    end
end

function LNKPD_UpdateModeBuild()
    LNKPD_showResults = true
    LNKPD_printPrefix = "Building"

    -- Search grab an ID we want a link for
    local itemID = LNKPDSV_ValidSearchID[LNKPD_currentSearchIDX];
    local itemName, itemLink = GetItemInfo(itemID);

    -- If the item exists, then cache it
    if(itemName) then
        LNKPD_CacheItem(itemLink, LNKPD_currentSearchIDX);
        table.remove(LNKPDSV_ValidSearchID, LNKPD_currentSearchIDX);
        LNKPD_linksFound = LNKPD_linksFound + 1;
    else
        LNKPD_currentSearchIDX = LNKPD_currentSearchIDX + 1;
    end

    LNKPD_percNum = LNKPD_percNum + 1;

    -- if we have found everything, then let's stop building
    if(LNKPD_currentSearchIDX > getn(LNKPDSV_ValidSearchID)) then
        LNKPDUtils.Print(LNKPD_printPrefix .. LNKPDUtils.Lite(" 100%"));
        LNKPDUtils.Print("Links Found: " .. LNKPDUtils.Lite(LNKPD_linksFound));

        LNKPDFrame_SetIdleState();
        LNKPDFrame_BuildCache:Hide();
        
        LNKPD_currentSearchIDX = 1;
        LNKPD_linksFound       = 0;
        LNKPD_showResults      = false;
        LNKPD_updateMode       = LNKPD_UpdateModeIdleScan
        LNKPD_percNum          = 0;
        LNKPD_percDenom        = getn(LNKPDSV_ValidSearchID);
    end
end

-- wait for X numbers of seconds before continuing
function LNKPD_UpdateModeWait()
    LNKPD_currentSearchIDX = getn(LNKPDSV_ValidSearchID);
    LNKPDFrame_SetActiveStatus(2);
    
    local currentTime = GetTime();
    local diff = currentTime - LNKPD_prevTimeLag;
    LNKPD_prevTimeLag = currentTime;

    LNKPD_timeToLag = LNKPD_timeToLag - diff;

    if(LNKPD_timeToLag <= 0) then
        LNKPD_updateMode = LNKPD_UpdateModeBuild;
        LNKPD_prevTimeLag = 0;
        
        LNKPD_currentSearchIDX = 1;
        LNKPDFrame_SetPercentage(0);
        LNKPDFrame_SetActiveStatus(3);
        LNKPD_percNum = 0;
        LNKPD_percDenom = getn(LNKPDSV_ValidSearchID);
    end

end

-- Query the database for items
function LNKPD_UpdateModeQuery()
    LNKPD_showResults = true
    LNKPD_printPrefix = "Querying"

    local itemID = LNKPDSV_ValidSearchID[LNKPD_currentSearchIDX];
        
    -- Check for a valid item. GetItemIcon is quick. If it's invalid, remove it. Else, send query for it
    if(GetItemIcon(itemID) == nil) then
        table.remove(LNKPDSV_ValidSearchID, LNKPD_currentSearchIDX)
    else
        GetItemInfo(itemID);
        LNKPD_currentSearchIDX = LNKPD_currentSearchIDX + 1;
    end

    LNKPD_percNum = LNKPD_percNum + 1;

    -- Else we are finished with the query stage, now wait for 5 seconds then build the DB
    if(LNKPD_currentSearchIDX > getn(LNKPDSV_ValidSearchID)) then
        LNKPDUtils.Print(LNKPD_printPrefix .. ": " .. LNKPDUtils.Lite(" 100%"));
        LNKPDUtils.Print("Query Complete. Waiting 5 seconds before building the database.");
        LNKPD_updateMode  = LNKPD_UpdateModeWait
        LNKPD_timeToLag   = 5
        LNKPD_prevTimeLag = GetTime();
    end
end

function LNKPD_UpdateResults()
    -- calculate the percent
    local perc = LNKPD_percNum / LNKPD_percDenom;

    -- update the results for the player in the chat box
    if(LNKPDFrame_BuildCache:IsShown()) then
        LNKPDFrame_SetPercentage(perc);
        LNKPDFrame_SetLinksFound(LNKPD_linksFound);
    elseif(LNKPD_showResults) then
        local diff = GetTime() - LNKPD_lastPercPrintTime;
        if(diff > LNKPD_percSecPerPrint) then
            local str = string.format(" %.2f", perc * 100) .. "%";
            LNKPDUtils.Print(LNKPD_printPrefix .. ": " .. LNKPDUtils.Lite(str));
            LNKPD_lastPercPrintTime = GetTime();
        end
    end
end

-- Overall update function that performs all database operations
function LNKPD_UpdateActiveItemCache()

    if(LNKPD_SavedVariablesLoaded == false or getn(LNKPDSV_ValidSearchID) == 0) then
        return;
    end

    if(LNKPD_updateMode ~= nil) then
        for upd = 0, LNKPD_updatesPerFrame do
            LNKPD_updateMode()
        end
    else
        LNKPD_updateMode = LNKPD_UpdateModeIdleScan
        LNKPD_percDenom = getn(LNKPDSV_ValidSearchID)
    end
    
    LNKPD_UpdateResults()
end

-- Rebuild cache selected.
function LNKPD_RebuildCache()
--[[
    -- Development - Check highest valid item ID - Uncomment this code will highly lag the system
    local maxID = 1;
	local invalidIcon = GetItemIcon(9999999)
	for i = 100000, LNKPD_MAX_ITEM_ID do
        if(GetItemIcon(i) ~= invalidIcon) then
            maxID = i;
		end
	end
    LNKPDUtils.Print("Max valid ID is - " .. maxID);
--]]
	
    -- Clear out old variables
    LNKPDSV_ActiveItemLink = {}

    LNKPDSV_ValidSearchID   = {};

    LNKPD_currentSearchIDX = 1;
    LNKPD_updatesPerFrame  = 50;
    LNKPD_linksFound       = 0;

    for i = 1, LNKPD_MAX_ITEM_ID do
        LNKPDSV_ValidSearchID[i] = i;
    end

    LNKPD_percDenom   = LNKPD_MAX_ITEM_ID;
    LNKPD_percNum     = 0;
    LNKPD_updateMode  = LNKPD_UpdateModeQuery;

    -- Set up the frame to be ready to build
    LNKPDFrame_ShowBuild();
    LNKPDFrame_SetStatusText("> Querying", "> Waiting 5 seconds...", "> Building");
    LNKPDFrame_SetLinksFound(0);
    LNKPDFrame_SetActiveStatus(1);
    LNKPDFrame_SetPercentage(0);
    LNKPDFrame_SetBuildState();
end

-- Expand the current database
function LNKPD_ExpandCache()

    LNKPD_currentSearchIDX = 1;
    LNKPD_updatesPerFrame  = 50;
    LNKPD_linksFound       = 0;
    LNKPD_percDenom        = getn(LNKPDSV_ValidSearchID);
    LNKPD_percNum          = 0;
    LNKPD_updateMode       = LNKPD_UpdateModeBuild

    LNKPDFrame_ShowBuild();
    LNKPDFrame_SetStatusText("> Expanding", "", "");
    LNKPDFrame_SetLinksFound(0);
    LNKPDFrame_SetActiveStatus(1);
    LNKPDFrame_SetPercentage(0);
    LNKPDFrame_SetBuildState();
end

-- Cancel the current build
function LNKPD_CancelBuild()
    LNKPDUtils.Print("Database Build Cancelled");
    LNKPD_currentSearchIDX  = 1;
    LNKPD_linksFound        = 0;
    LNKPD_updatesPerFrame   = 1;
    LNKPD_percDenom         = getn(LNKPDSV_ValidSearchID);
    LNKPD_percNum           = 0;
    LNKPD_updateMode        = LNKPD_UpdateModeIdleScan
    LNKPDFrame_SetIdleState(); 
end

-- Introduction to Linkepedia!
function LNKPD_Introduction()
    LNKPDFrame_ShowWelcome();
    LNKPDUtils.Print("Welcome to Linkepedia! Type " .. LNKPDUtils.Lite("/linkepedia build") .. " to build your item database! Type " .. LNKPDUtils.Lite("/linkepedia help") .. " to see a full list of commands. Enjoy!");
end

-- Check and initialize the saved variables if they aren't already
function LNKPD_CheckSavedVariables()
    -- check saved variables
    if (LNKPDSV_ActiveItemLink == nil) or (LNKPDSV_ValidSearchID == nil) then
        LNKPDSV_ActiveItemLink  = {};
        LNKPDSV_ValidSearchID   = {};
    end

    if(LNKPDSV_Version == nil) then
        LNKPDSV_Version = {LNKPD_VERSION[1], LNKPD_VERSION[2], LNKPD_VERSION[3]};
        LNKPD_Introduction();
    elseif(LNKPDSV_Version[1] ~= LNKPD_VERSION[1] or LNKPDSV_Version[2] ~= LNKPD_VERSION[2] or LNKPDSV_Version[3] ~= LNKPD_VERSION[3]) then
        LNKPD_PerformVersionUpdates();
        LNKPDSV_Version = {LNKPD_VERSION[1], LNKPD_VERSION[2], LNKPD_VERSION[3]};
    end

    if(LNKPDSV_AutoCompleteDelay == nil) then
        LNKPDSV_AutoCompleteDelay = LNKPD_DEFAULT_DELAY;
    end

end

function LNKPD_Perform140Updates(updateFrom)
    LNKPDSV_ActiveItemLink = {}
    LNKPDSV_ValidSearchID  = {}

    LNKPDFrame_Update_VersionChange:SetText("Upgrading from " .. updateFrom .. " to " .. LNKPD_VERSION_STR .. "!");
     
    LNKPDFrame_Update_Info:SetText("" ..
    "Please read this important information about upgrading before you use Linkepedia!\n\n" ..
    "For this version to work, you need to rebuild your database. Type '/linkepedia build' to " ..
    "start the building process! This is mandatory! The way of storing the items has changed.\n\n" ..
    "What changed in this version?\n" ..
    "  > Fixed the addon to update to work with the latest WoW Expansion Warlords of Draenor\n" ..
    "  > Fixed link format syntax to prevent errors in game\n" ..
    "  > Changed the max item ID from 90913 to 120945\n" ..
    "  > Removed /linkspell from Linkepedia since it's broken. Might add back in the future.\n" ..
    "Sorry for the delay in getting this update out! I've been playing EVE and took a break from WoW.\n" ..
    "Thanks to lapdragon, Rubio9, gehwalt, and Qithe helping on Curse with these fixes!\n\n" ..
    " - Sincerely GhostfromTexas\n" ..
    "   (Norelco, Floss and Scalemaster on Area52 Horde)\n" ..
    "");
    LNKPDFrame_ShowUpdate();
end

function LNKPD_Perform150Updates(updateFrom)
    LNKPDSV_ActiveItemLink = {}
    LNKPDSV_ValidSearchID  = {}

    LNKPDFrame_Update_VersionChange:SetText("Upgrading from " .. updateFrom .. " to " .. LNKPD_VERSION_STR .. "!");
     
    LNKPDFrame_Update_Info:SetText("" ..
    "Please read this important information about upgrading before you use Linkepedia!\n\n" ..
    "For this version to work, you need to rebuild your database. Type '/linkepedia build' to " ..
    "start the building process! This is mandatory! The way of storing the items has changed.\n\n" ..
    "What changed in this version?\n" ..
    "  > Fixed the addon to update to work with the latest WoW Version\n" ..
    "  > Fixed link format syntax to prevent errors in game\n" ..
    "  > Changed the max item ID from 120945 to 134047\n\n" ..
    "I am still not active in WoW, so my apologies. I have started live-streaming video games!\n\n" ..
	"Come check me out on www.beam.pro/GhostfromTexas\n\n" ..
    "Thanks to matt0717 and VanderSwag helping on Curse with these fixes!\n\n" ..
    " - Sincerely GhostfromTexas\n" ..
    "   (Norelco, Floss and Scalemaster on Area52 Horde)\n" ..
    "");
    LNKPDFrame_ShowUpdate();
end

function LNKPD_PerformVersionUpdates()
    -- IF YOU ARE UPGRADING FROM VERSION 1.3.x
    if(LNKPDSV_Version[1] ~= 1 or LNKPDSV_Version[2] ~= 4 or LNKPDSV_Version[3] ~= 0) then
        LNKPD_Perform140Updates("1.3.x");
    end
	
	-- IF YOU ARE UPGRADING FROM VERSION 1.4.0
    if(LNKPDSV_Version[1] ~= 1 or LNKPDSV_Version[2] ~= 5 or LNKPDSV_Version[3] ~= 0) then
        LNKPD_Perform150Updates("1.4.0");
    end
end
