package com.jackwallner.baby.ui.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.baby.model.EventKind

/** The one place a number is decided. Port of iOS `AppTheme`: a four-point scale, one 20dp margin and radius. */
object Tokens {
    val hair = 4.dp
    val tight = 8.dp
    val spacing = 12.dp
    val loose = 20.dp
    val margin = 20.dp
    val radius = 20.dp
    val logButtonHeight = 88.dp
    val maxLogButtonHeight = 124.dp
    val minLogButtonHeight = 52.dp
    val compactCardPadding = 16.dp
    val outlineWidth = 2.dp
    val hairlineWidth = 1.dp
    val shadowOffset = 3.dp
    val graphicSize = 44.dp
    val ctaHeight = 52.dp
    val tabHeight = 48.dp
    val tabWidth = 72.dp
    val chartHeight = 160.dp
    val legendDot = 8.dp
    val cellHeight = 10.dp
    val cellGap = 2.dp
    val cellRadius = 3.dp
    val minTouch = 48.dp
    val previewBlur = 6.dp
    const val PARTIAL_BAR_ALPHA = 0.45f
    val shape = RoundedCornerShape(radius)
}

@Immutable
data class Palette(
    val paper: Color,
    val card: Color,
    val cardElevated: Color,
    val ink: Color,
    val ink2: Color,
    val ink3: Color,
    val feed: Color,
    val wet: Color,
    val dirty: Color,
    val sleep: Color,
    val accent: Color,
    val notice: Color,
    val outline: Color,
    val edge: Color,
    val separator: Color,
    /** The offset "physical edge" shadow. Only light has one. */
    val shadow: Color?,
    val actionFill: Color,
    val buttonInk: Color,
    val codePaper: Color,
    val isDark: Boolean,
) {
    fun color(kind: EventKind): Color = when (kind) {
        EventKind.FEED -> feed
        EventKind.WET -> wet
        EventKind.DIRTY -> dirty
        EventKind.SLEEP -> sleep
        EventKind.WEIGHT -> ink2
    }

    /** The soft fill behind a kind's button, flattened onto the card colour. */
    fun fill(kind: EventKind): Color = blend(card, color(kind), 0.20f)
    fun strongFill(kind: EventKind): Color = blend(card, color(kind), 0.42f)

    private fun blend(base: Color, over: Color, alpha: Float) = Color(
        red = base.red + (over.red - base.red) * alpha,
        green = base.green + (over.green - base.green) * alpha,
        blue = base.blue + (over.blue - base.blue) * alpha,
    )

    companion object {
        private fun c(r: Double, g: Double, b: Double) = Color(r.toFloat(), g.toFloat(), b.toFloat())

        val light = Palette(
            paper = c(0.97, 0.96, 0.94), card = c(1.0, 1.0, 1.0), cardElevated = c(0.94, 0.93, 0.91),
            ink = c(0.11, 0.10, 0.09), ink2 = c(0.42, 0.40, 0.38), ink3 = c(0.43, 0.41, 0.39),
            feed = c(0.58, 0.35, 0.10), wet = c(0.18, 0.43, 0.76), dirty = c(0.52, 0.38, 0.22), sleep = c(0.36, 0.34, 0.78),
            accent = c(0.70, 0.30, 0.20), notice = c(0.60, 0.36, 0.06), outline = c(0.14, 0.12, 0.11), edge = c(0.14, 0.12, 0.11),
            separator = c(0.85, 0.83, 0.80), shadow = c(0.14, 0.12, 0.11), actionFill = c(1.0, 0.72, 0.60), buttonInk = c(0.10, 0.10, 0.10),
            codePaper = c(1.0, 1.0, 1.0), isDark = false,
        )
        val dark = Palette(
            paper = c(0.07, 0.065, 0.06), card = c(0.125, 0.12, 0.11), cardElevated = c(0.17, 0.162, 0.15),
            ink = c(0.95, 0.94, 0.92), ink2 = c(0.68, 0.66, 0.63), ink3 = c(0.62, 0.60, 0.58),
            feed = c(0.95, 0.68, 0.30), wet = c(0.45, 0.68, 0.95), dirty = c(0.72, 0.58, 0.40), sleep = c(0.62, 0.60, 0.95),
            accent = c(0.95, 0.55, 0.42), notice = c(0.95, 0.68, 0.30), outline = c(0.56, 0.53, 0.50), edge = c(0.25, 0.235, 0.22),
            separator = c(0.22, 0.21, 0.20), shadow = null, actionFill = c(0.92, 0.63, 0.51), buttonInk = c(0.10, 0.10, 0.10),
            codePaper = c(0.90, 0.89, 0.87), isDark = true,
        )
        /** Dim warm umber, no pure white, no saturated blue: feeds in a dark room. */
        val night = Palette(
            paper = c(0.045, 0.032, 0.022), card = c(0.095, 0.068, 0.048), cardElevated = c(0.13, 0.095, 0.068),
            ink = c(0.86, 0.68, 0.52), ink2 = c(0.64, 0.49, 0.37), ink3 = c(0.56, 0.43, 0.33),
            feed = c(0.84, 0.56, 0.26), wet = c(0.46, 0.60, 0.58), dirty = c(0.62, 0.56, 0.36), sleep = c(0.64, 0.50, 0.58),
            accent = c(0.84, 0.48, 0.34), notice = c(0.84, 0.56, 0.26), outline = c(0.52, 0.40, 0.30), edge = c(0.20, 0.145, 0.10),
            separator = c(0.17, 0.125, 0.09), shadow = null, actionFill = c(0.70, 0.43, 0.30), buttonInk = c(0.07, 0.045, 0.03),
            codePaper = c(0.74, 0.66, 0.56), isDark = true,
        )
    }
}

