-- Smart player created by a brothers
-- UI Language: English

require "import"
import "android.app.AlertDialog"
import "android.content.DialogInterface"
import "android.media.MediaPlayer"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "android.net.Uri"
import "android.content.Intent"
import "android.view.WindowManager"
import "android.os.Handler"
import "android.os.Looper"
import "java.lang.Runnable"
import "android.view.View"
import "android.widget.LinearLayout"
import "android.widget.TextView"
import "android.widget.SeekBar"
import "android.widget.Button"
import "android.widget.EditText"
import "android.text.InputType"
import "android.view.Gravity"
import "android.os.StrictMode"
import "android.app.NotificationManager"
import "android.app.NotificationChannel"
import "android.app.Notification"
import "android.app.PendingIntent"
import "android.content.Context"
import "android.content.IntentFilter"
import "android.media.audiofx.LoudnessEnhancer"
import "android.provider.MediaStore"
import "android.widget.ScrollView"
import "android.os.Environment"
import "android.view.SurfaceView"
import "android.view.SurfaceHolder"
import "android.widget.ListView"
import "android.widget.ArrayAdapter"
import "android.widget.AdapterView"
import "java.lang.Thread"

-- Helper to create byte array (works in all LuaJava environments)
local function newByteArray(size)
    return luajava.newArray(luajava.bindClass("java.lang.Byte").TYPE, size)
end

-- Helper to set StrictMode policy (avoids nested class syntax error)
local function setStrictModeAllowFileUri()
    pcall(function()
        local builder = luajava.newInstance("android.os.StrictMode$VmPolicy$Builder")
        local policy = builder.build()
        StrictMode.setVmPolicy(policy)
    end)
end

-- Truly Persistent Global Player Instance & States
if not _G.smart_media_player then
    _G.smart_media_player = MediaPlayer()
    _G.smart_player_current_path = ""
    _G.smart_player_is_prepared = false
end
local player = _G.smart_media_player

-- Persistent custom FF/RW dynamic configurations storage
if not _G.ffRwOptions then
    _G.ffRwOptions = {5000, 10000, 20000, 30000, 60000}
end

local currentPlaylist = {}
local currentIndex = 1
local currentFilePath = ""
local currentSavedFolder = "/storage/emulated/0"
local currentSavedMediaType = "audio"
local lastPlayedPosition = 0
local ffRwDuration = 10000
local backgroundPlay = "on"
local autoPlay = "on"
local currentBoostStage = 1
local loudnessEnhancer = nil
local currentPlaybackSpeed = 1.0
-- WhatsApp Media Center settings variables
local showWhatsAppMediaToggle = "on"
local showVolumeBoostToggle = "on"
local showSleepTimerToggle = "on"
local showStatusImages = "on"
local showStatusVideos = "on"
local multiSelectSetting = "on"

-- Search, Sort & Browse Engine States
local currentSortMethod = "A-Z"
local currentSearchQuery = ""
local currentBrowseMode = "folders" 

-- Multi-Select Engine Global Variables
local isMultiSelectActive = false
local selectedItemsMap = {}

-- Sleep Timer Engine Variables
local sleepHandler = Handler(Looper.getMainLooper())
local sleepRunnable = nil
local sleepModeActive = "off"
local sleepDurationMs = 0
local lastSleepAudioPath = ""

-- Configuration File Paths
local configPath = "/sdcard/smart_player_config.txt"
local favoritesPath = "/sdcard/smart_player_favorites.txt"
local NOTIF_ID = 9923
local CHANNEL_ID = "smart_player_channel"
local mediaReceiver = nil

-- Favorites Engine Storage
local favoritesMap = {}

-- UI References
local controlsDialog = nil
local txtTitleRef = nil
local txtTimeRef = nil
local seekBarRef = nil
local btnVolumeBoostRef = nil
local btnSleepToggleRef = nil
local btnPlayPauseRef = nil
local btnFavoriteRef = nil
local currentSurfaceHolder = nil

local function showToast(text)
    service.speak(text)
end

-- Favorites Management Functions
local function loadFavorites()
    favoritesMap = {}
    pcall(function()
        local f = io.open(favoritesPath, "r")
        if f then
            for line in f:lines() do
                if line ~= "" then
                    favoritesMap[line] = true
                end
            end
            f:close()
        end
    end)
end

local function saveFavorites()
    pcall(function()
        local f = io.open(favoritesPath, "w")
        if f then
            for path, _ in pairs(favoritesMap) do
                f:write(path .. "\n")
            end
            f:close()
        end
    end)
end

local function isFavorite(path)
    return favoritesMap[path] == true
end

local function toggleFavorite(path)
    if isFavorite(path) then
        favoritesMap[path] = nil
        showToast("Removed from Favorites")
    else
        favoritesMap[path] = true
        showToast("Added to Favorites")
    end
    saveFavorites()
end

-- Native Playback Speed Applier
local function applyPlaybackSpeed()
    if not player then return end
    pcall(function()
        local params = player.getPlaybackParams()
        params.setSpeed(currentPlaybackSpeed)
        player.setPlaybackParams(params)
    end)
end

-- Native Volume Boost Applier
local function applyVolumeBoost(silent)
    if not player then return end
    pcall(function()
        if not loudnessEnhancer then
            loudnessEnhancer = LoudnessEnhancer(player.getAudioSessionId())
        end
        loudnessEnhancer.setEnabled(true)
        if currentBoostStage == 1 then
            loudnessEnhancer.setTargetGain(0)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: Normal") end
            if not silent then showToast("Volume Boost: Normal") end
        elseif currentBoostStage == 2 then
            loudnessEnhancer.setTargetGain(1200)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: 1.5x") end
            if not silent then showToast("Volume Boost: 1.5x") end
        elseif currentBoostStage == 3 then
            loudnessEnhancer.setTargetGain(2500)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: 2.0x") end
            if not silent then showToast("Volume Boost: 2.0x") end
        elseif currentBoostStage == 4 then
            loudnessEnhancer.setTargetGain(4000)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: 3.0x") end
            if not silent then showToast("Volume Boost: 3.0x") end
        end
    end)
end

-- Notification Controller Engine
local function showNotification(title)
    pcall(function()
        local ns = Context.NOTIFICATION_SERVICE
        local nm = service.getSystemService(ns)
        if android.os.Build.VERSION.SDK_INT >= 26 then
            local channel = NotificationChannel(CHANNEL_ID, "Smart Player Playback", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(channel)
        end
        local builder
        if android.os.Build.VERSION.SDK_INT >= 26 then
            builder = Notification.Builder(service, CHANNEL_ID)
        else
            builder = Notification.Builder(service)
        end
        if not mediaReceiver then
            mediaReceiver = luajava.createProxy("android.content.BroadcastReceiver", {
                onReceive = function(context, intent)
                    if intent.getAction() == "com.smartplayer.TOGGLE" then
                        if player.isPlaying() then
                            player.pause()
                            if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
                        else
                            player.start()
                            applyPlaybackSpeed()
                            if btnPlayPauseRef then btnPlayPauseRef.setText("Pause") end
                        end
                        showNotification(File(currentFilePath).getName())
                    end
                end
            })
            local filter = IntentFilter("com.smartplayer.TOGGLE")
            service.registerReceiver(mediaReceiver, filter)
        end
        local toggleIntent = Intent("com.smartplayer.TOGGLE")
        local flags = 134217728
        if android.os.Build.VERSION.SDK_INT >= 23 then
            flags = flags + 67108864
        end
        local pToggle = PendingIntent.getBroadcast(service, 0, toggleIntent, flags)
        local appInfo = service.getApplicationInfo()
        builder.setContentTitle("Smart player created by a brothers")
        builder.setContentText(title)
        builder.setSmallIcon(appInfo.icon)
        builder.setOngoing(player.isPlaying())
        local actionText = player.isPlaying() and "Pause" or "Play"
        if android.os.Build.VERSION.SDK_INT >= 20 then
            local action = Notification.Action.Builder(appInfo.icon, actionText, pToggle).build()
            builder.addAction(action)
        else
            builder.addAction(appInfo.icon, actionText, pToggle)
        end
        nm.notify(NOTIF_ID, builder.build())
    end)
end

local function cancelNotification()
    pcall(function()
        local ns = Context.NOTIFICATION_SERVICE
        local nm = service.getSystemService(ns)
        nm.cancel(NOTIF_ID)
    end)
end

-- Recursive Folder Deletion Engine
local function deleteFolderRecursive(fileOrDirectory)
    if fileOrDirectory.isDirectory() then
        local children = fileOrDirectory.listFiles()
        if children then
            for i = 0, #children - 1 do
                deleteFolderRecursive(children[i])
            end
        end
    end
    return fileOrDirectory.delete()
end

-- Recursive Folder Size Calculation Engine
local function getFolderSizeRecursive(fileOrDirectory)
    local totalSize = 0
    if fileOrDirectory.isDirectory() then
        local children = fileOrDirectory.listFiles()
        if children then
            for i = 0, #children - 1 do
                totalSize = totalSize + getFolderSizeRecursive(children[i])
            end
        end
    else
        pcall(function() totalSize = fileOrDirectory.length() end)
    end
    return totalSize
end

-- Helper to Format Bytes to MB/GB
local function formatSize(totalBytes)
    local sizeInMb = totalBytes / (1024 * 1024)
    if sizeInMb >= 1024 then
        local sizeInGb = sizeInMb / 1024
        return string.format("%.2f GB", sizeInGb)
    else
        return string.format("%.2f MB", sizeInMb)
    end
end

-- Multi-Select Statistics Tracker
local function getSelectedStats(filteredList, selectedMap)
    local count = 0
    local totalSize = 0
    for _, item in ipairs(filteredList) do
        if selectedMap[item.path] then
            count = count + 1
            local f = File(item.path)
            if item.isDir then
                pcall(function() totalSize = totalSize + getFolderSizeRecursive(f) end)
            else
                pcall(function() totalSize = totalSize + f.length() end)
            end
        end
    end
    return count, formatSize(totalSize)
end

-- Persistent Storage: Save State
local function saveState()
    pcall(function()
        _G.smart_player_playlist = currentPlaylist
        _G.smart_player_index = currentIndex
        local f = io.open(configPath, "w")
        if f then
            f:write((currentSavedFolder or "/storage/emulated/0") .. "\n")
            f:write((currentSavedMediaType or "audio") .. "\n")
            f:write((currentFilePath or "") .. "\n")
            local pos = 0
            if player and currentFilePath ~= "" and _G.smart_player_is_prepared then 
                pcall(function() pos = player.getCurrentPosition() end) 
            end
            if pos <= 0 and lastPlayedPosition > 0 then pos = lastPlayedPosition end
            f:write(tostring(pos) .. "\n")
            f:write(tostring(ffRwDuration) .. "\n")
            f:write((backgroundPlay or "on") .. "\n")
            f:write((autoPlay or "on") .. "\n")
            f:write(tostring(sleepDurationMs or 0) .. "\n")
            f:write(tostring(currentPlaybackSpeed or 1.0) .. "\n")
            f:write((showWhatsAppMediaToggle or "on") .. "\n")
            f:write((currentSortMethod or "A-Z") .. "\n")
            f:write((currentBrowseMode or "folders") .. "\n")
            f:write((showVolumeBoostToggle or "on") .. "\n")
            f:write((showSleepTimerToggle or "on") .. "\n")
            f:write((showStatusImages or "on") .. "\n")
            f:write((showStatusVideos or "on") .. "\n")
            f:write((multiSelectSetting or "on") .. "\n")
            f:close()
        end
    end)
end

-- Persistent Storage: Load State
local function loadState()
    pcall(function()
        if _G.smart_player_playlist then
            currentPlaylist = _G.smart_player_playlist
        end
        if _G.smart_player_index then
            currentIndex = _G.smart_player_index
        end
        local f = io.open(configPath, "r")
        if f then
            currentSavedFolder = f:read("*l") or "/storage/emulated/0"
            currentSavedMediaType = f:read("*l") or "audio"
            currentFilePath = f:read("*l") or ""
            lastPlayedPosition = tonumber(f:read("*l")) or 0
            ffRwDuration = tonumber(f:read("*l")) or 10000
            backgroundPlay = f:read("*l") or "on"
            autoPlay = f:read("*l") or "on"
            sleepDurationMs = tonumber(f:read("*l")) or 0
            currentPlaybackSpeed = tonumber(f:read("*l")) or 1.0
            showWhatsAppMediaToggle = f:read("*l") or "on"
            currentSortMethod = f:read("*l") or "A-Z"
            currentBrowseMode = f:read("*l") or "folders"
            showVolumeBoostToggle = f:read("*l") or "on"
            showSleepTimerToggle = f:read("*l") or "on"
            showStatusImages = f:read("*l") or "on"
            showStatusVideos = f:read("*l") or "on"
            multiSelectSetting = f:read("*l") or "on"
            f:close()
        end
    end)
end

-- Safe Dialog UI Launcher
local function showDialogSafe(builder, onBackHandler)
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            if onBackHandler then
                import "android.view.KeyEvent"
                dialog.setOnKeyListener(DialogInterface.OnKeyListener({
                    onKey = function(d, keyCode, event)
                        if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                            dialog.dismiss()
                            onBackHandler()
                            return true
                        end
                        return false
                    end
                }))
            end
            dialog.show()
        end
    }))
