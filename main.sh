#!/bin/bash

# GitHub Organization Name
ORG_NAME="orgname"

# GitHub API URL for listing repos
API_URL="https://api.github.com/orgs/$ORG_NAME/repos"

# Create a directory to store package.json files
mkdir -p package_jsons

# Function to fetch repository information with pagination
fetch_repos() {
    # Try GitHub CLI first with pagination
    local repos_info
    if command -v gh &>/dev/null; then
        repos_info=$(gh api --paginate "$API_URL" --jq '.[] | [.full_name, .default_branch] | @tsv' 2>/dev/null)
    fi
    
    # Fallback to curl if gh failed or not available
    if [[ -z "$repos_info" ]]; then
        echo "[!] Using curl to fetch repositories (may be slower)..."
        local page=1
        while :; do
            local page_url="$API_URL?page=$page&per_page=100"
            local response
            response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$page_url")
            if [[ -z "$response" || "$response" == "[]" ]]; then
                break
            fi
            repos_info+=$'\n'$(echo "$response" | jq -r '.[] | [.full_name, .default_branch] | @tsv' 2>/dev/null)
            ((page++))
        done
        # Remove empty lines
        repos_info=$(echo "$repos_info" | sed '/^$/d')
    fi
    
    echo "$repos_info"
}

# Fetch repository information
echo "[+] Fetching repositories from GitHub Org: $ORG_NAME"
repos_info=$(fetch_repos)

# Check if we got any repositories
if [[ -z "$repos_info" ]]; then
    echo "[!] Error: No repositories found or failed to fetch data"
    exit 1
fi

# Process repositories
echo "$repos_info" | while IFS=$'\t' read -r repo default_branch; do
    echo "[+] Checking repo: $repo (default branch: $default_branch)"
    raw_url="https://raw.githubusercontent.com/$repo/$default_branch/package.json"
    output_file="package_jsons/${repo//\//_}.json"

    # Try to download package.json
    if curl -s -f -o "$output_file" "$raw_url"; then
        echo "[+] Successfully downloaded package.json"
    else
        echo "[!] Failed to download package.json"
        # Remove empty file if created
        [[ -f "$output_file" ]] && rm "$output_file"
    fi
done

# Check dependencies on npm
echo "[+] Checking dependencies on npm..."

for file in package_jsons/*.json; do
    # Skip if not a regular file or empty
    [[ ! -f "$file" || ! -s "$file" ]] && continue
    
    echo "[+] Processing $file"
    
    # Extract dependencies and check them
    jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$file" 2>/dev/null | while read -r pkg; do
        if npm view "$pkg" &>/dev/null; then
            echo -e "  \033[32m✔ $pkg exists on npm\033[0m"
        else
            echo -e "  \033[31m✖ $pkg NOT FOUND on npm\033[0m"
        fi
    done
done

echo "[+] Script completed"
