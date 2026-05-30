package com.example.see_the_world

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.see_the_world/keys"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDirectionsApiKey" -> {
                        val resId = resources.getIdentifier(
                            "google_directions_api_key",
                            "string",
                            packageName
                        )
                        if (resId != 0) {
                            result.success(resources.getString(resId))
                        } else {
                            result.success("")
                        }
                    }
                    "getPlacesApiKey" -> {
                        val uiKitId = resources.getIdentifier(
                            "google_places_ui_kit_api_key",
                            "string",
                            packageName
                        )
                        val fallbackId = resources.getIdentifier(
                            "google_places_api_key",
                            "string",
                            packageName
                        )
                        val resolvedId = if (uiKitId != 0) uiKitId else fallbackId
                        if (resolvedId != 0) {
                            result.success(getString(resolvedId))
                        } else {
                            result.success("")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
