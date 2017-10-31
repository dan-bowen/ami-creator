#!/usr/bin/env bash

############
# Commands #
############

command_help() {
    local help_message="
NAME
        ami-creator

DESCRIPTION

        ami-creator is a command line tool to build custom AMIs using Ansible for provisioning.

OPTIONS

        --version   Display the version of this tool.

AVAILABLE COMMANDS

    init                Create a new ami-creator project
    create              Create a custom AMI start to finish
    pre-ansible         Run a script on the instance before running Ansible
    ansible             Run Ansible on the instance
    ssh                 SSH to the currently running instance
    finalize            Create AMI from currently running instance
    terminate           Terminate the currently running instance
    list-amis           List AMIs created on a per-session, per-project or global basis
    list-instances      List any instances that are running on a per-session, per-project or global basis
";

    # if no parameters are sent in just display the help message
    if [ "$#" == 0 ]; then
        echo "${help_message}";
        exit 0;
    fi

    # parse parameters
    for i in "${@-}"
    do
    case ${i} in
        --version)
        echo "${VERSION}"
        exit 0;
        shift # past argument=value
        ;;
        *)
        echo "[ERROR] Unexpected option ${i}"
        echo "${help_message}";
        exit 1;
        ;;
    esac
    done

    exit 0;
}

command_create() {
    local help_message="
NAME
        ami-creator create

DESCRIPTION

        Create a custom AMI using Ansible for provisioning.

        This command must be called from inside the project directory.

AVAILABLE SUB-COMMANDS

        help    Display this help message

OPTIONS

        All arguments are optional. If given, they will override project values saved by 'ami-creator init'.

        [--profile]                  AWS profile. Same as 'aws --profile'. Default: 'default'
        [--ami-base]                 Base AMI to start building from
        [--ec2-ssh-key]              EC2 SSH key name to assign to the instance
        [--ec2-ssh-key-file]         EC2 SSH key file on your local machine to use for logging in
        [--ec2-ssh-user]             EC2 SSH user
        [--ec2-security-groups]      EC2 security groups to assign to the temporary instance
        [--ec2-subnets]              EC2 subnets to assign to the instance
        [--ec2-instance-type]        EC2 instance type
        [--iam-instance-profile]     IAM profile to assign to the instance
";

    # process arguments
    for i in "${@-}"
    do
    case ${i} in
        # subcommand
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
    esac
    done

    set_global_variables ${@-}

    # copy original playbook to pick up changes
    copy_playbook "../../${ANSIBLE_PLAYBOOK}" ${PROJECT_DIR}

    # Create the instance
    echo "[INFO] Creating temporary EC2 instance."
    create_instance
    echo "[INFO] Created instance id: ${INSTANCE_ID}";

    # Wait for it to exit pending state
    echo "[INFO] Waiting for instance to become available.";
    while state=$(aws ec2 describe-instances \
        --profile ${AWS_PROFILE} \
        --instance-ids ${INSTANCE_ID} \
        --output text \
        --query 'Reservations[*].Instances[*].State.Name');
        test "$state" = "pending";
    do
        sleep 1;
        echo -n '.';
    done

    # Get the public IP address
    ip_address=$(aws ec2 describe-instances \
        --profile ${AWS_PROFILE} \
        --instance-ids ${INSTANCE_ID} \
        --output text \
        --query 'Reservations[*].Instances[*].PublicIpAddress'
    );

    echo "[INFO] IP address of temporary instance: $ip_address";
    lock_ssh_config ${ip_address}

    echo "[INFO] Waiting for EC2 instance to finish initializing.";
    echo "[INFO] Sleeping for 180 seconds...";
    sleep 180;

    # run pre-ansible.sh
    pre_ansible

    # Provision with Ansible
    ansible ${INSTANCE_ID}

    echo "[INFO] Sleeping for 30 seconds..."
    sleep 30;

    echo "[INFO] Creating AMI...";
    ami_id=$(create_ami ${INSTANCE_ID});

    # Wait for it to exit pending state
    ami_wait ${ami_id}

    # Terminate temporary EC2 instance
    terminate_instances "session"
}

