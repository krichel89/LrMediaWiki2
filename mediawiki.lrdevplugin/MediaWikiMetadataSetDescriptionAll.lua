-- This file is part of the LrMediaWiki project and distributed under the terms
-- of the MIT license (see LICENSE.txt file in the project root directory).
--
-- This Metadata Set "LrMediaWiki – Wikitext" is the dedicated view
-- for the all-in-one wikitext field "Wikitext" – deliberately the
-- ONLY field here: captions, depicts etc. are contained in the wikitext or
-- edited elsewhere; content is typically prepared in an external editor or
-- another tool and pasted in. The per-language single-line fields live in the
-- "Information" / "Information (de)" sets; the converter tool (File >
-- Plug-in Extras > "🔁 Description fields ↔ Wikitext") moves content
-- between the two representations. Note: the Lightroom SDK offers no
-- notification when the user switches the Metadata panel set, so the
-- conversion cannot run automatically on switching – use the menu tool. At
-- export, both representations are merged automatically, so nothing is lost
-- either way.

local Info = require 'Info'
local pf = Info.LrToolkitIdentifier .. '.' -- Prefix, e.g. 'org.ireas.lightroom.mediawiki.'

return {
	id = 'LrMediaWikiMetadataSetDescriptionAll', -- needs to be unique!
	title = 'LrMediaWiki – Wikitext', -- no localization needed
	items = {
		{ 'com.adobe.label', label = 'LrMediaWiki – Wikitext' },
		{ pf .. 'description_all', label = LOC "$$$/LrMediaWiki/Metadata/DescriptionAll=Wikitext", height_in_lines = 25 },
	},
}
