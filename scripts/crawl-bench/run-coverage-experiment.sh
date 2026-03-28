#!/bin/bash
################################################################################
# Automated Coverage Experiment Script
#
# This script runs all combinations of SAFs and traversal methods for a PHP app
# and automatically collects code coverage data.
#
# Usage: ./run-coverage-experiment.sh <app-name>
# Example: ./run-coverage-experiment.sh mantisbt
#
# SAFs: siamese, rted, pdiff, fraggen
# Traversal Methods: bfs, dfs, most_actions_first, priority_bfs
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SAFS=("dynamic-rted" "dynamic-pdiff" "dynamic-consensus")
TRAVERSALS=("bfs" "dfs" "most_actions_first" "priority_bfs")
MAX_RUNTIME=120  # minutes
CRAWL_WAIT_TIME=$((MAX_RUNTIME * 120 + 120))  # Runtime + 2 min buffer (in seconds)

# Function to log messages (defined early so they can be used anywhere)
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check system dependencies for FragGen (OpenCV/GTK)
check_fraggen_dependencies() {
    if command -v ldconfig &> /dev/null; then
        if ! ldconfig -p | grep -q libgtk-x11-2.0; then
            log_warning "FragGen dependency missing: libgtk-x11-2.0.so.0"
            log_warning "FragGen runs may fail. Install with: sudo apt-get install libgtk2.0-0"
            return 1
        fi
    fi
    return 0
}

# Validate input
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Application name is required${NC}"
    echo ""
    echo "Usage: $0 <app-name>"
    echo ""
    echo "Available PHP applications:"
    echo "  mantisbt, mrbs, ppma, addressbook, claroline"
    echo ""
    echo "Example:"
    echo "  $0 mantisbt"
    exit 1
fi

APP_NAME=$1
VALID_APPS=("mantisbt" "mrbs" "ppma" "addressbook" "claroline")

# Validate app name
if [[ ! " ${VALID_APPS[@]} " =~ " ${APP_NAME} " ]]; then
    echo -e "${RED}Error: Invalid application name: $APP_NAME${NC}"
    echo "Valid applications: ${VALID_APPS[@]}"
    exit 1
fi

# Determine coverage path based on app
if [[ "$APP_NAME" == "addressbook" || "$APP_NAME" == "claroline" ]]; then
    COVERAGE_BASE="$PROJECT_ROOT/web-apps-main/web-apps-coverage/dbApps-coverage"
    COVERAGE_SESSIONS_PATH="$COVERAGE_BASE/www/html/coverage/coverage_data/sessions"
else
    COVERAGE_BASE="$PROJECT_ROOT/web-apps-main/web-apps-coverage/$APP_NAME"
    COVERAGE_SESSIONS_PATH="$COVERAGE_BASE/coverage/coverage_data/sessions"
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Automated Coverage Experiment Runner${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "Application:      ${GREEN}$APP_NAME${NC}"
echo -e "SAFs:             ${SAFS[@]}"
echo -e "Traversals:       ${TRAVERSALS[@]}"
echo -e "Total runs:       ${GREEN}$((${#SAFS[@]} * ${#TRAVERSALS[@]}))${NC}"
echo -e "Max runtime:      ${MAX_RUNTIME} minutes per run"
echo -e "Coverage path:    $COVERAGE_SESSIONS_PATH"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check FragGen dependencies
FRAGGEN_AVAILABLE=true
if ! check_fraggen_dependencies; then
    log_warning "FragGen will be skipped due to missing dependencies"
    FRAGGEN_AVAILABLE=false
    # Remove fraggen from SAFS array if dependencies missing
    SAFS=("${SAFS[@]/fraggen/}")
    TOTAL_RUNS=$((${#SAFS[@]} * ${#TRAVERSALS[@]}))
    log "Adjusted total runs: $TOTAL_RUNS (FragGen excluded)"
fi

# Ask for confirmation
read -p "Do you want to proceed? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Track progress
TOTAL_RUNS=$((${#SAFS[@]} * ${#TRAVERSALS[@]}))
CURRENT_RUN=0
SUCCESSFUL_RUNS=0
FAILED_RUNS=0

# Function to determine which SAF services are needed for a strategy
get_required_safs() {
    local saf=$1

    case "$saf" in
        # Dynamic strategies with specific requirements
        dynamic_pdiff|dynamic-pdiff)
            echo "pdiff"
            ;;
        dynamic_rted|dynamic-rted)
            echo "rted"
            ;;
        dynamic_switch|dynamic-switch)
            echo "pdiff rted fraggen"
            ;;
        dynamic_fraggen|dynamic-fraggen)
            echo "fraggen"
            ;;
        dynamic_consensus|dynamic-consensus)
            echo "pdiff rted siamese fraggen"
            ;;
        consensus_pdiff_rted|consensus-pdiff-rted)
            echo "pdiff rted siamese fraggen"
            ;;
        # Standard SAF strategies
        *)
            echo "$saf"
            ;;
    esac
}

