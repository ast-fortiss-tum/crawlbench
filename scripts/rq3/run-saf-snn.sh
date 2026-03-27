#!/bin/bash
# Script to run saf-snn.py for a single app
# Usage: ./run-saf-snn.sh <appname> [title] [setting]
# Example: ./run-saf-snn.sh mantisbt
# Example: ./run-saf-snn.sh mantisbt acrossapp_modernbert contrastive

# Check if at least one argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Application name is required"
    echo ""
    echo "Usage: ./run-saf-snn.sh <appname> [title] [setting]"
    echo ""
    echo "Available applications:"
    echo "  addressbook, claroline, ppma, mrbs, mantisbt, dimeshift, pagekit, phoenix, petclinic"
    echo ""
    echo "Available titles (optional, default: acrossapp_modernbert):"
    echo "  acrossapp_modernbert, acrossapp_bert, acrossapp_doc2vec, acrossapp_markuplm"
    echo "  withinapp_modernbert, withinapp_bert, withinapp_doc2vec, withinapp_markuplm"
    echo ""
    echo "Available settings (optional, default: contrastive):"
    echo "  contrastive, triplet"
    echo ""
    echo "Examples:"
    echo "  ./run-saf-snn.sh mantisbt"
    echo "  ./run-saf-snn.sh mrbs acrossapp_modernbert contrastive"
    echo "  ./run-saf-snn.sh ppma withinapp_doc2vec triplet"
    exit 1
fi

APPNAME=$1
TITLE=${2:-"acrossapp_modernbert"}
SETTING=${3:-"triplet"}

# Validate appname
VALID_APPS=("addressbook" "claroline" "ppma" "mrbs" "mantisbt" "dimeshift" "pagekit" "phoenix" "petclinic")
if [[ ! " ${VALID_APPS[@]} " =~ " ${APPNAME} " ]]; then
    echo "Error: Invalid application name: $APPNAME"
    echo "Valid applications: ${VALID_APPS[@]}"
    exit 1
fi

# Validate setting
if [[ "$SETTING" != "contrastive" && "$SETTING" != "triplet" ]]; then
    echo "Error: Invalid setting: $SETTING"
    echo "Valid settings: contrastive, triplet"
    exit 1
fi

echo "====================================================================="
echo "Running saf-snn.py with configuration:"
echo "  App Name: $APPNAME"
echo "  Title:    $TITLE"
echo "  Setting:  $SETTING"
echo "  Port:     Auto-assigned (500X based on app)"
echo "====================================================================="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_SCRIPT="$SCRIPT_DIR/saf-snn.py"

# Check if the Python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: saf-snn.py not found at $PYTHON_SCRIPT"
    exit 1
fi

# Run the Python script with arguments
python "$PYTHON_SCRIPT" --appname "$APPNAME" --title "$TITLE" --setting "$SETTING"