end

-- Enhanced Format Filter Logic
local function matchesFormat(name, mediaType)
    local lower = name:lower()
    if mediaType == "audio" then
        return lower:find("%.mp3$") or lower:find("%.m4a$") or lower:find("%.wav$") or lower:find("%.ogg$") or lower:find("%.amr$") or lower:find("%.opus$")
    elseif mediaType == "video" then
        return lower:find("%.mp4$") or lower:find("%.mkv$") or lower:find("%.3gp$")
    elseif mediaType == "statuses" then
        local isImg = lower:find("%.jpg$") or lower:find("%.jpeg$") or lower:find("%.png$")
        local isVid = lower:find("%.mp4$") or lower:find("%.mkv$") or lower:find("%.3gp$")
        if isImg and showStatusImages == "off" then return false end
        if isVid and showStatusVideos == "off" then return false end
        return isImg or isVid
    end
    return false
end

-- WhatsApp Status Helpers
local function openImageExternally(filePath)
    pcall(function()
        local context = service
        local file = File(filePath)
        setStrictModeAllowFileUri()
        local uri = Uri.fromFile(file)
        
        local intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(uri, "image/*")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(intent)
    end)
end

-- MediaStore helper
local function getMediaStoreDirsAndFiles(rootPath, mediaType)
    local dirs = {}
    local files = {}
    local resolver = service.getContentResolver()
    local uri = MediaStore.Files.getContentUri("external")
    local projection = {MediaStore.Files.FileColumns.DATA}
    local selection = MediaStore.Files.FileColumns.DATA .. " LIKE ?"
    local selArgs = {rootPath .. "/%"}
    local cursor = resolver.query(uri, projection, selection, selArgs, nil)
    if cursor then
        while cursor.moveToNext() do
            local data = cursor.getString(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA))
            if data and data:sub(1, rootPath:len()) == rootPath then
                local relativePath = data:sub(rootPath:len() + 2)
                if relativePath and relativePath ~= "" then
                    local slashPos = relativePath:find("/")
                    if slashPos then
                        local dirName = relativePath:sub(1, slashPos - 1)
                        if dirName ~= "" and not dirName:find("^%.") then
                            dirs[dirName] = true
                        end
                    else
                        local name = relativePath
                        if matchesFormat(name, mediaType) then
                            table.insert(files, {name = name, path = data, isDir = false})
                        end
                    end
                end
            end
        end
        cursor.close()
    end
    local dirList = {}
    for dirName, _ in pairs(dirs) do
        table.insert(dirList, {name = dirName, path = rootPath .. "/" .. dirName, isDir = true})
    end
    table.sort(dirList, function(a,b) return a.name:lower() < b.name:lower() end)
    table.sort(files, function(a,b) return a.name:lower() < b.name:lower() end)
    return dirList, files
end

-- Recursive Scanner Engine
local function getAllRecursiveFiles(rootPath, mediaType)
    local files = {}
    local resolver = service.getContentResolver()
    local uri = MediaStore.Files.getContentUri("external")
    local projection = {MediaStore.Files.FileColumns.DATA, MediaStore.Files.FileColumns.DATE_MODIFIED}
    local selection = MediaStore.Files.FileColumns.DATA .. " LIKE ?"
    local selArgs = {rootPath .. "/%"}
    local cursor = nil
    pcall(function() cursor = resolver.query(uri, projection, selection, selArgs, nil) end)
    if cursor then
        while cursor.moveToNext() do
            local data = cursor.getString(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA))
            if data then
                local fileObj = File(data)
                local name = fileObj.getName()
                if (mediaType == "statuses" or not name:find("^%.")) and matchesFormat(name, mediaType) then
                    local time = 0
                    pcall(function() time = cursor.getLong(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATE_MODIFIED)) * 1000 end)
                    table.insert(files, {name = name, path = data, isDir = false, time = time})
                end
            end
        end
        cursor.close()
    end
    if #files == 0 then
        local function scanDir(dir)
            local list = nil
            pcall(function() list = dir.listFiles() end)
            if not list then return end
            for i = 0, #list - 1 do
                local f = list[i]
                local name = f.getName()
                if mediaType == "statuses" or not name:find("^%.") then
                    local isDir = false
                    pcall(function() isDir = f.isDirectory() end)
                    if isDir then
                        scanDir(f)
                    else
                        if matchesFormat(name, mediaType) then
                            local time = 0
                            pcall(function() time = f.lastModified() end)
                            table.insert(files, {name = name, path = f.getAbsolutePath(), isDir = false, time = time})
                        end
                    end
                end
            end
        end
        scanDir(File(rootPath))
    end
    return files
end

-- Smart Filter
local function hasMedia(fileObj, mediaType, depth)
    if depth > 10 then return false end
    local list = nil
    pcall(function() list = fileObj.listFiles() end)
    if not list then return false end
    for i = 0, #list - 1 do
        local child = list[i]
        local name = child.getName()
        if not name:find("^%.") then
            local isDir = false
            pcall(function() isDir = child.isDirectory() end)
            if isDir then
                if hasMedia(child, mediaType, depth + 1) then return true end
            else
                if matchesFormat(name, mediaType) then return true end
            end
        end
    end
    return false
end

-- Helper to find SD card path
local function getSdCardPathViaMediaStore()
    local resolver = service.getContentResolver()
    local uri = MediaStore.Files.getContentUri("external")
    local projection = {MediaStore.Files.FileColumns.DATA}
    local selection = MediaStore.Files.FileColumns.DATA .. " LIKE ?"
    local selArgs = {"/storage/%"}
    local cursor = nil
    pcall(function()
        cursor = resolver.query(uri, projection, selection, selArgs, nil)
    end)
    if cursor then
        while cursor.moveToNext() do
            local data = cursor.getString(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA))
            if data and data:sub(1, 9) == "/storage/" then
                local relativePath = data:sub(10)
                local slashPos = relativePath:find("/")
                if slashPos then
                    local volume = relativePath:sub(1, slashPos - 1)
                    if volume ~= "emulated" and volume ~= "self" and volume ~= "sdcard0" then
                        cursor.close()
                        return "/storage/" .. volume
                    end
                end
            end
        end
        cursor.close()
    end
    return nil
end

-- Robust SD card path detection
local function getExternalSdCardPath()
    local storageDir = File("/storage")
    local list = storageDir.listFiles()
    if list then
        for i = 0, #list - 1 do
            local f = list[i]
            local name = f.getName()
            if not name:find("^%.") and name ~= "emulated" and name ~= "self" and name ~= "sdcard0" and name ~= "0" then
                local isDir = false
                pcall(function() isDir = f.isDirectory() end)
                if isDir then
                    return f.getAbsolutePath()
                end
            end
        end
    end
    local secondary = os.getenv("SECONDARY_STORAGE")
    if secondary and secondary ~= "" then
        local dir = File(secondary)
        if dir.exists() and dir.isDirectory() then
            return secondary
        end
    end
    local msPath = getSdCardPathViaMediaStore()
    if msPath then
        return msPath
    end
    local mediaRw = File("/mnt/media_rw")
    local listRw = mediaRw.listFiles()
    if listRw then
        for i = 0, #listRw - 1 do
            local f = listRw[i]
            local name = f.getName()
            if not name:find("^%.") and name ~= "emulated" and name ~= "self" then
                local isDir = false
                pcall(function() isDir = f.isDirectory() end)
                if isDir then
                    return f.getAbsolutePath()
                end
            end
        end
    end
    return "/storage"
end

local function saveStatusToGallery(filePath)
    pcall(function()
        local srcFile = File(filePath)
        local fileName = srcFile.getName()
        local mimeType = fileName:lower():find("%.mp4$") and "video/mp4" or "image/jpeg"
        
        local resolver = service.getContentResolver()
        local contentValues = luajava.newInstance("android.content.ContentValues")
        contentValues.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
        contentValues.put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
        contentValues.put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Saved Statuses")
        
        local collection
        if mimeType:find("video") then
            collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        else
            collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        end
        
        local uri = resolver.insert(collection, contentValues)
        if uri then
            local os = resolver.openOutputStream(uri)
            local ins = FileInputStream(srcFile)
            local buffer = newByteArray(8192)
            local len
            while true do
                len = ins.read(buffer)
                if len == -1 then break end
                os.write(buffer, 0, len)
            end
            ins.close()
            os.close()
            showToast("Status saved to Download/Saved Statuses")
        else
            local destDir = File("/storage/emulated/0/Download/Saved Statuses")
            if not destDir.exists() then destDir.mkdirs() end
            local destFile = File(destDir, fileName)
            local inStream = FileInputStream(srcFile)
            local outStream = FileOutputStream(destFile)
            local buffer = newByteArray(4096)
            local bytesRead = inStream.read(buffer)
            while bytesRead ~= -1 do
                outStream.write(buffer, 0, bytesRead)
                bytesRead = inStream.read(buffer)
            end
            inStream.close()
            outStream.close()
            local intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            intent.setData(Uri.fromFile(destFile))
            service.sendBroadcast(intent)
            showToast("Status saved to Download/Saved Statuses (legacy)")
        end
    end)
