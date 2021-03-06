#!/bin/bash

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

prog_version=0.2


if tput init >/dev/null 2>&1; then
    # Enable colors
    normal=$(tput sgr0)
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    cyan=$(tput setaf 6)
else
    normal=""
    red=""
    green=""
    cyan=""
fi


# https://confluence.jetbrains.com/display/TCD10/Configuring+Build+Parameters
teamcity() {
    echo "##teamcity[$@]"
}

# Basic status function
_status() {
    local type="${1}"
    local status="${package:+${package}: }${2}"
    local items=("${@:3}")

    if [[ -n ${TEAMCITY_VERSION} ]]; then
        case "${type}" in
            block_open)  local teamcity_args="blockOpened name='${status}'" ;;
            block_close) local teamcity_args="blockClosed name='${status}'" ;;
            message)     local teamcity_args="message text='${status}'" ;;
            failure)     local teamcity_args="buildProblem description='${status}'" ;;
            success)     return 0 ;;  # skip it, TC will set the default "Success" badge by default
        esac
        teamcity "${teamcity_args}"
        printf "${items:+\t%s\n}" "${items:+${items[@]}}"
    else
        case "${type}" in
            block_close) return 0 ;;  # don't report when running from terminal
            block_open|message)
                     local color="${cyan}";  title='[BUILD]' ;;
            failure) local color="${red}";   title='[BUILD] FAILURE:' ;;
            success) local color="${green}"; title='[BUILD] SUCCESS:' ;;
        esac
        echo "${color}${title}${normal} ${status}" >&2
        printf "${items:+\t%s\n}" "${items:+${items[@]}}" >&2
    fi
}

# Status functions
error() { echo "$@" >&2; exit -1; }
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}" "${items[@]}"; exit 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}" "${items[@]}"; exit 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}" "${items[@]}"; }
block_open()  { local status="${1}"; local items=("${@:2}"); _status block_open  "${status}"  "${items[@]}"; }
block_close() { local status="${1}"; local items=("${@:2}"); _status block_close "${status}"  "${items[@]}"; }


# Git configuration
git_config() {
    local name="${1}"
    local value="${2}"
    test -n "$(git config ${name})" && return 0
    git config --global "${name}" "${value}" && return 0
    failure 'Could not configure Git for makepkg'
}


# Passes arguments to `find` and removes found files verbosely
find_and_rm() {
    local f
    while read -rd '' f; do
        rm -vf "$f"
    done < <(find "$@" -print0)
}


# Get package information
_package_info() {
    local package="${1}"
    local properties=("${@:2}")
    test -f "${PKG_ROOT_DIR}/${package}/PKGBUILD" || failure "Unknown package: ${PKG_ROOT_DIR}/${package}/PKGBUILD"
    for property in "${properties[@]}"; do
        eval "${property}=()"
        local value=($(
            source "${MAKEPKG_CONF}" > /dev/null && \
            cd "${PKG_ROOT_DIR}/${package}" && \
            source "PKGBUILD" > /dev/null
            eval echo "\${${property}[@]}"))
        eval "${property}=(\"\${value[@]}\")"
    done
}

# Package provides another
_package_provides() {
    local package="${1}"
    local another="${2}"
    local pkgname provides
    _package_info "${package}" pkgname provides
    for pkg_name in "${pkgname[@]}";  do [[ "${pkg_name}" = "${another}" ]] && return 0; done
    for provided in "${provides[@]}"; do [[ "${provided}" = "${another}" ]] && return 0; done
    return 1
}

# Add package to build after required dependencies
_build_add() {
    local include_makedepends="${1}"  # 0 or 1
    local package="${2}"

    local depends makedepends
    local seen_package

    for seen_package in "${seen_packages[@]}"; do
        [[ "${seen_package}" = "${package}" ]] && return 0
    done
    seen_packages+=("${package}")

    _package_info "${package}" depends makedepends

    local kind='runtime'
    if (( include_makedepends )); then
        kind='build'
        depends+=("${makedepends[@]}")
    fi

    message "Resolving ${kind} dependencies" "${depends[@]}"

    for dependency in "${depends[@]}"; do
        _build_add ${include_makedepends} "${dependency}"
    done
    sorted_packages+=("${package}")
}

