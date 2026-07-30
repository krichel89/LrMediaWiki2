-- This file is part of the LrMediaWiki2 project and distributed under the
-- terms of the MIT license (see LICENSE.txt file in the project root
-- directory).
--
-- Switches the background bridge on and off and reports its state.
--
-- Deliberately built with LrDialogs.confirm rather than a LrView dialog:
-- confirm needs no view hierarchy, no bindings and no observers, so none
-- of the LrView quirks recorded in the project notes (push_button titles
-- do not update when bound, `visible` is ignored on row containers,
-- dropdowns cannot be opened programmatically) can apply here.
--
-- PAUSING: ensureRunning launches a process and waits for it, so it must
-- not be called from inside a pcall.

local LrDialogs = import 'LrDialogs'
local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'

local MediaWikiSdcBridge = require 'MediaWikiSdcBridge'

local TITLE = 'LrMediaWiki – Hintergrund-App'

local function statusText()
	local lines = {}

	if MediaWikiSdcBridge.isEnabled() then
		lines[#lines + 1] = 'Zustand: eingeschaltet'
	else
		lines[#lines + 1] = 'Zustand: ausgeschaltet'
	end

	if MediaWikiSdcBridge.running and MediaWikiSdcBridge.port then
		lines[#lines + 1] = 'Läuft auf Port ' .. tostring(MediaWikiSdcBridge.port)
		lines[#lines + 1] = 'Offene Editorseiten: '
			.. tostring(MediaWikiSdcBridge.subscribers or 0)
	else
		lines[#lines + 1] = 'Läuft gerade nicht.'
	end

	if MediaWikiSdcBridge.lastError then
		lines[#lines + 1] = ''
		lines[#lines + 1] = 'Letzter Fehler: ' .. tostring(MediaWikiSdcBridge.lastError)
	end

	lines[#lines + 1] = ''
	lines[#lines + 1] = 'Protokoll der App:'
	lines[#lines + 1] = tostring(MediaWikiSdcBridge.bridgeLogPath())
	lines[#lines + 1] = ''
	lines[#lines + 1] = 'Ist die App aus, läuft der SDC-Editor weiter über den '
		.. 'Dateiweg – die Seite kann dann nur nicht beim Fotowechsel mitziehen.'

	return table.concat(lines, '\n')
end

LrTasks.startAsyncTask(function()

	local enabled = MediaWikiSdcBridge.isEnabled()
	local running = MediaWikiSdcBridge.running and MediaWikiSdcBridge.port ~= nil

	local action, other
	if not enabled then
		action = 'Einschalten und starten'
		other = nil
	elseif running then
		action = 'Ausschalten'
		other = 'Editor öffnen'
	else
		action = 'Jetzt starten'
		other = 'Ausschalten'
	end

	local choice = LrDialogs.confirm(TITLE, statusText(), action, 'Schließen', other)

	if choice == 'cancel' then
		return
	end

	if not enabled and choice == 'ok' then
		MediaWikiSdcBridge.setEnabled(true)
		-- ensureRunning pauses – no pcall.
		if MediaWikiSdcBridge.ensureRunning() then
			LrDialogs.message(TITLE,
				'Die Hintergrund-App läuft auf Port '
				.. tostring(MediaWikiSdcBridge.port) .. '.\n\n'
				.. 'Der SDC-Editor öffnet sich ab jetzt über sie und zieht beim '
				.. 'Fotowechsel mit.', 'info')
		else
			MediaWikiSdcBridge.setEnabled(false)
			LrDialogs.message(TITLE,
				'Der Start ist fehlgeschlagen, die App bleibt ausgeschaltet.\n\n'
				.. tostring(MediaWikiSdcBridge.lastError or 'Grund unbekannt.'),
				'critical')
		end
		return
	end

	if enabled and running then
		if choice == 'ok' then
			MediaWikiSdcBridge.setEnabled(false)
			MediaWikiSdcBridge.stop()
			LrDialogs.message(TITLE,
				'Ausgeschaltet. Die App beendet sich von selbst, sobald die '
				.. 'Lebenszeichen aus Lightroom ausbleiben.', 'info')
		elseif choice == 'other' then
			local url = MediaWikiSdcBridge.editorUrl()
			if url then
				pcall(function() LrHttp.openUrlInBrowser(url) end)
			end
		end
		return
	end

	-- enabled, but not running
	if choice == 'ok' then
		if MediaWikiSdcBridge.ensureRunning() then
			LrDialogs.message(TITLE,
				'Gestartet auf Port ' .. tostring(MediaWikiSdcBridge.port) .. '.', 'info')
		else
			LrDialogs.message(TITLE,
				'Der Start ist fehlgeschlagen.\n\n'
				.. tostring(MediaWikiSdcBridge.lastError or 'Grund unbekannt.'),
				'critical')
		end
	elseif choice == 'other' then
		MediaWikiSdcBridge.setEnabled(false)
		MediaWikiSdcBridge.stop()
		LrDialogs.message(TITLE, 'Ausgeschaltet.', 'info')
	end
end)
