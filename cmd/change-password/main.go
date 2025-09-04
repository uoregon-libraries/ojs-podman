package main

import (
	"bufio"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

	_ "github.com/go-sql-driver/mysql"
	"golang.org/x/crypto/bcrypt"
)

func main() {
	var (
		userId    int
		email     string
		password  string
		userIdStr string
	)

	flag.StringVar(&userIdStr, "user-id", "", "User ID")
	flag.StringVar(&email, "email", "", "User email")
	flag.StringVar(&password, "password", "", "New password")
	flag.Parse()

	if userIdStr != "" {
		var err error
		userId, err = strconv.Atoi(userIdStr)
		if err != nil {
			log.Fatalf("Invalid user ID: %v", err)
		}
	}

	if (userId == 0 && email == "") || (userId != 0 && email != "") {
		log.Fatal("Please provide either a user ID or an email, but not both.")
	}
	if password == "" {
		log.Fatal("Please provide a password.")
	}

	dsn := os.Getenv("DSN")
	if dsn == "" {
		log.Fatal("DSN environment variable not set")
	}

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("Error connecting to database: %v", err)
	}
	defer db.Close()

	var username string
	var query string
	var arg interface{}

	if userId != 0 {
		query = "SELECT username FROM users WHERE user_id = ?"
		arg = userId
	} else {
		query = "SELECT username FROM users WHERE email = ?"
		arg = email
	}

	err = db.QueryRow(query, arg).Scan(&username)
	if err != nil {
		if err == sql.ErrNoRows {
			log.Fatalf("User not found")
		}
		log.Fatalf("Error querying database: %v", err)
	}

	fmt.Printf("Found user with username '%s'. Do you want to update the password? (y/n): ", username)
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	if strings.TrimSpace(input) != "y" {
		fmt.Println("Password update cancelled.")
		os.Exit(0)
	}

	hash, err := bcryptHash(password)
	if err != nil {
		log.Fatalf("Error generating hash: %v", err)
	}

	if userId != 0 {
		query = "UPDATE users SET password = ? WHERE user_id = ?"
	} else {
		query = "UPDATE users SET password = ? WHERE email = ?"
	}

	_, err = db.Exec(query, hash, arg)
	if err != nil {
		log.Fatalf("Error updating password: %v", err)
	}

	fmt.Println("Password updated successfully.")
}

func bcryptHash(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}
