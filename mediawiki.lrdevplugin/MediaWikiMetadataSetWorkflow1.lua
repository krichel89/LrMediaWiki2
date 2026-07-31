--[==[
MediaWikiMetadataSetWorkflow1.lua – Platz 1 der Workflow-Metadatensaetze.

Der Inhalt kommt aus dem 1. [[workflow]]-Block von
~/LrMediaWiki2/workflows.toml; gebaut wird er in
MediaWikiWorkflowTagset.lua. Gibt es dort keinen 1. Block, meldet sich
der Platz als "nicht belegt".

Diese Datei bewusst NICHT von Hand aendern – Bezeichnung und Felder stehen
in der Datei des Nutzers.
]==]

local MediaWikiWorkflowTagset = require 'MediaWikiWorkflowTagset'

return MediaWikiWorkflowTagset.build(1)
