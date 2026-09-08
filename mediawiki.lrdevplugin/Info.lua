-- Menu titles are localised. LOC is available inside Lightroom, but NOT when
-- Info.lua is loaded by the check script in plain Lua - and a nil call here
-- would break loading of the whole plug-in. So the call is guarded and falls
-- back to the English default that stands behind the "=" in the key.
local function menuTitle(key)
	if type(LOC) == 'function' then return LOC(key) end
	return (key:match('=(.*)$') or key)
end

-- This file is part of the LrMediaWiki project and distributed under the terms
-- of the MIT license (see LICENSE.txt file in the project root directory or
-- [0]).  See [1] for more information about LrMediaWiki.
--
-- Copyright (C) 2014 by the LrMediaWiki team (see CREDITS.txt file in the
-- project root directory or [2])
--
-- [0]  <https://raw.githubusercontent.com/LrMediaWiki/LrMediaWiki/master/LICENSE.txt>
-- [1]  <https://commons.wikimedia.org/wiki/Commons:LrMediaWiki>
-- [2]  <https://raw.githubusercontent.com/LrMediaWiki/LrMediaWiki/master/CREDITS.txt>

return {
	LrSdkVersion = 6.0,
	LrSdkMinimumVersion = 4.0,
	LrToolkitIdentifier = 'org.ireas.lightroom.mediawiki',
	LrPluginName = 'LrMediaWiki2',

	LrInitPlugin = 'MediaWikiInit.lua',

	LrExportServiceProvider = {
		title = 'MediaWiki',
		file = 'MediaWikiExportServiceProvider.lua',
	},

	-- Die sechs Workflow-Saetze stehen oben: ihre Bezeichnungen und Felder
	-- kommen aus ~/LrMediaWiki2/workflows.toml und stimmen deshalb immer mit
	-- dem Editor ueberein. Darunter die beiden Werkzeugsaetze, die zu keinem
	-- Workflow gehoeren: alle Felder auf einmal, und nur der Wikitext.
	LrMetadataTagsetFactory = {
		'MediaWikiMetadataSetWorkflow1.lua',
		'MediaWikiMetadataSetWorkflow2.lua',
		'MediaWikiMetadataSetWorkflow3.lua',
		'MediaWikiMetadataSetWorkflow4.lua',
		'MediaWikiMetadataSetWorkflow5.lua',
		'MediaWikiMetadataSetWorkflow6.lua',
		'MediaWikiMetadataSetAll.lua',
		'MediaWikiMetadataSetDescriptionAll.lua',
	},

	LrMetadataProvider = 'MediaWikiMetadataProvider.lua',

	LrPluginInfoProvider = 'MediaWikiPluginInfoProvider.lua',

	LrPluginInfoUrl = 'https://github.com/krichel89/LrMediaWiki2',

	-- Menu titles go through LOC: English is the base form, the German
	-- wording lives in TranslatedStrings_de.txt. Lightroom then shows each
	-- entry in the language the application runs in, instead of the fixed
	-- mixture of English and German that stood here until 2.0.72.
	-- Same tools additionally in the Library menu (Bibliothek >
	-- Zusatzmoduloptionen), one menu closer to metadata work. The titles are
	-- identical to the File-menu entries on purpose, so a macOS app shortcut
	-- bound to the title triggers the same script from either menu.
	LrLibraryMenuItems = {
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/EditSdcWeb=🌐 Edit Structured Data in browser",
			file = "ToolEditSdcWeb.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/ConvertDescriptionAll=🔁 Description fields ↔ Wikitext",
			file = "ToolConvertDescriptionAll.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/SdcBridge=🔌 Background app (SDC bridge)",
			file = "ToolSdcBridge.lua",
		},
	},

	-- The browser editor is deliberately the FIRST entry in both menus: it is
	-- the most frequently used tool, and the first item of a submenu is the
	-- shortest possible pointer path.
	LrExportMenuItems = {
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/EditSdcWeb=🌐 Edit Structured Data in browser",
			file = "ToolEditSdcWeb.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/ConvertDescriptionAll=🔁 Description fields ↔ Wikitext",
			file = "ToolConvertDescriptionAll.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/SdcBridge=🔌 Background app (SDC bridge)",
			file = "ToolSdcBridge.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/SearchReplaceMetadata=🔍 Search and Replace Metadata",
			file = "ToolSearchAndReplaceMetadata.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/SearchReplaceFilename=🔎 Search and Replace Filename",
			file = "ToolSearchAndReplaceFilename.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/GenerateFromPersons=🚀 Generate filename and description from persons",
			file = "ToolGenerateFromPersons.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/TitlePrefixHeadline=📄 Set title to file prefix and headline",
			file = "ToolSetTitleToPrefixAndHeadline.lua",
		},
		{
			title = menuTitle "$$$/LrMediaWiki/Menu/TitlePrefixCaption=📄 Set title to file prefix and caption",
			file = "ToolSetTitleToPrefixAndCaption.lua",
		},
		--[[
		{
			title = "❓ Test",
			file = "ToolTest.lua",
		},
		--]]
	},

	-- Versioning policy: the third digit (revision) is bumped on every
	-- delivered change; the second digit (minor) changes only on explicit
	-- request. (Note: Lua silently keeps only the LAST duplicate key in a
	-- table constructor – that is why the old duplicate VERSION entry was
	-- removed here.)
	VERSION = {
		major = 2,
		minor = 0,
		revision = 73,
	},
}
