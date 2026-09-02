package com.dulatheo.documentscanner.ui.edit

import android.graphics.BitmapFactory
import android.graphics.PointF
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.data.model.SignatureStroke
import com.dulatheo.documentscanner.service.ExportFormat
import com.dulatheo.documentscanner.service.ExportManager
import com.dulatheo.documentscanner.service.ExportPage
import com.dulatheo.documentscanner.service.PremiumManager
import com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel
import com.dulatheo.documentscanner.ui.components.PageCard
import com.dulatheo.documentscanner.ui.components.ToastHost
import com.dulatheo.documentscanner.ui.components.ToastState
import com.dulatheo.documentscanner.ui.paywall.PaywallOutcome
import com.dulatheo.documentscanner.ui.paywall.PaywallScreen
import com.dulatheo.documentscanner.ui.sheets.CommentsPageContent
import com.dulatheo.documentscanner.ui.sheets.ExportSheetContent
import com.dulatheo.documentscanner.ui.sheets.OcrSheetContent
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import com.dulatheo.documentscanner.util.PerspectiveCrop
import kotlinx.coroutines.launch
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/**
 * Per-page editor (DESIGN_SPEC.md §4.3): Crop / Adjust / Comment / Text / Sign
 * tools over the page(s) captured in [scanSession]. Swiping between pages is
 * disabled while a tool is actively engaged so drag gestures aren't
 * ambiguous with the pager.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EditScreen(
    scanSession: ScanSessionViewModel,
    editViewModel: EditViewModel,
    toast: ToastState,
    onCancel: () -> Unit,
    onSaved: (documentId: String) -> Unit,
) {
    val tokens = LocalAppColors.current
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pages = scanSession.pages
    val exportManager = remember { ExportManager(context, editViewModel.imageStorage) }

    if (pages.isEmpty()) {
        LaunchedEffect(Unit) { onCancel() }
        return
    }

    val pagerState = rememberPagerState(initialPage = scanSession.currentIndex) { pages.size }
    LaunchedEffect(pagerState.currentPage) { scanSession.goTo(pagerState.currentPage) }

    var activeTool by remember { mutableStateOf<EditTool?>(null) }
    var displaySize by remember { mutableStateOf(IntSize.Zero) }
    var cropCorners by remember(scanSession.currentIndex) { mutableStateOf<List<Offset>?>(null) }

    var ocrBusy by remember { mutableStateOf(false) }
    var ocrSheetOpen by remember { mutableStateOf(false) }
    var showCommentsPage by remember { mutableStateOf(false) }
    var commentDraft by remember { mutableStateOf("") }

    var signMode by remember { mutableStateOf<SignMode?>(null) }
    var pendingStrokes by remember { mutableStateOf<List<SignatureStroke>>(emptyList()) }
    var pendingColor by remember { mutableStateOf(SignatureColorOptions[0].second) }
    var pendingThickness by remember { mutableStateOf(5f) }
    var placementRect by remember { mutableStateOf<Rect?>(null) }
    var placementRotation by remember { mutableStateOf(0f) }

    var showPaywall by remember { mutableStateOf(false) }
    // Which premium-gated tool (SIGN or TEXT) triggered showPaywall, so a
    // successful trial/subscription can resume the tool the user actually
    // tapped instead of always reopening Sign.
    var pendingPremiumTool by remember { mutableStateOf<EditTool?>(null) }
    var isPremium by remember { mutableStateOf(editViewModel.premiumManager.isPremium()) }
    var showSaveLimitDialog by remember { mutableStateOf(false) }
    var showSaveLimitPaywall by remember { mutableStateOf(false) }
    var showExportWithoutSavingSheet by remember { mutableStateOf(false) }
    var ewsPasswordPrompt by remember { mutableStateOf(false) }
    var ewsPasswordInput by remember { mutableStateOf("") }
    var ewsProtectPaywall by remember { mutableStateOf(false) }
    var ewsPasswordSuggestion by remember { mutableStateOf(false) }
    var ewsOfficePaywall by remember { mutableStateOf(false) }
    var ewsPendingOfficeFormat by remember { mutableStateOf<ExportFormat?>(null) }
    var isExporting by remember { mutableStateOf(false) }
    var exportingMessage by remember { mutableStateOf("") }
    // Confirms deleting the current page (DESIGN_SPEC §4.3 "delete a
    // scanned page") — e.g. after scanning the same page a few times and
    // finding one capture came out badly during review.
    var showDeletePageConfirm by remember { mutableStateOf(false) }

    val currentPage = pages[scanSession.currentIndex]

    // Initialize crop corners (inset rectangle) once we know the displayed size.
    LaunchedEffect(activeTool, displaySize, scanSession.currentIndex) {
        if (activeTool == EditTool.CROP && cropCorners == null && displaySize.width > 0) {
            val inset = displaySize.width * 0.04f
            val insetY = displaySize.height * 0.04f
            cropCorners = listOf(
                Offset(inset, insetY),
                Offset(displaySize.width - inset, insetY),
                Offset(displaySize.width - inset, displaySize.height - insetY),
                Offset(inset, displaySize.height - insetY),
            )
        }
    }

    suspend fun commitCropSuspend() {
        val corners = cropCorners ?: return
        val page = currentPage
        val size = displaySize
        cropCorners = null
        if (size.width == 0) return
        val sourcePath = page.originalImagePath ?: page.imagePath
        val original = BitmapFactory.decodeFile(sourcePath) ?: return
        val scale = original.width / size.width.toFloat()
        val scaledCorners = corners.map { PointF(it.x * scale, it.y * scale) }
        val cropped = PerspectiveCrop.crop(original, scaledCorners)
        val newPath = editViewModel.imageStorage.saveBitmap(cropped)
        editViewModel.imageStorage.delete(page.imagePath)
        scanSession.replaceCurrentPage { it.copy(imagePath = newPath) }
        cropped.recycle()
        original.recycle()
    }

    fun commitCropIfNeeded() {
        if (cropCorners == null) return
        scope.launch { commitCropSuspend() }
    }

    /** Persists the current pages/comments — creating a brand-new
     * document, or (DESIGN_SPEC §4.4) updating one already-saved when this
     * session was opened via `ScanSessionViewModel.startExistingSession` —
     * then opens the same export sheet "export without saving" uses.
     * There's no separate Document Viewer screen to land on afterward
     * (re-editing a saved document just reopens this one), so this is
     * also what happens right after tapping Save on a brand-new capture,
     * matching the "save, then straight into the export sheet" flow iOS
     * already used. The top bar's button reads "Save" or "Export"
     * depending on which case this is, but both paths end up here. */
    suspend fun performSaveOrExport() {
        commitCropSuspend()
        val isNewDocument = scanSession.existingDocumentId == null
        val id = scanSession.save()
        if (isNewDocument) toast.show("Saved to Documents")
        onSaved(id)
        showExportWithoutSavingSheet = true
    }

    /** Removes the currently-viewed page (DESIGN_SPEC §4.3 "delete a
     * scanned page"). Deleting the last remaining page is handled by the
     * `pages.isEmpty()` guard at the top of this composable, which calls
     * `onCancel()` on the next recomposition — nothing extra needed here. */
    fun deleteCurrentPage() {
        scanSession.deletePage(scanSession.currentIndex)
    }

    /** "Export" on the save-limit dialog (DESIGN_SPEC §5 "limited document
     * storage") — builds the given format from the current pages and shares
     * it directly, without ever adding the document to the library. Ends
     * the edit session afterward regardless of format, matching the "give
     * up on saving" intent of picking Export over upgrading. */
    fun exportWithoutSavingFormat(format: ExportFormat, password: String? = null) {
        isExporting = true
        exportingMessage = when (format) {
            ExportFormat.PDF -> "Preparing your PDF…"
            ExportFormat.JPG -> "Preparing your images…"
            ExportFormat.DOCX -> "Preparing your Word document…"
            ExportFormat.XLSX -> "Preparing your Excel spreadsheet…"
            ExportFormat.PPTX -> "Preparing your PowerPoint slides…"
        }
        scope.launch {
            commitCropSuspend()
            val exportPages = scanSession.pages.map { p ->
                ExportPage(imagePath = p.imagePath, ocrLines = p.ocrLines, signature = p.signature, brightness = p.brightness, contrast = p.contrast)
            }
            val files = exportManager.export("Scan", exportPages, format, password)
            exportManager.shareAndFinish(files, format)
            showExportWithoutSavingSheet = false
            scanSession.clear()
            onCancel()
        }
    }

    fun selectTool(tool: EditTool?) {
        if (activeTool == EditTool.CROP && tool != EditTool.CROP) {
            commitCropIfNeeded()
        }
        // Sign and Text recognition are premium-only (DESIGN_SPEC §4.3/§7)
        // — gate before touching activeTool/opening the drawing pad or the
        // recognized-text page, and re-check on every tap (rather than
        // trusting a possibly-stale `isPremium`) since a trial started
        // elsewhere in the app could have expired since this screen last
        // refreshed it. Comment isn't gated — it doesn't touch OCR.
        if (tool == EditTool.SIGN || tool == EditTool.TEXT) {
            isPremium = editViewModel.premiumManager.isPremium()
            if (!isPremium) {
                pendingPremiumTool = tool
                showPaywall = true
                return
            }
        }
        activeTool = tool
        when (tool) {
            EditTool.TEXT -> {
                ocrSheetOpen = true
                if (currentPage.ocrText == null) {
                    ocrBusy = true
                    scope.launch {
                        val bmp = BitmapFactory.decodeFile(currentPage.imagePath)
                        if (bmp != null) {
                            val result = editViewModel.runOcr(bmp)
                            scanSession.replaceCurrentPage {
                                it.copy(ocrText = result.fullText, ocrLines = result.lines)
                            }
                        }
                        ocrBusy = false
                    }
                }
            }
            EditTool.SIGN -> {
                pendingStrokes = emptyList()
                signMode = SignMode.DRAWING
            }
            EditTool.COMMENT -> {
                showCommentsPage = true
            }
            else -> {}
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(tokens.bg)) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 56.dp, start = 18.dp, end = 18.dp, bottom = 14.dp),
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Cancel",
                    color = tokens.ink2,
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.clickable {
                        scanSession.clear()
                        onCancel()
                    },
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                    Text(
                        "Page ${scanSession.currentIndex + 1} of ${pages.size}",
                        color = tokens.ink,
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Icon(
                        Icons.Filled.Delete,
                        contentDescription = "Delete this page",
                        tint = tokens.ink2,
                        modifier = Modifier
                            .size(18.dp)
                            .clickable { showDeletePageConfirm = true },
                    )
                }
                Text(
                    if (scanSession.existingDocumentId == null) "Save" else "Export",
                    color = tokens.accent,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.clickable {
                        // Re-saving an existing document never counts
                        // against the free-tier save limit (DESIGN_SPEC
                        // §5) — only creating a brand-new one does.
                        if (scanSession.existingDocumentId != null) {
                            scope.launch { performSaveOrExport() }
                        } else {
                            scope.launch {
                                val count = editViewModel.documentCount()
                                if (editViewModel.premiumManager.canCreateNewDocument(count)) {
                                    performSaveOrExport()
                                } else {
                                    showSaveLimitDialog = true
                                }
                            }
                        }
                    },
                )
            }

            HorizontalPager(
                state = pagerState,
                userScrollEnabled = activeTool == null,
                contentPadding = PaddingValues(horizontal = 26.dp),
                pageSpacing = 14.dp,
                modifier = Modifier.weight(1f),
            ) { pageIndex ->
                val page = pages[pageIndex]
                // While the Crop tool is active, display the same image commitCropSuspend()
                // will crop from (the pristine pre-crop original when one exists) rather than
                // the page's current — possibly already-cropped — imagePath. Otherwise, on a
                // second or later crop of the same page, the on-screen drag coordinates (and
                // the displaySize used to scale them) would be measured against the previous
                // crop's image while commitCropSuspend() decodes and scales against the
                // original's different pixel dimensions, producing a wrong crop region.
                val cropSourcePath = page.originalImagePath ?: page.imagePath
                val isCurrentPageCropping = pageIndex == scanSession.currentIndex && activeTool == EditTool.CROP
                Box(modifier = Modifier.fillMaxSize().padding(vertical = 22.dp)) {
                    PageCard(
                        imagePath = if (isCurrentPageCropping) cropSourcePath else page.imagePath,
                        ocrLines = if (pageIndex == scanSession.currentIndex) page.ocrLines else emptyList(),
                        signature = if (pageIndex == scanSession.currentIndex && signMode != SignMode.PLACING) page.signature else null,
                        brightness = page.brightness,
                        contrast = page.contrast,
                        cropCorners = if (isCurrentPageCropping) cropCorners else null,
                        onCropCornersChange = if (isCurrentPageCropping) {
                            { cropCorners = it }
                        } else null,
                        placementRect = if (pageIndex == scanSession.currentIndex && signMode == SignMode.PLACING) placementRect else null,
                        onPlacementRectChange = if (signMode == SignMode.PLACING) {
                            { placementRect = it }
                        } else null,
                        placementStrokes = if (signMode == SignMode.PLACING) pendingStrokes else emptyList(),
                        placementRotation = placementRotation,
                        onPlacementRotationChange = if (signMode == SignMode.PLACING) {
                            { placementRotation = it }
                        } else null,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .let { m ->
                                if (pageIndex == scanSession.currentIndex) {
                                    m.reportSize { displaySize = it }
                                } else m
                            },
                    )
                }
            }

            // Tool bar
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(tokens.surface)
                    .padding(top = 12.dp, start = 14.dp, end = 14.dp, bottom = 40.dp),
            ) {
                Box(
                    modifier = Modifier.fillMaxWidth().height(26.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        activeTool?.hint ?: "",
                        color = tokens.ink2,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
                if (activeTool == EditTool.ADJUST) {
                    AdjustSliders(
                        brightness = currentPage.brightness,
                        contrast = currentPage.contrast,
                        onBrightnessChange = { v -> scanSession.replaceCurrentPage { it.copy(brightness = v) } },
                        onContrastChange = { v -> scanSession.replaceCurrentPage { it.copy(contrast = v) } },
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                ) {
                    EditTool.entries.forEach { tool ->
                        ToolButton(
                            tool = tool,
                            selected = activeTool == tool,
                            showsProBadge = (tool == EditTool.SIGN || tool == EditTool.TEXT) && !isPremium,
                            modifier = Modifier.weight(1f),
                            onClick = {
                                selectTool(if (activeTool == tool) null else tool)
                            },
                        )
                    }
                }
            }
        }

        if (ocrSheetOpen) {
            // A full-screen Dialog rather than a ModalBottomSheet — the
            // recognized text needs room to breathe and be selectable, and
            // a Dialog (unlike a plain full-size overlay Box) also gets the
            // system back button/gesture for free as an equivalent to
            // onDismissRequest.
            Dialog(
                onDismissRequest = { ocrSheetOpen = false; activeTool = null },
                properties = DialogProperties(usePlatformDefaultWidth = false),
            ) {
                // A Dialog opens its own Android Window, layered above the
                // Activity's — the app-wide ToastHost mounted in
                // MainActivity lives in that other window, so it's hidden
                // behind this one. Sharing the same `toast` ToastState with
                // a second ToastHost here (drawn after — i.e. on top of —
                // OcrSheetContent) is what actually makes "Copied" visible.
                Box {
                    OcrSheetContent(
                        busy = ocrBusy,
                        text = currentPage.ocrText,
                        onCopy = {
                            currentPage.ocrText?.let { text ->
                                clipboard.setText(androidx.compose.ui.text.AnnotatedString(text))
                            }
                            toast.show("Copied")
                        },
                        onDone = {
                            ocrSheetOpen = false
                            activeTool = null
                        },
                    )
                    ToastHost(state = toast)
                }
            }
        }

        if (showCommentsPage) {
            Dialog(
                onDismissRequest = { showCommentsPage = false; activeTool = null; commentDraft = "" },
                properties = DialogProperties(usePlatformDefaultWidth = false),
            ) {
                CommentsPageContent(
                    comments = scanSession.comments,
                    draft = commentDraft,
                    onDraftChange = { commentDraft = it },
                    onPost = {
                        val trimmed = commentDraft.trim()
                        if (trimmed.isNotEmpty()) {
                            scanSession.addDraftComment(trimmed, scanSession.currentIndex)
                            commentDraft = ""
                        }
                    },
                    onDone = { showCommentsPage = false; activeTool = null; commentDraft = "" },
                )
            }
        }

        if (showPaywall) {
            PaywallScreen(premiumManager = editViewModel.premiumManager) { outcome ->
                showPaywall = false
                when (outcome) {
                    PaywallOutcome.TRIAL_STARTED -> {
                        isPremium = true
                        toast.show("Trial started — enjoy Premium!")
                        selectTool(pendingPremiumTool ?: EditTool.SIGN)
                    }
                    PaywallOutcome.SUBSCRIBED -> {
                        isPremium = true
                        toast.show("Welcome to Premium!")
                        selectTool(pendingPremiumTool ?: EditTool.SIGN)
                    }
                    PaywallOutcome.RESTORED -> {
                        isPremium = editViewModel.premiumManager.isPremium()
                        toast.show("Purchases restored")
                    }
                    PaywallOutcome.NOT_RESTORED -> toast.show("No previous purchase found")
                    PaywallOutcome.DISMISSED -> {}
                }
                pendingPremiumTool = null
            }
        }

        if (showSaveLimitPaywall) {
            PaywallScreen(
                premiumManager = editViewModel.premiumManager,
                reason = "You've reached the free plan's ${PremiumManager.FREE_DOCUMENT_LIMIT}-document limit",
            ) { outcome ->
                showSaveLimitPaywall = false
                when (outcome) {
                    PaywallOutcome.TRIAL_STARTED -> {
                        isPremium = true
                        toast.show("Trial started — enjoy Premium!")
                        scope.launch { performSaveOrExport() }
                    }
                    PaywallOutcome.SUBSCRIBED -> {
                        isPremium = true
                        toast.show("Welcome to Premium!")
                        scope.launch { performSaveOrExport() }
                    }
                    PaywallOutcome.RESTORED -> {
                        isPremium = editViewModel.premiumManager.isPremium()
                        toast.show("Purchases restored")
                        if (isPremium) scope.launch { performSaveOrExport() }
                    }
                    PaywallOutcome.NOT_RESTORED -> toast.show("No previous purchase found")
                    PaywallOutcome.DISMISSED -> {}
                }
            }
        }

        if (showDeletePageConfirm) {
            AlertDialog(
                onDismissRequest = { showDeletePageConfirm = false },
                title = { Text("Delete this page?") },
                text = {
                    Text(
                        "This can't be undone.",
                        color = tokens.ink2,
                        style = MaterialTheme.typography.bodySmall,
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        showDeletePageConfirm = false
                        deleteCurrentPage()
                    }) { Text("Delete") }
                },
                dismissButton = {
                    TextButton(onClick = { showDeletePageConfirm = false }) { Text("Cancel") }
                },
            )
        }

        if (showSaveLimitDialog) {
            AlertDialog(
                onDismissRequest = { showSaveLimitDialog = false },
                title = { Text("Document limit reached") },
                text = {
                    Column {
                        Text(
                            "Free plan is limited to ${PremiumManager.FREE_DOCUMENT_LIMIT} saved documents. " +
                                "Upgrade for unlimited storage, export this one without saving, or cancel.",
                            color = tokens.ink2,
                            style = MaterialTheme.typography.bodySmall,
                        )
                        TextButton(onClick = {
                            showSaveLimitDialog = false
                            showExportWithoutSavingSheet = true
                        }) { Text("Export") }
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        showSaveLimitDialog = false
                        showSaveLimitPaywall = true
                    }) {
                        Text(if (editViewModel.premiumManager.hasUsedTrial()) "Upgrade to Premium" else "Start Free Trial")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showSaveLimitDialog = false }) { Text("Cancel") }
                },
            )
        }

        if (showExportWithoutSavingSheet) {
            ModalBottomSheet(
                onDismissRequest = {
                    showExportWithoutSavingSheet = false
                    scanSession.clear()
                    onCancel()
                },
                containerColor = tokens.surface,
            ) {
                ExportSheetContent(
                    subtitle = "Choose a format to share",
                    dismissLabel = "Cancel",
                    onExport = { format ->
                        when (format) {
                            ExportFormat.PDF -> {
                                if (editViewModel.premiumManager.isPremium()) {
                                    exportWithoutSavingFormat(ExportFormat.PDF)
                                } else {
                                    showExportWithoutSavingSheet = false
                                    ewsPasswordSuggestion = true
                                }
                            }
                            ExportFormat.JPG -> exportWithoutSavingFormat(ExportFormat.JPG)
                            ExportFormat.DOCX, ExportFormat.XLSX, ExportFormat.PPTX -> {
                                if (editViewModel.premiumManager.isPremium()) {
                                    exportWithoutSavingFormat(format)
                                } else {
                                    showExportWithoutSavingSheet = false
                                    ewsPendingOfficeFormat = format
                                    ewsOfficePaywall = true
                                }
                            }
                        }
                    },
                    onProtectPdfClick = {
                        showExportWithoutSavingSheet = false
                        if (editViewModel.premiumManager.isPremium()) {
                            ewsPasswordInput = ""
                            ewsPasswordPrompt = true
                        } else {
                            ewsProtectPaywall = true
                        }
                    },
                    showProBadge = !editViewModel.premiumManager.isPremium(),
                    onDismiss = {
                        showExportWithoutSavingSheet = false
                        scanSession.clear()
                        onCancel()
                    },
                )
            }
        }

        if (ewsPasswordSuggestion) {
            AlertDialog(
                onDismissRequest = { ewsPasswordSuggestion = false },
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
                        ewsPasswordSuggestion = false
                        ewsProtectPaywall = true
                    }) { Text("Add Password") }
                },
                dismissButton = {
                    TextButton(onClick = {
                        ewsPasswordSuggestion = false
                        exportWithoutSavingFormat(ExportFormat.PDF)
                    }) { Text("Export Without Password") }
                },
            )
        }

        if (ewsPasswordPrompt) {
            AlertDialog(
                onDismissRequest = { ewsPasswordPrompt = false; ewsPasswordInput = "" },
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
                            value = ewsPasswordInput,
                            onValueChange = { ewsPasswordInput = it },
                            label = { Text("Password") },
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        )
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        ewsPasswordPrompt = false
                        exportWithoutSavingFormat(ExportFormat.PDF, ewsPasswordInput.trim().ifEmpty { null })
                        ewsPasswordInput = ""
                    }) { Text("Export") }
                },
                dismissButton = {
                    TextButton(onClick = { ewsPasswordPrompt = false; ewsPasswordInput = "" }) { Text("Cancel") }
                },
            )
        }

        if (ewsProtectPaywall) {
            PaywallScreen(
                premiumManager = editViewModel.premiumManager,
                reason = "Password-protecting PDFs is a Premium feature",
            ) { outcome ->
                ewsProtectPaywall = false
                when (outcome) {
                    PaywallOutcome.TRIAL_STARTED -> {
                        isPremium = true
                        toast.show("Trial started — enjoy Premium!")
                        ewsPasswordInput = ""
                        ewsPasswordPrompt = true
                    }
                    PaywallOutcome.SUBSCRIBED -> {
                        isPremium = true
                        toast.show("Welcome to Premium!")
                        ewsPasswordInput = ""
                        ewsPasswordPrompt = true
                    }
                    PaywallOutcome.RESTORED -> {
                        isPremium = editViewModel.premiumManager.isPremium()
                        toast.show("Purchases restored")
                        if (isPremium) {
                            ewsPasswordInput = ""
                            ewsPasswordPrompt = true
                        }
                    }
                    PaywallOutcome.NOT_RESTORED -> toast.show("No previous purchase found")
                    PaywallOutcome.DISMISSED -> {}
                }
            }
        }

        if (ewsOfficePaywall) {
            PaywallScreen(
                premiumManager = editViewModel.premiumManager,
                reason = "Office format export is a Premium feature",
            ) { outcome ->
                ewsOfficePaywall = false
                when (outcome) {
                    PaywallOutcome.TRIAL_STARTED -> {
                        isPremium = true
                        toast.show("Trial started — enjoy Premium!")
                        ewsPendingOfficeFormat?.let { exportWithoutSavingFormat(it) }
                    }
                    PaywallOutcome.SUBSCRIBED -> {
                        isPremium = true
                        toast.show("Welcome to Premium!")
                        ewsPendingOfficeFormat?.let { exportWithoutSavingFormat(it) }
                    }
                    PaywallOutcome.RESTORED -> {
                        isPremium = editViewModel.premiumManager.isPremium()
                        toast.show("Purchases restored")
                        if (isPremium) {
                            ewsPendingOfficeFormat?.let { exportWithoutSavingFormat(it) }
                        }
                    }
                    PaywallOutcome.NOT_RESTORED -> toast.show("No previous purchase found")
                    PaywallOutcome.DISMISSED -> {}
                }
                ewsPendingOfficeFormat = null
            }
        }

        if (signMode == SignMode.DRAWING) {
            Box(modifier = Modifier.fillMaxSize().background(tokens.bg)) {
                SignaturePad(
                    onCancel = {
                        signMode = null
                        activeTool = null
                    },
                    onDone = { strokes, colorHex, thickness ->
                        pendingStrokes = strokes
                        pendingColor = colorHex
                        pendingThickness = thickness
                        val w = (displaySize.width * 0.35f).coerceAtLeast(120f)
                        val h = w * (SIGNATURE_CANVAS_HEIGHT / SIGNATURE_CANVAS_WIDTH)
                        placementRect = Rect(
                            displaySize.width * 0.15f,
                            displaySize.height * 0.55f,
                            displaySize.width * 0.15f + w,
                            displaySize.height * 0.55f + h,
                        )
                        placementRotation = 0f
                        signMode = SignMode.PLACING
                    },
                )
            }
        }

        if (signMode == SignMode.PLACING) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(tokens.surface)
                    .padding(start = 18.dp, end = 18.dp, top = 14.dp, bottom = 40.dp),
            ) {
                Text(
                    "Drag to position · pull the corner to resize",
                    color = tokens.ink2,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)) {
                        SignatureColorOptions.forEach { (_, hex) ->
                            Box(
                                modifier = Modifier
                                    .height(30.dp)
                                    .padding(0.dp)
                            ) {
                                androidx.compose.foundation.layout.Box(
                                    modifier = Modifier
                                        .height(30.dp)
                                        .width(30.dp)
                                        .background(parseHexColor(hex), androidx.compose.foundation.shape.CircleShape)
                                        .clickable {
                                            pendingColor = hex
                                            pendingStrokes = pendingStrokes.map { it.copy(colorHex = hex) }
                                        },
                                )
                            }
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        "Redraw",
                        color = tokens.ink2,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.clickable { signMode = SignMode.DRAWING },
                    )
                    Spacer(Modifier.width(14.dp))
                    Box(
                        modifier = Modifier
                            .background(tokens.accent, RoundedCornerShape(12.dp))
                            .clickable {
                                val rect = placementRect
                                if (rect != null && displaySize.width > 0) {
                                    val signature = Signature(
                                        strokes = pendingStrokes,
                                        colorHex = pendingColor,
                                        thickness = pendingThickness,
                                        canvasWidth = SIGNATURE_CANVAS_WIDTH,
                                        canvasHeight = SIGNATURE_CANVAS_HEIGHT,
                                        x = rect.left / displaySize.width,
                                        y = rect.top / displaySize.height,
                                        width = rect.width / displaySize.width,
                                        height = rect.height / displaySize.height,
                                        rotation = placementRotation,
                                    )
                                    scanSession.replaceCurrentPage { it.copy(signature = signature) }
                                    toast.show("Signature added")
                                }
                                signMode = null
                                activeTool = null
                                placementRect = null
                            }
                            .padding(horizontal = 24.dp, vertical = 11.dp),
                    ) {
                        Text("Done", color = Color.White, style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }

        if (isExporting) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(tokens.surface)
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(color = tokens.accent)
                    Spacer(Modifier.height(12.dp))
                    Text(exportingMessage, color = tokens.ink2, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

/** Brightness/Contrast sliders (DESIGN_SPEC §4.3 "Adjust tool"), shown
 * above the tool row while Adjust is active. Unlike iOS, there's no
 * separate "commit" step — [onBrightnessChange]/[onContrastChange] write
 * straight into the current page's [com.dulatheo.documentscanner.data.DraftPage]
 * on every drag tick, since brightness/contrast are applied live via a
 * cheap `ColorFilter` (`PageCard`) rather than re-rendering a bitmap. */
@Composable
private fun AdjustSliders(
    brightness: Float,
    contrast: Float,
    onBrightnessChange: (Float) -> Unit,
    onContrastChange: (Float) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp, vertical = 4.dp),
    ) {
        AdjustSlider(label = "Brightness", value = brightness, range = -0.3f..0.3f, onValueChange = onBrightnessChange)
        AdjustSlider(label = "Contrast", value = contrast, range = 0.7f..1.5f, onValueChange = onContrastChange)
    }
}

@Composable
private fun AdjustSlider(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onValueChange: (Float) -> Unit,
) {
    val tokens = LocalAppColors.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            label,
            color = tokens.ink2,
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.width(74.dp),
        )
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = range,
            modifier = Modifier.weight(1f),
            colors = androidx.compose.material3.SliderDefaults.colors(
                thumbColor = tokens.accent,
                activeTrackColor = tokens.accent,
            ),
        )
    }
}

@Composable
private fun ToolButton(
    tool: EditTool,
    selected: Boolean,
    showsProBadge: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val tokens = LocalAppColors.current
    val bg = if (selected) tokens.accentSoft else Color.Transparent
    val fg = if (selected) tokens.accent else tokens.ink2
    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(bg, RoundedCornerShape(12.dp))
                .clickable(onClick = onClick)
                .padding(vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(tool.label, color = fg, style = MaterialTheme.typography.labelMedium)
        }
        if (showsProBadge) {
            Text(
                "PRO",
                color = Color.White,
                style = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-2).dp, y = 2.dp)
                    .background(tokens.accent, RoundedCornerShape(50))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            )
        }
    }
}

/** Reports this composable's laid-out pixel size — used to keep the Crop
 * and Sign-placement overlays (owned by EditScreen) in the same coordinate
 * space as the PageCard they sit on top of. */
private fun Modifier.reportSize(onSize: (IntSize) -> Unit): Modifier =
    this.then(Modifier.onGloballyPositioned { coords -> onSize(coords.size) })
