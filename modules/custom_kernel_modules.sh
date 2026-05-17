#!/bin/bash
# =============================================================================
# custom_kernel_modules.sh — Monitor loaded kernel modules
#
# Why: Rootkits and malware often load kernel modules for persistence.
#      Unknown modules appearing in the Git diff are a strong warning signal.
# =============================================================================

collect_custom_kernel_modules() {
    local entries=""

    # Known legitimate modules (base whitelist)
    local -A KNOWN_MODULES
    while IFS= read -r mod; do
        KNOWN_MODULES["$mod"]="known"
    done < <(cat << 'KNOWN'
af_packet
autofs4
bpf
bridge
br_netfilter
btrfs
cfg80211
cifs
coretemp
cpuid
crct10dif_pclmul
cryptd
ctr
dax
dm_mod
drm
e1000
e1000e
ebtables
ext4
fuse
hid
hid_generic
input_leds
intel_rapl_msr
ip6_tables
ip6table_filter
ip_tables
iptable_filter
iptable_nat
iptable_raw
isofs
jbd2
kvm
kvm_amd
kvm_intel
libata
loop
lz4
lz4_compress
mac_hid
md_mod
mptcp_diag
nf_conntrack
nf_defrag_ipv4
nf_defrag_ipv6
nf_nat
nfnetlink
nfs
nfsv4
nls_utf8
nvme
nvme_core
overlay
psmouse
sch_fq_codel
serio_raw
sg
snd
tcp_bbr
tls
udf
usbhid
veth
video
virtio
virtio_balloon
virtio_blk
virtio_net
virtio_pci
virtio_ring
vmw_balloon
vmwgfx
vxlan
xfs
xt_MASQUERADE
xt_addrtype
xt_comment
xt_conntrack
xt_mark
xt_multiport
xt_nat
xt_tcpudp
zram
KNOWN
)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name size used_by
        name=$(echo "$line"    | awk '{print $1}')
        size=$(echo "$line"    | awk '{print $2}')
        used_by=$(echo "$line" | awk '{print $4}' | tr ',' ' ' | xargs)

        local known="false"
        [[ -n "${KNOWN_MODULES[$name]+x}" ]] && known="true"

        local e
        e="{\"name\":\"$(json_escape "$name")\","
        e+="\"size\":$size,"
        e+="\"used_by\":\"$(json_escape "$used_by")\","
        e+="\"known\":$known}"
        entries=$(append_entry "$entries" "$e")
    done < <(lsmod 2>/dev/null | tail -n +2 | sort -k1)

    wrap_array "$entries"
}
