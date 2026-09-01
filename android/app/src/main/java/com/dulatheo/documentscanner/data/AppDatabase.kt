package com.dulatheo.documentscanner.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.dulatheo.documentscanner.data.dao.CommentDao
import com.dulatheo.documentscanner.data.dao.DocumentDao
import com.dulatheo.documentscanner.data.dao.PageDao
import com.dulatheo.documentscanner.data.model.CommentEntity
import com.dulatheo.documentscanner.data.model.DocumentEntity
import com.dulatheo.documentscanner.data.model.PageEntity

@Database(
    entities = [DocumentEntity::class, PageEntity::class, CommentEntity::class],
    version = 2,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun documentDao(): DocumentDao
    abstract fun pageDao(): PageDao
    abstract fun commentDao(): CommentDao

    companion object {
        @Volatile
        private var instance: AppDatabase? = null

        fun get(context: Context): AppDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "documentscanner.db",
                )
                    // No shipped release depends on this schema surviving
                    // an upgrade yet (pre-release, exportSchema = false) —
                    // a real migration path can replace this once that's
                    // no longer true. Added for PageEntity.brightness/
                    // contrast (DESIGN_SPEC §4.3 "Adjust tool").
                    .fallbackToDestructiveMigration()
                    .build().also { instance = it }
            }
    }
}
