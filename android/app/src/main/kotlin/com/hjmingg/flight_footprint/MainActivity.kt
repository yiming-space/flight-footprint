package com.hjmingg.flight_footprint

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Calendar access stays behind a very small platform channel.  The Flutter
 * side owns parsing and import decisions; Android only asks for READ_CALENDAR
 * and returns the provider's raw event fields.  Keeping the provider query
 * here avoids adding a heavyweight calendar plugin to the release client.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CALENDAR_CHANNEL = "flight_footprint/calendar"
        private const val UPDATE_CHANNEL = "flight_footprint/update"
        private const val READ_CALENDAR_REQUEST = 4101
    }

    private var pendingCalendarArguments: Map<*, *>? = null
    private var pendingCalendarResult: MethodChannel.Result? = null

    // A TextureView stays inside Android's resizable view hierarchy. That is
    // important on foldables: the outer and inner displays have different
    // aspect ratios, and a SurfaceView can briefly scale its previous buffer
    // non-uniformly while the display is switching.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "queryEvents" -> queryEvents(call.arguments, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> installApk(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("update_file_missing", "The update file path is empty.", null)
            return
        }
        val apk = File(path)
        if (!apk.isFile) {
            result.error("update_file_missing", "The update APK does not exist.", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.error("update_installer_missing", error.message, null)
        } catch (error: IllegalArgumentException) {
            result.error("update_file_invalid", error.message, null)
        }
    }

    private fun queryEvents(arguments: Any?, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            if (pendingCalendarResult != null) {
                result.error(
                    "calendar_request_in_progress",
                    "Calendar permission request is already in progress.",
                    null,
                )
                return
            }
            pendingCalendarArguments = arguments as? Map<*, *>
            pendingCalendarResult = result
            requestPermissions(
                arrayOf(Manifest.permission.READ_CALENDAR),
                READ_CALENDAR_REQUEST,
            )
            return
        }
        result.success(readCalendarEvents(arguments as? Map<*, *>))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != READ_CALENDAR_REQUEST) return

        val result = pendingCalendarResult
        val arguments = pendingCalendarArguments
        pendingCalendarResult = null
        pendingCalendarArguments = null
        if (result == null) return

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            result.success(readCalendarEvents(arguments))
        } else {
            result.error(
                "calendar_permission_denied",
                "Calendar read permission was not granted.",
                null,
            )
        }
    }

    private fun readCalendarEvents(arguments: Map<*, *>?): List<Map<String, Any?>> {
        val startMillis = (arguments?.get("startMillis") as? Number)?.toLong()
            ?: 0L
        val endMillis = (arguments?.get("endMillis") as? Number)?.toLong()
            ?: Long.MAX_VALUE
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.EVENT_TIMEZONE,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.CALENDAR_ID,
        )
        val selection = "${CalendarContract.Events.DTSTART} <= ? AND " +
            "(${CalendarContract.Events.DTEND} IS NULL OR " +
            "${CalendarContract.Events.DTEND} >= ?)"
        val selectionArgs = arrayOf(endMillis.toString(), startMillis.toString())
        val events = mutableListOf<Map<String, Any?>>()

        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${CalendarContract.Events.DTSTART} ASC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndex(CalendarContract.Events._ID)
            val titleIndex = cursor.getColumnIndex(CalendarContract.Events.TITLE)
            val descriptionIndex = cursor.getColumnIndex(CalendarContract.Events.DESCRIPTION)
            val locationIndex = cursor.getColumnIndex(CalendarContract.Events.EVENT_LOCATION)
            val startIndex = cursor.getColumnIndex(CalendarContract.Events.DTSTART)
            val endIndex = cursor.getColumnIndex(CalendarContract.Events.DTEND)
            val timezoneIndex = cursor.getColumnIndex(CalendarContract.Events.EVENT_TIMEZONE)
            val allDayIndex = cursor.getColumnIndex(CalendarContract.Events.ALL_DAY)
            val calendarIdIndex = cursor.getColumnIndex(CalendarContract.Events.CALENDAR_ID)

            // A calendar can contain years of unrelated events. The Flutter
            // parser filters flight-like rows, while this cap protects older
            // devices from returning an unbounded provider cursor.
            while (cursor.moveToNext() && events.size < 5000) {
                events += mapOf(
                    "id" to if (idIndex >= 0) cursor.getLong(idIndex).toString() else "",
                    "title" to if (titleIndex >= 0) cursor.getString(titleIndex) else null,
                    "description" to if (descriptionIndex >= 0) cursor.getString(descriptionIndex) else null,
                    "location" to if (locationIndex >= 0) cursor.getString(locationIndex) else null,
                    "startMillis" to if (startIndex >= 0 && !cursor.isNull(startIndex)) cursor.getLong(startIndex) else null,
                    "endMillis" to if (endIndex >= 0 && !cursor.isNull(endIndex)) cursor.getLong(endIndex) else null,
                    "timezone" to if (timezoneIndex >= 0) cursor.getString(timezoneIndex) else null,
                    "allDay" to (allDayIndex >= 0 && !cursor.isNull(allDayIndex) && cursor.getInt(allDayIndex) != 0),
                    "calendarId" to if (calendarIdIndex >= 0 && !cursor.isNull(calendarIdIndex)) cursor.getLong(calendarIdIndex) else null,
                )
            }
        }
        return events
    }
}
