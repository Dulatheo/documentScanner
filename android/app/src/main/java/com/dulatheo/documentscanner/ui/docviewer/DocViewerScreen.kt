package com.dulatheo.documentscanner.ui.docviewer

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.service.ExportManager
import com.dulatheo.documentscanner.service.ExportPage
import com.dulatheo.documentscanner.ui.components.PageCard
import com.dulatheo.documentscanner.ui.components.ToastState
import com.dulatheo.documentscanner.service.ExportFormat
import com.dulatheo.documentscanner.ui.paywall.PaywallOutcome
import com.dulatheo.documentscanner.ui.paywall.PaywallScreen
import com.dulatheo.documentscanner.ui.sheets.CommentSheetContent
import com.dulatheo.documentscanner.ui.sheets.ExportSheetContent
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import com.dulatheo.documentscanner.util.JsonCodec
import com.dulatheo.documentscanner.util.relativeTime
import kotlinx.coroutines.launch

/**
 * Document viewer (DESIGN_SPEC.md §4.4): page(s) rendered with any committed
 * highlights/signature, comments below, Comment/Export bottom bar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DocViewerScreen(
    documentId: String,
    viewModel: DocViewerViewModel,
    toast: ToastState,
    justSaved: Boolean,
    onBack: () -> Unit,
) {
    val tokens = LocalAppColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val doc by viewModel.observeDocument(documentId).collectAsState(initial = null)

    var showComment by remember { mutableStateOf(false) }
    var showExport by remember { mutableStateOf(false) }
    var commentDraft by remember { mutableStateOf("") }
    var showPasswordPrompt by remember { mutableStateOf(false) }
    var passwordInput by remember { mutableStateOf("") }
    var showProtectPaywall by remember { mutableStateOf(false) }
    var showPasswordSuggestion by remember { mutableStateOf(false) }
    var showOfficePaywall by remember { mutableStateOf(false) }
    var pendingOfficeFormat by remember { mutableStateOf<ExportFormat?>(null) }

    val exportManager = remember { ExportManager(context, viewModel.imageStorage) }

    fun exportPdf(password: String?) {
        showExport = false
        scope.launch {
            val current = doc ?: return@launch
            val pages = current.orderedPages.map { page ->
                ExportPage(
                    imagePath = page.imagePath,
                    ocrLines = JsonCodec.decodeOcrLines(page.ocrLinesJson),
                    signature = JsonCodec.decodeSignature(page.signatureJson),
                )
            }
            val files = exportManager.export(current.document.name, pages, ExportFormat.PDF, password)
            exportManager.shareAndFinish(files, ExportFormat.PDF)
            if (justSaved) onBack()
        }
    }

    /** DOCX/XLSX/PPTX (DESIGN_SPEC §5/§9 "Office format export") — all
     * Premium, gated the same way as the Sign tool: paywall on tap when
     * not premium, direct export once premium. Currently routed through
     * CloudConvert (network), so unlike every other export path here this
     * can genuinely fail (missing API key, offline, CloudConvert error) —
     * caught and toasted rather than left to crash the coroutine. */
    fun exportOfficeFormat(format: ExportFormat) {
        showExport = false
        scope.launch {
            val current = doc ?: return@launch
            val pages = current.orderedPages.map { page ->
                ExportPage(
                    imagePath = page.imagePath,
                    ocrLines = JsonCodec.decodeOcrLines(page.ocrLinesJson),
                    signature = JsonCodec.decodeSignature(page.signatureJson),
                )
            }
            try {
                val files = exportManager.export(current.document.name, pages, format)
                exportManager.shareAndFinish(files, format)
                if (justSaved) onBack()
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                toast.show(e.message ?: "Export failed")
            }
        }
    }

    val document = doc
    if (document == null) {
        Box(modifier = Modifier.fillMaxSize().background(tokens.bg))
        return
    }

    Box(modifier = Modifier.fillMaxSize().background(tokens.bg)) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 56.dp, start = 8.dp, end = 14.dp, bottom = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.clickable(onClick = onBack).padding(6.dp),
                ) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = null, tint = tokens.accent)
                    Text("Documents", color = tokens.accent, style = MaterialTheme.typography.bodyLarge)
                }
                Text(
                    document.document.name,
                    color = tokens.ink,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                )
                Spacer(Modifier.width(56.dp))
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 26.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                document.orderedPages.forEach { page ->
                    PageCard(
                        imagePath = page.imagePath,
                        ocrLines = JsonCodec.decodeOcrLines(page.ocrLinesJson),
                        signature = JsonCodec.decodeSignature(page.signatureJson),
                    )
                }

                if (document.orderedComments.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "COMMENTS",
                        color = tokens.ink3,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    document.orderedComments.forEach { comment ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(tokens.surface, RoundedCornerShape(12.dp))
                                .padding(14.dp),
                        ) {
                            Text(comment.text, color = tokens.ink, style = MaterialTheme.typography.bodyMedium)
                            val pageLabel = comment.pageIndex?.let { " · page ${it + 1}" } ?: ""
                            Text(
                                "You · ${relativeTime(comment.createdAt)}$pageLabel",
                                color = tokens.ink3,
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier.padding(top = 5.dp),
                            )
                        }
                    }
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(tokens.surface)
                    .padding(horizontal = 18.dp, vertical = 12.dp)
                    .padding(bottom = 28.dp),
            ) {
                BottomBarButton(
                    icon = Icons.Filled.ChatBubbleOutline,
                    label = "Comment",
                    modifier = Modifier.weight(1f),
                    onClick = { showComment = true },
                )
                BottomBarButton(
                    icon = Icons.Filled.FileDownload,
                    label = "Export",
                    modifier = Modifier.weight(1f),
                    onClick = { showExport = true },
                )
            }
        }

        if (showComment) {
            ModalBottomSheet(
                onDismissRequest = { showComment = false; commentDraft = "" },
                containerColor = tokens.surface,
            ) {
                CommentSheetContent(
                    draft = commentDraft,
                    onDraftChange = { commentDraft = it },
                    onPost = {
                        if (commentDraft.isNotBlank()) {
                            viewModel.addComment(documentId, commentDraft.trim())
                            commentDraft = ""
                            showComment = false
                        }
                    },
                    onCancel = { showComment = false; commentDraft = "" },
                )
            }
        }

        if (showExport) {
            val subtitle = if (justSaved) "Saved to Documents · choose a format to share" else "Choose a format to share"
            val dismissLabel = if (justSaved) "Close" else "Cancel"
            ModalBottomSheet(
                onDismissRequest = { showExport = false },
                containerColor = tokens.surface,
            ) {
                ExportSheetContent(
                    subtitle = subtitle,
                    dismissLabel = dismissLabel,
                    onExport = { format ->
                        when (format) {
                            ExportFormat.PDF -> {
                                if (viewModel.premiumManager.isPremium()) {
                                    exportPdf(null)
                                } else {
                                    showExport = false
                                    showPasswordSuggestion = true
                                }
                            }
                            ExportFormat.JPG -> {
                                showExport = false
                                scope.launch {
                                    val pages = document.orderedPages.map { page ->
                                        ExportPage(
                                            imagePath = page.imagePath,
                                            ocrLines = JsonCodec.decodeOcrLines(page.ocrLinesJson),
                                            signature = JsonCodec.decodeSignature(page.signatureJson),
                                        )
                                    }
                                    val files = exportManager.export(document.document.name, pages, format)
                                    exportManager.shareAndFinish(files, format)
                                    if (justSaved) onBack()
                                }
                            }
                            ExportFormat.DOCX, ExportFormat.XLSX, ExportFormat.PPTX -> {
                                if (viewModel.premiumManager.isPremium()) {
                                    exportOfficeFormat(format)
                                } else {
                                    showExport = false
                                    pendingOfficeFormat = format
                                    showOfficePaywall = true
                                }
                            }
                        }
                    },
                    onProtectPdfClick = {
                        showExport = false
                        if (viewModel.premiumManager.isPremium()) {
                            passwordInput = ""
                            showPasswordPrompt = true
                        } else {
                            showProtectPaywall = true
                        }
                    },
                    showProBadge = !viewModel.premiumManager.isPremium(),
                    onDismiss = {
                        showExport = false
                        if (justSaved) onBack()
                    },
                )
            }
        }

        if (showPasswordSuggestion) {
            AlertDialog(
                onDismissRequest = { showPasswordSuggestion = false },
                title = { Text("Protect this PDF?") },
                text = {
                    Text(
                        "Add a password so only people who have it can open this file. Available with Premium.",
                        color = tokens.ink2,
                        style = MaterialTheme.typography.bodySmall,
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        showPasswordSuggestion = false
                        showProtectPaywall = true
                    }) { Text("Add Password") }
                },
                dismissButton = {
                    TextButton(onClick = {
                        showPasswordSuggestion = false
                        exportPdf(null)
                    }) { Text("Export Without Password") }
                },
            )
        }

        if (showPasswordPrompt) {
            AlertDialog(
                onDismissRequest = { showPasswordPrompt = false; passwordInput = "" },
                title = { Text("Protect PDF") },
                text = {
                    Column {
                        Text(
                            "Anyone opening this PDF will need this password.",
                            color = tokens.ink2,
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = passwordInput,
                            onValueChange = { passwordInput = it },
                            label = { Text("Password") },
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        )
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        showPasswordPrompt = false
                        exportPdf(passwordInput.trim().ifEmpty { null })
                        passwordInput = ""
                    }) { Text("Export") }
                },
                dismissButton = {
                    TextButton(onClick = { showPasswordPrompt = false; passwordInput = "" }) { Text("Cancel") }
                },
            )
        }

        if (showProtectPaywall) {
            PaywallScreen(
                premiumManager = viewModel.premiumManager,
                reason = "Password-protecting PDFs is a Premium feature",
            ) { outcome ->
                showProtectPaywall = false
                when (outcome) {
                    PaywallOutcome.TRIAL_STARTED -> {
                        toast.show("Trial started — enjoy Premium!")
                        passwordInput = ""
                        showPasswordPrompt = true
                    }
                    PaywallOutcome.SUBSCRIBED -> {
                        toast.show("Welcome to Premium!")
                        passwordInput = ""
                        showPasswordPrompt = true
                    }
                    PaywallOutcome.RESTORED -> {
                        toast.show("Purchases restored")
                        if (viewModel.premiumManager.isPremium()) {
                            passwordInput = ""
                            showPasswordPrompt = true
                        }
                    }
                    PaywallOutcome.NOT_RESTORED -> toast.show("No previous purchase found")
                    PaywallOutcome.DISMISSED -> {}
                }
            }
        }

        if (showOfficePaywall) {
            PaywallScreen(
                premiumManager = viewModel.premiumManager,
                reason = "Office format export is a Premium feature",
            ) { outcome ->
                showOfficePaywall = false
                when (outcome) {
                    PaywallOutcome.TRIAL_STARTED -> {
                        toast.show("Trial started — enjoy Premium!")
                        pendingOfficeFormat?.let { exportOfficeFormat(it) }
                    }
                    PaywallOutcome.SUBSCRIBED -> {
                        toast.show("Welcome to Premium!")
                        pendingOfficeFormat?.let { exportOfficeFormat(it) }
                    }
                    PaywallOutcome.RESTORED -> {
                        toast.show("Purchases restored")
                        if (viewModel.premiumManager.isPremium()) {
                            pendingOfficeFormat?.let { exportOfficeFormat(it) }
                        }
                    }
                    PaywallOutcome.NOT_RESTORED -> toast.show("No previous purchase found")
                    PaywallOutcome.DISMISSED -> {}
                }
                pendingOfficeFormat = null
            }
        }
    }
}

@Composable
private fun BottomBarButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val tokens = LocalAppColors.current
    Column(
        modifier = modifier.clickable(onClick = onClick).padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, contentDescription = label, tint = tokens.ink2, modifier = Modifier.height(22.dp))
        Spacer(Modifier.height(6.dp))
        Text(label, color = tokens.ink2, style = MaterialTheme.typography.labelMedium)
    }
}
