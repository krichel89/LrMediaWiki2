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
	title = 'LrMediaWiki2',
	id = 'LrMediaWikiTagset',
	metadataFieldsForPhotos = {
		-- Fields of templates "Information" and "Artwork":
		{
			id = 'caption_en',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/FileCaptionEn=Caption (en)",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'depicts',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/Depicts=Depicts (P180)",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'created_during',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/CreatedDuring=Created during (P10408)",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'description_en',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/DescriptionEnLabel=Description (en)",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'description_de',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/DescriptionDeLabel=Description (de)",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'description_all',
			version = 10,
			title = LOC "$$$/LrMediaWiki/Metadata/DescriptionAll=Raw Metadata",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'categories',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Categories=Categories",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		-- Additional fields of template "Artwork":
		{
			id = 'artist',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Artist=Artist",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'title',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Title=Title",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'medium',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Medium=Medium",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'dimensions',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Dimensions=Dimensions",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'institution',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Institution=Institution",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'department',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Department=Department",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'accessionNumber',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/AccessionNumber=Accession Number",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'placeOfCreation',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/PlaceOfCreation=Place of Creation",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'placeOfDiscovery',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/PlaceOfDiscovery=Place of Discovery",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'objectHistory',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/ObjectHistory=Object History",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'exhibitionHistory',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/ExhibitionHistory=Exhibition History",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'creditLine',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/CreditLine=Credit Line",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'inscriptions',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Inscriptions=Inscriptions",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'notes',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Notes=Notes",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'references',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/References=References",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		-- Wieder deklariert in 2.0.57: diese sieben Felder waren beim
		-- Umbau auf description_all aus dem Anbieter geflogen, standen
		-- aber weiter in den Metadatensaetzen "Artwork" und "Object
		-- Photo" – sie erschienen also im Bedienfeld und bewirkten
		-- nichts. Die Fassungsnummern sind die des Originals, damit
		-- vorhandene Werte nicht verworfen werden.
		{
			id = 'author',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/AuthorTooltip=Author^n^nRequired field, if not “Artwork” has been chosen (“Artwork” recommends to use “Artist” or “Author”).^nShould be set per file or at export dialog. Setting per file has priority over setting at export dialog. Example:^n  [[User:MyUserName|MyRealName]]",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'date',
			version = 3,
			title = LOC "$$$/LrMediaWiki/Metadata/DateTooltip=Date^n^nOptional field. If this field is empty and “Date Created” is filled, that field is used.^nExamples for this field:^n  2017-02-26 19:58^n  {{Other date|before|1947}}^n  {{Taken on|<dateCreated>}}",
			dataType = 'string',
			searchable = true,
			browsable = true,
		},
		{
			id = 'description_other',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/DescriptionOtherTooltip=Description (other)^n^nDescription in another language (or in multiple other languages). Use language templates like {{fr|Une description française}}.^nOr choose for example “fr – French” at export field “Language (other)” – then the text here may not be set in the language template {{fr|…}} – simply enter the text in French.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'otherFields',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/OtherFieldsTooltip=Other Fields^n^nAdditional table fields added on the bottom of the template. Examples:^n  {{Information field}}^n  {{Credit line}}",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'otherVersions',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/OtherVersionsTooltip=Other Versions^n^nLinks to files with very similar content or derived files.^nUse thumbnails or gallery tags <gallery> </gallery>.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'source',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/SourceTooltip=Source^n^nRequired field. Should be set per file or at export dialog. Setting per file has priority over setting at export dialog. Example: {{own}}.^nThe field is named “Source/Photographer” at infobox template “Artwork”.",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'templates',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/TemplatesTooltip=Templates^n^nTemplates are inserted after the infobox template and before the licensing section. Examples:^n  {{Panorama}}^n  {{Personality rights}}^n  {{Location estimated}}",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'wikidata',
			version = 2,
			title = LOC "$$$/LrMediaWiki/Metadata/Wikidata=Wikidata",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		-- Additional fields of template "Object photo":
		{
			id = 'object',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/Object=Object",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'detail',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/Detail=Detail",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
		{
			id = 'detailPosition',
			version = 1,
			title = LOC "$$$/LrMediaWiki/Metadata/DetailPosition=Detail Position",
			dataType = 'string',
			searchable = false,
			browsable = false,
		},
	},
	schemaVersion = 13,
}
