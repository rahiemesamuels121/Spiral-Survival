package com.example.spiral_pass_play

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.util.Log

/** A single looping, bundled soundtrack, released whenever the lobby is left. */
@Suppress("DEPRECATION")
class LobbyMusicPlayer(private val context: Context, private val assetKey: String) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var player: MediaPlayer? = null
    private var prepared = false
    private var requested = false
    private var foreground = true
    private var hasFocus = false
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        hasFocus = change == AudioManager.AUDIOFOCUS_GAIN
        if (hasFocus && requested && foreground && prepared) {
            player?.start()
        } else if (prepared) {
            player?.pause()
        }
    }

    fun setActive(active: Boolean) {
        requested = active
        if (!active) { releasePlayer(); return }
        if (!foreground) return
        if (player != null) { startPrepared(); return }
        val current = MediaPlayer()
        player = current
        try {
            current.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            context.assets.openFd(assetKey).use { asset ->
                current.setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
            }
            current.isLooping = true
            current.setVolume(0.45f, 0.45f)
            current.setOnPreparedListener {
                if (player === it) { prepared = true; startPrepared() }
            }
            current.setOnErrorListener { failed, what, extra ->
                Log.w("LobbyMusic", "Playback error: $what/$extra")
                if (player === failed) releasePlayer()
                true
            }
            current.prepareAsync()
        } catch (error: Exception) {
            releasePlayer()
            throw error
        }
    }

    private fun startPrepared() {
        if (!prepared || !requested || !foreground) return
        if (!hasFocus) {
            hasFocus = audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        if (hasFocus) player?.start()
    }

    fun setForeground(active: Boolean) {
        foreground = active
        if (active && requested) setActive(true)
        else if (!active) {
            if (prepared) player?.pause()
            audio.abandonAudioFocus(focusListener)
            hasFocus = false
        }
    }

    private fun releasePlayer() {
        val old = player
        player = null
        prepared = false
        old?.setOnPreparedListener(null)
        old?.setOnErrorListener(null)
        old?.release()
        audio.abandonAudioFocus(focusListener)
        hasFocus = false
    }

    fun dispose() { requested = false; releasePlayer() }
}
