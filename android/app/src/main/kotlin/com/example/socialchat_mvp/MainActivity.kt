package com.example.socialchat_mvp

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "remdy/share_in"
    private var methodChannel: MethodChannel? = null
    private var pendingShare: HashMap<String, Any?>? = null
    private var lastDeliveredIntentId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    val share = pendingShare
                    pendingShare = null
                    result.success(share)
                }
                "peekPendingShare" -> {
                    // Não consome: Dart acusa via ackPendingShare após UI.
                    result.success(pendingShare)
                }
                "ackPendingShare" -> {
                    val intentId = call.argument<String>("intentId")
                    if (intentId != null && pendingShare?.get("intentId") == intentId) {
                        pendingShare = null
                    }
                    result.success(null)
                }
                "appendTrace" -> {
                    // Opcional (debug). Aceitar para não gerar MissingPluginException.
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cold start: só cacheia — Flutter puxa via getInitialShare (evita race).
        handleShareIntent(intent, pushImmediately = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // App já vivo: empurra via onShare.
        handleShareIntent(intent, pushImmediately = true)
    }

    private fun handleShareIntent(intent: Intent?, pushImmediately: Boolean) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND) return

        val type = intent.type ?: ""
        val isText = type.startsWith("text/") || type.isEmpty()
        if (!isText) return

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        if (text.isEmpty() && subject.isEmpty()) return

        val streamUri = readStreamUri(intent)
        if (streamUri != null && text.isEmpty()) return

        val intentId = UUID.randomUUID().toString()
        if (intentId == lastDeliveredIntentId) return

        val payload = HashMap<String, Any?>()
        payload["intentId"] = intentId
        payload["text"] = text.ifEmpty { subject }
        payload["subject"] = subject
        payload["mimeType"] = type.ifEmpty { "text/plain" }
        payload["source"] = "android"
        payload["receivedAtMs"] = System.currentTimeMillis()
        if (streamUri != null) {
            payload["uri"] = streamUri.toString()
        }

        lastDeliveredIntentId = intentId

        // Limpa extras para não reabrir no recreate.
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.removeExtra(Intent.EXTRA_SUBJECT)
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.action = Intent.ACTION_MAIN

        val channel = methodChannel
        if (pushImmediately && channel != null) {
            pendingShare = null
            channel.invokeMethod("onShare", payload)
        } else {
            pendingShare = payload
        }
    }

    private fun readStreamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }
}
