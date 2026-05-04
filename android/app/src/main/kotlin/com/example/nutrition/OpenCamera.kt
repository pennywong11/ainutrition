package com.example.nutrition

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.content.Intent

/**
 * Implementation of App Widget functionality.
 */
class OpenCamera : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        // There may be multiple widgets active, so update all of them
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        // Enter relevant functionality for when the first widget is created
    }

    override fun onDisabled(context: Context) {
        // Enter relevant functionality for when the last widget is disabled
    }
}

// android/app/src/main/kotlin/com/example/nutrition/OpenCamera.kt

internal fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
    val views = RemoteViews(context.packageName, R.layout.open_camera)

    // 1. 獲取啟動 Intent
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
        // 關鍵：這行決定了傳給 Flutter 的暗號
        putExtra("route", "analysis")
        // 確保不會開啟多個實例
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }

    if (intent != null) {
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId, // 建議使用 appWidgetId 作為 requestCode
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // 2. 綁定點擊事件到最外層容器
        views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
    }

    appWidgetManager.updateAppWidget(appWidgetId, views)
}