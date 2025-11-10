# Plex Server Monitor

A robust monitoring solution for Plex Media Server on macOS that provides automated server monitoring, recovery, and event logging through Airtable. Features intelligent update detection, conservative reboot cycles, comprehensive error handling, and remote deployment capabilities.

## 🌟 Key Features

- **🔄 Continuous Monitoring** - Real-time Plex Media Server health checks every 5 minutes
- **🧠 Smart Update Detection** - Automatically pauses monitoring during Plex updates
- **🌐 Network Recovery** - Multi-stage network connectivity restoration (soft reset → DNS flush → hard reset)
- **⚡ Daily Speed Testing** - Tracks network performance at 2am EST with intelligent retry logic
- **🔒 Security Focused** - Minimal permissions, passwordless sudo only for required operations
- **🛡️ Hardware Protection** - Conservative reboot limits (maximum 1 per day)
- **📊 Comprehensive Logging** - Local log files + Airtable integration for notifications
- **✅ Success Notifications** - Know when issues are automatically resolved
- **🎬 Stream-Aware** - Never interrupts active Plex streams during speed tests
- **🚀 Auto-Deployment** - Update from anywhere without SSH access

## 🚀 Auto-Deployment System

**Update your monitor from anywhere without SSH access!**

The auto-deployment system automatically checks GitHub for updates every 60 seconds and deploys them to your Mac. This means you can:

- Edit scripts on GitHub from any device (laptop, phone, tablet)
- Push changes and have them deploy automatically within 1 minute
- No SSH or remote access required
- View deployment logs to confirm updates

**How it works:**
1. You push changes to GitHub
2. Auto-deploy script checks for updates every 60 seconds
3. If updates found, it pulls them and deploys automatically
4. Monitor service restarts with new code
5. Logs confirm successful deployment

**What gets auto-deployed:**
- ✅ `scripts/plex_monitor.sh` - Main monitoring script
- ❌ Config files (plist, env) - Must be manually updated for safety

## 📋 Quick Start

### Prerequisites

- macOS (tested on macOS 12+)
- Plex Media Server installed and configured
- Administrative access
- Airtable account (for notifications)
- Python 3 with pip (for network speed testing)

### Installation

1. **Clone this repository**
```bash
   git clone git@github.com:darrenchilton/plex_monitor.git
   cd plex_monitor
```

2. **Copy monitoring script**
```bash
   sudo cp scripts/plex_monitor.sh /Users/plex/
   sudo chown plex:staff /Users/plex/plex_monitor.sh
   sudo chmod 755 /Users/plex/plex_monitor.sh
```

3. **Install LaunchDaemon**
```bash
   sudo cp config/com.user.plexmonitor.plist /Library/LaunchDaemons/
   sudo chown root:wheel /Library/LaunchDaemons/com.user.plexmonitor.plist
   sudo chmod 644 /Library/LaunchDaemons/com.user.plexmonitor.plist
```

4. **Configure environment variables**
```bash
   # Copy template
   sudo -u plex cp config/.plex_monitor_env.example /Users/plex/.plex_monitor_env
   
   # Edit with your actual tokens
   sudo -u plex nano /Users/plex/.plex_monitor_env
   
   # Secure the file
   sudo -u plex chmod 600 /Users/plex/.plex_monitor_env
```

5. **Set up passwordless sudo** (Required for network recovery)
```bash
   sudo visudo -f /etc/sudoers.d/plex-monitor
```
   
   Add these lines (press `i` to insert, `Esc` then `:wq` to save):
```
   plex ALL=(ALL) NOPASSWD: /usr/sbin/networksetup
   plex ALL=(ALL) NOPASSWD: /sbin/ifconfig
   plex ALL=(ALL) NOPASSWD: /usr/bin/dscacheutil
   plex ALL=(ALL) NOPASSWD: /usr/bin/killall
   plex ALL=(ALL) NOPASSWD: /sbin/shutdown
   plex ALL=(ALL) NOPASSWD: /bin/mkdir
   plex ALL=(ALL) NOPASSWD: /usr/sbin/chown
   plex ALL=(ALL) NOPASSWD: /bin/chmod
   plex ALL=(ALL) NOPASSWD: /usr/bin/touch
   plex ALL=(ALL) NOPASSWD: /bin/launchctl
```

