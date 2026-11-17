package com.example.spiral_pass_play

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var lobbyMusic: LobbyMusicPlayer? = null

    override fun onResume() {
        super.onResume()
        lobbyMusic?.setForeground(true)
    }

    override fun onPause() {
        lobbyMusic?.setForeground(false)
        super.onPause()
    }

    override fun onDestroy() {
        lobbyMusic?.dispose()
        lobbyMusic = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val assetKey = io.flutter.FlutterInjector.instance().flutterLoader()
            .getLookupKeyForAsset("assets/audio/lobby.mp3")
        lobbyMusic = LobbyMusicPlayer(this, assetKey)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spiral_survival/lobby_music")
            .setMethodCallHandler { call, result ->
                if (call.method != "setActive") {
                    result.notImplemented()
                } else {
                    val active = call.arguments as? Boolean
                    if (active == null) {
                        result.error("invalid-argument", "Expected an active flag.", null)
                    } else {
                        try {
                            lobbyMusic?.setActive(active)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("audio-playback", "Could not play lobby music.", null)
                        }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spiral_quest/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("invalid-argument", "Expected an enabled flag.", null)
                        } else {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
