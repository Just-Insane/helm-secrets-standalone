#!/bin/bash
# shellcheck disable=SC1003

set -e

export yml=/Users/justin/Documents/CODE/kubernetes/src/services/nextcloud/values.yaml
export VAULT_ADDR=http://10.0.40.234:8200/
export VAULT_TOKEN=

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

create_variables() {
    local yaml_file="$1"
    local prefix="$2"
    eval "$(parse_yaml "$yaml_file" "$prefix" | awk '/changeme/{print $0}')"
    eval "$(parse_yaml "$yaml_file" "$prefix" | awk '/image_repository/{print $0}')"
}

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

get_secrets() { # Read secrets from Vault and write to values.yaml.dec file, substituting the values from helm into the plaintext values.yaml file
    report () { echo "${1%%=*}"; };

    envsarray=()
    while IFS= read -r line; do
        envsarray+=( "$line" )
    done < <( set -o posix +o allexport; set | grep "changeme" | awk 'match($0, "\.=") {print substr($0, 1, RSTART)}' )

    for env in "${envsarray[@]}";
    do
        yml_dec="$yml.dec"
        sec_values=`vault kv get secret/helm/$image_repository/$env | grep "value" | awk '/value/{print $2}'`
        echo "Secret Values = $sec_values"
        for sec in "${sec_values[@]}";
        do
            sed -i.dec "s/changeme/$sec/" $yml > $yml_dec
    done
}

create_variables $yml
set_secrets
get_secrets
