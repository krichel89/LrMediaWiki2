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


-- Start the SDC background bridge if the user switched it on. Opt-in: a
-- fresh installation launches nothing on its own.
--
-- Its own async task, because ensureRunning PAUSES (it starts a process and
-- then waits for the port file) and must not hold up the version check or
-- the rest of plug-in loading. No pcall anywhere above it, for the same
-- reason - in Lua 5.1 nothing can pause across a C function, and pcall is
-- one.
LrTasks.startAsyncTask(function()
	local okLoad, bridge = pcall(function() return require 'MediaWikiSdcBridge' end)
	if not okLoad or type(bridge) ~= 'table' then
		MediaWikiUtils.trace('SDC bridge autostart: module could not be loaded')
		return
	end
	-- isEnabled only reads preferences and does not pause, so the pcall
	-- around the require above is harmless here.
	if not bridge.isEnabled() then
		MediaWikiUtils.trace('SDC bridge autostart: switched off, nothing started')
		return
	end

	-- Give Lightroom a moment to finish starting up before we launch a
	-- process and wait for its port file. LrTasks.sleep PAUSES, which is
	-- fine here and would not be inside a pcall.
	LrTasks.sleep(3)

	MediaWikiUtils.trace('SDC bridge autostart: starting')
	if bridge.ensureRunning() then
		MediaWikiUtils.trace('SDC bridge autostart: up on port ' .. tostring(bridge.port))
	else
		-- Deliberately no dialog. An error box in front of a just-opened
		-- Lightroom would be a nuisance, and the file route still works;
		-- the state is visible in the bridge dialog and in the log.
		MediaWikiUtils.trace('SDC bridge autostart: failed – '
			.. tostring(bridge.lastError or 'reason unknown'))
	end
end)


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
