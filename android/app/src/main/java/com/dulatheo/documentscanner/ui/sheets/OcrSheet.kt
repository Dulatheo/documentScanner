package com.dulatheo.documentscanner.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/** Full-screen "Recognized text" page for the Text (OCR) tool (DESIGN_SPEC
 * §4.3, Premium — see §5/§7): busy state while OCR runs, then the
 * recognized text with a **Copy All** action. A full page rather than a
 * bottom sheet gives the text room to breathe and makes it selectable — a
 * cramped, fixed-height sheet was awkward to read and copy from on a page
 * with more than a few lines. (No separate "Keep as searchable" action:
 * recognized text is already embedded as the PDF's invisible text layer
 * automatically whenever OCR has run on a page, regardless of what happens
 * in this view — the button used to exist but did nothing but close the
 * screen, same as Done.) */
@Composable
fun OcrSheetContent(
    busy: Boolean,
    text: String?,
    onCopy: () -> Unit,
    onDone: () -> Unit,
) {
    val tokens = LocalAppColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(tokens.bg),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 18.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Recognized text", color = tokens.ink, style = MaterialTheme.typography.titleLarge)
            Text(
                "Done",
                color = tokens.ink2,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.clickable(onClick = onDone),
            )
        }

        if (busy) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text("Reading page…", color = tokens.ink2, style = MaterialTheme.typography.bodyMedium)
            }
        } else if (text != null) {
            // SelectionContainer lets the user drag out and copy just part
            // of the text with the system's own selection UI, alongside
            // "Copy All" below for the common case of wanting the whole
            // page at once.
            SelectionContainer(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
            ) {
                Text(
                    text,
                    color = tokens.ink,
                    style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                )
            }
            Button(
                onClick = onCopy,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = tokens.accent, contentColor = Color.White),
            ) { Text("Copy All", style = MaterialTheme.typography.labelLarge) }
        }
    }
}
