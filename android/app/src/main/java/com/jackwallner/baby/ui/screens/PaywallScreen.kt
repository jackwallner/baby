package com.jackwallner.baby.ui.screens

import android.app.Activity
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.data.PlanKind
import com.jackwallner.baby.data.PlanOption
import com.jackwallner.baby.data.PurchaseOutcome
import com.jackwallner.baby.model.ConversionCopy
import com.jackwallner.baby.model.PlusFeature
import com.jackwallner.baby.ui.CapsuleReserve
import com.jackwallner.baby.ui.Links
import com.jackwallner.baby.ui.PrimaryButton
import com.jackwallner.baby.ui.SectionLabel
import com.jackwallner.baby.ui.TextAction
import com.jackwallner.baby.ui.openUrl
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import kotlinx.coroutines.launch

/**
 * Upgrade: what Baby+ adds (reports for the doctor), worked-example previews,
 * plans with the billed amount leading, and the renewal disclosure, Restore,
 * Terms and Privacy in every state.
 */
@Composable
fun PaywallScreen() {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val store = graph.store
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selectedId by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        store.trackPaywallImpression("baby_paywall")
        if (store.plans.isEmpty()) store.loadPlans()
    }
    val plans = store.plans
    val selected = plans.firstOrNull { it.id == selectedId } ?: plans.firstOrNull { it.kind == PlanKind.YEARLY } ?: plans.firstOrNull()

    Column(
        Modifier.fillMaxSize().background(palette.paper).verticalScroll(rememberScrollState())
            .padding(horizontal = Tokens.margin).padding(top = Tokens.loose, bottom = CapsuleReserve + Tokens.loose)
            .testTag("paywall"),
        verticalArrangement = Arrangement.spacedBy(Tokens.loose),
    ) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            SectionLabel("Baby+")
            Text("Reports for the pediatrician", style = MaterialTheme.typography.titleLarge, color = palette.ink, textAlign = TextAlign.Center)
            Text("Logging and everything else stay free. Baby+ turns your log into what the doctor asks for.",
                style = MaterialTheme.typography.bodySmall, color = palette.ink2, textAlign = TextAlign.Center)
        }
        ReportPreviews()
        Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose), verticalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
            PlusFeature.entries.forEach { BenefitRow(it) }
        }
        when {
            store.isLoading && plans.isEmpty() -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(color = palette.accent, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(Tokens.tight))
                Text("Loading plans", color = palette.ink2)
            }
            plans.isEmpty() -> Column(Modifier.fillMaxWidth().testTag("paywall.failed"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                Text("Couldn't load plans", style = MaterialTheme.typography.labelLarge, color = palette.ink)
                Text(store.errorMessage ?: "Check your connection and try again.", style = MaterialTheme.typography.bodySmall, color = palette.ink2, textAlign = TextAlign.Center)
                TextAction("Try again", tag = "paywall.retry") { scope.launch { store.loadPlans() } }
            }
            else -> {
                Column(verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                    plans.forEach { plan -> PlanCard(plan, plan.id == selected?.id, savings(plan, plans)) { selectedId = plan.id } }
                }
            }
        }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            if (selected != null) {
                Text(ConversionCopy.billedAmount(selected.priceLabel), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = palette.ink,
                    modifier = Modifier.testTag("paywall.billedAmount"))
                Text(
                    if (selected.kind == PlanKind.LIFETIME) "One payment · Never renews" else ConversionCopy.billedNote(selected.trialLabel, selected.trialLabel != null),
                    style = MaterialTheme.typography.bodySmall, color = palette.ink2,
                )
            }
            PrimaryButton(if (store.isPurchasing) "Opening Google Play…" else ConversionCopy.CTA, enabled = selected != null && !store.isPurchasing, tag = "paywall.cta") {
                val plan = selected ?: return@PrimaryButton
                val activity = context as? Activity ?: return@PrimaryButton
                message = null
                scope.launch {
                    message = when (store.purchase(activity, plan)) {
                        PurchaseOutcome.PURCHASED -> null
                        PurchaseOutcome.PENDING -> ConversionCopy.PENDING
                        PurchaseOutcome.CANCELLED -> ConversionCopy.cancelled(plan.trialLabel != null)
                        PurchaseOutcome.FAILED -> store.errorMessage ?: ConversionCopy.failed(plan.trialLabel != null)
                    }
                }
            }
            Text(disclosure(selected), style = MaterialTheme.typography.labelSmall, color = palette.ink2, textAlign = TextAlign.Center,
                modifier = Modifier.testTag("paywall.disclosure"))
            message?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = palette.notice, textAlign = TextAlign.Center) }
            TextAction("Restore purchases", tag = "paywall.restore") { scope.launch { message = store.restore() } }
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalAlignment = Alignment.CenterVertically) {
                TextAction("Terms of Use", tag = "paywall.terms") { context.openUrl(Links.TERMS) }
                Text("·", color = palette.ink3)
                TextAction("Privacy Policy", tag = "paywall.privacy") { context.openUrl(Links.PRIVACY) }
            }
        }
    }
}

private fun disclosure(plan: PlanOption?): String = when {
    plan == null -> "Prices are shown in your local currency before you buy. Subscriptions renew automatically until cancelled. ${ConversionCopy.HEDGE}"
    plan.kind == PlanKind.LIFETIME -> "${plan.priceLabel}. One-time purchase, no subscription and nothing renews. ${ConversionCopy.HEDGE}"
    else -> "${ConversionCopy.disclosure(plan.trialLabel, plan.priceLabel, plan.trialLabel != null)} ${ConversionCopy.HEDGE}"
}

