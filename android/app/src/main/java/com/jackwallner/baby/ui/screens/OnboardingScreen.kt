package com.jackwallner.baby.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedingStyle
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.Guidance
import com.jackwallner.baby.ui.theme.CareGraphic
import com.jackwallner.baby.ui.Chip
import com.jackwallner.baby.ui.DateDialog
import com.jackwallner.baby.ui.Links
import com.jackwallner.baby.ui.PrimaryButton
import com.jackwallner.baby.ui.TextAction
import com.jackwallner.baby.ui.ToggleRow
import com.jackwallner.baby.ui.openUrl
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import java.time.LocalDate
import java.time.ZoneId

/**
 * One screen: an optional name, birth date and "How is the baby fed?", which
 * only picks the reminder gap offered first. No purchase screen, no account.
 * Joining a shared log is iOS-only (CloudKit), so Android has the one path.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingScreen() {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    var name by rememberSaveable { mutableStateOf("") }
    var hasBirthDate by rememberSaveable { mutableStateOf(false) }
    var birthDate by rememberSaveable { mutableStateOf(LocalDate.now(zone).toEpochDay()) }
    var style by rememberSaveable { mutableStateOf<String?>(null) }
    var picking by rememberSaveable { mutableStateOf(false) }
    var failed by rememberSaveable { mutableStateOf(false) }
    val expecting = style == FeedingStyle.EXPECTING.raw

    Box(Modifier.fillMaxSize().background(palette.paper), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = 560.dp())
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = Tokens.margin, vertical = Tokens.loose),
            verticalArrangement = Arrangement.spacedBy(Tokens.loose),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                listOf(EventKind.FEED, EventKind.WET, EventKind.DIRTY, EventKind.SLEEP).forEach { CareGraphic(it) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Tokens.hair)) {
                Text("Hello, little one.", style = MaterialTheme.typography.headlineLarge, color = palette.ink)
                Text("Feeds, diapers and sleep. A little less to remember.", style = MaterialTheme.typography.bodyLarge, color = palette.ink2)
            }
            Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose), verticalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(40) },
                    label = { Text("Baby's name (optional)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = palette.accent, focusedLabelColor = palette.accent, cursorColor = palette.accent),
                    modifier = Modifier.fillMaxWidth().testTag("onboarding.name"),
                )
                if (!expecting) {
                    Column(Modifier.fillMaxWidth()) {
                        ToggleRow("Add birth date", hasBirthDate, tag = "onboarding.birthToggle", inset = 0.dp()) { hasBirthDate = it }
                        if (hasBirthDate) {
                            TextAction("Birth date: ${Format.monthDayYear(LocalDate.ofEpochDay(birthDate).atStartOfDay(zone).toInstant().toEpochMilli(), zone)}", tag = "onboarding.birthDate") { picking = true }
                        }
                    }
                }
                Text("How is the baby fed?", style = MaterialTheme.typography.labelLarge, color = palette.ink)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                    FeedingStyle.entries.forEach { s ->
                        Chip(s.label, style == s.raw, tag = "onboarding.feeding.${s.raw}") { style = if (style == s.raw) null else s.raw }
                    }
                }
                Text("All optional. You can change these in Settings once you're in.", style = MaterialTheme.typography.bodySmall, color = palette.ink2)
            }
            Text(Guidance.DISCLAIMER, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
            if (failed) Text("Your details are still here. Please try again.", color = palette.notice, style = MaterialTheme.typography.bodySmall)
            PrimaryButton("Start tracking", tag = "onboarding.start") {
                val feeding = FeedingStyle.fromRaw(style)
                val birth = if (hasBirthDate && !expecting) LocalDate.ofEpochDay(birthDate).atStartOfDay(zone).toInstant().toEpochMilli() else null
                if (!graph.events.createChild(name, birth)) {
                    failed = true
                    return@PrimaryButton
                }
                graph.settings.updateFeedingStyle(feeding)
                graph.store.recordSetupStage(born = feeding != FeedingStyle.EXPECTING)
                graph.settings.completeSetup()
            }
            TextAction("Privacy Policy", Modifier.align(Alignment.CenterHorizontally)) { context.openUrl(Links.PRIVACY) }
            Text(" ", textAlign = TextAlign.Center)
        }
    }
    if (picking) {
        DateDialog(LocalDate.ofEpochDay(birthDate), zone, allowFuture = false, onDismiss = { picking = false }) { birthDate = it.toEpochDay() }
    }
}

private fun Int.dp() = androidx.compose.ui.unit.Dp(this.toFloat())
