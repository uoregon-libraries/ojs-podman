#!/bin/bash

if [ $# -lt 2 ]; then
    echo "Usage: $0 <input_file> <output_file>"
    exit 1
fi

input_file="$1"
output_file="$2"

if [ ! -f "$input_file" ]; then
    echo "Error: File '$input_file' not found"
    exit 1
fi

# Create a temporary file for processing
temp_file=$(mktemp)
cp "$input_file" "$temp_file"

# Get all environment variables with MYSQL_ or OJS_ prefix
env | grep -E '^(MYSQL_|OJS_)' | while IFS='=' read -r key value; do
    # Escape special characters in the value for sed
    escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^"$()+?{|]/\\&/g')

    # Replace %<key>% with the actual value in the temp file
    sed -i "s|%${key}%|${escaped_value}|g" "$temp_file"
done

# Move the processed file to the output location
mv "$temp_file" "$output_file"