/** Yearly against twelve months, when both are on offer. */
private fun savings(plan: PlanOption, plans: List<PlanOption>): Int? {
    if (plan.kind != PlanKind.YEARLY) return null
    val monthly = plans.firstOrNull { it.kind == PlanKind.MONTHLY } ?: return null
    val atMonthly = monthly.priceMicros * 12
    if (atMonthly <= plan.priceMicros || plan.priceMicros <= 0) return null
    return ((atMonthly - plan.priceMicros) * 100 / atMonthly).toInt()
}

@Composable
private fun PlanCard(plan: PlanOption, isSelected: Boolean, savingsPercent: Int?, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().graphicBorder(palette, fill = if (isSelected) palette.fill(com.jackwallner.baby.model.EventKind.FEED) else palette.card)
            .clip(Tokens.shape)
            .then(if (isSelected) Modifier.border(Tokens.outlineWidth, palette.accent, Tokens.shape) else Modifier)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .semantics { selected = isSelected }
            .heightIn(min = 64.dp).padding(horizontal = Tokens.loose, vertical = Tokens.spacing)
            .testTag("plan.${plan.kind.name.lowercase()}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(plan.title, style = MaterialTheme.typography.labelLarge, color = palette.ink)
                savingsPercent?.let {
                    Spacer(Modifier.width(Tokens.tight))
                    Text("Save $it%", style = MaterialTheme.typography.labelSmall, color = palette.accent)
                }
            }
            plan.trialLabel?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = palette.ink2) }
            if (plan.kind == PlanKind.LIFETIME) Text("Pay once", style = MaterialTheme.typography.bodySmall, color = palette.ink2)
        }
        Text(plan.priceLabel, style = MaterialTheme.typography.labelLarge, color = palette.ink)
    }
}

@Composable
private fun BenefitRow(feature: PlusFeature) {
    val palette = LocalPalette.current
    Row(verticalAlignment = Alignment.Top) {
        Icon(
            when (feature) {
                PlusFeature.PEDIATRICIAN_SUMMARY -> Icons.Filled.Description
                PlusFeature.TRENDS -> Icons.Filled.BarChart
                PlusFeature.EXPORT -> Icons.Filled.IosShare
            },
            null, tint = palette.accent, modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(Tokens.spacing))
        Column {
            Text(feature.title, style = MaterialTheme.typography.labelLarge, color = palette.ink)
            Text(feature.detail, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
        }
    }
}

/** Three worked-example cards, stamped as examples, before anything is bought. */
@Composable
private fun ReportPreviews() {
    val palette = LocalPalette.current
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
        PreviewCard("Pediatrician summary") {
            Column(Modifier.fillMaxWidth().background(palette.codePaper, Tokens.shape).padding(Tokens.spacing), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Elsa: feeds, diapers and sleep", style = MaterialTheme.typography.labelMedium, color = com.jackwallner.baby.ui.theme.Palette.light.ink)
                listOf("FEEDS / DAY  8.6  longest gap 3h 40m", "WET / DAY  6.2  lowest day 5", "DIRTY / DAY  3.0", "SLEEP / DAY  15h 20m").forEach {
                    Text(it, style = MaterialTheme.typography.labelSmall, color = com.jackwallner.baby.ui.theme.Palette.light.ink2)
                }
                Text("EXAMPLE, NOT YOUR BABY'S DATA", style = MaterialTheme.typography.labelSmall, color = com.jackwallner.baby.ui.theme.Palette.light.accent)
            }
        }
        PreviewCard("Trends") {
            val bars = listOf(7, 9, 8, 10, 8, 9, 11, 8, 9, 10)
            Canvas(Modifier.fillMaxWidth().height(96.dp)) {
                val slot = size.width / bars.size
                bars.forEachIndexed { i, v ->
                    val h = v / 12f * size.height
                    drawRoundRect(palette.feed, Offset(i * slot + slot * 0.2f, size.height - h), Size(slot * 0.6f, h), androidx.compose.ui.geometry.CornerRadius(3f))
                }
            }
        }
        PreviewCard("CSV export") {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                listOf("date,time,kind,side", "2026-10-11,2:00 AM,feed,left", "2026-10-11,3:05 AM,wet,", "2026-10-11,5:10 AM,feed,right").forEach {
                    Text(it, style = MaterialTheme.typography.labelSmall, color = palette.ink2, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun PreviewCard(title: String, content: @Composable () -> Unit) {
    val palette = LocalPalette.current
    Column(Modifier.widthIn(min = 260.dp, max = 260.dp).graphicBorder(palette).padding(Tokens.spacing), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = palette.ink, modifier = Modifier.weight(1f))
            Text("Example", style = MaterialTheme.typography.labelSmall, color = palette.ink2)
        }
        Box(Modifier.fillMaxWidth().height(136.dp)) { content() }
    }
}

/** Shown in place of the paywall's pitch once Baby+ is active. */
@Composable
fun PlusActiveCard() {
    val palette = LocalPalette.current
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CheckCircle, null, tint = palette.accent)
            Spacer(Modifier.width(Tokens.tight))
            Text("Baby+ is active", style = MaterialTheme.typography.labelLarge, color = palette.ink)
        }
        Text("The pediatrician summary, trends and export are unlocked for this Google account.", style = MaterialTheme.typography.bodySmall, color = palette.ink2)
        TextAction("Manage subscription") { context.openUrl(com.jackwallner.baby.data.StoreService.MANAGE_URL) }
    }
}
