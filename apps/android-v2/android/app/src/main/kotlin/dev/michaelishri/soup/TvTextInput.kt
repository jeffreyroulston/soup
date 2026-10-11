package dev.michaelishri.soup

import android.app.Activity
import android.app.Dialog
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Own the TV editor and IME in one native window, outside Flutter key routing.
 * Drawn with Soup v2's tokens (dark glass card, ink text, accent cursor) so it
 * matches the Flutter UI behind it.
 */
class TvTextInput(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var dialog: Dialog? = null

    private val isTelevision: Boolean
        get() = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isTelevision" -> result.success(isTelevision)
            "dismiss" -> {
                dismiss()
                result.success(null)
            }
            "edit" -> {
                if (!isTelevision) {
                    result.error("not_television", "TV editing is unavailable on this device.", null)
                    return
                }
                if (dialog != null || activity.isFinishing || activity.isDestroyed) {
                    result.error("editor_unavailable", "The TV editor is already open or unavailable.", null)
                    return
                }
                showEditor(call, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun dp(value: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, activity.resources.displayMetrics).toInt()

    /** Manrope from the Flutter bundle at [weight]; the system font if it can't load. */
    private fun manrope(weight: Int): Typeface = try {
        Typeface.Builder(activity.assets, FONT_ASSET)
            .setFontVariationSettings("'wght' $weight")
            .build()
    } catch (_: Exception) {
        Typeface.create(Typeface.DEFAULT, weight, false)
    }

    private fun rounded(color: Int, radius: Float, stroke: Int = 0, strokeColor: Int = 0) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
            if (stroke > 0) setStroke(stroke, strokeColor)
        }

    private fun focusStates(focused: GradientDrawable, normal: GradientDrawable) =
        StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), focused)
            addState(intArrayOf(), normal)
        }

    private fun button(label: String, primary: Boolean, onClick: () -> Unit) =
        TextView(activity).apply {
            text = label
            gravity = Gravity.CENTER
            isFocusable = true
            isClickable = true
            typeface = manrope(800)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setPadding(dp(28f), 0, dp(28f), 0)
            minWidth = dp(120f)
            // Focus is the only cue a remote has, so it inverts to the ink fill.
            background = focusStates(
                rounded(INK, 12f),
                if (primary) rounded(GLASS_STRONG, 12f) else rounded(GLASS, 12f),
            )
            setTextColor(
                ColorStateList(
                    arrayOf(intArrayOf(android.R.attr.state_focused), intArrayOf()),
                    intArrayOf(CANVAS, INK),
                ),
            )
            setOnClickListener { onClick() }
        }

    private fun showEditor(call: MethodCall, result: MethodChannel.Result) {
        val label = call.argument<String>("label") ?: "Text"
        val password = call.argument<Boolean>("obscureText") == true
        val next = call.argument<Boolean>("next") == true
        val current = Dialog(activity, R.style.TvTextInputTheme)
        var submitted = false
        val editor = object : EditText(activity) {
            override fun onKeyPreIme(keyCode: Int, event: KeyEvent): Boolean {
                if (keyCode == KeyEvent.KEYCODE_BACK) {
                    if (event.action == KeyEvent.ACTION_UP) current.dismiss()
                    return true
                }
                return super.onKeyPreIme(keyCode, event)
            }
        }.apply {
            setSingleLine(true)
            inputType = InputType.TYPE_CLASS_TEXT or when {
                password -> InputType.TYPE_TEXT_VARIATION_PASSWORD
                call.argument<Boolean>("isUrl") == true -> InputType.TYPE_TEXT_VARIATION_URI
                else -> InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            }
            imeOptions = (if (next) EditorInfo.IME_ACTION_NEXT else EditorInfo.IME_ACTION_DONE) or
                EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            contentDescription = label
            hint = label
            typeface = manrope(600)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setTextColor(INK)
            setHintTextColor(MUTED_HINT)
            highlightColor = ACCENT_SELECTION
            textCursorDrawable = rounded(ACCENT, 1f).apply { setSize(dp(2f), dp(24f)) }
            background = focusStates(
                rounded(FIELD_FOCUSED, 12f, dp(2f), INK),
                rounded(FIELD, 12f),
            )
            setPadding(dp(18f), dp(14f), dp(18f), dp(14f))
            setText(call.argument<String>("text") ?: "")
            setSelection(text.length)
        }
        val title = TextView(activity).apply {
            text = label
            typeface = manrope(800)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            setTextColor(INK)
            letterSpacing = -0.02f
        }
        val actions = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            addView(button("Back", primary = false) { current.dismiss() }, LinearLayout.LayoutParams(-2, dp(52f)))
            addView(
                button(if (next) "Next" else "Done", primary = true) {
                    submitted = true
                    current.dismiss()
                },
                LinearLayout.LayoutParams(-2, dp(52f)).apply { marginStart = dp(12f) },
            )
        }
        val card = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(CARD, 28f, dp(1f), CARD_STROKE)
            setPadding(dp(32f), dp(28f), dp(32f), dp(28f))
            addView(title, LinearLayout.LayoutParams(-1, -2))
            addView(editor, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(18f) })
            addView(actions, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(22f) })
        }
        current.setContentView(card)
        current.setCancelable(true)
        current.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setLayout(dp(560f), ViewGroup.LayoutParams.WRAP_CONTENT)
            // Sit above the TV keyboard, which takes the lower half of the screen.
            setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
            attributes = attributes.apply { y = dp(48f) }
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setDimAmount(0.6f)
            setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING or
                    WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE,
            )
        }
        dialog = current
        current.setOnDismissListener {
            if (dialog === current) dialog = null
            // Back preserves the draft, but never submits or changes the setup step.
            val text = editor.text.toString()
            editor.text.clear()
            result.success(mapOf("text" to text, "submitted" to submitted))
        }
        editor.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_DONE || action == EditorInfo.IME_ACTION_NEXT) {
                submitted = true
                current.dismiss()
                true
            } else {
                false
            }
        }
        current.setOnShowListener {
            editor.requestFocus()
            editor.post {
                if (current.isShowing) {
                    activity.getSystemService(InputMethodManager::class.java)
                        .showSoftInput(editor, InputMethodManager.SHOW_IMPLICIT)
                }
            }
        }
        current.show()
    }

    fun dismiss() {
        dialog?.dismiss()
    }

    private companion object {
        const val FONT_ASSET = "flutter_assets/assets/fonts/Manrope-Variable.ttf"

        // Soup v2 tokens (apps/android-v2/lib/src/ui/theme/soup_tokens.dart).
        val CANVAS = Color.parseColor("#0A0A0B")
        val INK = Color.parseColor("#F5F5F7")
        val MUTED_HINT = Color.parseColor("#99A1A1A6")
        val ACCENT = Color.parseColor("#FC7814")
        val ACCENT_SELECTION = Color.parseColor("#66FC7814")
        val CARD = Color.parseColor("#F21E1E20")
        val CARD_STROKE = Color.parseColor("#1AFFFFFF")
        val FIELD = Color.parseColor("#1AFFFFFF")
        val FIELD_FOCUSED = Color.parseColor("#26FFFFFF")
        val GLASS = Color.parseColor("#1AFFFFFF")
        val GLASS_STRONG = Color.parseColor("#2EFFFFFF")
    }
}
