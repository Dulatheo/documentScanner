package com.dulatheo.documentscanner.ui.sheets

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/** "Recognized text" bottom sheet content (DESIGN_SPEC.md §4.3): busy state
 * while OCR runs, then the recognized text with Copy / Keep-as-searchable. */
@Composable
fun OcrSheetContent(
    busy: Boolean,
    text: String?,
    onCopy: () -> Unit,
    onKeepSearchable: () -> Unit,
    onDone: () -> Unit,
) {
    val tokens = LocalAppColors.current
    Column(modifier = Modifier.padding(horizontal = 22.dp, vertical = 20.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Recognized text", color = tokens.ink, style = MaterialTheme.typography.titleMedium)
            Text(
                "Done",
                color = tokens.ink2,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.clickable(onClick = onDone),
            )
        }
        Spacer(Modifier.height(14.dp))

        if (busy) {
            Box(modifier = Modifier.padding(vertical = 26.dp)) {
                Text("Reading page…", color = tokens.ink2, style = MaterialTheme.typography.bodySmall)
            }
        } else if (text != null) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 250.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(tokens.bg)
                    .border(1.dp, tokens.line, RoundedCornerShape(12.dp))
                    .padding(14.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                Text(text, color = tokens.ink, style = MaterialTheme.typography.bodySmall)
            }
            Spacer(Modifier.height(14.dp))
            Row(modifier = Modifier.fillMaxWidth()) {
                Button(
                    onClick = onCopy,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = tokens.accent, contentColor = Color.White),
                ) { Text("Copy text", style = MaterialTheme.typography.labelLarge) }
                Spacer(Modifier.width(10.dp))
                OutlinedButton(
                    onClick = onKeepSearchable,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedButtonDefaults.outlinedButtonColors(contentColor = tokens.ink),
                    border = BorderStroke(1.dp, tokens.line),
                ) { Text("Keep as searchable", style = MaterialTheme.typography.labelLarge) }
            }
        }
    }
}
