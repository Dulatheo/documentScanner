package com.dulatheo.documentscanner.ui.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dulatheo.documentscanner.data.model.DocumentWithDetails
import com.dulatheo.documentscanner.service.PremiumManager
import com.dulatheo.documentscanner.ui.components.DocumentCard
import com.dulatheo.documentscanner.ui.components.ScanCornersIcon
import com.dulatheo.documentscanner.ui.components.ToastState
import com.dulatheo.documentscanner.ui.paywall.PaywallOutcome
import com.dulatheo.documentscanner.ui.paywall.PaywallScreen
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import java.text.SimpleDateFormat
import java.util.Locale

private val dateFormatter = SimpleDateFormat("d MMM yyyy", Locale.getDefault())

/** Surfaces the free-tier saved-document cap (DESIGN_SPEC §5 "limited
 * document storage") before the user hits it, rather than only ever
 * explaining itself via the paywall shown when Save is actually blocked.
 * Only the "Premium for unlimited" portion (see [HomeScreen]) is styled
 * and tappable — this is the plain lead-in text before it, so it's empty
 * once premium (nothing left to show) or when there's nothing to attach
 * the link to yet (the empty-library case has no natural place for it). */
private fun documentCountPrefix(count: Int, premiumManager: PremiumManager): String {
    if (premiumManager.isPremium()) {
        return if (count == 0) "Nothing saved yet" else "$count document${if (count == 1) "" else "s"}"
    }
    return if (count == 0) {
        "Nothing saved yet · ${PremiumManager.FREE_DOCUMENT_LIMIT} free documents"
    } else {
        "$count of ${PremiumManager.FREE_DOCUMENT_LIMIT} free documents — "
    }
}

