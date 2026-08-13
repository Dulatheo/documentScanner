package com.dulatheo.documentscanner

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.dulatheo.documentscanner.ui.components.ToastHost
import com.dulatheo.documentscanner.ui.components.ToastState
import com.dulatheo.documentscanner.ui.nav.AppNavGraph
import com.dulatheo.documentscanner.ui.nav.AppViewModelFactory
import com.dulatheo.documentscanner.ui.theme.DocumentScannerTheme
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val app = application as DocumentScannerApp
        val factory = AppViewModelFactory(app.repository)

        setContent {
            DocumentScannerTheme {
                val tokens = LocalAppColors.current
                val toast = remember { ToastState() }
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(tokens.bg),
                ) {
                    AppNavGraph(factory = factory, toast = toast)
                    ToastHost(state = toast)
                }
            }
        }
    }
}
