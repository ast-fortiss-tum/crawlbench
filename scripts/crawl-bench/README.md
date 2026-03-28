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
