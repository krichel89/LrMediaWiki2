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

return {
	title = 'LrMediaWiki',
	id = 'LrMediaWikiTagset',
	metadataFieldsForPhotos = {
		-- Fields of templates "Information" and "Artwork":
		{
			id = 'caption_en',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/FileCaptionEnTooltip=Caption (en)^n^nA short description in English",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'depicts',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/DepictsTooltip=Depicts (P180)^n^nWikidata QIDs of what is shown, comma-separated (e.g. Q640, Q42). Published as SDC statements (P180). A value here overrides any depicts= line in “Description (all)”.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'created_during',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/CreatedDuringTooltip=Created during (P10408)^n^nWikidata QID of the event the photo was created during (e.g. Q124692383). Published as an SDC statement (P10408). A value here overrides the export dialog default and any created_during= line in “Description (all)”.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'description_all',
			version = 10,
			title = LOC "$$$/LrMediaWiki/Metadata/DescriptionAllTooltip=Description (all)^n^nFull Wikitext description for this file. Enter the complete wikitext including templates, license, categories etc. Categories can also be entered as [[Category:Name]] and will be merged with categories from the export dialog.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
				{
			id = 'categories',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/CategoriesTooltip=Categories^n^nThe categories all uploaded images should be added to; without the prefix “Category:” and without square brackets [[…]]. Multiple categories are separated by a ; (semicolon).",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		-- Additional fields of template "Artwork":
		{
			id = 'artist',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/ArtistTooltip=Artist^n^nArtist who created the original artwork. Use {{Creator:Name Surname}} with {{Creator}} template whenever possible. Use either “Artist” or “Author”, not both.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'title',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/TitleTooltip=Title^n^nTitle of the artwork. If the artwork has no title, use a description field.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'medium',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/MediumTooltip=Medium^n^nMedium (technique and materials) used to create artwork",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'dimensions',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/DimensionsTooltip=Dimensions^n^nDimensions of the artwork. Please use {{Size}} formatting template.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'institution',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/InstitutionTooltip=Institution^n^nGallery, museum or collection owning the piece. Will be shown together with field “Department” as “Current location”.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'department',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/DepartmentTooltip=Department^n^nDepartment or location within the museum or gallery",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'accessionNumber',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/AccessionNumberTooltip=Accession Number^n^nMuseum’s accession number or some other inventory or identification number",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'placeOfCreation',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/PlaceOfCreationTooltip=Place of Creation",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'placeOfDiscovery',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/PlaceOfDiscoveryTooltip=Place of Discovery^n^nPlace of discovery or location where given object was found. This field mostly makes sense with archeological artifacts.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'objectHistory',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/ObjectHistoryTooltip=Object History^n^nProvenance (history of artwork ownership). Use {{ProvenanceEvent}}, {{Discovered}} and other similar templates.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'exhibitionHistory',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/ExhibitionHistoryTooltip=Exhibition History^n^nExhibition history, {{Temporary Exhibition}}",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'creditLine',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/CreditLineTooltip=Credit Line^n^nDescribes how the artwork came into the museum’s collection, or how it came to be on view at the museum",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'inscriptions',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/InscriptionsTooltip=Inscriptions^n^nDescription of: inscriptions, watermarks, captions, coats of arm, etc. Use {{inscription}}.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'notes',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/NotesTooltip=Notes^n^nAdditional information about the artwork and its history",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'references',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/ReferencesTooltip=References^n^nBooks and websites with information about the artwork. Please use {{Cite book}} and {{Cite web}} templates.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'wikidata',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/WikidataTooltip=Wikidata^n^nID of the Wikidata item about the artwork (if any)",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		-- Additional fields of template "Object photo":
		{
			id = 'object',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/ObjectTooltip=Object^n^nName of the category with the object description",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'detail',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/DetailTooltip=Detail^n^nWrite “yes” if you want a message “This photograph shows a detail …” to be displayed before the section “Object”. You can also explain what is shown in the detail, it will both display the message and explain what detail it is in the “Description” field of the section “Photograph”.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'detailPosition',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/DetailPositionTooltip=Detail Position^n^nPosition of the detail on the object",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
	},
	schemaVersion = 11,
}
