#!/bin/bash
################################################################################
# Automated Coverage Experiment Script for JavaScript Applications
#
# This script runs all combinations of SAFs and traversal methods for a JS app
# and automatically collects code coverage data.
#
# Usage: ./run-js-coverage-experiment.sh <app-name>
# Example: ./run-js-coverage-experiment.sh dimeshift
#
# SAFs: siamese, rted, pdiff, fraggen
# Traversal Methods: bfs, dfs, most_actions_first, priority_bfs
# JS Apps: dimeshift, pagekit, phoenix, petclinic
################################################################################

# NOTE: set -e removed to prevent premature exits on non-critical errors
# Error handling is done explicitly in critical sections

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DANTE_ROOT="$PROJECT_ROOT/ICST20-submission-material-DANTE/dante"
CRAWLJAX_ROOT="$PROJECT_ROOT/ICST20-submission-material-DANTE/crawljax"
TEMP_DIR="$PROJECT_ROOT/.temp"
mkdir -p "$TEMP_DIR"

# Results and Logs Configuration
RESULTS_BASE_DIR="$PROJECT_ROOT/results/crawlbench"
mkdir -p "$RESULTS_BASE_DIR"

SAFS=("dynamic-rted" "dynamic-pdiff" "dynamic-consensus")
TRAVERSALS=("bfs" "dfs" "most_actions_first" "priority_bfs")
MAX_RUNTIME=120  # minutes
CRAWL_WAIT_TIME=$((MAX_RUNTIME * 120 + 120))  # Runtime + 2 min buffer (in seconds)

# Create results directory
RESULTS_DIR="$RESULTS_BASE_DIR"
mkdir -p "$RESULTS_DIR"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Validate input
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Application name is required${NC}"
    echo ""
    echo "Usage: $0 <app-name>"
    echo ""
    echo "Available JavaScript applications:"
    echo "  dimeshift, pagekit, phoenix, petclinic"
    echo ""
    echo "Example:"
    echo "  $0 dimeshift"
    exit 1
fi

APP_NAME=$1
VALID_APPS=("dimeshift" "pagekit" "phoenix" "petclinic")

# Validate app name
if [[ ! " ${VALID_APPS[@]} " =~ " ${APP_NAME} " ]]; then
    echo -e "${RED}Error: Invalid application name: $APP_NAME${NC}"
    echo "Valid applications: ${VALID_APPS[@]}"
    exit 1
fi

# Determine element strategy for the app
get_element_strategy() {
    local app=$1
    case "$app" in
        dimeshift|pagekit|petclinic)
            echo "fired"
            ;;
        phoenix)
            echo "checked"
            ;;
        *)
            echo "fired"
            ;;
    esac
}

# Get unique database port for JavaScript apps
get_db_port() {
    local app=$1
    case "$app" in
        dimeshift)
            echo "3311"  # MySQL for dimeshift
            ;;
        pagekit)
            echo "3312"  # MySQL for pagekit
            ;;
        phoenix)
            echo "5433"  # PostgreSQL for phoenix (5432 + 1)
            ;;
        petclinic)
            echo "3314"  # MySQL for petclinic
            ;;
        *)
            echo "3306"  # Default MySQL
            ;;
    esac
}

# Get unique Tomcat port for Petclinic
get_tomcat_port() {
    local app=$1
    case "$app" in
        petclinic)
            echo "9967"  # Tomcat for petclinic (9966 + 1 to avoid conflicts)
            ;;
        *)
            echo "9966"  # Default
            ;;
    esac
}

# Get unique web/app port for JavaScript apps
get_app_port() {
    local app=$1
    case "$app" in
        dimeshift)
            echo "3006"
            ;;
        pagekit)
            echo "3007"
            ;;
        phoenix)
            echo "4000"
            ;;
        petclinic)
            echo "3009"
            ;;
        *)
            echo "3000"  # Default
            ;;
    esac
}

