-- This file is part of the LrMediaWiki project and distributed under the terms
-- of the MIT license (see LICENSE.txt file in the project root directory or
-- [0]).  See [1] for more information about LrMediaWiki.
--
-- Copyright (C) 2014 by the LrMediaWiki team (see CREDITS.txt file in the
-- project root directory or [2])
--
-- [0]  <https://raw.githubusercontent.com/ireas/LrMediaWiki/master/LICENSE.txt>
-- [1]  <https://commons.wikimedia.org/wiki/Commons:LrMediaWiki>
-- [2]  <https://raw.githubusercontent.com/ireas/LrMediaWiki/master/CREDITS.txt>

-- Code status:
-- doc:   missing
-- i18n:  complete

local LrApplication = import 'LrApplication'
local LrLogger = import 'LrLogger'
local LrPasswords = import 'LrPasswords'
local LrPrefs = import 'LrPrefs'
local LrDate = import 'LrDate'

local Info = require 'Info'

local MediaWikiUtils = {}
local myLogger = LrLogger('LrMediaWikiLogger')

local prefs = LrPrefs.prefsForPlugin(nil)
if prefs.logging then
	myLogger:enable('logfile')
end

-- Allows formatting of strings like "${test} one two three ${test2}"
-- Based on a solution by http://lua-users.org/wiki/RiciLake shown here:
-- http://lua-users.org/wiki/StringInterpolation
MediaWikiUtils.formatString = function(str, arguments)
	return (str:gsub('($%b{})', function(w) return arguments[w:sub(3, -2)] or w end))
end

-- Substitute placeholders of format "<var>" – similar to function "formatString"
MediaWikiUtils.substitutePlaceholders = function(str, arguments)
	return (str:gsub('(%b<>)', function(w) return arguments[w:sub(2, -2)] or w end))
end

MediaWikiUtils.isStringEmpty = function(str)
	return str == nil or string.match(str, '^%s*$') ~= nil
	-- see e.g. http://stackoverflow.com/questions/10328211/how-to-check-if-a-value-is-empty-in-lua
end

MediaWikiUtils.isStringFilled = function(str)
	return not MediaWikiUtils.isStringEmpty(str)
end

MediaWikiUtils.trim = function(str)
	return string.match(str, '^%s*(.-)%s*$')
	-- see e.g. http://lua-users.org/wiki/StringTrim
	--- or http://lua-users.org/wiki/CommonFunctions
end

