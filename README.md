# Microsoft SCOM Collection for Ansible
[![CI](https://github.com/ansible-collections/microsoft.scom/workflows/CI/badge.svg?event=push)](https://github.com/ansible-collections/microsoft.scom/actions) [![Codecov](https://img.shields.io/codecov/c/github/ansible-collections/microsoft.scom)](https://codecov.io/gh/ansible-collections/microsoft.scom)

This collection provides Ansible modules and plugins for automating Microsoft System Center Operations Manager (SCOM) infrastructure. It enables users to manage SCOM environments, configure monitoring, and automate operational tasks through Ansible playbooks.

## Our mission


At the Microsoft SCOM collection, our mission is to produce and maintain simple, flexible,
and powerful open-source software tailored to Microsoft System Center Operations Manager (SCOM) automation.

We welcome members from all skill levels to participate actively in our open, inclusive, and vibrant community.
Whether you are an expert or just beginning your journey with Ansible and Microsoft SCOM,
you are encouraged to contribute, share insights, and collaborate with fellow enthusiasts!

## Code of Conduct

We follow the [Ansible Code of Conduct](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html) in all our interactions within this project.

If you encounter abusive behavior, please refer to the [policy violations](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html#policy-violations) section of the Code for information on how to raise a complaint.

## Communication


* Join the Ansible forum:
  * [Get Help](https://forum.ansible.com/c/help/6): get help or help others. Please add the `microsoft` and `scom` tags when starting new discussions.
  * [Posts tagged with 'microsoft'](https://forum.ansible.com/tag/microsoft): subscribe to participate in Microsoft-related conversations.
  * [Posts tagged with 'scom'](https://forum.ansible.com/tag/scom): subscribe to participate in SCOM-related conversations.
  * [Social Spaces](https://forum.ansible.com/c/chat/4): gather and interact with fellow enthusiasts.
  * [News & Announcements](https://forum.ansible.com/c/news/5): track project-wide announcements including social events. The [Bullhorn newsletter](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn), which is used to announce releases and important changes, can also be found here.

For more information about communication, see the [Ansible communication guide](https://docs.ansible.com/ansible/devel/community/communication.html).

## Contributing to this collection


The content of this collection is made by people like you, a community of individuals collaborating on making the world better through developing automation software.

We are actively accepting new contributors and all types of contributions are very welcome.

Don't know how to start? Refer to the [Ansible community guide](https://docs.ansible.com/ansible/devel/community/index.html)!

Want to submit code changes? Take a look at the [Quick-start development guide](https://docs.ansible.com/ansible/devel/community/create_pr_quick_start.html).

We also use the following guidelines:

* [Collection review checklist](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_reviewing.html)
* [Ansible development guide](https://docs.ansible.com/ansible/devel/dev_guide/index.html)
* [Ansible collection development guide](https://docs.ansible.com/ansible/devel/dev_guide/developing_collections.html#contributing-to-collections)

## Collection maintenance

The current maintainers are listed in the [MAINTAINERS](MAINTAINERS) file. If you have questions or need help, feel free to mention them in the proposals.

To learn how to maintain/become a maintainer of this collection, refer to the [Maintainer guidelines](https://docs.ansible.com/ansible/devel/community/maintainers.html).

It is necessary for maintainers of this collection to be subscribed to:

* The collection itself (the `Watch` button -> `All Activity` in the upper right corner of the repository's homepage).
* The [news-for-maintainers repository](https://github.com/ansible-collections/news-for-maintainers).

They also should be subscribed to Ansible's [The Bullhorn newsletter](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn).

## Governance


The process of decision making in this collection is based on discussing and finding consensus among participants.

Every voice is important. If you have something on your mind, create an issue or dedicated discussion and let's discuss it!


### Installation

Before using this collection, you need to install it with the Ansible Galaxy command-line tool:
```bash
ansible-galaxy collection install microsoft.scom
```

You can also include it in a `requirements.yml` file and install it with `ansible-galaxy collection install -r requirements.yml`, using the format:
```yaml
---
collections:
  - name: microsoft.scom
```

Note that if you install the collection from Ansible Galaxy, it will not be upgraded automatically when you upgrade the `ansible` package. To upgrade the collection to the latest available version, run the following command:
```bash
ansible-galaxy collection install microsoft.scom --upgrade
```

You can also install a specific version of the collection, for example, if you need to downgrade when something is broken in the latest version (please report an issue). Use the following syntax to install version `0.1.0`:

```bash
ansible-galaxy collection install microsoft.scom:==0.1.0
```

See [using Ansible collections](https://docs.ansible.com/ansible/devel/user_guide/collections_using.html) for more details.

### Using the Collection SCOM Plugin On AAP/EDA 

In order to use the collection plugin `scom_plugin` on your AAP/EDA you have to have it on the EDA Decision Environment

To build an EDA Decision Environment use `microsoft.scom/Containerfile` 

```bash
podman build -t scom-eda-de:1.0.0 .
```

Push the image to your container registry

Use the image to create decision environment in EDA

In EDA Rulebook Activations create rulebook activation with the created decision environment 
And with Rulebook `microsoft.scom/extensions/eda/rulebooks/scom-rulebook.yml`


## Release notes

See the [changelog](https://github.com/ansible-collections/microsoft.scom/tree/main/CHANGELOG.rst).

## Support

As Red Hat Ansible Certified Content, this collection is entitled to support through Ansible Automation Platform (AAP) using the **Create issue** button on the top right corner.
If a support case cannot be opened with Red Hat and the collection has been obtained either from Galaxy or GitHub, there may community help available on the [Ansible Forum](https://forum.ansible.com/).

## More information


- [Ansible user guide](https://docs.ansible.com/ansible/devel/user_guide/index.html)
- [Ansible developer guide](https://docs.ansible.com/ansible/devel/dev_guide/index.html)
- [Ansible collections requirements](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_requirements.html)
- [Ansible community Code of Conduct](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html)
- [The Bullhorn (the Ansible contributor newsletter)](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn)
- [Important announcements for maintainers](https://github.com/ansible-collections/news-for-maintainers)

## Licensing


GNU General Public License v3.0 or later.

See [LICENSE](https://www.gnu.org/licenses/gpl-3.0.txt) to see the full text.