# Sort packages by dependency
define_build_order() {
    local unsorted_packages=("$@")

    local seen_packages
    local sorted_packages
    local unsorted_package

    seen_packages=()
    sorted_packages=()
    for unsorted_package in "${unsorted_packages[@]}"; do
        _build_add 1 "${unsorted_package}"
    done
    make_packages=("${sorted_packages[@]}")

    seen_packages=()
    sorted_packages=()
    for unsorted_package in "$@"; do
        _build_add 0 "${unsorted_package}"
    done
    packages=("${sorted_packages[@]}")
}


get_pkgfile() {
    local pkgfile_noext
    pkgfile_noext=$(get_pkgfile_noext "${1}") || failure "Unknown package file"
    printf "%s%s\n" "${pkgfile_noext}" "${PKGEXT}"
}

get_pkgfile_noext() {
    epoch=0
    _package_info "${1}" pkgname epoch pkgver pkgrel arch

    if [[ $arch != "any" ]]; then
        arch="$CARCH"
    fi

    if (( epoch > 0 )); then
        printf "%s\n" "${pkgname}-$epoch:$pkgver-$pkgrel-$arch"
    else
        printf "%s\n" "${pkgname}-$pkgver-$pkgrel-$arch"
    fi
}

pkgfilename() {
    [[ -n "${package}" ]] || failure "\${package} undefined"
    get_pkgfile "${package}"
}


# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
    block_open "${status}"
    ${command} ${arguments[@]} || failure "${status} failed"
    block_close "${status}"
}

execute_cd(){
    local d="${1}"
    local status="${2}"
    local command="${3}"
    local arguments=("${@:4}")
    block_open "${status}"
    pushd "${d}" > /dev/null
    ${command} ${arguments[@]} || failure "${status} failed"
    popd > /dev/null
    block_close "${status}"
}


usage() {
    printf "%s %s\n" "$0" "$prog_version"
    echo
    printf -- "Build packages using makepkg and bundle a single archive\n"
    echo
    printf -- "Usage: %s [-P <pkgroot>] [-c <makepkg.conf>] [OPTION...] [--] [PACKAGE...]\n" "$0"
    echo
    printf -- "Options:\n"
    printf -- "  -P, --pkgroot <dir>  Directory to search packages in (instead of '%s')\n" "\$CWD"
    printf -- "  -c, --config <file>  Use an alternate config file (instead of '%s')\n" "\$pkgroot/makepkg.conf"
    printf -- "  --nomakepkg          Do not rebuild packages\n"
    printf -- "  --noinstall          Do not extract packages into '%s'\n" "\$PREFIX"
    printf -- "  --nobundle           Do not create '%s' from package files\n" "\$DESTDIR/bundle.tar.xz"
    printf -- "  --nodeps             Do not build or bunble dependencies\n"
    printf -- "  --onlydeps           Build or bunble only dependencies, useful with --nomakepkg --nobundle\n"
    printf -- "  -h, --help           Show this help message and exit\n"
    printf -- "  -V, --version        Show version information and exit\n"
    echo
    printf -- "These options can be passed to %s:\n" "makepkg"
    echo
    printf -- "  --clean              Clean up work files after build\n"
    printf -- "  --cleanbuild         Remove %s dir before building the package\n" "\$package/\$srcdir/"
    printf -- "  -g, --geninteg       Generate integrity checks for source files (implies --noinstall --nobundle)\n"
    printf -- "  -o, --nobuild        Download and extract files only\n"
    printf -- "  -e, --noextract      Do not extract source files (use existing %s dir)\n" "\$package/\$srcdir/"
    printf -- "  -R, --repackage      Repackage contents of the package without rebuilding\n"
    printf -- "  -L, --log            Log package build process\n"
    printf -- "  --nocolor            Disable colorized output messages\n"
    echo
    printf -- "The following variables can be passed through environment:\n"
    echo
    printf -- "  DESTDIR              where to put the resulting bundle  [ \$CWD/artifacts-\$chost ]\n"
    printf -- "  PKGDEST              where all packages will be placed  [ \$DESTDIR/makepkg/pkg ]\n"
    printf -- "  SRCDEST              where source files will be cached  [ \$DESTDIR/makepkg/src ]\n"
    printf -- "  LOGDEST              where all log files will be placed [ \$DESTDIR/makepkg/log ]\n"
    printf -- "  BUILDDIR             where to run package compilation   [ \$DESTDIR/makepkg/build ]\n"
    printf -- "  CCACHE_DIR           where to keep ccache'd outputs     [ \$DESTDIR/ccache ]\n"
    echo
}

