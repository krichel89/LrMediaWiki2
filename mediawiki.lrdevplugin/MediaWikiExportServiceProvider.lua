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
local LrBinding = import 'LrBinding'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local bind = LrView.bind

local Info = require 'Info'
local MediaWikiApi = require 'MediaWikiApi'
local MediaWikiInterface = require 'MediaWikiInterface'
local MediaWikiOAuth = require 'MediaWikiOAuth'
local MediaWikiUtils = require 'MediaWikiUtils'

local MediaWikiExportServiceProvider = {}

-- Normalize a Structured-Data QID entered in the export dialog:
-- trim surrounding whitespace, strip an inline comment after "#"
-- (e.g. "Q640 # Harald Krichel" -> "Q640"), and upper-case a leading "q"
-- (q640 -> Q640), so the value matches the ^Q%d+$ form expected by
-- MediaWikiApi.wbEditEntity.
-- Returns '' for anything that is not a single, well-formed QID.
local function normalizeSdcQid(value)
	if not MediaWikiUtils.isStringFilled(value) then
		return ''
	end
	local qid = MediaWikiUtils.trim(value)
	-- Strip inline comment
	qid = qid:match('^([^#]+)') or qid
	qid = MediaWikiUtils.trim(qid)
	qid = qid:gsub('^[qQ](%d+)$', 'Q%1')
	if qid:match('^Q%d+$') then
		return qid
	end
	return ''
end

