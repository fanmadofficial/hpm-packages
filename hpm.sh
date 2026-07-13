#!/bin/bash

# ╔══════════════════════════════════════════╗
# ║        Hobby Package Manager v1          ║
# ╚══════════════════════════════════════════╝

# Configuration
HPM_DIR="$HOME/.hpm"
PKG_DIR="$HPM_DIR/packages"
DB_DIR="$HPM_DIR/db"
CACHE_DIR="$HPM_DIR/cache"
CONFIG_FILE="$HPM_DIR/config"
GITHUB_REPO="fanmadofficial/hpm-packages"
GITHUB_BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH"
API_URL="https://api.github.com/repos/$GITHUB_REPO"

# Colors and styles
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Icons and emoji
CHECK="✓"
CROSS="✗"
ARROW="→"
STAR="★"
PACKAGE="📦"
GEAR="⚙"
ROCKET="🚀"
SEARCH="🔍"
TRASH="🗑"
SYNC="⟳"

# HPM Banner
show_banner() {
    echo -e "${MAGENTA}"
    cat << "EOF"
╔═══════════════╗
║  ╦ ╦╔═╗╔╦╗    ║
║  ╠═╣╠═╝║║║    ║
║  ╩ ╩╩  ╩ ╩    ║
║ Hobby Package ║
║ Manager v1    ║
╚═══════════════╝
EOF
    echo -e "${NC}"
}

# Helper logging functions
log_info() {
    echo -e "${BLUE}${ARROW}${NC} $1"
}

log_success() {
    echo -e "${GREEN}${CHECK}${NC} $1"
}

log_error() {
    echo -e "${RED}${CROSS}${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}${STAR}${NC} $1"
}

# Create HPM directory structure
init_hpm() {
    mkdir -p "$PKG_DIR" "$DB_DIR" "$CACHE_DIR" "$DB_DIR/installed"
    
    # Create config if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# HPM Configuration
GITHUB_REPO="$GITHUB_REPO"
GITHUB_BRANCH="$GITHUB_BRANCH"
AUTO_UPDATE=true
CHECK_DEPS=true
EOF
    else
        # Load configuration
        source "$CONFIG_FILE"
    fi
}

# Download function with GitHub caching
hpm_download() {
    local url="$1"
    local output="$2"
    local use_cache="${3:-true}"
    
    if [ "$use_cache" = "true" ] && [ -f "$output" ]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$output" 2>/dev/null || echo 0)))
        if [ $cache_age -lt 3600 ]; then  # Cache valid for 1 hour
            return 0
        fi
    fi
    
    if command -v curl &> /dev/null; then
        curl -sSL --fail "$url" -o "$output" 2>/dev/null
        return $?
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$output" 2>/dev/null
        return $?
    else
        log_error "curl or wget is required!"
        return 1
    fi
}

# Simple JSON parsing (without jq)
hpm_json_get() {
    local json="$1"
    local key="$2"
    grep -o "\"$key\":[[:space:]]*\"[^\"]*\"" <<< "$json" | head -1 | sed 's/.*: *"\(.*\)"/\1/'
}

# Update package index from GitHub
hpm_update() {
    echo -e "${SYNC} ${CYAN}Updating HPM package index...${NC}"
    
    local index_url="$RAW_URL/packages/index.json"
    local index_file="$DB_DIR/index.json"
    
    if hpm_download "$index_url" "$index_file" "false"; then
        log_success "HPM index updated successfully!"
        
        # Display statistics
        local package_count=$(grep -c '"name":' "$index_file")
        echo -e "  ${PACKAGE} Available packages: ${GREEN}$package_count${NC}"
        
        # Save update date
        date "+%Y-%m-%d %H:%M:%S" > "$DB_DIR/last_update"
        
        # Save statistics
        if [ -f "$DB_DIR/index.json" ]; then
            local repo_name=$(hpm_json_get "$(head -20 "$DB_DIR/index.json")" "name")
            echo -e "  ${GEAR} Repository: ${GREEN}$repo_name${NC}"
        fi
    else
        log_error "Cannot download HPM index!"
        echo -e "  Check your internet connection"
        echo -e "  Repository: ${CYAN}$GITHUB_REPO${NC}"
        return 1
    fi
}

