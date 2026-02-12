This is an install script to quickly retore my setup on NixOS.

Instructions:

1. Use the graphical installer to install NixOs
    - https://nixos.org/download/
    - Set the user to `gusjengis`
    - Use the same password for both the user and root
    - Choose the "No Desktop" option

2. After booting:
    - Login as `gusjengis`
    - Use nmtui to connect to the network
    - Run the following command:
    ```
    curl -fsSL https://raw.githubusercontent.com/gusjengis/nix-install-script/main/bootstrap-fresh-nixos.sh | bash -s -- gusjengis
    ```

3. After the script finishes, reboot the system. You should boot straight into the desktop.
4. Open the terminal with SUPER+T
5. Run ```gh auth login``` to authenticate git with GitHub   
6. Run ```sync``` to pull all missing repos 
7. Reboot and get to work!