command_init() {
    local help_message="
NAME
        ami-creator init

DESCRIPTION

        Initialize a new ami-creator project.

AVAILABLE SUB-COMMANDS

        help    Display this help message

OPTIONS

        None. You will be prompted for project variables.
";

    # init is expected to be called in the ./ami-creator folder within the ansible directory. `dirname` should give us
    # the full path to the ansible directory structure.
    local ansible_dir=$(dirname ${CALLING_DIR})

    local project_name
    local ami_base
    local ec2_ssh_key
    local ec2_ssh_key_file
    local ec2_security_groups
    local ec2_subnets
    local ec2_instance_type
    local ec2_ssh_user
    local iam_instance_profile
    local aws_profile
    local ansible_playbook

    # process arguments
    for i in "${@-}"
    do
    case ${i} in
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
    esac
    done

    if [ -f ${CALLING_DIR}/project.cfg ]; then
        echo "[ERROR] cannot call init from inside a project directory"
        exit 1
    fi

    # @todo better checking for empty inputs that don't have defaults
    read -p 'Project Name (ex: innovative_project_dev): ' project_name
    read -p 'EC2 ssh key name (default: ami-creator): ' ec2_ssh_key

    # ensure SSH key file actually exists
    while true; do
        # -e gives us tab completion
        read -e -p 'Absolute path to ssh key file (default: ~/.ssh/ami-creator.pem): ' ec2_ssh_key_file

        # set up default ec2_ssh_key_file if nothing was entered
        ec2_ssh_key_file=$([ "${ec2_ssh_key_file}" == "" ] && echo "~/.ssh/ami-creator.pem" || echo "${ec2_ssh_key_file}");

        # allow tilde expansion to find files in home directory
        local expansion_check=${ec2_ssh_key_file/#~\//$HOME/}

        if [[ -f ${expansion_check} ]]; then
            break;
        else
            echo "[ERROR] File does not exist: ${expansion_check}"
            echo "Please try again..."
        fi
    done

    read -p 'EC2 ssh user (usually ec2-user or ubuntu. default: ec2-user): ' ec2_ssh_user
    read -p 'EC2 security groups (must allow SSH access): ' ec2_security_groups
    read -p 'EC2 subnets: ' ec2_subnets
    read -p 'EC2 instance type (default: t2.small): ' ec2_instance_type
    read -p 'IAM instance profile (default: ami-creator-instance): ' iam_instance_profile
    read -p 'AWS profile for issuing AWS CLI commands (default: default): ' aws_profile
    read -p 'Base AMI: ' ami_base

    # cd into ansible dir to start tab completion from the correct directory
    cd ${ansible_dir}
    # ensure Ansible playbook actually exists
    while true; do
        # -e gives us tab completion
        read -e -p "Ansible playbook, relative to ansible directory (${ansible_dir}): " ansible_playbook

        if [[ -f "${ansible_dir}/${ansible_playbook}" ]]; then
            break;
        else
            echo "[ERROR] File does not exist: ${ansible_dir}/${ansible_playbook}"
            echo "Please try again..."
        fi
    done
    # cd back to CALLING_DIR
    cd ${CALLING_DIR}

    # set up defaults
    local aws_profile=$([ "${aws_profile}" == "" ] && echo "default" || echo "${aws_profile}");
    local ec2_ssh_key=$([ "${ec2_ssh_key}" == "" ] && echo "ami-creator" || echo "${ec2_ssh_key}");
    local ec2_ssh_user=$([ "${ec2_ssh_user}" == "" ] && echo "ec2-user" || echo "${ec2_ssh_user}");
    local ec2_instance_type=$([ "${ec2_instance_type}" == "" ] && echo "t2.small" || echo "${ec2_instance_type}");
    local iam_instance_profile=$([ "${iam_instance_profile}" == "" ] && echo "ami-creator-instance" || echo "${iam_instance_profile}");

    # create project directory
    local project_dir="./${project_name}"
    mkdir ${project_dir}

    # create project config file
    cat <<EOF >> ${project_dir}/project.cfg
PROJECT_NAME='${project_name}'
ANSIBLE_PLAYBOOK='${ansible_playbook}'
AWS_PROFILE='${aws_profile}'
AMI_BASE='${ami_base}'
EC2_SSH_KEY='${ec2_ssh_key}'
EC2_SSH_KEY_FILE='${ec2_ssh_key_file}'
EC2_SSH_USER='${ec2_ssh_user}'
EC2_SECURITY_GROUPS='${ec2_security_groups}'
EC2_SUBNETS='${ec2_subnets}'
EC2_INSTANCE_TYPE='${ec2_instance_type}'
IAM_INSTANCE_PROFILE='${iam_instance_profile}'
EOF

    echo "[INFO] Created project configuration file: ${project_dir}/project.cfg"

    # create inventory file
    cat <<EOF >> ${project_dir}/inventory.ini
ami-creator
EOF

    echo "[INFO] Created inventory file:             ${project_dir}/inventory.ini"

    # create pre-ansible script
    cat <<'EOF' >> ${project_dir}/pre-ansible.sh
#!/usr/bin/env bash
set -euo pipefail

# @TODO handle other platforms

if apt-get -v &> /dev/null; then
    sudo apt-get -y update;
    sudo apt-get -y upgrade;
    sudo apt-get -y install python-simplejson;
    sudo apt-get -y update;
fi

if which yum &> /dev/null; then
    exit 1
fi
EOF

    chmod +x ${project_dir}/pre-ansible.sh

    echo "[INFO] Created pre-ansible script:         ${project_dir}/pre-ansible.sh"

    # Copy playbook. we should be in the 'ami-creator' folder when this happens
    copy_playbook "../${ansible_playbook}" ${project_dir}

    # create provisioning script
    cat <<EOF >> ${project_dir}/ansible.sh
#!/usr/bin/env bash
set -euo pipefail

ANSIBLE_ROLES_PATH=../../roles \\
ansible-playbook ./playbook.yml \\
    --inventory=./inventory.ini \\
    --ssh-common-args='-F ./ssh.cfg';
EOF

    chmod +x ${project_dir}/ansible.sh

    echo "[INFO] Created ansible script:             ${project_dir}/ansible.sh"

    # create starter ssh config file
    cat <<EOF >> ${project_dir}/ssh.cfg
Host ami-creator
  Hostname REPLACE_ME
  IdentityFile ${ec2_ssh_key_file}
  User ${ec2_ssh_user}
  Port 22
  TCPKeepAlive yes
EOF

    echo "[INFO] Created SSH configuration script:   ${project_dir}/ssh.cfg"

    # create session lockfile
    cat <<EOF >> ${project_dir}/session.lock
INSTANCE_ID=''
AMI_ID=''
EOF

}

command_pre_ansible() {
    local help_message="
NAME
        ami-creator pre-ansible

DESCRIPTION

        Run pre-ansible.sh script on currently running instance

AVAILABLE SUB-COMMANDS

        help    Display this help message
";

    # handle subcommands
    for i in "${@-}"
    do
    case ${i} in
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
    esac
    done

    set_global_variables ${@-}

    pre_ansible
}

command_ansible() {
    local help_message="
NAME
        ami-creator ansible

DESCRIPTION

        Run Ansible against the currently running instance

AVAILABLE SUB-COMMANDS

        help    Display this help message
";

    # handle subcommands
    for i in "${@-}"
    do
    case ${i} in
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
    esac
    done

    set_global_variables ${@-}

    ansible ${INSTANCE_ID}
}

command_terminate() {
    local help_message="
NAME
        ami-creator terminate

DESCRIPTION

        Terminate instance(s) created by ami-creator

AVAILABLE SUB-COMMANDS

        help    Display this help message

OPTIONS
        [--scope]       Optional. Limit instances by scope.
                        Valid choices: [ session | project | all ]
                        Default: session
";

    # set default scope
    local scope='session'

    # process arguments
    for i in "${@-}"
    do
    case ${i} in
        # subcommand
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
        --scope=*)
        scope="${i#*=}"
        shift # past argument=value
        ;;
    esac
    done

    # validate scopes
    declare -a valid_scopes=("session" "project" "all");
    if ! in_array valid_scopes "${scope}"; then
        echo "[ERROR] invalid --scope"
        exit 0;
    fi

    set_global_variables ${@-}

    terminate_instances "${scope}"
}

