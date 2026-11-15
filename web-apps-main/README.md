# Apps for Web Testing Research

This repository contains nine subject web applications to be used in web 
testing research. The following applications are included:

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


## Instructions

In [web-apps](/web-apps/), Docker containers and instructions to run each of the nine web applications are provided.

In [web-apps-coverage](/web-apps-coverage/), instrumented versions of the PHP-based apps (i.e.: Addressbook, Claroline, MantisBT, MRBS, PPMA) are available. These instrumented versions can be used to compute code coverage of End-to-End user interactions. Please refer to the instructions provided for each of the apps for more information on how to compute code coverage.