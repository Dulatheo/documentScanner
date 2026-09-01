package com.dulatheo.documentscanner.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.dulatheo.documentscanner.ui.theme.LocalAppColors

/**
 * Home-grid document card, per DESIGN_SPEC.md §4.1: a stylized paper preview
 * (real first-page thumbnail once available, else simulated text-line bars),
 * a page-count badge, the document name, and the date.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DocumentCard(
    name: String,
    dateLabel: String,
    pageCount: Int,
    thumbnailPath: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    /** Long-press to delete (DESIGN_SPEC §4.1 "delete a saved document") —
     * the same gesture Android's own launcher/home-screen grids use for a
     * "manage this item" affordance, so it doesn't need its own visible
     * button crowding the card. */
    onLongClick: (() -> Unit)? = null,
) {
    val tokens = LocalAppColors.current
    Column(modifier = modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(3f / 4f)
                .clip(RoundedCornerShape(10.dp))
                .background(tokens.paper)
                .border(1.dp, tokens.line, RoundedCornerShape(10.dp))
        ) {
            if (thumbnailPath != null) {
                AsyncImage(
                    model = thumbnailPath,
                    contentDescription = name,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
            } else {
                PaperLinesPlaceholder(lineColor = tokens.paperLine)
            }

            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(tokens.accentSoft)
                    .padding(horizontal = 6.dp, vertical = 3.dp)
            ) {
                Text(
                    text = if (pageCount == 1) "1 pg" else "$pageCount pgs",
                    color = tokens.accent,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
        Text(
            text = name,
            color = tokens.ink,
            style = MaterialTheme.typography.titleSmall,
            maxLines = 1,
            modifier = Modifier.padding(top = 9.dp),
        )
        Text(
            text = dateLabel,
            color = tokens.ink3,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(top = 2.dp),
        )
    }
}

@Composable
private fun PaperLinesPlaceholder(lineColor: Color) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(14.dp, 14.dp, 12.dp, 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val widths = listOf(0.52f, 0.92f, 0.86f, 0.94f, 0.64f, 0.90f, 0.78f)
        widths.forEachIndexed { index, w ->
            Box(
                modifier = Modifier
                    .fillMaxWidth(w)
                    .height(if (index == 0) 7.dp else 4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(lineColor)
            )
        }
    }
}
