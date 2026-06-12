# Firecracker

## Installation

*Tested on Ubuntu Desktop 26.04*

Update your linux system

`sudo apt update`
`sudo apt upgrade`

Install curl and bridge-utils

`sudo apt install -y curl bridge-utils`

Download firecracker

`curl -LO https://github.com/firecracker-microvm/firecracker/releases/download/v1.15.1/firecracker-v1.15.1-x86_64.tgz`

Extract it

`tar -xf firecracker-v1.15.1-x86_64.tgz`

CD into it

`cd release-v1.15.1-x86_64/`

Copy to /usr/local/bin/

`sudo cp firecracker-v1.15.1-x86_64 /usr/local/bin/firecracker`

Add the user running firecracker to the `kvm` group

`sudo usermod -aG kvm USERNAME`

If it was your user account log out and back in

## Testing

This section details testing firecracker with a standard Linux image.

run it (ideally in a new console window)

`sudo firecracker`

Check what it is listening on. Likely /run/firecracker.socket

In another console:

`sudo chmod 666 /run/firecracker.socket`

`curl -LO https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin`

You should have a 21MiB Linux kernel

Config files

Adjust path to vmlinux.bin as needed

```
boot.json 
{
    "kernel_image_path": "/home/ian/Code/vmlinux.bin",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
}

vm_config.json 
{
    "vcpu_count": 1,
    "mem_size_mib": 128
}

action.json 
{
    "action_type": "InstanceStart"
}
```

Set boot source

`curl --unix-socket /run/firecracker.socket -X PUT -d @boot.json http://localhost/boot-source`

or

`curl --unix-socket /run/firecracker.socket -i -X PUT 'http://localhost/boot-source' -H 'Content-Type: application/json' -d '{ "kernel_image_path": "/home/ian/Code/vmlinux.bin", "boot_args": "console=ttyS0 reboot=k panic=1 pci=off" }'`

Set machine config

`curl --unix-socket /run/firecracker.socket -X PUT -d @vm_config.json http://localhost/machine-config`

or

`curl --unix-socket /run/firecracker.socket -i -X PUT 'http://localhost/machine-config' -H 'Content-Type: application/json' -d '{ "vcpu_count": 1, "mem_size_mib": 128 }'`

Optional rootfs

`curl --unix-socket /run/firecracker.socket -i -X PUT 'http://localhost/drives/rootfs' -H 'Content-Type: application/json' -d '{ "drive_id": "rootfs", "path_on_host": "./rootfs.ext4", "is_root_device": true, "is_read_only": false }'`

Start it

`curl --unix-socket /run/firecracker.socket -X PUT -d @action.json http://localhost/actions`

or 

`curl --unix-socket /run/firecracker.socket -i -X PUT 'http://localhost/actions' -H 'Content-Type: application/json' -d '{ "action_type": "InstanceStart" }'`

Check the terminal where you started firecracker. The linux kernel should have started and stopped due to a missing rootfs.

Clear out the old socket

`sudo rm /run/firecracker.socket`


Production Notes for Linux:

`nomodule` - Disable linux kernel module loading - Doesn't really apply here
`8250.nr_uarts=0` - Disable serial input/output - We interact via network only
`i8042.noaux i8042.nomux i8042.dumbkbd` - Minimal keyboard
`pci=off` - This is default but we don't use PCI here

None of these apply to BareMetal