end

-- Local helper to build playlist dynamically when restoring or playing
local function rebuildPlaylistFromFolder(folderPath, mediaType)
    if not folderPath or folderPath == "" then return end
    local file = File(folderPath)
    local list = file.listFiles()
    local rawItems = {}
    if list and #list > 0 then
        for i = 0, #list - 1 do
            local f = list[i]
            local name = f.getName()
            if (mediaType == "statuses" or not name:find("^%.")) and not f.isDirectory() then
                if matchesFormat(name, mediaType) then
                    local time = 0
                    pcall(function() time = f.lastModified() end)
                    table.insert(rawItems, {name = name, path = f.getAbsolutePath(), isDir = false, time = time})
                end
            end
        end
    else
        local dirs, files = getMediaStoreDirsAndFiles(folderPath, mediaType)
        for _, f in ipairs(files) do
            local time = 0
            pcall(function() time = File(f.path).lastModified() end)
            table.insert(rawItems, {name = f.name, path = f.path, isDir = false, time = time})
        end
    end

    if currentSortMethod == "A-Z" then
        table.sort(rawItems, function(a, b) return a.name:lower() < b.name:lower() end)
    elseif currentSortMethod == "Z-A" then
        table.sort(rawItems, function(a, b) return a.name:lower() > b.name:lower() end)
    elseif currentSortMethod == "Newest" then
        table.sort(rawItems, function(a, b) return (a.time or 0) > (b.time or 0) end)
    elseif currentSortMethod == "Oldest" then
        table.sort(rawItems, function(a, b) return (a.time or 0) < (b.time or 0) end)
    end

    currentPlaylist = {}
    for _, item in ipairs(rawItems) do
        if mediaType == "statuses" then
            if item.path:lower():find("%.mp4$") then
                table.insert(currentPlaylist, item.path)
            end
        else
            table.insert(currentPlaylist, item.path)
        end
    end

    for i, path in ipairs(currentPlaylist) do
        if path == currentFilePath then
            currentIndex = i
            break
        end
    end
end

local showMainMenu, showStorageMenu, showWhatsAppMenu, showMediaTypeMenu, showBrowseModeMenu, renderMediaList, playMedia, showPlayerControls, showMoreOptions, startSeekBarUpdate, showSettingsMenu, showAudioSettingsMenu, showSleepTimerDialog, showPlaybackSpeedMenu, showStatusSettingsMenu, resumeLastPlayerState

-- 1. Main Menu
showMainMenu = function()
    local items = {}
    local actions = {}
    table.insert(items, "Scan")
    table.insert(actions, "scan")
    if showWhatsAppMediaToggle == "on" then
        table.insert(items, "WhatsApp Media")
        table.insert(actions, "whatsapp")
    end
    table.insert(items, "Settings")
    table.insert(actions, "settings")
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Smart player created by a brothers")
    builder.setItems(items, function(dialog, which)
        local action = actions[which + 1]
        if action == "scan" then
            showStorageMenu()
        elseif action == "whatsapp" then
            showWhatsAppMenu()
        elseif action == "settings" then
            showSettingsMenu()
        end
    end)
    builder.setNegativeButton("Close", nil)
    showDialogSafe(builder)
end

-- WhatsApp Media Shortcut
showWhatsAppMenu = function()
    local items = {"WhatsApp Audio", "WhatsApp Voice Notes", "WhatsApp Video", "WhatsApp Statuses"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("WhatsApp Media Center")
    builder.setItems(items, function(dialog, which)
        local baseDir = "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/"
        if not File(baseDir .. "WhatsApp Video").exists() then
            baseDir = "/storage/emulated/0/WhatsApp/Media/"
        end
        local selectedPath = ""
        local mediaType = "audio"
        if which == 0 then
            selectedPath = baseDir .. "WhatsApp Audio"
        elseif which == 1 then
            selectedPath = baseDir .. "WhatsApp Voice Notes"
        elseif which == 2 then
            selectedPath = baseDir .. "WhatsApp Video"
            mediaType = "video"
        elseif which == 3 then
            selectedPath = baseDir .. ".Statuses"
            mediaType = "statuses"
        end
        local checkFile = File(selectedPath)
        if checkFile.exists() and checkFile.isDirectory() then
            currentBrowseMode = "folders"
            currentSearchQuery = ""
            saveState()
            renderMediaList(selectedPath, mediaType)
        else
            showToast("WhatsApp directory not found or empty.")
            showMainMenu()
        end
    end)
    builder.setNegativeButton("Back", function() showMainMenu() end)
    showDialogSafe(builder, function() showMainMenu() end)
end

-- 2. Master Settings Menu
showSettingsMenu = function()
    local displayItems = luajava.newInstance("java.util.ArrayList")
    local lv = ListView(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, displayItems)
    lv.setAdapter(adapter)

    local function updateItems()
        displayItems.clear()
        displayItems.add("Audio Settings")
        displayItems.add("Status Settings")
        displayItems.add("Show WhatsApp Media in Main Menu: " .. showWhatsAppMediaToggle:upper())
        displayItems.add("Multi-Select Mode: " .. multiSelectSetting:upper())
        displayItems.add("About Extension")
        adapter.notifyDataSetChanged()
    end
    updateItems()

    local builder = AlertDialog.Builder(service)
    builder.setTitle("Settings")
    builder.setView(lv)
    
    local dialog = nil
    lv.setOnItemClickListener(AdapterView.OnItemClickListener({
        onItemClick = function(parent, view, position, id)
            if position == 0 then
                dialog.dismiss()
                showAudioSettingsMenu()
            elseif position == 1 then
                dialog.dismiss()
                showStatusSettingsMenu()
            elseif position == 2 then
                showWhatsAppMediaToggle = (showWhatsAppMediaToggle == "on") and "off" or "on"
                saveState()
                showToast("WhatsApp Media Visibility: " .. showWhatsAppMediaToggle:upper())
                updateItems()
                pcall(function() lv.setSelection(position) end)
            elseif position == 3 then
                multiSelectSetting = (multiSelectSetting == "on") and "off" or "on"
                saveState()
                showToast("Multi-Select Mode: " .. multiSelectSetting:upper())
                updateItems()
                pcall(function() lv.setSelection(position) end)
            elseif position == 4 then
                dialog.dismiss()
                Handler(Looper.getMainLooper()).post(Runnable({
                    run = function()
                        local aboutBuilder = AlertDialog.Builder(service)
                        aboutBuilder.setTitle("About Extension")
                        aboutBuilder.setMessage("Smart Player\nCreated by a brothers\n\nOverview:\nA professional high-performance media utility built for advanced persistence control, recursive background scanning, dynamic multi-speed playback modification, and comprehensive automated accessibility assistance.")
                        aboutBuilder.setNegativeButton("Cancel", function() showSettingsMenu() end)
                        aboutBuilder.setPositiveButton("Help & Feedback", DialogInterface.OnClickListener({
                            onClick = function(d, w)
                                pcall(function()
                                    d.dismiss()
                                    local message = "Official Smart Player Support & Feedback:\n\nHello Team,\nI am currently utilizing your Smart Player extension. I am incredibly impressed by its high-performance playback capabilities, robust design, and accessibility integration. Kindly keep me updated regarding future professional releases and technical builds."
                                    local encodedMsg = Uri.encode(message)
                                    local url = "https://api.whatsapp.com/send?phone=923477583735&text=" .. encodedMsg
                                    local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    service.startActivity(intent)
                                end)
                            end
                        }))
                        local abDialog = aboutBuilder.create()
                        abDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                        import "android.view.KeyEvent"
                        abDialog.setOnKeyListener(DialogInterface.OnKeyListener({
                            onKey = function(d, keyCode, event)
                                if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                                    abDialog.dismiss()
                                    showSettingsMenu()
                                    return true
                                end
                                return false
                            end
                        }))
                        abDialog.show()
                    end
                }))
            end
        end
    }))
    builder.setNegativeButton("Back", function() dialog.dismiss() showMainMenu() end)
    
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dialog.show()
        end
    }))
end

-- Status Settings Sub-Menu
showStatusSettingsMenu = function()
    local displayItems = luajava.newInstance("java.util.ArrayList")
    local lv = ListView(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, displayItems)
    lv.setAdapter(adapter)

    local function updateItems()
        displayItems.clear()
        displayItems.add("Show Images in Status Folder: " .. showStatusImages:upper())
        displayItems.add("Show Videos in Status Folder: " .. showStatusVideos:upper())
        adapter.notifyDataSetChanged()
    end
    updateItems()

    local builder = AlertDialog.Builder(service)
    builder.setTitle("Status Settings")
    builder.setView(lv)
    
    local dialog = nil
    lv.setOnItemClickListener(AdapterView.OnItemClickListener({
        onItemClick = function(parent, view, position, id)
            if position == 0 then
                showStatusImages = (showStatusImages == "on") and "off" or "on"
                showToast("Images in Status: " .. showStatusImages:upper())
                updateItems()
                pcall(function() lv.setSelection(position) end)
            elseif position == 1 then
                showStatusVideos = (showStatusVideos == "on") and "off" or "on"
                showToast("Videos in Status: " .. showStatusVideos:upper())
                updateItems()
                pcall(function() lv.setSelection(position) end)
            end
            saveState()
        end
    }))
    builder.setNegativeButton("Back", function() dialog.dismiss() showSettingsMenu() end)
    
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dialog.show()
        end
    }))
end

