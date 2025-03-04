#!/bin/bash

# GitHub Organization Name
ORG_NAME="enter_your_org_name_here"

# GitHub API URL for listing repos
API_URL="https://api.github.com/orgs/$ORG_NAME/repos"

# Create a directory to store package.json files
mkdir -p package_jsons

# Fetch the list of repositories in the Formio organization
echo "[+] Fetching repositories from GitHub Org: $ORG_NAME"
repos=$(gh api $API_URL --jq '.[].full_name' 2>/dev/null)

# If GitHub CLI fails, fallback to curl
if [[ -z "$repos" ]]; then
    echo "[!] GitHub CLI failed, trying curl..."
    repos=$(curl -s "$API_URL" | jq -r '.[].full_name')
fi

# Loop through each repository and fetch package.json
for repo in $repos; do
    echo "[+] Checking repo: $repo"

    # Possible branches to check (some repos use 'main', some 'master', etc.)
    for branch in main master develop; do
        raw_url="https://raw.githubusercontent.com/$repo/$branch/package.json"

        # Try to download package.json
        curl -s -f -o "package_jsons/${repo//\//_}.json" "$raw_url"
        if [[ $? -eq 0 ]]; then
            echo "[+] Found package.json in $repo ($branch)"
            break  # Stop checking branches if found
        fi
    done
done

# Check all dependencies on npm
echo "[+] Checking dependencies on npm..."

for file in package_jsons/*.json; do
    echo "[+] Processing $file"

    # Extract dependencies and devDependencies
    packages=$(jq -r '.dependencies,.devDependencies | keys[]?' "$file" 2>/dev/null)

    # Check each package on npm
    for pkg in $packages; do
        npm view "$pkg" &>/dev/null && echo "$pkg exists on npm" || echo "$pkg NOT FOUND on npm"
    done
done
