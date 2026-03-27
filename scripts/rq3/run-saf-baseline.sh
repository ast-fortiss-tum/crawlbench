#!/bin/bash
# Script to run saf-other-baseline.py for a single app
# Usage: ./run-saf-baseline.sh <appname> [method] [setting]
# Example: ./run-saf-baseline.sh mantisbt
# Example: ./run-saf-baseline.sh mantisbt DOM_RTED acrossapp

# Check if at least one argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Application name is required"
    echo ""
    echo "Usage: ./run-saf-baseline.sh <appname> [method] [setting]"
    echo ""
    echo "Available applications:"
    echo "  addressbook, claroline, ppma, mrbs, mantisbt, dimeshift, pagekit, phoenix, petclinic"
    echo ""
    echo "Available methods (optional, default: DOM_RTED):"
    echo "  DOM_RTED, VISUAL_PDiff, webembed"
    echo ""
    echo "Available settings (optional, default: acrossapp):"
    echo "  acrossapp, withinapps"
    echo ""
    echo "Examples:"
    echo "  ./run-saf-baseline.sh mantisbt"
    echo "  ./run-saf-baseline.sh mrbs DOM_RTED acrossapp"
    echo "  ./run-saf-baseline.sh ppma VISUAL_PDiff withinapps"
    exit 1
fi

APPNAME=$1
METHOD=${2:-"DOM_RTED"}
SETTING=${3:-"acrossapp"}

# Validate appname
VALID_APPS=("addressbook" "claroline" "ppma" "mrbs" "mantisbt" "dimeshift" "pagekit" "phoenix" "petclinic")
if [[ ! " ${VALID_APPS[@]} " =~ " ${APPNAME} " ]]; then
    echo "Error: Invalid application name: $APPNAME"
    echo "Valid applications: ${VALID_APPS[@]}"
    exit 1
fi

# Validate method
if [[ "$METHOD" != "DOM_RTED" && "$METHOD" != "VISUAL_PDiff" && "$METHOD" != "webembed" ]]; then
    echo "Error: Invalid method: $METHOD"
    echo "Valid methods: DOM_RTED, VISUAL_PDiff, webembed"
    exit 1
fi

# Validate setting
if [[ "$SETTING" != "acrossapp" && "$SETTING" != "withinapps" ]]; then
    echo "Error: Invalid setting: $SETTING"
    echo "Valid settings: acrossapp, withinapps"
    exit 1
fi

echo "====================================================================="
echo "Running saf-other-baseline.py with configuration:"
echo "  App Name: $APPNAME"
echo "  Method:   $METHOD"
echo "  Setting:  $SETTING"
if [ "$METHOD" = "VISUAL_PDiff" ]; then
    echo "  Port:     Auto-assigned (700X for PDiff based on app)"
else
    echo "  Port:     Auto-assigned (600X for RTED based on app)"
fi
echo "====================================================================="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_SCRIPT="$SCRIPT_DIR/saf-other-baseline.py"

# Check if the Python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: saf-other-baseline.py not found at $PYTHON_SCRIPT"
    exit 1
fi

# Run the Python script with arguments
python "$PYTHON_SCRIPT" --appname "$APPNAME" --method "$METHOD" --setting "$SETTING"