-- Audio Settings Sub-Menu
showAudioSettingsMenu = function()
    local displayItems = luajava.newInstance("java.util.ArrayList")
    local lv = ListView(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, displayItems)
    lv.setAdapter(adapter)

    local function updateItems()
        displayItems.clear()
        local currentSec = math.floor(ffRwDuration / 1000)
        displayItems.add("Fast Forward and Rewind Changing Time: " .. currentSec .. " Seconds")
        displayItems.add("Background Playback: " .. backgroundPlay:upper())
        displayItems.add("Auto Play Next File: " .. autoPlay:upper())
        displayItems.add("Playback Speed: " .. currentPlaybackSpeed .. "x")
        displayItems.add("Set Sleep Timer Duration")
        displayItems.add("Show Volume Boost on Player: " .. showVolumeBoostToggle:upper())
        displayItems.add("Show Sleep Timer on Player: " .. showSleepTimerToggle:upper())
        adapter.notifyDataSetChanged()
    end
    updateItems()

    local builder = AlertDialog.Builder(service)
    builder.setTitle("Audio Settings")
    builder.setView(lv)
    
    local dialog = nil
    lv.setOnItemClickListener(AdapterView.OnItemClickListener({
        onItemClick = function(parent, view, position, id)
            if position == 0 then
                dialog.dismiss()
                local durItems = {}
                local actionDurations = {}
                for _, dur in ipairs(_G.ffRwOptions) do
                    table.insert(durItems, math.floor(dur / 1000) .. " Seconds")
                    table.insert(actionDurations, dur)
                end
                table.insert(durItems, "Add Custom Duration...")
                
                local lvDur = ListView(service)
                local adapterDur = ArrayAdapter(service, android.R.layout.simple_list_item_1, durItems)
                lvDur.setAdapter(adapterDur)
                
                local durBuilder = AlertDialog.Builder(service)
                durBuilder.setTitle("Select FF/RW Duration (Long Press to Delete)")
                durBuilder.setView(lvDur)
                local durDialog = nil
                
                lvDur.setOnItemClickListener(AdapterView.OnItemClickListener({
                    onItemClick = function(p, v, pos, i)
                        local idx = pos + 1
                        if idx == #durItems then
                            durDialog.dismiss()
                            Handler(Looper.getMainLooper()).post(Runnable({
                                run = function()
                                    local inputField = EditText(service)
                                    inputField.setHint("Enter seconds (e.g., 25)")
                                    inputField.setInputType(InputType.TYPE_CLASS_NUMBER)
                                    
                                    local customDurBuilder = AlertDialog.Builder(service)
                                    customDurBuilder.setTitle("Enter Custom Duration")
                                    customDurBuilder.setView(inputField)
                                    customDurBuilder.setPositiveButton("Add", function()
                                        local val = tonumber(tostring(inputField.getText()))
                                        if val and val > 0 then
                                            table.insert(_G.ffRwOptions, val * 1000)
                                            ffRwDuration = val * 1000
                                            saveState()
                                            showToast("Duration added and selected: " .. val .. " seconds")
                                        else
                                            showToast("Invalid duration")
                                        end
                                        showAudioSettingsMenu()
                                    end)
                                    customDurBuilder.setNegativeButton("Cancel", function() showAudioSettingsMenu() end)
                                    showDialogSafe(customDurBuilder, function() showAudioSettingsMenu() end)
                                end
                            }))
                        else
                            ffRwDuration = actionDurations[idx]
                            saveState()
                            showToast("Duration updated to " .. math.floor(ffRwDuration / 1000) .. " seconds")
                            durDialog.dismiss()
                            showAudioSettingsMenu()
                        end
                    end
                }))
                
                lvDur.setOnItemLongClickListener(AdapterView.OnItemLongClickListener({
                    onItemLongClick = function(p, v, pos, i)
                        local idx = pos + 1
                        if idx < #durItems then
                            local targetDel = actionDurations[idx]
                            durDialog.dismiss()
                            local confDel = AlertDialog.Builder(service)
                            confDel.setTitle("Delete Duration?")
                            confDel.setMessage("Are you sure you want to delete " .. math.floor(targetDel / 1000) .. " seconds from list?")
                            confDel.setPositiveButton("Delete", function()
                                table.remove(_G.ffRwOptions, idx)
                                showToast("Duration deleted.")
                                showAudioSettingsMenu()
                            end)
                            confDel.setNegativeButton("Cancel", function() showAudioSettingsMenu() end)
                            showDialogSafe(confDel, function() showAudioSettingsMenu() end)
                        end
                        return true
                    end
                }))
                
                Handler(Looper.getMainLooper()).post(Runnable({
                    run = function()
                        durDialog = durBuilder.create()
                        durDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                        durDialog.show()
                    end
                }))
                
            elseif position == 1 then
                backgroundPlay = (backgroundPlay == "on") and "off" or "on"
                if backgroundPlay == "off" then cancelNotification() end
                saveState()
                showToast("Background playback " .. backgroundPlay)
                updateItems()
                pcall(function() lv.setSelection(position) end)
            elseif position == 2 then
                autoPlay = (autoPlay == "on") and "off" or "on"
                saveState()
                showToast("Auto Play " .. autoPlay)
                updateItems()
                pcall(function() lv.setSelection(position) end)
            elseif position == 3 then
                dialog.dismiss()
                showPlaybackSpeedMenu("settings")
            elseif position == 4 then
                dialog.dismiss()
                showSleepTimerDialog()
            elseif position == 5 then
                showVolumeBoostToggle = (showVolumeBoostToggle == "on") and "off" or "on"
                saveState()
                showToast("Volume Boost: " .. showVolumeBoostToggle:upper())
                updateItems()
                pcall(function() lv.setSelection(position) end)
            elseif position == 6 then
                showSleepTimerToggle = (showSleepTimerToggle == "on") and "off" or "on"
                saveState()
                showToast("Sleep Timer: " .. showSleepTimerToggle:upper())
                updateItems()
                pcall(function() lv.setSelection(position) end)
            end
        end
    }))
    builder.setNegativeButton("Back", function() dialog.dismiss() showSettingsMenu() end)
    
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dialog.show()
        end
    }))
end

-- Playback Speed Menu
showPlaybackSpeedMenu = function(parentMenu)
    local availableSpeeds = {0.5, 0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 2.75, 3.0, 3.5, 3.75, 4.0}
    local displayItems = luajava.newInstance("java.util.ArrayList")
    local lv = ListView(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, displayItems)
    lv.setAdapter(adapter)

    local activeIdx = 0
    for i, v in ipairs(availableSpeeds) do
        if math.abs(currentPlaybackSpeed - v) < 0.01 then
            displayItems.add(string.format("%.2fx (Active)", v))
            activeIdx = i - 1
        else
            displayItems.add(string.format("%.2fx", v))
        end
    end
    
    local speedBuilder = AlertDialog.Builder(service)
    speedBuilder.setTitle("Playback Speed")
    speedBuilder.setView(lv)
    
    local dialog = nil
    lv.setOnItemClickListener(AdapterView.OnItemClickListener({
        onItemClick = function(parent, view, position, id)
            currentPlaybackSpeed = availableSpeeds[position + 1]
            applyPlaybackSpeed()
            saveState()
            showToast("Playback speed changed: " .. currentPlaybackSpeed .. "x")
            dialog.dismiss()
            if parentMenu == "settings" then showAudioSettingsMenu() else showMoreOptions() end
        end
    }))

    local backFunc = function()
        dialog.dismiss()
        if parentMenu == "settings" then showAudioSettingsMenu() else showMoreOptions() end
    end
    speedBuilder.setNegativeButton("Back", backFunc)
    
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            dialog = speedBuilder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            import "android.view.KeyEvent"
            dialog.setOnKeyListener(DialogInterface.OnKeyListener({
                onKey = function(d, keyCode, event)
                    if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                        backFunc()
                        return true
                    end
                    return false
                end
            }))
            dialog.show()
            pcall(function() lv.setSelection(activeIdx) end)
        end
    }))
end

-- Sleep Timer Dialog
showSleepTimerDialog = function()
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local context = service
            local layout = LinearLayout(context)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(50, 40, 50, 40)
            local txtMsg = TextView(context)
            txtMsg.setText("Select Your Sleep Mode Time Duration:")
            txtMsg.setTextSize(16)
            txtMsg.setPadding(0, 0, 0, 20)
            layout.addView(txtMsg)
            local etHours = EditText(context)
            etHours.setHint("Enter Hours")
            etHours.setInputType(InputType.TYPE_CLASS_NUMBER)
            layout.addView(etHours)
            local etMinutes = EditText(context)
            etMinutes.setHint("Enter Minutes")
            etMinutes.setInputType(InputType.TYPE_CLASS_NUMBER)
            layout.addView(etMinutes)
            local etSeconds = EditText(context)
            etSeconds.setHint("Enter Seconds")
            etSeconds.setInputType(InputType.TYPE_CLASS_NUMBER)
            layout.addView(etSeconds)
            local builder = AlertDialog.Builder(context)
            builder.setTitle("Sleep Timer Manager")
            builder.setView(layout)
            builder.setPositiveButton("Set Timer", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    local h = tonumber(tostring(etHours.getText())) or 0
                    local m = tonumber(tostring(etMinutes.getText())) or 0
                    local s = tonumber(tostring(etSeconds.getText())) or 0
                    local totalMs = ((h * 3600) + (m * 60) + s) * 1000
                    if totalMs > 0 then
                        sleepDurationMs = totalMs
                        sleepModeActive = "on"
                        saveState()
                        if btnSleepToggleRef then btnSleepToggleRef.setText("Sleep Mode: ON") end
                        pcall(function()
                            _G.sleepTargetPos = player.getCurrentPosition() + sleepDurationMs
                            lastSleepAudioPath = _G.smart_player_current_path
                        end)
                        startSeekBarUpdate()
                        
                        local timeStr = ""
                        if h > 0 then timeStr = timeStr .. h .. " hours " end
                        if m > 0 then timeStr = timeStr .. m .. " minutes " end
                        if s > 0 then timeStr = timeStr .. s .. " seconds " end
                        showToast("Sleep timer on for " .. timeStr)
                        showAudioSettingsMenu()
                    else
                        showToast("Invalid time duration entered.")
                        showAudioSettingsMenu()
                    end
                end
            }))
            builder.setNegativeButton("Cancel", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    showAudioSettingsMenu()
                end
            }))
            local dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            import "android.view.KeyEvent"
            dialog.setOnKeyListener(DialogInterface.OnKeyListener({
                onKey = function(d, keyCode, event)
                    if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                        dialog.dismiss()
                        showAudioSettingsMenu()
                        return true
                    end
                    return false
                end
            }))
            dialog.show()
        end
    }))
end

