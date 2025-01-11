# fcos-helper

# Purpose
This script was created to help ease the installation process of Fedora CoreOS. It is designed to be used on the Fedora CoreOS live DVD where it will download `butane` from (here)[https://github.com/coreos/butane] and convert your butane configuration you pass to it via an HTTPS link or a full path. This script also features a way to edit the admin username (if desired), the password hash (if present), and the SSH public key in the butane configuration file (for if you want to use an existing configuration file you did not write yourself). This allows you to use your own password and SSH public key values instead of those provided by the author.

You can learn more about the butane specification and how to write a butane configuration [here](https://coreos.github.io/butane/specs/) and you can learn more about Fedora CoreOS [here](https://docs.fedoraproject.org/en-US/fedora-coreos/).


# How To Use
This script is designed to be used on the live DVD, so after you have booted the live DVD you can get this script by doing:
```
curl -LO https://raw.githubusercontent.com/topaz8/fcos-helper/refs/heads/main/fcos-helper.sh
chmod +x fcos-helper.sh
```

Read through the available flags:
```
./fcos-helper.sh -h
```

> [!NOTE]
> the `-b` flag is required as it is the way you tell the script where your butane configuration file is.
> `-b` takes either an HTTPS link or a full path (such as if you have the configuration file on a USB). Relative paths are not yet supported.

To convert an existing butane configuration without modifying it you can use the `-n` flag:
```
./fcos-helper.sh -n -b <config source>
```

To edit either the admin username (default is 'core') and/or the SSH public key you use the `-u` and `-k` flags respectively. If a password_hash directive is found in the configuration file, it will be edited.
```
./fcos-helper.sh -b <config source> -u <admin username> -k "pubkey"
```

> [!NOTE]
> You can provide your SSH public key in a few different ways. Either with the environment variable `USER_SSH_KEY`, by using `-k`, or it will be read interactively. `-k` can take the public key string literally or you can use the output from a subshell e.g. `-k "$(cat key)"` for if you have your SSH public key stored on a USB drive.
