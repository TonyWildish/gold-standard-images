# Introduction

Gold Standard Images is a pillar of DevOps best practices. Images are repeatable, self-documented, and portable across multiple platforms and ensure production/staging/development parity. Other benefits include:
- Fast deployment, benefiting not only production, but development as well.
- Early test-ability.
- End-to-end control.
- Known and predictable state.
- Policy enforcement.

The system proposed here relies on [Packer.io](https://www.packer.io), [Ansible](https://www.ansible.com) and virtualization technologies ([Vagrant](https://www.vagrantup.com), [VirtualBox](https://www.virtualbox.org), [KVM](http://www.linux-kvm.org), [QEMU](http://wiki.qemu.org) and [Docker](https://www.docker.com)) to build minimal images in a repeatable and portable manner. In addition to virtual machines, bare metal is also supported. This is accomplished by providing kickstarts and Ansible playbooks that are similar between bare metal and VMs.

The images produced are minimal by design, containing only the minimum number of packages and configuration to make them workable, secure and general enough to be reused in multiple projects. Images are created from scratch based on ISO images and don't depend on previously uploaded images to the several cloud providers.

The system depends on four inputs, which are well known and maintained:
- OS ISO image.
- OS package repositories.
- Kickstart.
- Ansible playbooks.

# Supported Images

## OS

- CentOS 7.x
- RedHat 7.x

Note that OS name and versions are named after the values reported by `ansible_distribution` and `ansible_distribution_version`.

## Providers

This is the list of supported providers by build name (Packer's build type in parenthesis):
- `aws`: [Amazon Web Services](#amazon-web-services-aws-) (`virtualbox-iso`)
- `azure`: [Microsoft Azure](#microsoft-azure-azure-) (`qemu`)
- `docker`: [Docker](#docker-docker-) (`qemu`)
- `gcp`: [Google Compute Platform](#google-compute-platform-gcp-) (`qemu`)
- `openstack`: [OpenStack](#openstack-openstack-) (`qemu`)
- `virtualbox`: [VirtualBox](#virtualbox-virtualbox-) (`virtualbox-iso`)
- `vmware`: [VMware](#vmware-vmware-) (`vmware-iso`)

# Building Artifacts

Read the [Bootstrapping](#bootstrapping) section below before attempting to build images for any provider.

Select the VM to build, ie:
``` sh
vm_name=CentOS-7.6.1810
```

And run Packer in parallel to generate images for all providers. Note that due to an incompatibility between VirtualBox and KVM running concurrently, builds need to be split:
``` sh
packer build -var-file=templates/site.json -var-file=templates/os/${vm_name}.json $opts --only=virtualbox,aws templates/main.json
packer build -var-file=templates/site.json -var-file=templates/os/${vm_name}.json $opts --except=virtualbox,aws templates/main.json
```

Use Packer options `--only` and `--except` to select a set of providers to build.

Variables used by Packer templates are set in `templates/site.json` and the the OS specific templates found in directory `templates/os`. They can also be overridden in the command line using the `-var` option. A complete list of variables can be found at the top of `templates/main.json`. For example:
``` sh
-var version=0.0.0
```

The following options might also be useful:
``` sh
opts="-var headless=false"        # helps debugging kickstarts
opts="-force"                     # forces overwriting of artifacts
```

SHA256 checksums generated for all artifacts can be found in the artifacts directory for each provider (see [sha256sum](#sha256sum)).

Note that, although Packer allows automated upload of images to cloud providers, this is not activated at the moment. See below for instructions on uploading/importing to the different providers.

## Providers

In this section has specific instructions for the supported providers.

Note that in the upload/import subsections, an effort has been made to simplify the commands used by abstracting some of the variables used in all providers, ie `build`, `artdir` and `artifact`. In the future this will evolve into a shell utility to aid building/uploading/importing images.

### Amazon Web Services (`aws`)

The `aws` provider uses the `virtualbox-iso` build type (see [virtualbox-iso](#virtualbox-iso) for dependencies). It also depends on [AWS CLI](#aws-cli) to manage uploads.

#### Upload

The following instructions assume AWS CLI installed and configured to access your AWS account. In addition a AWS S3 bucket for temporary upload of the image before final import into an AWS image must be already available. Note that you might also need to configure AWS policies to accept image imports (see http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/VMImportPrerequisites.html#vmimport-service-role).

``` sh
build=aws
artdir=artifacts/${version}/${vm_name}/${build}
artifact=${vm_name}-${version}_${build}

aws_s3_bucket=myawsbucket

aws s3 cp $artdir/$artifact.ova s3://${aws_s3_bucket}/
aws ec2 import-image --disk-container "Format=ova,UserBucket={S3Bucket=${aws_s3_bucket},S3Key=$artifact.ova}"
aws ec2 describe-import-image-tasks
```

### Microsoft Azure (`azure`)

The `azure` provider uses the `qemu` build type (see [qemu](#qemu) for dependencies). It also depends on [qemu-img](#qemu-img) to convert the artifact into VHD format. [Azure CLI](#azure-cli) is use to upload the image.

#### Upload

The following instructions assume Azure CLI is install and configured to access your Azure account. In addition a resource group must already be available.

``` sh
build=azure
artdir=artifacts/${version}/${vm_name}/${build}
artifact=${vm_name}-${version}_${build}

resource_group=myresourcegroup
storage_account=mystorageaccount
container=images-container

az login
az group create -l northeurope -n $resource_group
az storage account create -g $resource_group -l northeurope --kind Storage --sku Standard_RAGRS -n $storage_account
key=$(az storage account keys list -n $storage_account -g $resource_group --output json | jq -r '.[] | select(.keyName == "key1") | .value')
az storage container create --account-name $storage_account --account-key $key -n $container
az storage blob upload -t page --account-name $storage_account --account-key $key -c $container -f $artdir/$artifact.vhd -n $artifact.vhd
```

Create a VM image from the uploaded VHD

```
az disk create -g $resource_group -n $artifact --source https://$storage_account.blob.core.windows.net/$container/$artifact.vhd
disk=$(az disk list -g $resource_group  --output table --query "[].{Name:name, ID:id}" --output json | jq -r '.[] | select(.Name == "'$artifact'") | .ID')
az image create --resource-group $resource_group --location northeurope  --name $artifact  --os-type linux  --source $disk
```

### Docker (`docker`)

The `docker` provider uses the `qemu` build type (see [qemu](#qemu) for dependencies). It also depends on [virt-tar-out](#virt-tar-out) and gzip to convert the artifact into compress tar file, and [Docker](#docker) to import the image.

#### Import

``` sh
build=docker
artdir=artifacts/${version}/${vm_name}/${build}
artifact=${vm_name}-${version}_${build}

docker import $artdir/$artifact.tar.gz ${artifact,,}
```

Note that docker images need to be lowercase. The above bash substitution in 'docker import' requires Bash 4+.

### Google Compute Platform (`gcp`)

The `gcp` provider uses the `qemu` build type (see [qemu](#qemu) for dependencies). It also depends on [qemu-img](#qemu-img) and tar to convert the artifact into compressed tar file. [Cloud SDK](#cloud-sdk) is use to upload the image.

#### Upload

The following instructions assume CLOUD SDK is installed and configured to access your GCP account. In particular, the `gsutil` and `gcloud` tools need to be available. In addition a GCP bucket for upload of the image before importing must already be available.

``` sh
build=gcp
artdir=artifacts/${version}/${vm_name}/${build}
artifact=${vm_name}-${version}_${build}

gcp_bucket=mygcpbucket
image=$(echo $artifact | tr [_.] - | tr [A-Z] [a-z])

gsutil cp $artdir/$artifact.tar.gz gs://${gcp_bucket}
gcloud compute images create $image --source-uri gs://${gcp_bucket}/$artifact.tar.gz
```

### OpenStack (`openstack`)

The `openstack` provider uses the `qemu` build type (see [qemu](#qemu) for dependencies). It also depends on the [OpenStack command-line](http://docs.openstack.org/user-guide/common/cli-install-openstack-command-line-clients.html) to manage an OpenStack cloud, which requires [Openstackclient Python Libraries](#openstackclient-python-libraries) (see below).

#### Upload

``` sh
build=openstack
artdir=artifacts/${version}/${vm_name}/${build}
artifact=${vm_name}-${version}_${build}

. ~/python-openstack/bin/activate
openstack image create --disk-format qcow2 --file $artdir/$artifact.qcow2 --tag packer $artifact
```

Add:
- `--protected` to protect the image from being deleted.
- `--public` to make it available to other openstack users.

### VirtualBox (`virtualbox`)

The `virtualbox` provider uses the `virtualbox-iso` build type (see [virtualbox-iso](#virtualbox-iso) for dependencies). VirtualBox images are create to be used as Vagrant boxes (see [Vagrant](#vagrant)). A catalog metadata file can be used for each OS to manage Vagrant images. These files are located in `artifacts/`. An example can be found in `artifacts/CentOS-7.6.1810.json.example`. Referencing a catalog in a `Vagrantfile` will automatically import the last image or prompt for an upgrade if a newer version is found based on the data in the catalog. For example:

``` ruby
# Vagrantfile

Vagrant.configure(2) do |config|
  config.vm.box = "namespace/CentOS-7.6.1810"
  config.vm.box_url = 'file:///path/to/artifacts/CentOS-7.6.1810.json'
end
```

### VMware (`vmware`)

The `vmware` provider uses the `vmware` build type (see [vmware-iso](#vmware-iso) for dependencies). It also depends on [ovftool](#ovftool) to convert the artifact to OVA format.

#### Upload

To upload the artifact, login to your VMware account and manually upload the OVA image at `$artdir/$artifact.ova`.

``` sh
build=vmware
artdir=artifacts/${version}/${vm_name}/${build}
artifact=${vm_name}-${version}_${build}
```

# Components

The build of an artifact for use in a cloud environment start with a Packer's template, which in turn will first use a kickstart to bootstrap the machine and then provision if with Ansible playbooks and shell scripts. The end result will produce an artifact that can be deployed to the target cloud environment.

## Packer Templates

A standard Packer's JSON template for parallel generation of artifacts for different cloud providers is located in the `templates/main.json` alongside with a site specific template in `templates/site.json` and OS specific templates in directory `templates/os` (ie `CentOS-7.6.1810.json`).

The main template declares a set of variables (`user variables` as per Packer). These variables are unset in the main template and instead should be set in the appropriate template (see below). Note that failure to set all variables declared with `null` in the main template will prevent the build process. Variables can also be overridden in command line (see above). Variables are divided into two types:
- Site specific variables (for example namespace, versions, server urls, disk space, locale info and root password) should be set in `templates/site.json` (an example is provided in `templates/site.json.example`).
- OS specific variables (ie `os_name`, `os_version`, `iso` and `iso_checksum`, `iso_server` and `repo_server`). These should be set in the OS specific template under `templates/os` (an example is provided in `templates/os/CentOS-7.6.1810.json.example`).

This setup provides flexibility in the image building process and allows site and os selection.

The main templates will bootstrap artifacts for multiple providers, usually providing an additional VirtualBox artifact for development/testing purposes.

As any other Packer template, `templates/main.json` is divided in:
- builders: on builder per provider, each declaring how to build the provider. All depend on a local HTTP server to access the kickstart files (see [Kickstarts](#kickstarts)).
- provisioners: all execute two provisioners, the first one using Ansible to provision the image (see [Ansible Playbooks](#ansible-playbooks)), and another calling two shell scripts to clean up the image (see [Cleanup Shell Scripts](#cleanup-shell-scripts)).
- post-processors: some providers need post-processors to convert artifacts to the appropriate format. See [Post-processors](#post-processors) for a list of the dependencies required.

## Kickstarts

Kickstart files are located in the `http/` directory. The main kickstart file is `ks.php`, and requires a server running PHP (see [Kickstart server](#kickstart-server)).

You can serve the kickstart files from your local directory using a PHP docker container:

``` sh
  docker run \
    -it \
    --detach \
    --rm \
    --name ks-server \
    --volume `pwd`/http:/var/www/html \
    --volume `pwd`/templates:/var/www/templates \
    --publish 8080:80 \
    php:7.3.2-apache-stretch
  ```

### Packer Variables

Packer site variables variables defined in `templates/site.json` and OS variables defined in `templates/os` are available in the kickstart in PHP objects `packer_site` and `packer_os`. Note that variables defined in the command line while running packer are not reflected here. Currently only `packer_os['os_version']` is used (see below).

### Build Types

The kickstart system is divided in multiple files that get included depending on the variables defined the build type and build files for the specified server (found in `builds/`). All Packer templates will use definitions found in `builds/virtual` while bare metal servers will look for definition files in `build/metal`. Different kickstart sections get included for metal or virtual builds appropriately. URLs to target different servers are in the form of `http://server.domain:port/ks.php?build=buildtype/build`, where `buildtype` is `virtual` or `metal` and `build` is a specific build or host (with default values if `build` is not found). If buildtype is not defined, `virtual` is used.

### OS

Multiple OS (and OS version) are supported by passing `os=name-version` in the URL to the kickstart server, ie `http://server.domain:port/ks.php?os=CentOS-7.6.1810`. Currently this is only used to pass the OS version to the kickstart scripts and generate the URL for the repository (see `http/includes/repo.php`).

### First Boot Options

Builders using a kickstart pass the following boot options:
- `selinux=0` will disable selinux.

The customized kickstart also understands the following options:
- `EJECT` will eject the first CD/DVD drive. This is mainly use in bare metal outside of Packer.

## Ansible Playbooks

Each builder will provision the image by running Ansbile playbook `ansible/site.yml`, which in turns runs base tasks from `ansible/base.yml` (common to all builders), and then builder specific tasks based on the build name, ie `ansible/aws.yml`.

Packer site and OS specific variables are available to Ansible tasks. Site variables (see `templates/site.json`) are passed as Ansible command line variables and prefixed with `packer_` (ie `packer_namespace`). These variables are also reflected in Ansible if overridden as Packer's command line options. OS specific variables in `templates/os` are imported into object `packer_os` at the start of the main playbook (ie `packer_os.repo_server`) and are not reflected in Ansible if overridden as Packer's command line options.

The structure of these playbooks might not conform to best practices due to the specificity of this projects. In particular, tasks are used directly instead of roles. Tasks (as well as templates and files) are shared among all playbooks to better maintain consistency among generated artifacts. Note that idempotency is not key when running Ansible in this project because a playbook is only run once.

## Cleanup Shell Scripts

Several shell scripts located in `scripts/` are run by each template to clean up the images:
- `cleanup.up` remove caches and sessions.
- `zero.sh` compresses the image.

## Directory Structure

Following is a tree of files compromising the system along with a brief description. To simplify the tree, only `CentOS` is listed here where multiple OS are possible, and only `aws` is listed where multiple builder/providers are possible. Note that items marked with `!VC` are not stored in version control (git). Also, files ending in `.example` will need to be copied into actual files as described in the relevant section in this document and those files should not be stored in version control.

```
|-- ansible/                                      Ansible playbooks
|   |-- site.yml                                  Main playbook for all Packer builds
|   |-- base.yml                                  Base tasks common to all Packer builds
|   |-- aws.yml                                   Specific playbook for each Packer build
|   |-- group_vars/
|   |   `-- all.yml                               Variables for all playbooks/artifacts
|   |-- tasks/                                    Tasks used in playbooks
|   |-- files/                                    Files used by Ansible tasks
|   `-- templates/                                Templates used by Ansible tasks
|-- artifacts/                                    Artifacts (intermediate/end images)
|   |-- 0.0.0/                                    Ordered by version
|   |   `-- CentOS-7.6.1810/                        and OS
|   |       `-- aws/                                and provider
|   |           |-- SHA256SUM                       SHA256 checksum for all artifacts
|   |           |-- CentOS-7.6.1810-0.0.0_aws.ova   Template specific artifact
|   |           |-- CentOS-7.6.1810-0.0.0_aws.box   Vagrant box for debugging purposes
|   |           `-- ...                             Other files might be generated. Artifacts are not kept in VC
|   `-- CentOS-7.6.1810.json.example              Example for vagrant boxes catalog metadata (one per OS)
|-- http/                                         HTTP server directory for Packer and metal PXE
|   |-- ks.php                                    Kickstart entry point
|   |-- includes/                                 Kickstart include files
|   |   |-- header.php                            Parse incoming URL and set settings
|   |   |-- repo.php                              Repository URLs for OSs
|   |   |-- rootpw.php                            Crypted root password
|   |   |-- metal/                                Metal specific Kickstart settings
|   |   |   |-- disk.php
|   |   |   |-- network.php
|   |   |   `-- post.php
|   |   |-- virtual/                              VMs specific Kickstart settings
|   |   |   |-- disk.php
|   |   |   |-- network.php
|   |   |   `-- post.php
|   `-- builds/                                   Per build type definitions
|       |-- defaults.php                          Common defaults for all builds
|       |-- virtual/
|       |   |-- defaults.php                      Default options for virtual builds
|       |   `-- aws.php                           Options for specific builds
|       |-- metal/
|       |   |-- defaults.php                      Default options for metal hosts
|       |   `-- {host1,...}.php                   Options for specific hosts
|       `-- packer/
|           |-- vars.php                          Import packer site and OS variables into PHP
|           |-- site.json ->                      Link to packer's templates/site.json
|           `-- templates/os/ ->                  Link to packer's templates/os
|-- keys/                                         SSH keys [!VC]
|   |-- packer                                      For passwordless root access
|   |-- packer.pub
|   |-- vagrant                                     For passwordless access to Vagrant boxes
|   `-- vagrant.pub
|-- README.md                                     Yeah, readme please!
|-- scripts/                                      Provisioning helper scripts
|   |-- cleanup.sh                                Cleanup boxes
|   `-- zero.sh                                   Compress boxes
|-- templates/                                    Packer templates
|   |-- main.json                                 Parallel template with all builds
|   |-- site.json.example                         Example for site specific variables
|   `-- os/                                       OS specific variables
|       `-- CentOS-7.6.1810.json.example          Example of OS specific template
|-- test/                                         Vagrant tests
|   `-- Vagrantfile
`-- .gitignore                                    Files to ignore in VC
```


# Bootstrapping

Before attempting to build images for any provider you should bootstrap the system for your site and have a few tools ready in your system. These would depend on the providers you want to support. Each provider's section above lists the tools needed. Building images can be (and should be) done under a regular non-root user. However, some of the dependencies might need to be installed system wide as the root user.

## General

### Site Specifics

To bootstrap your site you set up some templates (find further information in [Packer Templates](#packer-templates)):
- Set your site variables `templates/site.json`. An example is provided in `templates/site.json.example`
- Set your OS variables `templates/os/`. An example is provided in `templates/os/CentOS-7.6.1810.json.example`

You also need to set up private keys to access the images when booted on the different providers. These keys live in `keys/` and should not be committed to version control. To create both keys use:
``` sh
ssh-keygen -t rsa -b 2048 -N "" -C "packer" -f keys/packer
ssh-keygen -t rsa -b 2048 -N "" -C "vagrant" -f keys/vagrant
```

### Packer

[Packer](https://www.packer.io) is the main tool and is used to manage the build process. Find more information and download links their website.

### Ansible

[Ansible](https://www.ansible.com) is used to provision the builds in a standardized way. Most distributions have packages available for Ansible. Alternatively you can also clone the git repository at git://github.com/ansible/ansible.git (see http://docs.ansible.com/ansible/intro_installation.html for more information).

### Kickstart server

You need an HTTP server with PHP support to serve the kickstart files found in the `http/` directory. The simplest way is to install `apache` and `php` and configure it to serve the files in `http/`. A simple approach is to configure Apache with `Userdir` activated and adding a symlink to `~/public_html`, ie. `ln -sf /path/to/http ~/public_html/gold_standard_images`.

## Build Types

Different built types need different tools installed.

### qemu

These builds depend on [QEMU](http://wiki.qemu.org) and [KVM](http://www.linux-kvm.org). Most distributions have a package `qemu-kvm` available.

### virtualbox-iso

These builds depends on [VirtualBox](https://www.virtualbox.org). Most distributions have packages available.

### vmware-iso

[VMware Workstation](http://www.vmware.com/products/workstation-for-linux.html) or [VMware Player](https://www.vmware.com/products/workstation-player.html)+VMware VIX are needed for builds that use the `vmware-iso` builder. Note that you might need to be registered at https://my.vmware.com to download the tools. VMware VIX can be downloaded from VMware Player's download site by clicking on the "Drivers & Tools" tab. Note that VMWare 6.5+ changed it support for SHA from SHA1 to SHA256. If you are on an older version of VMware, you'll need to change the SHA algorithm `templates/site.json` to produce valid OVA files.

## Upload/Import tools

### AWS CLI

Instructions to install and configure [AWS CLI](https://aws.amazon.com/cli/) can be found [here](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-set-up.html). Some Linux distributions have packages available.

### Azure CLI

Follow instructions to install and configure [Azure CLI](https://docs.microsoft.com/en-us/azure/xplat-cli-install).

### CLOUD SDK

Install and configure [CLOUD SDK](https://cloud.google.com/sdk) by following the instructions in that link.

### Docker

Instructions to install [Docker](https://www.docker.com) can be found [here](https://docs.docker.com/engine/installation).

### Openstackclient Python Libraries

To manage an OpenStack cloud from command line requires the [OpenStack command-line](http://docs.openstack.org/user-guide/common/cli-install-openstack-command-line-clients.html) client. Instructions to install and use the client can be found in its webpage. Briefly, being a python tool it is best to install it in a virtualenv:
``` sh
virtualenv ~/python-openstack
. ~/python-openstack/bin/activate
pip install python-openstackclient
```

We also need to configure our system to access the OpenStack cloud. The easiest route is to set environment variables using the OpenStack RC file. Download this file from your cloud at `Access & Security > API Access > Download OpenStack RC file` and save locally. Source it before issuing OpenStack client commands and enter your password:
``` sh
. openstack.rc
```

### Vagrant

Download Vagrant from https://www.vagrantup.com/downloads.html.

## Post-processors

Providers might need some post-processing to convert artifacts to the appropriate format. The following is a list of dependencies.

### qemu-img

qemu-img is used to convert the Packer artifacts for the `azure` and `gcp` providers into their proper format for upload. qemu-img is part of qemu and can be found in mainstream distributions as part of the qemu-utils or qemu-img packages.

### ovftool

The Open Virtualization Format Tool (ovftool) is used to convert the Packer artifact for `vmware` from VMX to OVA format, which is needed to upload to VMware servers. Note that you will need to be registered at my.vmware.com to download ovftool. Follow these links to [download](https://code.vmware.com/tool/ovf) and access the [documentation](https://www.vmware.com/support/developer/ovf).

### virt-tar-out

virt-tar-out is used to produce a compress tar file from the Packer artifact for the `docker` provider. [virt-tar-out](http://libguestfs.org/virt-tar-out.1.html) is part of [libguestfs](http://libguestfs.org). Install `libguestfs-tools` from your package manager or see [here](http://libguestfs.org/guestfs-faq.1.html#binaries) for further instructions.

### sha256sum

sha256sum is needed to generate the SHA256 checksums of all files created by Packer. Usually found in package coreutils.

# TODO

- User vagrant? Different users might be needed for each artifact
- Bigger disk size and allow to grow?
- guest_os_type variables for vbox and VMware should go in OS template
- Move vm_name out of OS templates?
- Add other options, ie locale, root pass, ...
- Move files with options to example files
- Automate vagrant boxes catalog metadata files in artifacts
- Better description of which variables are set in `site.json`
- Provide defaults for `site.json` variables in kickstarts and ansible (in case they are not defined in `site.json`)
- Talk about artifact's size in readme.
- Document what ansible playbooks do in detail.

Licence
-------
Released under the [MIT license](https://opensource.org/licenses/MIT).

Author Information
------------------
Luis Gracia while at [EMBL-EBI](http://www.ebi.ac.uk/):
- luis.gracia [at] ebi.ac.uk
- GitHub at [luisico](https://github.com/luisico)
- Galaxy at [luisico](https://galaxy.ansible.com/luisico)
