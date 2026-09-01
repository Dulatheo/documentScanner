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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dulatheo.documentscanner.service.ExportFormat
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/** "Export document" bottom sheet content (DESIGN_SPEC.md §4.5). The PDF row
 * carries an extra lock-icon button (Premium "PDF password protection",
 * DESIGN_SPEC §5/§9) that opens a password prompt or the paywall instead of
 * exporting immediately — tapping the rest of the row still exports
 * unprotected, as before. DOCX/XLSX/PPTX are Premium formats in their own
 * right (whole row gated, like the Sign tool) rather than an add-on to a
 * free export. [showProBadge] marks all of these as Premium for a free
 * user; hidden once they're premium — the caller (not this composable)
 * decides what happens when a Premium row is tapped while not premium. */
@Composable
fun ExportSheetContent(
    subtitle: String,
    dismissLabel: String,
    onExport: (ExportFormat) -> Unit,
    onProtectPdfClick: () -> Unit,
    showProBadge: Boolean,
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
            trailing = {
                Box {
                    IconButton(onClick = onProtectPdfClick) {
                        Icon(Icons.Filled.Lock, contentDescription = "Password-protect PDF", tint = tokens.ink2)
                    }
                    if (showProBadge) {
                        Text(
                            "PRO",
                            color = Color.White,
                            fontSize = 7.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(top = 2.dp, end = 2.dp)
                                .clip(RoundedCornerShape(50))
                                .background(tokens.accent)
                                .padding(horizontal = 4.dp, vertical = 1.dp),
                        )
                    }
                }
            },
        )
        Spacer(Modifier.height(10.dp))
        ExportOptionRow(
            badge = "JPG",
            title = "JPG images",
            subtitle = "One image per page",
            onClick = { onExport(ExportFormat.JPG) },
        )
        Spacer(Modifier.height(10.dp))
        ExportOptionRow(
            badge = "DOC",
            title = "Word document",
            subtitle = "Recognized text, all pages",
            onClick = { onExport(ExportFormat.DOCX) },
            proBadge = showProBadge,
        )
        Spacer(Modifier.height(10.dp))
        ExportOptionRow(
            badge = "XLS",
            title = "Excel spreadsheet",
            subtitle = "One row per line of text",
            onClick = { onExport(ExportFormat.XLSX) },
            proBadge = showProBadge,
        )
        Spacer(Modifier.height(10.dp))
        ExportOptionRow(
            badge = "PPT",
            title = "PowerPoint slides",
            subtitle = "One slide per page",
            onClick = { onExport(ExportFormat.PPTX) },
            proBadge = showProBadge,
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
private fun ExportOptionRow(
    badge: String,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    proBadge: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
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
        Box {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(RoundedCornerShape(9.dp))
                    .background(tokens.accentSoft),
                contentAlignment = Alignment.Center,
            ) {
                Text(badge, color = tokens.accent, style = MaterialTheme.typography.labelSmall)
            }
            if (proBadge) {
                Text(
                    "PRO",
                    color = Color.White,
                    fontSize = 7.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 6.dp, y = (-4).dp)
                        .clip(RoundedCornerShape(50))
                        .background(tokens.accent)
                        .padding(horizontal = 4.dp, vertical = 1.dp),
                )
            }
        }
        Spacer(Modifier.width(13.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = tokens.ink, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, color = tokens.ink3, style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(top = 2.dp))
        }
        if (trailing != null) {
            trailing()
        }
    }
}