# Check if package exists
hpm_package_exists() {
    local pkg_name="$1"
    
    if [ ! -f "$DB_DIR/index.json" ]; then
        hpm_update || return 1
    fi
    
    grep -q "\"name\":[[:space:]]*\"$pkg_name\"" "$DB_DIR/index.json"
}

# Get package metadata
hpm_get_metadata() {
    local pkg_name="$1"
    local metadata_url="$RAW_URL/packages/$pkg_name/package.json"
    local metadata_file="$CACHE_DIR/${pkg_name}.json"
    
    if hpm_download "$metadata_url" "$metadata_file" "false"; then
        cat "$metadata_file"
    else
        log_error "Cannot download metadata for package ${CYAN}$pkg_name${NC}"
        return 1
    fi
}

# Install package
hpm_install() {
    local pkg_name="$1"
    local pkg_dir="$PKG_DIR/$pkg_name"
    
    show_banner
    
    echo -e "${ROCKET} ${CYAN}Installing HPM package: ${GREEN}$pkg_name${NC}"
    echo ""
    
    # Check if package exists
    if ! hpm_package_exists "$pkg_name"; then
        log_error "Package '${CYAN}$pkg_name${NC}' does not exist in HPM repository!"
        echo -e "  Use: ${YELLOW}hpm search <name>${NC} to find packages"
        return 1
    fi
    
    # Check if already installed
    if [ -f "$DB_DIR/installed/$pkg_name" ]; then
        local current_version=$(grep "version:" "$DB_DIR/installed/$pkg_name" | cut -d' ' -f2)
        log_warning "Package ${CYAN}$pkg_name${NC} (v$current_version) is already installed."
        echo -e "  Use: ${YELLOW}hpm upgrade $pkg_name${NC} to update"
        return 0
    fi
    
    # Get metadata
    local metadata=$(hpm_get_metadata "$pkg_name")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local version=$(hpm_json_get "$metadata" "version")
    local description=$(hpm_json_get "$metadata" "description")
    local author=$(hpm_json_get "$metadata" "author")
    
    echo -e "  ${PACKAGE} Name:         ${GREEN}$pkg_name${NC}"
    echo -e "  ${STAR} Version:      ${GREEN}$version${NC}"
    echo -e "  ${GEAR} Author:       ${CYAN}$author${NC}"
    echo -e "  📝 Description:  $description"
    echo ""
    
    # Check dependencies
    if [ "$CHECK_DEPS" = "true" ]; then
        local deps=$(echo "$metadata" | grep -o '"dependencies":\[[^]]*\]' | grep -o '"[^"]*"' | tr -d '"')
        if [ ! -z "$deps" ]; then
            log_info "Checking dependencies..."
            for dep in $deps; do
                if [ ! -f "$DB_DIR/installed/$dep" ]; then
                    echo -e "  ${ARROW} Installing dependency: ${CYAN}$dep${NC}"
                    hpm_install "$dep" || {
                        log_error "Cannot install dependency: $dep"
                        return 1
                    }
                else
                    echo -e "  ${CHECK} Dependency ${CYAN}$dep${NC} already installed"
                fi
            done
            echo ""
        fi
    fi
    
    # Download and install files
    log_info "Downloading package files..."
    local files=$(echo "$metadata" | grep -o '"files":\[[^]]*\]' | grep -o '"[^"]*"' | tr -d '"')
    
    mkdir -p "$pkg_dir/bin"
    
    for file in $files; do
        local file_url="$RAW_URL/packages/$pkg_name/$file"
        local local_path="$pkg_dir/$file"
        
        if hpm_download "$file_url" "$local_path" "false"; then
            echo -e "    ${CHECK} $file"
            chmod +x "$local_path" 2>/dev/null
        else
            echo -e "    ${CROSS} $file"
        fi
    done
    
    # Execute install script if exists
    local install_script="$pkg_dir/install.sh"
    if [ -f "$install_script" ]; then
        chmod +x "$install_script"
        bash "$install_script"
    fi
    
    # Save installation info
    cat > "$DB_DIR/installed/$pkg_name" << EOF
name: $pkg_name
version: $version
author: $author
install_date: $(date "+%Y-%m-%d %H:%M:%S")
source: $GITHUB_REPO
EOF
    
    echo ""
    log_success "Package ${GREEN}$pkg_name v$version${NC} installed successfully!"
    echo -e "  ${ROCKET} Ready to use!"
}