command_ssh() {
    local help_message="
NAME
        ami-creator ssh

DESCRIPTION

        SSH to the currently running instance

AVAILABLE SUB-COMMANDS

        help    Display this help message
";

    # process arguments
    for i in "${@-}"
    do
    case ${i} in
        # subcommand
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
        --scope=*)
        scope="${i#*=}"
        shift # past argument=value
        ;;
    esac
    done

    set_global_variables ${@-}

    local ssh_config_file="${PROJECT_DIR}/ssh.cfg"
    #source ${PROJECT_DIR}/session.lock

    ssh -F ${ssh_config_file} ami-creator;
}

command_finalize() {
    local help_message="
NAME
        ami-creator finalize

DESCRIPTION

        Create AMI from currently running instance

AVAILABLE SUB-COMMANDS

        help    Display this help message
";

    # handle subcommands
    for i in "${@-}"
    do
    case ${i} in
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
    esac
    done

    set_global_variables ${@-}

    echo "[INFO] Creating AMI...";
    ami_id=$(create_ami ${INSTANCE_ID});

    # Wait for it to exit pending state
    ami_wait ${ami_id}

    # Terminate temporary EC2 instance
    terminate_instances "session"
}

command_list_instances() {
    local help_message="
NAME
        ami-creator list-instances

DESCRIPTION

        List instances created by ami-creator

AVAILABLE SUB-COMMANDS

        help    Display this help message

OPTIONS
        [--scope]       Optional. Limit instances by scope.
                        Valid choices: [ project | session | all ]
                        Default: project
";

    local scope='project'

    for i in "${@-}"
    do
    case ${i} in
        # subcommand
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
        --scope=*)
        scope="${i#*=}"
        shift # past argument=value
        ;;
    esac
    done

    # validate scopes
    declare -a valid_scopes=("project" "session" "all");
    if ! in_array valid_scopes "${scope}"; then
        echo "[ERROR] invalid --scope"
        exit 0;
    fi

    set_global_variables ${@-}

    list_instances ${scope}
}

