package main

import (
	"bufio"
	"database/sql"
	"fmt"
	"log"
	"os"
	"strings"

	_ "github.com/go-sql-driver/mysql"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: create-admin <email>")
	}
	email := os.Args[1]

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

	// 1. Find user_group_id for admin
	var userGroupID int64
	err = db.QueryRow("SELECT user_group_id FROM user_groups WHERE (context_id = 0 OR context_id IS NULL) AND role_id = 1").Scan(&userGroupID)
	if err != nil {
		log.Fatalf("failed to find admin user_group_id: %v", err)
	}

	// 2. Find user by email
	var userID int64
	var username string
	err = db.QueryRow("SELECT user_id, username FROM users WHERE email = ?", email).Scan(&userID, &username)
	if err != nil {
		if err == sql.ErrNoRows {
			log.Fatalf("no user found with email: %s", email)
		}
		log.Fatalf("failed to find user: %v", err)
	}

	// 3. Check if user is already an admin
	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM user_user_groups WHERE user_id = ? AND user_group_id = ?", userID, userGroupID).Scan(&count)
	if err != nil {
		log.Fatalf("failed to check for existing admin rights: %v", err)
	}

	if count > 0 {
		fmt.Printf("User %s (ID: %d) is already an admin.\n", username, userID)
		return
	}

	// 4. Confirm before making changes
	fmt.Printf("Found user: %s (ID: %d)\n", username, userID)
	fmt.Print("Are you sure you want to give this user admin privileges? (y/N): ")
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	if strings.ToLower(strings.TrimSpace(input)) != "y" {
		fmt.Println("Aborted.")
		return
	}

	// 5. Add user to admin group
	_, err = db.Exec("INSERT INTO user_user_groups (user_id, user_group_id) VALUES (?, ?)", userID, userGroupID)
	if err != nil {
		log.Fatalf("failed to grant admin privileges: %v", err)
	}

	fmt.Println("Admin privileges granted successfully.")
}
