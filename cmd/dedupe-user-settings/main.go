package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	_ "github.com/go-sql-driver/mysql"
)

// UserSetting represents a record in the user_settings table
type UserSetting struct {
	UserID       int64
	Locale       string
	SettingName  string
	AssocType    sql.NullInt64
	AssocID      sql.NullInt64
	SettingValue sql.NullString
	SettingType  string
}

// UserSettingKey is the composite key for a user setting
type UserSettingKey struct {
	UserID      int64
	Locale      string
	SettingName string
	AssocType   int64
	AssocID     int64
}

func main() {
	dsn := os.Getenv("DSN")
	if dsn == "" {
		log.Fatal("DSN environment variable is not set")
	}

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("failed to open database: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("failed to ping database: %v", err)
	}

	fmt.Println("Successfully connected to the database")

	// Find and delete duplicates
	if err := findAndDeleteDuplicates(db); err != nil {
		log.Fatalf("failed to find and delete duplicates: %v", err)
	}
}

func findAndDeleteDuplicates(db *sql.DB) error {
	rows, err := db.Query("SELECT user_id, locale, setting_name, assoc_type, assoc_id, setting_value, setting_type FROM user_settings ORDER BY user_id, locale, setting_name, assoc_type, assoc_id")
	if err != nil {
		return fmt.Errorf("failed to query user_settings: %w", err)
	}
	defer rows.Close()

	settingsMap := make(map[UserSettingKey][]UserSetting)

	for rows.Next() {
		var s UserSetting
		if err := rows.Scan(&s.UserID, &s.Locale, &s.SettingName, &s.AssocType, &s.AssocID, &s.SettingValue, &s.SettingType); err != nil {
			return fmt.Errorf("failed to scan row: %w", err)
		}
		key := UserSettingKey{
			UserID:      s.UserID,
			Locale:      s.Locale,
			SettingName: s.SettingName,
			AssocType:   s.AssocType.Int64,
			AssocID:     s.AssocID.Int64,
		}
		settingsMap[key] = append(settingsMap[key], s)
	}

	if err := rows.Err(); err != nil {
		return fmt.Errorf("error during rows iteration: %w", err)
	}

	for _, settings := range settingsMap {
		if len(settings) > 1 {
			// Keep the last one
			toDelete := settings[:len(settings)-1]
			fmt.Printf("Found %d duplicates for user_id %d, setting_name %s. Deleting %d of them.\n", len(settings), settings[0].UserID, settings[0].SettingName, len(toDelete))
			for _, s := range toDelete {
				if err := deleteUserSetting(db, s); err != nil {
					log.Printf("failed to delete user setting: %v", err)
				}
			}
		}
	}

	return nil
}

func deleteUserSetting(db *sql.DB, s UserSetting) error {
	query := `DELETE FROM user_settings WHERE user_id = ? AND locale = ? AND setting_name = ? AND `
	args := []interface{}{s.UserID, s.Locale, s.SettingName}

	if s.AssocType.Valid {
		query += "assoc_type = ? "
		args = append(args, s.AssocType.Int64)
	} else {
		query += "assoc_type IS NULL "
	}

	query += "AND "
	if s.AssocID.Valid {
		query += "assoc_id = ? "
		args = append(args, s.AssocID.Int64)
	} else {
		query += "assoc_id IS NULL "
	}

	query += "AND "
	if s.SettingValue.Valid {
		query += "setting_value = ?"
		args = append(args, s.SettingValue.String)
	} else {
		query += "setting_value IS NULL"
	}

	// Since setting_value can be large, we'll only log the first 100 characters
	truncatedValue := s.SettingValue.String
	if len(truncatedValue) > 100 {
		truncatedValue = truncatedValue[:100] + "..."
	}

	fmt.Printf(
		"Deleting record with user_id=%d, locale=%s, setting_name=%s, assoc_type=%v, assoc_id=%v, setting_value (truncated)='%s'\n",
		s.UserID,
		s.Locale,
		s.SettingName,
		s.AssocType,
		s.AssocID,
		truncatedValue,
	)

	result, err := db.Exec(query, args...)
	if err != nil {
		return fmt.Errorf("failed to execute delete: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		fmt.Println("Warning: Delete statement affected 0 rows.")
	} else {
		fmt.Printf("Deleted %d rows.\n", rowsAffected)
	}

	return nil
}
