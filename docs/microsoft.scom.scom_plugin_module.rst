.. Created with antsibull-docs 2.21.0

microsoft.scom.scom_plugin module -- Event Driven Ansible source for System Center Operations Manager (SCOM) Alerts.
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

This module is part of the `microsoft.scom collection <https://galaxy.ansible.com/ui/repo/published/microsoft/scom/>`_ (version 1.0.0).

It is not included in ``ansible-core``.
To check whether it is installed, run ``ansible-galaxy collection list``.

To install it, use: :code:`ansible\-galaxy collection install microsoft.scom`.

To use it in a playbook, specify: ``microsoft.scom.scom_plugin``.


.. contents::
   :local:
   :depth: 1


Synopsis
--------

- Poll the Microsoft System Center Operations Manager Server API for any new alerts, using them as a source for Event Driven Ansible.








Parameters
----------

.. raw:: html

  <table style="width: 100%;">
  <thead>
    <tr>
    <th><p>Parameter</p></th>
    <th><p>Comments</p></th>
  </tr>
  </thead>
  <tbody>
  <tr>
    <td valign="top">
      <div class="ansibleOptionAnchor" id="parameter-criteria"></div>
      <p style="display: inline;"><strong>criteria</strong></p>
      <a class="ansibleOptionLink" href="#parameter-criteria" title="Permalink to this option"></a>
      <p style="font-size: small; margin-bottom: 0;">
        <span style="color: purple;">string</span>
        / <span style="color: red;">required</span>
      </p>
    </td>
    <td valign="top">
      <p>This is a property of an alert in SCOM that indicates its current state in the alert lifecycle.</p>
      <p>The criteria (ResolutionState = &#x27;&#x27;) is a filter that describes the alert state.</p>
      <p>New (ResolutionState = &#x27;0&#x27;) The alert has been generated and has not been acted upon.</p>
      <p>Resolved (ResolutionState = &#x27;1&#x27;) The underlying issue has been fixed and the alert is marked as resolved.</p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <div class="ansibleOptionAnchor" id="parameter-interval"></div>
      <p style="display: inline;"><strong>interval</strong></p>
      <a class="ansibleOptionLink" href="#parameter-interval" title="Permalink to this option"></a>
      <p style="font-size: small; margin-bottom: 0;">
        <span style="color: purple;">string</span>
      </p>
    </td>
    <td valign="top">
      <p>Time between http API queries to fetch SCOM Server alerts.</p>
      <p style="margin-top: 8px;"><b style="color: blue;">Default:</b> <code style="color: blue;">5</code></p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <div class="ansibleOptionAnchor" id="parameter-ntlm_token_refresh"></div>
      <p style="display: inline;"><strong>ntlm_token_refresh</strong></p>
      <a class="ansibleOptionLink" href="#parameter-ntlm_token_refresh" title="Permalink to this option"></a>
      <p style="font-size: small; margin-bottom: 0;">
        <span style="color: purple;">string</span>
      </p>
    </td>
    <td valign="top">
      <p>Time between requests for a brand new token for SCOM Server API.</p>
      <p style="margin-top: 8px;"><b style="color: blue;">Default:</b> <code style="color: blue;">21600</code></p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <div class="ansibleOptionAnchor" id="parameter-password"></div>
      <p style="display: inline;"><strong>password</strong></p>
      <a class="ansibleOptionLink" href="#parameter-password" title="Permalink to this option"></a>
      <p style="font-size: small; margin-bottom: 0;">
        <span style="color: purple;">string</span>
        / <span style="color: red;">required</span>
      </p>
    </td>
    <td valign="top">
      <p>SCOM Server Login password.</p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <div class="ansibleOptionAnchor" id="parameter-scom_server"></div>
      <p style="display: inline;"><strong>scom_server</strong></p>
      <a class="ansibleOptionLink" href="#parameter-scom_server" title="Permalink to this option"></a>
      <p style="font-size: small; margin-bottom: 0;">
        <span style="color: purple;">string</span>
        / <span style="color: red;">required</span>
      </p>
    </td>
    <td valign="top">
      <p>SCOM Server IP or FQDN.</p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <div class="ansibleOptionAnchor" id="parameter-username"></div>
      <p style="display: inline;"><strong>username</strong></p>
      <a class="ansibleOptionLink" href="#parameter-username" title="Permalink to this option"></a>
      <p style="font-size: small; margin-bottom: 0;">
        <span style="color: purple;">string</span>
        / <span style="color: red;">required</span>
      </p>
    </td>
    <td valign="top">
      <p>SCOM Server Login username.</p>
    </td>
  </tr>
  </tbody>
  </table>






Examples
--------

.. code-block:: yaml

    ---
    - name: Listen for events on Microsoft SCOM Alerts
      hosts: localhost
      sources:
        - microsoft.scom.scom_plugin:
            scom_server: 10.55.55.100
            username: ECO\Administrator
            password: Password1!
            criteria: "(ResolutionState = '0')"
            interval: 10
            ntlm_token_refresh: 300
      rules:
        - name: New record created
          condition: event.id is defined
          action:
            debug:
              msg: "New SCOM Alert received! Alert Name: {{ event | default('N/A') }}"






Authors
~~~~~~~

- Microsoft SCOM Collection Contributors (@ansible-collections)


Collection links
~~~~~~~~~~~~~~~~

* `Issue Tracker <https://github.com/ansible\-collections/microsoft.scom/issues>`__
* `Repository (Sources) <https://github.com/ansible\-collections/microsoft.scom>`__
* `Report an issue <https://github.com/ansible\-collections/microsoft.scom/issues/new/choose>`__