local fillFieldsByFile = function(propertyTable, photo, useLocationInfo)
	-- All decisions done by this function should be documented at user's guide.
	local artworkParameters = { -- Parameters of infobox template "Artwork"
		artist = '', -- '<!-- Artist -->',
		title = '', -- '<!-- Title -->',
		date = '', -- '<!-- Date -->',
		medium = '', -- '<!-- Medium -->',
		dimensions = '', -- '<!-- Dimensions -->',
		institution = '', -- '<!-- Institution -->',
		department = '', -- '<!-- Department -->',
		accessionNumber = '', -- '<!-- Accession number -->',
		placeOfCreation = '', -- '<!-- Place of creation -->',
		placeOfDiscovery = '', -- '<!-- Place of discovery -->',
		objectHistory = '', -- '<!-- Object history -->',
		exhibitionHistory = '', -- '<!-- Exhibition history -->',
		creditLine = '', -- '<!-- Credit line -->',
		inscriptions = '', -- '<!-- Inscriptions -->',
		notes = '', -- '<!-- Notes -->',
		references = '', -- '<!-- References -->',
		wikidata = '', -- '<!-- Wikidata -->',
	}
	local objectPhotoParameters = { -- Parameters of infobox template "Object photo" without "description" and "permission"
		object = '',
		detail = '',
		detailPosition = '',
	}
	local exportFields = { -- Fields set at export dialog, copied to return object, order by UI
		info_template = propertyTable.info_template,
		info_mode = propertyTable.info_mode,
		info_language = propertyTable.info_language,
		info_source = propertyTable.info_source,
		info_author = propertyTable.info_author,
		info_permission = propertyTable.info_permission,
		info_license = propertyTable.info_license,
		info_templates = propertyTable.info_templates,
		other_fields = propertyTable.other_fields,
		info_categories = propertyTable.info_categories,
		-- Structured data
		caption_en = '', -- '<!-- File Caption (en) -->',
		depicts = '', -- P180, comma-separated QIDs (Metadata panel field)
		created_during = '', -- P10408, single QID (Metadata panel field)
		-- Single freetext description field (replaces description, date, source, author, etc.)
		['description_all'] = '', -- '<!-- Wikitext description -->',
		categories = '', -- '<!-- Per-file categories -->',
		art = artworkParameters, -- Parameters of infobox template "Artwork"
		objectPhoto = objectPhotoParameters, -- Parameters of infobox template "Object photo"
	}

	-- Field "File caption (en)"
	local captionEn = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'caption_en')
	if MediaWikiUtils.isStringFilled(captionEn) then
		exportFields.caption_en = captionEn
	end

	-- Per-file overrides for the fields that came back in 2.0.57. The export
	-- dialog keeps supplying the default for the whole batch; a value in the
	-- Metadata panel of a single photo wins over it. That is the behaviour of
	-- the original plug-in, and the reason these fields exist again: an
	-- artwork needs its own source, author and date, a press photo does not.
	-- Reading them is safe again because MediaWikiMetadataProvider declares
	-- them; before 2.0.57 it did not, and an undeclared read aborts the
	-- export with "Attempt to access property ... not declared in Info.lua".
	local function perFile(fieldId, batchKey)
		local value = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, fieldId)
		if MediaWikiUtils.isStringFilled(value) then
			exportFields[batchKey] = value
		end
	end
	perFile('source', 'info_source')
	perFile('author', 'info_author')
	perFile('templates', 'info_templates')
	perFile('otherFields', 'other_fields')

	-- Field "description_all" – single freetext Wikitext field
	local descriptionAll = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'description_all') or ''

	-- Merge the per-language single-line fields (Metadata panel sets
	-- "Information" / "Information (de)") into the wikitext description as
	-- {{en|1=…}} / {{de|1=…}} blocks. This makes both representations
	-- equivalent at export time, no matter which panel set was used last.
	-- A block that is already literally present is not added twice.
	local langBlocks = ''
	for _, lang in ipairs({ 'en', 'de' }) do
		local fieldValue = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'description_' .. lang) or ''
		if MediaWikiUtils.isStringFilled(fieldValue) then
			local block = '{{' .. lang .. '|1=' .. MediaWikiUtils.trim(fieldValue) .. '}}'
			if not descriptionAll:find(block, 1, true) then
				if langBlocks ~= '' then
					langBlocks = langBlocks .. '\n'
				end
				langBlocks = langBlocks .. block
			end
		end
	end
	if langBlocks ~= '' then
		if MediaWikiUtils.isStringFilled(descriptionAll) then
			descriptionAll = langBlocks .. '\n' .. descriptionAll
		else
			descriptionAll = langBlocks
		end
	end
	exportFields['description_all'] = descriptionAll

	-- Structured-data sidebar fields (Metadata panel): depicts (P180) and
	-- created during (P10408). Read as-is; the priority relative to
	-- description_all / the export dialog default is applied in processRenderedPhotos.
	exportFields.depicts = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'depicts') or ''
	exportFields.created_during = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'created_during') or ''

	-- Field "location" (auto-prepended to description_all if GPS data is available)
	local gps = photo:getRawMetadata('gps')
	local LrMajorVersion = LrApplication.versionTable().major -- number type
	local LrVersionString = LrApplication.versionString() -- string with major, minor and revison numbers
	local subText = LOC "$$$/LrMediaWiki/Interface/MessageByLrMediaWiki=Message by LrMediaWiki"
	local locationTemplate = ''
	if gps and gps.latitude and gps.longitude and useLocationInfo then -- Only include {{Location}} if the setting allows it
		local location = '{{Location|' .. gps.latitude .. '|' .. gps.longitude
		if LrMajorVersion >= 6 then
			local heading = photo:getRawMetadata('gpsImgDirection')
			 -- The call of "getRawMetadata" with parameter "gpsImgDirection" is supported since LR 6.0
			if heading then
				location = location .. '|heading:' .. heading -- append heading at location
				local headingRounded = string.format("%.0f", heading) -- rounding, e.g. 359.9876 -> 360
				local hintLine1 = LOC ("$$$/LrMediaWiki/Interface/HintHeadingTrueL1=Hint: The Lightroom field ^[Direction^] has a value of ^1^D.", headingRounded)
				local hintLine2 = LOC ("$$$/LrMediaWiki/Interface/HintHeadingTrueL2=This value has been used to set the ^[heading^] parameter at {{Location}} template.")
				local hintLine3 = LOC ("$$$/LrMediaWiki/Interface/HintHeadingTrueL3=This feature requires a Lightroom version 6/CC or higher.")
				local hintLine4 = LOC ("$$$/LrMediaWiki/Interface/HintHeadingTrueL4=This Lightroom version is ^1, therefore this feature works.", LrVersionString)
				local hintMessage = hintLine1 .. '\n' .. hintLine2 .. '\n' .. hintLine3 .. '\n' .. hintLine4
				local messageTable = {message = hintMessage, info = subText, actionPrefKey = 'Show hint message of used LR version'}
				LrDialogs.messageWithDoNotShow(messageTable)
			end
		elseif LrMajorVersion == 5 then
			local hintLine1 = LOC ("$$$/LrMediaWiki/Interface/HintHeadingFalseL1=Hint: If the Lightroom field ^[Direction^] has a value, this can not be used to set a ^[heading^] parameter at {{Location}} template.")
			local hintLine2 = LOC ("$$$/LrMediaWiki/Interface/HintHeadingFalseL2=This feature requires a Lightroom version 6/CC or higher.")
			local hintLine3 = LOC ("$$$/LrMediaWiki/Interface/HintHeadingFalseL3=This Lightroom version is ^1, therefore this feature works not.", LrVersionString)
			local hintMessage = hintLine1 .. '\n' .. hintLine2 .. '\n' .. hintLine3
			local table = {message = hintMessage, info = subText, actionPrefKey = 'Show hint message of used LR version'}
			LrDialogs.messageWithDoNotShow(table)
		elseif LrMajorVersion == 4 then
			location = location .. '' -- add empty string
		else -- LrMajorVersion < 4
			error 'Unsupported Lightroom version' -- unlikely use case
		end
		location = location .. '}}' -- close Location template
		locationTemplate = location
	end
	-- Prepend location template to description_all if present
	if MediaWikiUtils.isStringFilled(locationTemplate) then
		if MediaWikiUtils.isStringFilled(exportFields['description_all']) then
			exportFields['description_all'] = locationTemplate .. '\n' .. exportFields['description_all']
		else
			exportFields['description_all'] = locationTemplate
		end
	end

	-- Field "categories" (per-file, from plugin metadata)
	exportFields.categories = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'categories') or ''

	-- Fields of infobox template "Artwork":
	local artist = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'artist')
	if MediaWikiUtils.isStringFilled(artist) then
		exportFields.art.artist = artist
	end
	local title = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'title')
	if MediaWikiUtils.isStringFilled(title) then
		exportFields.art.title = title
	end
	local medium = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'medium')
	if MediaWikiUtils.isStringFilled(medium) then
		exportFields.art.medium = medium
	end
	local dimensions = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'dimensions')
	if MediaWikiUtils.isStringFilled(dimensions) then
		exportFields.art.dimensions = dimensions
	end
	local institution = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'institution')
	if MediaWikiUtils.isStringFilled(institution) then
		exportFields.art.institution = institution
	end
	local department = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'department')
	if MediaWikiUtils.isStringFilled(department) then
		exportFields.art.department = department
	end
	local accessionNumber = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'accessionNumber')
	if MediaWikiUtils.isStringFilled(accessionNumber) then
		exportFields.art.accessionNumber = accessionNumber
	end
	local placeOfCreation = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'placeOfCreation')
	if MediaWikiUtils.isStringFilled(placeOfCreation) then
		exportFields.art.placeOfCreation = placeOfCreation
	end
	local placeOfDiscovery = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'placeOfDiscovery')
	if MediaWikiUtils.isStringFilled(placeOfDiscovery) then
		exportFields.art.placeOfDiscovery = placeOfDiscovery
	end
	local objectHistory = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'objectHistory')
	if MediaWikiUtils.isStringFilled(objectHistory) then
		exportFields.art.objectHistory = objectHistory
	end
	local exhibitionHistory = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'exhibitionHistory')
	if MediaWikiUtils.isStringFilled(exhibitionHistory) then
		exportFields.art.exhibitionHistory = exhibitionHistory
	end
	local creditLine = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'creditLine')
	if MediaWikiUtils.isStringFilled(creditLine) then
		exportFields.art.creditLine = creditLine
	end
	local inscriptions = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'inscriptions')
	if MediaWikiUtils.isStringFilled(inscriptions) then
		exportFields.art.inscriptions = inscriptions
	end
	local notes = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'notes')
	if MediaWikiUtils.isStringFilled(notes) then
		exportFields.art.notes = notes
	end
	local references = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'references')
	if MediaWikiUtils.isStringFilled(references) then
		exportFields.art.references = references
	end
	local wikidata = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'wikidata')
	if MediaWikiUtils.isStringFilled(wikidata) then
		exportFields.art.wikidata = wikidata
	end
	local object = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'object')
	if MediaWikiUtils.isStringFilled(object) then
		exportFields.objectPhoto.object = object
	end
	local detail = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'detail')
	if MediaWikiUtils.isStringFilled(detail) then
		exportFields.objectPhoto.detail = detail
	end
	local detailPosition = photo:getPropertyForPlugin(Info.LrToolkitIdentifier, 'detailPosition')
	if MediaWikiUtils.isStringFilled(detailPosition) then
		exportFields.objectPhoto.detailPosition = detailPosition
	end

	return exportFields
end

local getUseLocationInfo = function(propertyTable)
	-- determine if the switch "Remove Location Info" is set or not at Export dialog section "Metadata"
	local useLocationInfo = true
	for key, value in pairs(propertyTable) do
		for key2, value2 in pairs(value) do
			if key2 == 'LR_removeLocationMetadata' then
				useLocationInfo = not value2
			end
		end
	end
	return useLocationInfo
end

local preparePreviewText = function(propertyTable, photo)
	local useLocationInfo = getUseLocationInfo(propertyTable)
	local ExportFields = fillFieldsByFile(propertyTable, photo, useLocationInfo)
	local wikitext = MediaWikiInterface.buildFileDescription(ExportFields, photo)

	-- substitute placeholders in export dialog field "gallery"
	if MediaWikiUtils.isStringFilled(propertyTable.gallery) then
		local arguments = {}
		arguments = MediaWikiUtils.currentDate(arguments) -- get list of date related placeholders
		local substitutedGallery = MediaWikiUtils.substitutePlaceholders(propertyTable.gallery, arguments)
		wikitext = wikitext .. "\nGallery: " .. substitutedGallery
	end
	return wikitext
