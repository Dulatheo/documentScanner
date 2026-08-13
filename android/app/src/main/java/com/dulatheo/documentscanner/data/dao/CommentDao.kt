package com.dulatheo.documentscanner.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.dulatheo.documentscanner.data.model.CommentEntity

@Dao
interface CommentDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(comment: CommentEntity)

    @Query("SELECT * FROM comments WHERE documentId = :documentId ORDER BY createdAt DESC")
    suspend fun forDocument(documentId: String): List<CommentEntity>
}
