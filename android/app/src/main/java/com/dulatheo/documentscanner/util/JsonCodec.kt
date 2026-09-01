package com.dulatheo.documentscanner.util

import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.OcrWord
import com.dulatheo.documentscanner.data.model.SigPoint
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.data.model.SignatureStroke
import org.json.JSONArray
import org.json.JSONObject

/**
 * Hand-rolled JSON (de)serialization for the small nested structures stored
 * as text columns on [com.dulatheo.documentscanner.data.model.PageEntity]
 * (Signature, OCR line regions). Uses `org.json`, already on the Android
 * platform, to avoid pulling in a serialization library for two small types.
 */
object JsonCodec {

    fun encodeOcrLines(lines: List<OcrLine>): String {
        val arr = JSONArray()
        for (l in lines) {
            arr.put(
                JSONObject().apply {
                    put("text", l.text)
                    put("left", l.left)
                    put("top", l.top)
                    put("right", l.right)
                    put("bottom", l.bottom)
                    put("highlighted", l.highlighted)
                    val wordsArr = JSONArray()
                    for (w in l.words) {
                        wordsArr.put(
                            JSONObject().apply {
                                put("text", w.text)
                                put("left", w.left)
                                put("top", w.top)
                                put("right", w.right)
                                put("bottom", w.bottom)
                            }
                        )
                    }
                    put("words", wordsArr)
                }
            )
        }
        return arr.toString()
    }

    fun decodeOcrLines(json: String?): List<OcrLine> {
        if (json.isNullOrBlank()) return emptyList()
        return runCatching {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                val wordsArr = o.optJSONArray("words") ?: JSONArray()
                val words = (0 until wordsArr.length()).map { j ->
                    val wo = wordsArr.getJSONObject(j)
                    OcrWord(
                        text = wo.optString("text"),
                        left = wo.optDouble("left").toFloat(),
                        top = wo.optDouble("top").toFloat(),
                        right = wo.optDouble("right").toFloat(),
                        bottom = wo.optDouble("bottom").toFloat(),
                    )
                }
                OcrLine(
                    text = o.optString("text"),
                    left = o.optDouble("left").toFloat(),
                    top = o.optDouble("top").toFloat(),
                    right = o.optDouble("right").toFloat(),
                    bottom = o.optDouble("bottom").toFloat(),
                    highlighted = o.optBoolean("highlighted", false),
                    words = words,
                )
            }
        }.getOrDefault(emptyList())
    }

    fun encodeSignature(sig: Signature): String {
        val strokesArr = JSONArray()
        for (s in sig.strokes) {
            val ptsArr = JSONArray()
            for (p in s.points) {
                ptsArr.put(JSONObject().apply { put("x", p.x); put("y", p.y) })
            }
            strokesArr.put(
                JSONObject().apply {
                    put("points", ptsArr)
                    put("colorHex", s.colorHex)
                    put("widthPx", s.widthPx)
                }
            )
        }
        return JSONObject().apply {
            put("strokes", strokesArr)
            put("colorHex", sig.colorHex)
            put("thickness", sig.thickness)
            put("canvasWidth", sig.canvasWidth)
            put("canvasHeight", sig.canvasHeight)
            put("x", sig.x)
            put("y", sig.y)
            put("width", sig.width)
            put("height", sig.height)
            put("rotation", sig.rotation)
        }.toString()
    }

    fun decodeSignature(json: String?): Signature? {
        if (json.isNullOrBlank()) return null
        return runCatching {
            val o = JSONObject(json)
            val strokesArr = o.optJSONArray("strokes") ?: JSONArray()
            val strokes = (0 until strokesArr.length()).map { i ->
                val so = strokesArr.getJSONObject(i)
                val ptsArr = so.optJSONArray("points") ?: JSONArray()
                val points = (0 until ptsArr.length()).map { j ->
                    val po = ptsArr.getJSONObject(j)
                    SigPoint(po.optDouble("x").toFloat(), po.optDouble("y").toFloat())
                }
                SignatureStroke(
                    points = points,
                    colorHex = so.optString("colorHex", "#171614"),
                    widthPx = so.optDouble("widthPx", 5.0).toFloat(),
                )
            }
            Signature(
                strokes = strokes,
                colorHex = o.optString("colorHex", "#171614"),
                thickness = o.optDouble("thickness", 5.0).toFloat(),
                canvasWidth = o.optDouble("canvasWidth", 834.0).toFloat(),
                canvasHeight = o.optDouble("canvasHeight", 250.0).toFloat(),
                x = o.optDouble("x").toFloat(),
                y = o.optDouble("y").toFloat(),
                width = o.optDouble("width", 0.3).toFloat(),
                height = o.optDouble("height", 0.1).toFloat(),
                rotation = o.optDouble("rotation", 0.0).toFloat(),
            )
        }.getOrNull()
    }
}
