package com.dulatheo.documentscanner.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.service.ExportFormat
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/** "Export document" bottom sheet content (DESIGN_SPEC.md §4.5). */
@Composable
fun ExportSheetContent(
    subtitle: String,
    dismissLabel: String,
    onExport: (ExportFormat) -> Unit,
    onDismiss: () -> Unit,
) {
    val tokens = LocalAppColors.current
    Column(modifier = Modifier.padding(horizontal = 22.dp, vertical = 20.dp)) {
        Text(
            "Export document",
            color = tokens.ink,
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            subtitle,
            color = tokens.ink3,
            style = MaterialTheme.typography.labelMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 18.dp),
        )

        ExportOptionRow(
            badge = "PDF",
            title = "PDF document",
            subtitle = "Searchable text, all pages",
            onClick = { onExport(ExportFormat.PDF) },
        )
        Spacer(Modifier.height(10.dp))
        ExportOptionRow(
            badge = "JPG",
            title = "JPG images",
            subtitle = "One image per page",
            onClick = { onExport(ExportFormat.JPG) },
        )

        Spacer(Modifier.height(14.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .border(1.dp, tokens.line, RoundedCornerShape(14.dp))
                .clickable(onClick = onDismiss)
                .padding(14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(dismissLabel, color = tokens.ink, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun ExportOptionRow(badge: String, title: String, subtitle: String, onClick: () -> Unit) {
    val tokens = LocalAppColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, tokens.line, RoundedCornerShape(14.dp))
            .background(tokens.bg)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(RoundedCornerShape(9.dp))
                .background(tokens.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            Text(badge, color = tokens.accent, style = MaterialTheme.typography.labelSmall)
        }
        Spacer(Modifier.width(13.dp))
        Column {
            Text(title, color = tokens.ink, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, color = tokens.ink3, style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(top = 2.dp))
        }
    }
}