6. **Install speedtest-cli**
```bash
   python3 -m pip install speedtest-cli --user
   sudo ln -s /Users/plex/Library/Python/3.*/bin/speedtest-cli /usr/local/bin/speedtest-cli
   speedtest-cli --version  # Verify installation
```

7. **Start the monitor**
```bash
   sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.plist
```

8. **Install Auto-Deployment System** (Optional but Recommended)
```bash
   # Copy auto-deploy script
   chmod +x ~/plex_monitor/scripts/auto_deploy.sh
   
   # Install auto-deploy LaunchDaemon
   sudo cp ~/plex_monitor/config/com.user.plexmonitor.autodeploy.plist /Library/LaunchDaemons/
   sudo chown root:wheel /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist
   sudo chmod 644 /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist
   
   # Start auto-deployment
   sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist
```

   Verify it's running:
```bash
   sudo launchctl list | grep autodeploy
   tail /Users/plex/Library/Logs/auto_deploy.log
```

## 🌐 Remote Update Workflow

With auto-deployment enabled, you can update your monitor from anywhere:

### From GitHub Web Interface:

1. Go to https://github.com/darrenchilton/plex_monitor
2. Navigate to `scripts/plex_monitor.sh`
3. Click the pencil icon (Edit this file)
4. Make your changes
5. Scroll down and commit: "Description of changes"
6. Wait up to 60 seconds for automatic deployment

### From Any Computer:
```bash
# Clone or update your local copy
git clone git@github.com:darrenchilton/plex_monitor.git
cd plex_monitor

# Make changes
nano scripts/plex_monitor.sh

# Commit and push
git add scripts/plex_monitor.sh
git commit -m "Description of changes"
git push
```

### Verify Deployment:

Check the auto-deploy log on your Mac:
```bash
tail /Users/plex/Library/Logs/auto_deploy.log
```

You should see:
```
[2025-11-10 12:03:07] Updates detected! Local: abc1234, Remote: def5678
[2025-11-10 12:03:07] Successfully pulled changes from GitHub
[2025-11-10 12:03:07] Stopping plex_monitor service...
[2025-11-10 12:03:07] Script deployed successfully
[2025-11-10 12:03:07] Starting plex_monitor service...
[2025-11-10 12:03:07] Service restarted successfully
[2025-11-10 12:03:07] Deployment complete! Commit: def5678
```

### Manual Trigger (Optional):

Don't want to wait 60 seconds? Trigger deployment immediately via SSH:
```bash
ssh plex@your-mac-address
sudo launchctl start com.user.plexmonitor.autodeploy
```

## 🎯 Conservative Design Philosophy

This monitor prioritizes hardware longevity and system stability over aggressive recovery attempts.

### Reboot Strategy

| Feature | Setting | Purpose |
|---------|---------|---------|
| **Maximum Reboots** | 1 per day | Protects hardware from excessive cycling |
| **Reboot Delay** | 24 hours | Prevents rapid reboot loops |
| **Daily Reset** | Midnight | Fresh cycle each day |
| **Speed Tests** | 2am EST | Minimizes streaming impact |
| **Stream Detection** | Auto-delay | Never interrupts active viewing |

### Example: 4-Day Network Outage

- **Day 1**: 1 reboot → 24hr wait → 1 reboot → wait until next day
- **Day 2**: Reset → 1 reboot → 24hr wait → 1 reboot → wait
- **Day 3**: Reset → 1 reboot → 24hr wait → 1 reboot → wait
- **Day 4**: Reset → 1 reboot → 24hr wait → 1 reboot

**Result**: ~6-8 reboots over 4 days (vs. potentially hundreds with aggressive settings)

## 📊 Monitoring & Notifications

### What Gets Logged to Airtable

The monitor sends notifications for:

**Plex Server Events:**
- Plex restart attempts
- ✅ Plex restart successes
- Plex update detection

**Network Events:**
- Network restart attempts
- ✅ Network restoration (soft reset/DNS flush/hard reset)
- Network speed test results

**System Events:**
- System reboot notifications
- Reboot cycle status updates

**Note**: You receive BOTH alert notifications when issues are detected AND success notifications when they're resolved automatically.

### Local Log Files

