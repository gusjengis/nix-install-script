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

3. After the script finishes, reboot the system
4. After reboot use ```gh auth login``` to authenticate git with GitHub   
5. Run ```sync``` to pull any private repos that would have failed during the earlier script
6. Reboot and get to work!
