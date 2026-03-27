import json
import os
from flask import Flask, request, jsonify
import torch
from gensim.models import Doc2Vec
from transformers import AutoTokenizer, AutoModel, MarkupLMProcessor
import sys, pathlib

os.environ["TOKENIZERS_PARALLELISM"] = "false"

sys.path.append(str(pathlib.Path(__file__).resolve().parents[2]))

from scripts.utils.utils import fix_json_crawling, get_model, initialize_device, saf_equals, saf_equals_with_distance, set_all_seeds

base_path    = os.getcwd()
doc2vec_path     = f"/{base_path}/resources/embedding-models/content_tags_model_train_setsize300epoch50.doc2vec.model"
no_of_inferences = 0

app_to_dim = {
    'withinapp_markuplm' : {
        'addressbook' : 2304,
        'claroline' : 768,
        'ppma' : 768,
        'mrbs' : 2304,
        'mantisbt' : 1536,
        'dimeshift' : 1536,
        'pagekit' : 768,
        'phoenix' : 768,
        'petclinic' : 768,
    },
    'acrossapp_markuplm' : {
        'addressbook' : 768,
        'claroline' : 768,
        'ppma' : 768,
        'mrbs' : 768,
        'mantisbt' : 768,
        'dimeshift' : 768,
        'pagekit' : 768,
        'phoenix' : 768,
        'petclinic' : 768,
    },
    
}

# Configurations
configurations = [
    {
        'model_name': None,
        'title': "withinapp_doc2vec",
        'embedding_type': "doc2vec",
        'setting': "contrastive",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': doc2vec_path,
        'lr' : 1e-04,
        'epochs' : 15,
        'wd' : 0.05,
        'bs' : 32,
    },
    {
        'model_name': "bert-base-uncased",
        'title': "withinapp_bert",
        'embedding_type': "bert",
        'setting': "contrastive",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': None,
        'lr': 1e-04,
        'epochs': 15,
        'wd' : 0.05,
        'bs' : 32,
    },
    {
        'model_name': "answerdotai/ModernBERT-base",
        'title': "withinapp_modernbert",
        'embedding_type': "bert",
        'setting': "contrastive",
        'chunk_size': 8192,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': None,
        'lr': 1e-04,
        'epochs': 15,
        'wd': 0.05,
        'bs': 32,
    },
    {
        'model_name': "microsoft/markuplm-base",
        'title': "withinapp_markuplm",
        'embedding_type': "markuplm",
        'setting': "contrastive",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': None,
        'lr': 1e-04,
        'epochs': 15,
        'wd' : 0.05,
        'bs' : 32,
    },
    {
        'model_name': None,
        'title': "withinapp_doc2vec",
        'embedding_type': "doc2vec",
        'setting': "triplet",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': doc2vec_path,
        'lr': 1e-03,
        'epochs': 15,
        'wd': 0.05,
        'bs': 32,
    },
    {
        'model_name': "bert-base-uncased",
        'title': "withinapp_bert",
        'embedding_type': "bert",
        'setting': "triplet",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': None,
        'lr': 1e-03,
        'epochs': 15,
        'wd': 0.05,
        'bs': 32,
    },
    {
        'model_name': "answerdotai/ModernBERT-base",
        'title': "withinapp_modernbert",
        'embedding_type': "bert",
        'setting': "triplet",
        'chunk_size': 8192,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': None,
        'lr': 1e-03,
        'epochs': 15,
        'wd': 0.05,
        'bs': 32,
    },
    {
        'model_name': "microsoft/markuplm-base",
        'title': "withinapp_markuplm",
        'embedding_type': "markuplm",
        'setting': "triplet",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 5,
        'doc2vec_path': None,
        'lr': 1e-03,
        'epochs': 15,
        'wd': 0.05,
        'bs': 32,
    },
    {
        'model_name': None,
        'title': "acrossapp_doc2vec",
        'embedding_type': "doc2vec",
        'setting': "contrastive",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 2,
        'doc2vec_path': doc2vec_path,
        'lr': 2e-05,
        'epochs': 10,
        'wd': 0.01,
        'bs': 128,
    },
    {
        'model_name': "bert-base-uncased",
        'title': "acrossapp_bert",
        'embedding_type': "bert",
        'setting': "contrastive",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 2,
        'doc2vec_path': None,
        'lr': 2e-05,
        'epochs': 10,
        'wd': 0.01,
        'bs': 128,
    },
    {
        'model_name': "answerdotai/ModernBERT-base",
        'title': "acrossapp_modernbert",
        'embedding_type': "bert",
        'setting': "contrastive",
        'chunk_size': 8192,
        'overlap': 0,
        'chunk_limit': 2,
        'doc2vec_path': None,
        'lr': 2e-05,
        'epochs': 10,
        'wd': 0.01,
        'bs': 128,
    },
    {
        'model_name': "microsoft/markuplm-base",
        'title': "acrossapp_markuplm",
        'embedding_type': "markuplm",
        'setting': "contrastive",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 1,
        'doc2vec_path': None,
        'lr': 2e-05,
        'epochs': 15,
        'wd': 0.01,
        'bs': 128,
    },
    {
        'model_name': None,
        'title': "acrossapp_doc2vec",
        'embedding_type': "doc2vec",
        'setting': "triplet",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 2,
        'doc2vec_path': doc2vec_path,
        'lr': 0.0001,
        'epochs': 7,
        'wd': 0.01,
        'bs': 128,
    },
    {
        'model_name': "bert-base-uncased",
        'title': "acrossapp_bert",
        'embedding_type': "bert",
        'setting': "triplet",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 2,
        'doc2vec_path': None,
        'lr': 2e-05,
        'epochs': 15,
        'wd': 0.01,
        'bs': 128,
    },
    {
        'model_name': "answerdotai/ModernBERT-base",
        'title': "acrossapp_modernbert",
        'embedding_type': "bert",
        'setting': "triplet",
        'chunk_size': 8192,
        'overlap': 0,
        'chunk_limit': 2,
        'doc2vec_path': None,
        'lr': 5e-06,
        'epochs': 30,
        'wd': 0.01,
        'bs': 64,
    },
    {
        'model_name': "microsoft/markuplm-base",
        'title': "acrossapp_markuplm",
        'embedding_type': "markuplm",
        'setting': "triplet",
        'chunk_size': 512,
        'overlap': 0,
        'chunk_limit': 1,
        'doc2vec_path': None,
        'lr': 2e-05,
        'epochs': 12,
        'wd': 0.01,
        'bs': 128,
    },
]

