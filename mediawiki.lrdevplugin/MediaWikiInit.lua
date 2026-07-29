-- This file is part of the LrMediaWiki project and distributed under the terms
-- of the MIT license (see LICENSE.txt file in the project root directory or
-- [0]). See [1] for more information about LrMediaWiki.
--
-- Copyright (C) 2015 by the LrMediaWiki team (see CREDITS.txt file in the
-- project root directory or [2])
--
-- [0] <https://raw.githubusercontent.com/robinkrahl/LrMediaWiki/master/LICENSE.txt>
-- [1] <https://commons.wikimedia.org/wiki/Commons:LrMediaWiki>
-- [2] <https://raw.githubusercontent.com/robinkrahl/LrMediaWiki/master/CREDITS.txt>

-- Code status:
-- doc: missing
-- i18n: complete

local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

local MediaWikiApi = require 'MediaWikiApi'
local MediaWikiUtils = require 'MediaWikiUtils'

-- Split a version string like "v2.0.15", "2.0.15" or "0.5" into its numeric
-- parts. Anything that is not a number is ignored, missing parts count as 0,
-- so "0.5" and "0.5.0" compare as equal. Returns a table of numbers.
local function versionParts(version)
	local parts = {}
	for number in tostring(version or ''):gmatch('%d+') do
		parts[#parts + 1] = tonumber(number)
	end
	return parts
end

-- Numeric comparison: true if `available` is newer than `installed`.
-- (Purely local; the standalone tests copy this function verbatim, so no
-- export hook is needed.)
--
-- The original code compared the two version STRINGS with ">", which breaks
-- as soon as a part reaches two digits: "v2.0.9" > "v2.0.15" is true for a
-- string comparison, because '9' sorts after '1'. From revision 10 onwards
-- that silently suppressed every update notice.
local function isNewerVersion(available, installed)
	local a = versionParts(available)
	local b = versionParts(installed)
	local count = math.max(#a, #b)
	for i = 1, count do
		local left = a[i] or 0
		local right = b[i] or 0
		if left ~= right then
			return left > right
		end
	end
	return false -- identical
end


if MediaWikiUtils.getCheckVersion() then
	LrTasks.startAsyncTask(function()
	-- local installedFullVersion = MediaWikiUtils.getVersionString()
	local installedVersion = 'v' .. MediaWikiUtils.getInstalledVersion()
	local availableVersion = MediaWikiApi.getCurrentPluginVersion()
		if availableVersion ~= nil then
			-- MediaWikiUtils.trace('Installed LrMediaWiki version (with LR version and OS): ' .. installedFullVersion)
			-- MediaWikiUtils.trace('Installed LrMediaWiki version: ' .. installedVersion)
			-- MediaWikiUtils.trace('Available LrMediaWiki version: ' .. availableVersion)

			if isNewerVersion(availableVersion, installedVersion) then
				-- new version available!
				local  msg = LOC("$$$/LrMediaWiki/Init/Version/InfoInstalledVersion=Installed LrMediaWiki version: ^1^n", installedVersion)
				msg = msg .. LOC("$$$/LrMediaWiki/Init/Version/InfoAvailableVersion=Available LrMediaWiki version: ^1^n", availableVersion)
				msg = msg .. LOC("$$$/LrMediaWiki/Init/Version/InfoSummary=Please update to new available version.")
				LrDialogs.message(LOC "$$$/LrMediaWiki/Init/Version/Message=New version available", msg, 'info')
			end
		end
	end)
end
