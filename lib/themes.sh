# rice themes: themes from the catalog (github.com/larion928/hypr-rice-themes), in packs. themegen.py fetches
# the catalog, checks its signature and each archive; here is the terminal's side of it.

cmd_themes() {
    case "${1:-}" in
        "") pick_catalog_themes ;;
        install) shift; install_catalog_themes "$@" ;;
        remove) shift; remove_catalog_themes "$@" ;;
        *) die "rice themes [install|remove <тема или пак>...]" ;;
    esac
    finish
}

themegen() { python3 "$HOME/.config/hypr/scripts/themegen.py" "$@"; }

# The menu: every catalog theme, the installed ones ticked; ticking installs, unticking removes.
pick_catalog_themes() {
    step "Темы из каталога"
    local catalog
    catalog=$(themegen catalog) || die "каталог тем не открылся"
    local options installed taken
    mapfile -t options < <(jq -r '.[] | .label as $pack | .themes[] | select(.state != "taken")
                                  | "\($pack) · \(.label)=\(.name)"' <<<"$catalog")
    installed=$(jq -r '[.[] | .label as $pack | .themes[] | select(.state == "installed" or .state == "changed")
                        | "\($pack) · \(.label)"] | join(",")' <<<"$catalog")
    taken=$(jq -r '[.[].themes[] | select(.state == "taken") | .name] | join(", ")' <<<"$catalog")
    [ -z "$taken" ] || info "не предлагаю (имя занято твоей темой или темой райса): $taken"
    if ! have_tty; then
        printf '    %s\n' "${options[@]%%=*}"
        return
    fi
    local picked
    picked=$(choose_many "Какие темы держать?" "$installed" "${options[@]}") || return 0
    local name to_install=() to_remove=()
    for name in $(jq -r '.[].themes[] | select(.state == "absent" or .state == "changed") | .name' <<<"$catalog"); do
        grep -qxF "$name" <<<"$picked" && to_install+=("$name")
    done
    for name in $(jq -r '.[].themes[] | select(.state == "installed" or .state == "changed") | .name' <<<"$catalog"); do
        grep -qxF "$name" <<<"$picked" || to_remove+=("$name")
    done
    [ ${#to_install[@]} -eq 0 ] || install_catalog_themes "${to_install[@]}"
    if [ ${#to_remove[@]} -gt 0 ] && ask "Удалить темы: ${to_remove[*]}?" n; then
        remove_catalog_themes "${to_remove[@]}"
    fi
}

install_catalog_themes() {  # install_catalog_themes THEME_OR_PACK...
    [ $# -gt 0 ] || die "rice themes install <тема или пак>..."
    local name
    for name in "$@"; do
        if themegen catalog-install "$name" >/dev/null; then
            ok "$name: поставлена"
        else
            warn "$name: не поставлена"
        fi
    done
}

remove_catalog_themes() {  # remove_catalog_themes THEME...
    [ $# -gt 0 ] || die "rice themes remove <тема>..."
    local name
    for name in "$@"; do
        if themegen delete "$name" >/dev/null; then
            ok "$name: удалена"
        else
            warn "$name: не удалена"
        fi
    done
}

# rice update: the installed catalog themes the catalog changed, and the current one applied again if it did.
update_catalog_themes() {
    local updated
    updated=$(themegen catalog-update) || { warn "темы из каталога не обновились"; return 0; }
    [ -n "$updated" ] || return 0
    ok "темы из каталога обновлены: $(paste -sd ' ' <<<"$updated")"
    if grep -qxF "$(current_theme)" <<<"$updated"; then
        apply_theme "$(current_theme)"
    fi
}