end

local copyToClipboard = function(clipboardText, fileName)
  local fileNameLabel = LOC "$$$/LrMediaWiki/Preview/FileName=File Name" .. ": " -- used twice
	clipboardText = clipboardText .. "\n" .. fileNameLabel .. fileName
	local copyCmd
	if WIN_ENV == true then
		-- Windows "echo" command doesn't work with the pipes and newlines of the cliboardText.
		-- Workaround: A temporary file is used to allow "clip < file".
		LrTasks.startAsyncTask( function ()
			local tmpFile = os.tmpname()
			local fd = assert(io.open(tmpFile, "w+"))
			fd:write(clipboardText)
			copyCmd = "chcp 65001 & clip < " .. tmpFile -- chcp 65001 == change code page to UTF-8
			io.close(fd)
			LrTasks.execute(copyCmd)
		end)
	elseif MAC_ENV == true then
		-- Frueher wurde der Text direkt in die Shell-Zeile eingesetzt
		-- (echo "<Text>" | pbcopy). Der Text ist aber der Vorschau-Wikitext
		-- und enthaelt frei eingegebene Beschreibung und Felder; ein " oder
		-- $(...) darin waere Shell-Befehlseinschleusung. Deshalb wie unter
		-- Windows ueber eine TEMPORAERE DATEI, die pbcopy nur noch LIEST -
		-- nichts vom Inhalt landet mehr in der Kommandozeile.
		LrTasks.startAsyncTask( function ()
			local tmpFile = os.tmpname()
			local fd = assert(io.open(tmpFile, "w+"))
			fd:write(clipboardText)
			io.close(fd)
			copyCmd = "export LANG=en_US.UTF-8; pbcopy < '" .. tmpFile .. "'"
			LrTasks.execute(copyCmd)
			os.remove(tmpFile)
		end)
	end
end

local showPreview = function(propertyTable)
	-- This function to provide a preview message box needs to run as a separate task,
	-- according to this discussion post: <https://forums.adobe.com/message/8493589#8493589>
	LrTasks.startAsyncTask( function ()
		LrFunctionContext.callWithContext ('showPreview', function(context) -- luacheck: ignore context
			local properties = LrBinding.makePropertyTable(context)
			local activeCatalog = LrApplication.activeCatalog()
			properties.photoList = activeCatalog:getTargetPhotos()
			local photo = properties.photoList[1] -- first photo of the selection
			properties.fileName = photo:getFormattedMetadata('fileName')
			properties.index = 1

			local setCurrentOfAll = function(current)
				properties.currentOfAll = current .. '/' .. #properties.photoList
			end

			local setPhoto = function(pos)
				local max = #properties.photoList
				if pos == 'first' then
					properties.index = 1
				elseif pos == 'previous' then
					if properties.index > 1 then
						properties.index = properties.index - 1
					else -- we are at first position
						return
					end
				elseif pos == 'next' then
					if properties.index < max then
						properties.index = properties.index + 1
					else -- we are at last position
						return
					end
				elseif pos == 'last' then
					properties.index = max
				else -- invalid parameter "pos"
					return
				end

				LrTasks.startAsyncTask( function ()
					setCurrentOfAll(properties.index)

					photo = properties.photoList[properties.index]
					properties.fileName = photo:getFormattedMetadata('fileName')
					properties.dialogValue = preparePreviewText(propertyTable, photo)
				end)
			end

			setCurrentOfAll(1)
			local result, message = MediaWikiInterface.loadFileDescriptionTemplate(propertyTable.info_template)
			if not result then
				LrDialogs.message(LOC "$$$/LrMediaWiki/Export/DescriptionError=Error reading the file description", message, 'error')
				return
			end

			local wikitext = preparePreviewText(propertyTable, photo)
			local dialogTitle = LOC "$$$/LrMediaWiki/Section/UploadInformation/Preview=Preview of generated wikitext"
			local factory = LrView.osFactory()
			properties.dialogValue = wikitext

			local theWikiText = factory:static_text {
				title = LrView.bind('dialogValue'),
				height_in_lines = -1, -- to let the text wrap
				width_in_chars = 60, -- text wrap needs a value too
				height = 200, -- initial value
				fill_horizontal = 1,
				fill_vertical = 1,
				font = { -- see [1]
					name = MediaWikiUtils.getPreviewWikitextFontName(),
					size = MediaWikiUtils.getPreviewWikitextFontSize(),
				},
				immediate = true, -- NEW
				tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipWikitext=Font name and font size of the wikitext are customizable at the plug-in’s configuration.",
			}

			local fileName = factory:static_text {
				bind_to_object = properties,
				title = LrView.bind('fileName'),
				width_in_chars = 30,
				fill_horizontal = 1,
				tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipFileName=Current file name",
			}

			local contents = factory:column {
				fill_horizontal = 1,
				fill_vertical = 1,
				spacing = factory:label_spacing(),
				factory:row {
					fill_vertical = 1,
					bind_to_object = properties,
					theWikiText,
				},
				factory:row {
					factory:separator {
						fill_horizontal = 1, -- "1" means full width
					},
				},
				factory:row {
					factory:push_button {
						-- | + U+25C0 = BLACK LEFT-POINTING TRIANGLE = |◀
						title = '|◀',
						action = function() setPhoto('first') end,
						tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipButtonFirst=First file",
					},
					factory:push_button {
						-- U+25C0 = BLACK LEFT-POINTING TRIANGLE = ◀
						title = '◀',
						action = function() setPhoto('previous') end,
						tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipButtonPrevious=Previous file",
					},
					factory:push_button {
						-- U+25B6 = BLACK RIGHT-POINTING TRIANGLE = ▶
						title = '▶',
						action = function() setPhoto('next') end,
						tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipButtonNext=Next file",
					},
					factory:push_button {
						-- U+25B6 + | = BLACK RIGHT-POINTING TRIANGLE = ▶|
						title = '▶|',
						action = function() setPhoto('last') end,
						tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipButtonLast=Last file",
					},
					factory:push_button {
						title = LOC "$$$/LrMediaWiki/Preview/ButtonCopyToClipboard=Copy to clipboard",
						action = function() copyToClipboard(theWikiText.title, fileName.title) end,
						tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipButtonCopyToClipboard=Copies text to clipboard",
					},
					factory:static_text {
						bind_to_object = properties,
						title = LrView.bind('currentOfAll'),
						width_in_chars = 30,
						tooltip = LOC "$$$/LrMediaWiki/Preview/TooltipCurrentOfAll=Current index in relation to the total number of selected files",
					},
				},
				factory:row {
					factory:static_text {
						title = LOC "$$$/LrMediaWiki/Preview/FileName=File Name" .. ':', -- used twice
					},
					fileName,
				},
			}

			LrDialogs.presentModalDialog({
				title = dialogTitle,
				contents = contents,
				-- cancelVerb = '< exclude >', -- no cancel button
				resizable = true,
				save_frame= 'PreviewDialogSaveFrame',
			})

		end)
	end)
end

