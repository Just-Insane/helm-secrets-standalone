#!/usr/bin/env bash
# shellcheck disable=SC1003

set -e

export yml=/Users/justin/Documents/CODE/kubernetes/src/services/nextcloud/values.yaml
export VAULT_ADDR=http://10.0.40.234:8200/
if [[ -z "${VAULT_TOKEN}" ]]
then
    export VAULT_TOKEN=
fi

# Parses yaml document
parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    local s
    local w
    local fs

    s='[[:space:]]*'
    w='[a-zA-Z0-9_.-]*'
    fs="$(echo @|tr @ '\034')"

    (
        sed -e '/- [^\“]'"[^\']"'.*: /s|\([ ]*\)- \([[:space:]]*\)|\1-\'$'\n''  \1\2|g' |

        sed -ne '/^--/s|--||g; s|\"|\\\"|g; s/[[:space:]]*$//g;' \
            -e "/#.*[\"\']/!s| #.*||g; /^#/s|#.*||g;" \
            -e "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
            -e "s|^\($s\)\($w\)${s}[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" |

        awk -F"$fs" '{
            indent = length($1)/2;
            if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
            vname[indent] = $2;
            for (i in vname) {if (i > indent) {delete vname[i]}}
                if (length($3) > 0) {
                    vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                    printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
                }
            }' |

        sed -e 's/_=/+=/g' |

        awk 'BEGIN {
                FS="=";
                OFS="="
            }
            /(-|\.).*=/ {
                gsub("-|\\.", "_", $1)
            }
            { print }'
    ) < "$yaml_file"
}

# Created environment variables for secrets key invocations as well as the image repository
create_variables() {
    local yaml_file="$1"
    local prefix="$2"
    eval "$(parse_yaml "$yaml_file" "$prefix" | awk '/changeme/{print $0}')"
    eval "$(parse_yaml "$yaml_file" "$prefix" | awk '/image_repository/{print $0}')"
}

# Prompts user for secret material and uploads to vault K/V Store
set_secrets() {
    report () { echo "${1%%=*}"; };

    envsarray=()
    while IFS= read -r line; do
        envsarray+=( "$line" )
    done < <( set -o posix +o allexport; set | grep "changeme" | awk 'match($0, "\.=") {print substr($0, 1, RSTART)}' )

    for env in "${envsarray[@]}";
    do
        echo "Enter a secret value for $image_repository/$env"
        read -r usersecret
        vault kv put secret/helm/$image_repository/$env value=$usersecret
    done
}

# Pulls secret material from vault K/V store and saves it to a .dec file, needed by helm to update or deploy
get_secrets() { 
    report () { echo "${1%%=*}"; };

    envsarray=()
    while IFS= read -r line; do
        envsarray+=( "$line" )
    done < <( set -o posix +o allexport; set | grep "changeme" | awk 'match($0, "\.=") {print substr($0, 1, RSTART)}' )

    yml_dec="$yml.dec"
    cp $yml $yml_dec

    for env in "${envsarray[@]}";
    do
        sec_values=`vault kv get secret/helm/$image_repository/$env | grep "value" | awk '/value/{print $2}'`
        echo "Secret Values = $sec_values"
        for sec in "${sec_values[@]}";
        do
            #this will fail if "changeme" is on the first line of the file, but is required for GNU sed
            sed -i.tmp "1,// s/changeme/$sec/" $yml_dec
        done
    done
}

create_variables $yml
set_secrets
get_secrets
