#!/bin/bash
set -e

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Create Claude configuration
create_claude_config() {
    local config_file="$HOME/.claude.json"

    log "Creating Claude configuration at: $config_file"

    mkdir -p "$(dirname "$config_file")"

    # Create config
cat > "$config_file" << CONFIG_EOF
{
"hasCompletedOnboarding": true,
"projects": {},
"customApiKeyResponses": {
"approved": [],
"rejected": []
},
"mcpServers": {}
}
CONFIG_EOF

    # Verify JSON validity using python (more reliable than jq)
    if ! python3 -m json.tool "$config_file" > /dev/null 2>&1; then
        error_exit "Generated configuration file contains invalid JSON"
    fi

    log "Configuration file created"
}

# Verify OAuth token authentication
verify_oauth_token() {
    if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        error_exit "CLAUDE_CODE_OAUTH_TOKEN environment variable is required but not set"
    fi

    log "✅ CLAUDE_CODE_OAUTH_TOKEN environment variable detected"
    log "� Claude Code will use OAuth token for authentication"

    # Verify token format (basic validation)
    if [[ ${#CLAUDE_CODE_OAUTH_TOKEN} -lt 20 ]]; then
        log "⚠️  WARNING: OAuth token seems unusually short"
    fi

    return 0
}

# Set CLI configuration flags
configure_claude_cli() {
    log "Setting Claude CLI configuration flags..."

    # Set configuration flags to skip interactive prompts
    claude config set hasCompletedOnboarding true 2>/dev/null || log "WARNING: Failed to set hasCompletedOnboarding"
    claude config set hasTrustDialogAccepted true 2>/dev/null || log "WARNING: Failed to set hasTrustDialogAccepted"

    log "CLI configuration completed"
}

# Verify Pro subscription configuration
verify_pro_configuration() {
    local config_file="$HOME/.claude.json"

    log "Verifying Claude Pro subscription configuration..."

    # Check file existence
    if [[ ! -f "$config_file" ]]; then
        error_exit "Configuration file not found: $config_file"
    fi

    # Validate JSON structure using python
    if ! python3 -c "import json; json.load(open('$config_file'))" > /dev/null 2>&1; then
        error_exit "Configuration file contains invalid JSON"
    fi

    # Check onboarding completion
    local onboarding=$(python3 -c "import json; print(json.load(open('$config_file')).get('hasCompletedOnboarding', False))" 2>/dev/null || echo "false")

    if [[ "$onboarding" != "True" ]]; then
        log "WARNING: Onboarding not marked as complete, but continuing with Pro subscription"
    fi

    log "Pro subscription configuration verification successful"
}

# Test Claude functionality
test_claude_functionality() {
    log "Testing Claude Code functionality..."

    # Test basic command
    if claude --version >/dev/null 2>&1; then
        local version=$(claude --version 2>/dev/null || echo "Unknown")
        log "Claude Code version check successful: $version"
    else
        log "WARNING: Claude Code version check failed"
    fi

    # Test configuration access
    if claude config show >/dev/null 2>&1; then
        log "Claude Code configuration accessible"
    else
        log "WARNING: Claude Code configuration not accessible"
    fi
}

# Main setup function
main() {
    # Default to /workspace if no target directory specified
    # TARGET_DIR=${TARGET_DIR:-/workspace}
    # AMPLIFIER_DATA_DIR=${AMPLIFIER_DATA_DIR:-/app/amplifier-data}

    log "🚀 Starting Amplifier Docker Container with Enhanced Claude Configuration"
    log "📁 Target project: $TARGET_DIR"
    log "📁 Amplifier dir: $AMPLIFIER_DIR"
    log "📁 Amplifier data: $AMPLIFIER_DATA_DIR"

    # Environment variable debugging
    log "🔍 Environment Variable Debug Information:"
    log "   HOME: $HOME"
    log "   USER: $(whoami)"
    log "   PWD: $PWD"

    # Check for OAuth token
    if [ ! -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        log "   Authentication: Claude Pro OAuth Token (no billing)"
    else
        log "   CLAUDE_CODE_OAUTH_TOKEN: (not set)"
        error_exit "CLAUDE_CODE_OAUTH_TOKEN environment variable is required"
    fi

    # Validate target directory exists
    if [ -d "$TARGET_DIR" ]; then
        log "✅ Target directory found: $TARGET_DIR"
    else
        log "❌ Target directory not found: $TARGET_DIR"
        log "💡 Make sure you mounted your project directory to $TARGET_DIR"
        exit 1
    fi

    # Change to Amplifier directory and activate environment
    log "🔧 Setting up Amplifier environment..."
    cd $AMPLIFIER_DIR
    source .venv/bin/activate

    # Configure Claude Code with Pro subscription (no billing)
    log "🔧 Configuring Claude Code with Claude Pro subscription..."
    log "🌐 Backend: CLAUDE PRO SUBSCRIPTION (No billing required)"
    log "� Using your existing Claude Pro account authentication"

    # Create configuration
    create_claude_config

    # Test basic functionality (non-blocking)
    test_claude_functionality

    log "✅ Claude Code OAuth configuration completed"
    log "📁 Adding target directory: $TARGET_DIR"
    log "🚀 Starting Claude Code with OAuth authentication..."
    log "💰 No API billing - using your Claude Pro subscription limits"
    log ""

    # Create placeholder directories to suppress Claude Code's "Path not found" warnings
    mkdir -p /app/amplifier/.data
    mkdir -p /root/amplifier

    # Start Claude with OAuth token authentication
    # The CLAUDE_CODE_OAUTH_TOKEN environment variable will be automatically used
    claude --add-dir "$TARGET_DIR" --permission-mode acceptEdits "I'm working in $TARGET_DIR which doesn't have Amplifier files. Please cd to that directory and work there. Do NOT update any issues or PRs in the Amplifier repo."
}

# Execute main function
main "$@"