- `/Users/plex/Library/Logs/plex_monitor.log` - Main activity log
- `/Users/plex/Library/Logs/network_speeds.log` - Speed test history
- `/Users/plex/Library/Logs/plex_monitor_error.log` - Error details
- `/Users/plex/Library/Logs/airtable_queue.json` - Offline event queue
- `/Users/plex/Library/Logs/reboot_history.json` - Reboot cycle tracking
- `/Users/plex/Library/Logs/speed_test_history.json` - Speed test attempts
- `/Users/plex/Library/Logs/auto_deploy.log` - Auto-deployment history
- `/Users/plex/Library/Logs/auto_deploy_error.log` - Auto-deployment errors

## ⚙️ Configuration

### Main Settings (in `scripts/plex_monitor.sh`)
```bash
CHECK_INTERVAL=300               # Check frequency (5 minutes)
MAX_RETRIES=2                   # Max Plex restart attempts
NETWORK_RESTART_ATTEMPTS=3      # Max network restart attempts
MAX_REBOOT_ATTEMPTS=1          # Max reboots per cycle
REBOOT_CYCLE_PAUSE=86400       # 24 hours between cycles
SPEED_TEST_HOUR=2              # Run speed test at 2am
SPEED_TEST_TIMEZONE='America/New_York'  # EST
```

### Network Test Endpoints
```bash
NETWORK_TEST_ENDPOINTS=(
    "1.1.1.1"         # Cloudflare
    "8.8.8.8"         # Google
    "208.67.222.222"  # OpenDNS
    "9.9.9.9"         # Quad9
)
```

### Auto-Deploy Settings (in `config/com.user.plexmonitor.autodeploy.plist`)
```xml
<key>StartInterval</key>
<integer>60</integer>              <!-- Check GitHub every 60 seconds -->
```

**Adjusting the check interval:**
- `60` - Default (1 minute) - Good balance for most users
- `10` - Fast updates (10 seconds) - Best for active development/testing
- `300` - Conservative (5 minutes) - Lower overhead if updates are rare

**To change the interval:**
1. Edit the plist file on GitHub or locally
2. Copy to `/Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist`
3. Reload: `sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist && sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist`

**Important:** Changes to plist files, environment files, or sudoers configuration are NOT auto-deployed for security. These must be manually updated.

## 🔧 Basic Commands

### Monitor Commands
```bash
# Check if monitor is running
sudo launchctl list | grep plexmonitor
ps aux | grep plex_monitor

# View recent activity
tail -20 /Users/plex/Library/Logs/plex_monitor.log

# Monitor in real-time
tail -f /Users/plex/Library/Logs/plex_monitor.log

# View speed test results
tail -10 /Users/plex/Library/Logs/network_speeds.log

# Stop monitoring
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.plist

# Start monitoring
sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.plist

# Restart monitoring
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.plist
sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.plist
```

### Auto-Deployment Commands
```bash
# Check if auto-deploy is running
sudo launchctl list | grep autodeploy

# View deployment history
tail -20 /Users/plex/Library/Logs/auto_deploy.log

# View only successful deployments
grep "Deployment complete" /Users/plex/Library/Logs/auto_deploy.log

# Manually trigger deployment check
sudo launchctl start com.user.plexmonitor.autodeploy

# Stop auto-deployment
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist

# Restart auto-deployment
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist
sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.autodeploy.plist
```

## 🔐 Security

- **Environment Files**: Secured with 600 permissions (user read/write only)
- **Passwordless Sudo**: Restricted to specific binaries only
- **No Hardcoded Secrets**: All tokens stored in separate environment file
- **API Rate Limiting**: All external calls are rate-limited
- **Minimal Permissions**: Script runs with least privilege required
- **Auto-Deploy Safety**: Only deploys main script, not config files

## 🐛 Troubleshooting

### Script Not Starting
```bash
# Check if running
ps aux | grep plex_monitor

# Check LaunchDaemon status
sudo launchctl list | grep plexmonitor

# Verify permissions
ls -l /Users/plex/plex_monitor.sh
ls -l /Library/LaunchDaemons/com.user.plexmonitor.plist
```

### Permission Errors
```bash
# Verify sudoers file exists
sudo cat /etc/sudoers.d/plex-monitor

# Test sudo without password
sudo -u plex sudo -n /usr/sbin/networksetup -listallnetworkservices

# If it asks for password, sudoers file needs to be reconfigured
```

### Speed Test Issues
```bash
# Test speedtest-cli manually
speedtest-cli --simple

# Check speed test history
cat /Users/plex/Library/Logs/speed_test_history.json

# Verify installation
which speedtest-cli
speedtest-cli --version
```

