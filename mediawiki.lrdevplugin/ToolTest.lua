-- Access the Lightroom SDK namespaces.
local LrDialogs = import 'LrDialogs'
local LrLogger = import 'LrLogger'
local LrView = import 'LrView'
local LrDialogs = import 'LrDialogs'
local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'

-- Other Libaries
local Info = require 'Info'
local MediaWikiUtils = require 'MediaWikiUtils'
local json = require 'JSON'
local u = require 'utils'
local metadataProvider = require 'MediaWikiMetadataProvider'



local catalog = LrApplication.activeCatalog()
local photo = catalog:getTargetPhoto()
local photos = catalog:getTargetPhotos()
local data = LrTasks.startAsyncTask(function()
    local data = ''
    u.log(metadataProvider.title);

    catalog:withWriteAccessDo('Get MetaData', function()
    
        for key,photo in pairs(photos) do 

            u.log( photo:getFormattedMetadata('fileName') )
            u.log( photo:getFormattedMetadata('personShown') )
            
        end

    end)
    --utils.log(tostring(data))

    return data
end )