# Parse command-line arguments (if provided)
import argparse
parser = argparse.ArgumentParser(description='Run SAF-SNN Flask server')
parser.add_argument('--appname', type=str, default=None, help='Application name (addressbook, claroline, ppma, mrbs, mantisbt, dimeshift, pagekit, phoenix, petclinic)')
parser.add_argument('--title', type=str, default=None, help='Model title (e.g., acrossapp_modernbert, withinapp_doc2vec)')
parser.add_argument('--setting', type=str, default=None, choices=['contrastive', 'triplet'], help='Setting type (contrastive or triplet)')
parser.add_argument('--port', type=int, default=None, help='Port number for Flask server (default: auto-assigned based on app)')
args = parser.parse_args()

# Port mapping for Siamese SAF services (5001-5009)
app_to_port = {
    'mantisbt': 5001,
    'mrbs': 5002,
    'ppma': 5003,
    'addressbook': 5004,
    'claroline': 5005,
    'dimeshift': 5006,
    'pagekit': 5007,
    'phoenix': 5008,
    'petclinic': 5009,
}

# Use command-line args if provided, otherwise use defaults from file
title            = args.title if args.title else "acrossapp_modernbert" # <acrossapp or withinapp>_<doc2vec or bert or modernbert or markuplm>
appname          = args.appname if args.appname else "mantisbt" # appname is treated as within app -> target app and across app -> test app
setting          = args.setting if args.setting else "contrastive" # contrastive or triplet
port             = args.port if args.port else app_to_port.get(appname, 5000) # Auto-assign port based on app

current_configs   = [config for config in configurations if config['title'] == title]
current_config    = current_configs[0] if (current_configs[0]['setting'] == 'contrastive' and setting == 'contrastive') else current_configs[1]

model_name       = current_config['model_name']
setting          = current_config['setting']
embedding_type   = current_config['embedding_type']
chunk_size       = current_config['chunk_size']
chunk_limit      = current_config['chunk_limit']
overlap          = current_config['overlap']
trained_epochs   = current_config['epochs']
lr               = current_config['lr']
bs               = current_config['bs']
wd               = current_config['wd']


if embedding_type == 'markuplm':
    dimensions = app_to_dim[title][appname]
elif embedding_type == 'bert':
    dimensions = 768
elif embedding_type == 'doc2vec':
    dimensions = 300

def increase_no_of_inferences():
    global no_of_inferences
    no_of_inferences += 1
    if no_of_inferences % 10 == 0:
        print(f"Number of inferences: {no_of_inferences}")

