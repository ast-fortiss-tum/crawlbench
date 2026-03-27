import os
import json
import pickle
from flask import Flask, request, jsonify
import sys, pathlib

sys.path.append(str(pathlib.Path(__file__).resolve().parents[2]))

from scripts.utils.utils import fix_json_crawling

# -----------------------------------------------------------------
#  Global settings and baseline model info
# -----------------------------------------------------------------
no_of_inferences = 0
BASE_PATH = os.getcwd()
MODEL_DIR = f"{BASE_PATH}/baseline-models"
SELECTED_APPS = [
    'addressbook', 'claroline', 'ppma', 'mrbs',
    'mantisbt', 'dimeshift', 'pagekit', 'phoenix', 'petclinic'
]

baseline_model_info = {
    "webembed": {
        "withinapps": "within-apps-{app}-svm-rbf-doc2vec-distance-content-tags.sav",
        "acrossapp": "across-apps-{app}-svm-rbf-doc2vec-distance-content-tags.sav",
    },
    "DOM_RTED": {
        "withinapps": "within-apps-{app}-svm-rbf-dom-rted.sav",
        "acrossapp": "across-apps-{app}-svm-rbf-dom-rted.sav",
    },
    "VISUAL_PDiff": {
        "withinapps": "within-apps-{app}-svm-rbf-visual-pdiff.sav",
        "acrossapp": "across-apps-{app}-svm-rbf-visual-pdiff.sav",
    }
}

def increase_no_of_inferences():
    global no_of_inferences
    no_of_inferences += 1
    if no_of_inferences % 10 == 0:
        print(f"[Info] Number of inferences: {no_of_inferences}")


def load_baseline_model(appname, method, setting):
    """
    appname: e.g. 'mantisbt'
    method:  e.g. 'webembed', 'DOM_RTED', or 'VISUAL_PDiff'
    setting: 'withinapps' or 'acrossapp'
    Returns a loaded SVM model.
    """
    if appname not in SELECTED_APPS:
        raise ValueError(f"Unknown appname: {appname}")
    if method not in baseline_model_info:
        raise ValueError(f"Unknown baseline method: {method}")
    if setting not in baseline_model_info[method]:
        raise ValueError(f"Unknown baseline setting for {method}: {setting}")

    filename = baseline_model_info[method][setting].format(app=appname)
    model_path = os.path.join(MODEL_DIR, filename)
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file not found: {model_path}")
    with open(model_path, 'rb') as f:
        clf = pickle.load(f)
    return clf

def saf_equals_baseline_distance(distance, classifier):
    """
    Returns 1 if predicted near-duplicate (true), 0 if distinct (false).
    """
    pred = classifier.predict([[distance]])[0]
    return int(pred)


# -----------------------------------------------------------------
#  Parse command-line arguments
# -----------------------------------------------------------------
import argparse
parser = argparse.ArgumentParser(description='Run Baseline SAF Flask server')
parser.add_argument('--appname', type=str, default=None, help='Application name')
parser.add_argument('--method', type=str, default=None, choices=['DOM_RTED', 'VISUAL_PDiff', 'webembed'], help='Baseline method')
parser.add_argument('--setting', type=str, default=None, choices=['withinapps', 'acrossapp'], help='Setting type')
parser.add_argument('--port', type=int, default=None, help='Port number for Flask server (default: auto-assigned based on app)')
args = parser.parse_args()

# Port mapping for RTED (DOM-based) SAF services (6001-6009)
app_to_port_rted = {
    'mantisbt': 6001,
    'mrbs': 6002,
    'ppma': 6003,
    'addressbook': 6004,
    'claroline': 6005,
    'dimeshift': 6006,
    'pagekit': 6007,
    'phoenix': 6008,
    'petclinic': 6009,
}

# Port mapping for PDiff (Visual-based) SAF services (7001-7009)
app_to_port_pdiff = {
    'mantisbt': 7001,
    'mrbs': 7002,
    'ppma': 7003,
    'addressbook': 7004,
    'claroline': 7005,
    'dimeshift': 7006,
    'pagekit': 7007,
    'phoenix': 7008,
    'petclinic': 7009,
}

# Use command-line args if provided, otherwise use defaults from file
appname = args.appname if args.appname else "mantisbt"  # one of SELECTED_APPS
method = args.method if args.method else "DOM_RTED"  # one of:"DOM_RTED", "VISUAL_PDiff", "webembed"
setting = args.setting if args.setting else "acrossapp"  # either 'withinapps' or 'acrossapp'

# Auto-assign port based on app and method
if args.port:
    port = args.port
elif method == "VISUAL_PDiff":
    port = app_to_port_pdiff.get(appname, 7000)
else:  # DOM_RTED or webembed
    port = app_to_port_rted.get(appname, 6000)

# -----------------------------------------------------------------
#  Build the Flask app
# -----------------------------------------------------------------
app = Flask(__name__)

classifier_baseline = load_baseline_model(appname, method, setting)

@app.route('/', methods=['GET'])
def index():
    return jsonify({
        "status": "OK",
        "message": "Baseline Service is up. Call /equals to compare two states."
    })


@app.route('/equals', methods=['POST'])
def equals_route():
    content_type = request.headers.get('Content-Type')
    if content_type not in ('application/json', 'application/json; utf-8'):
        return 'Content-Type not supported!', 400

    fixed_json = fix_json_crawling(request.data.decode('utf-8'))
    if fixed_json == "Error decoding JSON":
        print("Exiting due to JSON error")
        return "Error decoding JSON", 400

    data = json.loads(fixed_json)
    print(data)

    distance = data['distance']

    nd_label = saf_equals_baseline_distance(distance, classifier_baseline)
    result = "true" if nd_label == 1 else "false"

    increase_no_of_inferences()
    print(f"[Info] Distance: {distance}, result -> {result}")
    return result


if __name__ == "__main__":
    import sys
    print(f"******* Starting Baseline SAF: {appname} - {method} - {setting} *******")
    print(f"******* Flask server starting on port {port} *******")

    # Try to start the server with error handling
    max_retries = 3
    for attempt in range(max_retries):
        try:
            app.run(debug=False, host='0.0.0.0', port=port, use_reloader=False)
            break  # If successful, break out of retry loop
        except OSError as e:
            if "Address already in use" in str(e) or "address already in use" in str(e).lower():
                if attempt < max_retries - 1:
                    print(f"[Warning] Port {port} is in use, retrying in 5 seconds (attempt {attempt + 1}/{max_retries})...")
                    import time
                    time.sleep(5)
                else:
                    print(f"[Error] Port {port} is still in use after {max_retries} attempts. Exiting.")
                    sys.exit(1)
            else:
                print(f"[Error] Failed to start Flask server: {e}")
                sys.exit(1)
        except Exception as e:
            print(f"[Error] Unexpected error starting Flask server: {e}")
            sys.exit(1)
