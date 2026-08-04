--[==[
MediaWikiWorkflowTagset.lua – baut EINEN Metadatensatz aus dem n-ten
Workflow der Datei ~/LrMediaWiki2/workflows.toml.

Damit stimmen Bezeichnung und Feldliste in Lightroom immer mit dem ueberein,
was der Editor im Browser anzeigt: beide lesen dieselbe Datei. Umbenennen
oder Umsortieren in der Datei wirkt nach dem naechsten Start von Lightroom.

Warum feste Plaetze und keine Schleife? Die Zahl der Metadatensaetze steht
in Info.lua und ist statisch – Lightroom liest sie beim Laden. Es gibt
deshalb genau ACHT vorbereitete Plaetze; sind weniger Workflows in der Datei,
melden die uebrigen Plaetze sich als „(nicht belegt)" und zeigen nur das
Wikitext-Feld.

Der Lightroom-Block haengt immer unten dran – ohne ihn waere der Satz im
Bedienfeld unbrauchbar (kein Dateiname, kein Aufnahmedatum).
]==]

local Info = require 'Info'
local MediaWikiWorkflows = require 'MediaWikiWorkflows'

local pf = Info.LrToolkitIdentifier .. '.'

local MediaWikiWorkflowTagset = {}

-- Beschriftungen und Zeilenhoehen der eigenen Felder. Ein Feld, das hier
-- fehlt, bekommt seine Beschriftung aus dem Anbieter.
local BESCHRIFTUNG = {
	artist            = LOC "$$$/LrMediaWiki/Metadata/Artist=Artist",
	author            = LOC "$$$/LrMediaWiki/Metadata/Author=Author",
	title             = LOC "$$$/LrMediaWiki/Metadata/Title=Title",
	caption_en        = LOC "$$$/LrMediaWiki/Metadata/FileCaptionEn=Caption (en)",
	description_en    = LOC "$$$/LrMediaWiki/Metadata/DescriptionEn=Description (en)",
	description_de    = LOC "$$$/LrMediaWiki/Metadata/DescriptionDe=Description (de)",
	description_other = LOC "$$$/LrMediaWiki/Metadata/DescriptionOther=Description (other)",
	description_all   = LOC "$$$/LrMediaWiki/Metadata/DescriptionAll=Raw Metadata",
	date              = LOC "$$$/LrMediaWiki/Metadata/Date=Date",
	medium            = LOC "$$$/LrMediaWiki/Metadata/Medium=Medium",
	dimensions        = LOC "$$$/LrMediaWiki/Metadata/Dimensions=Dimensions",
	institution       = LOC "$$$/LrMediaWiki/Metadata/Institution=Institution",
	department        = LOC "$$$/LrMediaWiki/Metadata/Department=Department",
	accessionNumber   = LOC "$$$/LrMediaWiki/Metadata/AccessionNumber=Accession Number",
	placeOfCreation   = LOC "$$$/LrMediaWiki/Metadata/PlaceOfCreation=Place of Creation",
	placeOfDiscovery  = LOC "$$$/LrMediaWiki/Metadata/PlaceOfDiscovery=Place of Discovery",
	objectHistory     = LOC "$$$/LrMediaWiki/Metadata/ObjectHistory=Object History",
	exhibitionHistory = LOC "$$$/LrMediaWiki/Metadata/ExhibitionHistory=Exhibition History",
	creditLine        = LOC "$$$/LrMediaWiki/Metadata/CreditLine=Credit Line",
	inscriptions      = LOC "$$$/LrMediaWiki/Metadata/Inscriptions=Inscriptions",
	notes             = LOC "$$$/LrMediaWiki/Metadata/Notes=Notes",
	references        = LOC "$$$/LrMediaWiki/Metadata/References=References",
	source            = LOC "$$$/LrMediaWiki/Metadata/Source=Source",
	otherVersions     = LOC "$$$/LrMediaWiki/Metadata/OtherVersions=Other Versions",
	otherFields       = LOC "$$$/LrMediaWiki/Metadata/OtherFields=Other Fields",
	wikidata          = LOC "$$$/LrMediaWiki/Metadata/Wikidata=Wikidata",
	templates         = LOC "$$$/LrMediaWiki/Metadata/Templates=Templates",
	categories        = LOC "$$$/LrMediaWiki/Metadata/Categories=Categories",
	object            = LOC "$$$/LrMediaWiki/Metadata/Object=Object",
	detail            = LOC "$$$/LrMediaWiki/Metadata/Detail=Detail",
	detailPosition    = LOC "$$$/LrMediaWiki/Metadata/DetailPosition=Detail Position",
	depicts           = LOC "$$$/LrMediaWiki/Metadata/Depicts=Depicts (SDC)",
	created_during    = LOC "$$$/LrMediaWiki/Metadata/CreatedDuring=Created during (SDC)",
}

