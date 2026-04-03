package com.galleryze.app.channel.streams.platformtodart

import com.galleryze.app.channel.streams.BaseStreamHandler
import com.galleryze.app.utils.LogUtils

class WindowChangeStreamHandler : BaseStreamHandler() {
    fun notifyCutoutInsetsChange() = success(CODE_CUTOUT_INSETS)
    fun notifyWindowModeChange() = success(CODE_WINDOW_MODE)

    override val logTag = LOG_TAG

    companion object {
        private val LOG_TAG = LogUtils.createTag<ErrorStreamHandler>()
        const val CHANNEL = "deckers.thibault/aves/window_change"

        private const val CODE_CUTOUT_INSETS = "cutout_insets"
        private const val CODE_WINDOW_MODE = "window_mode"
    }
}