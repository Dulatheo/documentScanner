package com.dulatheo.documentscanner.ui.nav

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.dulatheo.documentscanner.ui.camera.CameraScreen
import com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel
import com.dulatheo.documentscanner.ui.components.ToastState
import com.dulatheo.documentscanner.service.PremiumManager
import com.dulatheo.documentscanner.ui.edit.EditScreen
import com.dulatheo.documentscanner.ui.edit.EditViewModel
import com.dulatheo.documentscanner.ui.home.HomeScreen
import com.dulatheo.documentscanner.ui.home.HomeViewModel

/**
 * State machine per DESIGN_SPEC.md §4: home → camera → edit →
 * (export sheet → share) → home, and home → edit (re-edit an existing
 * document) → (export sheet → share) → home. There's no separate
 * Document Viewer screen — viewing/editing a saved document reopens the
 * same Edit screen a fresh capture uses, seeded from that document
 * (`ScanSessionViewModel.startExistingSession`), with Export in place of
 * Save in its top bar.
 *
 * [ScanSessionViewModel] is Activity-scoped (obtained once, shared by the
 * Camera and Edit destinations) since there is only ever one in-progress
 * capture/re-edit session in flight at a time.
 */
private const val ROUTE_HOME = "home"
private const val ROUTE_CAMERA = "camera"
private const val ROUTE_EDIT = "edit"

@Composable
fun AppNavGraph(factory: AppViewModelFactory, toast: ToastState, premiumManager: PremiumManager) {
    val navController = rememberNavController()
    val scanSession: ScanSessionViewModel = viewModel(factory = factory)

    NavHost(navController = navController, startDestination = ROUTE_HOME) {
        composable(ROUTE_HOME) {
            val homeViewModel: HomeViewModel = viewModel(factory = factory)
            HomeScreen(
                viewModel = homeViewModel,
                onOpenDocument = { document ->
                    scanSession.startExistingSession(document)
                    navController.navigate(ROUTE_EDIT)
                },
                onScan = { navController.navigate(ROUTE_CAMERA) },
                premiumManager = premiumManager,
                toast = toast,
            )
        }

        composable(ROUTE_CAMERA) {
            CameraScreen(
                scanSession = scanSession,
                onCaptured = {
                    navController.navigate(ROUTE_EDIT) {
                        popUpTo(ROUTE_CAMERA) { inclusive = true }
                    }
                },
                onCancelled = { navController.popBackStack() },
            )
        }

        composable(ROUTE_EDIT) {
            val editViewModel: EditViewModel = viewModel(factory = factory)
            EditScreen(
                scanSession = scanSession,
                editViewModel = editViewModel,
                toast = toast,
                onCancel = {
                    navController.popBackStack(ROUTE_HOME, inclusive = false)
                },
                // Saving/exporting now happens entirely within EditScreen
                // itself (its own export sheet, whose dismissal navigates
                // home) — this hook is unused for navigation today, kept
                // only in case a future caller needs to react to it.
                onSaved = {},
            )
        }
    }
}
