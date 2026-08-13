package com.dulatheo.documentscanner.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/** "Add comment" bottom sheet content (DESIGN_SPEC.md §4.4). */
@Composable
fun CommentSheetContent(
    draft: String,
    onDraftChange: (String) -> Unit,
    onPost: () -> Unit,
    onCancel: () -> Unit,
) {
    val tokens = LocalAppColors.current
    Column(modifier = Modifier.padding(horizontal = 22.dp, vertical = 20.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Add comment", color = tokens.ink, style = MaterialTheme.typography.titleMedium)
            Text(
                "Cancel",
                color = tokens.ink2,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.clickable(onClick = onCancel),
            )
        }
        Spacer(Modifier.height(14.dp))

        androidx.compose.foundation.layout.Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(84.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(tokens.bg)
                .border(1.dp, tokens.line, RoundedCornerShape(12.dp))
                .padding(12.dp),
        ) {
            if (draft.isEmpty()) {
                Text("Note for this page", color = tokens.ink3, fontSize = 14.sp)
            }
            BasicTextField(
                value = draft,
                onValueChange = onDraftChange,
                textStyle = TextStyle(color = tokens.ink, fontSize = 14.sp, lineHeight = 21.sp),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Spacer(Modifier.height(12.dp))

        Button(
            onClick = onPost,
            enabled = draft.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(containerColor = tokens.accent, contentColor = Color.White),
        ) {
            Text("Post", style = MaterialTheme.typography.labelLarge)
        }
    }
}