command_list_amis() {
    local help_message="
NAME
        ami-creator list-amis

DESCRIPTION

        List AMIs created by ami-creator

AVAILABLE SUB-COMMANDS

        help    Display this help message

OPTIONS
        [--scope]       Optional. Limit instances by scope.
                        Valid choices: [ project | session | all ]
                        Default: project
";

    local scope='project'

    for i in "${@-}"
    do
    case ${i} in
        # subcommand
        help)
        echo "${help_message}";
        exit 0;
        shift # past argument=value
        ;;
        --scope=*)
        scope="${i#*=}"
        shift # past argument=value
        ;;
    esac
    done

    # validate scopes
    declare -a valid_scopes=("project" "session" "all");
    if ! in_array valid_scopes "${scope}"; then
        echo "[ERROR] invalid --scope"
        exit 0;
    fi

    set_global_variables ${@-}

    list_amis ${scope}
}

#############
# Functions #
#############

set_global_variables() {
    # check for project configuration in current directory
    if [ -f ${CALLING_DIR}/project.cfg ]; then
        # source in project configuration variables
        source ${CALLING_DIR}/project.cfg
        PROJECT_DIR=${CALLING_DIR}

        # source in session veraibles
        source ${PROJECT_DIR}/session.lock
    fi

    # process configuration overrides
    for i in "${@-}"
    do
    case ${i} in
        --profile=*)
        AWS_PROFILE="${i#*=}"
        shift # past argument=value
        ;;
        --ami-base=*)
        AMI_BASE="${i#*=}"
        shift # past argument=value
        ;;
        --ec2-ssh-key=*)
        EC2_SSH_KEY="${i#*=}"
        shift # past argument=value
        ;;
        --ec2-ssh-key-file=*)
        EC2_SSH_KEY_FILE="${i#*=}"
        shift # past argument=value
        ;;
        --ec2-ssh-user=*)
        EC2_SSH_USER="${i#*=}"
        shift # past argument=value
        ;;
        --ec2-security-groups=*)
        EC2_SECURITY_GROUPS="${i#*=}"
        shift # past argument=value
        ;;
        --ec2-subnets=*)
        EC2_SUBNETS="${i#*=}"
        shift # past argument=value
        ;;
        --ec2-instance-type=*)
        EC2_INSTANCE_TYPE="${i#*=}"
        shift # past argument=value
        ;;
        --iam-instance-profile=*)
        IAM_INSTANCE_PROFILE="${i#*=}"
        shift # past argument=value
        ;;
    esac
    done

    #
    # Validate global variables
    #
    if [ -z "$AMI_BASE" ]; then
        echo "[ERROR] missing option --ami-base"
        exit 1;
    fi
    if [ -z "$EC2_INSTANCE_TYPE" ]; then
        echo "[ERROR] missing option --ec2-instance-type"
        exit 1;
    fi
    if [ -z "$EC2_SSH_KEY" ]; then
        echo "[ERROR] missing option --ec2-ssh-key"
        exit 1;
    fi
    if [ -z "$EC2_SSH_KEY_FILE" ]; then
        echo "[ERROR] missing option --ec2-ssh-key-file"
        exit 1;
    fi
    if [ -z "$EC2_SSH_USER" ]; then
        echo "[ERROR] missing option --ec2-ssh-user"
        exit 1;
    fi
    if [ -z "$EC2_SECURITY_GROUPS" ]; then
        echo "[ERROR] missing option --ec2-security-groups"
        exit 1;
    fi
    if [ -z "$EC2_SUBNETS" ]; then
        echo "[ERROR] missing option --ec2-subnets"
        exit 1;
    fi
    if [ -z "$IAM_INSTANCE_PROFILE" ]; then
        echo "[ERROR] missing option --iam-instance-profile"
        exit 1;
    fi
}