# Function to start a single SAF backend service
start_single_saf_backend() {
    local saf_type=$1
    local app=$2

    if [ "$saf_type" == "fraggen" ]; then
        log "FragGen doesn't need SAF service (built into Crawljax)"
        return 0
    fi

    log "Starting SAF backend service: $saf_type for $app"

    if [ "$saf_type" == "siamese" ]; then
        # Start Siamese SAF service
        cd "$PROJECT_ROOT"
        ./scripts/crawl-bench/run-saf-snn.sh "$app" > "saf-${saf_type}-${app}.log" 2>&1 &
        SAF_PID=$!
        echo $SAF_PID > "/tmp/saf-${saf_type}-${app}.pid"
        log "Siamese SAF backend started (PID: $SAF_PID)"
    elif [ "$saf_type" == "rted" ]; then
        # Start RTED baseline SAF service
        cd "$PROJECT_ROOT"
        ./scripts/crawl-bench/run-saf-baseline.sh "$app" DOM_RTED acrossapp > "saf-${saf_type}-${app}.log" 2>&1 &
        SAF_PID=$!
        echo $SAF_PID > "/tmp/saf-${saf_type}-${app}.pid"
        log "RTED SAF backend started (PID: $SAF_PID)"
    elif [ "$saf_type" == "pdiff" ]; then
        # Start PDiff baseline SAF service
        cd "$PROJECT_ROOT"
        ./scripts/crawl-bench/run-saf-baseline.sh "$app" VISUAL_PDiff acrossapp > "saf-${saf_type}-${app}.log" 2>&1 &
        SAF_PID=$!
        echo $SAF_PID > "/tmp/saf-${saf_type}-${app}.pid"
        log "PDiff SAF backend started (PID: $SAF_PID)"
    fi

    # Wait for SAF service to be ready
    sleep 10
    log "SAF backend service ready"
    return 0
}

# Function to start SAF service(s) for a strategy
start_saf_service() {
    local saf=$1
    local app=$2

    log "Starting SAF service(s) for strategy: $saf"

    # Get required SAF backends for this strategy
    local required_safs=$(get_required_safs "$saf")

    if [ -z "$required_safs" ]; then
        log_warning "No SAF backends required for strategy: $saf"
        return 0
    fi

    # Start each required SAF backend
    for saf_type in $required_safs; do
        if ! start_single_saf_backend "$saf_type" "$app"; then
            log_error "Failed to start SAF backend: $saf_type"
            return 1
        fi
    done

    log "All required SAF backends started for strategy: $saf"
    return 0
}

# Function to stop a single SAF backend service
stop_single_saf_backend() {
    local saf_type=$1
    local app=$2

    if [ "$saf_type" == "fraggen" ]; then
        return 0
    fi

    local pid_file="/tmp/saf-${saf_type}-${app}.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        log "Stopping SAF backend service (PID: $pid)"
        kill $pid 2>/dev/null || true
        sleep 2

        # Force kill if still alive
        if ps -p $pid > /dev/null 2>&1; then
            log_warning "Force killing SAF backend service (PID: $pid)"
            kill -9 $pid 2>/dev/null || true
        fi

        rm -f "$pid_file"
        log "SAF backend service ${saf_type} stopped"
    else
        log "No PID file found for SAF backend service ${saf_type}"
    fi
}

# Function to stop SAF service(s) for a strategy
stop_saf_service() {
    local saf=$1
    local app=$2

    log "Stopping SAF service(s) for strategy: ${saf}"

    # Get required SAF backends for this strategy
    local required_safs=$(get_required_safs "$saf")

    if [ -z "$required_safs" ]; then
        log "No SAF backends to stop for strategy: $saf"
        return 0
    fi

    # Stop each required SAF backend
    for saf_type in $required_safs; do
        stop_single_saf_backend "$saf_type" "$app"
    done

    log "All SAF backends stopped for strategy: ${saf}"
}

# Function to start Docker coverage container
start_docker_coverage() {
    local app=$1

    log "Starting Docker coverage container for $app"

    cd "$COVERAGE_BASE"

    # Build if needed
    if ! docker images | grep -q "${app}-coveragex"; then
        log "Building Docker image..."
        docker build --no-cache . -t "${app}-coveragex"
    fi

    # Start container
    log "Starting Docker container..."
    docker compose up -d

    # Wait for container to be ready
    log "Waiting for container to be ready..."
    sleep 15

    # Verify container is running
    if ! docker compose ps | grep -q "Up"; then
        log_error "Docker container failed to start"
        return 1
    fi

    log "Docker coverage container ready"
    return 0
}

