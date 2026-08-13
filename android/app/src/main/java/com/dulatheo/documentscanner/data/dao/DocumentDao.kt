package com.dulatheo.documentscanner.data.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.dulatheo.documentscanner.data.model.DocumentEntity
import com.dulatheo.documentscanner.data.model.DocumentWithDetails
import kotlinx.coroutines.flow.Flow

@Dao
interface DocumentDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(document: DocumentEntity)

    @Update
    suspend fun update(document: DocumentEntity)

    @Delete
    suspend fun delete(document: DocumentEntity)

    @Transaction
    @Query("SELECT * FROM documents ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<DocumentWithDetails>>

    @Transaction
    @Query("SELECT * FROM documents WHERE id = :id")
    fun observeById(id: String): Flow<DocumentWithDetails?>

    @Transaction
    @Query("SELECT * FROM documents WHERE id = :id")
    suspend fun getById(id: String): DocumentWithDetails?

    @Query("SELECT COUNT(*) FROM documents")
    fun observeCount(): Flow<Int>
}
