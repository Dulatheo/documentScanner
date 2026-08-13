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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.data.model.SignatureStroke
import com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel
import com.dulatheo.documentscanner.ui.components.PageCard
import com.dulatheo.documentscanner.ui.components.ToastState
import com.dulatheo.documentscanner.ui.sheets.OcrSheetContent
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import com.dulatheo.documentscanner.util.PerspectiveCrop
import kotlinx.coroutines.launch

/**
 * Per-page editor (DESIGN_SPEC.md §4.3): Crop / Highlight / Text / Sign tools
 * over the page(s) captured in [scanSession]. Swiping between pages is
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
    val scope = rememberCoroutineScope()
    val pages = scanSession.pages

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

    var signMode by remember { mutableStateOf<SignMode?>(null) }
    var pendingStrokes by remember { mutableStateOf<List<SignatureStroke>>(emptyList()) }
    var pendingColor by remember { mutableStateOf(SignatureColorOptions[0].second) }
    var pendingThickness by remember { mutableStateOf(5f) }
    var placementRect by remember { mutableStateOf<Rect?>(null) }

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

    fun selectTool(tool: EditTool?) {
        if (activeTool == EditTool.CROP && tool != EditTool.CROP) {
            commitCropIfNeeded()
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
            EditTool.HIGHLIGHT -> {
                if (currentPage.ocrLines.isEmpty()) {
                    scope.launch {
                        val bmp = BitmapFactory.decodeFile(currentPage.imagePath)
                        if (bmp != null) {
                            val result = editViewModel.runOcr(bmp)
                            scanSession.replaceCurrentPage {
                                it.copy(ocrText = result.fullText, ocrLines = result.lines)
                            }
                        }
                    }
                }
            }
            EditTool.SIGN -> {
                pendingStrokes = emptyList()
                signMode = SignMode.DRAWING
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
                Text(
                    "Page ${scanSession.currentIndex + 1} of ${pages.size}",
                    color = tokens.ink,
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    "Save",
                    color = tokens.accent,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.clickable {
                        scope.launch {
                            commitCropSuspend()
                            val id = scanSession.save()
                            toast.show("Saved to Documents")
                            onSaved(id)
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
                        onLineTap = if (pageIndex == scanSession.currentIndex && activeTool == EditTool.HIGHLIGHT) {
                            { idx ->
                                scanSession.replaceCurrentPage { p ->
                                    val updated = p.ocrLines.toMutableList()
                                    updated[idx] = updated[idx].copy(highlighted = !updated[idx].highlighted)
                                    p.copy(ocrLines = updated)
                                }
                            }
                        } else null,
                        signature = if (pageIndex == scanSession.currentIndex && signMode != SignMode.PLACING) page.signature else null,
                        cropCorners = if (isCurrentPageCropping) cropCorners else null,
                        onCropCornersChange = if (isCurrentPageCropping) {
                            { cropCorners = it }
                        } else null,
                        placementRect = if (pageIndex == scanSession.currentIndex && signMode == SignMode.PLACING) placementRect else null,
                        onPlacementRectChange = if (signMode == SignMode.PLACING) {
                            { placementRect = it }
                        } else null,
                        placementStrokes = if (signMode == SignMode.PLACING) pendingStrokes else emptyList(),
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
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                ) {
                    EditTool.entries.forEach { tool ->
                        ToolButton(
                            tool = tool,
                            selected = activeTool == tool,
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
            val sheetState: SheetState = rememberModalBottomSheetState()
            ModalBottomSheet(
                onDismissRequest = { ocrSheetOpen = false; activeTool = null },
                sheetState = sheetState,
                containerColor = tokens.surface,
            ) {
                OcrSheetContent(
                    busy = ocrBusy,
                    text = currentPage.ocrText,
                    onCopy = {
                        currentPage.ocrText?.let { text ->
                            clipboard.setText(androidx.compose.ui.text.AnnotatedString(text))
                        }
                        toast.show("Copied")
                    },
                    onKeepSearchable = {
                        toast.show("Kept as searchable")
                        ocrSheetOpen = false
                        activeTool = null
                    },
                    onDone = {
                        ocrSheetOpen = false
                        activeTool = null
                    },
                )
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
    }
}

@Composable
private fun ToolButton(tool: EditTool, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val tokens = LocalAppColors.current
    val bg = if (selected) tokens.accentSoft else Color.Transparent
    val fg = if (selected) tokens.accent else tokens.ink2
    Column(
        modifier = modifier
            .background(bg, RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(tool.label, color = fg, style = MaterialTheme.typography.labelMedium)
    }
}

/** Reports this composable's laid-out pixel size — used to keep the Crop
 * and Sign-placement overlays (owned by EditScreen) in the same coordinate
 * space as the PageCard they sit on top of. */
private fun Modifier.reportSize(onSize: (IntSize) -> Unit): Modifier =
    this.then(androidx.compose.ui.layout.onGloballyPositioned { coords -> onSize(coords.size) })
