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

-- Configuration File Path
local configPath = "/sdcard/smart_player_config.txt"
local NOTIF_ID = 9923
local CHANNEL_ID = "smart_player_channel"
local mediaReceiver = nil

-- UI References
local controlsDialog = nil
local txtTitleRef = nil
local txtTimeRef = nil
local seekBarRef = nil
local btnVolumeBoostRef = nil
local btnSleepToggleRef = nil
local btnPlayPauseRef = nil

local function showToast(text)
    service.speak(text)
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

-- Multi-Select Statistics Tracker (Optimized with cached pre-fetched sizes to avoid freezes)
local function getSelectedStats(filteredList, selectedMap)
    local count = 0
    local totalSize = 0
    for _, item in ipairs(filteredList) do
        if selectedMap[item.path] then
            count = count + 1
            if item.size and item.size > 0 then
                totalSize = totalSize + item.size
            else
                local f = File(item.path)
                if item.isDir then
                    pcall(function() totalSize = totalSize + getFolderSizeRecursive(f) end)
                else
                    pcall(function() totalSize = totalSize + f.length() end)
                end
            end
        end
    end
    return count, formatSize(totalSize)
end

-- Persistent Storage: Save State
local function saveState()
    pcall(function()
        local f = io.open(configPath, "w")
        if f then
            f:write((currentSavedFolder or "/storage/emulated/0") .. "\n")
            f:write((currentSavedMediaType or "audio") .. "\n")
            f:write((currentFilePath or "") .. "\n")
            local pos = 0
            if player and currentFilePath ~= "" and _G.smart_media_player_is_prepared then 
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

-- WhatsApp Status Helpers (Save, Share & Open External View Engine)
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

-- SAVE to Gallery using MediaStore (Android 10+ compatible) with correct byte array
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
            -- fallback to old method (if MediaStore fails)
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

-- Recursive Scanner Engine (Optimized with size projection to cache file sizes instantly)
local function getAllRecursiveFiles(rootPath, mediaType)
    local files = {}
    local resolver = service.getContentResolver()
    local uri = MediaStore.Files.getContentUri("external")
    local projection = {MediaStore.Files.FileColumns.DATA, MediaStore.Files.FileColumns.DATE_MODIFIED, MediaStore.Files.FileColumns.SIZE}
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
                    local size = 0
                    pcall(function() size = cursor.getLong(cursor.getColumnIndex(MediaStore.Files.FileColumns.SIZE)) end)
                    table.insert(files, {name = name, path = data, isDir = false, time = time, size = size})
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
                            local size = 0
                            pcall(function() size = f.length() end)
                            table.insert(files, {name = name, path = f.getAbsolutePath(), isDir = false, time = time, size = size})
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

local showMainMenu, showStorageMenu, showWhatsAppMenu, showMediaTypeMenu, showBrowseModeMenu, renderMediaList, playMedia, showPlayerControls, showMoreOptions, startSeekBarUpdate, showSettingsMenu, showAudioSettingsMenu, showSleepTimerDialog, showPlaybackSpeedMenu, showStatusSettingsMenu

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
    local items = {
        "Audio Settings",
        "Status Settings",
        "Show WhatsApp Media in Main Menu: " .. showWhatsAppMediaToggle:upper(),
        "Multi-Select Mode Setting: " .. multiSelectSetting:upper()
    }
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Settings")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
            showAudioSettingsMenu()
        elseif which == 1 then
            showStatusSettingsMenu()
        elseif which == 2 then
            if showWhatsAppMediaToggle == "on" then
                showWhatsAppMediaToggle = "off"
            else
                showWhatsAppMediaToggle = "on"
            end
            saveState()
            showToast("WhatsApp Media Visibility: " .. showWhatsAppMediaToggle:upper())
            showSettingsMenu()
        elseif which == 3 then
            if multiSelectSetting == "on" then
                multiSelectSetting = "off"
            else
                multiSelectSetting = "on"
            end
            saveState()
            showToast("Multi-Select Mode: " .. multiSelectSetting:upper())
            showSettingsMenu()
        end
    end)
    builder.setNegativeButton("Back", function() showMainMenu() end)
    showDialogSafe(builder, function() showMainMenu() end)
end

-- Status Settings Sub-Menu
showStatusSettingsMenu = function()
    local items = {
        "Show Images in Status Folder: " .. showStatusImages:upper(),
        "Show Videos in Status Folder: " .. showStatusVideos:upper()
    }
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Status Settings")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
            showStatusImages = (showStatusImages == "on") and "off" or "on"
            showToast("Images in Status: " .. showStatusImages:upper())
        elseif which == 1 then
            showStatusVideos = (showStatusVideos == "on") and "off" or "on"
            showToast("Videos in Status: " .. showStatusVideos:upper())
        end
        saveState()
        showStatusSettingsMenu()
    end)
    builder.setNegativeButton("Back", function() showSettingsMenu() end)
    showDialogSafe(builder, function() showSettingsMenu() end)