### Network Recovery Issues
```bash
# Check network interface
ifconfig en0

# Test connectivity manually
ping -c 3 8.8.8.8

# View reboot history
cat /Users/plex/Library/Logs/reboot_history.json
```

### Auto-Deployment Issues
```bash
# Check if auto-deploy is running
sudo launchctl list | grep autodeploy
# Should show: -	0	com.user.plexmonitor.autodeploy

# View recent deployment attempts
tail -20 /Users/plex/Library/Logs/auto_deploy.log

# Check for errors
cat /Users/plex/Library/Logs/auto_deploy_error.log

# Test manually
bash /Users/plex/plex_monitor/scripts/auto_deploy.sh

# Verify git is accessible
cd ~/plex_monitor && git status
```

**Common Auto-Deploy Issues:**

**Auto-deploy not detecting changes:**
- Check that you pushed to the `main` branch
- Verify the script can access GitHub: `cd ~/plex_monitor && git fetch`
- Check the interval setting in the plist file

**Permission errors in deployment log:**
- Verify sudoers includes `/bin/launchctl`: `sudo cat /etc/sudoers | grep launchctl`
- Ensure the plex user has permissions: `ls -la /Users/plex/plex_monitor.sh`

**Deployments succeeding but changes not taking effect:**
- Verify the monitor service restarted: `ps aux | grep plex_monitor`
- Check that the production script was updated: `ls -la /Users/plex/plex_monitor.sh`
- View the monitor's main log: `tail /Users/plex/Library/Logs/plex_monitor.log`

### Emergency: Stop Excessive API Calls
```bash
# Stop monitor immediately
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.plist

# Clear event queue
echo "[]" | sudo tee /Users/plex/Library/Logs/airtable_queue.json

# Reset reboot history
echo '{"last_reboot": null, "attempts": 0, "cycle": 1, "last_cycle_start": null}' | sudo tee /Users/plex/Library/Logs/reboot_history.json
```

## 📈 Performance Impact

The conservative settings minimize system impact:

- **Network checks**: Every 5 minutes
- **Plex restarts**: Only when Plex is actually down
- **System reboots**: Maximum 2 per day during extended outages
- **API calls**: Batched and queued to reduce load
- **Speed tests**: Once per day (or less if streams active)
- **Speed test duration**: 30-45 seconds per test
- **Speed test bandwidth**: ~100-200 MB per test
- **Auto-deploy checks**: Every 60 seconds (minimal overhead)

## 🛡️ Hardware Protection

This version is designed to protect your Mac hardware:

- **Minimal reboots**: 1 per day maximum during outages
- **24-hour delays**: Prevents rapid cycling
- **Update awareness**: Won't interfere with Plex updates
- **Conservative approach**: Prioritizes hardware longevity
- **Stream-aware**: Never impacts active streaming

## 🔄 Version History

- **v3.2** (2025-11) - Added auto-deployment system for remote updates
- **v3.1** (2025-11) - Added success notifications for network recoveries
- **v3.0** (2025-11) - Added daily network speed testing with intelligent retry logic
- **v2.0** (2025) - Conservative reboot implementation (1/day max, 24hr delays)
- **v1.0** (2024) - Initial release

## 🤝 Contributing

Improvements are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on your system
5. Submit a pull request with detailed description

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

## 💡 Tips

- Set up Airtable → Slack integration for instant mobile notifications
- **Enable auto-deployment for remote updates without SSH**
- Review logs weekly to identify patterns
- **Check auto-deploy logs after pushing changes to confirm deployment**
- Rotate API tokens quarterly for security
- Keep backups of your configuration files
- Test changes in isolation before deploying
- **For active development, reduce auto-deploy interval to 10 seconds**

## 📞 Support

For issues:
1. Check the error log: `tail -20 /Users/plex/Library/Logs/plex_monitor_error.log`
2. Check auto-deploy log: `tail -20 /Users/plex/Library/Logs/auto_deploy.log`
3. Verify permissions are correct
4. Ensure tokens are valid in `/Users/plex/.plex_monitor_env`
5. Test network connectivity manually
6. Review the troubleshooting section above

---

**Repository**: https://github.com/darrenchilton/plex_monitor  
**Status**: Production-ready, actively maintained  
**Last Updated**: November 2025
