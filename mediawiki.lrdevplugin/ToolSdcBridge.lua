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

local TITLE = 'LrMediaWiki2 – Hintergrund-App'

-- Die beiden Zustaende sind VERSCHIEDENE Dinge, und genau daran ist der alte
-- Text gescheitert ("Zustand: eingeschaltet" direkt neben "Laeuft gerade
-- nicht" liest sich wie ein Widerspruch):
--
--   eingeschaltet  dauerhafte Voreinstellung. Sie ueberlebt den Neustart und
--                  entscheidet, ob die App beim Start von Lightroom
--                  automatisch hochkommt.
--   aktiv          laeuft die App JETZT, in dieser Lightroom-Sitzung.
--
-- Eingeschaltet und trotzdem nicht aktiv ist der voellig normale Fall, wenn
-- der Start fehlgeschlagen ist oder man sie in dieser Sitzung angehalten hat.
local function statusText()
	local lines = {}

	lines[#lines + 1] = 'Die Hintergrund-App lässt die Editorseite offen und'
	lines[#lines + 1] = 'beim Fotowechsel mitziehen.'
	lines[#lines + 1] = ''

	if MediaWikiSdcBridge.isEnabled() then
		lines[#lines + 1] = 'Dauerhaft eingeschaltet:  JA'
		lines[#lines + 1] = '  (startet automatisch mit Lightroom)'
	else
		lines[#lines + 1] = 'Dauerhaft eingeschaltet:  NEIN'
		lines[#lines + 1] = '  (startet nicht von selbst)'
	end

	if MediaWikiSdcBridge.running and MediaWikiSdcBridge.port then
		lines[#lines + 1] = 'Jetzt aktiv:              JA, Port '
			.. tostring(MediaWikiSdcBridge.port)
		lines[#lines + 1] = '  Offene Editorseiten: '
			.. tostring(MediaWikiSdcBridge.subscribers or 0)
	else
		lines[#lines + 1] = 'Jetzt aktiv:              NEIN'
		lines[#lines + 1] = '  (in dieser Lightroom-Sitzung läuft sie nicht)'
	end

	if MediaWikiSdcBridge.lastError then
		lines[#lines + 1] = ''
		lines[#lines + 1] = 'Letzter Fehler: ' .. tostring(MediaWikiSdcBridge.lastError)
	end

	lines[#lines + 1] = ''
	lines[#lines + 1] = 'Ist sie nicht aktiv, funktioniert der SDC-Editor'
	lines[#lines + 1] = 'weiter über den Dateiweg. Die Seite kann dann nur'
	lines[#lines + 1] = 'nicht beim Fotowechsel mitziehen, und eine schon'
	lines[#lines + 1] = 'offene Seite meldet selbst, dass sie veraltet ist.'
	lines[#lines + 1] = ''
	lines[#lines + 1] = 'Protokoll der App:'
	lines[#lines + 1] = tostring(MediaWikiSdcBridge.bridgeLogPath())

	return table.concat(lines, '\n')
end

LrTasks.startAsyncTask(function()

	local enabled = MediaWikiSdcBridge.isEnabled()
	local running = MediaWikiSdcBridge.running and MediaWikiSdcBridge.port ~= nil

	-- Die Beschriftungen sagen jeweils, WELCHE der beiden Ebenen sie
	-- anfassen: "dauerhaft" die Voreinstellung, "in dieser Sitzung" den
	-- laufenden Prozess. Vorher hiess es nur "Ausschalten" und "Jetzt
	-- starten", und daran war nicht zu erkennen, was womit passiert.
	local action, other
	if not enabled then
		action = 'Dauerhaft einschalten und jetzt starten'
		other = nil
	elseif running then
		action = 'Dauerhaft ausschalten und anhalten'
		other = 'Editorseite öffnen'
	else
		action = 'Jetzt starten (bleibt eingeschaltet)'
		other = 'Dauerhaft ausschalten'
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
