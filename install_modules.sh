#!/bin/bash

MODULE_PATH=/etc/puppet/modules

function remove_module {
  local SHORT_MODULE_NAME=$1
  if [ -n "$SHORT_MODULE_NAME" ]; then
    rm -Rf "$MODULE_PATH/$SHORT_MODULE_NAME"
  else
    echo "ERROR: remove_module requires a SHORT_MODULE_NAME."
  fi
}

# Array of modules to be installed key:value is module:version.
declare -A MODULES

# Array of modues to be installed from source and without dependency resolution.
# key:value is source location, revision to checkout
declare -A SOURCE_MODULES

#NOTE: if we previously installed kickstandproject-ntp we nuke it here
# since puppetlabs-ntp and kickstandproject-ntp install to the same dir
if grep kickstandproject-ntp /etc/puppet/modules/ntp/Modulefile &> /dev/null; then
  remove_module "ntp"
fi

remove_module "gearman" #remove old saz-gearman
remove_module "limits" # remove saz-limits (required by saz-gearman)

MODULES["puppetlabs-ntp"]="0.2.0"

# freenode #puppet 2012-09-25:
# 18:25 < jeblair> i would like to use some code that someone wrote,
# but it's important that i understand how the author wants me to use
# it...
# 18:25 < jeblair> in the case of the vcsrepo module, there is
# ambiguity, and so we are trying to determine what the author(s)
# intent is
# 18:30 < jamesturnbull> jeblair: since we - being PL - are the author
# - our intent was not to limit it's use and it should be Apache
# licensed
MODULES["openstackci-vcsrepo"]="0.0.8"

MODULES["puppetlabs-apache"]="0.0.4"
MODULES["puppetlabs-apt"]="1.4.2"
MODULES["puppetlabs-haproxy"]="0.4.1"
MODULES["puppetlabs-mysql"]="0.6.1"
MODULES["puppetlabs-postgresql"]="4.0.0"
MODULES["puppetlabs-stdlib"]="4.3.2"
MODULES["saz-memcached"]="2.0.2"
MODULES["spiette-selinux"]="0.5.1"
MODULES["rafaelfc-pear"]="1.0.3"
MODULES["puppetlabs-inifile"]="1.0.0"
MODULES["puppetlabs-firewall"]="0.0.4"
MODULES["puppetlabs-puppetdb"]="3.0.1"
MODULES["stankevich-python"]="1.6.6"
MODULES["puppetlabs-rabbitmq"]="4.0.0"
MODULES["puppetlabs-rabbitmq"]="4.0.0"
MODULES["garethr-docker"]="2.0.0"

# Source modules should use tags, explicit refs or remote branches because
# we do not update local branches in this script.
SOURCE_MODULES["https://github.com/puppet-community/puppet-module-puppetboard"]="2.4.0"

# Add modules that should be part of the openstack-infra integration test here
if [[ "$PUPPET_INTEGRATION_TEST" -ne "1" ]]; then
  SOURCE_MODULES["https://git.openstack.org/openstack-infra/puppet-storyboard"]="origin/master"
fi

MODULE_LIST=`puppet module list`

# Transition away from old things
if [ -d /etc/puppet/modules/vcsrepo/.git ]
then
  rm -rf /etc/puppet/modules/vcsrepo
fi

# Install all the modules
for MOD in ${!MODULES[*]} ; do
  # If the module at the current version does not exist upgrade or install it.
  if ! echo $MODULE_LIST | grep "$MOD ([^v]*v${MODULES[$MOD]}" >/dev/null 2>&1
  then
    # Attempt module upgrade. If that fails try installing the module.
    if ! puppet module upgrade $MOD --version ${MODULES[$MOD]} >/dev/null 2>&1
    then
      # This will get run in cron, so silence non-error output
      puppet module install $MOD --version ${MODULES[$MOD]} >/dev/null
    fi
  fi
done

MODULE_LIST=`puppet module list`

# Make a second pass, just installing modules from source
for MOD in ${!SOURCE_MODULES[*]} ; do
  # get the name of the module directory
  if [ `echo $MOD | awk -F. '{print $NF}'` = 'git' ]; then
    echo "Remote repos of the form repo.git are not supported: ${MOD}"
    exit 1
  fi
  MODULE_NAME=`echo $MOD | awk -F- '{print $NF}'`
  # set up git base command to use the correct path
  GIT_CMD_BASE="git --git-dir=${MODULE_PATH}/${MODULE_NAME}/.git --work-tree ${MODULE_PATH}/${MODULE_NAME}"
  # treat any occurrence of the module as a match
  if ! echo $MODULE_LIST | grep "${MODULE_NAME}" >/dev/null 2>&1; then
    # clone modules that are not installed
    git clone $MOD "${MODULE_PATH}/${MODULE_NAME}"
  else
    if [ ! -d ${MODULE_PATH}/${MODULE_NAME}/.git ]; then
      echo "Found directory ${MODULE_PATH}/${MODULE_NAME} that is not a git repo, deleting it and reinstalling from source"
      remove_module $MODULE_NAME
      git clone $MOD "${MODULE_PATH}/${MODULE_NAME}"
    elif [ `${GIT_CMD_BASE} remote show origin | grep 'Fetch URL' | awk -F'URL: ' '{print $2}'` != $MOD ]; then
      echo "Found remote in ${MODULE_PATH}/${MODULE_NAME} that does not match desired remote ${MOD}, deleting dir and re-cloning"
      remove_module $MODULE_NAME
      git clone $MOD "${MODULE_PATH}/${MODULE_NAME}"
    fi
  fi
  # fetch the latest refs from the repo
  $GIT_CMD_BASE remote update
  # make sure the correct revision is installed, I have to use rev-list b/c rev-parse does not work with tags
  if [ `${GIT_CMD_BASE} rev-list HEAD --max-count=1` != `${GIT_CMD_BASE} rev-list ${SOURCE_MODULES[$MOD]} --max-count=1` ]; then
    # checkout correct revision
    $GIT_CMD_BASE checkout ${SOURCE_MODULES[$MOD]}
  fi
done
