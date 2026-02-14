TF_HOSTS_FILE := "tf_hosts.json"
MANUAL_HOSTS_FILE := "manual_hosts.json"
HOSTS_FILE := "hosts.json"

tf-apply +args="":
    cd terraform && terraform apply {{ args }}
    cd terraform && terraform output -json > ../{{ TF_HOSTS_FILE }}
    @just _merge-hosts

tf-destroy +args="":
    cd terraform && terraform destroy {{ args }}
    cd terraform && terraform output -json > ../{{ TF_HOSTS_FILE }}
    @just _merge-hosts

[private]
_merge-hosts:
    #!/usr/bin/env bash
    echo "🔄 Merging {{ TF_HOSTS_FILE }} and {{ MANUAL_HOSTS_FILE }}"
    TF_DATA=$(jq '.server_ips.value // {}' {{ TF_HOSTS_FILE }} 2>/dev/null || echo '{}')
    MANUAL_DATA=$(cat {{ MANUAL_HOSTS_FILE }} 2>/dev/null || echo '{}')

    echo "$TF_DATA $MANUAL_DATA" | jq -s '.[0] * .[1]' > {{ HOSTS_FILE }}

    echo "✅ Updated {{ HOSTS_FILE }}"

bootstrap host: _merge-hosts
    #!/usr/bin/env bash
    set -e
    IP=$(jq -r '."{{ host }}"' {{ HOSTS_FILE }})

    echo "Test"
    if [ "$IP" = "null" ] || [ -z "$IP" ]; then
        echo "❌ Error: Host '{{ host }}' not found in {{ HOSTS_FILE }}"
        echo "Available hosts:"
        jq -r 'keys[]' {{ HOSTS_FILE }}
        exit 1
    fi

    echo "🚀 Bootstrapping {{ host }} ($IP)..."

    cd colmena && nix run github:nix-community/nixos-anywhere -- --flake .#{{ host }} "root@$IP"

bootstrap-all: _merge-hosts
    #!/usr/bin/env bash
    set -e
    HOSTS=$(jq -r 'keys[]' {{ HOSTS_FILE }})

    if [ -z "$HOSTS" ]; then
        echo "⚠️ No hosts found in {{ HOSTS_FILE }}."
        exit 0
    fi

    for host in $HOSTS; do
        just bootstrap "$host"
    done

deploy +args="":
    @just _merge-hosts
    cd colmena && colmena apply {{ args }}

keygen host: _merge-hosts
    #!/usr/bin/env bash
    set -e
    IP=$(jq -r '."{{ host }}"' {{ HOSTS_FILE }})

    if [ "$IP" = "null" ] || [ -z "$IP" ]; then
        echo "❌ Error: Host '{{ host }}' not found in {{ HOSTS_FILE }}"
        echo "Available hosts:"
        jq -r 'keys[]' {{ HOSTS_FILE }}
        exit 1
    fi

    echo "🧹 Removing SSH key for {{ host }} ($IP)..."
    ssh-keygen -R $IP
    echo "✅ Key removed."

keygen-all: _merge-hosts
    #!/usr/bin/env bash
    IPS=$(jq -r 'values[]' {{ HOSTS_FILE }})

    if [ -z "$IPS" ]; then
        echo "⚠️ No hosts found."
        exit 0
    fi

    for ip in $IPS; do
        echo "🧹 Removing SSH key for $IP..."
        ssh-keygen -R "$ip"
        echo "✅ Key removed."
    done

get-age-key host: _merge-hosts
    #!/usr/bin/env bash
    set -e
    IP=$(jq -r '."{{ host }}"' {{ HOSTS_FILE }})

    if [ "$IP" = "null" ] || [ -z "$IP" ]; then
        echo "❌ Error: Host '{{ host }}' not found in {{ HOSTS_FILE }}"
        echo "Available hosts:"
        jq -r 'keys[]' {{ HOSTS_FILE }}
        exit 1
    fi

    echo "🔍 Scanning SSH host key for {{ host }} ($IP)..."
    KEY=$(ssh-keyscan -t ed25519 $IP 2>/dev/null | grep "ssh-ed25519" | ssh-to-age)

    if [ -z "$KEY" ]; then
        echo "❌ Failed to retrieve or convert key. Is the host reachable?"
        exit 1
    fi

    echo ""
    echo "✅ Age Public Key for {{ host }}:"
    echo "$KEY"
    echo ""
    echo "📋 Add this to your .sops.yaml keys list!"

update-keys:
    @echo "🔐 Updating keys for all secrets..."
    @find colmena/secrets -name "*.yaml" -type f -exec sops updatekeys -y {} \;
    @echo "✅ All secrets updated."