in_array() {
    local haystack=${1}[@]
    local needle=${2}
    for i in ${!haystack}; do
        if [[ ${i} == ${needle} ]]; then
            return 0
        fi
    done
    return 1
}

confirm_or_exit() {
    local prompt=$1
    local input
    while true
        do
            read -p "${prompt}" input
            case ${input} in
                y|Y|YES|yes|Yes)
                    break ;;
                n|N|NO|no|No)
                    echo "Aborting - you entered $input"
                    exit ;;
                *) echo "Please enter only y|Y|YES|yes|Yes or n|N|NO|no|No"
            esac
        done
    echo "You entered $input. Continuing..."
}

copy_playbook() {
    local ansible_playbook=$1
    local project_dir=$2

    echo "[INFO] Copied Ansible playbook: ${ansible_playbook} -> ${project_dir}/playbook.yml"

    cp ${ansible_playbook} ${project_dir}/playbook.yml
    sed -i "" -E "s/^(.*)hosts:(.*)/\1hosts: ami-creator/g" ${project_dir}/playbook.yml
}

# @todo genericize setting session variables
lock_instance_id() {
    local instance_id=$1
    local lockfile="${PROJECT_DIR}/session.lock"

    # replace instance_id in lockfile
    sed -i "" "s/^INSTANCE_ID.*/INSTANCE_ID='$instance_id'/" ${lockfile}

    # session just changed. update the global session variable
    INSTANCE_ID="${instance_id}"
}

# @todo genericize setting session variables
lock_ami_id() {
    local ami_id=$1
    local lockfile="${PROJECT_DIR}/session.lock"

    # replace ami_id in lockfile
    sed -i "" "s/^AMI_ID.*/AMI_ID='$ami_id'/" ${lockfile}

    # session just changed. update the global session variable
    AMI_ID="${ami_id}"
}

lock_ssh_config() {
    local ip_address=$1
    local ssh_config_file="${PROJECT_DIR}/ssh.cfg"

    # replace IP address
    echo "[INFO] Updating Hostname in $ssh_config_file";
    sed -i "" "s/^  Hostname.*/  Hostname $ip_address/" ${ssh_config_file}

    # replace SSH key name
    echo "[INFO] Updating IdentityFile in $ssh_config_file";
    # use : instead of / for sed delimiter. The filename might contain / which will confuse sed
    sed -i "" "s:^  IdentityFile.*:  IdentityFile $EC2_SSH_KEY_FILE:" ${ssh_config_file}

    # replace SSH user
    echo "[INFO] Updating User in $ssh_config_file";
    sed -i "" "s/^  User.*/  User $EC2_SSH_USER/" ${ssh_config_file}
}