@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onOpenDocument: (String) -> Unit,
    onScan: () -> Unit,
    premiumManager: PremiumManager,
    toast: ToastState,
) {
    val tokens = LocalAppColors.current
    val documents by viewModel.documents.collectAsState()
    val query by viewModel.searchQuery.collectAsState()
    var searchOpen by remember { mutableStateOf(false) }
    var showPaywall by remember { mutableStateOf(false) }
    // Long-pressing a card opens a small Rename/Delete menu rather than
    // jumping straight to a destructive confirmation.
    var actionMenuDocumentId by remember { mutableStateOf<String?>(null) }
    var pendingDeleteDocument by remember { mutableStateOf<DocumentWithDetails?>(null) }
    var pendingRenameDocument by remember { mutableStateOf<DocumentWithDetails?>(null) }
    var renameInput by remember { mutableStateOf("") }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(tokens.bg)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 56.dp, start = 20.dp, end = 20.dp, bottom = 4.dp),
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Column {
                    Text(
                        text = "Documents",
                        style = MaterialTheme.typography.headlineMedium,
                        color = tokens.ink,
                    )
                    val isPremiumNow = premiumManager.isPremium()
                    val showPremiumLink = !isPremiumNow && documents.isNotEmpty()
                    Row(modifier = Modifier.padding(top = 5.dp)) {
                        Text(
                            text = documentCountPrefix(documents.size, premiumManager),
                            style = MaterialTheme.typography.bodySmall,
                            color = tokens.ink3,
                        )
                        if (showPremiumLink) {
                            Text(
                                text = "Premium for unlimited",
                                style = MaterialTheme.typography.bodySmall.copy(
                                    fontWeight = FontWeight.Medium,
                                    textDecoration = TextDecoration.Underline,
                                ),
                                color = tokens.accent,
                                modifier = Modifier.clickable { showPaywall = true },
                            )
                        }
                    }
                }
                if (documents.isNotEmpty() || query.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .background(tokens.surface)
                            .border(1.dp, tokens.line, CircleShape)
                            .clickable { searchOpen = !searchOpen },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Filled.Search,
                            contentDescription = "Search documents",
                            tint = tokens.ink2,
                            modifier = Modifier.size(17.dp),
                        )
                    }
                }
            }

            AnimatedVisibility(visible = searchOpen) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 8.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(tokens.surface)
                        .border(1.dp, tokens.line, RoundedCornerShape(12.dp))
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                ) {
                    BasicTextField(
                        value = query,
                        onValueChange = viewModel::onQueryChange,
                        singleLine = true,
                        textStyle = TextStyle(color = tokens.ink, fontSize = 14.sp),
                        cursorBrush = Brush.verticalGradient(listOf(tokens.accent, tokens.accent)),
                        decorationBox = { inner ->
                            Box {
                                if (query.isEmpty()) {
                                    Text("Search by name", color = tokens.ink3, fontSize = 14.sp)
                                }
                                inner()
                            }
                        },
                    )
                }
            }

            if (documents.isEmpty() && query.isEmpty()) {
                EmptyState(onScan = onScan, modifier = Modifier.weight(1f))
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 150.dp),
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(16.dp),
                    verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(18.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    items(documents, key = { it.document.id }) { doc: DocumentWithDetails ->
                        Box {
                            DocumentCard(
                                name = doc.document.name,
                                dateLabel = dateFormatter.format(java.util.Date(doc.document.createdAt)),
                                pageCount = doc.pages.size,
                                thumbnailPath = doc.orderedPages.firstOrNull()?.imagePath,
                                onClick = { onOpenDocument(doc.document.id) },
                                onLongClick = { actionMenuDocumentId = doc.document.id },
                            )
                            DropdownMenu(
                                expanded = actionMenuDocumentId == doc.document.id,
                                onDismissRequest = { actionMenuDocumentId = null },
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Rename") },
                                    onClick = {
                                        actionMenuDocumentId = null
                                        renameInput = doc.document.name
                                        pendingRenameDocument = doc
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text("Delete") },
                                    onClick = {
                                        actionMenuDocumentId = null
                                        pendingDeleteDocument = doc
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }

        // Bottom fade + floating scan button, always visible on Home.
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(120.dp)
                .background(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        1f to tokens.bg,
                    )
                )
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 46.dp)
                .size(64.dp)
                .clip(CircleShape)
                .background(tokens.accent)
                .clickable(onClick = onScan),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.CameraAlt,
                contentDescription = "Scan a document",
                tint = Color.White,
                modifier = Modifier.size(27.dp),
            )
        }

        if (showPaywall) {
            PaywallScreen(premiumManager = premiumManager) { outcome ->
                showPaywall = false
                when (outcome) {
                    PaywallOutcome.TRIAL_STARTED -> toast.show("Trial started — enjoy Premium!")
                    PaywallOutcome.SUBSCRIBED -> toast.show("Welcome to Premium!")
                    PaywallOutcome.RESTORED -> toast.show("Purchases restored")
                    PaywallOutcome.NOT_RESTORED -> toast.show("No previous purchase found")
                    PaywallOutcome.DISMISSED -> {}
                }
            }
        }

        pendingDeleteDocument?.let { doc ->
            AlertDialog(
                onDismissRequest = { pendingDeleteDocument = null },
                title = { Text("Delete “${doc.document.name}”?") },
                text = {
                    Text(
                        "This can't be undone.",
                        color = tokens.ink2,
                        style = MaterialTheme.typography.bodySmall,
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        viewModel.deleteDocument(doc)
                        pendingDeleteDocument = null
                    }) { Text("Delete") }
                },
                dismissButton = {
                    TextButton(onClick = { pendingDeleteDocument = null }) { Text("Cancel") }
                },
            )
        }

        pendingRenameDocument?.let { doc ->
            AlertDialog(
                onDismissRequest = { pendingRenameDocument = null },
                title = { Text("Rename document") },
                text = {
                    OutlinedTextField(
                        value = renameInput,
                        onValueChange = { renameInput = it },
                        singleLine = true,
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        val trimmed = renameInput.trim()
                        if (trimmed.isNotEmpty()) {
                            viewModel.renameDocument(doc, trimmed)
                        }
                        pendingRenameDocument = null
                    }) { Text("Save") }
                },
                dismissButton = {
                    TextButton(onClick = { pendingRenameDocument = null }) { Text("Cancel") }
                },
            )
        }
    }
}

@Composable
private fun EmptyState(onScan: () -> Unit, modifier: Modifier = Modifier) {
    val tokens = LocalAppColors.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(112.dp)
                .clip(RoundedCornerShape(26.dp))
                .background(tokens.surface)
                .border(1.dp, tokens.line, RoundedCornerShape(26.dp)),
            contentAlignment = Alignment.Center,
        ) {
            ScanCornersIcon(color = tokens.accent, size = 52.dp, strokeWidth = 2.4.dp)
        }
        Spacer(Modifier.height(20.dp))
        Text(
            "No documents yet",
            style = MaterialTheme.typography.titleMedium,
            color = tokens.ink,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Scanned documents are saved here. Point your camera at a page to begin.",
            style = MaterialTheme.typography.bodyMedium,
            color = tokens.ink2,
            textAlign = TextAlign.Center,
            modifier = Modifier.width(250.dp),
        )
        Spacer(Modifier.height(20.dp))
        Button(
            onClick = onScan,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = tokens.accent, contentColor = Color.White),
        ) {
            Icon(Icons.Filled.CameraAlt, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(9.dp))
            Text("Scan a document", style = MaterialTheme.typography.labelLarge)
        }
    }
}
