#!/bin/bash
# system-anv.sh - sourced by install.sh, uninstall.sh, enable.sh, disable.sh and tools/session-check.sh.
#
# "System mode": the distribution's own Mesa is built with patches/mesa-26.3 (Anatase does this through
# oxp3-anatase-fixes). Then every Vulkan program already runs the patched ANV, so the package's own
# drivers, the ICD wrapper and VK_DRIVER_FILES are not needed - only the variables below. That is also
# the only way the patched driver reaches games under a Flatpak Steam: Flatpak drops VK_DRIVER_FILES
# from the environment it passes in, and pressure-vessel takes the graphics drivers from the Flatpak
# runtime.
#
# Anatase's Steam is the Flatpak org.anatase.Steam; its runtime (org.anatase.Platform) is the host's /usr
# plus overrides, and it shares the home directory, so the package folder and its compiler are reachable
# from the game's container.

# path of the host's 64-bit ANV if it carries the CM kernel injection, else nothing
xmx_system_anv() {
  local l
  for l in /usr/lib64/libvulkan_intel.so /usr/lib/x86_64-linux-gnu/libvulkan_intel.so /usr/lib/libvulkan_intel.so; do
    [ -f "$l" ] && grep -aq 'ANV_CM_HELPER' "$l" && { printf '%s\n' "$l"; return 0; }
  done
  return 1
}

# the Flatpak Steam whose runtime can carry the system's Mesa (Anatase), if installed
xmx_flatpak_steam() {
  command -v flatpak >/dev/null 2>&1 || return 1
  flatpak info org.anatase.Steam >/dev/null 2>&1 && { echo org.anatase.Steam; return 0; }
  return 1
}

# 64-bit ANV that games under that Flatpak Steam load (its runtime's), if it can be found
xmx_flatpak_anv() {
  local app=$1 rt loc
  rt=$(flatpak info --show-runtime "$app" 2>/dev/null) || return 1
  loc=$(flatpak info --show-location "$rt" 2>/dev/null) || return 1
  [ -f "$loc/files/lib64/libvulkan_intel.so" ] && printf '%s\n' "$loc/files/lib64/libvulkan_intel.so"
}

# variables a game needs in system mode (KEY=VALUE per line). No ANV_CM_KERNEL_DIR: with a helper the
# driver compiles at run time, and the kernel folder would make it look up every compute shader there.
xmx_system_env() { # <package dir>
  echo "ANV_CM_HELPER=$1/tools/cm-compile.sh"
  # the kernel binding code needs vkd3d-proton's classic descriptor heap (descriptor_heap is opt-in today)
  echo "VKD3D_DISABLE_EXTENSIONS=VK_EXT_descriptor_buffer,VK_EXT_descriptor_heap"
  # Mesa hides the Intel vendor id from some games (force_vk_vendor=-1 profiles), which keeps XeSS on DP4a
  echo "force_vk_vendor=0"
}
XMX_ENV_KEYS="VK_DRIVER_FILES VKD3D_DISABLE_EXTENSIONS ANV_CM_KERNEL_DIR ANV_CM_HELPER force_vk_vendor"

# Flatpak overrides file of an app for the user
xmx_flatpak_override_file() { echo "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/overrides/$1"; }

# remove our variables from the app's user overrides (other overrides stay)
xmx_flatpak_env_clear() { # <app>
  local f k; f=$(xmx_flatpak_override_file "$1")
  [ -f "$f" ] || return 0
  for k in $XMX_ENV_KEYS; do sed -i "/^$k=/d" "$f"; done
}

# the prefix's igd_faux driver store folders (Proton creates DriverStore/FileRepository, older setups
# have it in lower case)
xmx_driverstores() { # <prefix root (the folder with drive_c)>
  local d
  for d in "$1"/drive_c/windows/system32/{driverstore,DriverStore}/{filerepository,FileRepository}/igd_faux.inf_1; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
}
# the folder enable.sh should use for a prefix: an existing one, else Proton's spelling
xmx_driverstore_for() { # <prefix root>
  local d; d=$(xmx_driverstores "$1" | head -1)
  printf '%s\n' "${d:-$1/drive_c/windows/system32/DriverStore/FileRepository/igd_faux.inf_1}"
}
