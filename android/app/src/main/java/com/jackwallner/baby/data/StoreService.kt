package com.jackwallner.baby.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.baby.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.models.PurchaseState
import com.revenuecat.purchases.models.SubscriptionOption
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import kotlin.coroutines.cancellation.CancellationException

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED, FAILED }

enum class PlanKind { MONTHLY, YEARLY, LIFETIME, OTHER }

/** One package on the paywall, with the localised Play price. */
data class PlanOption(
    val id: String,
    val kind: PlanKind,
    val title: String,
    /** "$24.99 / year", "$39.99". */
    val priceLabel: String,
    val priceMicros: Long,
    /** "1-week free trial" when Play offers this account a free phase. */
    val trialLabel: String?,
    val pkg: Package?,
)

/**
 * RevenueCat for Baby+: the `default` offering's monthly, yearly and lifetime
 * packages. Any active entitlement unlocks Baby+ (iOS gates the same way, on
 * the `baby` entitlement). Debug builds use the Test Store key; release
 * builds the Play key; the production key never runs in a debuggable build.
 */
class StoreService(private val context: Context, private val settings: AppSettings) {
    var plans by mutableStateOf<List<PlanOption>>(emptyList())
        private set
    var isLoading by mutableStateOf(false)
        private set
    var loadFailed by mutableStateOf(false)
        private set
    var isPurchasing by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    private var entitled by mutableStateOf(false)

    /** Debug: screenshot runs record no paywall impressions. */
    var suppressImpressions = false
    private val impressions = mutableSetOf<String>()
    private var configured = false

    val isPlus: Boolean get() = entitled || (BuildConfig.DEBUG && settings.debugPlus)
    val isAvailable: Boolean get() = configureIfNeeded()

    private fun configureIfNeeded(): Boolean {
        if (configured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        if (BuildConfig.DEBUG && !key.startsWith("test_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        val builder = PurchasesConfiguration.Builder(context, key)
        // Test Store runs share one tester so test installs don't inflate the
        // live project's customer charts. Never with the Play key: real buyers
        // would share one identity.
        if (key.startsWith("test_")) builder.appUserID(QA_APP_USER_ID)
        Purchases.configure(builder.build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener(::update)
        configured = true
        return true
    }

    private fun update(info: CustomerInfo) {
        // Single premium tier: any active entitlement unlocks Baby+, which
        // survives entitlement renames in the dashboard (as on iOS).
        entitled = info.entitlements.active.isNotEmpty()
    }

    suspend fun start() {
        if (!configureIfNeeded()) {
            loadFailed = true
            return
        }
        runCatching { update(Purchases.sharedInstance.awaitCustomerInfo()) }
        loadPlans()
    }

    suspend fun loadPlans() {
        if (!configureIfNeeded()) {
            loadFailed = true
            return
        }
        isLoading = true
        loadFailed = false
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val offering = offerings["default"] ?: offerings.current
            plans = offering?.availablePackages.orEmpty().map(::plan).sortedBy { it.kind.ordinal }
            loadFailed = plans.isEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            loadFailed = true
        } finally {
            isLoading = false
        }
    }

    private fun plan(pkg: Package): PlanOption {
        val product = pkg.product
        val kind = when (pkg.packageType) {
            PackageType.MONTHLY -> PlanKind.MONTHLY
            PackageType.ANNUAL -> PlanKind.YEARLY
            PackageType.LIFETIME -> PlanKind.LIFETIME
            else -> when (product.period?.unit) {
                Period.Unit.MONTH -> PlanKind.MONTHLY
                Period.Unit.YEAR -> PlanKind.YEARLY
                null -> PlanKind.LIFETIME
                else -> PlanKind.OTHER
            }
        }
        val base = basePlan(product.subscriptionOptions?.toList())
        val price = base?.fullPricePhase?.price ?: product.price
        val suffix = when (kind) {
            PlanKind.MONTHLY -> " / month"
            PlanKind.YEARLY -> " / year"
            else -> ""
        }
        val trial = product.subscriptionOptions?.firstOrNull { it.freePhase != null }?.freePhase?.billingPeriod?.let(::trialLabel)
        val title = when (kind) {
            PlanKind.MONTHLY -> "Monthly"
            PlanKind.YEARLY -> "Yearly"
            PlanKind.LIFETIME -> "Lifetime"
            PlanKind.OTHER -> product.title
        }
        return PlanOption(pkg.identifier, kind, title, price.formatted + suffix, price.amountMicros, trial, pkg)
    }

    private fun basePlan(options: List<SubscriptionOption>?): SubscriptionOption? = options?.firstOrNull { it.isBasePlan }

    private fun trialLabel(period: Period): String = when (period.unit) {
        Period.Unit.DAY -> if (period.value == 7) "1-week free trial" else "${period.value}-day free trial"
        Period.Unit.WEEK -> "${period.value}-week free trial"
        Period.Unit.MONTH -> "${period.value}-month free trial"
        else -> "Free trial"
    }

    fun trackPaywallImpression(id: String) {
        if (suppressImpressions || !impressions.add(id) || !configureIfNeeded()) return
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(CustomPaywallImpressionParams(id)) }
    }

    /** The only setup answer that leaves the phone: `setup_stage` (expecting or born). */
    fun recordSetupStage(born: Boolean) {
        if (!configureIfNeeded()) return
        runCatching { Purchases.sharedInstance.setAttributes(mapOf("setup_stage" to if (born) "born" else "expecting")) }
    }

    suspend fun purchase(activity: Activity, plan: PlanOption): PurchaseOutcome {
        val pkg = plan.pkg ?: return PurchaseOutcome.FAILED
        if (!configureIfNeeded()) {
            errorMessage = "Purchases aren't available in this build."
            return PurchaseOutcome.FAILED
        }
        isPurchasing = true
        errorMessage = null
        return try {
            val trialOption = pkg.product.subscriptionOptions?.firstOrNull { it.freePhase != null }
            val params = if (trialOption != null) PurchaseParams.Builder(activity, trialOption) else PurchaseParams.Builder(activity, pkg)
            val result = Purchases.sharedInstance.awaitPurchase(params.build())
            // Pending Play purchases are not granted until Play reports PURCHASED.
            if (result.storeTransaction.purchaseState == PurchaseState.PENDING) return PurchaseOutcome.PENDING
            update(result.customerInfo)
            PurchaseOutcome.PURCHASED
        } catch (e: PurchasesTransactionException) {
            when {
                e.userCancelled || e.error.code == PurchasesErrorCode.PurchaseCancelledError -> PurchaseOutcome.CANCELLED
                e.error.code == PurchasesErrorCode.PaymentPendingError -> PurchaseOutcome.PENDING
                else -> {
                    errorMessage = e.error.message
                    PurchaseOutcome.FAILED
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            errorMessage = e.message ?: "Purchase didn't complete. You weren't charged."
            PurchaseOutcome.FAILED
        } finally {
            isPurchasing = false
        }
    }

    /** Returns a message for the person: restored, nothing found, or why it failed. */
    suspend fun restore(): String {
        if (!configureIfNeeded()) return "Purchases aren't available in this build."
        return try {
            val info = Purchases.sharedInstance.awaitRestore()
            update(info)
            if (entitled) "Baby+ is active again." else "No Baby+ purchase found for this Google account."
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            e.message ?: "Couldn't restore purchases. Please try again."
        }
    }

    companion object {
        private const val QA_APP_USER_ID = "qa-android"
        const val MANAGE_URL = "https://play.google.com/store/account/subscriptions?package=com.jackwallner.baby"
    }
}
