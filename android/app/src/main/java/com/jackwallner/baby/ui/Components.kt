package com.jackwallner.baby.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder

object Links {
    const val PRIVACY = "https://jackwallner.github.io/baby/privacy-policy.html"
    const val SUPPORT = "https://jackwallner.github.io/baby/support.html"
    const val TERMS = "https://jackwallner.github.io/baby/terms.html"
    const val FEEDBACK = "mailto:jackwallner@gmail.com?subject=Baby%20Tracker%20feedback%20(Android)"
    const val PLAY_LISTING = "https://play.google.com/store/apps/details?id=com.jackwallner.baby"
}

fun Context.openUrl(url: String) {
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** "TODAY", "BABY+": a small caps label over a section. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall, color = LocalPalette.current.ink2, modifier = modifier)
}

/** Peach primary action, ink label: onboarding, paywall. */
@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, tag: String? = null, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = Tokens.ctaHeight)
            .graphicBorder(palette, fill = if (enabled) palette.actionFill else palette.cardElevated)
            .clip(Tokens.shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .padding(horizontal = Tokens.loose),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = if (enabled) palette.buttonInk else palette.ink2, textAlign = TextAlign.Center)
    }
}

/** A quiet text action at least 48dp tall. */
@Composable
fun TextAction(text: String, modifier: Modifier = Modifier, color: Color = LocalPalette.current.accent, tag: String? = null, onClick: () -> Unit) {
    Box(
        modifier
            .heightIn(min = Tokens.minTouch)
            .clip(Tokens.shape)
            .clickable(role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .padding(horizontal = Tokens.tight),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = color)
    }
}

/** A selectable chip: Left / Right / Bottle, feeding style, range. */
@Composable
fun Chip(text: String, selected: Boolean, modifier: Modifier = Modifier, color: Color = LocalPalette.current.accent, tag: String? = null, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        modifier
            .heightIn(min = Tokens.minTouch)
            .clip(Tokens.shape)
            .background(if (selected) color else palette.card)
            .border(Tokens.hairlineWidth, if (selected) color else palette.edge, Tokens.shape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { this.selected = selected }
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .padding(horizontal = Tokens.spacing),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (selected) {
            Icon(Icons.Filled.Check, null, tint = palette.paper, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(Tokens.hair))
        }
        Text(text, style = MaterialTheme.typography.labelLarge, color = if (selected) palette.paper else palette.ink, maxLines = 1)
    }
}

/** A settings-style group: a header, card rows with separators, an optional footer. */
@Composable
fun Group(header: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val palette = LocalPalette.current
    Column(Modifier.fillMaxWidth()) {
        if (header != null) SectionLabel(header, Modifier.padding(start = Tokens.spacing, bottom = Tokens.hair + 2.dp))
        Column(Modifier.fillMaxWidth().graphicBorder(palette).clip(Tokens.shape), content = content)
        if (footer != null) {
            Text(footer, style = MaterialTheme.typography.bodySmall, color = palette.ink2, modifier = Modifier.padding(start = Tokens.spacing, end = Tokens.spacing, top = Tokens.hair + 2.dp))
        }
    }
}

@Composable
fun RowDivider() {
    HorizontalDivider(color = LocalPalette.current.separator, thickness = 1.dp, modifier = Modifier.padding(start = Tokens.loose))
}

@Composable
fun NavRow(title: String, icon: ImageVector? = null, detail: String? = null, tag: String? = null, color: Color? = null, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .padding(horizontal = Tokens.loose, vertical = Tokens.tight),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = color ?: palette.accent, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(Tokens.spacing))
        }
        Text(title, style = MaterialTheme.typography.bodyLarge, color = color ?: palette.ink, modifier = Modifier.weight(1f))
        if (detail != null) Text(detail, style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.ink3, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun ToggleRow(title: String, checked: Boolean, tag: String? = null, inset: androidx.compose.ui.unit.Dp = Tokens.loose, leading: (@Composable () -> Unit)? = null, onChange: (Boolean) -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clickable(role = Role.Switch) { onChange(!checked) }
            .semantics { contentDescription = title }
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .padding(horizontal = inset, vertical = Tokens.hair),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(Tokens.spacing))
        }
        Text(title, style = MaterialTheme.typography.bodyLarge, color = palette.ink, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedTrackColor = palette.accent,
                checkedThumbColor = if (palette.isDark) palette.ink else Color.White,
                uncheckedTrackColor = palette.cardElevated,
                uncheckedThumbColor = palette.ink2,
                uncheckedBorderColor = palette.edge,
            ),
        )
    }
}

@Composable
fun ValueRow(title: String, value: String, tag: String? = null, onClick: (() -> Unit)? = null) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .padding(horizontal = Tokens.loose, vertical = Tokens.tight),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, color = palette.ink, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyLarge, color = if (onClick != null) palette.accent else palette.ink2, fontWeight = FontWeight.Medium)
    }
}

/** The kind dot beside a total and at the head of each hour-strip row. */
@Composable
fun KindDot(color: Color, modifier: Modifier = Modifier) {
    Box(modifier.size(Tokens.legendDot).background(color, CircleShape))
}
