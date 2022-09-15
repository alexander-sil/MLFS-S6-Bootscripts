#! /bin/sh

. /etc/s6/dash-scripts/common_funcs.sh 
. /etc/s6/s6.conf

CGROUP_OPTS=nodev,noexec,nosuid

#if [ $CGROUP_CONTROLLERS = "none" ]; then
#    CGROUP_CONTROLLERS=""
#fi

cgroup2_find_path() {
    if grep -qw cgroup2 /proc/filesystems; then
        case "${CGROUP_MODE}" in
            hybrid) printf "/sys/fs/cgroup/unified" ;;
            unified) printf "/sys/fs/cgroup" ;;
        esac
    fi
    return 0
}

cgroup1_base() {
    grep -qw cgroup /proc/filesystems || return 0
    if ! mountpoint -q /sys/fs/cgroup; then
        local opts="${CGROUP_OPTS},mode=755,size=${rc_cgroupsize:-10m}"
        mount -n -t tmpfs -o "${opts}" cgroup_root /sys/fs/cgroup
    fi

    if ! mountpoint -q /sys/fs/cgroup/openrc; then
        local agent="/etc/s6/sv/mount-cgroups/cgroup-release-agent.sh"
        mkdir /sys/fs/cgroup/openrc
        mount -n -t cgroup -o none,${CGROUP_OPTS},name=openrc,release_agent="$agent" openrc /sys/fs/cgroup/openrc
        printf 1 > /sys/fs/cgroup/openrc/notify_on_release
    fi
    return 0
}

cgroup1_controllers() {
    ${HAVE_CONTROLLER1_GROUPS} && [ -e /proc/cgroups ]  && grep -qw cgroup /proc/filesystems || return 0
    while read -r name _ _ enabled _; do
        case "${enabled}" in
            1)  if mountpoint -q "/sys/fs/cgroup/${name}";then continue;fi
                local x
                for x in $CGROUP_CONTROLLERS; do
                    [ "${name}" = "blkio" ] && [ "${x}" = "io" ] &&
                        continue 2
                    [ "${name}" = "${x}" ] &&
                    continue 2
                done
                mkdir "/sys/fs/cgroup/${name}"
                mount -n -t cgroup -o "${CGROUP_OPTS},${name}" "${name}" "/sys/fs/cgroup/${name}"
            ;;
        esac
    done < /proc/cgroups
    return 0
}

cgroup2_base() {
    grep -qw cgroup2 /proc/filesystems || return 0
    local base
    base="$(cgroup2_find_path)"
    mkdir -p "${base}"
    mount -t cgroup2 none -o "${CGROUP_OPTS},nsdelegate" "${base}" 2> /dev/null ||
        mount -t cgroup2 none -o "${CGROUP_OPTS}" "${base}"
    return 0
}

cgroup2_controllers() {
    grep -qw cgroup2 /proc/filesystems || return 0
    local active cgroup_path x y
    cgroup_path="$(cgroup2_find_path)"
    [ -z "${cgroup_path}" ] && return 0
    [ -e "${cgroup_path}/cgroup.controllers" ] && read -r active < "${cgroup_path}/cgroup.controllers"
    for x in ${CGROUP_CONTROLLERS}; do
        for y in ${active}; do
            [ "$x" = "$y" ] && [ -e "${cgroup_path}/cgroup.subtree_control" ] &&
            echo "+${x}"  > "${cgroup_path}/cgroup.subtree_control"
        done
    done
    return 0
}

cgroups_hybrid() {
    cgroup1_base
    cgroup2_base
    cgroup2_controllers
    cgroup1_controllers
    return 0
}

cgroups_legacy() {
    cgroup1_base
    cgroup1_controllers
    return 0
}

cgroups_unified() {
    cgroup2_base
    cgroup2_controllers
    return 0
}

mount_cgroups() {
    case "${CGROUP_MODE}" in
        hybrid) cgroups_hybrid 
		dbg "cgroups mode is hybrid. \n" 
		;;
        legacy) cgroups_legacy 
		dbg "cgroups mode is legacy. \n"
		;;
        unified) cgroups_unified 
		dbg "cgroups modeis unified. \n"
		;;
    esac
    return 0
}

mount_cgs() {
    if [ -d /sys/fs/cgroup ];then
	msg "Mounting cgroups... \n"
        mount_cgroups
        return 0
    fi
    return 1
}

mount_cgs
