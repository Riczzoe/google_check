#!/usr/bin/env bash
set -euo pipefail
umask 077

BASE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

check_youtube_region() {
    local ytb_resp region
    ytb_check_res="Unknown"

    if ytb_resp=$(curl -4 --noproxy '*' -sSL --max-time 10 \
        -H 'Accept-Language: en' \
        -b 'YSC=BiCUU3-5Gdk; CONSENT=YES+cb.20220301-11-p0.en+FX+700; GPS=1; VISITOR_INFO1_LIVE=4VwPMkB7W5A; PREF=tz=Asia.Shanghai; _gcl_au=1.1.1809531354.1646633279' \
        'https://www.youtube.com/premium' 2>&1); then

        region=$(sed -nE \
            's/.*"contentRegion"[[:space:]]*:[[:space:]]*"([A-Z]{2})".*/\1/p' \
            <<< "$ytb_resp" | sed -n '1p')
        if grep -q 'www\.google\.cn' <<< "$ytb_resp" || [[ "$region" == "CN" ]]; then
            ytb_check_res="China [CN]"
        elif [[ -n "$region" ]] && grep -q 'ad-free' <<< "$ytb_resp"; then
            ytb_check_res="Premium available [${region}]"
        fi
    fi

    return 0
}

check_google_url() {
    local jar final_url
    google_check_res="Unknown"
    jar=$(mktemp 2>/dev/null) || return 0

    if final_url=$(curl -4 --noproxy '*' -sSL --max-time 10 \
        -A "${UA:-Mozilla/5.0}" -H 'Accept-Language: en-US,en;q=0.9' \
        -c "$jar" -b "$jar" -o /dev/null -w '%{url_effective}' 'https://www.google.com/' 2>/dev/null); then

        [[ -z "$final_url" ]] || google_check_res="$final_url"
    fi

    rm -f "$jar"
    return 0
}

send_telegram() {
    local response
    if ! response=$(curl -q --noproxy '*' -fsS --max-time 20 \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=$1" 2>/dev/null); then
        return 1
    fi
}

main() {
    [[ -f "$BASE_DIR/.env" ]] || { printf '%s\n' 'Missing .env configuration.' >&2; return 1; }
    source "$BASE_DIR/.env"
    [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" ]] || {
        printf '%s\n' 'Configure TG_BOT_TOKEN and TG_CHAT_ID in .env.' >&2
        return 1
    }

    local dependency
    for dependency in curl flock; do
        command -v "$dependency" >/dev/null || { printf 'Missing dependency: %s\n' "$dependency" >&2; return 1; }
    done

    exec 9>"$BASE_DIR/.monitor.lock"
    flock -n 9 || return 0

    local state_file="$BASE_DIR/.last_state" previous="" current message pending
    check_youtube_region
    check_google_url

    current=$(printf 'YouTube: %s\nGoogle URL: %s' "$ytb_check_res" "$google_check_res")
    if [[ -f "$state_file" ]]; then
        previous=$(cat -- "$state_file")
        [[ "$current" != "$previous" ]] || return 0
    fi

    # Save
    pending=$(mktemp "$BASE_DIR/.last_state.XXXXXX")
    printf '%s\n' "$current" > "$pending"
    mv -f -- "$pending" "$state_file"

    printf -v message 'Server: %s\nTime: %s\n\nPrevious:\n%s\n\nCurrent:\n%s' \
        "${SERVER_NAME:-$(hostname)}" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "${previous:-No previous record}" "$current"

    send_telegram "$message"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

