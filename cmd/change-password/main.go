package main

import (
	"bufio"
	"database/sql"
	"fmt"
	"log"
	"os"
	"strings"

	_ "github.com/go-sql-driver/mysql"
	"golang.org/x/crypto/bcrypt"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: go run main.go <email> <password>")
		os.Exit(1)
	}

	dsn := os.Getenv("DSN")
	if dsn == "" {
		log.Fatal("DSN environment variable not set")
	}

	email := os.Args[1]
	password := os.Args[2]

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("Error connecting to database: %v", err)
	}
	defer db.Close()

	var username string
	err = db.QueryRow("SELECT username FROM users WHERE email = ?", email).Scan(&username)
	if err != nil {
		if err == sql.ErrNoRows {
			log.Fatalf("User with email %s not found", email)
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

	_, err = db.Exec("UPDATE users SET password = ? WHERE email = ?", hash, email)
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
