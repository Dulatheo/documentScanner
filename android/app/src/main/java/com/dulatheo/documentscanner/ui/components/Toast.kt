package com.dulatheo.documentscanner.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/**
 * Transient centered toast per DESIGN_SPEC.md §4.7: dark pill, white text,
 * low on screen, auto-dismisses after ~1.6s. Used for confirmations like
 * "Saved to Documents", "Signature added", "Copied", "Added from gallery".
 */
class ToastState {
    var message by mutableStateOf<String?>(null)
        private set
    private var token by mutableIntStateOf(0)

    fun show(text: String) {
        token++
        message = text
    }

    fun dismiss(expectedToken: Int) {
        if (token == expectedToken) message = null
    }

    fun currentToken() = token
}

val LocalToast = compositionLocalOf<ToastState> {
    error("LocalToast not provided — wrap content in a ToastState provider")
}

@Composable
fun ToastHost(state: ToastState) {
    val message = state.message
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(
            visible = message != null,
            enter = fadeIn(tween(180)) + slideInVertically(tween(180)) { it / 4 },
            exit = fadeOut(tween(160)),
            modifier = Modifier.padding(bottom = 170.dp),
        ) {
            Box(
                modifier = Modifier
                    .wrapContentSize()
                    .background(Color(0xEB141312), RoundedCornerShape(20.dp))
                    .padding(horizontal = 18.dp, vertical = 11.dp)
            ) {
                Text(text = message.orEmpty(), color = Color.White, fontSize = 13.sp)
            }
        }
    }

    if (message != null) {
        val tokenAtStart = state.currentToken()
        LaunchedEffect(tokenAtStart) {
            delay(1600)
            state.dismiss(tokenAtStart)
        }
    }
}