# Upgrade package(s)
hpm_upgrade() {
    local pkg_name="$1"
    
    if [ -z "$pkg_name" ]; then
        # Upgrade all
        echo -e "${SYNC} ${CYAN}Upgrading all HPM packages...${NC}"
        echo ""
        
        local updated=0
        local failed=0
        
        for installed in "$DB_DIR/installed/"*; do
            if [ -f "$installed" ]; then
                local pkg=$(basename "$installed")
                if hpm_upgrade_package "$pkg"; then
                    ((updated++))
                else
                    ((failed++))
                fi
            fi
        done
        
        echo ""
        if [ $updated -gt 0 ]; then
            log_success "Upgraded ${GREEN}$updated${NC} packages"
        fi
        if [ $failed -gt 0 ]; then
            log_error "Failed to upgrade ${RED}$failed${NC} packages"
        fi
        if [ $updated -eq 0 ] && [ $failed -eq 0 ]; then
            log_success "All packages are up to date!"
        fi
    else
        hpm_upgrade_package "$pkg_name"
    fi
}

hpm_upgrade_package() {
    local pkg_name="$1"
    local current_version=""
    
    if [ ! -f "$DB_DIR/installed/$pkg_name" ]; then
        log_error "Package '${CYAN}$pkg_name${NC}' is not installed!"
        return 1
    fi
    
    current_version=$(grep "version:" "$DB_DIR/installed/$pkg_name" | cut -d' ' -f2)
    
    echo -e "${SYNC} Checking: ${CYAN}$pkg_name${NC}"
    
    # Get latest version
    local metadata=$(hpm_get_metadata "$pkg_name")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local latest_version=$(hpm_json_get "$metadata" "version")
    
    if [ "$current_version" = "$latest_version" ]; then
        echo -e "  ${CHECK} Up to date (v$current_version)"
        return 0
    fi
    
    echo -e "  ${ARROW} Upgrading: v${RED}$current_version${NC} ${ARROW} v${GREEN}$latest_version${NC}"
    hpm_remove "$pkg_name" --silent
    hpm_install "$pkg_name"
}

# Remove package
hpm_remove() {
    local pkg_name="$1"
    local silent="$2"
    local pkg_dir="$PKG_DIR/$pkg_name"
    
    if [ ! -f "$DB_DIR/installed/$pkg_name" ]; then
        [ "$silent" != "--silent" ] && log_error "Package '${CYAN}$pkg_name${NC}' is not installed!"
        return 1
    fi
    
    [ "$silent" != "--silent" ] && echo -e "${TRASH} ${YELLOW}Removing package: ${CYAN}$pkg_name${NC}"
    
    # Execute uninstall script if exists
    local remove_script="$pkg_dir/uninstall.sh"
    if [ -f "$remove_script" ]; then
        chmod +x "$remove_script"
        bash "$remove_script"
    fi
    
    # Remove files
    rm -rf "$pkg_dir"
    rm -f "$DB_DIR/installed/$pkg_name"
    
    [ "$silent" != "--silent" ] && log_success "Package ${CYAN}$pkg_name${NC} removed!"
}