# Function to get coverage URL for app
get_coverage_url() {
    local app=$1

    case "$app" in
        mantisbt)
            echo "http://localhost:3001/coverage"
            ;;
        mrbs)
            echo "http://localhost:3002/coverage"
            ;;
        ppma)
            echo "http://localhost:3003/coverage"
            ;;
        addressbook|claroline)
            echo "http://localhost:3004/coverage"
            ;;
        *)
            log_error "Unknown app for coverage URL: $app"
            return 1
            ;;
    esac
}

# Function to start code coverage recording
start_coverage_recording() {
    local app=$1
    local coverage_url=$(get_coverage_url "$app")

    if [ -z "$coverage_url" ]; then
        return 1
    fi

    log "Starting code coverage recording for $app"
    log "Coverage URL: ${coverage_url}/start.php"

    # Start coverage recording
    local response=$(curl -s -o /dev/null -w "%{http_code}" "${coverage_url}/start.php")

    if [ "$response" = "200" ]; then
        log "Code coverage recording started successfully"
        return 0
    else
        log_error "Failed to start coverage recording (HTTP $response)"
        return 1
    fi
}

# Function to stop code coverage recording and generate reports
stop_coverage_recording() {
    local app=$1
    local coverage_url=$(get_coverage_url "$app")

    if [ -z "$coverage_url" ]; then
        return 1
    fi

    log "Stopping code coverage recording for $app"
    log "Coverage URL: ${coverage_url}/stop.php"

    # Stop coverage and trigger report generation
    local response=$(curl -s -o /dev/null -w "%{http_code}" "${coverage_url}/stop.php")

    if [ "$response" = "200" ]; then
        log "Code coverage stopped successfully"
        log "Waiting for HTML report generation (this can take several minutes)..."

        # Wait for report generation - can take 3-5 minutes
        sleep 180

        log "Report generation wait completed"
        return 0
    else
        log_error "Failed to stop coverage recording (HTTP $response)"
        return 1
    fi
}

# Function to stop Docker coverage container
stop_docker_coverage() {
    local app=$1

    log "Stopping Docker coverage for $app"
    cd "$COVERAGE_BASE"
    docker compose down
    sleep 5
}

# Function to ensure Crawljax is built (run once)
ensure_crawljax_built() {
    local crawljax_root="$PROJECT_ROOT/ICST20-submission-material-DANTE/crawljax"
    local build_marker="$crawljax_root/.built_with_port_config"

    # Check if we've already built with our port configuration changes
    if [ -f "$build_marker" ]; then
        return 0
    fi

    log "Building Crawljax with port configuration changes..."
    cd "$crawljax_root"

    # Clean and build entire project (core + examples)
    mvn clean install -DskipTests >> "$PROJECT_ROOT/maven-build.log" 2>&1

    if [ $? -ne 0 ]; then
        log_error "Failed to build Crawljax project"
        log_error "Check maven-build.log for details"
        cd "$PROJECT_ROOT"
        return 1
    fi

    # Create marker file to avoid rebuilding
    touch "$build_marker"
    log "Crawljax built successfully"
    cd "$PROJECT_ROOT"
    return 0
}

# Function to run crawljax
run_crawljax() {
    local app=$1
    local saf=$2
    local traversal=$3

    log "Running Crawljax: $app with $saf SAF and $traversal traversal"

    # Ensure Crawljax is built (only happens once)
    if ! ensure_crawljax_built; then
        return 1
    fi

    # Navigate to Crawljax examples directory
    local crawljax_dir="$PROJECT_ROOT/ICST20-submission-material-DANTE/crawljax/examples"
    cd "$crawljax_dir"

    # Use Maven exec:java to run UnifiedRunner with proper classpath
    local maven_cmd="mvn exec:java -Dexec.mainClass=com.crawljax.examples.UnifiedRunner -Dexec.args='$app $saf $traversal'"

    log "Executing: $maven_cmd"
    log "Working directory: $crawljax_dir"

    # Run crawljax with timeout
    timeout ${CRAWL_WAIT_TIME}s bash -c "$maven_cmd" > "$PROJECT_ROOT/crawl-${app}-${saf}-${traversal}.log" 2>&1
    local exit_code=$?

    # Return to project root
    cd "$PROJECT_ROOT"

    if [ $exit_code -eq 0 ]; then
        log "Crawl completed successfully"
        return 0
    elif [ $exit_code -eq 124 ]; then
        log_warning "Crawl timed out (expected after ${MAX_RUNTIME} minutes)"
        return 0
    else
        log_error "Crawl failed with exit code $exit_code"
        log_error "Check log file: crawl-${app}-${saf}-${traversal}.log"
        return 1
    fi
}