-- 3. Storage Selection
showStorageMenu = function()
    local items = {"Internal Storage", "SD Card"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Choose Your Storage")
    builder.setItems(items, function(dialog, which)
        local selectedStorage = "/storage/emulated/0"
        if which == 1 then
            local sdPath = getExternalSdCardPath()
            if not sdPath or sdPath == "/storage" or sdPath == "/storage/emulated/0" then
                showToast("Not inserted SD card")
                showStorageMenu()
                return
            end
            selectedStorage = sdPath
        end
        showMediaTypeMenu(selectedStorage)
    end)
    builder.setNegativeButton("Back", function() showMainMenu() end)
    showDialogSafe(builder, function() showMainMenu() end)
end

-- 4. Media Type Selection
showMediaTypeMenu = function(storagePath)
    local items = {"Audio", "Video"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Choose Your Selection")
    builder.setItems(items, function(dialog, which)
        local mediaType = (which == 0) and "audio" or "video"
        showBrowseModeMenu(storagePath, mediaType)
    end)
    builder.setNegativeButton("Back", function() showStorageMenu() end)
    showDialogSafe(builder, function() showStorageMenu() end)
end

-- 5. Selection Mode Menu
showBrowseModeMenu = function(storagePath, mediaType)
    local items = {"All Files", "Browse Folders", "Favorites"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Select Mode")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
            currentBrowseMode = "all_files"
        elseif which == 1 then
            currentBrowseMode = "folders"
        else
            currentBrowseMode = "favorites"
        end
        currentSearchQuery = ""
        saveState()
        renderMediaList(storagePath, mediaType)
    end)
    builder.setNegativeButton("Back", function() showMediaTypeMenu(storagePath) end)
    showDialogSafe(builder, function() showMediaTypeMenu(storagePath) end)
end

-- 6. Unified Media List Engine
renderMediaList = function(currentPath, mediaType)
    if currentPath == "/storage" then
        local autoSd = getExternalSdCardPath()
        if autoSd and autoSd ~= "/storage" then currentPath = autoSd else currentPath = "/storage/emulated/0" end
    end
    if currentPath == "/storage/emulated" then currentPath = "/storage/emulated/0" end

    currentSavedFolder = currentPath
    currentSavedMediaType = mediaType
    saveState()

    local rawItems = {}

    if currentBrowseMode == "all_files" then
        showToast("Scanning files, please wait...")
        rawItems = getAllRecursiveFiles(currentPath, mediaType)
    elseif currentBrowseMode == "favorites" then
        rawItems = {}
        for path, _ in pairs(favoritesMap) do
            if path:sub(1, #currentPath) == currentPath then
                local f = File(path)
                if f.exists() then
                    local name = f.getName()
                    if matchesFormat(name, mediaType) then
                        local time = 0
                        pcall(function() time = f.lastModified() end)
                        table.insert(rawItems, {name = name, path = path, isDir = false, time = time})
                    end
                end
            end
        end
    else
        local file = File(currentPath)
        local list = nil
        pcall(function() list = file.listFiles() end)
        local isStorageRoot = (currentPath == "/storage")

        if list and #list > 0 then
            for i = 0, #list - 1 do
                local f = list[i]
                local name = f.getName()
                if (mediaType == "statuses" or not name:find("^%.")) and name ~= "emulated" and name ~= "self" and name ~= "sdcard0" and name ~= "0" then
                    if not (isStorageRoot and name:find("^%w+-%w+$")) then
                        local isDir = false
                        pcall(function() isDir = f.isDirectory() end)
                        local time = 0
                        pcall(function() time = f.lastModified() end)
                        if isDir then
                            if currentPath == "/storage" or hasMedia(f, mediaType, 1) then
                                table.insert(rawItems, {name = name, path = f.getAbsolutePath(), isDir = true, time = time})
                            end
                        else
                            if matchesFormat(name, mediaType) then
                                table.insert(rawItems, {name = name, path = f.getAbsolutePath(), isDir = false, time = time})
                            end
                        end
                    end
                end
            end
        else
            local dirs, files = getMediaStoreDirsAndFiles(currentPath, mediaType)
            for _, d in ipairs(dirs) do
                if d.name ~= "emulated" and d.name ~= "self" and d.name ~= "sdcard0" and d.name ~= "0" then
                    if File(d.path).exists() then
                        local time = 0
                        pcall(function() time = File(d.path).lastModified() end)
                        table.insert(rawItems, {name = d.name, path = d.path, isDir = true, time = time})
                    end
                end
            end
            for _, f in ipairs(files) do
                if File(f.path).exists() then
                    local time = 0
                    pcall(function() time = File(f.path).lastModified() end)
                    table.insert(rawItems, {name = f.name, path = f.path, isDir = false, time = time})
                end
            end
        end
    end

    local filteredList = {}
    for _, item in ipairs(rawItems) do
        local keeps = true
        if currentSearchQuery ~= "" then
            if not item.name:lower():find(currentSearchQuery:lower(), 1, true) then
                keeps = false
            end
        end
        if keeps then table.insert(filteredList, item) end
    end

    if currentSortMethod == "A-Z" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return a.name:lower() < b.name:lower()
        end)
    elseif currentSortMethod == "Z-A" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return a.name:lower() > b.name:lower()
        end)
    elseif currentSortMethod == "Newest" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return (a.time or 0) > (b.time or 0)
        end)
    elseif currentSortMethod == "Oldest" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return (a.time or 0) < (b.time or 0)
        end)
    end

    if #filteredList == 0 and currentSearchQuery == "" then
        if currentBrowseMode == "favorites" then
            showToast("Favorite Button Empty")
            showBrowseModeMenu(currentPath, mediaType)
        else
            showToast("No files found.")
            if tostring(currentPath):find("WhatsApp") then
                showWhatsAppMenu()
            else
                showMainMenu()
            end
        end
        return
    end

    local displayItems = luajava.newInstance("java.util.ArrayList")
    local actionItems = {}

    local lvMedia = ListView(service)
    local adapterMedia = ArrayAdapter(service, android.R.layout.simple_list_item_1, displayItems)
    lvMedia.setAdapter(adapterMedia)

    local mainLayout = LinearLayout(service)
    mainLayout.setOrientation(LinearLayout.VERTICAL)
    
    local lvParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1.0)
    lvMedia.setLayoutParams(lvParams)
    mainLayout.addView(lvMedia)

    local bottomBar = nil
    local btnCancel = nil
    local btnShare = nil
    local btnDelete = nil
    local mediaListDialog = nil

    local function updateListAndButtons()
        displayItems.clear()
        actionItems = {}

        local searchString = "Search"
        if currentSearchQuery ~= "" then searchString = "Search: " .. currentSearchQuery end
        displayItems.add(searchString)
        table.insert(actionItems, {type = "control", target = "search"})

        local sortMethodsTranslations = {["A-Z"] = "A-Z", ["Z-A"] = "Z-A", ["Newest"] = "Newest First", ["Oldest"] = "Oldest First"}
        displayItems.add("Sort By: " .. (sortMethodsTranslations[currentSortMethod] or currentSortMethod))
        table.insert(actionItems, {type = "control", target = "sort"})

        if currentSearchQuery ~= "" then
            displayItems.add("Clear Search")
            table.insert(actionItems, {type = "control", target = "clear_search"})
        end

        if isMultiSelectActive then
            displayItems.add("[Select All]")
            table.insert(actionItems, {type = "multiselect_control", target = "select_all"})
        end

        for _, item in ipairs(filteredList) do
            local prefix = ""
            if isMultiSelectActive then
                if selectedItemsMap[item.path] then 
                    prefix = "[Checkbox Checked] " 
                else 
                    prefix = "[Checkbox Not Checked] " 
                end
            else
                if not item.isDir then
                    if mediaType == "video" or (mediaType == "statuses" and item.name:lower():find("%.mp4$")) then
                        prefix = "📹 "
                    elseif mediaType == "statuses" then
                        prefix = "🖼️ "
                    end
                end
            end
            
            if item.isDir then
                displayItems.add(prefix .. "[Folder] " .. item.name)
                table.insert(actionItems, {type = "media", data = item})
            else
                displayItems.add(prefix .. item.name)
                table.insert(actionItems, {type = "media", data = item})
            end
        end

        adapterMedia.notifyDataSetChanged()

        if isMultiSelectActive and btnShare and btnDelete then
            local selCount, selSizeStr = getSelectedStats(filteredList, selectedItemsMap)
            btnShare.setText(string.format("Share (%d items, %s)", selCount, selSizeStr))
            btnDelete.setText(string.format("Delete (%d items, %s)", selCount, selSizeStr))
            
            local hasFolderSelected = false
            for _, item in ipairs(filteredList) do
                if selectedItemsMap[item.path] and item.isDir then
                    hasFolderSelected = true
                    break
                end
            end
            if hasFolderSelected then
                btnShare.setVisibility(View.GONE)
            else
                btnShare.setVisibility(View.VISIBLE)
            end
        end
    end

    bottomBar = LinearLayout(service)
    bottomBar.setOrientation(LinearLayout.HORIZONTAL)
    bottomBar.setGravity(Gravity.RIGHT)
    local barParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    bottomBar.setLayoutParams(barParams)

    btnCancel = Button(service)
    btnCancel.setText("Cancel")
    btnCancel.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            isMultiSelectActive = false
            selectedItemsMap = {}
            if bottomBar then bottomBar.setVisibility(View.GONE) end
            updateListAndButtons()
        end
    }))

    btnShare = Button(service)
    btnShare.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            local sharePaths = {}
            for _, item in ipairs(filteredList) do
                if not item.isDir and selectedItemsMap[item.path] then
                    table.insert(sharePaths, item.path)
                end
            end
            if #sharePaths == 0 then
                showToast("No files selected to share. Folders cannot be shared directly.")
                return
            end
            saveState()
            mediaListDialog.dismiss()
            
            local originalPackage = ""
            pcall(function()
                local root = service.getRootInActiveWindow()
                if root then originalPackage = tostring(root.getPackageName()) end
            end)
            if originalPackage == "" or originalPackage == "android" or originalPackage == "com.android.intentresolver" then
                originalPackage = "com.android.launcher3"
            end
            
            pcall(function()
                local context = service
                setStrictModeAllowFileUri()
                if #sharePaths == 1 then
                    local file = File(sharePaths[1])
                    local shareUri = Uri.fromFile(file)
                    local intent = Intent(Intent.ACTION_SEND)
                    intent.setType("*/*")
                    intent.putExtra(Intent.EXTRA_STREAM, shareUri)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    local chooser = Intent.createChooser(intent, "Share File")
                    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(chooser)
                else
                    local uris = luajava.newInstance("java.util.ArrayList")
                    for _, path in ipairs(sharePaths) do
                        uris.add(Uri.fromFile(File(path)))
                    end
                    local intent = Intent(Intent.ACTION_SEND_MULTIPLE)
                    intent.setType("*/*")
                    intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    local chooser = Intent.createChooser(intent, "Share Files")
                    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(chooser)
                end
            end)
            
            local monitorHandler = Handler(Looper.getMainLooper())
            local monitorRunnable
            local loopCount = 0
            local hasLeftApp = false
            
            monitorRunnable = Runnable({
                run = function()
                    loopCount = loopCount + 1
                    local currentPkg = ""
                    pcall(function()
                        local root = service.getRootInActiveWindow()
                        if root then currentPkg = tostring(root.getPackageName()) end
                    end)
                    local currentPkgLower = currentPkg:lower()
                    
                    if currentPkg ~= "" and currentPkg ~= originalPackage and not currentPkgLower:find("launcher") and not currentPkgLower:find("home") then
                        hasLeftApp = true
                    end
                    
                    if hasLeftApp and (currentPkg == originalPackage or currentPkgLower:find("launcher") or currentPkgLower:find("home")) then
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function() 
                                if currentFilePath and currentFilePath ~= "" then
                                    showPlayerControls()
                                else
                                    renderMediaList(currentPath, mediaType)
                                end
                            end
                        }))
                    elseif not hasLeftApp and loopCount > 10 then
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function()
                                if currentFilePath and currentFilePath ~= "" then
                                    showPlayerControls()
                                else
                                    renderMediaList(currentPath, mediaType)
                                end
                            end
                        }))
                    elseif loopCount < 120 then
                        monitorHandler.postDelayed(monitorRunnable, 1000)
                    end
                end
            })
            monitorHandler.postDelayed(monitorRunnable, 1000)
            
            isMultiSelectActive = false
            selectedItemsMap = {}
        end
    }))

    btnDelete = Button(service)
    btnDelete.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            local selCount, selSizeStr = getSelectedStats(filteredList, selectedItemsMap)
            if selCount == 0 then
                showToast("No items selected.")
            else
                local confSelDel = AlertDialog.Builder(service)
                confSelDel.setTitle("Confirm Deletion")
                confSelDel.setMessage(string.format("Are you sure you want to permanently delete %d selected items (%s)?", selCount, selSizeStr))
                confSelDel.setPositiveButton("Delete All", function()
                    mediaListDialog.dismiss()
                    showToast("Deleting selected items...")
                    
                    Thread(Runnable({
                        run = function()
                            local resetPlayer = false
                            for _, item in ipairs(filteredList) do
                                if selectedItemsMap[item.path] and currentFilePath == item.path then
                                    resetPlayer = true
                                end
                            end
                            if resetPlayer then
                                Handler(Looper.getMainLooper()).post(Runnable({
                                    run = function() player.reset() cancelNotification() end
                                }))
                                _G.smart_player_is_prepared = false
                                _G.smart_player_current_path = ""
                                currentFilePath = "" lastPlayedPosition = 0
                            end

                            local successCount = 0
                            for _, item in ipairs(filteredList) do
                                if selectedItemsMap[item.path] then
                                    local targetFile = File(item.path)
                                    if item.isDir then
                                        if deleteFolderRecursive(targetFile) then successCount = successCount + 1 end
                                    else
                                        if targetFile.delete() then successCount = successCount + 1 end
                                    end
                                end
                            end
                            
                            Handler(Looper.getMainLooper()).post(Runnable({
                                run = function()
                                    showToast(successCount .. " items deleted successfully.")
                                    isMultiSelectActive = false
                                    selectedItemsMap = {}
                                    saveState()
                                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                                    renderMediaList(currentPath, mediaType)
                                end
                            }))
                        end
                    })).start()
                end)
                confSelDel.setNegativeButton("Cancel", nil)
                showDialogSafe(confSelDel, function() end)
            end
        end
    }))

    bottomBar.addView(btnCancel)
    bottomBar.addView(btnShare)
    bottomBar.addView(btnDelete)
    mainLayout.addView(bottomBar)

    if isMultiSelectActive then
        bottomBar.setVisibility(View.VISIBLE)
    else
        bottomBar.setVisibility(View.GONE)
    end

    updateListAndButtons()

    local builder = AlertDialog.Builder(service)
    builder.setTitle(currentBrowseMode == "all_files" and "All Files" or (currentBrowseMode == "favorites" and "Favorites" or "Browse Folders"))
    builder.setView(mainLayout)

    lvMedia.setOnItemClickListener(AdapterView.OnItemClickListener({
        onItemClick = function(parent, view, position, id)
            local action = actionItems[position + 1]
            if not action then return end
            
            if action.type == "control" then
                if action.target == "search" then
                    mediaListDialog.dismiss()
                    Handler(Looper.getMainLooper()).post(Runnable({
                        run = function()
                            local inputField = EditText(service)
                            inputField.setHint("Search...")
                            if currentSearchQuery ~= "" then inputField.setText(currentSearchQuery) end
                            local searchDialog = AlertDialog.Builder(service)
                            searchDialog.setTitle("Search")
                            searchDialog.setView(inputField)
                            searchDialog.setPositiveButton("Search", function()
                                currentSearchQuery = tostring(inputField.getText())
                                renderMediaList(currentPath, mediaType)
                            end)
                            searchDialog.setNegativeButton("Cancel", function()
                                renderMediaList(currentPath, mediaType)
                            end)
                            showDialogSafe(searchDialog, function() renderMediaList(currentPath, mediaType) end)
                        end
                    }))
                elseif action.target == "sort" then
                    mediaListDialog.dismiss()
                    local sortOptions = {"A-Z", "Z-A", "Newest First", "Oldest First"}
                    local sortOptionBuilder = AlertDialog.Builder(service)
                    sortOptionBuilder.setTitle("Sort By")
                    sortOptionBuilder.setItems(sortOptions, function(d, w)
                        if w == 0 then currentSortMethod = "A-Z"
                        elseif w == 1 then currentSortMethod = "Z-A"
                        elseif w == 2 then currentSortMethod = "Newest"
                        elseif w == 3 then currentSortMethod = "Oldest" end
                        saveState()
                        renderMediaList(currentPath, mediaType)
                    end)
                    showDialogSafe(sortOptionBuilder, function() renderMediaList(currentPath, mediaType) end)
                elseif action.target == "clear_search" then
                    currentSearchQuery = ""
                    mediaListDialog.dismiss()
                    renderMediaList(currentPath, mediaType)
                end
            elseif action.type == "multiselect_control" then
                if action.target == "select_all" then
                    for _, item in ipairs(filteredList) do
                        selectedItemsMap[item.path] = true
                    end
                    updateListAndButtons()
                    pcall(function() lvMedia.setSelection(position) end)
                end
            elseif action.type == "media" then
                local selectedMedia = action.data
                if isMultiSelectActive then
                    selectedItemsMap[selectedMedia.path] = not selectedItemsMap[selectedMedia.path]
                    if selectedItemsMap[selectedMedia.path] then
                        service.speak("Checkbox checked")
                    else
                        service.speak("Checkbox unchecked")
                    end
                    updateListAndButtons() 
                    pcall(function() lvMedia.setSelection(position) end)
                else
                    if selectedMedia.isDir then
                        mediaListDialog.dismiss()
                        renderMediaList(selectedMedia.path, mediaType)
                    else
                        if mediaType == "statuses" and not selectedMedia.path:lower():find("%.mp4$") then
                            openImageExternally(selectedMedia.path)
                        else
                            mediaListDialog.dismiss()
                            currentPlaylist = {}
                            for _, innerObj in ipairs(filteredList) do
                                if not innerObj.isDir then
                                    if mediaType == "statuses" then
                                        if innerObj.path:lower():find("%.mp4$") then
                                            table.insert(currentPlaylist, innerObj.path)
                                            if innerObj.path == selectedMedia.path then currentIndex = #currentPlaylist end
                                        end
                                    else
                                        table.insert(currentPlaylist, innerObj.path)
                                        if innerObj.path == selectedMedia.path then currentIndex = #currentPlaylist end
                                    end
                                end
                            end
                            lastPlayedPosition = 0
                            playMedia(selectedMedia.path, true)
                        end
                    end
                end
            end
        end
    }))

    lvMedia.setOnItemLongClickListener(AdapterView.OnItemLongClickListener({
        onItemLongClick = function(parent, view, position, id)
            local action = actionItems[position + 1]
            if action and action.type == "media" then
                local targetMedia = action.data
                if multiSelectSetting == "on" then
                    if not isMultiSelectActive then
                        isMultiSelectActive = true
                        selectedItemsMap = {}
                        selectedItemsMap[targetMedia.path] = true
                        showToast("Multi-select mode enabled.")
                        if bottomBar then bottomBar.setVisibility(View.VISIBLE) end
                        updateListAndButtons()
                        pcall(function() lvMedia.setSelection(position) end)
                    end
                else
                    local confSingleDel = AlertDialog.Builder(service)
                    confSingleDel.setTitle("Delete Item?")
                    
                    local msg = "Are you sure you want to permanently delete: " .. targetMedia.name .. "?"
                    if targetMedia.isDir then
                        local totalSize = getFolderSizeRecursive(File(targetMedia.path))
                        local sizeStr = formatSize(totalSize)
                        msg = "Do you want to delete this folder: " .. targetMedia.name .. " (" .. sizeStr .. ")?"
                    end
                    confSingleDel.setMessage(msg)
                    
                    confSingleDel.setPositiveButton("Delete", function()
                        showToast("Deleting...")
                        Thread(Runnable({
                            run = function()
                                local targetFile = File(targetMedia.path)
                                local deleted = false
                                if targetMedia.isDir then
                                    deleted = deleteFolderRecursive(targetFile)
                                else
                                    deleted = targetFile.delete()
                                end
                                
                                Handler(Looper.getMainLooper()).post(Runnable({
                                    run = function()
                                        if deleted then
                                            showToast("Deleted successfully.")
                                            if currentFilePath == targetMedia.path then
                                                player.reset() cancelNotification()
                                                currentFilePath = "" lastPlayedPosition = 0 saveState()
                                                if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                                            end
                                            mediaListDialog.dismiss()
                                            renderMediaList(currentPath, mediaType)
                                        else
                                            showToast("Failed to delete.")
                                        end
                                    end
                                }))
                            end
                        })).start()
                    end)
                    confSingleDel.setNegativeButton("Cancel", nil)
                    showDialogSafe(confSingleDel)
                end
            end
            return true
        end
    }))

    local backFunc = function()
        if isMultiSelectActive then
            isMultiSelectActive = false
            selectedItemsMap = {}
            if bottomBar then bottomBar.setVisibility(View.GONE) end
            updateListAndButtons()
        else
            mediaListDialog.dismiss()
            
            local pathStr = tostring(currentPath)
            if pathStr:find("WhatsApp/Media") then
                local name = File(currentPath).getName()
                if name == "WhatsApp Audio" or name == "WhatsApp Voice Notes" or name == "WhatsApp Video" or name == ".Statuses" then
                    showWhatsAppMenu()
                    return
                end
            end
            
            if currentBrowseMode == "all_files" or currentBrowseMode == "favorites" then
                local baseStorage = "/storage/emulated/0"
                local sdPath = getExternalSdCardPath()
                if sdPath and pathStr:sub(1, #sdPath) == sdPath then baseStorage = sdPath end
                showBrowseModeMenu(baseStorage, mediaType)
            else
                local sdPath = getExternalSdCardPath()
                if currentPath == "/storage/emulated/0" or (sdPath and currentPath == sdPath) then
                    local baseStorage = "/storage/emulated/0"
                    if sdPath and pathStr:sub(1, #sdPath) == sdPath then baseStorage = sdPath end
                    showBrowseModeMenu(baseStorage, mediaType)
                else
                    local parentDir = File(currentPath).getParent()
                    if parentDir and parentDir ~= "/storage" and parentDir ~= "/storage/emulated" then
                        renderMediaList(parentDir, mediaType)
                    else
                        local baseStorage = "/storage/emulated/0"
                        if sdPath and pathStr:sub(1, #sdPath) == sdPath then baseStorage = sdPath end
                        showBrowseModeMenu(baseStorage, mediaType)
                    end
                end
            end
        end
    end
    
    builder.setNegativeButton("Back", backFunc)
    
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            mediaListDialog = builder.create()
            mediaListDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            import "android.view.KeyEvent"
            mediaListDialog.setOnKeyListener(DialogInterface.OnKeyListener({
                onKey = function(d, keyCode, event)
                    if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                        backFunc()
                        return true
                    end
                    return false
                end
            }))
            mediaListDialog.show()
        end
    }))
