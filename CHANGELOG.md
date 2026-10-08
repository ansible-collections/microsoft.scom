# Microsoft SCOM Ansible Collection Release Notes

**Topics**

- <a href="#v2-0-0">v2\.0\.0</a>
    - <a href="#release-summary">Release Summary</a>
    - <a href="#major-changes">Major Changes</a>
    - <a href="#new-modules">New Modules</a>
- <a href="#v1-0-1">v1\.0\.1</a>
    - <a href="#minor-changes">Minor Changes</a>
- <a href="#v1-0-0">v1\.0\.0</a>
    - <a href="#release-summary-1">Release Summary</a>

<a id="v2-0-0"></a>
## v2\.0\.0

<a id="release-summary"></a>
### Release Summary

11 New modules for the Microsoft SCOM Ansible Collection

<a id="major-changes"></a>
### Major Changes

* Introduce the Microsoft SCOM Ansible Collection — a centralised automation framework for Microsoft System Center Operations Manager\. All modules share a unified connection and credential validation layer\, ensuring consistent behaviour and a predictable experience across every SCOM operation\.

<a id="new-modules"></a>
### New Modules

* microsoft\.scom\.alert \- Manage the state of a SCOM alert\.
* microsoft\.scom\.alert\_info \- Retrieve information about SCOM alerts\.
* microsoft\.scom\.group \- Manage SCOM groups with explicit membership\.
* microsoft\.scom\.group\_info \- Retrieve information about SCOM groups\.
* microsoft\.scom\.maintenance\_schedule \- Manage SCOM maintenance schedules\.
* microsoft\.scom\.maintenance\_schedule\_info \- Retrieve information about SCOM maintenance schedules\.
* microsoft\.scom\.management\_pack \- Import or remove SCOM management packs\.
* microsoft\.scom\.management\_pack\_info \- Retrieve information about installed SCOM management packs\.
* microsoft\.scom\.monitor\_override \- Manage SCOM monitor overrides\.
* microsoft\.scom\.monitor\_override\_info \- Retrieve SCOM monitors and their overrides by Monitor ID\, Display Name\, or Target Class\.
* microsoft\.scom\.notification\_channel \- Manage SCOM notification channels\.
* microsoft\.scom\.notification\_channel\_info \- Retrieve information about SCOM notification channels\.
* microsoft\.scom\.notification\_subscriber \- Manage SCOM notification subscribers\.
* microsoft\.scom\.notification\_subscriber\_info \- Retrieve information about SCOM notification subscribers\.
* microsoft\.scom\.notification\_subscription \- Manage SCOM notification subscriptions\.
* microsoft\.scom\.notification\_subscription\_info \- Retrieve information about SCOM notification subscriptions\.
* microsoft\.scom\.pending\_agent\_request \- Approve or Reject SCOM manual agent management requests\.
* microsoft\.scom\.pending\_agent\_request\_info \- Retrieve information about SCOM pending agent management requests\.
* microsoft\.scom\.run\_as\_account \- Manage SCOM Run As Accounts\.
* microsoft\.scom\.run\_as\_account\_info \- Retrieve information about SCOM RunAs accounts\.
* microsoft\.scom\.run\_as\_distribution \- Manage the credential distribution policy of SCOM RunAs account\.
* microsoft\.scom\.run\_as\_distribution\_info \- Retrieve the credential distribution policy of SCOM RunAs accounts\.

<a id="v1-0-1"></a>
## v1\.0\.1

<a id="minor-changes"></a>
### Minor Changes

* prepare\_release\.yml \- added proper task names\, FQCN usage\, and pipefail safety for shell commands\.
* scom\_plugin \- added HTTP status code constants for better code maintainability\.
* scom\_plugin \- improved code quality and linting compliance with type annotations\, proper error handling\, and modern Python syntax\.
* scom\_plugin \- improved logging configuration for CLI testing\.

<a id="v1-0-0"></a>
## v1\.0\.0

<a id="release-summary-1"></a>
### Release Summary

First release of the microsoft\.scom collection