version() {
    printf "%s %s\n" "$0" "$prog_version"
    makepkg --version
}

if [[ $# -eq 0 ]]; then
    usage; exit -1
fi

MAKEPKG_CONF=
PKG_ROOT_DIR=

set_file_option() {
    local varname="$1" option="$2" value="$3"
    [[ -n "${value}" ]] || error "${option}: Missing option value"
    [[ -e "${value}" ]] || error "${value}: No such file or directory"

    eval "${varname}=\"\${value}\""
}

MAKEPKG_OPTS=(--force --noconfirm --skippgpcheck --nocheck --nodeps)

NOMAKEPKG=0
NOBUNDLE=0
NODEPS=0
ONLYDEPS=0
NOINSTALL=0
LOGGING=0

target_packages=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -P|--pkgroot)     set_file_option PKG_ROOT_DIR "$1" "$2"; shift ;;
        -P=*|--pkgroot=*) set_file_option PKG_ROOT_DIR "${1%%=*}" "${1#*=}" ;;

        -c|--config)      set_file_option MAKEPKG_CONF "$1" "$2"; shift ;;
        -c=*|--config=*)  set_file_option MAKEPKG_CONF "${1%%=*}" "${1#*=}" ;;

        # Makepkg Options
        --clean)          MAKEPKG_OPTS+=($1) ;;
        --cleanbuild)     MAKEPKG_OPTS+=($1) ;;
        -g|--geninteg)    MAKEPKG_OPTS+=($1); NOBUNDLE=1; NOINSTALL=1 ;;
        -o|--nobuild)     MAKEPKG_OPTS+=($1); ;;
        -e|--noextract)   MAKEPKG_OPTS+=($1) ;;
        -R|--repackage)   MAKEPKG_OPTS+=($1) ;;
        -L|--log)         MAKEPKG_OPTS+=($1); LOGGING=1 ;;
        --nocolor)        MAKEPKG_OPTS+=($1) ;;

        --nomakepkg)      NOMAKEPKG=1 ;;
        --noinstall)      NOINSTALL=1 ;;
        --nobundle)       NOBUNDLE=1 ;;
        --nodeps)         NODEPS=1 ;;
        --onlydeps)       ONLYDEPS=1 ;;

        -h|--help)        usage; exit 0 ;; # E_OK
        -V|--version)     version; exit 0 ;; # E_OK

        --)               OPT_IND=0; shift; break 2;;
        -*)               echo "${1}: Unknown option" >&2
                          echo; usage; exit -1 ;;
        *)                target_packages+=("$1") ;;
    esac
    shift
done

target_packages+=("$@")
for package in "${target_packages[@]}"; do
    _package_info "${package}"  # check package exists
done


is_target_package() {
    local target_package
    for target_package in "${target_packages[@]}"; do
        if [[ "${1}" == "${target_package}" ]]; then
            return 0  # true
        fi
    done
    return 1  # false
}

filter_out_target_packages() {
    local ret_packages=()
    local package
    for package in "$@"; do
        is_target_package "${package}" || ret_packages+=("${package}")
    done
    printf "%s\n" "${ret_packages[@]}"
}