end

-- 7. Media Playback Function
playMedia = function(filePath, forcePlay)
    currentFilePath = filePath
    saveState()
    
    for i, path in ipairs(currentPlaylist) do
        if path == filePath then
            currentIndex = i
            break
        end
    end
    
    local shouldStart = false
    if forcePlay ~= nil then
        shouldStart = forcePlay
    else
        pcall(function() shouldStart = player.isPlaying() end)
    end

    local success, err = pcall(function()
        player.reset()
        player.setDataSource(filePath)
        player.prepare()
        _G.smart_player_is_prepared = true
        _G.smart_player_current_path = filePath
        
        if currentSurfaceHolder then
            pcall(function() player.setDisplay(currentSurfaceHolder) end)
        end
        
        loudnessEnhancer = LoudnessEnhancer(player.getAudioSessionId())
        applyVolumeBoost(true)
        
        player.setOnCompletionListener(MediaPlayer.OnCompletionListener({
            onCompletion = function(mp)
                if autoPlay == "on" then
                    if currentIndex < #currentPlaylist then
                        currentIndex = currentIndex + 1
                        lastPlayedPosition = 0
                        playMedia(currentPlaylist[currentIndex], true)
                    else
                        cancelNotification()
                        if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
                    end
                else
                    cancelNotification()
                    if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
                end
            end
        }))
        
        if lastPlayedPosition > 0 then player.seekTo(lastPlayedPosition) end
        
        if shouldStart then
            player.start()
            applyPlaybackSpeed()
            if btnPlayPauseRef then btnPlayPauseRef.setText("Pause") end
            if backgroundPlay == "on" then showNotification(File(filePath).getName()) end
        else
            if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
            cancelNotification()
        end
    end)
    if not success then showToast("Playback Error.") end
    showPlayerControls()