create_instance() {
    local instance_id=$(aws ec2 run-instances \
        --profile ${AWS_PROFILE} \
        --image-id ${AMI_BASE} \
        --count 1 \
        --instance-type ${EC2_INSTANCE_TYPE} \
        --key-name ${EC2_SSH_KEY} \
        --security-group-ids ${EC2_SECURITY_GROUPS} \
        --subnet-id ${EC2_SUBNETS} \
        --iam-instance-profile Name=${IAM_INSTANCE_PROFILE} \
        --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=ami-creator},{Key=ami-creator,Value=ami-creator},{Key=ami-creator-project,Value=${PROJECT_NAME}}]" \
            "ResourceType=volume,Tags=[{Key=Name,Value=ami-creator},{Key=ami-creator,Value=ami-creator},{Key=ami-creator-project,Value=${PROJECT_NAME}}]" \
        --associate-public-ip-address \
        --output text \
        --query 'Instances[*].InstanceId');

    # @todo exit if this fails

    # write instance_id to lockfile
    lock_instance_id ${instance_id}
}

list_instances() {
    local scope=$1
    local filters

    if [ "${scope}" == 'all' ]; then
        echo "[INFO] Listing instances tagged with ami-creator=ami-creator"
        filters='Name=tag:ami-creator,Values=ami-creator'
    elif [ "${scope}" == 'project' ]; then
        echo "[INFO] Listing instances tagged with ami-creator-project=${PROJECT_NAME}"
        filters="Name=tag:ami-creator-project,Values=${PROJECT_NAME}"
    else
        # 'session' scope
        echo "[INFO] Listing Instance ID: ${INSTANCE_ID}"
        filters="Name=instance-id,Values=${INSTANCE_ID}"
    fi

    # @todo show instance name
    aws ec2 describe-instances \
        --profile ${AWS_PROFILE} \
        --filters ${filters} \
        --query 'Reservations[*].Instances[*].{SecurityGroups:SecurityGroups[*].GroupName|join(`"\n"`, @),ID:InstanceId,Project:Tags[?Key==`ami-creator-project`]|[0].Value,State:State.Name,Type:InstanceType,"SSH Key":KeyName,"Public IP":PublicIpAddress,Subnet:SubnetId,Profile:IamInstanceProfile.Arn,State:State.Name}' \
        --output table
}

list_amis() {
    local scope=$1
    local filters

    if [ "${scope}" == 'all' ]; then
        echo "[INFO] Listing AMIs tagged with ami-creator=ami-creator"
        filters='Name=tag:Name,Values=ami-creator'
    elif [ "${scope}" == 'project' ]; then
        echo "[INFO] Listing AMIs tagged with ami-creator-project=${PROJECT_NAME}"
        filters="Name=tag:ami-creator-project,Values=${PROJECT_NAME}"
    else
        echo "[INFO] Listing AMI ID: ${AMI_ID}"
        filters="Name=image-id,Values=${AMI_ID}"
    fi

    aws ec2 describe-images \
        --profile ${AWS_PROFILE} \
        --filters ${filters} \
        --query 'Images[*].{ID:ImageId,Name:Name,Description:Description,Project:Tags[?Key==`ami-creator-project`]|[0].Value,State:State}' \
        --output table
}

get_instances_by_scope() {
    local scope=$1
    local filters
    local instances

    if [ "${scope}" = 'all' ]; then
        filters='Name=tag:Name,Values=ami-creator'
    elif [ "${scope}" = 'project' ]; then
        filters="Name=tag:ami-creator-project,Values=${PROJECT_NAME}"
    else
        filters="Name=instance-id,Values=${INSTANCE_ID}"
    fi

    instances=$(aws ec2 describe-instances \
        --profile ${AWS_PROFILE} \
        --filters ${filters} \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text);

    echo ${instances}
}

# @todo name this something else so it doesn't conflict with the actual `ansible` command
# @todo copy playbook here instead of outside??? to ensure we always have the latest playbook whenever ansible is run
ansible() {
    local instance_id=$1
    local ansible_exit_code

    echo "[INFO] Provisioning with Ansible."
    ${PROJECT_DIR}/ansible.sh
    ansible_exit_code=$?

    if [ ${ansible_exit_code} != 0 ]; then
        echo "[ERROR] Ansible provisioning failed."
        exit 1
    fi

    return ${ansible_exit_code}
}

