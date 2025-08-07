# **GPU Workstation Setup Guide for Ubuntu Cinnamon**

This guide details how to install NVIDIA drivers and configure remote desktop software (NICE DCV, Parsec) on a server running a full desktop environment like Ubuntu Cinnamon 24.04.

## **Step 1: Install NVIDIA Drivers**

This process remains the same as before, but it is the essential first step.

1. **Update and Reboot:** Ensure your system is fully updated and reboot to apply any kernel changes.  
   sudo apt update && sudo apt upgrade \-y  
   sudo reboot

2. **Install Recommended Drivers:** After rebooting, use the ubuntu-drivers utility to automatically install the best driver for your GPU.  
   sudo ubuntu-drivers autoinstall

3. **Reboot Again:** A final reboot is required to load the newly installed NVIDIA driver.  
   sudo reboot

4. **Verify:** Log back in and run nvidia-smi. You should see your GPU details, confirming the driver is active.

## **Step 2: Configure NICE DCV (Console Session)**

Since we have a physical desktop session running, we will configure DCV to capture it directly instead of creating a separate virtual session.

1. **Install DCV Server:** Follow the standard installation process for the NICE DCV server as outlined previously.  
2. **Configure for Console Capture:** Open the DCV configuration file with a text editor:  
   sudo nano /etc/dcv/dcv.conf

3. Find the \[session-management/defaults\] section and add the following line to set the session type to console:  
   create-session \= true

4. Find the \[display\] section and specify the owner of the console session. This is typically the user you log in with. If you are using the root user for the desktop, set it to root.  
   owner \= "root"

   Save the file and exit the editor.  
5. **Restart the DCV Server:** Apply the new configuration by restarting the service.  
   sudo systemctl restart dcvserver

6. **Set a Password:** Ensure the user you specified as the owner has a password set.  
   sudo passwd root

You can now connect with your NICE DCV client. You will not need to specify a session ID; DCV will automatically connect you to the running Cinnamon desktop.

## **Step 3: Configure Parsec (Desktop Version)**

For a desktop environment, you should use the standard Parsec application, not the headless version.

1. **Download Parsec:** On the server (you can do this via an SSH terminal), use wget to download the standard Parsec .deb package for Ubuntu. You can get the link from the [Parsec downloads page](https://parsec.app/downloads).  
   wget https://builds.parsec.app/package/parsec-linux.deb

2. **Install the Package:** Use dpkg to install the application.  
   sudo dpkg \-i parsec-linux.deb

   If you encounter any dependency errors, run the following command to automatically fix them:  
   sudo apt \-f install

3. **Run Parsec:** You will need to run the Parsec application from within the desktop environment. You can do this by connecting via NICE DCV first, opening a terminal in your Cinnamon session, and running:  
   parsec

   The Parsec GUI will launch, and you can log in with your credentials just as you would on a local machine. Once logged in, the server will be available for connection from your other devices via the Parsec app.