STRATEGY=$(get_element_strategy "$APP_NAME")

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  JavaScript Application Coverage Experiment Runner${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "Application:      ${GREEN}$APP_NAME${NC}"
echo -e "Strategy:         ${GREEN}$STRATEGY${NC}"
echo -e "SAFs:             ${SAFS[@]}"
echo -e "Traversals:       ${TRAVERSALS[@]}"
echo -e "Total runs:       ${GREEN}$((${#SAFS[@]} * ${#TRAVERSALS[@]}))${NC}"
echo -e "Max runtime:      ${MAX_RUNTIME} minutes per run"
echo -e "Results dir:      $RESULTS_DIR"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Initial cleanup of stale PID files only (don't kill running services)
log "Cleaning up stale PID files for ${APP_NAME}..."
rm -f /tmp/saf-*-${APP_NAME}.pid 2>/dev/null || true
log "Cleanup complete"
echo ""

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

# Store run information
RUN_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_LOG="$RESULTS_DIR/${APP_NAME}_experiment_${RUN_TIMESTAMP}.log"
COVERAGE_SUMMARY="$RESULTS_DIR/${APP_NAME}_coverage_summary_${RUN_TIMESTAMP}.csv"

# Initialize CSV summary
echo "SAF,Traversal,Status,CrawlTime,OutputDir,SeleniumActionsFile,CoveragePath,Timestamp" > "$COVERAGE_SUMMARY"

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

    local saf_log="$RESULTS_BASE_DIR/saf-${saf_type}-${app}.log"

    if [ "$saf_type" == "siamese" ]; then
        # Start Siamese SAF service
        cd "$PROJECT_ROOT"
        ./scripts/crawl-bench/run-saf-snn.sh "$app" > "$saf_log" 2>&1 &
        SAF_PID=$!
        echo $SAF_PID > "/tmp/saf-${saf_type}-${app}.pid"
        log "Siamese SAF backend started (PID: $SAF_PID, Log: $saf_log)"
    elif [ "$saf_type" == "rted" ]; then
        # Start RTED baseline SAF service
        cd "$PROJECT_ROOT"
        ./scripts/crawl-bench/run-saf-baseline.sh "$app" DOM_RTED acrossapp > "$saf_log" 2>&1 &
        SAF_PID=$!
        echo $SAF_PID > "/tmp/saf-${saf_type}-${app}.pid"
        log "RTED SAF backend started (PID: $SAF_PID, Log: $saf_log)"
    elif [ "$saf_type" == "pdiff" ]; then
        # Start PDiff baseline SAF service
        cd "$PROJECT_ROOT"
        ./scripts/crawl-bench/run-saf-baseline.sh "$app" VISUAL_PDiff acrossapp > "$saf_log" 2>&1 &
        SAF_PID=$!
        echo $SAF_PID > "/tmp/saf-${saf_type}-${app}.pid"
        log "PDiff SAF backend started (PID: $SAF_PID, Log: $saf_log)"
    fi

    # Wait for SAF service to be ready and verify it started
    log "Waiting for SAF backend service to initialize..."
    sleep 15

    # Verify the process is still running
    if [ -f "/tmp/saf-${saf_type}-${app}.pid" ]; then
        local pid=$(cat "/tmp/saf-${saf_type}-${app}.pid")
        if ps -p $pid > /dev/null 2>&1; then
            log "SAF backend service ready (PID: $pid still running)"
        else
            log_error "SAF backend service process died after starting (PID: $pid)"
            # Show last 20 lines of the log
            tail -20 "$saf_log"
            return 1
        fi
    else
        log_warning "No PID file found for SAF backend service"
    fi

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

    log "Stopping SAF backend service: ${saf_type} for ${app}"

    local pid_file="/tmp/saf-${saf_type}-${app}.pid"
    local pids_to_kill=()

    # Step 1: Get PID from file if exists
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        pids_to_kill+=($pid)
        log "Found PID from file: $pid"
    fi

    # Step 2: Search for processes by command line pattern
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows: Find all matching Python processes
        local found_pids=$(powershell.exe -Command "
            Get-Process python* -ErrorAction SilentlyContinue | ForEach-Object {
                \$pid = \$_.Id
                \$cmdLine = (Get-CimInstance Win32_Process -Filter \"ProcessId = \$pid\").CommandLine
                if (\$cmdLine -like '*saf-snn*--appname*${app}*' -or \$cmdLine -like '*saf-baseline*${app}*' -or \$cmdLine -like '*saf-other-baseline*--appname*${app}*') {
                    Write-Output \$pid
                }
            }
        " 2>/dev/null)

        if [ ! -z "$found_pids" ]; then
            while IFS= read -r pid; do
                if [ ! -z "$pid" ]; then
                    pids_to_kill+=($pid)
                fi
            done <<< "$found_pids"
        fi
    else
        # Unix: Find matching processes
        local found_pids=$(pgrep -f "saf-snn.py.*--appname.*${app}|saf-other-baseline.py.*--appname.*${app}" 2>/dev/null || true)
        if [ ! -z "$found_pids" ]; then
            while IFS= read -r pid; do
                if [ ! -z "$pid" ]; then
                    pids_to_kill+=($pid)
                fi
            done <<< "$found_pids"
        fi
    fi

    # Step 3: Kill all found PIDs
    if [ ${#pids_to_kill[@]} -gt 0 ]; then
        # Remove duplicates
        local unique_pids=($(printf '%s\n' "${pids_to_kill[@]}" | sort -u))

        log "Killing PIDs: ${unique_pids[@]}"
        for pid in "${unique_pids[@]}"; do
            if ps -p $pid > /dev/null 2>&1; then
                kill $pid 2>/dev/null || kill -9 $pid 2>/dev/null || true
                log "Killed PID: $pid"
            fi
        done

        # Wait a bit for processes to die
        sleep 2

        # Verify processes are dead
        for pid in "${unique_pids[@]}"; do
            if ps -p $pid > /dev/null 2>&1; then
                log_warning "Process $pid still running after kill attempt"
                kill -9 $pid 2>/dev/null || true
            fi
        done
    else
        log "No SAF backend processes found for ${saf_type}"
    fi

    # Clean up PID file
    rm -f "$pid_file" 2>/dev/null || true

    log "SAF backend service ${saf_type} stopped"
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

# Function to start Docker container
start_docker_app() {
    local app=$1
    local container_name="${app}-crawl-${RUN_TIMESTAMP}-${CURRENT_RUN}"
    local app_port=$(get_app_port "$app")
    local db_port=$(get_db_port "$app")

    log "Starting Docker container for $app"
    log "App port: $app_port, DB port: $db_port"

    # Clean up any containers using these ports (especially important for petclinic)
    log "Cleaning up any existing containers using ports $app_port and $db_port"
    local conflicting_containers=$(docker ps -a --format "{{.ID}} {{.Ports}}" | grep -E ":${app_port}->|:${db_port}->" | awk '{print $1}')
    if [ -n "$conflicting_containers" ]; then
        for cid in $conflicting_containers; do
            log "Removing conflicting container: $cid"
            docker stop "$cid" 2>/dev/null || true
            docker rm "$cid" 2>/dev/null || true
        done
        sleep 3
    fi

    cd "$DANTE_ROOT/docker/$app"

    # Start container with unique name and ports
    # Use MSYS_NO_PATHCONV=1 to prevent Git Bash path conversion on Windows
    if [ "$app" == "petclinic" ]; then
        # Petclinic has an extra Tomcat port
        local tomcat_port=$(get_tomcat_port "$app")
        log "Tomcat port: $tomcat_port"
        # Clean up containers using tomcat port too
        local tomcat_conflicts=$(docker ps -a --format "{{.ID}} {{.Ports}}" | grep ":${tomcat_port}->" | awk '{print $1}')
        if [ -n "$tomcat_conflicts" ]; then
            for cid in $tomcat_conflicts; do
                log "Removing conflicting container using tomcat port: $cid"
                docker stop "$cid" 2>/dev/null || true
                docker rm "$cid" 2>/dev/null || true
            done
            sleep 3
        fi
        MSYS_NO_PATHCONV=1 ./run-docker.sh -p yes -n "$container_name" -a "$app_port" -d "$db_port" -t "$tomcat_port"
    else
        MSYS_NO_PATHCONV=1 ./run-docker.sh -p yes -n "$container_name" -a "$app_port" -d "$db_port"
    fi

    # Wait for container to be ready
    log "Waiting for container to be ready..."
    sleep 60

    # Verify container is running
    # For petclinic, check for both server and client containers
    if [ "$app" == "petclinic" ]; then
        if ! docker ps | grep -q "${container_name}-server" || ! docker ps | grep -q "${container_name}-client"; then
            log_error "Docker container failed to start (petclinic needs both server and client)"
            return 1
        fi
    else
        if ! docker ps | grep -q "$container_name"; then
            log_error "Docker container failed to start"
            return 1
        fi
    fi

    log "Docker container ready: $container_name"
    echo "$container_name" > "$TEMP_DIR/docker-${app}-${CURRENT_RUN}.name" || {
        log_warning "Failed to write docker name file, continuing anyway"
    }
    return 0
}

# Function to stop Docker container
stop_docker_app() {
    local app=$1
    local name_file="$TEMP_DIR/docker-${app}-${CURRENT_RUN}.name"

    if [ -f "$name_file" ]; then
        local container_name=$(cat "$name_file")
        log "Stopping Docker container(s): $container_name"

        # For petclinic, we need to stop both -server and -client containers
        # For other apps, just stop the single container
        # Use grep with the base name to find all related containers
        local container_ids=$(docker ps -a --format "{{.ID}} {{.Names}}" | grep "$container_name" | awk '{print $1}')

        if [ -n "$container_ids" ]; then
            for container_id in $container_ids; do
                local container_full_name=$(docker ps -a --format "{{.ID}} {{.Names}}" | grep "^$container_id" | awk '{print $2}')
                log "Stopping container: $container_full_name (ID: $container_id)"
                docker stop "$container_id" 2>/dev/null || true
                docker rm "$container_id" 2>/dev/null || true
            done
        else
            log_warning "No containers found matching: $container_name"
        fi

        rm -f "$name_file"
        sleep 5
    fi
}

# Function to ensure Crawljax is built
ensure_crawljax_built() {
    # TEMPORARILY DISABLED: Assuming Crawljax is already built manually
    # To re-enable automatic build, uncomment the code below
    log "Skipping Crawljax build (assuming already built manually)"
    return 0

    # local build_marker="$CRAWLJAX_ROOT/.built_js_coverage_v2"
    # local unified_runner="$CRAWLJAX_ROOT/examples/src/main/java/com/crawljax/examples/UnifiedRunner.java"

    # # Check if we've already built AND UnifiedRunner.java hasn't been modified since
    # if [ -f "$build_marker" ]; then
    #     # If UnifiedRunner.java is newer than the marker, force rebuild
    #     if [ "$unified_runner" -nt "$build_marker" ]; then
    #         log "UnifiedRunner.java has been modified, rebuilding..."
    #         rm -f "$build_marker"
    #     else
    #         return 0
    #     fi
    # fi

    # log "Building Crawljax with JS coverage configuration..."
    # if ! cd "$CRAWLJAX_ROOT"; then
    #     log_error "Failed to navigate to Crawljax directory: $CRAWLJAX_ROOT"
    #     return 1
    # fi

    # # Clean and build entire project
    # mvn clean install -DskipTests >> "$RESULTS_BASE_DIR/maven-js-build.log" 2>&1

    # if [ $? -ne 0 ]; then
    #     log_error "Failed to build Crawljax project"
    #     log_error "Check maven-js-build.log for details"
    #     cd "$PROJECT_ROOT" 2>/dev/null || true
    #     return 1
    # fi

    # # Create marker file to avoid rebuilding
    # touch "$build_marker" || log_warning "Could not create build marker file"
    # log "Crawljax built successfully"
    # cd "$PROJECT_ROOT" 2>/dev/null || true
    # return 0
}

# Function to run crawljax
run_crawljax() {
    local app=$1
    local saf=$2
    local traversal=$3
    local run_id="${app}-${saf}-${traversal}-${RUN_TIMESTAMP}-${CURRENT_RUN}"

    log "Running Crawljax: $app with $saf SAF and $traversal traversal"

    # Ensure Crawljax is built
    if ! ensure_crawljax_built; then
        return 1
    fi

    # Navigate to Crawljax examples directory
    local crawljax_dir="$CRAWLJAX_ROOT/examples"
    if ! cd "$crawljax_dir" 2>/dev/null; then
        log_error "Failed to navigate to Crawljax directory: $crawljax_dir"
        return 1
    fi

    # Use Maven exec:java to run UnifiedRunner
    # UnifiedRunner will create unique selenium-actions filename: selenium-actions-{app}-{saf}-{traversal}-{timestamp}
    local maven_cmd="mvn exec:java -Dexec.mainClass=com.crawljax.examples.UnifiedRunner -Dexec.args='$app $saf $traversal'"

    log "Executing: $maven_cmd"
    log "Working directory: $crawljax_dir"

    # Verify we're in the right directory
    if [ ! -f "pom.xml" ]; then
        log_error "pom.xml not found in current directory: $(pwd)"
        cd "$PROJECT_ROOT" 2>/dev/null || true
        return 1
    fi

    # Run crawljax with timeout
    local crawl_log="$RESULTS_BASE_DIR/crawl-${run_id}.log"
    log "Crawl log will be written to: $crawl_log"

    # Build the final command with timeout if available
    timeout ${CRAWL_WAIT_TIME}s bash -c "$maven_cmd" > "$crawl_log" 2>&1
    local exit_code=$?

    log "Maven command finished with exit code: $exit_code"

    # Return to project root
    cd "$PROJECT_ROOT" 2>/dev/null || log_warning "Could not return to project root"

    if [ $exit_code -eq 0 ]; then
        log "Crawl completed successfully"
        echo "$crawl_log"
        return 0
    elif [ $exit_code -eq 124 ]; then
        log_warning "Crawl timed out (expected after ${MAX_RUNTIME} minutes)"
        echo "$crawl_log"
        return 0
    else
        log_error "Crawl failed with exit code $exit_code"
        log_error "Check log file: $crawl_log"
        echo "$crawl_log"
        return 1
    fi
}

# Function to organize crawl artifacts
organize_artifacts() {
    local app=$1
    local saf=$2
    local traversal=$3
    local crawl_log=$4
    local run_id="${app}-${saf}-${traversal}-${RUN_TIMESTAMP}-${CURRENT_RUN}"

    log "Organizing crawl artifacts"

    # Find the crawljax output directory (most recent with timestamp)
    local crawljax_out=$(ls -td "$CRAWLJAX_ROOT/examples/out/${app}"* 2>/dev/null | head -n 1)

    if [ -z "$crawljax_out" ] || [ ! -d "$crawljax_out" ]; then
        log_error "Crawljax output directory not found"
        return 1
    fi

    log "Found crawljax output: $crawljax_out"

    # Create application directory in DANTE
    local dante_app_dir="$DANTE_ROOT/applications/$app"
    mkdir -p "$dante_app_dir"

    # First, copy to archive with unique name
    local target_dir_archive="$dante_app_dir/${run_id}"
    log "Archiving crawljax output to: $target_dir_archive"
    cp -r "$crawljax_out" "$target_dir_archive"

    # Then extract localhost directory to standard location for DANTE scripts
    local target_dir_standard="$dante_app_dir"
    log "Moving localhost directory to standard location: $target_dir_standard"

    # Remove old localhost if exists
    rm -rf "$target_dir_standard/localhost" 2>/dev/null || true

    # Move the localhost directory from crawljax output to standard location
    if [ -d "$crawljax_out/localhost" ]; then
        mv "$crawljax_out/localhost" "$target_dir_standard/"
        log "Moved localhost directory successfully"
    else
        log_error "localhost directory not found in crawljax output: $crawljax_out"
        return 1
    fi

    # Remove the now-empty crawljax output directory
    rm -rf "$crawljax_out" 2>/dev/null || true

    # Rename crawl0 to crawl-with-inputs in both locations
    if [ -d "$target_dir_standard/localhost/crawl0" ]; then
        mv "$target_dir_standard/localhost/crawl0" "$target_dir_standard/localhost/crawl-with-inputs"
        log "Renamed crawl0 to crawl-with-inputs in standard location"
    fi
    if [ -d "$target_dir_archive/localhost/crawl0" ]; then
        mv "$target_dir_archive/localhost/crawl0" "$target_dir_archive/localhost/crawl-with-inputs"
        log "Renamed crawl0 to crawl-with-inputs in archive"
    fi

    # Find and copy selenium-actions file from crawljax output directory
    # Crawljax now writes to output dir: selenium-actions-{app}-{saf}-{traversal}-{timestamp}
    local selenium_pattern="selenium-actions-${app}-${saf}-${traversal}-*"
    local selenium_file=$(find "$target_dir_archive" -name "$selenium_pattern" -type f 2>/dev/null | head -n 1)
    local target_selenium_archive="$dante_app_dir/selenium-actions-${run_id}.txt"
    local target_selenium_standard="$dante_app_dir/selenium-actions-${app}-${STRATEGY}.txt"

    if [ -f "$selenium_file" ]; then
        log "Found selenium-actions file in crawljax output: $(basename $selenium_file)"

        # Check if file is not empty and has at least one driver command
        local line_count=$(wc -l < "$selenium_file" 2>/dev/null || echo "0")
        local has_content=$(grep -c "driver\." "$selenium_file" 2>/dev/null || echo "0")

        if [ "$line_count" -gt 0 ] && [ "$has_content" -gt 0 ]; then
            # File looks valid - copy it
            cp "$selenium_file" "$target_selenium_archive" 2>/dev/null || {
                log_warning "Failed to copy selenium-actions, trying alternative method"
                cat "$selenium_file" > "$target_selenium_archive" 2>/dev/null || {
                    log_error "Could not copy selenium-actions file"
                    target_selenium_archive=""
                    return 1
                }
            }

            # Also copy to standard location for DANTE scripts
            if [ -n "$target_selenium_archive" ] && [ -f "$target_selenium_archive" ]; then
                cp "$target_selenium_archive" "$target_selenium_standard"
                log "Copied selenium-actions to archive: $target_selenium_archive"
                log "Also copied to standard location: $target_selenium_standard"
            fi
        else
            log_error "selenium-actions file is empty or has no driver commands"
            log_error "This crawl did not generate any selenium actions"
            return 1
        fi
    else
        log_error "selenium-actions file not found matching pattern: $selenium_pattern"
        log_error "This crawl did not generate any selenium actions"
        return 1
    fi

    # Copy crawl log to results directory (if it exists and is a valid file)
    if [ -f "$crawl_log" ]; then
        local result_crawl_log="$RESULTS_DIR/${run_id}.log"
        cp "$crawl_log" "$result_crawl_log" 2>/dev/null || {
            log_warning "Could not copy crawl log to results directory"
        }
    fi

    # Extract crawl time from result.json if available
    local result_json="$target_dir_standard/localhost/crawl-with-inputs/result.json"
    local crawl_time="N/A"
    if [ -f "$result_json" ]; then
        # Extract duration field (in milliseconds)
        crawl_time=$(grep -oP '"duration":\s*\K[0-9]+' "$result_json" 2>/dev/null || echo "N/A")
        if [ "$crawl_time" != "N/A" ]; then
            # Convert to minutes
            crawl_time=$(echo "scale=2; $crawl_time / 60000" | bc 2>/dev/null || echo "N/A")
        fi
    fi

    # Store paths for later use
    echo "$target_dir_archive" > "/tmp/crawl-output-${CURRENT_RUN}.path"
    echo "$target_selenium_archive" > "/tmp/selenium-actions-${CURRENT_RUN}.path"
    echo "$crawl_time" > "/tmp/crawl-time-${CURRENT_RUN}.txt"

    log "Artifacts organized successfully"
    log "Archive: $target_dir_archive"
    log "Standard: $target_dir_standard/localhost"
    return 0
}

# Function to generate test suite and collect coverage
generate_tests_and_coverage() {
    local app=$1
    local saf=$2
    local traversal=$3
    local run_id="${app}-${saf}-${traversal}-${RUN_TIMESTAMP}-${CURRENT_RUN}"

    log "Generating test suite and collecting coverage"

    cd "$DANTE_ROOT"

    # Verify crawl data exists
    local crawl_data_dir="$DANTE_ROOT/applications/$app/localhost/crawl-with-inputs"
    if [ ! -d "$crawl_data_dir" ]; then
        log_error "Crawl data directory not found: $crawl_data_dir"
        return 1
    fi
    log "Verified crawl data exists at: $crawl_data_dir"

    # Build DANTE if not already built
    if [ ! -d "target/classes" ] || [ ! -f "target/classes/com/dante/suitegenerator/TestSuiteGenerator.class" ]; then
        log "Building DANTE framework (this may take several minutes)..."
        mvn clean install -DskipTests > "$RESULTS_DIR/${run_id}-dante-build.log" 2>&1
        if [ $? -ne 0 ]; then
            log_error "Failed to build DANTE framework"
            log_error "Check log: $RESULTS_DIR/${run_id}-dante-build.log"
            return 1
        fi
        log "DANTE framework built successfully"
    else
        log "DANTE framework already built"
    fi

    # Setup classpath for DANTE - use the exact classpath from generate-java-project-from-crawling.sh
    log "Setting up classpath for DANTE"

    # DANTE classes must come FIRST in classpath, and use absolute path
    local dante_classes="$DANTE_ROOT/target/classes"

    # Verify DANTE classes exist
    if [ ! -d "$dante_classes" ]; then
        log_error "DANTE classes directory not found: $dante_classes"
        return 1
    fi

    if [ ! -f "$dante_classes/com/dante/suitegenerator/TestSuiteGenerator.class" ]; then
        log_error "TestSuiteGenerator.class not found in: $dante_classes"
        return 1
    fi

    log "Verified TestSuiteGenerator.class exists"

    # This is the complete classpath as defined in the original generate script
    # Added roaster-api and roaster-jdt JARs to fix JavaClassSource missing class error
    local classpath="$dante_classes:$HOME/.m2/repository/io/pebbletemplates/pebble/3.0.8/pebble-3.0.8.jar:$HOME/.m2/repository/org/unbescape/unbescape/1.1.6.RELEASE/unbescape-1.1.6.RELEASE.jar:$HOME/.m2/repository/org/slf4j/slf4j-api/1.7.25/slf4j-api-1.7.25.jar:$HOME/.m2/repository/com/crawljax/crawljax-core/5.2.4-SNAPSHOT/crawljax-core-5.2.4-SNAPSHOT.jar:$HOME/.m2/repository/log4j/log4j/1.2.17/log4j-1.2.17.jar:$HOME/.m2/repository/org/apache/logging/log4j/log4j-core/2.11.2/log4j-core-2.11.2.jar:$HOME/.m2/repository/org/apache/logging/log4j/log4j-api/2.11.2/log4j-api-2.11.2.jar:$HOME/.m2/repository/org/testng/testng/7.0.0-beta1/testng-7.0.0-beta1.jar:$HOME/.m2/repository/com/beust/jcommander/1.72/jcommander-1.72.jar:$HOME/.m2/repository/org/jboss/forge/roaster/roaster-api/2.20.8.Final/roaster-api-2.20.8.Final.jar:$HOME/.m2/repository/org/jboss/forge/roaster/roaster-jdt/2.20.8.Final/roaster-jdt-2.20.8.Final.jar"

    log "Classpath configured with $(echo $classpath | tr ':' '\n' | wc -l) entries"

    # Set application name in properties
    local properties_file="src/main/resources/app.properties"
    log "Configuring application properties for $app"

    # Get the correct URL for this app
    local app_port=$(get_app_port "$app")
    local app_url=""
    case "$app" in
        dimeshift)
            app_url="http://localhost:${app_port}"
            ;;
        pagekit)
            app_url="http://localhost:${app_port}/pagekit/index.php/admin/login"
            ;;
        phoenix)
            app_url="http://localhost:${app_port}"
            ;;
        petclinic)
            app_url="http://localhost:${app_port}/petclinic"
            ;;
        *)
            app_url="http://localhost:${app_port}"
            ;;
    esac

    log "Setting URL to: $app_url"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i "" "s/application_name=.*/application_name=$app/g" "$properties_file"
        sed -i "" "s|url=.*|url=$app_url|g" "$properties_file"
        sed -i "" "s/headless=.*/headless=false/g" "$properties_file"
    else
        sed -i "s/application_name=.*/application_name=$app/g" "$properties_file"
        sed -i "s|url=.*|url=$app_url|g" "$properties_file"
        sed -i "s/headless=.*/headless=false/g" "$properties_file"
    fi

    # Set element strategy (fired vs checked)
    if [[ "$app" == "phoenix" ]]; then
        log "Setting element strategy: checked (for Phoenix)"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i "" "s/GeneratedTestSuite.*.java/GeneratedTestSuiteChecked.java/g" "$properties_file"
            sed -i "" "s/fired_element_strategy=.*/fired_element_strategy=false/g" "$properties_file"
        else
            sed -i "s/GeneratedTestSuite.*.java/GeneratedTestSuiteChecked.java/g" "$properties_file"
            sed -i "s/fired_element_strategy=.*/fired_element_strategy=false/g" "$properties_file"
        fi
    else
        log "Setting element strategy: fired"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i "" "s/GeneratedTestSuite.*.java/GeneratedTestSuiteFired.java/g" "$properties_file"
            sed -i "" "s/fired_element_strategy=.*/fired_element_strategy=true/g" "$properties_file"
        else
            sed -i "s/GeneratedTestSuite.*.java/GeneratedTestSuiteFired.java/g" "$properties_file"
            sed -i "s/fired_element_strategy=.*/fired_element_strategy=true/g" "$properties_file"
        fi
    fi

    # Generate test suite using Java directly
    log "Generating test suite with TestSuiteGenerator"
    java -cp "$classpath" com.dante.suitegenerator.TestSuiteGenerator > "$RESULTS_DIR/${run_id}-generate.log" 2>&1

    if [ $? -ne 0 ]; then
        log_error "Failed to generate test suite"
        log_error "Check log: $RESULTS_DIR/${run_id}-generate.log"
        return 1
    fi

    log "Test suite generated successfully"

    # Check if test suite was created
    local testsuite_dir="$DANTE_ROOT/applications/$app/testsuite-$app"
    if [ ! -d "$testsuite_dir" ]; then
        log_error "Test suite directory not created: $testsuite_dir"
        return 1
    fi
    log "Test suite created at: $testsuite_dir"

    # Get ports for this app
    local app_port=$(get_app_port "$app")
    local db_port=$(get_db_port "$app")
    local element_strategy=$([ "$app" == "phoenix" ] && echo "checked" || echo "fired")

    # Start Docker container for test execution
    log "Starting Docker container for test execution (ports: $app_port, $db_port)"
    local container_name="${app}-test-${RUN_TIMESTAMP}-${CURRENT_RUN}"

    cd "$DANTE_ROOT/docker/$app"
    if [ "$app" == "petclinic" ]; then
        local tomcat_port=$(get_tomcat_port "$app")
        MSYS_NO_PATHCONV=1 ./run-docker.sh -p yes -n "$container_name" -a "$app_port" -d "$db_port" -t "$tomcat_port" > "$RESULTS_DIR/${run_id}-docker-test.log" 2>&1 &
    else
        MSYS_NO_PATHCONV=1 ./run-docker.sh -p yes -n "$container_name" -a "$app_port" -d "$db_port" > "$RESULTS_DIR/${run_id}-docker-test.log" 2>&1 &
    fi

    sleep 60  # Wait for container to start
    log "Docker container started: $container_name"

    # Compile and run tests (first pass - no coverage)
    log "Compiling and running tests (first pass)"
    cd "$testsuite_dir"

    if [ -f "compile-and-run-${element_strategy}.sh" ]; then
        chmod +x "compile-and-run-${element_strategy}.sh"
        ./compile-and-run-${element_strategy}.sh true false > "$RESULTS_DIR/${run_id}-test-run.log" 2>&1

        if [ $? -ne 0 ]; then
            log_warning "Some tests may have failed, but continuing"
        else
            log "Tests compiled and executed successfully"
        fi
    else
        log_error "compile-and-run script not found: compile-and-run-${element_strategy}.sh"
        # Stop Docker and return
        docker stop "$container_name" 2>/dev/null
        docker rm "$container_name" 2>/dev/null
        cd "$PROJECT_ROOT"
        return 1
    fi

    # Stop and restart Docker for coverage collection
    log "Restarting Docker container for coverage collection"
    docker stop "$container_name" 2>/dev/null
    docker rm "$container_name" 2>/dev/null
    sleep 5

    cd "$DANTE_ROOT/docker/$app"
    if [ "$app" == "petclinic" ]; then
        local tomcat_port=$(get_tomcat_port "$app")
        MSYS_NO_PATHCONV=1 ./run-docker.sh -p yes -n "$container_name" -a "$app_port" -d "$db_port" -t "$tomcat_port" > "$RESULTS_DIR/${run_id}-docker-coverage.log" 2>&1 &
    else
        MSYS_NO_PATHCONV=1 ./run-docker.sh -p yes -n "$container_name" -a "$app_port" -d "$db_port" > "$RESULTS_DIR/${run_id}-docker-coverage.log" 2>&1 &
    fi

    sleep 60  # Wait for container to start
    log "Docker container restarted for coverage"

    # Run tests with coverage collection
    log "Running tests with JavaScript coverage collection"
    cd "$testsuite_dir"
    ./compile-and-run-${element_strategy}.sh false true > "$RESULTS_DIR/${run_id}-coverage-run.log" 2>&1

    if [ $? -ne 0 ]; then
        log_warning "Coverage collection may have encountered issues"
    else
        log "Coverage collected successfully"
    fi

    # Stop Docker container
    log "Stopping Docker container: $container_name"
    docker stop "$container_name" 2>/dev/null
    docker rm "$container_name" 2>/dev/null

    # Copy coverage reports
    local found_coverage=false

    # First check all-coverage-reports directory
    if [ -d "$testsuite_dir/all-coverage-reports" ]; then
        local coverage_report="$testsuite_dir/all-coverage-reports/test-suite-report.txt"
        if [ -f "$coverage_report" ]; then
            local target_coverage="$RESULTS_DIR/${app}_${saf}_${traversal}_${RUN_TIMESTAMP}-${CURRENT_RUN}.txt"
            cp "$coverage_report" "$target_coverage"
            log "Coverage report saved to: $target_coverage"
            echo "$target_coverage" > "/tmp/coverage-path-${CURRENT_RUN}.txt"
            found_coverage=true
        fi
    fi

    # Also check coverage-reports directory (fallback location)
    if [ "$found_coverage" = false ] && [ -d "$testsuite_dir/coverage-reports" ]; then
        local coverage_report="$testsuite_dir/coverage-reports/test-suite-report.txt"
        if [ -f "$coverage_report" ]; then
            local target_coverage="$RESULTS_DIR/${app}_${saf}_${traversal}_${RUN_TIMESTAMP}-${CURRENT_RUN}.txt"
            cp "$coverage_report" "$target_coverage"
            log "Coverage report saved to: $target_coverage"
            echo "$target_coverage" > "/tmp/coverage-path-${CURRENT_RUN}.txt"
            found_coverage=true
        fi
    fi

    if [ "$found_coverage" = false ]; then
        log_warning "Coverage report not found in all-coverage-reports or coverage-reports directories"
        echo "" > "/tmp/coverage-path-${CURRENT_RUN}.txt"
    fi

    # Check for Desktop logs as backup
    local coverage_log="$HOME/Desktop/logs_MeasureCoverageOfTests_crawljax_${app}.txt"
    local test_log="$HOME/Desktop/logs_RunTests_crawljax_${app}.txt"

    if [ -f "$coverage_log" ]; then
        local target_coverage_desktop="$RESULTS_DIR/${run_id}-coverage-desktop.txt"
        cp "$coverage_log" "$target_coverage_desktop"
        log "Desktop coverage log saved to: $target_coverage_desktop"
    fi

    if [ -f "$test_log" ]; then
        local target_test="$RESULTS_DIR/${run_id}-test-results.txt"
        cp "$test_log" "$target_test"
        log "Test log saved to: $target_test"
    fi

    cd "$PROJECT_ROOT"
    log "Test generation and coverage collection completed"
    return 0
}

# Function to record run results
record_results() {
    local saf=$1
    local traversal=$2
    local status=$3
    local run_id="${APP_NAME}-${saf}-${traversal}-${RUN_TIMESTAMP}-${CURRENT_RUN}"

    local output_dir=$(cat "$TEMP_DIR/crawl-output-${CURRENT_RUN}.path" 2>/dev/null || echo "N/A")
    local selenium_file=$(cat "$TEMP_DIR/selenium-actions-${CURRENT_RUN}.path" 2>/dev/null || echo "N/A")
    local crawl_time=$(cat "$TEMP_DIR/crawl-time-${CURRENT_RUN}.txt" 2>/dev/null || echo "N/A")
    local coverage_path=$(cat "$TEMP_DIR/coverage-path-${CURRENT_RUN}.txt" 2>/dev/null || echo "N/A")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Append to CSV
    echo "$saf,$traversal,$status,$crawl_time,$output_dir,$selenium_file,$coverage_path,$timestamp" >> "$COVERAGE_SUMMARY"

    # Cleanup temp files
    rm -f "/tmp/crawl-output-${CURRENT_RUN}.path"
    rm -f "/tmp/selenium-actions-${CURRENT_RUN}.path"
    rm -f "/tmp/crawl-time-${CURRENT_RUN}.txt"
    rm -f "/tmp/coverage-path-${CURRENT_RUN}.txt"
}

# Function to cleanup processes
cleanup() {
    log "Cleaning up processes..."

    # Kill any running SAF services
    for saf in "${SAFS[@]}"; do
        stop_saf_service "$saf" "$APP_NAME"
    done

    # Stop any Docker containers
    stop_docker_app "$APP_NAME" 2>/dev/null || true

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

        RUN_STATUS="FAILED"

        # Ensure previous SAF service is completely stopped before starting new one
        log "Ensuring no stale SAF service from previous iteration..."
        stop_saf_service "$saf" "$APP_NAME"

        # Extra verification: wait a bit and check port is free
        sleep 3

        # Start SAF service
        if ! start_saf_service "$saf" "$APP_NAME"; then
            log_error "Failed to start SAF service"
            FAILED_RUNS=$((FAILED_RUNS + 1))
            record_results "$saf" "$traversal" "FAILED_SAF_START"
            stop_saf_service "$saf" "$APP_NAME"
            continue
        fi

        # Start Docker app
        if ! start_docker_app "$APP_NAME"; then
            log_error "Failed to start Docker app"
            FAILED_RUNS=$((FAILED_RUNS + 1))
            record_results "$saf" "$traversal" "FAILED_DOCKER_START"
            stop_saf_service "$saf" "$APP_NAME"
            stop_docker_app "$APP_NAME"
            continue
        fi

        # Run Crawljax
        crawl_log=$(run_crawljax "$APP_NAME" "$saf" "$traversal")
        if [ $? -ne 0 ]; then
            log_error "Crawljax run failed"
            FAILED_RUNS=$((FAILED_RUNS + 1))
            record_results "$saf" "$traversal" "FAILED_CRAWL"
            stop_saf_service "$saf" "$APP_NAME"
            stop_docker_app "$APP_NAME"
            continue
        fi

        # Stop Docker app before generating tests
        stop_docker_app "$APP_NAME"

        # Organize artifacts
        if ! organize_artifacts "$APP_NAME" "$saf" "$traversal" "$crawl_log"; then
            log_error "Failed to organize artifacts"
            FAILED_RUNS=$((FAILED_RUNS + 1))
            record_results "$saf" "$traversal" "FAILED_ORGANIZE"
            stop_saf_service "$saf" "$APP_NAME"
            continue
        fi

        # Generate test suite and collect coverage
        if ! generate_tests_and_coverage "$APP_NAME" "$saf" "$traversal"; then
            log_warning "Coverage collection had issues, but continuing"
            RUN_STATUS="PARTIAL_SUCCESS"
        else
            RUN_STATUS="SUCCESS"
            SUCCESSFUL_RUNS=$((SUCCESSFUL_RUNS + 1))
            log "Run completed successfully!"
        fi

        # Record results
        record_results "$saf" "$traversal" "$RUN_STATUS"

        # Stop SAF service and ensure it's completely stopped
        log "Stopping SAF service after run completion..."
        stop_saf_service "$saf" "$APP_NAME"

        # Wait longer before next run to ensure complete cleanup
        log "Waiting 10 seconds for complete cleanup before next run..."
        sleep 10
        echo ""
    done
done

# Final summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Experiment Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "Application:      $APP_NAME"
echo -e "Total runs:       $TOTAL_RUNS"
echo -e "Successful:       ${GREEN}$SUCCESSFUL_RUNS${NC}"
echo -e "Failed:           ${RED}$FAILED_RUNS${NC}"
echo -e "Results dir:      $RESULTS_DIR"
echo -e "Summary CSV:      $COVERAGE_SUMMARY"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

log "Results summary:"
cat "$COVERAGE_SUMMARY"

exit 0
