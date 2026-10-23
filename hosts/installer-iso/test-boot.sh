#!/usr/bin/env bash
# Run on a disposable Linux runner with QEMU, OVMF and sshpass. No target disk.
set -euo pipefail
iso=$1
output=$2
mkdir -p "$output"
output=$(realpath "$output")
firmware=$(find /usr/share/OVMF -maxdepth 1 -name OVMF_CODE_4M.fd -print -quit)
test -n "$firmware"
accel=tcg
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then accel=kvm; fi
qemu-system-x86_64 \
  -machine q35,accel="$accel" -cpu max -m 4096 -smp 2 \
  -bios "$firmware" -cdrom "$iso" -boot d \
  -device virtio-vga -display none \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
  -serial "file:$output/serial.log" \
  -monitor "unix:$output/monitor.sock,server=on,wait=off" \
  >"$output/qemu.log" 2>&1 &
vm_pid=$!
trap 'kill "$vm_pid" 2>/dev/null || true; wait "$vm_pid" 2>/dev/null || true' EXIT
remote=(sshpass -p zenos ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 -p 2222 zenos@127.0.0.1)
ready=false
for _ in $(seq 1 180); do
  kill -0 "$vm_pid"
  if "${remote[@]}" true 2>/dev/null; then ready=true; break; fi
  sleep 2
done
if [ "$ready" != true ]; then cat "$output/qemu.log"; tail -80 "$output/serial.log"; exit 1; fi
status=1
for _ in $(seq 1 90); do
  if "${remote[@]}" 'systemctl is-active greetd && XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemctl --user is-active org.gnome.Shell@zenos-oobe.service zenos-setup.service' >"$output/services.log" 2>&1; then
    status=0
    break
  fi
  sleep 2
done
"${remote[@]}" 'sudo journalctl -b --no-pager -n 300' >"$output/journal.log" 2>&1 || true
python3 - "$output" <<'PY'
from pathlib import Path
import socket,sys,time
root=Path(sys.argv[1])
with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as monitor:
    monitor.connect(str(root/'monitor.sock'))
    monitor.sendall(f'screendump {root}/screen.ppm\n'.encode())
    time.sleep(1)
# QEMU PPM is sufficient for visual review; do not download the ISO again.
(root/'monitor.sock').unlink(missing_ok=True)
PY
cat "$output/services.log"
exit "$status"
