This is an install script to quickly retore my setup on NixOS. It assumes you've just done a fresh, no desktop install, using the graphical installer iso. I haven't tested it with other setups.

Instructions:

1. Use the graphical installer to install NixOs
    - https://nixos.org/download/
    - Set the name to `Anthony Green`
    - Set the user to `gusjengis`
    - Use the same password for both the user and root
    - Choose the "No Desktop" option

2. After booting:
    - Login as `gusjengis`
    - Use nmtui to connect to the network
    - Run the following command:
    ```
    curl -fsSL https://raw.githubusercontent.com/gusjengis/nix-install-script/main/install.sh | bash -s -- gusjengis
    ```
    - Select the modules you want to enable in the prompts

3. After the script finishes, reboot the system. You should boot straight into the desktop. Or just a TTY depending on the selected modules.
4. If not in TTY, open the terminal with SUPER+T
5. Run ```gh auth login``` to authenticate git with GitHub   
6. Run ```sync``` to pull all missing repos 
7. Reboot and get to work!

P.S. Don't forget to set a name in the tailscale dashboard! And you still need to sign in to stuff.
