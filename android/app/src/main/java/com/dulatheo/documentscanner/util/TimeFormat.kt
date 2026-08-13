package com.dulatheo.documentscanner.util

import java.util.concurrent.TimeUnit

/** "just now" / "5m ago" / "3h ago" / "2d ago" style relative timestamp, used
 * in the document viewer's comment meta line (DESIGN_SPEC.md §4.4). */
fun relativeTime(epochMillis: Long, nowMillis: Long = System.currentTimeMillis()): String {
    val diff = (nowMillis - epochMillis).coerceAtLeast(0)
    val minutes = TimeUnit.MILLISECONDS.toMinutes(diff)
    val hours = TimeUnit.MILLISECONDS.toHours(diff)
    val days = TimeUnit.MILLISECONDS.toDays(diff)
    return when {
        minutes < 1 -> "just now"
        minutes < 60 -> "${minutes}m ago"
        hours < 24 -> "${hours}h ago"
        days < 7 -> "${days}d ago"
        else -> {
            val fmt = java.text.SimpleDateFormat("d MMM yyyy", java.util.Locale.getDefault())
            fmt.format(java.util.Date(epochMillis))
        }
    }
}
