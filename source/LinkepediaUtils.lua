------------------------------------------------------
-- LinkepediaUtils.lua
-- Utils based off of original code from Fizzwidget are marked with <Gazmik Fizzwidget>
------------------------------------------------------

LNKPDUtils_COLORS = {
    ["1"] = "cff9d9d9d", -- gray
    ["2"] = "cffffffff", -- white
    ["3"] ="cff1eff00",  -- green
    ["4"] = "cff0070dd", -- blue
    ["5"] ="cffa335ee",  -- purple
    ["6"] ="cffff8000",  -- orange
    ["7"] = "cffe6cc80", -- gold
    ["8"] = "cff00ccff", -- blizzblue

    ["cff9d9d9d"] = "1", -- gray
    ["cffffffff"] = "2", -- white
    ["cff1eff00"] = "3", -- green
    ["cff0070dd"] = "4", -- blue
    ["cffa335ee"] = "5", -- purple
    ["cffff8000"] = "6", -- orange
    ["cffe6cc80"] = "7", -- gold
    ["cff00ccff"] = "8", -- blizzblue
}

-- <Gazmik Fizzwidget>
function LNKPDUtils_DecomposeItemLink(link)
	local _, _, itemID, enchant, gem1, gem2, gem3, gem4, randomProp, uniqueID = string.find(link, "item:(-?%d+):(-?%d+):(-?%d+):(-?%d+):(-?%d+):(-?%d+):(-?%d+):(-?%d+)");
	itemID = tonumber(itemID);
	enchant = tonumber(enchant);
	gem1 = tonumber(gem1);
	gem2 = tonumber(gem2);
	gem3 = tonumber(gem3);
	gem4 = tonumber(gem4);
	randomProp = tonumber(randomProp);
	uniqueID = tonumber(uniqueID);
	return itemID, enchant, gem1, gem2, gem3, gem4, randomProp, uniqueID;
end

-- <Gazmik Fizzwidget>
function LNKPDUtils_BuildItemLink(itemID, enchant, gem1, gem2, gem3, gem4, randomProp, uniqueID)
	itemID = itemID or 0;
	enchant = enchant or 0;
	gem1 = gem1 or 0;
	gem2 = gem2 or 0;
	gem3 = gem3 or 0;
	gem4 = gem4 or 0;
	randomProp = randomProp or 0;
	uniqueID = uniqueID or 0;
	return string.format("item:%d:%d:%d:%d:%d:%d:%d:%d", itemID, enchant, gem1, gem2, gem3, gem4, randomProp, uniqueID);
end

-- <Gazmik Fizzwidget>
function LNKPDUtils_TableCount(aTable)
	if (aTable == nil or type(aTable) ~= "table") then
		return nil; -- caller probably won't expect this, causing traceable error in their code
	end
	local count = 0;
	for key, value in pairs(aTable) do
		count = count + 1;
	end
	return count;
end

function LNKPDUtils_LinkCompress(link)
    local color, itemID, _, _, name = link:match("|(.-)|Hitem:(.-):.-:.-:.-:.-:.-:(.-):(.-):.+|h%[(.-)%]|h|r");
    color = LNKPDUtils_COLORS[color];
    local data = name .. "~" .. color .. "~" .. itemID;
    return data;
end

function LNKPDUtils_LinkDecompress(data)
    --local name, color, itemID = data:match("(.-)~(.-)~(.+)");
    local name, color, itemID = strsplit("~", data);
    -- local link = string.format("|%s|Hitem:%s:0:0:0:0:0:0:0:72:0|h[%s]|h|r", LNKPDUtils_COLORS[color], itemID, name )
    local link = "|" .. LNKPDUtils_COLORS[color] .. "|Hitem:" .. itemID .. ":0:0:0:0:0:0:0:100:0:0:0:0|h[" .. name .. "]|h|r";
    return link;
end

function LNKPDUtils_NameFromLink(link)
    local posStart = string.find(link, "%[") + 1;
    local posEnd = string.find(link, "%]", posStart) - 1;
    return string.sub(link, posStart, posEnd);
end

-- <Gazmik Fizzwidget>
function LNKPDUtils_WarningText(text)
    if (text == nil) then return nil; end
	return RED_FONT_COLOR_CODE..text..FONT_COLOR_CODE_CLOSE;
end

-- <Gazmik Fizzwidget>
function LNKPDUtils_LiteText(text)
	if (text == nil) then return nil; end
	return HIGHLIGHT_FONT_COLOR_CODE .. text .. FONT_COLOR_CODE_CLOSE;
end

function LNKPDUtils_PrintLink(var)
    if var then
        print(var);
    end
end

function LNKPDUtils_Print(var, r, g, b)
    
    if not r or not g or not b then
        r = LNKPD_PRINT_COLOR.r
        g = LNKPD_PRINT_COLOR.g
        b = LNKPD_PRINT_COLOR.b
    end

    DEFAULT_CHAT_FRAME:AddMessage(var, r, g, b);
    --print(var, (r or LNKPD_PRINT_COLOR.r), (g or LNKPD_PRINT_COLOR.g), (b or LNKPD_PRINT_COLOR.b)););
end

function LNKPDUtils_CommaValue(n) -- credit http://richard.warburton.it
	local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
	return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

if (LNKPDUtils == nil) then
	LNKPDUtils = {};
end
local L = LNKPDUtils;

LNKPD_PRINT_COLOR = {r=1.0, g=0.7, b=0.1};

L.Print             = LNKPDUtils_Print;
L.PrintLink         = LNKPDUtils_PrintLink;
L.Lite              = LNKPDUtils_LiteText;
L.LinkName          = LNKPDUtils_NameFromLink;
L.Warn              = LNKPDUtils_WarningText;
L.Comp              = LNKPDUtils_LinkCompress;
L.Decomp            = LNKPDUtils_LinkDecompress;
L.DecomposeItemLink = LNKPDUtils_DecomposeItemLink;
L.BuildItemLink     = LNKPDUtils_BuildItemLink;
L.TableCount        = LNKPDUtils_TableCount;
L.CommaValue        = LNKPDUtils_CommaValue;