terminate_instances() {
    local scope=$1

    # list instances that would be terminated
    list_instances ${scope}

    # get instance IDs for termination
    local instances=$(get_instances_by_scope ${scope})

    # confirm before terminating
    confirm_or_exit "Are you sure you want to terminate the listed instances? [y/n] "

    local terminated_instance=$(aws ec2 terminate-instances \
        --profile ${AWS_PROFILE} \
        --instance-ids ${instances} \
        --output text \
        --query 'TerminatingInstances[*].InstanceId');

    # @todo exit if this fails

    # remove instance id from lockfile
    lock_instance_id ''
}

create_ami() {
    local instance_id=$1
    local ami_version=$(date "+%Y-%m-%d-%H.%M.%S")
    local ami_id=$(aws ec2 create-image \
        --profile ${AWS_PROFILE} \
	    --instance-id ${instance_id} \
	    --name "${PROJECT_NAME}-${ami_version}" \
	    --description "Created by ami-creator" \
	    --reboot \
	    --output text);

    # lock AMI ID in session
    lock_ami_id ${ami_id}

    # tag AMI so we can query for it in AWS
	aws ec2 create-tags \
	    --profile ${AWS_PROFILE} \
	    --resources ${ami_id} \
	    --tags "Key=ami-creator,Value=ami-creator" "Key=ami-creator-project,Value=${PROJECT_NAME}" "Key=Name,Value=ami-creator"

    echo ${ami_id}
}

ami_wait() {
    local ami_id=$1
    local state
    # Wait for it to exit pending state
    echo "[INFO] Waiting for AMI to exit pending state...";
    while state=$(aws ec2 describe-images \
        --profile ${AWS_PROFILE} \
        --image-ids ${ami_id} \
        --output text \
        --query 'Images[*].State');

        test "$state" = "pending";
    do
        sleep 1;
        echo -n '.';
    done;

    echo "[INFO] AMI state: $state";
    echo "[INFO] Created AMI ID: $ami_id";
}

pre_ansible() {
    local copy_exit_code
    local execute_exit_code

    # copy pre-ansible.sh to instance
    echo "[INFO] Copying ./pre-ansible.sh to instance at /tmp/pre-ansible.sh"
    scp -F ${PROJECT_DIR}/ssh.cfg ${PROJECT_DIR}/pre-ansible.sh ami-creator:/tmp/
    copy_exit_code=$?
    if [ ${copy_exit_code} != 0 ]; then
        echo "[ERROR] Failed to copy ./pre-ansible.sh to instance at /tmp/pre-ansible.sh"
        exit 1
    else
        echo "[INFO] Copied ./pre-ansible.sh to instance at /tmp/pre-ansible.sh"
    fi

    # run pre-ansible.sh on instance
    echo "[INFO] Executing /tmp/pre-ansible.sh on instance."
    ssh -F ${PROJECT_DIR}/ssh.cfg ami-creator '/tmp/pre-ansible.sh';
    execute_exit_code=$?
    if [ ${execute_exit_code} != 0 ]; then
        echo "[ERROR] pre-ansible.sh provisioning failed."
        exit 1
    else
        echo "[INFO] pre-ansible provisioning succeeded."
    fi
}

main() {
    local command=$1;

    case ${command} in
        help)
        command_help ${@:2}
        exit 0
        ;;
        init)
        command_init ${@:2}
        exit 0
        ;;
        create)
        command_create ${@:2}
        exit 0
        ;;
        pre-ansible)
        command_pre_ansible ${@:2}
        exit 0
        ;;
        ansible)
        command_ansible ${@:2}
        exit 0
        ;;
        ssh)
        command_ssh ${@:2}
        exit 0
        ;;
        finalize)
        command_finalize ${@:2}
        exit 0
        ;;
        list-instances)
        command_list_instances ${@:2}
        exit 0
        ;;
        list-amis)
        command_list_amis ${@:2}
        exit 0
        ;;
        terminate)
        command_terminate ${@:2}
        exit 0
        ;;
        *)
        echo "${USAGE}";
        echo "[ERROR] invalid command"
        exit 1;
        ;;
    esac
}
