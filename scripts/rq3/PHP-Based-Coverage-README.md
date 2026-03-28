# PHP‑Based Applications (M\_antisBT, M\_RBS, P\_PMA, C\_laroline, A\_ddressbok)

This guide captures the full procedure for crawling, testing and collecting code‑coverage data on any of the supported PHP benchmark applications. 

First download and extract the files. It contain all application files and docker scripts. Follow each application Readme files for more details.
 
```
https://syncandshare.lrz.de/getlink/fi2zrg1ZzB4tCD4qZUwmHU/web-apps-main.7z
 ```

 *Password: `crawlbench`*


**Replace every instance of the placeholders below with values for the run you are performing.**

```
APPLICATION  : mantisbt         # or mrbs, ppma, claroline, addressbok
BASE-LINE    : markuplm-triplet # this can be any name according to your method (e.g: fraggen)
SETTING      : withinapp        # this can be any name according to your evaluation method (e.g: acrossapp)
```

Make the corresponding replacements in filenames, paths and commands prior to execution.

---

1. Clean the Docker Environment

---

* Remove the container, image and any associated Docker volumes of the target application.
* Search & replace the three placeholders (`APPLICATION`, `BASE-LINE`, `SETTING`) across the project files (Ctrl+F).
* Confirm that variables above reflect the new run before proceeding.

---

2. Build and Start the Instrumented Application

---

2.1 Navigate to the application’s coverage folder, e.g.

```
/…/web-apps-main/web-apps-coverage/«APPLICATION»
```

2.2 Build the coverage‑enabled Docker image (run inside `«APPLICATION»-coverage/`):

```bash
docker build --no-cache . -t «APPLICATION»-coveragex
```

2.3 Follow the README in the same directory to start the application **with coverage recording enabled**. Verify that the coverage agent is active before crawling.

---

3. Crawl the Application

---

3.1 Launch the Java runner for the application (ensure the correct SAF, e.g. `BertStateVertexFactory`, is configured) and start crawling.

3.2 When the crawl finishes **stop code‑coverage** in the container and wait for the HTML report to be fully generated.

---

4. Collect Crawl & Coverage Artifacts

---

4.1 Copy the crawl output:

```bash
mv /Users/kasun/workspace/ICST20-submission-material-DANTE/out/* \
   ~/Desktop/crawls_rq3/«APPLICATION»_30/«BASE-LINE»/«SETTING»/
```

4.2 Copy the Selenium actions log:

```bash
mv ~/Desktop/selenium-actions \
   ~/Desktop/le_files_rq3/«APPLICATION»_30/«BASE-LINE»/«SETTING»/
```

4.3 Retrieve the coverage *session* folder from inside the container:

```bash
docker ps                   # note container ID
docker exec -it <ID> bash   # open shell in container
# inside container:
#  (navigate to /var/www/html/coverage/coverage_data/sessions/)
exit
# back on host:
docker cp <ID>:/var/www/html/coverage/coverage_data/sessions/<sessionDir> \
   ~/Desktop/le_files_rq3/«APPLICATION»_30/«BASE-LINE»/«SETTING»/
```

4.4 Remove the copied *session* directory from the container to free space:

```bash
docker exec <ID> rm -rf /var/www/html/coverage/coverage_data/sessions/<sessionDir>
```

---

5. Tear Down the Docker Environment

---

Execute in the folder containing `docker-compose.yml` for the application:

```bash
docker compose down --rmi all --volumes
```

---

## Notes

* Ensure the coverage service is running before starting the crawl; otherwise the HTML report will be empty.
* All path references in this guide reflect the original author’s directory structure. Adjust them if your workspace differs.
* Always double‑check that the placeholders are fully substituted before executing any command.
