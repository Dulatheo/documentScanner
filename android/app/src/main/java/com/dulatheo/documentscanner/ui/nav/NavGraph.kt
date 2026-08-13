package com.dulatheo.documentscanner.ui.nav

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.dulatheo.documentscanner.ui.camera.CameraScreen
import com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel
import com.dulatheo.documentscanner.ui.components.ToastState
import com.dulatheo.documentscanner.ui.docviewer.DocViewerScreen
import com.dulatheo.documentscanner.ui.docviewer.DocViewerViewModel
import com.dulatheo.documentscanner.ui.edit.EditScreen
import com.dulatheo.documentscanner.ui.edit.EditViewModel
import com.dulatheo.documentscanner.ui.home.HomeScreen
import com.dulatheo.documentscanner.ui.home.HomeViewModel

/**
 * State machine per DESIGN_SPEC.md §4:
 * home → camera → edit → (export sheet → share) → home, and
 * home → doc viewer → (comment | export sheet → share) → home/doc viewer.
 *
 * [ScanSessionViewModel] is Activity-scoped (obtained once, shared by the
 * Camera and Edit destinations) since there is only ever one in-progress
 * capture at a time.
 */
private const val ROUTE_HOME = "home"
private const val ROUTE_CAMERA = "camera"
private const val ROUTE_EDIT = "edit"
private const val ROUTE_DOC_VIEWER = "docviewer/{documentId}?justSaved={justSaved}"

@Composable
fun AppNavGraph(factory: AppViewModelFactory, toast: ToastState) {
    val navController = rememberNavController()
    val scanSession: ScanSessionViewModel = viewModel(factory = factory)

    NavHost(navController = navController, startDestination = ROUTE_HOME) {
        composable(ROUTE_HOME) {
            val homeViewModel: HomeViewModel = viewModel(factory = factory)
            HomeScreen(
                viewModel = homeViewModel,
                onOpenDocument = { id -> navController.navigate("docviewer/$id?justSaved=false") },
                onScan = { navController.navigate(ROUTE_CAMERA) },
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
                onSaved = { documentId ->
                    navController.navigate("docviewer/$documentId?justSaved=true") {
                        popUpTo(ROUTE_HOME) { inclusive = false }
                    }
                },
            )
        }

        composable(
            route = ROUTE_DOC_VIEWER,
            arguments = listOf(
                navArgument("documentId") { type = NavType.StringType },
                navArgument("justSaved") { type = NavType.BoolType; defaultValue = false },
            ),
        ) { backStackEntry ->
            val documentId = backStackEntry.arguments?.getString("documentId").orEmpty()
            val justSaved = backStackEntry.arguments?.getBoolean("justSaved") ?: false
            val docViewerViewModel: DocViewerViewModel = viewModel(factory = factory)
            DocViewerScreen(
                documentId = documentId,
                viewModel = docViewerViewModel,
                toast = toast,
                justSaved = justSaved,
                onBack = { navController.popBackStack(ROUTE_HOME, inclusive = false) },
            )
        }
    }
}
