package com.dulatheo.documentscanner.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dulatheo.documentscanner.R
import com.dulatheo.documentscanner.data.DraftComment
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import com.dulatheo.documentscanner.util.relativeTime

/** Full-screen page for the Comment tool (DESIGN_SPEC §4.3): the
 * document's comments so far, plus a composer to add another. Works the
 * same for a fresh capture (comments buffered in
 * [com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel.comments]
 * until Save) and a re-edit of an existing document (its already-posted
 * comments loaded in alongside the buffered ones — see
 * [com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel.startExistingSession]). */
@Composable
fun CommentsPageContent(
    comments: List<DraftComment>,
    draft: String,
    onDraftChange: (String) -> Unit,
    onPost: () -> Unit,
    onDone: () -> Unit,
) {
    val tokens = LocalAppColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(tokens.bg),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 18.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.comments_title), color = tokens.ink, style = MaterialTheme.typography.titleLarge)
            Text(
                stringResource(R.string.action_done),
                color = tokens.ink2,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.clickable(onClick = onDone),
            )
        }

        if (comments.isEmpty()) {
            Box(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                Text(stringResource(R.string.comments_empty), color = tokens.ink2, style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                for (comment in comments.sortedBy { it.createdAt }) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(tokens.surface, RoundedCornerShape(12.dp))
                            .border(1.dp, tokens.line, RoundedCornerShape(12.dp))
                            .padding(14.dp),
                    ) {
                        Text(comment.text, color = tokens.ink, style = MaterialTheme.typography.bodyMedium)
                        val relative = relativeTime(comment.createdAt)
                        val meta = comment.pageIndex?.let { pageIndex ->
                            stringResource(R.string.comments_meta_with_page, relative, pageIndex + 1)
                        } ?: stringResource(R.string.comments_meta_no_page, relative)
                        Text(
                            meta,
                            color = tokens.ink3,
                            style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(top = 5.dp),
                        )
                    }
                }
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(tokens.bg)
                .padding(horizontal = 20.dp, vertical = 16.dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(70.dp)
                    .background(tokens.surface, RoundedCornerShape(12.dp))
                    .border(1.dp, tokens.line, RoundedCornerShape(12.dp))
                    .padding(12.dp),
            ) {
                if (draft.isEmpty()) {
                    Text(stringResource(R.string.comments_composer_placeholder), color = tokens.ink3, fontSize = 14.sp)
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
                Text(stringResource(R.string.comments_post), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}
