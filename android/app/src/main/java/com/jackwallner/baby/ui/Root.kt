package com.jackwallner.baby.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.baby.AppGraph
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.ui.screens.EventEditor
import com.jackwallner.baby.ui.screens.FirstWeeksScreen
import com.jackwallner.baby.ui.screens.HistoryScreen
import com.jackwallner.baby.ui.screens.LogScreen
import com.jackwallner.baby.ui.screens.OnboardingScreen
import com.jackwallner.baby.ui.screens.PaywallScreen
import com.jackwallner.baby.ui.screens.RemindersScreen
import com.jackwallner.baby.ui.screens.ReportsScreen
import com.jackwallner.baby.ui.screens.SettingsScreen
import com.jackwallner.baby.ui.screens.StainHelperScreen
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens

/** What the editor opens on: an existing entry, or a new one of a kind. */
data class EditorRequest(val event: LogEvent? = null, val kind: EventKind = EventKind.FEED)

enum class Tab { LOG, HISTORY, UPGRADE, SETTINGS }

enum class SettingsPage { ROOT, FIRST_WEEKS, STAIN, REMINDERS }

/** Height the floating capsule reserves at the bottom of every tab. */
val CapsuleReserve = Tokens.tabHeight + Tokens.hair * 4 + 8.dp

@Composable
fun Root(graph: AppGraph, pendingTab: Int?, consumedTab: () -> Unit) {
    val palette = LocalPalette.current
    val settings = graph.settings
    val events = graph.events
    if (!settings.hasCompletedSetup || events.child == null) {
        OnboardingScreen()
        return
    }
    var tab by rememberSaveable { mutableStateOf(Tab.LOG) }
    var settingsPage by rememberSaveable { mutableStateOf(SettingsPage.ROOT) }
    var editor by remember { mutableStateOf<EditorRequest?>(null) }
    LaunchedEffect(pendingTab) {
        pendingTab?.let { tab = Tab.entries.getOrElse(it) { Tab.LOG } }
        consumedTab()
    }
    BackHandler(enabled = tab != Tab.LOG || settingsPage != SettingsPage.ROOT) {
        if (tab == Tab.SETTINGS && settingsPage != SettingsPage.ROOT) settingsPage = SettingsPage.ROOT else tab = Tab.LOG
    }
    Box(Modifier.fillMaxSize().background(palette.paper)) {
        Box(Modifier.fillMaxSize().statusBarsPadding()) {
            when (tab) {
                Tab.LOG -> LogScreen(onEdit = { editor = it })
                Tab.HISTORY -> HistoryScreen(onEdit = { editor = it }, onUnlock = { tab = Tab.UPGRADE })
                Tab.UPGRADE -> if (graph.store.isPlus) ReportsScreen() else PaywallScreen()
                Tab.SETTINGS -> when (settingsPage) {
                    SettingsPage.ROOT -> SettingsScreen(open = { settingsPage = it }, onSeePlus = { tab = Tab.UPGRADE })
                    SettingsPage.FIRST_WEEKS -> FirstWeeksScreen(onBack = { settingsPage = SettingsPage.ROOT })
                    SettingsPage.STAIN -> StainHelperScreen(onBack = { settingsPage = SettingsPage.ROOT })
                    SettingsPage.REMINDERS -> RemindersScreen(onBack = { settingsPage = SettingsPage.ROOT })
                }
            }
        }
        UndoToast(Modifier.align(Alignment.TopCenter))
        Capsule(tab, graph.store.isPlus, Modifier.align(Alignment.BottomCenter)) {
            if (it == tab && it == Tab.SETTINGS) settingsPage = SettingsPage.ROOT
            tab = it
        }
    }
    editor?.let { request -> EventEditor(request, onDismiss = { editor = null }) }
}

/** One small translucent capsule: Log, History, Upgrade (Reports for Baby+), Settings. */
@Composable
private fun Capsule(selected: Tab, isPlus: Boolean, modifier: Modifier, onSelect: (Tab) -> Unit) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(50)
    Row(
        modifier
            .navigationBarsPadding()
            .padding(bottom = Tokens.tight)
            .clip(shape)
            .background(palette.card.copy(alpha = 0.94f))
            .border(Tokens.hairlineWidth, palette.edge, shape)
            .padding(Tokens.hair),
        horizontalArrangement = Arrangement.spacedBy(Tokens.hair),
    ) {
        TabButton(Tab.LOG, "Log", Icons.Filled.AddCircle, selected, onSelect)
        TabButton(Tab.HISTORY, "History", Icons.AutoMirrored.Filled.List, selected, onSelect)
        TabButton(Tab.UPGRADE, if (isPlus) "Reports" else "Upgrade", if (isPlus) Icons.Filled.BarChart else Icons.Filled.Star, selected, onSelect)
        TabButton(Tab.SETTINGS, "Settings", Icons.Filled.Settings, selected, onSelect)
    }
}

@Composable
private fun TabButton(tab: Tab, label: String, icon: ImageVector, selected: Tab, onSelect: (Tab) -> Unit) {
    val palette = LocalPalette.current
    val isOn = tab == selected
    Column(
        Modifier
            .width(Tokens.tabWidth)
            .height(Tokens.tabHeight)
            .clip(RoundedCornerShape(50))
            .background(if (isOn) palette.cardElevated else palette.card.copy(alpha = 0f))
            .clickable(role = Role.Tab) { onSelect(tab) }
            .semantics { this.selected = isOn }
            .testTag("tab.${tab.name.lowercase()}"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (isOn) palette.accent else palette.ink2, modifier = Modifier.size(18.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = if (isOn) palette.ink else palette.ink2)
    }
}

/** Pinned to the top so it never lands over the log controls. */
@Composable
private fun UndoToast(modifier: Modifier) {
    val graph = com.jackwallner.baby.LocalGraph.current
    val palette = LocalPalette.current
    val logged = graph.events.lastLogged
    AnimatedVisibility(
        logged != null,
        modifier.statusBarsPadding().padding(top = Tokens.tight).padding(horizontal = Tokens.margin),
        enter = fadeIn() + slideInVertically { -it / 2 },
        exit = fadeOut() + slideOutVertically { -it / 2 },
    ) {
        val shown = remember(logged) { logged } ?: return@AnimatedVisibility
        Row(
            Modifier
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(50))
                .background(palette.ink)
                .padding(start = Tokens.loose, end = Tokens.hair)
                .testTag("undoToast"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(shown.message, color = palette.paper, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(Tokens.tight))
            TextAction("Undo", color = palette.actionFill, tag = "undo") { graph.events.undoLast() }
        }
    }
}
