package com.jackwallner.baby

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.jackwallner.baby.data.Appearance
import com.jackwallner.baby.data.Reminders
import com.jackwallner.baby.model.ReminderPlan
import com.jackwallner.baby.ui.Root
import com.jackwallner.baby.ui.theme.BabyTheme
import com.jackwallner.baby.ui.theme.Palette
import kotlinx.coroutines.launch

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No graph") }

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : ComponentActivity() {
    private val graph: AppGraph get() = (application as BabyApplication).graph
    /** A tab to open: from a debug launch option, or a checkup note (Upgrade/Reports). */
    private var pendingTab by mutableStateOf<Int?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            pendingTab = DebugLaunchOptions.apply(graph, intent) ?: routeTab(intent)
        }
        graph.scope.launch { graph.store.start() }
        // Animator scale 0 (Remove animations) is Android's Reduce Motion.
        val reduceMotion = Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        setContent {
            val appearance = graph.settings.appearance
            val systemDark = isSystemInDarkTheme()
            val palette = when (appearance) {
                Appearance.SYSTEM -> if (systemDark) Palette.dark else Palette.light
                Appearance.LIGHT -> Palette.light
                Appearance.DARK -> Palette.dark
                Appearance.NIGHT -> Palette.night
            }
            LaunchedEffect(palette.isDark) {
                val bars = if (palette.isDark) SystemBarStyle.dark(Color.TRANSPARENT) else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = bars, navigationBarStyle = bars)
            }
            CompositionLocalProvider(LocalGraph provides graph) {
                BabyTheme(palette, reduceMotion) {
                    // Test tags double as resource ids for UI Automator and screenshot scripts.
                    Box(Modifier.semantics { testTagsAsResourceId = true }) {
                        Root(graph, pendingTab) { pendingTab = null }
                    }
                }
            }
        }
    }

    private fun routeTab(intent: Intent?): Int? =
        if (intent?.getStringExtra(Reminders.EXTRA_ROUTE) == ReminderPlan.CHECKUP_ROUTE) 2 else null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        routeTab(intent)?.let { pendingTab = it }
    }

    override fun onResume() {
        super.onResume()
        // Back from a long nap: elapsed times and the totals day must be right on first sight.
        graph.events.refresh()
    }
}