--------------------------------------------------------------------------------
-- OAuth 2.0 login (see MediaWikiOAuth.lua)
--------------------------------------------------------------------------------

-- Refreshes the three OAuth-related dialog properties from what is stored.
-- (Local functions: they are defined before every use site – startDialog and
-- the button actions in sectionsForTopOfDialog – so no globals are needed.)
local function updateOAuthStatus(propertyTable)
	local apiPath = propertyTable.api_path
	propertyTable.oauth_available = MediaWikiOAuth.isConfigured()
	if not MediaWikiOAuth.isConfigured() then
		propertyTable.oauth_logged_in = false
		propertyTable.oauth_status = LOC "$$$/LrMediaWiki/OAuth/Unconfigured=This build has no OAuth client ID – please use username and password."
		return
	end
	local token = MediaWikiOAuth.loadToken(apiPath)
	if token then
		propertyTable.oauth_logged_in = true
		local name = token.username
		if name and name ~= '' then
			propertyTable.oauth_status = LOC("$$$/LrMediaWiki/OAuth/LoggedInAs=Logged in as “^1”. Username and password below are not used.", name)
		else
			propertyTable.oauth_status = LOC "$$$/LrMediaWiki/OAuth/LoggedIn=Logged in. Username and password below are not used."
		end
	else
		propertyTable.oauth_logged_in = false
		propertyTable.oauth_status = LOC "$$$/LrMediaWiki/OAuth/NotLoggedIn=Not logged in – either log in with the browser or enter username and password."
	end
end

local function oauthLogin(propertyTable)
	local apiPath = propertyTable.api_path

	-- The browser page cannot be styled: LrSocket acknowledges every received
	-- line with "ok" by itself, so that is what the user will see there. Say
	-- so beforehand, otherwise a successful login looks like a failure.
	local proceed = LrDialogs.confirm(
		LOC "$$$/LrMediaWiki/OAuth/AboutTitle=Log in with your Wikimedia account",
		LOC("$$$/LrMediaWiki/OAuth/AboutText=Your browser will open so you can confirm the access.^n^nAfterwards the browser shows a page containing only the word “ok” several times. That is normal and means it worked – simply switch back to Lightroom.^n^n(Port ^1 on this computer is used briefly for the response.)", tostring(MediaWikiOAuth.port)),
		LOC "$$$/LrMediaWiki/OAuth/Continue=Open browser",
		LOC "$$$/LrMediaWiki/Cancel=Cancel")
	if proceed ~= 'ok' then
		return
	end

	propertyTable.oauth_status = LOC "$$$/LrMediaWiki/OAuth/Waiting=Waiting for confirmation in the browser…"

	LrFunctionContext.postAsyncTaskWithContext('LrMediaWikiOAuthLogin', function(context)
		local ok, message = MediaWikiOAuth.authorize(context, apiPath)
		if not ok then
			propertyTable.oauth_status = LOC("$$$/LrMediaWiki/OAuth/Failed=Login failed: ^1", tostring(message))
			return
		end

		-- Confirm the token really works and find out who it belongs to.
		MediaWikiApi.apiPath = apiPath
		local accessToken = MediaWikiOAuth.getValidAccessToken(apiPath)
		MediaWikiApi.setAccessToken(accessToken)
		local user = MediaWikiApi.getLoggedInUser()
		MediaWikiApi.setAccessToken(nil)
		if user then
			MediaWikiOAuth.setStoredUsername(apiPath, user)
			if MediaWikiUtils.isStringEmpty(propertyTable.username) then
				propertyTable.username = user
			end
		end
		updateOAuthStatus(propertyTable)
	end)
end

local function oauthLogout(propertyTable)
	MediaWikiOAuth.clearToken(propertyTable.api_path)
	MediaWikiApi.setAccessToken(nil)
	updateOAuthStatus(propertyTable)
end

MediaWikiExportServiceProvider.startDialog = function(propertyTable)
	updateOAuthStatus(propertyTable)
	-- Keep the status line in sync when the user switches to another wiki.
	propertyTable:addObserver('api_path', function()
		updateOAuthStatus(propertyTable)
	end)
	if MediaWikiUtils.isStringFilled(propertyTable.password) then
		MediaWikiUtils.storePassword(propertyTable.api_path, propertyTable.username, propertyTable.password)
	else
		propertyTable.password = MediaWikiUtils.retrievePassword(propertyTable.api_path, propertyTable.username)
	end
	-- Color label on export: global plug-in preference (single source of
	-- truth, shared with the Plug-in Manager section).
	propertyTable.export_color = MediaWikiUtils.getExportColor()
end

MediaWikiExportServiceProvider.endDialog = function(propertyTable)
	if MediaWikiUtils.isStringFilled(propertyTable.password) then
		-- Don't store password in preferences!
		-- Preferences are stored at file system and can read out from there.
		-- Therefore delete field "password" from property table:
		propertyTable.password = nil
	end
	MediaWikiUtils.setExportColor(propertyTable.export_color)
end