end

-- Audio Settings Sub-Menu
showAudioSettingsMenu = function()
    local currentSec = math.floor(ffRwDuration / 1000)
    local items = {
        "Fast Forward and Rewind Changing Time: " .. currentSec .. " Seconds",
        "Background Playback: " .. backgroundPlay:upper(),
        "Auto Play Next File: " .. autoPlay:upper(),
        "Playback Speed: " .. currentPlaybackSpeed .. "x",
        "Set Sleep Timer Duration",
        "Show Volume Boost on Player: " .. showVolumeBoostToggle:upper(),
        "Show Sleep Timer on Player: " .. showSleepTimerToggle:upper()
    }
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Audio Settings")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
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
                onItemClick = function(parent, view, position, id)
                    local idx = position + 1
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
                onItemLongClick = function(parent, view, position, id)
                    local idx = position + 1
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
            
        elseif which == 1 then
            if backgroundPlay == "on" then backgroundPlay = "off" cancelNotification() else backgroundPlay = "on" end
            saveState()
            showToast("Background playback " .. backgroundPlay)
            showAudioSettingsMenu()
        elseif which == 2 then
            if autoPlay == "on" then autoPlay = "off" else autoPlay = "on" end
            saveState()
            showToast("Auto Play " .. autoPlay)
            showAudioSettingsMenu()
        elseif which == 3 then
            showPlaybackSpeedMenu("settings")
        elseif which == 4 then
            showSleepTimerDialog()
        elseif which == 5 then
            showVolumeBoostToggle = (showVolumeBoostToggle == "on") and "off" or "on"
            saveState()
            showToast("Volume Boost visibility updated")
            showAudioSettingsMenu()
        elseif which == 6 then
            showSleepTimerToggle = (showSleepTimerToggle == "on") and "off" or "on"
            saveState()
            showToast("Sleep Timer visibility updated")
            showAudioSettingsMenu()
        end
    end)
    builder.setNegativeButton("Back", function() showSettingsMenu() end)
    showDialogSafe(builder, function() showSettingsMenu() end)
end

-- Playback Speed Menu
showPlaybackSpeedMenu = function(parentMenu)
    local availableSpeeds = {0.5, 0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 2.75, 3.0, 3.5, 3.75, 4.0}
    local items = {}
    for _, v in ipairs(availableSpeeds) do
        if math.abs(currentPlaybackSpeed - v) < 0.01 then
            table.insert(items, string.format("%.2fx (Active)", v))
        else
            table.insert(items, string.format("%.2fx", v))
        end
    end
    
    local speedBuilder = AlertDialog.Builder(service)
    speedBuilder.setTitle("Playback Speed")
    speedBuilder.setItems(items, function(d, w)
        currentPlaybackSpeed = availableSpeeds[w + 1]
        applyPlaybackSpeed()
        saveState()
        showToast("Playback speed changed: " .. currentPlaybackSpeed .. "x")
        if parentMenu == "settings" then showAudioSettingsMenu() else showMoreOptions() end
    end)
    local backFunc = function()
        if parentMenu == "settings" then showAudioSettingsMenu() else showMoreOptions() end
    end
    speedBuilder.setNegativeButton("Back", backFunc)
    showDialogSafe(speedBuilder, backFunc)
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
                        if sleepRunnable then sleepHandler.removeCallbacks(sleepRunnable) end
                        sleepRunnable = Runnable({
                            run = function()
                                pcall(function()
                                    if player and player.isPlaying() then player.pause() end
                                    if player then lastPlayedPosition = player.getCurrentPosition() end
                                    _G.smart_player_is_prepared = true
                                    _G.smart_player_minimized = false
                                    saveState()
                                    cancelNotification()
                                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                                end)
                            end
                        })
                        sleepHandler.postDelayed(sleepRunnable, sleepDurationMs)
                        showToast("Sleep mode activated successfully.")
                    else
                        showToast("Invalid time duration entered.")
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
            selectedStorage = getExternalSdCardPath()
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
    local items = {"All Files", "Browse Folders"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Select Mode")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
            currentBrowseMode = "all_files"
        else
            currentBrowseMode = "folders"
        end
        currentSearchQuery = ""
        saveState()
        renderMediaList(storagePath, mediaType)
    end)
    builder.setNegativeButton("Back", function() showMediaTypeMenu(storagePath) end)
    showDialogSafe(builder, function() showMediaTypeMenu(storagePath) end)
end

