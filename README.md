# CrawlBench: Neural Embeddings for Web Testing

*This project is a fork of the [Near Duplicate Detection Siamese Networks](https://github.com/ast-fortiss-tum/near-duplicate-detection-siamese-networks) project. It is designed to benchmark various combinations of **State Abstraction Functions (SAFs)**—including RTED, PDiff, FragGen, and SNN—with different **Crawl Traversal Methods** such as BFS, DFS, MOST_ACTION_FIRST, and PRIORITY_BFS. It provides a suite of automated scripts to facilitate these experiments.*

## 🚀 Get Started

Follow these steps to create and activate the Conda environment to set up the project. 

*   Use `snn-ndd` as the password for downloading the dataset and baseline resources.
*   Use `crawlbench` as the password for the Dante and web-app containers.

### 1) Clone the repository

```bash
git clone https://github.com/ast-fortiss-tum/crawlbench.git
```

### 2) Create the Conda environment

The `environment.yml` already pins compatible versions.

```bash
conda env create --name crawl-bench -f environment.yml
```

*What this does*

1. Creates a new Conda env called **`crawl-bench`**.
2. Installs all Conda‑managed packages.

### 3) Activate the environment

```bash
conda activate crawl-bench
```


## 💻 Apps for Web Testing Research

Applications evaluated in this work

<!-- - Addressbook (v. 8.2.5)
- PPMA (v. 0.6.0)
- MRBS (v. 1.4.9)
- Claroline (v. 1.11.10)
- PetClinic (commit 6010d5)
- Pagekit (v. 1.0.16)
- Dimeshift (commit 261166d)
- Phoenix (v. 1.1.0)
- MantisBT (v. 1.1.8) -->

| App name | Version | Technology | Description |
|----------|---------|------------|-------------|
| [Addressbook](https://sourceforge.net/projects/php-addressbook/) | 8.2.5 | PHP | A simple, web-based address & phone book, contact manager, organizer. |
| [Claroline](https://sourceforge.net/projects/claroline/) | 1.11.10 | PHP | A collaborative learning environment, allowing teachers or education institutions to create and administer courses through the web. |
| [Dimeshift](https://github.com/jeka-kiselyov/dimeshift)| commit 261166d | Node.js, Backbone.js | Expense tracker. |
| [MantisBT](https://github.com/mantisbt/mantisbt) | 1.1.8 | PHP | Bug Tracking system. |
| [MRBS](https://mrbs.sourceforge.io/) | 1.4.9 | PHP | A Meeting Room Booking System. |
| [Pagekit](https://github.com/pagekit/pagekit) | 1.0.16 | PHP, Vue.js |  A modular and lightweight CMS. |
| [PetClinic](https://github.com/spring-petclinic/spring-petclinic-angular) | commit 6010d5 | Java Spring, Angular | Demo web application for managing a veterinary clinic. | 
| [Phoenix](https://github.com/bigardone/phoenix-trello) | 1.1.0 | Elixir, Phoenix framework, React, Redux | Trello tribute done with Elixir, Phoenix Framework, Webpack, React and Redux. |
| [PPMA](https://github.com/pklink/ppma)  | 0.6.0 | PHP | A PHP Password MAnager. |


## 📂 Repository Structure

To honor the original work, the package and directory structures have been kept largely the same. Specifically, the folders `rq1` through `rq4` correspond to the research questions and evaluations belonging to the original SNN project.

**Our main contribution and the core of the benchmarking suite lies in the `scripts/crawl-bench/` folder.**

```
├── resources/                # Downloaded baseline datasets, doms, baseline runners (jar) and doc2vec embedding models
├── scripts/                  # Python scripts for running evaluations
│   ├── crawl-bench/          # [Our Contribution] CrawlBench specific scripts for automation and SAF/traversal benchmarking
│   ├── rq1/
│   │   ├── within-app-classification/
│   │   │   ├── bert_contrastive_classification.py
│   │   │   ├── doc2vec_contrastive_classification.py
│   │   │   └── markuplm_contrastive_classification.py
│   │   ├── across-app-classification/
│   │   │   └── [...same naming as above...]
│   │   └── baseline-classification/
│   │       └── run_baseline.py
│   ├── rq2/                   # RQ2 evaluation scripts
│   ├── rq3/                   # RQ3 evaluation scripts
│   └── rq4/                   # RQ4 evaluation scripts
├── results/                  # Generated experiment results
│   ├── crawlbench/           # [New] Centralized logs and results for CrawlBench automation
│   ├── rq1/
│   ├── rq2/
│   ├── rq3/
│   └── rq4/
├── baseline/                 # Baseline results
├── models/                   # Saved trained models
├── embedding/                # Cached embedding files
└── README.md                 
```


## 🖥️ Generate Reported Results


### 1) RQ1: Near-Duplicate Detection


#### a) SNN Evaluation

1. **Download resources**
   `resources.zip` from (use password password as ``snn-ndd``):

   ```
   https://syncandshare.lrz.de/getlink/fiY4KcSXCwSLW8g8TVmnep/resources.zip
   ```


   2. **Unpack and move the resources folder to the base project**

      ```bash
      unzip resources.zip -d resources
      ```

      You should now have folders:

      ```
      dataset
      scripts
      resources/
      ├── baseline-dataset/
      ├── baseline-runner/
      ├── doms/
      └── embedding-models/
      ```

   3. **Run the evaluation**

      ```bash
      python scripts/rq1/<evaluation_setting>-app-classification/<embedding_type>_contrastive_classification.py
      ```

      * `<evaluation_setting>`:

        * `within`
        * `across`
      * `<embedding_type>`:

        * `bert` (adjust the variant inside the script for ModernBERT)
        * `doc2vec`
        * `markuplm`

   4. **Outputs**

      * Experiment results → `results/rq1/`
      * Trained models → `models/`
      * Cached embeddings → `embedding/`

> **Re-runs** will automatically reuse any existing models or embeddings; nothing is re-trained if already present. If you want to use trained models and embeddings, please obtain them from the link below and ensure they are located at the project parent level separately (`./models`, `./embeddings`). Then try generating the results.
 
```
https://syncandshare.lrz.de/getlink/fi14MEw1swySBLPA6emQKP/models_and_embeddings.zip
```

#### b) FragGen Evaluation

   Run the evaluation from the project base directory

   ```
   python scripts/rq1/baseline-classification/within_app_fraggen.py
   ```


#### c) Other Baseline Methods - (WEBEMBED, RTED, PDIFF) Evaluation

   Run the evaluation from the project base directory

   ```
   python scripts/rq1/baseline-classification/<evaluation_setting>_app_baseline.py
   ```

   * `<evaluation_setting>`:

     * `within`
     * `across`

### 2) RQ2: Model Quality

#### a) SNN Evaluation

Run below command from the project base directory. Results will be saved in `results/rq2/`

   ```
   python scripts/rq2/model-quality-snn.py
   ```

#### b) FRAGGEN Evaluation

Run below command from the project base directory. Results will be saved in `results/rq2/`

   ```
   python scripts/rq2/fraggen.py
   ```

#### c) WEBEMBED Evaluation

Run below commands from the project base directory one after the other. The first scripts generates intermediate results files in `resources/csv_results_table/`. The second script generates the RQ2 results and save in `results/rq2/`

   ```
   python scripts/rq2/a-webembed.py
   python scripts/rq2/b-webembed.py
   ```

#### d) Other Baseline (RTED and PDIFF) Evaluation

Run below commands from the project base directory one after the other. The first scripts generates intermediate results files in `resources/csv_results_table/`. The second script generates the RQ2 results and save in `results/rq2/`
   ```
   python scripts/rq2/a-other-baselines.py
   python scripts/rq2/b-other-baselines.py
   ```

### 3) RQ3: Code Coverage

To integrate the state abstraction function during crawling, you want to follow the implementation of the state vertex and adjust the endpoint for your Flask app. When the crawler needs to evaluate  two states are, it can simply make a POST request to the endpoint with the necessary data, which allows the Flask app to function as the State Abstraction Function (SAF) and return the results you're looking for. 
Run below command to up flask app. 
   ```
   python scripts/rq3/saf-snn.py # SNN methods
   python scripts/rq3/saf-other-baseline.py # WEBEMBED methods
   python scripts/rq3/saf-other-baseline.py # RTED and PDIFF
   ```
Use this  [example](https://github.com/crawljax/crawljax/blob/master/examples/src/main/java/com/crawljax/examples/FragCrawlExample.java) for directly evaluating the FRAGGEN method without external SAF.

Code coverage varies depending on the application type. For PHP applications, server-side code coverage is measured, while JavaScript applications focus on client-side coverage. For crawling, we used Crawljax (5.2.4-SNAPSHOT). But it has compatibility considerations with certain versions of the Chrome driver. Alternative browsers can be used (Firefox for example) if specified in the crawl configuration. For evaluating FraGen is only possible with chrome hence we had to downgrade Chrome ( 114.0.5735.90)

---
In PHP applications, code coverage measurement is conducted using the Xdebug 2.2.42 extension alongside the php-code-coverage 2.2.33 library. Both crawling and code coverage measurement occur simultaneously. It is important to start code coverage before starting the crawl and to stop it after crawling completion to generate the coverage report. 

Refer [PHP Code Coverage README](scripts/rq3/PHP-Based-Coverage-README.md) for more details.

---
For JavaScript applications, the process operates separately. Crawljax was executed for Dante, which generates corresponding Selenium test cases. Once crawling is complete, Dante can utilize the generated test case files to produce JUnit test cases. For measuring coverage in JavaScript applications, cdp4j 3.0.81, a Java implementation of Chrome DevTools, was used.

Refer [JavaScript Code Coverage README](scripts/rq3/Javascript-Based-Coverage-README.md) for more details.

### 4) RQ4: Time Efficiency

#### a) SNN Training Times
SNN model training times are already recorded when you perform RQ1. In the results Excel file, you can find the training time for each model.

#### b) Crawling Times
After crawling the application in RQ3, a crawling report is generated. You can find the crawling time in the `result.json` file under **statistics → duration**.

#### c) Inference Times
Inference time is measured using 1,000 randomly selected pairs from our dataset.  
* **RTED and PDiff:** Compute the respective distances with the Crawljax implementation, then add the classifier inference time to obtain the total inference time.  
* **FragGen:** Use only the Crawljax classification time as the method’s inference time.

The JAR file `resources/baseline-runner/BaseLineRunner-1.0-SNAPSHOT.jar`—generated from the Java project linked below—is used to obtain distance-calculation times for RTED and PDiff, and total inference time for FragGen.

Baseline Runner project files  

   ```
   https://syncandshare.lrz.de/getlink/fiT5bUvN5DJfJ5uZ8JxgzC/baseline-runner.zip
   ```

#### SNN evaluation

Run below commands from the project base directory. Results will be saved in `results/rq4/`

```
python scripts/rq4/snn_inference_time.py
```

#### WEBEMBED evaluation

Run below commands from the project base directory. Results will be saved in `results/rq4/`
   
```
   python scripts/rq4/webembed_baseline_inference_time.py
```

#### Other baselines (FragGen, RTED, PDiff) evaluation

Run below commands from the project base directory. Results will be saved in `results/rq4/`
   
```
   python scripts/rq4/javabased_baseline_inference_time.py
```

### 5) 🛠️ CrawlBench Automation

For running large-scale experiments and automating the crawling process with different State Abstraction Functions (SAF), use the scripts in `scripts/crawl-bench/`.

#### a) Run SAF with SNN
```bash
./scripts/crawl-bench/run-saf-snn.sh
```

#### b) Run SAF with Baseline Methods
```bash
./scripts/crawl-bench/run-saf-baseline.sh
```

#### c) Run Coverage Experiments
```bash
# For PHP applications
./scripts/crawl-bench/run-coverage-experiment.sh

# For JavaScript applications
./scripts/crawl-bench/run-js-coverage-experiment.sh
```