PKG_ROOT_DIR="${PKG_ROOT_DIR:-$(pwd)}"
if [ ! -d "${PKG_ROOT_DIR}" ]; then
    error "${PKG_ROOT_DIR}: Directory doesn't exist"
fi
export PKG_ROOT_DIR=$(readlink -e "${PKG_ROOT_DIR}")

MAKEPKG_CONF="${MAKEPKG_CONF:-${PKG_ROOT_DIR}/makepkg.conf}"
if [ ! -f "${MAKEPKG_CONF}" ]; then
    error "${MAKEPKG_CONF}: File not found"
fi
export MAKEPKG_CONF=$(readlink -e "${MAKEPKG_CONF}")


source "${MAKEPKG_CONF}"

MAKEPKG_OPTS+=(--config "${MAKEPKG_CONF}")


[[ -n ${CHOST} ]] || CHOST=$(gcc -dumpmachine)
[[ "${CHOST}" == *-w64-mingw* ]] && ISMINGW=1 || ISMINGW=0

if [ ! -n "${PREFIX}" ]; then
    failure "${MAKEPKG_CONF}: Missing \$PREFIX variable definition"
fi
export PATH="$PATH:$PREFIX/bin"

# makepkg environmental variables
export DESTDIR=$(readlink -m ${DESTDIR:-artifacts-${CHOST}})
export PKGDEST=${PKGDEST:-${DESTDIR}/makepkg/pkg}      #-- Destination: where all packages will be placed
export SRCDEST=${SRCDEST:-${DESTDIR}/makepkg/src}      #-- Source cache: where source files will be cached
export LOGDEST=${LOGDEST:-${DESTDIR}/makepkg/log}      #-- Log files: where all log files will be placed
export BUILDDIR=${BUILDDIR:-${DESTDIR}/makepkg/build}  #-- Build tmp: where makepkg runs package build

export CCACHE_DIR=${CCACHE_DIR:-${DESTDIR}/ccache}     #-- where ccache will keep its cached compiler outputs

export CCACHE_BASEDIR=${BUILDDIR}
export CCACHE_COMPILERCHECK=content


BUNDLE_DIR="${DESTDIR}/bundle"
BUNDLE_TARBALL="${BUNDLE_DIR%%/}".tar.xz


[[ -n "${target_packages[*]}" ]] || failure 'No packages specified'
if (( ! NODEPS )); then
    define_build_order "${target_packages[@]}" || failure 'Could not determine build order'
    if (( ONLYDEPS )); then
        make_packages=($(filter_out_target_packages "${make_packages[@]}"))
        packages=($(filter_out_target_packages "${packages[@]}"))
    fi
else
    make_packages=("${target_packages[@]}")
    packages=("${target_packages[@]}")
fi

mkdir -p "${DESTDIR}" "${PKGDEST}" "${SRCDEST}" || failure "Couldn't create directories"
if (( LOGGING )); then
    mkdir -p "${LOGDEST}" || failure "Couldn't create directories"
fi

git_config user.name  "${GIT_COMMITTER_NAME}"
git_config user.email "${GIT_COMMITTER_EMAIL}"

export TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" INT QUIT TERM HUP EXIT

export PACMAN=false  # just to be sure makepkg won't call it

dependency_packages=($(filter_out_target_packages "${packages[@]}"))


