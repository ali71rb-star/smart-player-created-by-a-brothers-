require "import"
import "android.media.MediaPlayer"
local soundPath = "/storage/emulated/0/bdspeech_recognition_success.mp3"
local mediaPlayer = MediaPlayer()
mediaPlayer.setOnPreparedListener{
    onPrepared = function(mp)
        mp.start()
    end
}
mediaPlayer.setOnCompletionListener{
    onCompletion = function(mp)
        mp.release()
    end
}
mediaPlayer.setOnErrorListener{
    onError = function(mp, what, extra)
        mp.release()
        return true
    end
}
local success, err = pcall(function()
    mediaPlayer.setDataSource(soundPath)
    mediaPlayer.prepareAsync()
end)
if not success then
    mediaPlayer.release()
end
if service.plugin("Smart player created by a brothers", node) then
    return true
end