def load_model_and_tokenizer(embedding_type, model_name):
    embedding_model = None
    tokenizer = None
    processor = None
    model_path = f"{base_path}/models/{title}_{setting}_{appname}_cl_{chunk_limit}_bs_{bs}_ep_{trained_epochs}_lr_{lr}_wd_{wd}.pt"

    if not os.path.exists(model_path):
        print(f"[Warning] Model file not found at {model_path}. Skipping.")
        sys.exit(1)

    if embedding_type == 'doc2vec':
        embedding_model = Doc2Vec.load(doc2vec_path)
        embedding_model.random.seed(42)  # fix seed if needed

    elif embedding_type == 'bert':
        tokenizer = AutoTokenizer.from_pretrained(model_name)

        embedding_model = AutoModel.from_pretrained(model_name)
        embedding_model.to(device)

    elif embedding_type == 'markuplm':
        processor = MarkupLMProcessor.from_pretrained(model_name)
        processor.parse_html = False
        embedding_model = AutoModel.from_pretrained(model_name)
        embedding_model.to(device)
    else:
        print(f"[Error] Unknown embedding type {embedding_type}. Skipping.")
        sys.exit(1)


    classification_model = get_model(model_path, setting, device, dimensions)
    classification_model.to(device)

    model_state = torch.load(model_path, map_location=device, weights_only=True)
    classification_model.load_state_dict(model_state, strict=True)
    classification_model.eval()

    return classification_model, embedding_model, tokenizer, processor

app = Flask(__name__)
@app.route('/equals', methods=('GET', 'POST'))
def equals_route():
    content_type = request.headers.get('Content-Type')
    if content_type == 'application/json' or content_type == 'application/json; utf-8':
        fixed_json = fix_json_crawling(request.data.decode('utf-8'))
        if fixed_json == "Error decoding JSON":
            print("Exiting due to JSON error")
            exit(1)
        data = json.loads(fixed_json)
    else:
        return 'Content-Type not supported!'

    parametersJava = data

    dom1 = parametersJava['dom1']
    dom2 = parametersJava['dom2']
    url1 = parametersJava['url1']
    url2 = parametersJava['url2']

    # compute equality of DOM objects
    result = saf_equals(
        dom1=dom1,
        dom2=dom2,
        classification_model=classification_model,
        embedding_model=embedding_model,
        processor=processor,
        tokenizer=tokenizer,
        embedding_type=embedding_type,
        setting=setting,
        device=device,
        chunk_size=chunk_size,
        dimension=dimensions,
        overlap=overlap,
        threshold=0.5
       )
    result = "true" if result == 1 else "false"
    increase_no_of_inferences()

    print(f"[Info] url1 : {url1}, url2 : {url2}, results -> {result}")
    return result

@app.route('/equals_with_distance', methods=('GET', 'POST'))
def equals_with_distance_route():
    content_type = request.headers.get('Content-Type')
    if content_type == 'application/json' or content_type == 'application/json; utf-8':
        fixed_json = fix_json_crawling(request.data.decode('utf-8'))
        if fixed_json == "Error decoding JSON":
            print("Exiting due to JSON error")
            exit(1)
        data = json.loads(fixed_json)
    else:
        return 'Content-Type not supported!'

    parametersJava = data

    dom1 = parametersJava['dom1']
    dom2 = parametersJava['dom2']
    url1 = parametersJava['url1']
    url2 = parametersJava['url2']

    # compute equality of DOM objects and get distance
    prediction, distance = saf_equals_with_distance(
        dom1=dom1,
        dom2=dom2,
        classification_model=classification_model,
        embedding_model=embedding_model,
        processor=processor,
        tokenizer=tokenizer,
        embedding_type=embedding_type,
        setting=setting,
        device=device,
        chunk_size=chunk_size,
        dimension=dimensions,
        overlap=overlap,
        threshold=0.5
    )

    equals_result = "true" if prediction == 1 else "false"
    increase_no_of_inferences()

    print(f"[Info] url1 : {url1}, url2 : {url2}, equals -> {equals_result}, distance -> {distance}")

    response = {
        "equals": equals_result,
        "distance": distance
    }
    return jsonify(response)

@app.route('/', methods=['GET'])
def index():
    return jsonify({"status": "OK", "message": "Service is up and running. Call /equals for SAF service or /equals_with_distance for extended service"})

if __name__ == "__main__":
    seed = 42
    set_all_seeds(seed)
    device = initialize_device()
    classification_model, embedding_model, tokenizer, processor = load_model_and_tokenizer(embedding_type, model_name)
    print(f"******* We are using the model: {appname} - {title} - {setting} *******")
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