# Function to rename coverage session
rename_coverage_session() {
    local saf=$1
    local traversal=$2

    log "Renaming coverage session folder"

    # Find the latest session directory
    if [ ! -d "$COVERAGE_SESSIONS_PATH" ]; then
        log_error "Coverage sessions path does not exist: $COVERAGE_SESSIONS_PATH"
        return 1
    fi

    # Get the most recent session folder
    local latest_session=$(ls -t "$COVERAGE_SESSIONS_PATH" 2>/dev/null | head -n 1)

    if [ -z "$latest_session" ]; then
        log_error "No coverage session found"
        return 1
    fi

    # Generate new name with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local new_name="${saf}_${traversal}_${timestamp}"

    local old_path="$COVERAGE_SESSIONS_PATH/$latest_session"
    local new_path="$COVERAGE_SESSIONS_PATH/$new_name"

    log "Renaming: $latest_session -> $new_name"
    mv "$old_path" "$new_path"

    if [ $? -eq 0 ]; then
        log "Coverage session renamed successfully"
        return 0
    else
        log_error "Failed to rename coverage session"
        return 1
    fi
}

# Function to cleanup processes
cleanup() {
    log "Cleaning up processes..."

    # Kill any running SAF services
    for saf in "${SAFS[@]}"; do
        stop_saf_service "$saf" "$APP_NAME"
    done

    # Stop Docker
    stop_docker_coverage "$APP_NAME" 2>/dev/null || true

    log "Cleanup complete"
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Main execution loop
log "Starting experiment runs..."
echo ""

for saf in "${SAFS[@]}"; do
    for traversal in "${TRAVERSALS[@]}"; do
        CURRENT_RUN=$((CURRENT_RUN + 1))

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  Run ${CURRENT_RUN}/${TOTAL_RUNS}: ${saf} + ${traversal}${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        # Start SAF service
        if ! start_saf_service "$saf" "$APP_NAME"; then
            log_error "Failed to start SAF service"
            FAILED_RUNS=$((FAILED_RUNS + 1))
            stop_saf_service "$saf" "$APP_NAME"
            continue
        fi

        # Start Docker coverage
        if ! start_docker_coverage "$APP_NAME"; then
            log_error "Failed to start Docker coverage"
            FAILED_RUNS=$((FAILED_RUNS + 1))
            stop_saf_service "$saf" "$APP_NAME"
            stop_docker_coverage "$APP_NAME"
            continue
        fi

        # Start code coverage recording
        if ! start_coverage_recording "$APP_NAME"; then
            log_error "Failed to start coverage recording"
            FAILED_RUNS=$((FAILED_RUNS + 1))
            stop_saf_service "$saf" "$APP_NAME"
            stop_docker_coverage "$APP_NAME"
            continue
        fi

        # Run Crawljax
        if ! run_crawljax "$APP_NAME" "$saf" "$traversal"; then
            log_error "Crawljax run failed"
            # Still try to stop coverage and save what we have
            stop_coverage_recording "$APP_NAME"
            FAILED_RUNS=$((FAILED_RUNS + 1))
        else
            # Stop code coverage recording and generate reports
            if ! stop_coverage_recording "$APP_NAME"; then
                log_error "Failed to stop coverage recording properly"
                FAILED_RUNS=$((FAILED_RUNS + 1))
            else
                # Rename coverage session
                if ! rename_coverage_session "$saf" "$traversal"; then
                    log_error "Failed to rename coverage session"
                    FAILED_RUNS=$((FAILED_RUNS + 1))
                else
                    SUCCESSFUL_RUNS=$((SUCCESSFUL_RUNS + 1))
                    log "Run completed successfully!"
                fi
            fi
        fi

        # Stop services
        stop_saf_service "$saf" "$APP_NAME"
        stop_docker_coverage "$APP_NAME"

        # Wait a bit before next run
        log "Waiting 30 seconds before next run..."
        sleep 30
        echo ""
    done
done

# Final summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Experiment Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "Total runs:       $TOTAL_RUNS"
echo -e "Successful:       ${GREEN}$SUCCESSFUL_RUNS${NC}"
echo -e "Failed:           ${RED}$FAILED_RUNS${NC}"
echo -e "Coverage path:    $COVERAGE_SESSIONS_PATH"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# List all coverage sessions
log "Coverage sessions created:"
ls -lh "$COVERAGE_SESSIONS_PATH" | grep -E "fraggen|pdiff|siamese|rted"

exit 0