MediaWikiExportServiceProvider.processRenderedPhotos = function(functionContext, exportContext) -- luacheck: ignore functionContext
	-- configure progress display
	local exportSession = exportContext.exportSession
	local photoCount = exportSession:countRenditions()
	local MessageMultiple = LOC("$$$/LrMediaWiki/Export/Progress=Exporting ^1 photos to a MediaWiki", photoCount)
	local MessageSingle = LOC "$$$/LrMediaWiki/Export/Progress/One=Exporting one photo to a MediaWiki"
	exportContext:configureProgress{
		title = photoCount > 1 and MessageMultiple or MessageSingle
	}

	local exportSettings = assert(exportContext.propertyTable)

	if MediaWikiUtils.isStringEmpty(exportSettings.api_path) then
		LrErrors.throwUserError(LOC "$$$/LrMediaWiki/Export/NoApiPath=No API path given!")
	end

	-- With an OAuth token stored for this wiki, username and password are not
	-- needed at all; prepareUpload will use the token.
	local hasOAuth = MediaWikiOAuth.loadToken(exportSettings.api_path) ~= nil

	if not hasOAuth then
		-- require username, password, source, author, license
		if MediaWikiUtils.isStringEmpty(exportSettings.username) then
			LrErrors.throwUserError(LOC "$$$/LrMediaWiki/Export/NoUsername=No username given!")
		end

		exportSettings.password = MediaWikiUtils.retrievePassword(exportSettings.api_path, exportSettings.username)
		if MediaWikiUtils.isStringEmpty(exportSettings.password) then
			LrErrors.throwUserError(LOC "$$$/LrMediaWiki/Export/NoPassword=No password given!")
		end
	end

	if MediaWikiUtils.isStringEmpty(exportSettings.info_permission) and MediaWikiUtils.isStringEmpty(exportSettings.info_license) then
		LrErrors.throwUserError(LOC "$$$/LrMediaWiki/Export/NoPermissionLicense=No permission or license given!")
	end

	local updateCommentForAll = ''
	if exportSettings.info_mode == 'UpdateOnly' then
		updateCommentForAll = MediaWikiInterface.prompt(LOC "$$$/LrMediaWiki/Export/UpdateOnlyPromptTitle=Leave empty or Cancel to set comments per file",
														LOC "$$$/LrMediaWiki/Export/UpdateOnlyPromptLabel=Update comment for all selected files")
	end

	--if not MediaWikiInterface.loggedIn then
		MediaWikiInterface.prepareUpload(exportSettings.username, exportSettings.password, exportSettings.api_path, exportSettings.info_template)
	--end

	-- file entries for gallery creation (fileName + caption)
	local fileEntries = {}

	local useLocationInfo = getUseLocationInfo(exportContext.propertyTable)

	-- iterate over photos
	for i, rendition in exportContext:renditions() do -- luacheck: ignore i
		-- render photo
		local success, pathOrMessage = rendition:waitForRender()
		if success then
			local photo = rendition.photo
			local catalog = photo.catalog
			-- do upload to MediaWiki
			local artworkParameters = { -- Parameters of infobox template "Artwork" without "description" and "permission"
				artist = '',
				title = '',
				date = '',
				medium = '',
				dimensions = '',
				institution = '',
				department = '',
				accessionNumber = '',
				placeOfCreation = '',
				placeOfDiscovery = '',
				objectHistory = '',
				exhibitionHistory = '',
				creditLine = '',
				inscriptions = '',
				notes = '',
				references = '',
				wikidata = '',
			}
			local objectPhotoParameters = { -- Parameters of infobox template "Object photo" without "description" and "permission"
				object = '',
				detail = '',
				detailPosition = '',
			}
			local exportFields = { -- Fields set at export dialog, ordered by UI
				info_template = exportSettings.info_template,
				info_mode = exportSettings.info_mode,
				info_language = exportSettings.info_language,
				info_source = exportSettings.info_source,
				info_author = exportSettings.info_author,
				info_permission = exportSettings.info_permission,
				info_license = exportSettings.info_license,
				info_templates = exportSettings.info_templates,
				info_categories = exportSettings.info_categories,
				-- fields by file, to be filled by fillFieldsByFile()
				caption_en = '',
				['description_all'] = '',
				categories = '',
				art = artworkParameters, -- Parameters of infobox template "Artwork"
				objectPhoto = objectPhotoParameters, -- Parameters of infobox template "Object photo"
			}

			local filledExportFields = fillFieldsByFile(exportFields, photo, useLocationInfo)
			local fileDescription, arguments
			fileDescription, success, arguments = MediaWikiInterface.buildFileDescription(filledExportFields, photo)

			if success == false then
				local mesg = LOC("$$$/LrMediaWiki/Export/CancelMessage=The export failed due to empty variable or faulty placeholder name.")
				rendition:uploadFailed(mesg)
				return -- Stop any further export, neither this one nor other in the queue
			end

			-- ensure that the target file name does not contain a series of spaces or
			-- underscores (as this would cause the upload to fail without a proper
			-- error message)
			local fileName = string.gsub(LrPathUtils.leafName(pathOrMessage), '[ _]+', '_')
			local hasDescription = MediaWikiUtils.isStringFilled(filledExportFields['description_all'])
			local message = MediaWikiInterface.uploadFile(pathOrMessage, fileDescription, hasDescription, fileName, exportSettings.info_mode, updateCommentForAll)
			if message then
				rendition:uploadFailed(message)
			else
				-- Clear cached token after upload so structured data calls get a fresh token
				MediaWikiApi.clearEditToken()
				-- publish structured data (captions + claims)
				if MediaWikiUtils.getStructuredData() then -- Only if structured data is supported by the server
					-- Attach structuredData extracted from description_all to filledExportFields
					filledExportFields.structuredData = arguments.structuredData or {}
					-- Set all structured data (labels + claims) in a single API call
					local sd = filledExportFields.structuredData or {}
					-- Per-photo sidebar fields (Metadata panel) take priority over any
					-- depicts=/created_during= line in description_all. The batch-level
					-- default below only applies if neither of them is set.
					if MediaWikiUtils.isStringFilled(filledExportFields.depicts) then
						sd.depicts = filledExportFields.depicts
					end
					if MediaWikiUtils.isStringFilled(filledExportFields.created_during) then
						sd.created_during = filledExportFields.created_during
					end
					-- Merge batch-level SDC defaults from the export dialog:
					-- creator (P170), copyright (P6216), license (P275) and
					-- created during (P10408). A value set per file via
					-- description_all takes priority over the batch default.
					if not MediaWikiUtils.isStringFilled(sd.creator) then
						sd.creator = normalizeSdcQid(exportSettings.sdc_creator)
					end
					if not MediaWikiUtils.isStringFilled(sd.copyright) then
						sd.copyright = normalizeSdcQid(exportSettings.sdc_copyright)
					end
					if not MediaWikiUtils.isStringFilled(sd.license) then
						sd.license = normalizeSdcQid(exportSettings.sdc_license)
					end
					if not MediaWikiUtils.isStringFilled(sd.created_during) then
						sd.created_during = normalizeSdcQid(exportSettings.sdc_created_during)
					end
					-- A file has structured data if it has any caption (en from the
					-- caption_en field or any caption_XX language), or any claim.
					local hasAnyCaption = MediaWikiUtils.isStringFilled(filledExportFields.caption_en)
					if not hasAnyCaption then
						for k, v in pairs(sd) do
							if k:match('^caption_') and MediaWikiUtils.isStringFilled(v) then
								hasAnyCaption = true
								break
							end
						end
					end
					local hasStructuredData =
						hasAnyCaption
						or MediaWikiUtils.isStringFilled(sd.creator)
						or MediaWikiUtils.isStringFilled(sd.copyright)
						or MediaWikiUtils.isStringFilled(sd.license)
						or MediaWikiUtils.isStringFilled(sd.created_during)
						or MediaWikiUtils.isStringFilled(sd.depicts)
					if hasStructuredData then
						message = MediaWikiInterface.wbSetStructuredData(filledExportFields, fileName)
						if message then
							rendition:uploadFailed(message)
						end
					end
				end
				-- create new snapshot if the upload was successful
				if MediaWikiUtils.getCreateSnapshots() then
					local currentTimeStamp = LrDate.currentTime()
					local currentDate = LrDate.formatShortDate(currentTimeStamp)
					local currentTime = LrDate.formatShortTime(currentTimeStamp)
					local snapshotTitle = LOC("$$$/LrMediaWiki/Export/Snapshot=MediaWiki export, ^1 ^2, ^3", currentDate, currentTime, exportSettings.api_path)
					catalog:withWriteAccessDo('CreateDevelopSnapshot', function(context) -- luacheck: ignore context
						photo:createDevelopSnapshot(snapshotTitle, true)
					end)
				end

				-- mark image with color label
				local color = MediaWikiUtils.getExportColor()
				if color ~= nil then
					catalog:withWriteAccessDo('SetColorLabel', function(context) -- luacheck: ignore context
						photo:setRawMetadata('colorNameForLabel', color); 
					end)
				end

				-- add configured export keyword
				local keyword = MediaWikiUtils.getExportKeyword()
				if MediaWikiUtils.isStringFilled(keyword) then
					catalog:withWriteAccessDo('AddExportKeyword', function(context) -- luacheck: ignore context
						photo:addKeyword(catalog:createKeyword(keyword, {}, false, nil, true))
					end)
				end

				-- Small delay to avoid hitting rate limits (429)
				LrTasks.sleep(0.5)
				-- file entry for gallery creation (fileName + caption_en)
				local captionForGallery = filledExportFields.caption_en or ''
				if captionForGallery == '' and arguments and arguments.structuredData then
					captionForGallery = arguments.structuredData.caption_en or ''
				end
				fileEntries[#fileEntries + 1] = { fileName = fileName, caption = captionForGallery }
			end
			LrFileUtils.delete(pathOrMessage)
		else
			-- rendering failed --> report failure
			rendition:uploadFailed(pathOrMessage)
		end
	end

	-- add gallery
	if MediaWikiUtils.isStringFilled(exportSettings.gallery) and fileEntries and #fileEntries > 0 then
		local galleryArguments = {}
		galleryArguments = MediaWikiUtils.currentDate(galleryArguments)
		local substitutedGallery = MediaWikiUtils.substitutePlaceholders(exportSettings.gallery, galleryArguments)
		MediaWikiInterface.addToGallery(fileEntries, substitutedGallery)
	end
end

MediaWikiExportServiceProvider.sectionsForTopOfDialog = function(viewFactory, propertyTable)
	local labelAlignment = 'right'

	-- The OAuth properties are deliberately NOT export preset fields (they
	-- would end up on disk), so make sure they exist before anything binds to
	-- them, no matter in which order Lightroom calls startDialog.
	if propertyTable.oauth_status == nil then
		updateOAuthStatus(propertyTable)
	end

	-- The following tooltips are used twice, at the label and at the field. They are set as variables to avoid redundancy.
	local usernameTooltip = LOC "$$$/LrMediaWiki/Section/LoginInformation/UsernameTooltip=Username^n^nRequired field. Enter the username of your MediaWiki account."
	local passwordTooltip = LOC "$$$/LrMediaWiki/Section/LoginInformation/PasswordTooltip=Password^n^nRequired field. Enter the password of your MediaWiki account."
	local apiPathTooltip = LOC "$$$/LrMediaWiki/Section/LoginInformation/ApiPathTooltip=API Path^n^nRequired field. To determine the path, go to “Special:Version” → “Entry point URLs” → “api.php” of the intended MediaWiki."
	local infoboxTemplateTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/InfoboxTemplateTooltip=Infobox Template^n^nThese are mainly templates of Wikimedia Commons. “Information (de)” is the template “Information” of the German language Wikipedia."
	local modeTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/Mode/ModeTooltip=Choose “Upload only” if no new files should be uploaded."
	local languageOtherTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/LanguageOtherTooltip=Language of “Description (other)”"
	local sourceTooltip  = LOC "$$$/LrMediaWiki/Metadata/SourceTooltip=Source^n^nRequired field. Should be set per file or at export dialog. Setting per file has priority over setting at export dialog. Example: {{own}}.^nThe field is named “Source/Photographer” at infobox template “Artwork”."
	local authorTooltip = LOC "$$$/LrMediaWiki/Metadata/AuthorTooltip=Author^n^nRequired field, if not “Artwork” has been chosen (“Artwork” recommends to use “Artist” or “Author”).^nShould be set per file or at export dialog. Setting per file has priority over setting at export dialog. Example:^n  [[User:MyUserName|MyRealName]]"
	local permissionTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/PermisssionTooltip=Permission^n^nPermission information like {{PermissionOTRS}}. Either this field or “License” should be set."
	local otherTemplatesTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/OtherTemplatesTooltip=Other Templates^n^nOther templates are inserted after the infobox template and before the licensing section. Examples:^n  {{Panorama}}^n  {{Personality rights}}^n  {{Location estimated}}"
	local otherFieldsTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/OtherFieldsTooltip=Other fields^n^nExtra wikitext/templates inserted after the infobox template (same position as Other Templates). Applies to all files of this export. Examples:^n  {{Credit line}}^n  {{Information field}}"
	local licenseTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/LicenseTooltip=License^n^nThe license template to use, e.g. {{Cc-by-sa-4.0}}. Either this field or “Permission” should be set."
	local categoriesTooltip = LOC "$$$/LrMediaWiki/Metadata/CategoriesTooltip=Categories^n^nThe categories all uploaded images should be added to; without the prefix “Category:” and without square brackets [[…]]. Multiple categories are separated by a ; (semicolon)."
	local galleryTooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/GalleryTooltip=Gallery^n^nIf this field is set, a gallery of your uploads will be added to the page with the specified title. Current date related placeholders are recognized. Example:^n  User:MyUserName/My Uploads at <currentLongDate>"

	return {
		{	-- first section
			title = LOC "$$$/LrMediaWiki/Section/LoginInformation/Title=LrMediaWiki Login Information",
			synopsis = bind 'api_path',

			-- OAuth 2.0 login. When a token is stored, username and password
			-- below are ignored entirely.
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/LoginInformation/OAuth=Wikimedia account" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
				},
				viewFactory:push_button {
					title = LOC "$$$/LrMediaWiki/Section/LoginInformation/OAuthLogin=Log in with browser…",
					enabled = bind 'oauth_available',
					action = function()
						oauthLogin(propertyTable)
					end,
				},
				viewFactory:push_button {
					title = LOC "$$$/LrMediaWiki/Section/LoginInformation/OAuthLogout=Log out",
					enabled = bind 'oauth_logged_in',
					action = function()
						oauthLogout(propertyTable)
					end,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = '',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
				},
				-- Bound static_text titles are proven to update in this SDK
				-- (bound push_button titles are not), so all OAuth feedback
				-- goes here.
				viewFactory:static_text {
					title = bind 'oauth_status',
					fill_horizontal = 1,
					width_in_chars = 55,
				},
			},

			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/LoginInformation/Username=Username" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = usernameTooltip,
				},
				viewFactory:edit_field {
					value = bind 'username',
					immediate = true,
					fill_horizontal = 1,
					tooltip = usernameTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/LoginInformation/Password=Password" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = passwordTooltip,
				},
				viewFactory:password_field {
					value = bind 'password',
					immediate = true,
					validate = function(view, password) -- luacheck: ignore view
						MediaWikiUtils.storePassword(propertyTable.api_path, propertyTable.username, password)
						return true, password
					end,
					fill_horizontal = 1,
					tooltip = passwordTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/LoginInformation/ApiPath=API Path" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = apiPathTooltip,
				},
				viewFactory:combo_box {
					value = bind 'api_path',
					immediate = true,
					fill_horizontal = 1,
					items = {
						'https://commons.wikimedia.org/w/api.php',
						'https://commons.wikimedia.beta.wmflabs.org/w/api.php',
						'https://en.wikipedia.org/w/api.php',
						'https://de.wikipedia.org/w/api.php',
					},
					tooltip = apiPathTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorLabel=Color label on export" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = LOC "$$$/LrMediaWiki/Section/Config/ExportColorTooltip=After a successful upload, this color label is set on the photo. Global plug-in setting – the same value as in the Plug-in Manager.",
				},
				viewFactory:popup_menu {
					value = bind 'export_color',
					fill_horizontal = 1,
					items = {
						{ title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorRed=Red", value = 'red' },
						{ title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorYellow=Yellow", value = 'yellow' },
						{ title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorGreen=Green", value = 'green' },
						{ title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorBlue=Blue", value = 'blue' },
						{ title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorPurple=Purple", value = 'purple' },
						{ title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorNone=None", value = 'none' },
						{ title = LOC "$$$/LrMediaWiki/Section/Config/ExportColorUnchanged=Unchanged", value = nil },
					},
					tooltip = LOC "$$$/LrMediaWiki/Section/Config/ExportColorTooltip=After a successful upload, this color label is set on the photo. Global plug-in setting – the same value as in the Plug-in Manager.",
				},
			},
		},
		{	-- second section
			title = LOC "$$$/LrMediaWiki/Section/UploadInformation/Title=LrMediaWiki Upload Information",
			synopsis = bind 'info_template',

			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/InfoboxTemplate=Infobox Template" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = infoboxTemplateTooltip,
				},
				viewFactory:popup_menu {
					value = bind 'info_template',
					items = {
						'Information',
						'Information (de)',
						'Artwork',
						'Object photo',
					},
					tooltip = infoboxTemplateTooltip,
				},
				viewFactory:push_button {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/Preview=Preview of generated wikitext",
						action = function(button) -- luacheck: ignore button
							showPreview(propertyTable)
						end,
					tooltip = LOC "$$$/LrMediaWiki/Section/UploadInformation/PreviewTooltip=The preview shows how the wikitext of the file description page will look.",
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/Mode=Mode" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = modeTooltip,
				},
				viewFactory:popup_menu {
					value = bind 'info_mode',
					items = {
						{
							value = 'Standard',
							title = LOC "$$$/LrMediaWiki/Section/UploadInformation/Mode/Standard=Standard"
						},
						{
							value = 'UpdateOnly',
							title = LOC "$$$/LrMediaWiki/Section/UploadInformation/Mode/UpdateOnly=Update only"
						},
					},
					tooltip = modeTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/LanguageOther=Language (other)" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = languageOtherTooltip,
				},
				viewFactory:popup_menu {
					value = bind 'info_language',
					items = {
						{
							value = '',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/None=None"
						},
						{
							value = 'ar',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ar=ar – Arabic"
						},
						{
							value = 'be',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/be=be – Belarusian"
						},
						{
							value = 'bg',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/bg=bg – Bulgarian"
						},
						{
							value = 'bn',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/bn=bn – Bangla"
						},
						{
							value = 'ca',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ca=ca – Catalan"
						},
						{
							value = 'cs',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/cs=cs – Czech"
						},
						{
							value = 'da',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/da=da – Danish"
						},
						{
							value = 'el',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/el=el – Greek"
						},
						{
							value = 'es',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/es=es – Spanish"
						},
						{
							value = 'et',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/et=et – Estonian"
						},
						{
							value = 'fa',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/fa=fa – Persian"
						},
						{
							value = 'fi',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/fi=fi – Finnish"
						},
						{
							value = 'fr',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/fr=fr – French"
						},
						{
							value = 'ga',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ga=ga – Irish"
						},
						{
							value = 'he',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/he=he – Hebrew"
						},
						{
							value = 'hi',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/hi=hi – Hindi"
						},
						{
							value = 'hr',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/hr=hr – Croatian"
						},
						{
							value = 'hu',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/hu=hu – Hungarian"
						},
						{
							value = 'hy',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/hy=hy – Armenian"
						},
						{
							value = 'id',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/id=id – Indonesian"
						},
						{
							value = 'is',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/is=is – Icelandic"
						},
						{
							value = 'it',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/it=it – Italian"
						},
						{
							value = 'ja',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ja=ja – Japanese"
						},
						{
							value = 'ka',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ka=ka – Georgian"
						},
						{
							value = 'ko',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ko=ko – Korean"
						},
						{
							value = 'la',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/la=la – Latin"
						},
						{
							value = 'lt',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/lt=lt – Lithuanian"
						},
						{
							value = 'lv',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/lv=lv – Latvian"
						},
						{
							value = 'mk',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/mk=mk – Macedonian"
						},
						{
							value = 'nb',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/nb=nb – Norwegian Bokmål"
						},
						{
							value = 'nl',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/nl=nl – Dutch"
						},
						{
							value = 'nn',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/nn=nn – Norwegian Nynorsk"
						},
						{
							value = 'pl',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/pl=pl – Polish"
						},
						{
							value = 'pt',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/pt=pt – Portuguese"
						},
						{
							value = 'ro',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ro=ro – Romanian"
						},
						{
							value = 'ru',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/ru=ru – Russian"
						},
						{
							value = 'sk',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/sk=sk – Slovak"
						},
						{
							value = 'sl',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/sl=sl – Slovenian"
						},
						{
							value = 'sr',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/sr=sr – Serbian"
						},
						{
							value = 'sv',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/sv=sv – Swedish"
						},
						{
							value = 'th',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/th=th – Thai"
						},
						{
							value = 'tr',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/tr=tr – Turkish"
						},
						{
							value = 'uk',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/uk=uk – Ukrainian"
						},
						{
							value = 'vi',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/vi=vi – Vietnamese"
						},
						{
							value = 'yi',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/yi=yi – Yiddish"
						},
						{
							value = 'zh',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/zh=zh – Chinese (Simplified)"
						},
						{
							value = 'zh-hant',
							title = LOC "$$$/LrMediaWiki/Metadata/Language/zh-hant=zh-hant – Chinese (Traditional)"
						},
					},
					tooltip = languageOtherTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Metadata/Source=Source" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = sourceTooltip,
				},
				viewFactory:edit_field {
					value = bind 'info_source',
					immediate = true,
					fill_horizontal = 1,
					tooltip = sourceTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Metadata/Author=Author" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = authorTooltip,
				},
				viewFactory:edit_field {
					value = bind 'info_author',
					immediate = true,
					fill_horizontal = 1,
					tooltip = authorTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/Permission=Permission" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = permissionTooltip,
				},
				viewFactory:edit_field {
					value = bind 'info_permission',
					immediate = true,
					fill_horizontal = 1,
					tooltip = permissionTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/OtherTemplates=Other Templates" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = otherTemplatesTooltip,
				},
				viewFactory:edit_field {
					value = bind 'info_templates',
					immediate = true,
					fill_horizontal = 1,
					tooltip = otherTemplatesTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/OtherFields=Other fields" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = otherFieldsTooltip,
				},
				viewFactory:edit_field {
					value = bind 'other_fields',
					immediate = true,
					fill_horizontal = 1,
					tooltip = otherFieldsTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/License=License" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = licenseTooltip,
				},
				viewFactory:combo_box {
					value = bind 'info_license',
					immediate = true,
					fill_horizontal = 1,
					items = {
						'{{Cc-by-sa-4.0}}',
						'{{Cc-by-4.0}}',
						'{{Cc-zero}}',
					},
					tooltip = licenseTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Metadata/Categories=Categories" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = categoriesTooltip,
				},
				viewFactory:edit_field {
					value = bind 'info_categories',
					immediate = true,
					fill_horizontal = 1,
					height_in_lines = 3,
					tooltip = categoriesTooltip,
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/UploadInformation/Gallery=Gallery" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = galleryTooltip,
				},
				viewFactory:edit_field {
					value = bind 'gallery',
					immediate = true,
					fill_horizontal = 1,
					tooltip = galleryTooltip,
				},
			},
		},
		{	-- third section: Structured Data (SDC), batch-level defaults
			title = LOC "$$$/LrMediaWiki/Section/StructuredData/Title=LrMediaWiki Structured Data (SDC)",
			synopsis = bind 'sdc_license',

			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/StructuredData/Creator=Creator (P170)" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/CreatorTooltip=Creator (P170)^n^nWikidata QID of the author or photographer, e.g. Q640. Applies to every file in this export. A per-file creator= line in “Raw Metadata” overrides this value.",
				},
				viewFactory:edit_field {
					value = bind 'sdc_creator',
					immediate = true,
					fill_horizontal = 1,
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/CreatorTooltip=Creator (P170)^n^nWikidata QID of the author or photographer, e.g. Q640. Applies to every file in this export. A per-file creator= line in “Raw Metadata” overrides this value.",
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/StructuredData/Copyright=Copyright status (P6216)" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/CopyrightTooltip=Copyright status (P6216)^n^nWikidata QID for the copyright status. Default Q73566113 (as used in Cammello). Applies to every file; a per-file copyright= line overrides it.",
				},
				viewFactory:edit_field {
					value = bind 'sdc_copyright',
					immediate = true,
					fill_horizontal = 1,
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/CopyrightTooltip=Copyright status (P6216)^n^nWikidata QID for the copyright status. Default Q73566113 (as used in Cammello). Applies to every file; a per-file copyright= line overrides it.",
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/StructuredData/License=License (P275)" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/LicenseTooltip=License (P275)^n^nWikidata QID of the license. Q18199165 = CC BY-SA 4.0, Q6938433 = CC0 (values as used in Cammello – please verify). Applies to every file; a per-file license= line overrides it.",
				},
				viewFactory:combo_box {
					value = bind 'sdc_license',
					immediate = true,
					fill_horizontal = 1,
					items = {
						'Q18199165 # CC BY-SA 4.0',
						'Q6938433 # CC0',
					},
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/LicenseTooltip=License (P275)^n^nWikidata QID of the license. Q18199165 = CC BY-SA 4.0, Q6938433 = CC0 (values as used in Cammello – please verify). Applies to every file; a per-file license= line overrides it.",
				},
			},
			viewFactory:row {
				viewFactory:static_text {
					title = LOC "$$$/LrMediaWiki/Section/StructuredData/CreatedDuring=Created during (P10408)" .. ':',
					alignment = labelAlignment,
					width = LrView.share 'label_width',
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/CreatedDuringTooltip=Created during (P10408)^n^nWikidata QID of the event the files were created during, e.g. Q124692383 (81st Venice International Film Festival). Applies to every file; a per-file created_during= line overrides it.",
				},
				viewFactory:edit_field {
					value = bind 'sdc_created_during',
					immediate = true,
					fill_horizontal = 1,
					tooltip = LOC "$$$/LrMediaWiki/Section/StructuredData/CreatedDuringTooltip=Created during (P10408)^n^nWikidata QID of the event the files were created during, e.g. Q124692383 (81st Venice International Film Festival). Applies to every file; a per-file created_during= line overrides it.",
				},
			},
		},
	}