val LocalPalette = staticCompositionLocalOf { Palette.light }
val LocalReduceMotion = staticCompositionLocalOf { false }

@Composable
fun BabyTheme(palette: Palette, reduceMotion: Boolean, content: @Composable () -> Unit) {
    val scheme = if (palette.isDark) {
        darkColorScheme(primary = palette.accent, onPrimary = palette.buttonInk, background = palette.paper, surface = palette.card,
            onSurface = palette.ink, onBackground = palette.ink, surfaceVariant = palette.cardElevated, onSurfaceVariant = palette.ink2,
            outline = palette.edge, outlineVariant = palette.separator, secondaryContainer = palette.cardElevated, onSecondaryContainer = palette.ink,
            surfaceContainerHigh = palette.card, surfaceContainerHighest = palette.cardElevated, surfaceContainer = palette.card)
    } else {
        lightColorScheme(primary = palette.accent, onPrimary = Color.White, background = palette.paper, surface = palette.card,
            onSurface = palette.ink, onBackground = palette.ink, surfaceVariant = palette.cardElevated, onSurfaceVariant = palette.ink2,
            outline = palette.edge, outlineVariant = palette.separator, secondaryContainer = palette.cardElevated, onSecondaryContainer = palette.ink,
            surfaceContainerHigh = palette.card, surfaceContainerHighest = palette.cardElevated, surfaceContainer = palette.card)
    }
    val type = Typography(
        headlineLarge = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, lineHeight = 40.sp),
        titleLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold),
        titleMedium = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
        bodyLarge = TextStyle(fontSize = 17.sp),
        bodyMedium = TextStyle(fontSize = 15.sp),
        bodySmall = TextStyle(fontSize = 13.sp),
        labelLarge = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
        labelMedium = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
        labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium),
    )
    CompositionLocalProvider(LocalPalette provides palette, LocalReduceMotion provides reduceMotion) {
        MaterialTheme(colorScheme = scheme, typography = type, content = content)
    }
}

/**
 * The firm card edge: an outline, plus the offset ink shadow in light only.
 * The shadow is drawn behind the opaque fill, never under the text.
 */