-- Does a (new) upload file name carry any meaning? Commons file names should
-- describe the picture; names straight from the camera or its numbering do
-- not. Pure function - no Lightroom calls - so it can be checked outside
-- Lightroom. Takes the leaf name (with or without extension) and returns nil
-- if the name is acceptable, otherwise a reason code:
--   'leadingUnderscore'  starts with "_"  (e.g. _DSC1234, _MG_5678)
--   'cameraName'         a camera prefix followed by a number of at least
--                        three digits (IMG_1234, DSC01234, DSCF0042 ...);
--                        "Sam_2" is not a camera name
--   'noMeaning'          none of the following holds (KRI_2026_1834,
--                        A7R04312, 20260101 ...: a random camera counter):
--                          * two words of two or more letters, one of them
--                            with three or more,
--                          * one word of four or more letters (Madonna-1234,
--                            Cher-0042: single-name people),
--                          * one word of two or more NON-LATIN characters
--                            (北京-1: one character carries a whole syllable)
-- Letters include bytes >= 128 so that umlauts and other UTF-8 letters count;
-- the length of a word is counted in CHARACTERS (UTF-8 continuation bytes
-- 0x80-0xBF do not count), so "Çatak" has five, not six.
local CAMERA_PREFIXES = {
	'IMGP', 'IMG', 'DSCF', 'DSCN', 'DSC', 'DSF', 'MVI', 'GOPR', 'DJI', 'PXL',
	'PICT', 'SAM', 'SDC', 'CIMG', 'DCP', 'IMAG',
}
MediaWikiUtils.fileNameProblem = function(leafName)
	local name = tostring(leafName or '')
	local stem = (name:gsub('%.%w+$', ''))
	if stem:sub(1, 1) == '_' then
		return 'leadingUnderscore'
	end
	local upper = stem:upper()
	for _, prefix in ipairs(CAMERA_PREFIXES) do
		if upper:sub(1, #prefix) == prefix then
			local rest = upper:sub(#prefix + 1)
			if rest:match('^[_%-%s]*%d%d%d') then
				return 'cameraName'
			end
		end
	end
	local words, long, single = 0, 0, false
	for word in stem:gmatch('[%a\128-\255]+') do
		-- characters, not bytes: drop the UTF-8 continuation bytes
		local chars = #(word:gsub('[\128-\191]', ''))
		if chars >= 2 then words = words + 1 end
		if chars >= 3 then long = long + 1 end
		if chars >= 4 then single = true end
		-- two or more characters outside ASCII that are not just accented
		-- Latin letters: a lead byte >= 0xE0 starts a 3- or 4-byte sequence
		-- (CJK, Thai, Indic ...), Latin accents are 2-byte sequences
		if chars >= 2 and select(2, word:gsub('[\224-\247]', '')) >= 2 then
			single = true
		end
	end
	if not single and (words < 2 or long < 1) then
		return 'noMeaning'
	end
	return nil
end

-- Category name as Commons compares it: underscores are spaces, runs of
-- spaces are one, the first letter is case-insensitive. Pure.
MediaWikiUtils.normCategory = function(name)
	local n = tostring(name or ''):gsub('_', ' '):gsub('%s+', ' ')
	n = n:match('^%s*(.-)%s*$')
	return (n:gsub('^%l', string.upper))
end

-- Does a category from the export dialog belong to a DIFFERENT event set than
-- the photo's own categories? Only categories that belong to exactly ONE set
-- count; a category in several sets (e.g. a general WikiPortraits category)
-- says nothing about which event the photo is from. Pure.
--   dialogCats, photoCats  lists of category names
--   sets                   list of {name=, categories={...}}
-- Returns nil, or { category = <dialog category>, dialogSet = <set name>,
-- photoSet = <set name> }.
MediaWikiUtils.setCategoryConflict = function(dialogCats, photoCats, sets)
	if type(sets) ~= 'table' or #sets == 0 then return nil end
	local owners = {}
	for _, set in ipairs(sets) do
		local seen = {}
		for _, c in ipairs(set.categories or {}) do
			local k = MediaWikiUtils.normCategory(c)
			if k ~= '' and not seen[k] then
				seen[k] = true
				owners[k] = owners[k] or {}
				owners[k][#owners[k] + 1] = set.name
			end
		end
	end
	local function onlySet(c)
		local o = owners[MediaWikiUtils.normCategory(c)]
		if o and #o == 1 then return o[1] end
		return nil
	end
	local photoSets, firstPhotoSet = {}, nil
	for _, c in ipairs(photoCats or {}) do
		local s = onlySet(c)
		if s then
			photoSets[s] = true
			firstPhotoSet = firstPhotoSet or s
		end
	end
	if not firstPhotoSet then return nil end
	for _, c in ipairs(dialogCats or {}) do
		local s = onlySet(c)
		if s and not photoSets[s] then
			return { category = MediaWikiUtils.trim(c), dialogSet = s, photoSet = firstPhotoSet }
		end
	end
	return nil
end

MediaWikiUtils.getFirstKey = function(table)
	for key, value in pairs(table) do -- luacheck: ignore ("loop is executed at most once")
		return key
	end
	return nil
end

MediaWikiUtils.getInstalledVersion = function()
	local str = Info.VERSION.major .. '.' .. Info.VERSION.minor .. '.' .. Info.VERSION.revision
	return str
end

MediaWikiUtils.getVersionString = function()
	local installedVersion = Info.VERSION.major .. '.' .. Info.VERSION.minor .. '.' .. Info.VERSION.revision
	local platform = '?'
	-- Boolean global variables WIN_ENV and MAC_ENV are documented at LR SDK programmers guide
	if WIN_ENV == true then
		platform = 'Win'
	elseif MAC_ENV == true then
		platform = 'Mac' -- OS name has been changed in 2016 from "OS X" to "macOS"
	else
		error 'Unsupported platform – neither Windows nor macOS' -- unlikely case
	end
	return installedVersion .. ', LR ' .. LrApplication.versionString() .. ' ' .. platform
end

MediaWikiUtils.storePassword = function(apiPath, username, password)
	-- passwordKey needs to be the same as at "retrievePassword"
	local passwordKey = 'LrMediaWiki#' .. apiPath .. '#' .. username
	LrPasswords.store(passwordKey, password)
end

MediaWikiUtils.retrievePassword = function(apiPath, username)
	-- passwordKey needs to be the same as at "storePassword"
	local passwordKey = 'LrMediaWiki#' .. apiPath .. '#' .. username
	local password = LrPasswords.retrieve(passwordKey)
	if password == nil then
		password = ''
	end
	return password
end

-- configuration

MediaWikiUtils.getCreateSnapshots = function()
	return prefs.create_snapshot or false
end

MediaWikiUtils.setCreateSnapshots = function(create_snapshot)
	prefs.create_snapshot = create_snapshot
end

MediaWikiUtils.getExportKeyword = function()
	return prefs.export_keyword or nil
end

MediaWikiUtils.setExportKeyword = function(tag)
	prefs.export_keyword = tag
end

MediaWikiUtils.getExportColor = function()
	return prefs.export_color or nil
end

MediaWikiUtils.setExportColor = function(color)
	prefs.export_color = color
end

MediaWikiUtils.getCheckVersion = function()
	return prefs.check_version or false
end

MediaWikiUtils.setCheckVersion = function(check_version)
	prefs.check_version = check_version
end

MediaWikiUtils.getStructuredData = function()
	if prefs.structured_data == nil then -- first call
		prefs.structured_data = true -- default
	end
	return prefs.structured_data
end

MediaWikiUtils.setStructuredData = function(structured_data)
	prefs.structured_data = structured_data
end

MediaWikiUtils.getLogging = function()
	return prefs.logging or false
end

MediaWikiUtils.setLogging = function(logging)
	prefs.logging = logging
	if logging then
		myLogger:enable('logfile')
	else
		myLogger:disable()
	end
end

-- Browser for the OAuth login. The stored value is a key from the table
-- below; the empty string means the system default browser. Pure string
-- building here - the caller runs the command via LrTasks.execute, which
-- must NEVER be wrapped in pcall (Lua 5.1 cannot yield across pcall).
local LOGIN_BROWSERS = {
	firefox = { mac = 'Firefox',        win = 'firefox' },
	chrome  = { mac = 'Google Chrome',  win = 'chrome'  },
	edge    = { mac = 'Microsoft Edge', win = 'msedge'  },
	safari  = { mac = 'Safari',         win = nil       },
	vivaldi = { mac = 'Vivaldi',        win = 'vivaldi' },
	brave   = { mac = 'Brave Browser',  win = 'brave'   },
}

MediaWikiUtils.getLoginBrowser = function()
	return prefs.loginBrowser or ''
end

MediaWikiUtils.setLoginBrowser = function(browser)
	prefs.loginBrowser = browser
end

-- Returns the shell command that opens the URL in the chosen browser, or
-- nil if the default browser should be used (no choice made, unknown key,
-- browser not available on this platform, or a suspicious URL).
MediaWikiUtils.loginBrowserCommand = function(url)
	local entry = LOGIN_BROWSERS[MediaWikiUtils.getLoginBrowser()]
	if entry == nil or type(url) ~= 'string' then
		return nil
	end
	-- The URL is assembled from percent-encoded parts, so quotes and
	-- backslashes cannot occur. Guard anyway: anything suspicious goes to
	-- the default browser instead of into a shell line.
	if string.match(url, [=[['"\%s]]=]) then
		return nil
	end
	if MAC_ENV then
		return "open -a '" .. entry.mac .. "' '" .. url .. "'"
	elseif WIN_ENV and entry.win then
		-- start: the first quoted argument is the window title, hence "".
		return 'start "" ' .. entry.win .. ' "' .. url .. '"'
	end
	return nil
end

MediaWikiUtils.getPreviewWikitextFontName = function()
	return prefs.preview_wikitext_font_name or '' -- no default value
end

MediaWikiUtils.setPreviewWikitextFontName = function(tag)
	prefs.preview_wikitext_font_name = tag
end

MediaWikiUtils.getPreviewWikitextFontSize = function()
	return prefs.preview_wikitext_font_size or 12 -- 12 = default value
end

MediaWikiUtils.setPreviewWikitextFontSize = function(tag)
	prefs.preview_wikitext_font_size = tonumber(tag)
end

MediaWikiUtils.trace = function(message)
	myLogger:trace(message)
end

MediaWikiUtils.tracef = function(format, message)
	myLogger:tracef(format, message)
end

MediaWikiUtils.currentDate = function(arguments) -- returns list of date related placeholders
	local currentTime = LrDate.currentTime() -- number of seconds since midnight UTC on January 1, 2001
	arguments.currentIsoDate = LrDate.timeToIsoDate(currentTime) -- 2021-01-09
	arguments.currentLongDate = LrDate.formatLongDate(currentTime) -- 9. Januar 2021
	arguments.currentMediumDate = LrDate.formatMediumDate(currentTime) -- 09.01.2021
	arguments.currentShortDate = LrDate.formatShortDate(currentTime) -- 09.01.21
	arguments.currentYear = LrDate.timeToUserFormat(currentTime, '%Y') -- 2021
	arguments.currentYearXX = LrDate.timeToUserFormat(currentTime, '%y') -- 21
	arguments.currentMonthXX = LrDate.timeToUserFormat(currentTime, '%m') -- 01
	arguments.currentMonth = tonumber(arguments.currentMonthXX) -- 1
	arguments.currentMonthName = LrDate.timeToUserFormat(currentTime, '%B') -- January
	arguments.currentDayXX = LrDate.timeToUserFormat(currentTime, '%d') -- 09
	arguments.currentDay = LrDate.timeToUserFormat(currentTime, '%e') -- 9
	arguments.currentDayName = LrDate.timeToUserFormat(currentTime, '%A') -- Saturday
	arguments.currentTime = LrDate.timeToUserFormat(currentTime, '%H:%M:%S') -- 20:40:15
	arguments.currentHour = LrDate.timeToUserFormat(currentTime, '%H') -- 20
	arguments.currentMinute = LrDate.timeToUserFormat(currentTime, '%M') -- 40
	arguments.currentSecond = LrDate.timeToUserFormat(currentTime, '%S') -- 15
	return arguments
end

return MediaWikiUtils