end

-- 8. Custom Player Window
showPlayerControls = function()
    -- Dynamic Playlist Rebuild from saved folder state on wake up / resume
    if #currentPlaylist == 0 and currentSavedFolder and currentSavedFolder ~= "" then
        rebuildPlaylistFromFolder(currentSavedFolder, currentSavedMediaType)
    end

    if controlsDialog and controlsDialog.isShowing() then
        if txtTitleRef then txtTitleRef.setText(File(currentFilePath).getName()) end
        if btnFavoriteRef then
            if isFavorite(currentFilePath) then
                btnFavoriteRef.setText("Remove from Favorite")
            else
                btnFavoriteRef.setText("Add to Favorite")
            end
        end
        return
    end
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local context = service
            local scrollView = ScrollView(context)
            local layout = LinearLayout(context)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(45, 45, 45, 45)

            txtTitleRef = TextView(context)
            txtTitleRef.setText(File(currentFilePath).getName())
            txtTitleRef.setTextSize(18)
            txtTitleRef.setGravity(Gravity.CENTER)
            txtTitleRef.setPadding(0, 10, 0, 15)
            layout.addView(txtTitleRef)

            txtTimeRef = TextView(context)
            txtTimeRef.setText("00:00 / 00:00")
            txtTimeRef.setTextSize(15)
            txtTimeRef.setGravity(Gravity.CENTER)
            txtTimeRef.setPadding(0, 0, 0, 15)
            layout.addView(txtTimeRef)

            if currentSavedMediaType == "video" or currentSavedMediaType == "statuses" then
                local surfaceView = SurfaceView(context)
                surfaceView.setKeepScreenOn(true)
                local lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 550)
                lp.setMargins(0, 10, 0, 15)
                surfaceView.setLayoutParams(lp)
                layout.addView(surfaceView)
                
                local holder = surfaceView.getHolder()
                holder.addCallback(SurfaceHolder.Callback({
                    surfaceCreated = function(h)
                        currentSurfaceHolder = h
                        pcall(function() player.setDisplay(h) end)
                    end,
                    surfaceChanged = function(h, format, width, height) end,
                    surfaceDestroyed = function(h)
                        currentSurfaceHolder = nil
                        pcall(function() player.setDisplay(nil) end)
                    end
                }))
            end

            seekBarRef = SeekBar(context)
            layout.addView(seekBarRef)
            seekBarRef.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener({
                onProgressChanged = function(sBar, progress, fromUser)
                    if fromUser then player.seekTo(math.floor(progress)) saveState() end
                end,
                onStartTrackingTouch = function(sBar) end,
                onStopTrackingTouch = function(sBar) end
            }))

            local spaceBeforeRow = TextView(context)
            spaceBeforeRow.setPadding(0, 0, 0, 10)
            layout.addView(spaceBeforeRow)

            local rowBoostSleep = LinearLayout(context)
            rowBoostSleep.setOrientation(LinearLayout.HORIZONTAL)
            rowBoostSleep.setGravity(Gravity.CENTER)
            
            local hasSleepBtn = (showSleepTimerToggle == "on")
            local hasBoostBtn = (showVolumeBoostToggle == "on")

            if hasSleepBtn then
                btnSleepToggleRef = Button(context)
                btnSleepToggleRef.setText("Sleep Mode: " .. sleepModeActive:upper())
                local lpSleep = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
                btnSleepToggleRef.setLayoutParams(lpSleep)
                btnSleepToggleRef.setOnClickListener(View.OnClickListener({
                    onClick = function(v)
                        if sleepModeActive == "on" then
                            sleepModeActive = "off"
                            btnSleepToggleRef.setText("Sleep Mode: OFF")
                            showToast("Sleep timer off")
                        else
                            sleepModeActive = "on"
                            btnSleepToggleRef.setText("Sleep Mode: ON")
                            if sleepDurationMs and sleepDurationMs > 0 then
                                pcall(function()
                                    _G.sleepTargetPos = player.getCurrentPosition() + sleepDurationMs
                                    lastSleepAudioPath = _G.smart_player_current_path
                                end)
                                startSeekBarUpdate()
                                local totalSecs = math.floor(sleepDurationMs / 1000)
                                showToast("Sleep timer on for " .. totalSecs .. " seconds")
                            else
                                showToast("Sleep timer on")
                            end
                        end
                    end
                }))
                rowBoostSleep.addView(btnSleepToggleRef)
            end

            if hasBoostBtn then
                btnVolumeBoostRef = Button(context)
                local bLabels = {"Normal", "1.5x", "2.0x", "3.0x"}
                btnVolumeBoostRef.setText("Volume Boost: " .. bLabels[currentBoostStage])
                local lpBoost = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
                btnVolumeBoostRef.setLayoutParams(lpBoost)
                btnVolumeBoostRef.setOnClickListener(View.OnClickListener({
                    onClick = function(v)
                        currentBoostStage = currentBoostStage + 1
                        if currentBoostStage > 4 then currentBoostStage = 1 end
                        applyVolumeBoost()
                    end
                }))
                rowBoostSleep.addView(btnVolumeBoostRef)
            end

            if hasSleepBtn or hasBoostBtn then
                layout.addView(rowBoostSleep)
            end

            local spacer = TextView(context)
            spacer.setPadding(0, 0, 0, 20)
            layout.addView(spacer)

            local btnPrev = Button(context)
            btnPrev.setText("Previous")
            btnPrev.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    if currentIndex > 1 then
                        currentIndex = currentIndex - 1
                        lastPlayedPosition = 0
                        playMedia(currentPlaylist[currentIndex], true)
                    else showToast("First file.") end
                end
            }))
            layout.addView(btnPrev)

            local btnRewind = Button(context)
            btnRewind.setText("Rewind <<")
            btnRewind.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    local currentPos = player.getCurrentPosition()
                    local targetPos = math.floor(currentPos - ffRwDuration)
                    if targetPos < 0 then targetPos = 0 end
                    player.seekTo(targetPos)
                    saveState()
                end
            }))
            layout.addView(btnRewind)

            local btnPlayPause = Button(context)
            btnPlayPauseRef = btnPlayPause
            local isPlaying = false
            pcall(function() isPlaying = player.isPlaying() end)
            btnPlayPause.setText(isPlaying and "Pause" or "Play")
            
            btnPlayPause.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    if player and player.isPlaying() then
                        player.pause() 
                        saveState() 
                        btnPlayPause.setText("Play")
                        if backgroundPlay == "on" then showNotification(File(currentFilePath).getName()) end
                    else
                        player.start()
                        applyPlaybackSpeed()
                        btnPlayPause.setText("Pause")
                        if backgroundPlay == "on" then showNotification(File(currentFilePath).getName()) end
                    end
                end
            }))
            layout.addView(btnPlayPause)

            local btnFF = Button(context)
            btnFF.setText("Fast Forward >>")
            btnFF.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    local currentPos = player.getCurrentPosition()
                    local totalDur = player.getDuration()
                    local targetPos = math.floor(currentPos + ffRwDuration)
                    if targetPos > totalDur then targetPos = totalDur - 1000 end
                    player.seekTo(targetPos)
                    saveState()
                end
            }))
            layout.addView(btnFF)

            local btnNext = Button(context)
            btnNext.setText("Next")
            btnNext.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    if currentIndex < #currentPlaylist then
                        currentIndex = currentIndex + 1
                        lastPlayedPosition = 0
                        playMedia(currentPlaylist[currentIndex], true)
                    else showToast("Last file.") end
                end
            }))
            layout.addView(btnNext)

            local btnMore = Button(context)
            btnMore.setText("More Options")
            btnMore.setOnClickListener(View.OnClickListener({
                onClick = function(v) showMoreOptions() end
            }))
            layout.addView(btnMore)

            local btnFavorite = Button(context)
            btnFavoriteRef = btnFavorite
            local function updateFavoriteButtonText()
                if isFavorite(currentFilePath) then
                    btnFavorite.setText("Remove from Favorite")
                else
                    btnFavorite.setText("Add to Favorite")
                end
            end
            updateFavoriteButtonText()
            btnFavorite.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    toggleFavorite(currentFilePath)
                    updateFavoriteButtonText()
                end
            }))
            layout.addView(btnFavorite)

            local btnFolder = Button(context)
            btnFolder.setText("Choose Your Folder")
            btnFolder.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    saveState()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                    isMultiSelectActive = false
                    selectedItemsMap = {}
                    showStorageMenu()
                end
            }))
            layout.addView(btnFolder)

            local btnMinimize = Button(context)
            btnMinimize.setText("Minimize Player")
            btnMinimize.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    saveState()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                    _G.smart_player_minimized = true
                    if backgroundPlay == "on" then
                        showNotification(File(currentFilePath).getName())
                    else
                        pcall(function() 
                            if player.isPlaying() then player.pause() end 
                            lastPlayedPosition = player.getCurrentPosition() 
                        end)
                        _G.smart_player_is_prepared = true
                        saveState() cancelNotification()
                    end
                end
            }))
            layout.addView(btnMinimize)

            local btnExit = Button(context)
            btnExit.setText("Exit")
            btnExit.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    pcall(function() player.reset() end)
                    currentFilePath = ""
                    lastPlayedPosition = 0
                    currentSavedFolder = "" 
                    _G.smart_player_is_prepared = false
                    _G.smart_player_current_path = ""
                    _G.smart_player_minimized = false
                    saveState()
                    cancelNotification()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                end
            }))
            layout.addView(btnExit)

            scrollView.addView(layout)
            local builder = AlertDialog.Builder(context)
            builder.setView(scrollView)
            controlsDialog = builder.create()
            controlsDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            
            if currentSavedMediaType == "video" or currentSavedMediaType == "statuses" then
                controlsDialog.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            end
            
            import "android.view.KeyEvent"
            controlsDialog.setOnKeyListener(DialogInterface.OnKeyListener({
                onKey = function(dialog, keyCode, event)
                    if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                        controlsDialog.dismiss()
                        controlsDialog = nil
                        saveState()
                        
                        if currentSavedFolder and currentSavedFolder ~= "" then
                            isMultiSelectActive = false
                            selectedItemsMap = {}
                            renderMediaList(currentSavedFolder, currentSavedMediaType)
                        else
                            _G.smart_player_minimized = true
                            if backgroundPlay == "on" then
                                showNotification(File(currentFilePath).getName())
                            else
                                pcall(function() 
                                    if player.isPlaying() then player.pause() end 
                                    lastPlayedPosition = player.getCurrentPosition() 
                                end)
                                _G.smart_player_is_prepared = true
                                saveState() cancelNotification()
                            end
                        end
                        return true
                    end
                    return false
                end
            }))
            
            controlsDialog.show()
            startSeekBarUpdate()
        end
    }))