do_build_install() {
    message "packages to build:" "${make_packages[@]}"

    local package

    for package in "${make_packages[@]}"; do
        if (( ! NOMAKEPKG )); then
            execute_cd "${PKG_ROOT_DIR}/${package}" 'makepkg' \
                makepkg "${MAKEPKG_OPTS[@]}" --config "${MAKEPKG_CONF}"
        fi

        if (( ! NOINSTALL )); then
            execute "install" \
                bsdtar -xvf "${PKGDEST}/$(pkgfilename)" -C / ${PREFIX#/}
        fi
    done
}


do_bundle() {
    message "target packages:" "${target_packages[@]}"

    local package binary

    if [[ -n ${dependency_packages[*]} ]]; then
        message "dependencies:" "${dependency_packages[@]}"

        for package in "${dependency_packages[@]}"; do
            execute "extract (dep)" \
                bsdtar -xvf "${PKGDEST}/$(pkgfilename)" ${PREFIX#/}
        done
        unset package

        message 'Removing dependency binaries...'
        [[ -d ${PREFIX#/}/bin ]] || continue

        find_and_rm -L ${PREFIX#/}/bin -xtype l

        while read -rd '' binary ; do
            case "$(file -bi "$binary")" in
                *text/x-shellscript*) ;;
                *)
                     if (( ISMINGW )) && [[ "$binary" != *.exe ]]; then
                         continue
                     fi
                     ;;
            esac
            rm -vf "$binary"
        done < <(find ${PREFIX#/}/bin ! -type d -print0)
        unset binary
    fi

    for package in "${target_packages[@]}"; do
        execute "extract" \
            bsdtar -xvf "${PKGDEST}/$(pkgfilename)" ${PREFIX#/}
    done
    unset package

    message 'Removing shared library symlinks...'
    [[ -d ${PREFIX#/}/lib ]] && find_and_rm -L ${PREFIX#/}/lib -xtype l

    message 'Removing doc and man directories...'
    rm -rvf "${DOC_DIRS[@]}" "${MAN_DIRS[@]}"

    message 'Removing l10n files...'
    rm -rvf ${PREFIX#/}/share/locale

    message 'Removing leftover development files...'
    find_and_rm  ${PREFIX#/} ! -type d -name "*.a"
    find_and_rm  ${PREFIX#/} ! -type d -name "*.la"
    rm -rvf ${PREFIX#/}/lib/pkgconfig
    rm -rvf ${PREFIX#/}/include

    # Remove empty directories
    find ${PREFIX#/} -depth -type d -exec rmdir '{}' \; 2>/dev/null

    execute "Archiving ${BUNDLE_TARBALL}" tar -Jcvf "${BUNDLE_TARBALL}" ${PREFIX#/}

    if [[ -n ${TEAMCITY_VERSION} ]]; then
        local pkgname pkgver
        local tgt_tags=()
        local dep_tags=()
        local all_tags=()
        for package in "${packages[@]}"; do
            _package_info "${package}" pkgname pkgver
            if is_target_package "${package}"; then
                tgt_tags=("${pkgname}-${pkgver}" "${tgt_tags[@]}")
            else
                dep_tags=("${pkgname}-${pkgver}" "${dep_tags[@]}")
            fi
            all_tags=("${pkgname}-${pkgver}" "${all_tags[@]}")
            teamcity setParameter name="'${TEAMCITY_PARAMETER_PREFIX}bundle.pkg.${pkgname}.pkgver'" value="'${pkgver}'"
        done
        teamcity setParameter name="'${TEAMCITY_PARAMETER_PREFIX}bundle.tags'" value="'${tgt_tags[@]}'"
        teamcity setParameter name="'${TEAMCITY_PARAMETER_PREFIX}bundle.tags.dep'" value="'${dep_tags[@]}'"
        teamcity setParameter name="'${TEAMCITY_PARAMETER_PREFIX}bundle.tags.all'" value="'${all_tags[@]}'"
    fi
}


# Build
execute 'build' do_build_install


if (( ! NOBUNDLE )); then
    rm -rf "${BUNDLE_DIR}" "${BUNDLE_TARBALL}"
    mkdir -p "${BUNDLE_DIR}"

    execute_cd "${BUNDLE_DIR}" 'bundle' do_bundle
    echo "${PREFIX}" > "${BUNDLE_DIR}/.prefix"
    ln -s "${PREFIX#/}" "${BUNDLE_DIR}/.sysroot"
fi

success 'All packages built successfully'
