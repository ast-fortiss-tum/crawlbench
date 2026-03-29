# CrawlBench Automation Scripts

This folder contains scripts to automate the benchmarking of various **State Abstraction Functions (SAFs)** and **Crawl Traversal Methods**.

## 🛠️ Prerequisites

Before running the experiments, you must set up the necessary frameworks and applications.

### 1. Download DANTE and Crawljax
Download the modified version of DANTE and Crawljax from the following link:
[Modified DANTE & Crawljax](https://syncandshare.lrz.de/getlink/fi84Tgftkr9U4C6Rd3k55e/ICST20-submission-material-DANTE.7z)  
**Password:** `crawlbench`

**Extraction:**
Unpack the `.7z` file into the project root. You should see a folder named `ICST20-submission-material-DANTE/` which contains `dante/` and `crawljax/`.

### 2. Download PHP Web Applications
Download the collection of PHP web applications with modified Docker configurations:
[PHP Web Apps (Modified)](https://syncandshare.lrz.de/getlink/fi2zrg1ZzB4tCD4qZUwmHU/web-apps-main.7z)  
**Password:** `crawlbench`

**Extraction:**
Unpack the `.7z` file into the project root. You should see a folder named `web-apps-main/`.

---

## 🚀 Running Experiments

We provide two main scripts for running automated coverage experiments depending on the application type.

### 1. PHP Applications
Use `run-coverage-experiment.sh` for PHP-based applications (e.g., MantisBT, MRBS). This script handles starting the SAF backend, launching the Docker-based application with Xdebug for server-side coverage, and running Crawljax.

**Usage:**
```bash
./scripts/crawl-bench/run-coverage-experiment.sh <app-name>
```

**Example:**
```bash
./scripts/crawl-bench/run-coverage-experiment.sh mantisbt
```

**Supported Apps:** `mantisbt`, `mrbs`, `ppma`, `addressbook`, `claroline`

### 2. JavaScript Applications
Use `run-js-coverage-experiment.sh` for JavaScript-based applications. This script automates the crawling, organizes artifacts, generates a JUnit test suite via DANTE, and collects client-side coverage using `cdp4j`.

**Usage:**
```bash
./scripts/crawl-bench/run-js-coverage-experiment.sh <app-name>
```

**Example:**
```bash
./scripts/crawl-bench/run-js-coverage-experiment.sh dimeshift
```

**Supported Apps:** `dimeshift`, `pagekit`, `phoenix`, `petclinic`

---

## ⚙️ Customizing Experiments

You can customize the benchmarking by modifying the configuration variables at the top of the experiment scripts (`run-coverage-experiment.sh` or `run-js-coverage-experiment.sh`).

### 1. SAF and Traversal Strategies
By default, the scripts iterate through all combinations of the following:
```bash
SAFS=("rted" "pdiff" "fraggen" "siamese")
TRAVERSALS=("bfs" "dfs" "most_actions_first" "priority_bfs")
```
Modify these arrays in the script to include/exclude specific methods.

### 2. Runtime and Timeouts
To change the maximum duration of a crawl, you must update two places:

1.  **Script Timeout**: Modify `MAX_RUNTIME` (in minutes) at the top of the bash script. This controls the shell-level execution timeout.
    ```bash
    MAX_RUNTIME=120  # minutes
    ```
2.  **Crawljax Timeout**: You **must** also update the maximum duration inside the Java code to ensure Crawljax terminates gracefully.
    *   **File**: `ICST20-submission-material-DANTE/crawljax/examples/src/main/java/com/crawljax/examples/UnifiedRunner.java`
    *   Look for the configuration setting (e.g., `.setMaximumRunTime`) and update it to match your desired `MAX_RUNTIME`.

### 3. Adding New SAFs or Traversal Methods
If you wish to extend CrawlBench with new State Abstraction Functions or Traversal Strategies:
*   **Implementation**: New methods must be implemented within the Crawljax core or plugins (located in `ICST20-submission-material-DANTE/crawljax/`).
*   **Ready-to-use Methods**: Many traversal methods and SAFs are already available within Crawljax (either natively or through our modifications).
*   **Scope of this Project**: Specific SAFs and strategies implemented or integrated for this benchmarking suite can be found and reviewed in **`UnifiedRunner.java`**.
*   **Configuration**: After implementation, you must register and configure the new SAF or Traversal method within **`UnifiedRunner.java`** so it can be selected via command-line arguments.
*   **Automation**: Finally, update the `SAFS` or `TRAVERSALS` arrays in the experiment scripts to include your new identifiers.

---

## 📊 Results and Logs

All execution logs, including SAF backend output, Crawljax logs, and Maven build outputs, are centralized in:
`results/crawlbench/`

Specific coverage reports and CSV summaries for the experiments are also saved in this directory.

---

## 🧹 Cleanup

To stop all running SAF services and backend processes manually, you can use:
```bash
./scripts/crawl-bench/kill-saf-services.sh
```