end

-- 9. Optimized SeekBar & Text Sync Thread
local isUpdating = false
startSeekBarUpdate = function()
    if isUpdating then return end
    isUpdating = true
    local handler = Handler(Looper.getMainLooper())
    local updateRunnable
    local cycleCount = 0
    updateRunnable = Runnable({
        run = function()
            if player and ((controlsDialog and controlsDialog.isShowing()) or sleepModeActive == "on") then
                local isPlaying = false
                local current = 0
                local total = 0
                
                local ok = pcall(function()
                    isPlaying = player.isPlaying()
                    current = player.getCurrentPosition()
                    total = player.getDuration()
                end)

                if sleepModeActive == "on" then
                    if not _G.sleepTargetPos or _G.smart_player_current_path ~= lastSleepAudioPath then
                        _G.sleepTargetPos = current + sleepDurationMs
                        lastSleepAudioPath = _G.smart_player_current_path
                    end
                    
                    if current >= _G.sleepTargetPos then
                        sleepModeActive = "off"
                        _G.sleepTargetPos = nil
                        pcall(function()
                            if player and player.isPlaying() then player.pause() end
                            if player then lastPlayedPosition = player.getCurrentPosition() end
                            _G.smart_player_is_prepared = true
                            _G.smart_player_minimized = true
                            saveState()
                            cancelNotification()
                            if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                        end)
                    end
                else
                    _G.sleepTargetPos = nil
                    lastSleepAudioPath = ""
                end

                if controlsDialog and controlsDialog.isShowing() then
                    if ok and total > 0 then
                        if btnPlayPauseRef then
                            local expectedText = isPlaying and "Pause" or "Play"
                            if tostring(btnPlayPauseRef.getText()) ~= expectedText then
                                btnPlayPauseRef.setText(expectedText)
                            end
                        end
                        if btnSleepToggleRef then
                            local expectedSleepText = "Sleep Mode: " .. sleepModeActive:upper()
                            if tostring(btnSleepToggleRef.getText()) ~= expectedSleepText then
                                btnSleepToggleRef.setText(expectedSleepText)
                            end
                        end
                        seekBarRef.setMax(total)
                        seekBarRef.setProgress(current)
                        
                        if isPlaying then
                            lastPlayedPosition = current
                        end
                        
                        local curSec = math.floor(current / 1000)
                        local curMin = math.floor(curSec / 60)
                        curSec = curSec % 60
                        
                        local totSec = math.floor(total / 1000)
                        local totMin = math.floor(totSec / 60)
                        totSec = totSec % 60
                        
                        txtTimeRef.setText(string.format("%02d:%02d / %02d:%02d", curMin, curSec, totMin, totSec))
                        cycleCount = cycleCount + 1
                        if cycleCount >= 5 then cycleCount = 0 saveState() end
                    else
                        if btnPlayPauseRef then
                            local expectedText = isPlaying and "Pause" or "Play"
                            if tostring(btnPlayPauseRef.getText()) ~= expectedText then
                                btnPlayPauseRef.setText(expectedText)
                            end
                        end
                        txtTimeRef.setText("00:00 / 00:00")
                    end
                end
                handler.postDelayed(updateRunnable, 1000)
            else isUpdating = false end
        end
    })
    handler.post(updateRunnable)
end

-- 10. More Options Menu
showMoreOptions = function()
    local file = File(currentFilePath)
    local options = {"Delete", "Share", "Playback Speed", "Rename"}
    if currentSavedMediaType == "statuses" then
        table.insert(options, 1, "Save to Gallery")
    end
    local builder = AlertDialog.Builder(service)
    builder.setItems(options, function(dialog, which)
        local idx = which + 1
        local selectedOpt = options[idx]
        
        if selectedOpt == "Save to Gallery" then
            saveStatusToGallery(currentFilePath)
        elseif selectedOpt == "Delete" then
            local confDel = AlertDialog.Builder(service)
            confDel.setTitle("Delete File?")
            confDel.setMessage("Are you sure you want to permanently delete this file?")
            confDel.setPositiveButton("Delete", function()
                local f = File(currentFilePath)
                if f.delete() then
                    showToast("Deleted successfully.")
                    player.reset()
                    cancelNotification()
                    _G.smart_player_is_prepared = false
                    _G.smart_player_current_path = ""
                    currentFilePath = ""
                    lastPlayedPosition = 0
                    saveState()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                    renderMediaList(currentSavedFolder, currentSavedMediaType)
                else
                    showToast("Failed to delete.")
                end
            end)
            confDel.setNegativeButton("Cancel", nil)
            showDialogSafe(confDel)
        elseif selectedOpt == "Share" then
            if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
            
            local originalPackage = ""
            pcall(function()
                local root = service.getRootInActiveWindow()
                if root then originalPackage = tostring(root.getPackageName()) end
            end)
            if originalPackage == "" or originalPackage == "android" or originalPackage == "com.android.intentresolver" then
                originalPackage = "com.android.launcher3"
            end
            
            pcall(function()
                local context = service
                setStrictModeAllowFileUri()
                local shareUri = Uri.fromFile(File(currentFilePath))
                local intent = Intent(Intent.ACTION_SEND)
                intent.setType("*/*")
                intent.putExtra(Intent.EXTRA_STREAM, shareUri)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                local chooser = Intent.createChooser(intent, "Share File")
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
            end)
            
            local monitorHandler = Handler(Looper.getMainLooper())
            local monitorRunnable
            local loopCount = 0
            local hasLeftApp = false
            
            monitorRunnable = Runnable({
                run = function()
                    loopCount = loopCount + 1
                    local currentPkg = ""
                    pcall(function()
                        local root = service.getRootInActiveWindow()
                        if root then currentPkg = tostring(root.getPackageName()) end
                    end)
                    local currentPkgLower = currentPkg:lower()
                    
                    if currentPkg ~= "" and currentPkg ~= originalPackage and not currentPkgLower:find("launcher") and not currentPkgLower:find("home") then
                        hasLeftApp = true
                    end
                    
                    if hasLeftApp and (currentPkg == originalPackage or currentPkgLower:find("launcher") or currentPkgLower:find("home")) then
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function() 
                                showPlayerControls()
                            end
                        }))
                    elseif not hasLeftApp and loopCount > 10 then
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function()
                                showPlayerControls()
                            end
                        }))
                    elseif loopCount < 120 then
                        monitorHandler.postDelayed(monitorRunnable, 1000)
                    end
                end
            })
            monitorHandler.postDelayed(monitorRunnable, 1000)
            
        elseif selectedOpt == "Playback Speed" then
            showPlaybackSpeedMenu("player")
        elseif selectedOpt == "Rename" then
            Handler(Looper.getMainLooper()).post(Runnable({
                run = function()
                    local f = File(currentFilePath)
                    local oldFullName = f.getName()
                    
                    -- Extract filename and extension accurately
                    local displayName = oldFullName
                    local extension = ""
                    local dotIndex = oldFullName:match("^.*()%.")
                    if dotIndex then
                        displayName = oldFullName:sub(1, dotIndex - 1)
                        extension = oldFullName:sub(dotIndex) -- includes the dot
                    end
                    
                    local inputField = EditText(service)
                    inputField.setText(displayName) -- Show clean name without extension
                    inputField.setSelectAllOnFocus(true)
                    inputField.setOnClickListener(View.OnClickListener({
                        onClick = function(v)
                            inputField.setText("")
                        end
                    }))
                    
                    local renBuilder = AlertDialog.Builder(service)
                    renBuilder.setTitle("Rename File")
                    renBuilder.setView(inputField)
                    renBuilder.setPositiveButton("Rename", function()
                        local userInput = tostring(inputField.getText())
                        if userInput ~= "" and userInput ~= displayName then
                            -- Automatically attach the cached hidden extension
                            local newFullName = userInput .. extension
                            local parent = f.getParentFile()
                            local newFile = File(parent, newFullName)
                            if f.renameTo(newFile) then
                                showToast("Renamed successfully.")
                                currentFilePath = newFile.getAbsolutePath()
                                _G.smart_player_current_path = currentFilePath
                                saveState()
                                
                                -- Refresh the dynamic playlist in memory to reflect new file name
                                if currentSavedFolder and currentSavedFolder ~= "" then
                                    rebuildPlaylistFromFolder(currentSavedFolder, currentSavedMediaType)
                                end
                                
                                if txtTitleRef then txtTitleRef.setText(newFullName) end
                            else
                                showToast("Rename failed.")
                            end
                        end
                    end)
                    renBuilder.setNegativeButton("Cancel", nil)
                    showDialogSafe(renBuilder)
                end
            }))
        end
    end)
    builder.setNegativeButton("Cancel", nil)
    showDialogSafe(builder)
end

-- Initialization Engine Execution
loadState()
loadFavorites()

if currentFilePath and currentFilePath ~= "" and _G.smart_player_is_prepared and _G.smart_player_minimized then
    showPlayerControls()
else
    showMainMenu()
end