# List installed packages
hpm_list() {
    show_banner
    
    echo -e "${PACKAGE} ${CYAN}Installed HPM packages:${NC}"
    echo ""
    
    if [ ! -d "$DB_DIR/installed" ] || [ -z "$(ls -A "$DB_DIR/installed" 2>/dev/null)" ]; then
        echo -e "  ${YELLOW}No packages installed.${NC}"
        echo -e "  Use: ${GREEN}hpm install <package>${NC} to install one"
        return
    fi
    
    printf "  ${BOLD}%-25s %-15s %-25s${NC}\n" "NAME" "VERSION" "INSTALL DATE"
    echo "  $(printf '─%.0s' {1..70})"
    
    for pkg_file in "$DB_DIR/installed/"*; do
        if [ -f "$pkg_file" ]; then
            local name=""
            local version=""
            local date=""
            
            while IFS=': ' read -r key value; do
                case "$key" in
                    "name") name="$value" ;;
                    "version") version="$value" ;;
                    "install_date") date="$value" ;;
                esac
            done < "$pkg_file"
            
            printf "  ${GREEN}%-25s${NC} v%-14s ${CYAN}%s${NC}\n" "$name" "$version" "$date"
        fi
    done
    
    echo ""
    echo -e "  ${GEAR} Total: ${GREEN}$(ls -1 "$DB_DIR/installed" | wc -l)${NC} packages"
}

