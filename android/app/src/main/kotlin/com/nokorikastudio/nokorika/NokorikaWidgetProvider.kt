package com.nokorikastudio.nokorika

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

class NokorikaWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            updateWidget(context, appWidgetManager, widgetId, widgetData)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action
        if (action == Intent.ACTION_DATE_CHANGED ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, NokorikaWidgetProvider::class.java),
            )
            if (ids.isNotEmpty()) {
                onUpdate(context, manager, ids)
            }
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        widgetData: SharedPreferences,
    ) {
        val views = RemoteViews(context.packageName, R.layout.nokorika_widget)

        val pendingIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
        )
        views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

        val remainingJson = widgetData.getString(KEY_REMAINING_BY_DATE, null)
        val lastBusinessDay = widgetData.getString(KEY_LAST_BUSINESS_DAY, null)
        val monthLabel = widgetData.getString(KEY_MONTH_LABEL, null)
        val monthKey = widgetData.getString(KEY_MONTH_KEY, null)

        val calendar = Calendar.getInstance()
        val todayKey = String.format(
            Locale.US,
            "%04d-%02d-%02d",
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.DAY_OF_MONTH),
        )
        val currentMonthKey = String.format(
            Locale.US,
            "%04d-%02d",
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
        )

        if (remainingJson.isNullOrEmpty() || monthKey != currentMonthKey) {
            views.setTextViewText(R.id.widget_month_label, context.getString(R.string.widget_app_name))
            views.setTextViewText(R.id.widget_remaining_count, "—")
            views.setTextViewText(
                R.id.widget_remaining_label,
                context.getString(R.string.widget_open_app_hint),
            )
            views.setTextViewText(R.id.widget_last_business_day, "")
        } else {
            val remaining = try {
                JSONObject(remainingJson).optInt(todayKey, -1)
            } catch (_: Exception) {
                -1
            }

            views.setTextViewText(
                R.id.widget_month_label,
                monthLabel ?: context.getString(R.string.widget_app_name),
            )
            if (remaining >= 0) {
                views.setTextViewText(R.id.widget_remaining_count, remaining.toString())
                views.setTextViewText(
                    R.id.widget_remaining_label,
                    context.getString(R.string.widget_remaining_label),
                )
            } else {
                views.setTextViewText(R.id.widget_remaining_count, "—")
                views.setTextViewText(
                    R.id.widget_remaining_label,
                    context.getString(R.string.widget_open_app_hint),
                )
            }
            views.setTextViewText(
                R.id.widget_last_business_day,
                if (lastBusinessDay.isNullOrEmpty()) {
                    ""
                } else {
                    context.getString(R.string.widget_last_business_day, lastBusinessDay)
                },
            )
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    companion object {
        const val KEY_REMAINING_BY_DATE = "remaining_by_date"
        const val KEY_LAST_BUSINESS_DAY = "last_business_day"
        const val KEY_MONTH_LABEL = "month_label"
        const val KEY_MONTH_KEY = "month_key"
    }
}