-- 6. Unified Media List Engine with In-Place Update & Fixed Layout Width Actions
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
                        local size = 0
                        if not isDir then pcall(function() size = f.length() end) end
                        if isDir then
                            if currentPath == "/storage" or hasMedia(f, mediaType, 1) then
                                table.insert(rawItems, {name = name, path = f.getAbsolutePath(), isDir = true, time = time, size = 0})
                            end
                        else
                            if matchesFormat(name, mediaType) then
                                table.insert(rawItems, {name = name, path = f.getAbsolutePath(), isDir = false, time = time, size = size})
                            end
                        end
                    end
                end
            end
        else
            local dirs, files = getMediaStoreDirsAndFiles(currentPath, mediaType)
            for _, d in ipairs(dirs) do
                if d.name ~= "emulated" and d.name ~= "self" and d.name ~= "sdcard0" and d.name ~= "0" then
                    local time = 0
                    pcall(function() time = File(d.path).lastModified() end)
                    table.insert(rawItems, {name = d.name, path = d.path, isDir = true, time = time, size = 0})
                end
            end
            for _, f in ipairs(files) do
                local time = 0
                local size = 0
                pcall(function() 
                    local fileObj = File(f.path)
                    time = fileObj.lastModified() 
                    size = fileObj.length()
                end)
                table.insert(rawItems, {name = f.name, path = f.path, isDir = false, time = time, size = size})
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
        showToast("No files found.")
        showMainMenu()
        return
    end

    -- Create ArrayList for dynamic in-place updates (Fixes screen reader focus loss bug)
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

    -- In-place updating function that keeps the screen reader focused correctly
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
                if selectedItemsMap[item.path] then prefix = "[✓] " else prefix = "[ ] " end
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
            
            -- Dynamic Visibility Check: Hide share button if any folder is selected
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

    -- Setup Bottom Actions row layout for multi-select (Fixed Width to avoid pushing Delete off-screen)
    if isMultiSelectActive then
        bottomBar = LinearLayout(service)
        bottomBar.setOrientation(LinearLayout.HORIZONTAL)
        bottomBar.setGravity(Gravity.RIGHT)
        local barParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        bottomBar.setLayoutParams(barParams)

        local wrapParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        local weightParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)

        btnCancel = Button(service)
        btnCancel.setText("Cancel")
        btnCancel.setLayoutParams(wrapParams)
        btnCancel.setOnClickListener(View.OnClickListener({
            onClick = function(v)
                isMultiSelectActive = false
                selectedItemsMap = {}
                mediaListDialog.dismiss()
                renderMediaList(currentPath, mediaType)
            end
        }))

        btnShare = Button(service)
        btnShare.setLayoutParams(weightParams)
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
                
                -- Detect current package for return app monitor loop
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
                
                -- App Monitor Loop for Multiple Sharing safely without changing original logic
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
        btnDelete.setLayoutParams(weightParams)
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
                        
                        -- Non-blocking Thread Execution to avoid phone hang
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
    end

    updateListAndButtons()

    local builder = AlertDialog.Builder(service)
    builder.setTitle(currentBrowseMode == "all_files" and "All Files" or "Browse Folders")
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
                end
            elseif action.type == "media" then
                local selectedMedia = action.data
                if isMultiSelectActive then
                    selectedItemsMap[selectedMedia.path] = not selectedItemsMap[selectedMedia.path]
                    if selectedItemsMap[selectedMedia.path] then
                        service.speak("Checked")
                    else
                        service.speak("Not checked")
                    end
                    updateListAndButtons() 
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
                        mediaListDialog.dismiss()
                        renderMediaList(currentPath, mediaType)
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
            mediaListDialog.dismiss()
            renderMediaList(currentPath, mediaType)
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
            
            if currentBrowseMode == "all_files" then
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
    if controlsDialog and controlsDialog.isShowing() then
        txtTitleRef.setText(File(currentFilePath).getName())
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
                        pcall(function() player.setDisplay(h) end)
                    end,
                    surfaceChanged = function(h, format, width, height) end,
                    surfaceDestroyed = function(h)
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
                            if sleepRunnable then sleepHandler.removeCallbacks(sleepRunnable) end
                            btnSleepToggleRef.setText("Sleep Mode: OFF")
                            showToast("Sleep Mode OFF")
                        else
                            sleepModeActive = "on"
                            btnSleepToggleRef.setText("Sleep Mode: ON")
                            if sleepDurationMs and sleepDurationMs > 0 then
                                if sleepRunnable then sleepHandler.removeCallbacks(sleepRunnable) end
                                sleepRunnable = Runnable({
                                    run = function()
                                        pcall(function()
                                            if player and player.isPlaying() then player.pause() end
                                            if player then lastPlayedPosition = player.getCurrentPosition() end
                                            _G.smart_player_is_prepared = true
                                            _G.smart_player_minimized = false
                                            saveState()
                                            cancelNotification()
                                            if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                                        end)
                                    end
                                })
                                sleepHandler.postDelayed(sleepRunnable, sleepDurationMs)
                                showToast("Sleep Mode ON")
                            else
                                showToast("Sleep Mode ON")
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
                        playMedia(currentPlaylist[currentIndex])
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
                        playMedia(currentPlaylist[currentIndex])
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
            if controlsDialog and controlsDialog.isShowing() and player then
                local isPlaying = false
                local current = 0
                local total = 0
                
                local ok = pcall(function()
                    isPlaying = player.isPlaying()
                    current = player.getCurrentPosition()
                    total = player.getDuration()
                end)

                if ok and total > 0 then
                    if btnPlayPauseRef then
                        local expectedText = isPlaying and "Pause" or "Play"
                        if tostring(btnPlayPauseRef.getText()) ~= expectedText then
                            btnPlayPauseRef.setText(expectedText)
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
        if currentSavedMediaType == "statuses" then
            if idx == 1 then
                saveStatusToGallery(currentFilePath)
                return
            else
                idx = idx - 1
            end
        end
        if idx == 1 then
            if file.isDirectory() then showToast("Cannot delete folders here.") return end
            local confirm = AlertDialog.Builder(service)
            confirm.setTitle("Delete File?")
            confirm.setMessage("Are you sure you want to permanently delete this file?")
            confirm.setPositiveButton("Yes", function()
                player.reset() cancelNotification()
                _G.smart_player_is_prepared = false
                _G.smart_player_current_path = ""
                
                Thread(Runnable({
                    run = function()
                        local isDeleted = file.delete()
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function()
                                if isDeleted then
                                    showToast("File deleted successfully.")
                                    currentFilePath = "" lastPlayedPosition = 0 saveState()
                                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                                    renderMediaList(currentSavedFolder, currentSavedMediaType)
                                else showToast("Failed to delete file.") end
                            end
                        }))
                    end
                })).start()
            end)
            confirm.setNegativeButton("Cancel", nil)
            showDialogSafe(confirm, function() showMoreOptions() end)
        elseif idx == 2 then
            saveState()
            local originalPackage = ""
            pcall(function()
                local root = service.getRootInActiveWindow()
                if root then originalPackage = tostring(root.getPackageName()) end
            end)
            if originalPackage == "" or originalPackage == "android" or originalPackage == "com.android.intentresolver" then
                originalPackage = "com.android.launcher3"
            end
            if dialog then dialog.dismiss() end
            if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end

            pcall(function()
                local context = service
                setStrictModeAllowFileUri()
                local shareUri = Uri.fromFile(file)
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
                                if currentFilePath and currentFilePath ~= "" then
                                    showPlayerControls()
                                else
                                    renderMediaList(currentSavedFolder, currentSavedMediaType)
                                end
                            end
                        }))
                    elseif not hasLeftApp and loopCount > 10 then
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function()
                                if currentFilePath and currentFilePath ~= "" then
                                    showPlayerControls()
                                else
                                    renderMediaList(currentSavedFolder, currentSavedMediaType)
                                end
                            end
                        }))
                    elseif loopCount < 120 then
                        monitorHandler.postDelayed(monitorRunnable, 1000)
                    end
                end
            })
            monitorHandler.postDelayed(monitorRunnable, 1000)
        elseif idx == 3 then
            showPlaybackSpeedMenu("player")
        elseif idx == 4 then
            Handler(Looper.getMainLooper()).post(Runnable({
                run = function()
                    local inputField = EditText(service)
                    inputField.setText(file.getName())
                    local renameDialog = AlertDialog.Builder(service)
                    renameDialog.setTitle("Rename File")
                    renameDialog.setView(inputField)
                    renameDialog.setPositiveButton("Rename", function()
                        local newName = tostring(inputField.getText())
                        if newName ~= "" then
                            local parent = file.getParentFile()
                            local newFile = File(parent, newName)
                            if file.renameTo(newFile) then
                                showToast("Renamed successfully.")
                                currentFilePath = newFile.getAbsolutePath()
                                saveState()
                                showPlayerControls()
                            else
                                showToast("Failed to rename.")
                                showPlayerControls()
                            end
                        end
                    end)
                    renameDialog.setNegativeButton("Cancel", function() showPlayerControls() end)
                    showDialogSafe(renameDialog, function() showPlayerControls() end)
                end
            }))
        end
    end)
    builder.setNegativeButton("Cancel", function() showPlayerControls() end)
    showDialogSafe(builder, function() showPlayerControls() end)
end

-- Initialize Engine Initialization State Loops
loadState()
showMainMenu()
