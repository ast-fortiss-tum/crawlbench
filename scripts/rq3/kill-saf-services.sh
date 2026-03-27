#!/bin/bash
################################################################################
# Utility script to kill running SAF services
# Usage: ./kill-saf-services.sh [app-name]
#
# If app-name is specified, only kills SAF services for that app
# If no app-name is specified, kills ALL SAF services
#
# Examples:
#   ./kill-saf-services.sh phoenix    # Kill only phoenix SAF services
#   ./kill-saf-services.sh            # Kill all SAF services
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

APP_NAME=$1

if [ -z "$APP_NAME" ]; then
    echo -e "${YELLOW}Killing ALL SAF services...${NC}"
else
    echo -e "${YELLOW}Killing SAF services for app: ${APP_NAME}${NC}"
fi
echo ""

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    echo "Detected Windows environment"

    # Kill Python processes running SAF services
    echo "Looking for Python processes running SAF services..."

    if [ -z "$APP_NAME" ]; then
        # Kill all SAF services
        powershell.exe -Command "
            \$killed = 0
            Get-Process python* -ErrorAction SilentlyContinue | ForEach-Object {
                \$pid = \$_.Id
                \$cmdLine = (Get-CimInstance Win32_Process -Filter \"ProcessId = \$pid\").CommandLine
                if (\$cmdLine -like '*saf-snn*' -or \$cmdLine -like '*saf-baseline*' -or \$cmdLine -like '*saf-other-baseline*') {
                    Write-Host \"Killing Python process \$pid\"
                    Stop-Process -Id \$pid -Force -ErrorAction SilentlyContinue
                    \$killed++
                }
            }
            if (\$killed -eq 0) {
                Write-Host 'No SAF service processes found'
            } else {
                Write-Host \"Killed \$killed process(es)\"
            }
        "
    else
        # Kill only SAF services for specific app
        powershell.exe -Command "
            \$killed = 0
            Get-Process python* -ErrorAction SilentlyContinue | ForEach-Object {
                \$pid = \$_.Id
                \$cmdLine = (Get-CimInstance Win32_Process -Filter \"ProcessId = \$pid\").CommandLine
                if ((\$cmdLine -like '*saf-snn*--appname*${APP_NAME}*') -or (\$cmdLine -like '*saf-baseline*${APP_NAME}*') -or (\$cmdLine -like '*saf-other-baseline*--appname*${APP_NAME}*')) {
                    Write-Host \"Killing Python process \$pid for app ${APP_NAME}\"
                    Stop-Process -Id \$pid -Force -ErrorAction SilentlyContinue
                    \$killed++
                }
            }
            if (\$killed -eq 0) {
                Write-Host 'No SAF service processes found for ${APP_NAME}'
            } else {
                Write-Host \"Killed \$killed process(es) for ${APP_NAME}\"
            }
        "
    fi
else
    echo "Detected Unix-like environment"

    if [ -z "$APP_NAME" ]; then
        # Kill all SAF services
        if pgrep -f "saf-snn.py" > /dev/null; then
            echo "Killing saf-snn.py processes..."
            pkill -f "saf-snn.py"
            echo "Done"
        else
            echo "No saf-snn.py processes found"
        fi

        if pgrep -f "saf-baseline.py" > /dev/null; then
            echo "Killing saf-baseline.py processes..."
            pkill -f "saf-baseline.py"
            echo "Done"
        else
            echo "No saf-baseline.py processes found"
        fi

        if pgrep -f "saf-other-baseline.py" > /dev/null; then
            echo "Killing saf-other-baseline.py processes..."
            pkill -f "saf-other-baseline.py"
            echo "Done"
        else
            echo "No saf-other-baseline.py processes found"
        fi
    else
        # Kill only SAF services for specific app
        if pgrep -f "saf-snn.py.*--appname.*${APP_NAME}" > /dev/null; then
            echo "Killing saf-snn.py processes for ${APP_NAME}..."
            pkill -f "saf-snn.py.*--appname.*${APP_NAME}"
            echo "Done"
        else
            echo "No saf-snn.py processes found for ${APP_NAME}"
        fi

        if pgrep -f "saf-other-baseline.py.*--appname.*${APP_NAME}" > /dev/null; then
            echo "Killing saf-other-baseline.py processes for ${APP_NAME}..."
            pkill -f "saf-other-baseline.py.*--appname.*${APP_NAME}"
            echo "Done"
        else
            echo "No saf-other-baseline.py processes found for ${APP_NAME}"
        fi
    fi
fi

# Clean up PID files
echo ""
echo "Cleaning up PID files..."
if [ -z "$APP_NAME" ]; then
    # Clean all SAF PID files
    rm -f /tmp/saf-*.pid 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "All PID files cleaned"
    else
        echo "No PID files to clean"
    fi
else
    # Clean only PID files for specific app
    rm -f /tmp/saf-*-${APP_NAME}.pid 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "PID files for ${APP_NAME} cleaned"
    else
        echo "No PID files to clean for ${APP_NAME}"
    fi
fi

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
