package com.dulatheo.documentscanner.ui.camera

import android.app.Activity
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.R
import com.dulatheo.documentscanner.data.DraftPage
import com.google.android.gms.common.api.ApiException
import com.google.mlkit.vision.documentscanner.GmsDocumentScanner
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import kotlinx.coroutines.launch

/**
 * Trampoline destination: immediately launches ML Kit's Document Scanner
 * capture UI (`GmsDocumentScanning`) — real camera preview, edge detection,
 * auto-crop, multi-page capture and review, and gallery import all live
 * inside that platform flow (DESIGN_SPEC.md §4.2), so this screen only
 * bridges its result into a [ScanSessionViewModel] session and hands off to
 * Edit. A brief loading state covers the moment before the system sheet
 * appears and while imported pages are copied into app storage.
 */
@Composable
fun CameraScreen(
    scanSession: ScanSessionViewModel,
    onCaptured: () -> Unit,
    onCancelled: () -> Unit,
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val scope = rememberCoroutineScope()
    var launched by remember { mutableStateOf(false) }
    val preparingPagesText = stringResource(R.string.camera_preparing_pages)
    var statusText by remember { mutableStateOf(context.getString(R.string.camera_opening)) }

    val scanner: GmsDocumentScanner = remember {
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(20)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
        GmsDocumentScanning.getClient(options)
    }

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { activityResult ->
        if (activityResult.resultCode == Activity.RESULT_OK) {
            val result = GmsDocumentScanningResult.fromActivityResultIntent(activityResult.data)
            val uris = result?.pages?.map { it.imageUri } ?: emptyList()
            if (uris.isEmpty()) {
                onCancelled()
                return@rememberLauncherForActivityResult
            }
            statusText = preparingPagesText
            scope.launch {
                val storage = scanSession.imageStorage
                val draftPages = uris.map { uri ->
                    val original = storage.importFromUri(uri)
                    val working = storage.duplicate(original)
                    DraftPage(imagePath = working, originalImagePath = original)
                }
                scanSession.startSession(draftPages)
                onCaptured()
            }
        } else {
            onCancelled()
        }
    }

    LaunchedEffect(Unit) {
        if (launched) return@LaunchedEffect
        launched = true
        if (activity == null) {
            onCancelled()
            return@LaunchedEffect
        }
        scanner.getStartScanIntent(activity)
            .addOnSuccessListener { intentSender ->
                launcher.launch(IntentSenderRequest.Builder(intentSender).build())
            }
            .addOnFailureListener { e ->
                val message = if (e is ApiException) {
                    context.getString(R.string.camera_scanner_unavailable, e.statusCode)
                } else {
                    context.getString(R.string.camera_scanner_error, e.message)
                }
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
                onCancelled()
            }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0B0C)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = Color.White)
            Spacer(Modifier.height(16.dp))
            Text(statusText, color = Color(0xB3FFFFFF))
        }
    }
}
