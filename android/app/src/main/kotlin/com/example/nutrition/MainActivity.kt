package com.example.nutrition

import android.content.Intent // 需新增
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.nutrition/widget"
    private var startRoute: String? = null // 暫存路徑

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 檢查啟動時的 Intent
        handleIntent(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialRoute") {
                // 傳送路徑給 Flutter 並清空，避免重複跳轉
                val route = startRoute
                startRoute = null
                result.success(route)
            } else {
                result.notImplemented()
            }
        }
    }

    // 當 App 已經在背景，點擊小工具會觸發這個方法
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
        // 通知 Flutter 路徑更新（如果需要即時跳轉）
        flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, CHANNEL).invokeMethod("onUpdateRoute", startRoute)
        }
    }

    private fun handleIntent(intent: Intent?) {
        startRoute = intent?.getStringExtra("route")
    }
}