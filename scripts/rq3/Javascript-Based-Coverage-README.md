# JS‑Based Applications (D\_imeshift, P\_agekit, P\_hoenix, P\_etClinic)

This guide summarizes the end‑to‑end procedure for crawling, testing and measuring coverage on one of the supported JavaScript‑based benchmark applications.

First download and extract the DANTE project in user level ( /Users/_name_/workspace/)
```
https://syncandshare.lrz.de/getlink/fi84Tgftkr9U4C6Rd3k55e/ICST20-submission-material-DANTE.7z
```

*Password: `crawlbench`*

**Replace every occurrence of the placeholders below with the concrete values for the application you are working on.**

```
APPLICATION  : dimeshift        # or pagekit, phoenix, petclinic
BASE‑LINE    : bert-contrastive # this can be any name according to your method (e.g: fraggen)
SETTING      : withinapp        # this can be any name according to your evaluation method (e.g: acrossapp)
STRATEGY     : fired            # or checked (only for phoenix)
```

If you change the application name, make the same replacement in filenames, paths and commands.

---

## 1. Clean the Docker Environment

* Remove the container, image and any associated Docker volumes of the target application.
* Search & replace the four placeholders above throughout the project (Ctrl+F per placeholder).
* If the SAF needs to be updated, edit:
  `dante/src/main/java/com/dante/subjects/config/«APPLICATION»Config.java`
* When anything under `/dante` changes execute from *inside* the `dante` folder:

  ```
  mvn clean
  mvn install
  ```

---

## 2. Build Crawljax

From the `./crawljax` directory run:

```bash
mvn clean
mvn install -DskipTests
```

---

## 3. Crawl the Application

3.1 **Start the application in crawl mode**

```bash
./dante/docker/«APPLICATION»/run-docker.sh -p yes -n crawl
```

3.2 **Verify runner configuration**
Check the URL and settings in:
`crawljax/examples/src/main/java/com/crawljax/examples/«APPLICATION»/«APPLICATION»Runner.java`

3.3 **Run the crawler** via IntelliJ (ensure the correct model is active at the endpoint).

3.4 **After the crawl completes**

```bash
mkdir dante/applications/«APPLICATION»
mv crawljax/out/* dante/applications/«APPLICATION»
mv dante/applications/«APPLICATION»/localhost/crawl0 dante/applications/«APPLICATION»/localhost/crawl-with-inputs
mv ~/Desktop/selenium-actions dante/applications/«APPLICATION»/selenium-actions-«APPLICATION»-«STRATEGY».txt
```

3.5 **Clean up** – stop and delete the Docker container.

---

## 4. Generate the Test Suite & Collect Java Coverage

From the `./dante` directory:

```bash
./generate-java-project-from-crawling.sh «APPLICATION» false
```

The script compiles and executes the generated JUnit tests and stores coverage under:
`dante/applications/«APPLICATION»/testsuite-«APPLICATION»/all-coverage-reports/test-suite-report.txt`

---

## 5. Fix Flakiness / Reset the Application State

* Launch the application normally:

  ```bash
  ./dante/docker/«APPLICATION»/run-docker.sh true false
  ```
* Execute the flakiness script (make it executable if necessary):

  ```bash
  dante/applications/«APPLICATION»/testsuite-«APPLICATION»/run-flakiness-«STRATEGY».sh
  ```

  ‑ Stop after three executions **or** adjust `num_execution_flaky_test_suite` in
  `testsuite-«APPLICATION»/src/main/resources/app.properties`.
* Implement `ResetAppState` if it is empty. Reference implementation:
  [https://github.com/matteobiagiola/ICST20-submission-material-DANTE/blob/master/dante/applications/dimeshift/testsuite-dimeshift/src/main/java/utils/ResetAppState.java](https://github.com/matteobiagiola/ICST20-submission-material-DANTE/blob/master/dante/applications/dimeshift/testsuite-dimeshift/src/main/java/utils/ResetAppState.java)

---

## 6. Obtain JavaScript Code Coverage

Run:

```bash
./run-tests-and-measure-coverage.sh «APPLICATION» true crawljax
```

* Passing tests log → `~/Desktop/logs_RunTests_dante_«APPLICATION».txt`
* Coverage log   → `~/Desktop/logs_MeasureCoverageOfTests_dante_«APPLICATION».txt`

---

## 7. Archive Logs, Coverage & Crawl Artifacts

* Record in your results spreadsheet:

    * **Code coverage** – path above or
      `~/Desktop/logs_MeasureCoverageOfTests_crawljax_«APPLICATION».txt`
    * **Crawling time** – `dante/applications/«APPLICATION»/localhost/crawl-with-inputs/result.json` → field `duration`
    * **Breakage rate** – `~/Desktop/logs_RunTests_crawljax_«APPLICATION».txt`