local HOEHE = {
	description_en = 3, description_de = 3, description_other = 3,
	description_all = 8, depicts = 4,
}

-- Der Lightroom-Block, in allen Saetzen gleich.
local function lightroomBlock()
	return {
		'com.adobe.separator',
		{ 'com.adobe.label', label = 'Lightroom' },
		'com.adobe.filename',
		'com.adobe.copyname',
		'com.adobe.headline',
		'com.adobe.title',
		{ 'com.adobe.caption',
		  label = LOC "$$$/LrMediaWiki/Metadata/Caption=Description",
		  height_in_lines = 3 },
		'com.adobe.dateCreated',
		'com.adobe.captureTime',
		'com.adobe.captureDate',
		'com.adobe.location',
		'com.adobe.city',
		'com.adobe.state',
		'com.adobe.country',
		'com.adobe.jobIdentifier',
		{ 'com.adobe.personInImage', form = 'shortTitle' },
		{ 'com.adobe.organisationInImageName', form = 'shortTitle' },
		'com.adobe.event',
	}
end

-- Baut den Satz fuer Platz `nr` (1-basiert).
function MediaWikiWorkflowTagset.build(nr)
	local list = MediaWikiWorkflows.loadMerged()
	local wf = list[nr]

	local titel, felder
	if wf == nil then
		titel = 'LrMediaWiki2 – Workflow ' .. nr .. ' (nicht belegt)'
		felder = { 'description_all' }
	else
		titel = 'LrMediaWiki2 – ' .. wf.name
		felder = wf.felder
		-- Eine Datei aus einer aelteren Fassung kennt `felder` noch nicht.
		-- Ohne Rueckfall stuende dann in jedem Satz nur der Wikitext – die
		-- Datei wird ja nie ueberschrieben. Also die Felder des frueheren
		-- Satzes „Information" als Grundausstattung.
		if #felder == 0 then
			felder = { 'caption_en', 'description_en', 'description_de',
			           'description_all', 'depicts', 'created_during',
			           'categories' }
		end
		-- Raw Metadata steht in JEDEM Satz, und zwar UNTEN: es ist das
		-- Rohbild dessen, was daruber in Einzelfeldern steht, und gehoert
		-- deshalb ans Ende. Wo die Datei es auffuehrt, ist gleichgueltig -
		-- hier wird es herausgenommen und angehaengt.
		local kopie = {}
		for i = 1, #felder do
			if felder[i] ~= 'description_all' then
				kopie[#kopie + 1] = felder[i]
			end
		end
		kopie[#kopie + 1] = 'description_all'
		felder = kopie
	end

	local items = { { 'com.adobe.label', label = titel } }
	for i = 1, #felder do
		local id = felder[i]
		items[#items + 1] = {
			pf .. id,
			label = BESCHRIFTUNG[id] or id,
			height_in_lines = HOEHE[id],
		}
	end
	local lr = lightroomBlock()
	for i = 1, #lr do items[#items + 1] = lr[i] end

	return {
		id = 'LrMediaWiki2Workflow' .. nr,  -- muss eindeutig sein
		title = titel,
		items = items,
	}
end

return MediaWikiWorkflowTagset