fun Modifier.graphicBorder(palette: Palette, fill: Color = palette.card, radius: Dp = Tokens.radius): Modifier = this
    .drawBehind {
        val r = CornerRadius(radius.toPx())
        palette.shadow?.let { shadow ->
            val o = Tokens.shadowOffset.toPx()
            drawRoundRect(shadow, topLeft = Offset(o, o), size = Size(size.width, size.height), cornerRadius = r)
        }
        drawRoundRect(fill, cornerRadius = r)
    }
    .border(
        BorderStroke(if (palette.shadow != null) Tokens.outlineWidth else Tokens.hairlineWidth, palette.edge),
        RoundedCornerShape(radius),
    )

@Composable
fun Card(modifier: Modifier = Modifier, padding: Dp = Tokens.loose, content: @Composable ColumnScope.() -> Unit) {
    val palette = LocalPalette.current
    Column(modifier.graphicBorder(palette).padding(padding), content = content)
}

/** Small outlined care illustrations beside the labels, drawn from the iOS paths. */
@Composable
fun CareGraphic(kind: EventKind, modifier: Modifier = Modifier, size: Dp = Tokens.graphicSize) {
    val palette = LocalPalette.current
    Box(
        modifier
            .size(size)
            .background(palette.card, CircleShape)
            .border(Tokens.outlineWidth, palette.outline, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (kind == EventKind.FEED) {
            Icon(Icons.Filled.Favorite, contentDescription = null, tint = palette.feed, modifier = Modifier.size(size * 0.45f))
        } else {
            Canvas(Modifier.size(size).padding(Tokens.tight)) {
                val path = careGlyph(kind, this.size)
                drawPath(path, palette.fill(kind))
                drawPath(path, palette.outline, style = Stroke(Tokens.outlineWidth.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
    }
}

private fun careGlyph(kind: EventKind, s: Size): Path = Path().apply {
    fun x(v: Float) = v * s.width
    fun y(v: Float) = v * s.height
    when (kind) {
        EventKind.WET -> {
            moveTo(x(0.50f), y(0.04f))
            cubicTo(x(0.28f), y(0.38f), x(-0.13f), y(0.85f), x(0.50f), y(0.95f))
            cubicTo(x(1.13f), y(0.85f), x(0.72f), y(0.38f), x(0.50f), y(0.04f))
            close()
        }
        EventKind.DIRTY -> {
            moveTo(x(0.08f), y(0.23f)); lineTo(x(0.92f), y(0.23f))
            quadraticTo(x(0.92f), y(0.62f), x(0.70f), y(0.86f)); lineTo(x(0.30f), y(0.86f))
            quadraticTo(x(0.08f), y(0.62f), x(0.08f), y(0.23f)); close()
            moveTo(x(0.09f), y(0.40f)); lineTo(x(0.91f), y(0.40f))
            moveTo(x(0.12f), y(0.56f)); quadraticTo(x(0.37f), y(0.56f), x(0.34f), y(0.85f))
            moveTo(x(0.88f), y(0.56f)); quadraticTo(x(0.63f), y(0.56f), x(0.66f), y(0.85f))
        }
        EventKind.SLEEP -> {
            moveTo(x(0.67f), y(0.07f))
            cubicTo(x(-0.22f), y(-0.06f), x(0.04f), y(1.31f), x(0.87f), y(0.78f))
            cubicTo(x(0.30f), y(0.91f), x(0.23f), y(0.26f), x(0.67f), y(0.07f))
            close()
        }
        EventKind.WEIGHT -> {
            addRoundRect(androidx.compose.ui.geometry.RoundRect(x(0.12f), y(0.15f), x(0.88f), y(0.85f), CornerRadius(x(0.15f), y(0.15f))))
            moveTo(x(0.50f), y(0.48f)); lineTo(x(0.65f), y(0.30f))
        }
        EventKind.FEED -> {
            moveTo(x(0.39f), y(0.20f)); lineTo(x(0.39f), y(0.10f))
            quadraticTo(x(0.50f), y(-0.04f), x(0.61f), y(0.10f)); lineTo(x(0.61f), y(0.20f))
            lineTo(x(0.72f), y(0.28f)); lineTo(x(0.72f), y(0.85f))
            quadraticTo(x(0.50f), y(1.02f), x(0.28f), y(0.85f)); lineTo(x(0.28f), y(0.28f)); close()
        }
    }
}