# Search packages
hpm_search() {
    local query="$1"
    
    if [ -z "$query" ]; then
        log_error "Please provide a package name to search for!"
        echo -e "  Usage: ${YELLOW}hpm search <name>${NC}"
        return 1
    fi
    
    if [ ! -f "$DB_DIR/index.json" ]; then
        hpm_update || return 1
    fi
    
    echo -e "${SEARCH} ${CYAN}Search results for '${YELLOW}$query${CYAN}':${NC}"
    echo ""
    
    local found=0
    printf "  ${BOLD}%-25s %-15s %-40s${NC}\n" "NAME" "VERSION" "DESCRIPTION"
    echo "  $(printf '─%.0s' {1..85})"
    
    while IFS= read -r line; do
        if echo "$line" | grep -qi "$query"; then
            local block=$(grep -B 1 -A 10 "\"name\":[[:space:]]*\".*$query.*\"" "$DB_DIR/index.json" 2>/dev/null)
            if [ ! -z "$block" ]; then
                local name=$(echo "$block" | grep -o '"name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
                local version=$(echo "$block" | grep -o '"version":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
                local desc=$(echo "$block" | grep -o '"description":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
                
                if [ ! -z "$name" ]; then
                    # Check if installed
                    local status=""
                    if [ -f "$DB_DIR/installed/$name" ]; then
                        status=" ${GREEN}[installed]${NC}"
                    fi
                    
                    printf "  ${GREEN}%-25s${NC} v%-14s %-40s%s\n" "$name" "$version" "${desc:0:40}" "$status"
                    ((found++))
                fi
            fi
        fi
    done < <(grep -A 5 '"name":' "$DB_DIR/index.json")
    
    if [ $found -eq 0 ]; then
        echo -e "  ${YELLOW}No packages found matching '${CYAN}$query${YELLOW}'${NC}"
        echo -e "  Try: ${GREEN}hpm search .${NC} to see all packages"
    else
        echo ""
        echo -e "  ${SEARCH} Found: ${GREEN}$found${NC} packages"
    fi
}

# Package information
hpm_info() {
    local pkg_name="$1"
    
    if [ -z "$pkg_name" ]; then
        log_error "Please provide a package name!"
        echo -e "  Usage: ${YELLOW}hpm info <package>${NC}"
        return 1
    fi
    
    echo -e "${PACKAGE} ${CYAN}HPM package info: ${GREEN}$pkg_name${NC}"
    echo ""
    
    # Get metadata
    local metadata=$(hpm_get_metadata "$pkg_name")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local version=$(hpm_json_get "$metadata" "version")
    local description=$(hpm_json_get "$metadata" "description")
    local author=$(hpm_json_get "$metadata" "author")
    local license=$(hpm_json_get "$metadata" "license")
    local category=$(hpm_json_get "$metadata" "category")
    
    echo -e "  ${PACKAGE} Name:         ${GREEN}$pkg_name${NC}"
    echo -e "  ${STAR} Version:      ${GREEN}$version${NC}"
    echo -e "  ${GEAR} Author:       $author"
    echo -e "  📝 Description:  $description"
    echo -e "  📋 Category:     ${CYAN}$category${NC}"
    echo -e "  📜 License:      $license"
    
    # Installation status
    if [ -f "$DB_DIR/installed/$pkg_name" ]; then
        local installed_version=$(grep "version:" "$DB_DIR/installed/$pkg_name" | cut -d' ' -f2)
        local install_date=$(grep "install_date:" "$DB_DIR/installed/$pkg_name" | cut -d' ' -f2-)
        echo -e "  ${CHECK} Status:       ${GREEN}Installed${NC} (v$installed_version)"
        echo -e "  📅 Installed on: $install_date"
        
        if [ "$installed_version" != "$version" ]; then
            echo -e "  ${SYNC} Update available: v${GREEN}$version${NC}"
            echo -e "    Run: ${YELLOW}hpm upgrade $pkg_name${NC}"
        fi
    else
        echo -e "  ${CROSS} Status:       ${YELLOW}Not installed${NC}"
        echo -e "    Install with: ${GREEN}hpm install $pkg_name${NC}"
    fi
}

# HPM Configuration
hpm_config() {
    show_banner
    
    echo -e "${GEAR} ${CYAN}HPM Configuration${NC}"
    echo ""
    echo -e "  Repository:    ${GREEN}$GITHUB_REPO${NC}"
    echo -e "  Branch:        ${GREEN}$GITHUB_BRANCH${NC}"
    echo -e "  HPM Directory: ${CYAN}$HPM_DIR${NC}"
    echo ""
    
    echo -e "${YELLOW}Available options:${NC}"
    echo "  1) Change GitHub repository"
    echo "  2) Toggle auto-update"
    echo "  3) Clear cache"
    echo "  4) Show statistics"
    echo "  0) Exit"
    echo ""
    
    read -p "  Select option [0-4]: " option
    
    case $option in
        1)
            echo ""
            read -p "  Enter new repository (user/repo): " new_repo
            if [ ! -z "$new_repo" ]; then
                sed -i "s|GITHUB_REPO=.*|GITHUB_REPO=\"$new_repo\"|" "$CONFIG_FILE"
                sed -i "s|GITHUB_REPO=.*|GITHUB_REPO=\"$new_repo\"|" "$0" 2>/dev/null
                export GITHUB_REPO="$new_repo"
                RAW_URL="https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH"
                log_success "Repository changed to: ${GREEN}$new_repo${NC}"
                echo -e "  Run: ${YELLOW}hpm update${NC} to synchronize"
            fi
            ;;
        2)
            if [ "$AUTO_UPDATE" = "true" ]; then
                sed -i 's/AUTO_UPDATE=true/AUTO_UPDATE=false/' "$CONFIG_FILE"
                log_info "Auto-update: ${RED}OFF${NC}"
            else
                sed -i 's/AUTO_UPDATE=false/AUTO_UPDATE=true/' "$CONFIG_FILE"
                log_info "Auto-update: ${GREEN}ON${NC}"
            fi
            ;;
        3)
            rm -rf "$CACHE_DIR"/*
            log_success "Cache cleared!"
            ;;
        4)
            echo ""
            echo -e "${CYAN}HPM Statistics:${NC}"
            echo -e "  ${PACKAGE} Installed packages: ${GREEN}$(ls -1 "$DB_DIR/installed" 2>/dev/null | wc -l)${NC}"
            echo -e "  📁 Packages size: ${CYAN}$(du -sh "$PKG_DIR" 2>/dev/null | cut -f1)${NC}"
            echo -e "  💾 Cache size: ${CYAN}$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)${NC}"
            if [ -f "$DB_DIR/last_update" ]; then
                echo -e "  ${SYNC} Last update: $(cat "$DB_DIR/last_update")"
            fi
            ;;
        *)
            echo "Goodbye!"
            ;;
    esac
}

# HPM Help
hpm_help() {
    show_banner
    
    cat << EOF
${BOLD}${CYAN}HPM - Hobby Package Manager${NC}
A lightweight GitHub-integrated package manager

${BOLD}${YELLOW}Usage:${NC} hpm <command> [options]

${BOLD}${GREEN}Commands:${NC}
  ${YELLOW}install${NC} <package>     ${PACKAGE} Install a package from the repository
  ${YELLOW}remove${NC} <package>      ${TRASH} Uninstall a package
  ${YELLOW}upgrade${NC} [package]     ${SYNC} Upgrade package(s) to the latest version
  ${YELLOW}update${NC}                ${SYNC} Refresh package index from GitHub
  ${YELLOW}search${NC} <name>         ${SEARCH} Search for packages in the repository
  ${YELLOW}info${NC} <package>        ${GEAR} Show detailed package information
  ${YELLOW}list${NC}                  ${PACKAGE} List installed packages
  ${YELLOW}config${NC}                ${GEAR} Configure HPM settings
  ${YELLOW}help${NC}                  Show this help message

${BOLD}${GREEN}Examples:${NC}
  hpm update                  ${ARROW} Update the package list
  hpm search hello            ${ARROW} Search for "hello" package
  hpm install hello           ${ARROW} Install the hello package
  hpm info hello              ${ARROW} Show hello package info
  hpm list                    ${ARROW} List installed packages
  hpm upgrade                 ${ARROW} Upgrade all packages
  hpm remove hello            ${ARROW} Uninstall the hello package

${BOLD}${CYAN}Information:${NC}
  Repository:     ${GREEN}$GITHUB_REPO${NC}
  HPM Directory:  ${CYAN}$HPM_DIR${NC}
  HPM Version:    v1

${BOLD}More info:${NC} https://github.com/$GITHUB_REPO
EOF
}

# Main HPM function
hpm_main() {
    # Initialize HPM
    init_hpm
    
    # Auto-update if enabled
    if [ "$AUTO_UPDATE" = "true" ] && [ "$1" != "update" ] && [ "$1" != "help" ] && [ "$1" != "config" ]; then
        if [ ! -f "$DB_DIR/last_update" ] || [ $(($(date +%s) - $(date -d "$(cat "$DB_DIR/last_update")" +%s 2>/dev/null || echo 0))) -gt 86400 ]; then
            hpm_update > /dev/null 2>&1
        fi
    fi
    
    # Parse commands
    case "$1" in
        install|i)
            [ -z "$2" ] && { log_error "Usage: hpm install <package>"; return 1; }
            hpm_install "$2"
            ;;
        remove|rm|uninstall)
            [ -z "$2" ] && { log_error "Usage: hpm remove <package>"; return 1; }
            hpm_remove "$2"
            ;;
        upgrade|up)
            hpm_upgrade "$2"
            ;;
        update|sync|refresh)
            hpm_update
            ;;
        search|find|s)
            hpm_search "$2"
            ;;
        info|show|i)
            hpm_info "$2"
            ;;
        list|ls|installed)
            hpm_list
            ;;
        config|configure|settings)
            hpm_config
            ;;
        help|--help|-h|"")
            hpm_help
            ;;
        *)
            log_error "Unknown command: ${RED}$1${NC}"
            echo -e "  Use: ${YELLOW}hpm help${NC} to see available commands"
            return 1
            ;;
    esac
}

# Run HPM
hpm_main "$@"