end

MediaWikiExportServiceProvider.hidePrintResolution = true

MediaWikiExportServiceProvider.showSections = {'fileNaming', 'metadata', 'fileSettings', 'imageSettings', 'outputSharpening'}

MediaWikiExportServiceProvider.allowFileFormats = {'JPEG', 'TIFF'}

MediaWikiExportServiceProvider.allowColorSpaces = {'sRGB'}

MediaWikiExportServiceProvider.canExportVideo = false

MediaWikiExportServiceProvider.exportPresetFields = {
	-- Section Login Information:
	{ key = 'username', default = '' },
	-- SECURITY: the OAuth properties ('oauth_status', 'oauth_logged_in',
	-- 'oauth_available') are deliberately NOT preset fields either – they are
	-- transient UI state, and the tokens themselves never leave LrPasswords
	-- (see MediaWikiOAuth.storeToken).
	-- SECURITY: 'password' is deliberately NOT a preset field. Preset fields
	-- are persisted in plain text (.lrtemplate / preferences on disk); saving
	-- a preset while the password field is filled would have written the
	-- password to disk. The password lives only in LrPasswords (see
	-- MediaWikiUtils.storePassword) and is put into the property table at
	-- runtime by startDialog / processRenderedPhotos.
	{ key = 'api_path', default = 'https://commons.wikimedia.org/w/api.php' },
	-- Section Upload Information:
	{ key = 'info_template', default = 'Information' },
	{ key = 'info_mode', default = 'Standard' },
	{ key = 'info_language', default = '' },
	{ key = 'info_source', default = '{{own}}' },
	{ key = 'info_author', default = '' },
	{ key = 'info_permission', default = '' },
	{ key = 'info_templates', default = '' },
	{ key = 'other_fields', default = '' },
	{ key = 'info_license', default = '{{Cc-by-sa-4.0}}' },
	{ key = 'info_categories', default = '' },
	{ key = 'gallery', default = '' },
	-- Section Structured Data (SDC), batch-level defaults (Wikidata QIDs):
	{ key = 'sdc_creator', default = '' },
	{ key = 'sdc_copyright', default = 'Q73566113 # copyrighted' },
	{ key = 'sdc_license', default = 'Q18199165 # CC BY-SA 4.0' },
	{ key = 'sdc_created_during', default = '' },
}

return MediaWikiExportServiceProvider

--[[

[1]	According to the LR SDK 6 documentation, fonts can be specified by a table
	with keys "name" and "size" – beside specifying the font by a simple string.
	See LR 6 SDK documantaion PDF, page 95.

	In fact, it has to be done this way – we have to avoid to specify a
	a font by a simple string.

	Setting a font name by a simple string works at macOS, not at Windows.
	Therefore, this kind of naming a font has to be avoided.
	Instead, the format with the both keys "name" and "size" should be used.

	LR 6 SDK documentation mentions, the "size" property should be a string.
	This can be done at macOS without causing an error.
	But, this setting will be ignored.
	Doing the same at Windows causes an internal error:
	"bad argument #-1 to 'fontFromValue' (number expected, got string)"

	Therefore, setting a font by a simple string should be avoided.
	Instead, the font should be specified by a table with keys "name" and "size".
	The value of "size" has to be a number, not a string (as mentioned by
	the SDK documentaion).

	Obviously, it's a bug of both: the SDK and it's documentation.

	Rob Cole initiated a related thread at
	https://forums.adobe.com/message/3110373

--]]
